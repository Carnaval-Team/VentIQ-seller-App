import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Modelo de item del carrito
class CartItem {
  final String id; // ID único del item en el carrito
  final int productId;
  final String productName;
  final String? productImage;
  final String variantId;
  final String variantName;
  final String presentacion;
  final double price;
  final int quantity;
  final int storeId;
  final String storeName;
  final String? storeLocation;
  final String? storeAddress;
  final String? storeProvincia;
  final String? storeMunicipio;
  final DateTime addedAt;

  CartItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.productImage,
    required this.variantId,
    required this.variantName,
    required this.presentacion,
    required this.price,
    required this.quantity,
    required this.storeId,
    required this.storeName,
    this.storeLocation,
    this.storeAddress,
    this.storeProvincia,
    this.storeMunicipio,
    required this.addedAt,
  });

  double get subtotal => price * quantity;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'productName': productName,
      'productImage': productImage,
      'variantId': variantId,
      'variantName': variantName,
      'presentacion': presentacion,
      'price': price,
      'quantity': quantity,
      'storeId': storeId,
      'storeName': storeName,
      'storeLocation': storeLocation,
      'storeAddress': storeAddress,
      'storeProvincia': storeProvincia,
      'storeMunicipio': storeMunicipio,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      productId: json['productId'] as int,
      productName: json['productName'] as String,
      productImage: json['productImage'] as String?,
      variantId: json['variantId'] as String,
      variantName: json['variantName'] as String,
      presentacion: json['presentacion'] as String,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int,
      storeId: json['storeId'] as int,
      storeName: json['storeName'] as String,
      storeLocation: json['storeLocation'] as String?,
      storeAddress: json['storeAddress'] as String?,
      storeProvincia: json['storeProvincia'] as String?,
      storeMunicipio: json['storeMunicipio'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
    );
  }

  CartItem copyWith({
    String? id,
    int? productId,
    String? productName,
    String? productImage,
    String? variantId,
    String? variantName,
    String? presentacion,
    double? price,
    int? quantity,
    int? storeId,
    String? storeName,
    String? storeLocation,
    String? storeAddress,
    String? storeProvincia,
    String? storeMunicipio,
    DateTime? addedAt,
  }) {
    return CartItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      productImage: productImage ?? this.productImage,
      variantId: variantId ?? this.variantId,
      variantName: variantName ?? this.variantName,
      presentacion: presentacion ?? this.presentacion,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      storeLocation: storeLocation ?? this.storeLocation,
      storeAddress: storeAddress ?? this.storeAddress,
      storeProvincia: storeProvincia ?? this.storeProvincia,
      storeMunicipio: storeMunicipio ?? this.storeMunicipio,
      addedAt: addedAt ?? this.addedAt,
    );
  }
}

/// Servicio de gestión del carrito de compras con persistencia
class CartService {
  static const String _cartKey = 'marketplace_cart';
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal() {
    // Auto-inicializar al crear la instancia
    _autoInitialize();
  }

  List<CartItem> _cartItems = [];
  bool _isInitialized = false;
  
  /// Auto-inicialización en segundo plano
  void _autoInitialize() {
    initialize();
  }
  
  /// Obtiene todos los items del carrito
  List<CartItem> get items => List.unmodifiable(_cartItems);
  
  /// Obtiene el número total de items
  int get itemCount => _cartItems.length;
  
  /// Obtiene la cantidad total de productos
  int get totalQuantity => _cartItems.fold(0, (sum, item) => sum + item.quantity);
  
  /// Obtiene el total del carrito
  double get total => _cartItems.fold(0.0, (sum, item) => sum + item.subtotal);
  
  /// Verifica si el carrito está vacío
  bool get isEmpty => _cartItems.isEmpty;
  
  /// Verifica si el carrito tiene items
  bool get isNotEmpty => _cartItems.isNotEmpty;

  /// Inicializa el carrito cargando datos desde SharedPreferences
  Future<void> initialize() async {
    if (_isInitialized) {
      print('🛒 Carrito ya inicializado con ${_cartItems.length} items');
      return;
    }
    
    try {
      print('🛒 Inicializando carrito desde cache...');
      final prefs = await SharedPreferences.getInstance();
      final cartJson = prefs.getString(_cartKey);
      
      if (cartJson != null && cartJson.isNotEmpty) {
        final List<dynamic> cartList = jsonDecode(cartJson);
        _cartItems = cartList.map((item) => CartItem.fromJson(item)).toList();
        print('✅ Carrito cargado: ${_cartItems.length} items');
      } else {
        print('📭 Carrito vacío');
        _cartItems = [];
      }
      _isInitialized = true;
    } catch (e) {
      print('❌ Error cargando carrito: $e');
      _cartItems = [];
      _isInitialized = true;
    }
  }

