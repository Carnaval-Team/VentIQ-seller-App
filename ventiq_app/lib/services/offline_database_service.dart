import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Almacenamiento offline basado en SQLite.
///
/// Sustituye el JSON monolítico `offline_data` de SharedPreferences.
/// - Secciones pequeñas/medias: tabla `offline_sections` (key → JSON).
/// - Productos: tabla `offline_products` indexada (búsqueda parcial).
/// - Categorías: tabla `offline_categories`.
///
/// `getAllAsMap()` / `mergeSections()` mantienen compatibilidad con el API
/// anterior (`getOfflineData` / `mergeOfflineData`).
class OfflineDatabaseService {
  static final OfflineDatabaseService _instance =
      OfflineDatabaseService._internal();
  factory OfflineDatabaseService() => _instance;
  OfflineDatabaseService._internal();

  static const int _dbVersion = 2;
  static const String _dbName = 'ventiq_offline.db';
  static const String _prefsMigratedKey = 'offline_sqlite_migrated_v1';
  static const String _prefsOfflineDataKey = 'offline_data';
  static const String _prefsOfflineStagingKey = 'offline_data_staging';

  Database? _db;
  Future<void>? _initFuture;
  bool _ffiInitialized = false;

  bool get isReady => _db != null;

  Future<Database> get database async {
    await initialize();
    return _db!;
  }

  /// Inicializa la BD (idempotente). Llamar desde `main()` al arrancar.
  Future<void> initialize() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    _ensureFfiIfNeeded();

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    print('🗄️ OfflineDatabase: abriendo $dbPath');

