import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order.dart';
import 'user_preferences_service.dart';

/// Cache + sync de recetas (`app_dat_producto_ingredientes`) para gasto de
/// ingredientes online/offline en el resumen de ventas.
class ProductRecipeCacheService {
  static final ProductRecipeCacheService _instance =
      ProductRecipeCacheService._internal();
  factory ProductRecipeCacheService() => _instance;
  ProductRecipeCacheService._internal();

  final _prefs = UserPreferencesService();
  final _supabase = Supabase.instance.client;

  /// Descarga recetas de los elaborados indicados (o de [productIds] del
  /// catálogo) y las guarda en SharedPreferences.
  ///
  /// [replaceAll]: true en sync de catálogo (el cache queda solo con lo
  /// encontrado). false en refrescos puntuales (merge con cache existente).
  Future<Map<int, List<Map<String, dynamic>>>> syncRecipesForProductIds(
    Iterable<int> productIds, {
    bool replaceAll = false,
  }) async {
    final ids = productIds.toSet().where((id) => id > 0).toList();
    if (ids.isEmpty) {
      print('🍽️ Sync recetas: sin productIds');
      if (replaceAll) {
        await _prefs.saveProductIngredientRecipes({});
      }
      return {};
    }

    try {
      // Incluye elaborados anidados: si un ingrediente es elaborado, también
      // bajamos su receta (mismo criterio que fn_obtener_ingredientes_recursivos).
      final pending = ids.toSet();
      final grouped = <int, List<Map<String, dynamic>>>{};
      final fetched = <int>{};

      while (pending.isNotEmpty) {
        final batch = pending.toList();
        pending.clear();
        final response = await _supabase
            .from('app_dat_producto_ingredientes')
            .select('''
              id_producto_elaborado,
              id_ingrediente,
              cantidad_necesaria,
              unidad_medida,
              app_dat_producto!app_dat_producto_ingredientes_ingrediente_fkey(
                id,
                denominacion,
                sku,
                es_elaborado
              )
            ''')
            .inFilter('id_producto_elaborado', batch);

        for (final id in batch) {
          fetched.add(id);
          grouped.putIfAbsent(id, () => []);
        }

        for (final item in response) {
          final elaboradoId = (item['id_producto_elaborado'] as num?)?.toInt();
          if (elaboradoId == null) continue;
          final producto =
              item['app_dat_producto'] as Map<String, dynamic>? ?? {};
          final idIng = (item['id_ingrediente'] as num?)?.toInt();
          final esElab = producto['es_elaborado'] == true;
          grouped.putIfAbsent(elaboradoId, () => []).add({
            'nombre_ingrediente':
                producto['denominacion'] ?? 'Ingrediente desconocido',
            'cantidad_necesaria': item['cantidad_necesaria'] ?? 0,
            'unidad_medida': item['unidad_medida'] ?? 'unid',
            'sku': producto['sku'],
            'id_ingrediente': idIng,
            'producto_id': idIng,
            'es_elaborado': esElab,
          });
          if (esElab &&
              idIng != null &&
              !fetched.contains(idIng) &&
              !pending.contains(idIng)) {
            pending.add(idIng);
          }
        }
      }

      final Map<int, List<Map<String, dynamic>>> toSave;
      if (replaceAll) {
        toSave = grouped;
      } else {
        final existing = await _prefs.getProductIngredientRecipes();
        toSave = Map<int, List<Map<String, dynamic>>>.from(existing);
        for (final entry in grouped.entries) {
          toSave[entry.key] = entry.value;
        }
        for (final id in ids) {
          if (!grouped.containsKey(id)) toSave.remove(id);
        }
      }

      await _prefs.saveProductIngredientRecipes(toSave);
      print(
        '✅ Recetas sincronizadas: ${grouped.length} elaborados '
        '(${ids.length} ids raíz, anidados incluidos, replaceAll=$replaceAll)',
      );
      return grouped;
    } catch (e) {
      print('⚠️ Sync recetas elaborados (no bloqueante): $e');
      return await _prefs.getProductIngredientRecipes(ids: ids.toSet());
    }
  }

  /// Lee recetas: cache local si offline; si online intenta refrescar y cachear.
  Future<Map<int, List<Map<String, dynamic>>>> loadRecipes(
    Set<int> elaboradoIds, {
    bool forceRefresh = false,
  }) async {
    if (elaboradoIds.isEmpty) return {};

    final useLocal =
        !forceRefresh && await _prefs.shouldUseLocalData();
    if (useLocal) {
      final cached = await _prefs.getProductIngredientRecipes(
        ids: elaboradoIds,
      );
      print(
        '🔌 Offline - recetas desde cache: '
        '${cached.length}/${elaboradoIds.length}',
      );
      return cached;
    }

    try {
      return await syncRecipesForProductIds(elaboradoIds);
    } catch (e) {
      print('⚠️ loadRecipes online falló, usando cache: $e');
      return await _prefs.getProductIngredientRecipes(ids: elaboradoIds);
    }
  }

  /// Snapshot de ingredientes para persistir en orden pendiente offline.
  Future<List<Map<String, dynamic>>?> snapshotIngredientsForItem(
    OrderItem item,
  ) async {
    if (!item.producto.esElaborado) return null;

    final existing = item.ingredientes;
    if (existing != null && existing.isNotEmpty) {
      return existing
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final recipes = await _prefs.getProductIngredientRecipes(
      ids: {item.producto.id},
    );
    final rows = recipes[item.producto.id];
    if (rows == null || rows.isEmpty) return null;

    final factor = item.equivalenteBase;
    return rows.map((row) {
      final necesaria =
          (row['cantidad_necesaria'] as num?)?.toDouble() ?? 0.0;
      return <String, dynamic>{
        'nombre_ingrediente':
            row['nombre_ingrediente'] ?? 'Ingrediente desconocido',
        'unidad_medida': row['unidad_medida'] ?? 'unid',
        'cantidad_necesaria': necesaria,
        'cantidad_vendida': necesaria * factor,
        'id_ingrediente': row['id_ingrediente'],
        'sku': row['sku'],
      };
    }).toList();
  }
}
