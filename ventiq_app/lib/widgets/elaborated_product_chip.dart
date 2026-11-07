import 'package:flutter/material.dart';
import '../services/product_detail_service.dart';
import '../utils/app_snackbar.dart';

class ElaboratedProductChip extends StatefulWidget {
  final int productId;
  final String productName;
  final VoidCallback? onTap;

  /// `es_elaborado` / `es_servicio` ya resueltos por el detalle del producto.
  ///
  /// Si vienen, el chip se pinta **sin red** y los ingredientes solo se
  /// consultan al tocarlo (R14 del plan). Si no vienen (usos antiguos), se
  /// mantiene la comprobación al montar.
  final bool? esElaborado;
  final bool? esServicio;

  const ElaboratedProductChip({
    Key? key,
    required this.productId,
    required this.productName,
    this.onTap,
    this.esElaborado,
    this.esServicio,
  }) : super(key: key);

  @override
  State<ElaboratedProductChip> createState() => _ElaboratedProductChipState();
}

class _ElaboratedProductChipState extends State<ElaboratedProductChip> {
  // Perezoso: con los flags ya resueltos ni siquiera se crea el servicio, así
  // el chip no toca Supabase al montarse (R14).
  ProductDetailService? _servicio;
  ProductDetailService get _productDetailService =>
      _servicio ??= ProductDetailService();

  bool _isElaborated = false;
  bool _isServicio = false;
  bool _loading = true;
  bool _cargandoIngredientes = false;
  List<Map<String, dynamic>> _ingredients = [];

  @override
  void initState() {
    super.initState();
    if (widget.esElaborado != null) {
      // Camino perezoso: cero llamadas al montar.
      _isElaborated = widget.esElaborado!;
      _isServicio = widget.esServicio ?? false;
      _loading = false;
    } else {
      _checkIfElaborated();
    }
  }

  Future<void> _checkIfElaborated() async {
    try {
      final isElaborated = await _productDetailService.isProductElaborated(
        widget.productId,
      );

      if (isElaborated) {
        final isServicio = await _productDetailService.isProductServicio(
          widget.productId,
        );
        final ingredients =
            isServicio
                ? <Map<String, dynamic>>[]
                : await _productDetailService.getProductIngredients(
                  widget.productId,
                );
        setState(() {
          _isElaborated = true;
          _isServicio = isServicio;
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

  Future<void> _showIngredientsPreview() async {
    if (_cargandoIngredientes) return;

    // Camino perezoso: los ingredientes se piden AHORA, no al montar el chip.
    if (_ingredients.isEmpty) {
      setState(() => _cargandoIngredientes = true);
      try {
        final List<Map<String, dynamic>> cargados = await _productDetailService
            .getProductIngredients(widget.productId);
        if (!mounted) return;
        _ingredients = cargados;
      } catch (e) {
        debugPrint(
          'Error cargando ingredientes del producto ${widget.productId}: $e',
        );
      } finally {
        if (mounted) setState(() => _cargandoIngredientes = false);
      }
    }

    if (!mounted) return;

    if (_ingredients.isNotEmpty) {
      ProductDetailService.showIngredientsPreview(
        context,
        _ingredients,
        widget.productName,
      );
    } else {
      AppSnackBar.showPersistent(
        context,
        message: 'No se encontraron ingredientes para este producto',
        backgroundColor: Colors.orange,
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

    final chipColor = _isServicio ? Colors.blue[600]! : Colors.orange[600]!;
    final chipIcon =
        _isServicio ? Icons.miscellaneous_services : Icons.restaurant_menu;
    final chipLabel = _isServicio ? 'SERV' : 'ELAB';

    return GestureDetector(
      onTap: _isServicio ? null : (widget.onTap ?? _showIngredientsPreview),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: chipColor.withOpacity(0.3),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(chipIcon, size: 12, color: Colors.white),
            const SizedBox(width: 2),
            Text(
              chipLabel,
              style: const TextStyle(
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
  final bool? esElaborado;
  final bool? esServicio;

  const ElaboratedProductChipBuilder({
    Key? key,
    required this.productId,
    required this.productName,
    required this.child,
    this.onChipTap,
    this.esElaborado,
    this.esServicio,
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
          esElaborado: esElaborado,
          esServicio: esServicio,
        ),
      ],
    );
  }
}
