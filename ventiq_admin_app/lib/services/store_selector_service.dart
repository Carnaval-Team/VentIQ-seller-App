import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  static const String _selectedStoreKey = 'selected_store_id';
  
  final SupabaseClient _supabase = Supabase.instance.client;
  
  List<Store> _userStores = [];
  Store? _selectedStore;
  bool _isLoading = false;
  bool _isInitialized = false;

  List<Store> get userStores => _userStores;
  Store? get selectedStore => _selectedStore;
  bool get isLoading => _isLoading;
  bool get hasMultipleStores => _userStores.length > 1;
  bool get isInitialized => _isInitialized;

  /// Inicializar el servicio cargando las tiendas del usuario
  Future<void> initialize() async {
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
        _userStores = response
            .map((storeData) => Store.fromJson(storeData as Map<String, dynamic>))
            .toList();
        
        print('🏪 Tiendas cargadas: ${_userStores.length}');
      } else {
        print('⚠️ No se encontraron tiendas para el usuario');
        _userStores = [];
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

  /// Cargar tienda seleccionada desde preferencias
  Future<void> _loadSelectedStore() async {
    try {
      if (_userStores.isEmpty) {
        _selectedStore = null;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final selectedStoreId = prefs.getInt(_selectedStoreKey);

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
      }

      print('🏪 Tienda seleccionada: ${_selectedStore?.denominacion} (ID: ${_selectedStore?.id})');
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
