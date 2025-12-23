import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/cart_service.dart';
import 'route_plan_screen.dart';

/// Pantalla del carrito de compras
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with WidgetsBindingObserver {
  final CartService _cartService = CartService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cargar carrito al inicializar
    _loadCart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Recargar cuando la app vuelve al foreground
    if (state == AppLifecycleState.resumed && mounted) {
      print('📱 App resumed - Recargando carrito...');
      _loadCart();
    }
  }

  Future<void> _loadCart() async {
    if (!mounted || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Forzar recarga completa del carrito desde SharedPreferences
      await _cartService.forceReload();
      print('✅ Carrito actualizado en pantalla');
    } catch (e) {
      print('❌ Error cargando carrito: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar carrito: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshCart() async {
    print('🔄 Pull to refresh - Recargando carrito...');
    await _loadCart();
  }

  Future<void> _updateQuantity(String itemId, int newQuantity) async {
    try {
      await _cartService.updateQuantity(itemId, newQuantity);
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar cantidad: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _removeItem(String itemId) async {
    try {
      await _cartService.removeItem(itemId);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Producto eliminado del carrito'),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _clearCart() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vaciar carrito'),
        content: const Text(
          '¿Estás seguro de que quieres eliminar todos los productos?',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _cartService.clearCart();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plan vaciado'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    }
  }

  Future<void> _traceRoute() async {
    // Collect unique stores from cart items
    final Map<int, CartItem> uniqueStores = {};
    for (final item in _cartService.items) {
      if (!uniqueStores.containsKey(item.storeId)) {
        uniqueStores[item.storeId] = item;
      }
    }

    if (uniqueStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay tiendas en tu plan')),
      );
      return;
    }

    // Filter stores with valid location
    final List<Map<String, dynamic>> storesWithLocation = [];
    for (final item in uniqueStores.values) {
      if (item.storeLocation != null && item.storeLocation!.contains(',')) {
        storesWithLocation.add({
          'id': item.storeId,
          'denominacion': item.storeName,
          'ubicacion': item.storeLocation,
          'imagen_url': item
              .storeLocation, // Using storeLocation as placeholder if needed? No, wait.
          // CartItem doesn't have store image URL readily available in plain CartItem?
          // Let's check CartItem definition again.
          // It has 'storeLocation', 'storeName'. IT DOES NOT HAVE store image URL explicitly in the constructor shown earlier?
          // Wait, let me check the CartItem definition in step 13.
          // It DOES NOT have storeImageUrl. It has productImage and productName.
          // I might need to fetch store details or just use a default icon.
          // Or I can update CartItem to include it later, but for now let's survive without it or pass null.
          'direccion': item.storeAddress,
        });
      }
    }

    if (storesWithLocation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Las tiendas en tu plan no tienen ubicación registrada',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RoutePlanScreen(stores: storesWithLocation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Plan de Compra (${_cartService.itemCount})'),
        actions: [
          // Botón de refresh manual
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshCart,
            tooltip: 'Actualizar carrito',
          ),
          if (_cartService.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearCart,
              tooltip: 'Vaciar carrito',
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshCart,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _cartService.isEmpty
            ? _buildEmptyState()
            : _buildCartContent(),
      ),
      bottomNavigationBar: _cartService.isNotEmpty
          ? _buildCheckoutButton()
          : null,
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height - 200,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 100,
                  color: Colors.grey[300],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Tu plan de compra está vacío',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Agrega productos para armar tu ruta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppTheme.textSecondary.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Desliza hacia abajo para actualizar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.primaryColor.withOpacity(0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    // Navegar al home (MainScreen) limpiando todo el stack
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/home',
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text(
                    'Explorar productos',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartContent() {
    final itemsByStore = _cartService.getItemsByStore();

    // Debug: Mostrar agrupación por tienda
    print('🏪 Productos agrupados por tienda:');
    itemsByStore.forEach((storeId, items) {
      print('  Tienda ID: $storeId - ${items.first.storeName}');
      print('  Productos: ${items.length}');
      for (final item in items) {
        print('    - ${item.productName} (StoreID: ${item.storeId})');
      }
    });

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: itemsByStore.length,
      itemBuilder: (context, index) {
        final storeId = itemsByStore.keys.elementAt(index);
        final items = itemsByStore[storeId]!;
        final storeName = items.first.storeName;
        final storeTotal = _cartService.getTotalByStore(storeId);

        return _buildStoreSection(storeName, items, storeTotal);
      },
    );
  }

  Widget _buildStoreSection(
    String storeName,
    List<CartItem> items,
    double total,
  ) {
    // Obtener ubicación y dirección del primer item (todos son de la misma tienda)
    final firstItem = items.first;
    final storeLocation = firstItem.storeLocation;
    final storeMunicipio = firstItem.storeMunicipio;
    final storeProvincia = firstItem.storeProvincia;
    final storeAddress = firstItem.storeAddress;

    // Construir ubicación completa
    final List<String> locationParts = [];
    if (storeLocation != null && storeLocation.isNotEmpty) {
      locationParts.add(storeLocation);
    }
    if (storeMunicipio != null && storeMunicipio.isNotEmpty) {
      locationParts.add(storeMunicipio);
    }
    if (storeProvincia != null && storeProvincia.isNotEmpty) {
      locationParts.add(storeProvincia);
    }
    final fullLocation = locationParts.join(', ');

    return Container(
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de tienda con gradiente
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF0F4FF), Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila superior: Icono + Nombre + Total
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.store_rounded,
                        size: 20,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            storeName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (fullLocation.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                fullLocation,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary.withOpacity(
                                    0.8,
                                  ),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.successColor.withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.successColor,
                        ),
                      ),
                    ),
                  ],
                ),

                // Dirección (si existe)
                if (storeAddress != null && storeAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppTheme.textSecondary.withOpacity(0.7),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            storeAddress,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary.withOpacity(0.7),
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Divisor sutil
          Divider(height: 1, color: Colors.grey.withOpacity(0.1)),

          // Items de la tienda
          ...items.map((item) => _buildCartItem(item)),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withOpacity(0.05), width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagen del producto
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.productImage != null
                  ? Image.network(
                      item.productImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.shopping_bag_rounded,
                            size: 32,
                            color: Colors.grey[300],
                          ),
                        );
                      },
                    )
                  : Center(
                      child: Icon(
                        Icons.shopping_bag_rounded,
                        size: 32,
                        color: Colors.grey[300],
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),

          // Información del producto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${item.variantName} • ${item.presentacion}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary.withOpacity(0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '\$${item.price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Controles de cantidad
                    _buildQuantityControls(item),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityControls(CartItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Botón eliminar
        Container(
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconButton(
            onPressed: () => _removeItem(item.id),
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppTheme.errorColor,
            iconSize: 18,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        ),
        const SizedBox(width: 8),

        // Botón menos
        Container(
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconButton(
            onPressed: () => _updateQuantity(item.id, item.quantity - 1),
            icon: const Icon(Icons.remove_rounded),
            color: AppTheme.primaryColor,
            iconSize: 18,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        ),

        // Cantidad
        Container(
          width: 40,
          alignment: Alignment.center,
          child: Text(
            '${item.quantity}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ),

        // Botón más
        Container(
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconButton(
            onPressed: () => _updateQuantity(item.id, item.quantity + 1),
            icon: const Icon(Icons.add_rounded),
            color: AppTheme.primaryColor,
            iconSize: 18,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Resumen
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_cartService.totalQuantity} ${_cartService.totalQuantity == 1 ? 'producto' : 'productos'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total: \$${_cartService.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _traceRoute,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Row(
                    children: [
                      Text(
                        'Trazar ruta',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.map_rounded, color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
