import 'package:flutter/material.dart';
import '../models/product.dart';
import 'product_details_screen.dart';

class ProductsScreen extends StatefulWidget {
  final String categoryName;
  final Color categoryColor;

  const ProductsScreen({
    Key? key,
    required this.categoryName,
    required this.categoryColor,
  }) : super(key: key);

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  Map<String, List<Product>> productsBySubcategory = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  void _loadProducts() {
    // Simulando datos de productos organizados por subcategorías
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        productsBySubcategory = _generateProductsBySubcategory(widget.categoryName);
        isLoading = false;
      });
    });
  }

  Map<String, List<Product>> _generateProductsBySubcategory(String category) {
    // Datos organizados por subcategorías al estilo Google Play Store
    final productsBySubcategory = <String, List<Product>>{
      'Bebidas': [
        Product(
          id: 1,
          denominacion: 'Coca Cola 500ml',
          descripcion: 'Bebida gaseosa refrescante, sabor original.',
          foto: 'https://images.unsplash.com/photo-1581636625402-29b2a704ef13?w=300&h=300&fit=crop',
          precio: 2.50,
          cantidad: 150,
          esRefrigerado: true,
          esFragil: true,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
          variantes: [
            ProductVariant(
              id: 1,
              nombre: 'Coca Cola Original 500ml',
              precio: 2.50,
              cantidad: 50,
              descripcion: 'Sabor clásico original',
            ),
            ProductVariant(
              id: 2,
              nombre: 'Coca Cola Zero 500ml',
              precio: 2.75,
              cantidad: 35,
              descripcion: 'Sin azúcar, mismo sabor',
            ),
            ProductVariant(
              id: 3,
              nombre: 'Coca Cola Light 500ml',
              precio: 2.60,
              cantidad: 40,
              descripcion: 'Baja en calorías',
            ),
            ProductVariant(
              id: 4,
              nombre: 'Coca Cola Cherry 500ml',
              precio: 3.00,
              cantidad: 25,
              descripcion: 'Sabor cereza',
            ),
          ],
        ),
        Product(
          id: 2,
          denominacion: 'Pepsi 500ml',
          descripcion: 'Bebida cola refrescante.',
          foto: 'https://images.unsplash.com/photo-1629203851122-3726ecdf080e?w=300&h=300&fit=crop',
          precio: 2.25,
          cantidad: 120,
          esRefrigerado: true,
          esFragil: true,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
          variantes: [
            ProductVariant(
              id: 5,
              nombre: 'Pepsi Original 500ml',
              precio: 2.25,
              cantidad: 45,
              descripcion: 'Cola refrescante clásica',
            ),
            ProductVariant(
              id: 6,
              nombre: 'Pepsi Max 500ml',
              precio: 2.50,
              cantidad: 30,
              descripcion: 'Sin azúcar, máximo sabor',
            ),
            ProductVariant(
              id: 7,
              nombre: 'Pepsi Light 500ml',
              precio: 2.40,
              cantidad: 25,
              descripcion: 'Menos calorías',
            ),
            ProductVariant(
              id: 8,
              nombre: 'Pepsi Twist 500ml',
              precio: 2.80,
              cantidad: 20,
              descripcion: 'Con sabor a limón',
            ),
          ],
        ),
        Product(
          id: 3,
          denominacion: 'Sprite 500ml',
          descripcion: 'Bebida de lima-limón.',
          foto: 'https://images.unsplash.com/photo-1625772452859-1c03d5bf1137?w=300&h=300&fit=crop',
          precio: 2.30,
          cantidad: 100,
          esRefrigerado: true,
          esFragil: true,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
        ),
        Product(
          id: 89,
          denominacion: 'Coca Cola 500ml',
          descripcion: 'Bebida gaseosa refrescante, sabor original.',
          foto: 'https://images.unsplash.com/photo-1581636625402-29b2a704ef13?w=300&h=300&fit=crop',
          precio: 2.50,
          cantidad: 150,
          esRefrigerado: true,
          esFragil: true,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
        ),
      ],
      'Subcategoria 1': [
        Product(
          id: 4,
          denominacion: 'Agua Mineral 1L',
          descripcion: 'Agua mineral natural purificada.',
          foto: 'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=300&h=300&fit=crop',
          precio: 1.25,
          cantidad: 200,
          esRefrigerado: false,
          esFragil: false,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: true,
          categoria: category,
        ),
        Product(
          id: 5,
          denominacion: 'Jugo de Naranja 1L',
          descripcion: 'Jugo natural de naranja.',
          foto: 'https://images.unsplash.com/photo-1621506289937-a8e4df240d0b?w=300&h=300&fit=crop',
          precio: 3.75,
          cantidad: 85,
          esRefrigerado: true,
          esFragil: true,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
        ),
        Product(
          id: 6,
          denominacion: 'Té Helado 500ml',
          descripcion: 'Té helado sabor limón.',
          foto: 'https://images.unsplash.com/photo-1556679343-c7306c1976bc?w=300&h=300&fit=crop',
          precio: 2.00,
          cantidad: 90,
          esRefrigerado: true,
          esFragil: false,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
        ),
      ],
      'Nuevos productos': [
        Product(
          id: 7,
          denominacion: 'Energizante Red Bull',
          descripcion: 'Bebida energizante premium.',
          foto: 'https://images.unsplash.com/photo-1622543925917-763c34d1a86e?w=300&h=300&fit=crop',
          precio: 6.25,
          cantidad: 60,
          esRefrigerado: true,
          esFragil: false,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
        ),
        Product(
          id: 8,
          denominacion: 'Monster Energy',
          descripcion: 'Bebida energética sabor original.',
          foto: 'https://images.unsplash.com/photo-1571934811356-5cc061b6821f?w=300&h=300&fit=crop',
          precio: 5.50,
          cantidad: 45,
          esRefrigerado: true,
          esFragil: false,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
        ),
        Product(
          id: 9,
          denominacion: 'Gatorade 500ml',
          descripcion: 'Bebida deportiva hidratante.',
          foto: 'https://images.unsplash.com/photo-1594736797933-d0401ba2fe65?w=300&h=300&fit=crop',
          precio: 3.25,
          cantidad: 75,
          esRefrigerado: true,
          esFragil: false,
          esPeligroso: false,
          esVendible: true,
          esComprable: true,
          esInventariable: true,
          esPorLotes: false,
          categoria: category,
        ),
      ],
    };

    return productsBySubcategory;
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
                child: CircularProgressIndicator(
                  color: widget.categoryColor,
                  strokeWidth: 3,
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
                : ListView.builder(
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
    );
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
        // Lista horizontal de productos (máximo 3 visibles con scroll)
        SizedBox(
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
        ),
        const SizedBox(height: 24), // Espaciado entre secciones
      ],
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
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1F2937),
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(height: 1),
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
                              fontSize: 13,
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
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Estado de stock
                        Flexible(
                          child: Text(
                            widget.product.cantidad > 0 ? 'En Stock' : 'Agotado',
                            style: TextStyle(
                              fontSize: 11,
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
