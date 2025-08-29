import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import 'product_details_screen.dart';
import '../widgets/bottom_navigation.dart';

class ProductsScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final Color categoryColor;

  const ProductsScreen({
    Key? key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
  }) : super(key: key);

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  Map<String, List<Product>> productsBySubcategory = {};
  bool isLoading = true;
  String? errorMessage;
  final ProductService _productService = ProductService();
  
  // Cache para evitar peticiones frecuentes
  static final Map<int, Map<String, List<Product>>> _productsCache = {};
  static final Map<int, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiration = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  void _loadProducts({bool forceRefresh = false}) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      // Verificar caché si no es refresh forzado
      if (!forceRefresh && _isCacheValid(widget.categoryId)) {
        setState(() {
          productsBySubcategory = _productsCache[widget.categoryId]!;
          isLoading = false;
        });
        return;
      }

      final products = await _productService.getProductsByCategory(widget.categoryId);
      
      // Guardar en caché
      _productsCache[widget.categoryId] = products;
      _cacheTimestamps[widget.categoryId] = DateTime.now();
      
      setState(() {
        productsBySubcategory = products;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error al cargar productos: $e';
        isLoading = false;
      });
    }
  }
  
  bool _isCacheValid(int categoryId) {
    if (!_productsCache.containsKey(categoryId) || !_cacheTimestamps.containsKey(categoryId)) {
      return false;
    }
    
    final cacheTime = _cacheTimestamps[categoryId]!;
    final now = DateTime.now();
    return now.difference(cacheTime) < _cacheExpiration;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A90E2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.categoryName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0, // No tab selected since this is a detail screen
        onTap: _onBottomNavTap,
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F9FA),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: widget.categoryColor,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cargando productos...',
                      style: TextStyle(
                        fontSize: 16,
                        color: widget.categoryColor,
                      ),
                    ),
                  ],
                ),
              )
            : errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 80,
                          color: Colors.red.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          errorMessage!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _loadProducts(forceRefresh: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: widget.categoryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : productsBySubcategory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 80,
                              color: widget.categoryColor.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No hay productos disponibles',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: widget.categoryColor,
                              ),
                            ),
                          ],
                        ),
                      )
                : RefreshIndicator(
                    onRefresh: () async => _loadProducts(forceRefresh: true),
                    color: widget.categoryColor,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      itemCount: productsBySubcategory.keys.length,
                      itemBuilder: (context, index) {
                        final subcategory = productsBySubcategory.keys.elementAt(index);
                        final products = productsBySubcategory[subcategory]!;
                        return _SubcategorySection(
                          title: subcategory,
                          products: products,
                          categoryColor: widget.categoryColor,
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home (Categorías)
        Navigator.popUntil(context, (route) => route.isFirst);
        break;
      case 1: // Preorden
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/preorder');
        break;
      case 2: // Órdenes
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/orders');
        break;
      case 3: // Configuración
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}

// Nueva clase para las secciones de subcategorías al estilo Google Play Store
class _SubcategorySection extends StatelessWidget {
  final String title;
  final List<Product> products;
  final Color categoryColor;

  const _SubcategorySection({
    required this.title,
    required this.products,
    required this.categoryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título de la subcategoría
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
              ),
              TextButton(
                onPressed: () {
                  // TODO: Navegar a ver todos los productos de esta subcategoría
                },
                child: const Text(
                  'Ver más',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Lista horizontal de productos optimizada para espaciado
        _buildProductsList(),
        const SizedBox(height: 24), // Espaciado entre secciones
      ],
    );
  }

  Widget _buildProductsList() {
    // Si hay 3 o menos productos, mostrar en una sola columna sin espacios extra
    if (products.length <= 3) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: products.asMap().entries.map((entry) {
            final index = entry.key;
            final product = entry.value;
            return Container(
              margin: EdgeInsets.only(
                bottom: index < products.length - 1 ? 6 : 0,
              ),
              child: _PlayStoreProductCard(
                product: product,
                categoryColor: categoryColor,
              ),
            );
          }).toList(),
        ),
      );
    }

    // Para más de 3 productos, usar el layout horizontal original
    return SizedBox(
      height: 252, // Altura optimizada: 3 productos (80px) + espaciado (6px entre cards)
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: (products.length / 3).ceil(), // Número de columnas de 3 productos
        itemBuilder: (context, columnIndex) {
          // Calcular productos para esta columna
          final startIndex = columnIndex * 3;
          final endIndex = (startIndex + 3).clamp(0, products.length);
          final columnProducts = products.sublist(startIndex, endIndex);
          
          return Container(
            width: MediaQuery.of(context).size.width * 0.85, // 85% del ancho
            margin: const EdgeInsets.only(right: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: columnProducts.asMap().entries.map((entry) {
                final index = entry.key;
                final product = entry.value;
                return Container(
                  margin: EdgeInsets.only(
                    bottom: index < columnProducts.length - 1 ? 6 : 0, // Solo espaciado entre cards, no al final
                  ),
                  child: _PlayStoreProductCard(
                    product: product,
                    categoryColor: categoryColor,
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

// Nueva clase para las cards de producto al estilo Google Play Store
class _PlayStoreProductCard extends StatefulWidget {
  final Product product;
  final Color categoryColor;

  const _PlayStoreProductCard({
    required this.product,
    required this.categoryColor,
  });

  @override
  State<_PlayStoreProductCard> createState() => _PlayStoreProductCardState();
}

class _PlayStoreProductCardState extends State<_PlayStoreProductCard> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailsScreen(
              product: widget.product,
              categoryColor: widget.categoryColor,
            ),
          ),
        );
      },
      child: Container(
        height: 80, // Altura fija como Google Play Store
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Imagen del producto (pequeña, como icono de app)
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.product.foto ?? '',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: Icon(
                        Icons.shopping_bag,
                        size: 24,
                        color: Colors.grey[400],
                      ),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Información del producto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nombre del producto
                  Flexible(
                    child: Text(
                      widget.product.denominacion,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1F2937),
                        height: 1.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Descripción/Categoría
                  Flexible(
                    child: Text(
                      widget.product.descripcion ?? widget.product.categoria,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Precio y rating/stock
                  Flexible(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '\$${widget.product.precio.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: widget.categoryColor,
                              height: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Separador
                        Container(
                          width: 3,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Estado de stock
                        Flexible(
                          child: Text(
                            widget.product.cantidad > 0 ? 'Stock: ${widget.product.cantidad}' : 'Agotado',
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.product.cantidad > 0
                                  ? Colors.green[600]
                                  : Colors.red[600],
                              height: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Botón de acción (opcional, como en Play Store)
            Icon(
              Icons.more_vert,
              color: Colors.grey[400],
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatefulWidget {
  final Product product;
  final Color categoryColor;

  const _ProductCard({
    required this.product,
    required this.categoryColor,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _animationController.reverse();
    _onProductTap();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _onProductTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailsScreen(
          product: widget.product,
          categoryColor: widget.categoryColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _isPressed 
                          ? widget.categoryColor.withOpacity(0.3)
                          : Colors.black.withOpacity(0.08),
                      blurRadius: _isPressed ? 15 : 10,
                      offset: Offset(0, _isPressed ? 2 : 4),
                      spreadRadius: _isPressed ? 2 : 0,
                    ),
                  ],
                  border: _isPressed 
                      ? Border.all(color: widget.categoryColor.withOpacity(0.5), width: 2)
                      : null,
                ),
                child: Row(
                  children: [
                    // Foto del producto - más compacta
                    Container(
                      width: 75,
                      height: 75,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: widget.categoryColor.withOpacity(0.1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: widget.product.foto != null
                            ? Image.network(
                                widget.product.foto!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          widget.categoryColor.withOpacity(0.3),
                                          widget.categoryColor.withOpacity(0.1),
                                        ],
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.inventory_2,
                                      color: widget.categoryColor,
                                      size: 32,
                                    ),
                                  );
                                },
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          widget.categoryColor.withOpacity(0.2),
                                          widget.categoryColor.withOpacity(0.1),
                                        ],
                                      ),
                                    ),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: widget.categoryColor,
                                        strokeWidth: 2,
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      widget.categoryColor.withOpacity(0.3),
                                      widget.categoryColor.withOpacity(0.1),
                                    ],
                                  ),
                                ),
                                child: Icon(
                                  Icons.inventory_2,
                                  color: widget.categoryColor,
                                  size: 32,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Información del producto
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Denominación
                          Text(
                            widget.product.denominacion,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C3E50),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // Cantidad y precio
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: widget.categoryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Stock: ${widget.product.cantidad}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.categoryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '\$${widget.product.precio.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: widget.categoryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Iconos de propiedades
                          Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            children: [
                              if (widget.product.esRefrigerado)
                                _PropertyIcon(
                                  icon: Icons.ac_unit,
                                  color: Colors.blue,
                                  tooltip: 'Refrigerado',
                                ),
                              if (widget.product.esFragil)
                                _PropertyIcon(
                                  icon: Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                  tooltip: 'Frágil',
                                ),
                              if (widget.product.esPeligroso)
                                _PropertyIcon(
                                  icon: Icons.dangerous,
                                  color: Colors.red,
                                  tooltip: 'Peligroso',
                                ),
                              if (widget.product.esVendible)
                                _PropertyIcon(
                                  icon: Icons.sell,
                                  color: Colors.green,
                                  tooltip: 'Vendible',
                                ),
                              if (widget.product.esComprable)
                                _PropertyIcon(
                                  icon: Icons.shopping_cart,
                                  color: Colors.purple,
                                  tooltip: 'Comprable',
                                ),
                              if (widget.product.esInventariable)
                                _PropertyIcon(
                                  icon: Icons.inventory,
                                  color: Colors.teal,
                                  tooltip: 'Inventariable',
                                ),
                              if (widget.product.esPorLotes)
                                _PropertyIcon(
                                  icon: Icons.batch_prediction,
                                  color: Colors.brown,
                                  tooltip: 'Por lotes',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PropertyIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;

  const _PropertyIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Icon(
          icon,
          size: 14,
          color: color,
        ),
      ),
    );
  }
}
