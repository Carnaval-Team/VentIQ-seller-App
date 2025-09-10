import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Store {
  final int id;
  final String denominacion;
  final String? direccion;
  final String? telefono;
  final String? email;
  final bool esPrincipal;

  Store({
    required this.id,
    required this.denominacion,
    this.direccion,
    this.telefono,
    this.email,
    required this.esPrincipal,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      direccion: json['direccion'] as String?,
      telefono: json['telefono'] as String?,
      email: json['email'] as String?,
      esPrincipal: json['es_principal'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'direccion': direccion,
      'telefono': telefono,
      'email': email,
      'es_principal': esPrincipal,
    };
  }
}

class StoreSelectorService extends ChangeNotifier {
  static const String _selectedStoreKey = 'selected_store_id';
  static const String _userStoresKey = 'user_stores';
  
  final SupabaseClient _supabase = Supabase.instance.client;
  
  List<Store> _userStores = [];
  Store? _selectedStore;
  bool _isLoading = false;

  List<Store> get userStores => _userStores;
  Store? get selectedStore => _selectedStore;
  bool get isLoading => _isLoading;
  bool get hasMultipleStores => _userStores.length > 1;

  /// Inicializar el servicio cargando las tiendas del usuario
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _loadUserStores();
      await _loadSelectedStore();
    } catch (e) {
      print('Error initializing StoreSelectorService: $e');
    } finally {
      _isLoading = false;
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
        params: {'p_uuid': user.id},
      );

      print('🏪 Respuesta tiendas: $response');

      if (response != null && response is List) {
        _userStores = response
            .map((storeData) => Store.fromJson(storeData as Map<String, dynamic>))
            .toList();
        
        print('🏪 Tiendas cargadas: ${_userStores.length}');
        
        // Guardar en cache local
        await _saveStoresToCache();
      } else {
        print('⚠️ No se encontraron tiendas, usando datos mock');
        _userStores = _getMockStores();
      }
    } catch (e) {
      print('❌ Error cargando tiendas: $e');
      // Cargar desde cache o usar mock
      await _loadStoresFromCache();
      if (_userStores.isEmpty) {
        _userStores = _getMockStores();
      }
    }
  }

  /// Cargar tienda seleccionada desde preferencias
  Future<void> _loadSelectedStore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedStoreId = prefs.getInt(_selectedStoreKey);

      if (selectedStoreId != null) {
        _selectedStore = _userStores.firstWhere(
          (store) => store.id == selectedStoreId,
          orElse: () => _userStores.isNotEmpty ? _userStores.first : _getMockStores().first,
        );
      } else {
        // Seleccionar la tienda principal por defecto
        _selectedStore = _userStores.firstWhere(
          (store) => store.esPrincipal,
          orElse: () => _userStores.isNotEmpty ? _userStores.first : _getMockStores().first,
        );
      }

      print('🏪 Tienda seleccionada: ${_selectedStore?.denominacion} (ID: ${_selectedStore?.id})');
    } catch (e) {
      print('❌ Error cargando tienda seleccionada: $e');
      if (_userStores.isNotEmpty) {
        _selectedStore = _userStores.first;
      }
    }
  }

  /// Cambiar tienda seleccionada
  Future<void> selectStore(Store store) async {
    if (_selectedStore?.id == store.id) return;

    _selectedStore = store;
    
    // Guardar en preferencias
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_selectedStoreKey, store.id);
    
    print('🏪 Tienda cambiada a: ${store.denominacion} (ID: ${store.id})');
    
    notifyListeners();
  }

  /// Obtener ID de la tienda seleccionada (compatibilidad con código existente)
  int? getSelectedStoreId() {
    return _selectedStore?.id;
  }

  /// Refrescar lista de tiendas
  Future<void> refresh() async {
    await _loadUserStores();
    await _loadSelectedStore();
    notifyListeners();
  }

  /// Guardar tiendas en cache local
  Future<void> _saveStoresToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storesJson = _userStores.map((store) => store.toJson()).toList();
      await prefs.setString(_userStoresKey, storesJson.toString());
    } catch (e) {
      print('Error guardando tiendas en cache: $e');
    }
  }

  /// Cargar tiendas desde cache local
  Future<void> _loadStoresFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storesString = prefs.getString(_userStoresKey);
      if (storesString != null) {
        // Implementar deserialización si es necesario
        print('📱 Cargando tiendas desde cache local');
      }
    } catch (e) {
      print('Error cargando tiendas desde cache: $e');
    }
  }

  /// Datos mock para desarrollo/fallback
  List<Store> _getMockStores() {
    return [
      Store(
        id: 1,
        denominacion: 'Tienda Principal',
        direccion: 'Calle Principal 123',
        telefono: '+1234567890',
        email: 'principal@ventiq.com',
        esPrincipal: true,
      ),
      Store(
        id: 2,
        denominacion: 'Sucursal Norte',
        direccion: 'Av. Norte 456',
        telefono: '+1234567891',
        email: 'norte@ventiq.com',
        esPrincipal: false,
      ),
      Store(
        id: 3,
        denominacion: 'Sucursal Sur',
        direccion: 'Calle Sur 789',
        telefono: '+1234567892',
        email: 'sur@ventiq.com',
        esPrincipal: false,
      ),
    ];
  }
}
