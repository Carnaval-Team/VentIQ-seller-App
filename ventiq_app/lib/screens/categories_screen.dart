import 'package:flutter/material.dart';
import 'products_screen.dart';
import '../widgets/bottom_navigation.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  @override
  Widget build(BuildContext context) {
    final categories = _mockCategories;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Categorías',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            return _CategoryCard(
              name: cat.name,
              imageUrl: cat.imageUrl,
              color: cat.color,
            );
          },
        ),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0, // Home tab
        onTap: _onBottomNavTap,
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home (current)
        break;
      case 1: // Preorden
        Navigator.pushNamed(context, '/preorder');
        break;
      case 2: // Órdenes
        Navigator.pushNamed(context, '/orders');
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}

class _CategoryCard extends StatefulWidget {
  final String name;
  final String imageUrl;
  final Color color;
  
  const _CategoryCard({
    required this.name,
    required this.imageUrl,
    required this.color,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> with SingleTickerProviderStateMixin {
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
    // Navigate to products list for this category
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductsScreen(
          categoryName: widget.name,
          categoryColor: widget.color,
        ),
      ),
    );
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            child: Container(
              decoration: BoxDecoration(
                color: _isPressed 
                    ? widget.color.withOpacity(0.8)
                    : widget.color,
                border: Border(
                  right: const BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                  bottom: const BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                ),
              ),
              child: Stack(
                children: [
                  // Large rotated image behind text (bottom-right area)
                  Positioned(
                    bottom: 0,
                    right: -15,
                    child: Transform.rotate(
                      angle: -0.2, // Slight rotation (about 11 degrees)
                      child: Container(
                        width: 220,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(1),
                          child: Image.network(
                            widget.imageUrl,
                            width: 120,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getCategoryIcon(widget.name),
                                  size: 40,
                                  color: Colors.white,
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Category name in top-left corner (on top of image)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Text(
                      widget.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 3,
                            color: Colors.black26,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'bebidas':
        return Icons.local_drink;
      case 'snacks':
        return Icons.fastfood;
      case 'lácteos':
        return Icons.icecream;
      case 'panadería':
        return Icons.bakery_dining;
      case 'limpieza':
        return Icons.cleaning_services;
      case 'salud':
        return Icons.health_and_safety;
      default:
        return Icons.category;
    }
  }
}

class _Category {
  final String name;
  final String imageUrl;
  final Color color;
  
  const _Category(this.name, this.imageUrl, this.color);
}

// Mock categories with vibrant colors matching the reference design
const _mockCategories = <_Category>[
  _Category(
    'Bebidas',
    'https://images.unsplash.com/photo-1544145945-f90425340c7e?w=400&h=300&fit=crop',
    Color(0xFFE53E3E), // Vibrant red
  ),
  _Category(
    'Snacks',
    'https://images.unsplash.com/photo-1599490659213-e2b9527bd087?w=400&h=300&fit=crop',
    Color(0xFF6B46C1), // Vibrant purple
  ),
  _Category(
    'Lácteos',
    'https://images.unsplash.com/photo-1563636619-e9143da7973b?w=400&h=300&fit=crop',
    Color(0xFF059669), // Vibrant green
  ),
  _Category(
    'Panadería',
    'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400&h=300&fit=crop',
    Color(0xFFEA580C), // Vibrant orange
  ),
  _Category(
    'Limpieza',
    'https://images.unsplash.com/photo-1563453392212-326f5e854473?w=400&h=300&fit=crop',
    Color(0xFF0891B2), // Vibrant cyan
  ),
  _Category(
    'Salud',
    'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=400&h=300&fit=crop',
    Color(0xFFDC2626), // Vibrant red variant
  ),
];
