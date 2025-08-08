import 'package:flutter/material.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

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
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
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
    );
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
    // TODO: Navigate to category products
    _showSelectionFeedback();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _showSelectionFeedback() {
    // Haptic feedback for better UX
    // HapticFeedback.lightImpact(); // Uncomment if you want haptic feedback
    
    // Visual feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Categoría "${widget.name}" seleccionada'),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        backgroundColor: widget.color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: _isPressed 
                        ? widget.color.withOpacity(0.3)
                        : Colors.black.withOpacity(0.08),
                    blurRadius: _isPressed ? 15 : 10,
                    offset: Offset(0, _isPressed ? 2 : 4),
                    spreadRadius: _isPressed ? 2 : 0,
                  ),
                ],
                border: _isPressed 
                    ? Border.all(color: widget.color.withOpacity(0.5), width: 2)
                    : null,
              ),
              child: Column(
                children: [
                  // Image section with enhanced visual feedback
                  Expanded(
                    flex: 3,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            widget.color.withOpacity(_isPressed ? 0.9 : 0.8),
                            widget.color.withOpacity(_isPressed ? 0.7 : 0.6),
                          ],
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        child: Stack(
                          children: [
                            // Enhanced image loading with better fallback
                            Image.network(
                              widget.imageUrl,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        widget.color.withOpacity(0.3),
                                        widget.color.withOpacity(0.1),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _getCategoryIcon(widget.name),
                                          size: 48,
                                          color: widget.color,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          widget.name,
                                          style: TextStyle(
                                            color: widget.color,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        widget.color.withOpacity(0.2),
                                        widget.color.withOpacity(0.1),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: widget.color,
                                      strokeWidth: 3,
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Enhanced gradient overlay with press effect
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    widget.color.withOpacity(_isPressed ? 0.4 : 0.3),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Enhanced text section
                  Expanded(
                    flex: 1,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _isPressed 
                            ? widget.color.withOpacity(0.05)
                            : Colors.white,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          widget.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _isPressed 
                                ? widget.color
                                : const Color(0xFF2C3E50),
                            letterSpacing: 0.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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

// Mock categories with random images from Unsplash
const _mockCategories = <_Category>[
  _Category(
    'Bebidas',
    'https://images.unsplash.com/photo-1544145945-f90425340c7e?w=400&h=300&fit=crop',
    Color(0xFF4A90E2),
  ),
  _Category(
    'Snacks',
    'https://images.unsplash.com/photo-1599490659213-e2b9527bd087?w=400&h=300&fit=crop',
    Color(0xFFE74C3C),
  ),
  _Category(
    'Lácteos',
    'https://images.unsplash.com/photo-1563636619-e9143da7973b?w=400&h=300&fit=crop',
    Color(0xFF2ECC71),
  ),
  _Category(
    'Panadería',
    'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400&h=300&fit=crop',
    Color(0xFFF39C12),
  ),
  _Category(
    'Limpieza',
    'https://images.unsplash.com/photo-1563453392212-326f5e854473?w=400&h=300&fit=crop',
    Color(0xFF9B59B6),
  ),
  _Category(
    'Salud',
    'https://images.unsplash.com/photo-1559757148-5c350d0d3c56?w=400&h=300&fit=crop',
    Color(0xFF1ABC9C),
  ),
];
