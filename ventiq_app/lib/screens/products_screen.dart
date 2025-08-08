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
  List<Product> products = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  void _loadProducts() {
    // Simulando datos de productos para la categoría
    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        products = _generateSampleProducts(widget.categoryName);
        // Orden descendente por denominación (se puede cambiar a precio/stock según preferencia)
        products.sort((a, b) => b.denominacion.compareTo(a.denominacion));
        isLoading = false;
      });
    });
  }

  List<Product> _generateSampleProducts(String category) {
    // Datos de ejemplo basados en la categoría
    final sampleProducts = <Product>[
      Product(
        id: 1,
        denominacion: 'Coca Cola 500ml',
        descripcion: 'Bebida gaseosa refrescante, sabor original. Ideal para acompañar comidas o disfrutar en cualquier momento del día.',
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
            cantidad: 80,
            descripcion: 'Sabor clásico original',
          ),
          ProductVariant(
            id: 2,
            nombre: 'Coca Cola Zero 500ml',
            precio: 2.75,
            cantidad: 70,
            descripcion: 'Sin azúcar, mismo gran sabor',
          ),
        ],
      ),
      Product(
        id: 2,
        denominacion: 'Agua Mineral 1L',
        descripcion: 'Agua mineral natural, purificada y embotellada. Perfecta para hidratación diaria.',
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
        id: 3,
        denominacion: 'Jugo de Naranja 1L',
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
        id: 4,
        denominacion: 'Cerveza Corona 355ml',
        foto: 'https://images.unsplash.com/photo-1608270586620-248524c67de9?w=300&h=300&fit=crop',
        precio: 4.50,
        cantidad: 120,
        esRefrigerado: true,
        esFragil: true,
        esPeligroso: true,
        esVendible: true,
        esComprable: true,
        esInventariable: true,
        esPorLotes: false,
        categoria: category,
      ),
      Product(
        id: 5,
        denominacion: 'Energizante Red Bull',
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
    ];

    return sampleProducts;
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
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
        ),
        child: Column(
          children: [
            // Header con información de la categoría
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: widget.categoryColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Productos disponibles',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: widget.categoryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${products.length} productos encontrados',
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.categoryColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            // Lista de productos
            Expanded(
              child: isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: widget.categoryColor,
                        strokeWidth: 3,
                      ),
                    )
                  : products.isEmpty
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
                              const SizedBox(height: 8),
                              Text(
                                'en esta categoría',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: widget.categoryColor.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            return _ProductCard(
                              product: products[index],
                              categoryColor: widget.categoryColor,
                            );
                          },
                        ),
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