    _db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createAdminOpsTable(db);
        }
      },
    );

    await _migrateFromSharedPreferencesIfNeeded();
    print('✅ OfflineDatabase lista');
  }

  void _ensureFfiIfNeeded() {
    if (_ffiInitialized) return;
    if (kIsWeb) return;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
      print('🖥️ OfflineDatabase: sqflite_ffi inicializado (desktop)');
    }
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_sections (
        section_key TEXT PRIMARY KEY NOT NULL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_categories (
        id INTEGER PRIMARY KEY NOT NULL,
        denominacion TEXT,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_products (
        id INTEGER PRIMARY KEY NOT NULL,
        category_id TEXT NOT NULL,
        denominacion TEXT,
        sku TEXT,
        precio REAL,
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_category ON offline_products(category_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_denominacion ON offline_products(denominacion)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_sku ON offline_products(sku)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_meta (
        meta_key TEXT PRIMARY KEY NOT NULL,
        meta_value TEXT NOT NULL
      )
    ''');

    await _createAdminOpsTable(db);
  }

  Future<void> _createAdminOpsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS admin_pending_ops (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        op_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        synced_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_admin_ops_synced ON admin_pending_ops(synced)',
    );
  }

  // --------------------------------------------------------------------------
  // Admin pending ops (gestión inventario/productos offline)
  // --------------------------------------------------------------------------

  Future<void> enqueueAdminOp({
    required String clientUuid,
    required String opType,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    await db.insert(
      'admin_pending_ops',
      {
        'client_uuid': clientUuid,
        'op_type': opType,
        'payload': jsonEncode(payload),
        'synced': 0,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingAdminOps() async {
    final db = await database;
    final rows = await db.query(
      'admin_pending_ops',
      where: 'synced = 0',
      orderBy: 'id ASC',
    );
    return rows.map((r) {
      return {
        'id': r['id'],
        'client_uuid': r['client_uuid'],
        'op_type': r['op_type'],
        'payload': jsonDecode(r['payload'] as String),
        'created_at': r['created_at'],
        'last_error': r['last_error'],
      };
    }).toList();
  }

  Future<void> markAdminOpSynced(String clientUuid) async {
    final db = await database;
    await db.update(
      'admin_pending_ops',
      {
        'synced': 1,
        'synced_at': DateTime.now().toIso8601String(),
        'last_error': null,
      },
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
    );
  }

  Future<void> markAdminOpError(String clientUuid, String error) async {
    final db = await database;
    await db.update(
      'admin_pending_ops',
      {'last_error': error},
      where: 'client_uuid = ?',
      whereArgs: [clientUuid],
    );
  }

  Future<int> countPendingAdminOps() async {
    final db = await database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM admin_pending_ops WHERE synced = 0',
          ),
        ) ??
        0;
  }

  // --------------------------------------------------------------------------
  // API compatible con UserPreferencesService
  // --------------------------------------------------------------------------

  /// Reconstruye el mapa completo estilo `offline_data`.
  Future<Map<String, dynamic>?> getAllAsMap() async {
    final db = await database;
    final result = <String, dynamic>{};

    final sections = await db.query('offline_sections');
    for (final row in sections) {
      final key = row['section_key'] as String;
      // categories/products se leen de tablas normalizadas
      if (key == 'categories' || key == 'products') continue;
      try {
        result[key] = jsonDecode(row['payload'] as String);
      } catch (e) {
        print('⚠️ OfflineDatabase: sección $key corrupta: $e');
      }
    }

    // Categorías desde tabla normalizada (prioridad sobre section)
    final categories = await getCategories();
    if (categories.isNotEmpty) {
      result['categories'] = categories;
    }

    // Productos agrupados por categoría
    final productsByCategory = await getProductsGroupedByCategory();
    if (productsByCategory.isNotEmpty) {
      result['products'] = productsByCategory;
    }

    if (result.isEmpty) return null;
    return result;
  }

  /// Reemplaza todas las secciones (equivalente a saveOfflineData).
  Future<void> saveAllFromMap(Map<String, dynamic> data) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete('offline_sections');
      await txn.delete('offline_categories');
      await txn.delete('offline_products');

      for (final entry in data.entries) {
        if (entry.value == null) continue;
        await _upsertSectionInTxn(txn, entry.key, entry.value, now);
      }
    });
  }

  /// Merge por sección (equivalente a mergeOfflineData).
  Future<void> mergeSections(Map<String, dynamic> newData) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final entry in newData.entries) {
        if (entry.value == null) continue;
        await _upsertSectionInTxn(txn, entry.key, entry.value, now);
      }
    });
  }

  Future<void> _upsertSectionInTxn(
    Transaction txn,
    String key,
    dynamic value,
    String now,
  ) async {
    if (key == 'categories' && value is List) {
      await txn.delete('offline_categories');
      for (final item in value) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = _asInt(map['id']);
        if (id == null) continue;
        await txn.insert(
          'offline_categories',
          {
            'id': id,
            'denominacion':
                map['denominacion']?.toString() ??
                map['name']?.toString() ??
                '',
            'payload': jsonEncode(map),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      // Quitar snapshot legacy si existía
      await txn.delete(
        'offline_sections',
        where: 'section_key = ?',
        whereArgs: ['categories'],
      );
      return;
    }

    if (key == 'products' && value is Map) {
      await txn.delete('offline_products');
      final productsMap = Map<String, dynamic>.from(value);
      for (final catEntry in productsMap.entries) {
        final categoryId = catEntry.key.toString();
        final list = catEntry.value;
        if (list is! List) continue;
        for (final item in list) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          final id = _asInt(map['id']);
          if (id == null) continue;
          await txn.insert(
            'offline_products',
            {
              'id': id,
              'category_id': categoryId,
              'denominacion': map['denominacion']?.toString() ?? '',
              'sku': map['sku']?.toString(),
              'precio': _asDouble(map['precio']),
              'payload': jsonEncode(map),
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await txn.delete(
        'offline_sections',
        where: 'section_key = ?',
        whereArgs: ['products'],
      );
      return;
    }

    await txn.insert(
      'offline_sections',
      {
        'section_key': key,
        'payload': jsonEncode(value),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('offline_sections');
      await txn.delete('offline_categories');
      await txn.delete('offline_products');
    });
  }

  Future<bool> hasEssentialData() async {
    final db = await database;
    final cred = await db.query(
      'offline_sections',
      where: 'section_key = ?',
      whereArgs: ['credentials'],
      limit: 1,
    );
    final catCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM offline_categories'),
        ) ??
        0;
    final prodCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM offline_products'),
        ) ??
        0;
    return cred.isNotEmpty && catCount > 0 && prodCount > 0;
  }

  // --------------------------------------------------------------------------
  // Consultas parciales (beneficio real de SQLite)
  // --------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;
    final rows = await db.query('offline_categories', orderBy: 'denominacion');
    return rows.map((r) {
      try {
        return Map<String, dynamic>.from(jsonDecode(r['payload'] as String));
      } catch (_) {
        return <String, dynamic>{
          'id': r['id'],
          'denominacion': r['denominacion'],
        };
      }
    }).toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>>
      getProductsGroupedByCategory() async {
    final db = await database;
    final rows = await db.query('offline_products');
    final result = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final catId = r['category_id'] as String;
      try {
        final product =
            Map<String, dynamic>.from(jsonDecode(r['payload'] as String));
        result.putIfAbsent(catId, () => []).add(product);
      } catch (_) {
        // skip corrupt
      }
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getProductsByCategory(
    String categoryId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'offline_products',
      where: 'category_id = ?',
      whereArgs: [categoryId],
    );
    return rows
        .map((r) {
          try {
            return Map<String, dynamic>.from(
              jsonDecode(r['payload'] as String),
            );
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  /// Búsqueda parcial por nombre o SKU (sin cargar todo el catálogo).
  Future<List<Map<String, dynamic>>> searchProducts(
    String query, {
    int limit = 50,
  }) async {
    final db = await database;
    final q = '%${query.trim()}%';
    final rows = await db.query(
      'offline_products',
      where: 'denominacion LIKE ? OR sku LIKE ?',
      whereArgs: [q, q],
      limit: limit,
      orderBy: 'denominacion COLLATE NOCASE',
    );
    return rows
        .map((r) {
          try {
            return Map<String, dynamic>.from(
              jsonDecode(r['payload'] as String),
            );
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>?> getProductById(int id) async {
    final db = await database;
    final rows = await db.query(
      'offline_products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(
        jsonDecode(rows.first['payload'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> getSection(String key) async {
    if (key == 'categories') {
      final cats = await getCategories();
      return cats.isEmpty ? null : cats;
    }
    if (key == 'products') {
      final products = await getProductsGroupedByCategory();
      return products.isEmpty ? null : products;
    }

    final db = await database;
    final rows = await db.query(
      'offline_sections',
      where: 'section_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['payload'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>> getStats() async {
    final db = await database;
    final sections = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM offline_sections'),
        ) ??
        0;
    final categories = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM offline_categories'),
        ) ??
        0;
    final products = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM offline_products'),
        ) ??
        0;
    return {
      'sections': sections,
      'categories': categories,
      'products': products,
    };
  }

  // --------------------------------------------------------------------------
  // Migración one-shot desde SharedPreferences
  // --------------------------------------------------------------------------

  Future<void> _migrateFromSharedPreferencesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsMigratedKey) == true) {
      print('🗄️ OfflineDatabase: migración SharedPreferences ya hecha');
      return;
    }

    String? raw = prefs.getString(_prefsOfflineDataKey);
    raw ??= prefs.getString(_prefsOfflineStagingKey);
    if (raw == null || raw.isEmpty) {
      await prefs.setBool(_prefsMigratedKey, true);
      print('🗄️ OfflineDatabase: sin datos legacy que migrar');
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await prefs.setBool(_prefsMigratedKey, true);
        return;
      }

      final map = Map<String, dynamic>.from(decoded);
      print(
        '🗄️ OfflineDatabase: migrando ${map.keys.length} secciones desde SharedPreferences...',
      );
      await saveAllFromMap(map);

      // Limpiar el blob gigante de prefs (libera memoria / cuota)
      await prefs.remove(_prefsOfflineDataKey);
      await prefs.remove(_prefsOfflineStagingKey);
      await prefs.setBool(_prefsMigratedKey, true);

      final stats = await getStats();
      print(
        '✅ Migración offline completada: '
        '${stats['categories']} categorías, ${stats['products']} productos, '
        '${stats['sections']} secciones',
      );
    } catch (e) {
      print('❌ Error migrando offline_data a SQLite: $e');
      // No marcar migrado para reintentar en el próximo arranque
    }
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
