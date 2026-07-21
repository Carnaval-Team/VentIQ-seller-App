import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class Store {
  final int id;
  final String denominacion;
  final String? direccion;
  final String? ubicacion;
  final DateTime createdAt;

  Store({
    required this.id,
    required this.denominacion,
    this.direccion,
    this.ubicacion,
    required this.createdAt,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id_tienda'] as int,
      denominacion: json['denominacion'] as String,
      direccion: json['direccion'] as String?,
      ubicacion: json['ubicacion'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_tienda': id,
      'denominacion': denominacion,
      'direccion': direccion,
      'ubicacion': ubicacion,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class StoreSelectorService extends ChangeNotifier {
  static final StoreSelectorService _instance =
      StoreSelectorService._internal();
  factory StoreSelectorService() => _instance;
  StoreSelectorService._internal();

  static const String _selectedStoreKey = 'selected_store_id';
  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  List<Store> _userStores = [];
  Store? _selectedStore;
  bool _isLoading = false;
  bool _isInitialized = false;
  Future<void>? _initializationFuture;

  List<Store> get userStores => _userStores;
  Store? get selectedStore => _selectedStore;
  bool get isLoading => _isLoading;
  bool get hasMultipleStores => _userStores.length > 1;
  bool get isInitialized => _isInitialized;

  /// Inicializar el servicio cargando las tiendas del usuario
  Future<void> initialize() {
    if (_isInitialized) {
      return _refreshSelectedStore();
    }

    if (_initializationFuture != null) {
      return _initializationFuture!;
    }

    _initializationFuture = _initializeInternal();
    return _initializationFuture!;
  }

  Future<void> _refreshSelectedStore() async {
    try {
      if (_userStores.isEmpty) {
        await _loadUserStores();
      }
      await _loadSelectedStore();
      notifyListeners();
    } catch (e) {
      print('❌ Error refreshing selected store: $e');
    }
  }

  Future<void> _initializeInternal() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _loadUserStores();
      await _loadSelectedStore();
      _isInitialized = true;
    } catch (e) {
      print('Error initializing StoreSelectorService: $e');
    } finally {
      _isLoading = false;
      _initializationFuture = null;
      notifyListeners();
    }
  }

  /// Cargar tiendas del usuario desde la base de datos
  Future<void> _loadUserStores() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuario no autenticado');
      }

      print('🏪 Cargando tiendas para usuario: ${user.id}');

      final response = await _supabase.rpc(
        'fn_listar_tiendas_gerente',
        params: {'p_uuid_usuario': user.id},
      );

      print('🏪 Respuesta tiendas: $response');

      if (response != null && response is List && response.isNotEmpty) {
        _userStores =
            response
                .map(
                  (storeData) =>
                      Store.fromJson(storeData as Map<String, dynamic>),
                )
                .toList();

        print('🏪 Tiendas cargadas: ${_userStores.length}');
      } else {
        // RPC returned empty — user may be another admin role (supervisor, auditor, almacenero, HR).
        // Query role tables directly.
        print('⚠️ No se encontraron tiendas vía RPC, verificando otros roles admin...');
        await _loadAdminRoleStores(user.id);
      }
    } catch (e) {
      print('❌ Error cargando tiendas: $e');
      _userStores = [];

      // Si estamos en modo debug, usar mock como fallback
      if (kDebugMode) {
        print('🔧 Modo debug: usando datos mock como fallback');
        _userStores = _getMockStores();
      }
    }
  }

  /// Cargar tiendas asignadas a roles administrativos distintos de gerente
  Future<void> _loadAdminRoleStores(String userUuid) async {
    try {
      // Supervisor
      final supervisorData = await _supabase
          .from('app_dat_supervisor')
          .select('id_tienda, app_dat_tienda(id, denominacion, direccion, created_at)')
          .eq('uuid', userUuid);

      if (supervisorData.isNotEmpty) {
        _userStores = _mapRoleDataToStores(supervisorData);
        print('🏪 Tiendas Supervisor cargadas: ${_userStores.length}');
        return;
      }

      // Auditor
      final auditorData = await _supabase
          .from('auditor')
          .select('id_tienda, app_dat_tienda(id, denominacion, direccion, created_at)')
          .eq('uuid', userUuid);

      if (auditorData.isNotEmpty) {
        _userStores = _mapRoleDataToStores(auditorData);
        print('🏪 Tiendas Auditor cargadas: ${_userStores.length}');
        return;
      }

      // Almacenero
      final almaceneroData = await _supabase
          .from('app_dat_almacenero')
          .select('id_almacen, app_dat_almacen(id_tienda, app_dat_tienda(id, denominacion, direccion, created_at))')
          .eq('uuid', userUuid);

      if (almaceneroData.isNotEmpty) {
        final stores = <Store>[];
        for (final record in almaceneroData) {
          final almacen = record['app_dat_almacen'] as Map<String, dynamic>?;
          final tienda = almacen?['app_dat_tienda'] as Map<String, dynamic>?;
          if (tienda != null) {
            stores.add(_storeFromTiendaMap(tienda));
          }
        }
        _userStores = stores;
        print('🏪 Tiendas Almacenero cargadas: ${_userStores.length}');
        return;
      }

      // Recursos Humanos
      await _loadHRStores(userUuid);
    } catch (e) {
      print('❌ Error cargando tiendas por rol admin: $e');
      _userStores = [];
    }
  }

  /// Helper para convertir registros de rol a lista de Store
  List<Store> _mapRoleDataToStores(List<dynamic> roleData) {
    return roleData
        .where((r) => r['app_dat_tienda'] != null)
        .map((r) => _storeFromTiendaMap(r['app_dat_tienda'] as Map<String, dynamic>))
        .toList();
  }

  /// Helper para construir un Store desde un mapa de app_dat_tienda
  Store _storeFromTiendaMap(Map<String, dynamic> tienda) {
    return Store(
      id: tienda['id'] as int,
      denominacion: tienda['denominacion'] as String,
      direccion: tienda['direccion'] as String?,
      ubicacion: null,
      createdAt: tienda['created_at'] != null
          ? DateTime.parse(tienda['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// Cargar tienda seleccionada desde preferencias
  Future<void> _loadSelectedStore() async {
    try {
      if (_userStores.isEmpty) {
        _selectedStore = null;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final storedStoreId = prefs.getInt(_selectedStoreKey);
      final currentStoreId = await _userPreferencesService.getIdTienda();
      int? selectedStoreId = currentStoreId;

      if (selectedStoreId == null && storedStoreId != null) {
        selectedStoreId = storedStoreId;
        await _userPreferencesService.updateSelectedStore(storedStoreId);
      }

      if (selectedStoreId != null) {
        _selectedStore = _userStores.firstWhere(
          (store) => store.id == selectedStoreId,
          orElse: () => _userStores.first,
        );
      } else {
        // Seleccionar la tienda principal por defecto
        _selectedStore = _userStores.firstWhere(
          (store) => store.denominacion == 'Tienda Principal',
          orElse: () => _userStores.first,
        );
        await _userPreferencesService.updateSelectedStore(_selectedStore!.id);
        selectedStoreId = _selectedStore!.id;
      }

      final resolvedStoreId = _selectedStore?.id;
      if (resolvedStoreId != null) {
        if (storedStoreId != resolvedStoreId) {
          await prefs.setInt(_selectedStoreKey, resolvedStoreId);
        }
        if (selectedStoreId != resolvedStoreId) {
          await _userPreferencesService.updateSelectedStore(resolvedStoreId);
        }
      }

      print(
        '🏪 Tienda seleccionada: ${_selectedStore?.denominacion} (ID: ${_selectedStore?.id})',
      );
    } catch (e) {
      print('❌ Error cargando tienda seleccionada: $e');
      if (_userStores.isNotEmpty) {
        _selectedStore = _userStores.first;
      } else {
        _selectedStore = null;
      }
    }
  }

  /// Cambiar tienda seleccionada
  Future<void> selectStore(Store store) async {
    if (_selectedStore?.id == store.id) return;

    _selectedStore = store;

    // Guardar en preferencias
    await _userPreferencesService.updateSelectedStore(store.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_selectedStoreKey, store.id);

    print('🏪 Tienda cambiada a: ${store.denominacion} (ID: ${store.id})');

    notifyListeners();
  }

  /// Obtener ID de la tienda seleccionada (compatibilidad con código existente)
  int? getSelectedStoreId() {
    return _selectedStore?.id;
  }

  /// Sincronizar tienda seleccionada con preferencias (Dashboard)
  Future<void> syncSelectedStore({bool notify = true}) async {
    if (_userStores.isEmpty) return;

    final selectedStoreId = await _userPreferencesService.getIdTienda();
    if (selectedStoreId == null) return;
    if (_selectedStore?.id == selectedStoreId) return;

    _selectedStore = _userStores.firstWhere(
      (store) => store.id == selectedStoreId,
      orElse: () => _userStores.first,
    );
    if (notify) {
      notifyListeners();
    }
  }

  /// Refrescar lista de tiendas
  Future<void> refresh() async {
    await _loadUserStores();
    await _loadSelectedStore();
    notifyListeners();
  }

  /// Cargar tiendas asignadas a un usuario de Recursos Humanos
  Future<void> _loadHRStores(String userUuid) async {
    try {
      final rrhhData = await _supabase
          .from('app_dat_recursos_humanos')
          .select('id_tienda, app_dat_tienda(id, denominacion, direccion, created_at)')
          .eq('uuid', userUuid);

      print('🏪 Tiendas HR encontradas: ${rrhhData.length}');

      if (rrhhData.isNotEmpty) {
        _userStores = rrhhData
            .where((r) => r['app_dat_tienda'] != null)
            .map((r) {
              final tienda = r['app_dat_tienda'] as Map<String, dynamic>;
              return Store(
                id: tienda['id'] as int,
                denominacion: tienda['denominacion'] as String,
                direccion: tienda['direccion'] as String?,
                ubicacion: null,
                createdAt: tienda['created_at'] != null
                    ? DateTime.parse(tienda['created_at'] as String)
                    : DateTime.now(),
              );
            })
            .toList();
        print('🏪 Tiendas HR cargadas: ${_userStores.length}');
      } else {
        print('⚠️ No se encontraron tiendas para el usuario Recursos Humanos');
        _userStores = [];
      }
    } catch (e) {
      print('❌ Error cargando tiendas HR: $e');
      _userStores = [];
    }
  }

  /// Datos mock para desarrollo/fallback
  List<Store> _getMockStores() {
    return [
      Store(
        id: 1,
        denominacion: 'Tienda Principal',
        direccion: 'Calle Principal 123',
        ubicacion: 'Ubicación Principal',
        createdAt: DateTime.now(),
      ),
      Store(
        id: 2,
        denominacion: 'Sucursal Norte',
        direccion: 'Av. Norte 456',
        ubicacion: 'Ubicación Norte',
        createdAt: DateTime.now(),
      ),
      Store(
        id: 3,
        denominacion: 'Sucursal Sur',
        direccion: 'Calle Sur 789',
        ubicacion: 'Ubicación Sur',
        createdAt: DateTime.now(),
      ),
    ];
  }
}
