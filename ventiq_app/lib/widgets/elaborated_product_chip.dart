import 'package:flutter/material.dart';
import '../services/product_detail_service.dart';

class ElaboratedProductChip extends StatefulWidget {
  final int productId;
  final String productName;
  final VoidCallback? onTap;

  const ElaboratedProductChip({
    Key? key,
    required this.productId,
    required this.productName,
    this.onTap,
  }) : super(key: key);

  @override
  State<ElaboratedProductChip> createState() => _ElaboratedProductChipState();
}

class _ElaboratedProductChipState extends State<ElaboratedProductChip> {
  final ProductDetailService _productDetailService = ProductDetailService();
  bool _isElaborated = false;
  bool _loading = true;
  List<Map<String, dynamic>> _ingredients = [];

  @override
  void initState() {
    super.initState();
    _checkIfElaborated();
  }

  Future<void> _checkIfElaborated() async {
    try {
      final isElaborated = await _productDetailService.isProductElaborated(widget.productId);
      
      if (isElaborated) {
        final ingredients = await _productDetailService.getProductIngredients(widget.productId);
        setState(() {
          _isElaborated = isElaborated;
          _ingredients = ingredients;
          _loading = false;
        });
      } else {
        setState(() {
          _isElaborated = false;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking if product is elaborated: $e');
      setState(() {
        _isElaborated = false;
        _loading = false;
      });
    }
  }

  void _showIngredientsPreview() {
    if (_ingredients.isNotEmpty) {
      ProductDetailService.showIngredientsPreview(
        context,
        _ingredients,
        widget.productName,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontraron ingredientes para este producto'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[300]!),
        ),
      );
    }

    if (!_isElaborated) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: widget.onTap ?? _showIngredientsPreview,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange[600],
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.3),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.restaurant_menu,
              size: 12,
              color: Colors.white,
            ),
            const SizedBox(width: 2),
            const Text(
              'ELAB',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget builder function for easy integration
class ElaboratedProductChipBuilder extends StatelessWidget {
  final int productId;
  final String productName;
  final Widget child;
  final VoidCallback? onChipTap;

  const ElaboratedProductChipBuilder({
    Key? key,
    required this.productId,
    required this.productName,
    required this.child,
    this.onChipTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: child),
        const SizedBox(width: 8),
        ElaboratedProductChip(
          productId: productId,
          productName: productName,
          onTap: onChipTap,
        ),
      ],
    );
  }
}