  /// Fuerza una recarga completa del carrito desde SharedPreferences
  Future<void> forceReload() async {
    try {
      print('🔄 Forzando recarga del carrito desde SharedPreferences...');
      _isInitialized = false; // Resetear flag
      await initialize();
      print('✅ Carrito recargado: ${_cartItems.length} items, Total: \$${total.toStringAsFixed(2)}');
    } catch (e) {
      print('❌ Error recargando carrito: $e');
      rethrow;
    }
  }

  /// Guarda el carrito en SharedPreferences
  Future<void> _saveCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartJson = jsonEncode(_cartItems.map((item) => item.toJson()).toList());
      await prefs.setString(_cartKey, cartJson);
      print('💾 Carrito guardado: ${_cartItems.length} items');
    } catch (e) {
      print('❌ Error guardando carrito: $e');
    }
  }

  /// Agrega un item al carrito
  Future<void> addItem({
    required int productId,
    required String productName,
    String? productImage,
    required String variantId,
    required String variantName,
    required String presentacion,
    required double price,
    required int quantity,
    required int storeId,
    required String storeName,
    String? storeLocation,
    String? storeAddress,
    String? storeProvincia,
    String? storeMunicipio,
  }) async {
    try {
      // Asegurar que el carrito esté inicializado
      await initialize();
      
      // Verificar si ya existe un item con el mismo producto y variante
      final existingIndex = _cartItems.indexWhere(
        (item) => item.productId == productId && item.variantId == variantId,
      );

      if (existingIndex != -1) {
        // Actualizar cantidad del item existente
        final existingItem = _cartItems[existingIndex];
        _cartItems[existingIndex] = existingItem.copyWith(
          quantity: existingItem.quantity + quantity,
        );
        print('📦 Item actualizado en carrito: ${existingItem.productName} - ${existingItem.variantName}');
      } else {
        // Agregar nuevo item
        final newItem = CartItem(
          id: '${DateTime.now().millisecondsSinceEpoch}_$productId\_$variantId',
          productId: productId,
          productName: productName,
          productImage: productImage,
          variantId: variantId,
          variantName: variantName,
          presentacion: presentacion,
          price: price,
          quantity: quantity,
          storeId: storeId,
          storeName: storeName,
          storeLocation: storeLocation,
          storeAddress: storeAddress,
          storeProvincia: storeProvincia,
          storeMunicipio: storeMunicipio,
          addedAt: DateTime.now(),
        );
        _cartItems.add(newItem);
        print('✅ Nuevo item agregado al carrito: $productName - $variantName');
      }

      await _saveCart();
      print('🛒 Total items en carrito: ${_cartItems.length}');
    } catch (e) {
      print('❌ Error agregando item al carrito: $e');
      rethrow;
    }
  }

  /// Actualiza la cantidad de un item
  Future<void> updateQuantity(String itemId, int newQuantity) async {
    try {
      if (newQuantity <= 0) {
        await removeItem(itemId);
        return;
      }

      final index = _cartItems.indexWhere((item) => item.id == itemId);
      if (index != -1) {
        _cartItems[index] = _cartItems[index].copyWith(quantity: newQuantity);
        await _saveCart();
        print('🔄 Cantidad actualizada: ${_cartItems[index].productName} - $newQuantity');
      }
    } catch (e) {
      print('❌ Error actualizando cantidad: $e');
      rethrow;
    }
  }

  /// Remueve un item del carrito
  Future<void> removeItem(String itemId) async {
    try {
      final removedItem = _cartItems.firstWhere((item) => item.id == itemId);
      _cartItems.removeWhere((item) => item.id == itemId);
      await _saveCart();
      print('🗑️ Item removido del carrito: ${removedItem.productName}');
    } catch (e) {
      print('❌ Error removiendo item: $e');
      rethrow;
    }
  }

  /// Limpia todo el carrito
  Future<void> clearCart() async {
    try {
      _cartItems.clear();
      await _saveCart();
      print('🧹 Carrito limpiado');
    } catch (e) {
      print('❌ Error limpiando carrito: $e');
      rethrow;
    }
  }

  /// Obtiene items agrupados por tienda
  Map<int, List<CartItem>> getItemsByStore() {
    final Map<int, List<CartItem>> itemsByStore = {};
    
    for (final item in _cartItems) {
      if (!itemsByStore.containsKey(item.storeId)) {
        itemsByStore[item.storeId] = [];
      }
      itemsByStore[item.storeId]!.add(item);
    }
    
    return itemsByStore;
  }

  /// Obtiene el total por tienda
  double getTotalByStore(int storeId) {
    return _cartItems
        .where((item) => item.storeId == storeId)
        .fold(0.0, (sum, item) => sum + item.subtotal);
  }

  /// Obtiene la cantidad de items de una tienda específica
  int getStoreItemCount(int storeId) {
    return _cartItems.where((item) => item.storeId == storeId).length;
  }
}
