import 'package:flutter/material.dart';
import '../models/product.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Product product;
  final Color categoryColor;

  const ProductDetailsScreen({
    Key? key,
    required this.product,
    required this.categoryColor,
  }) : super(key: key);

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  ProductVariant? selectedVariant;
  int selectedQuantity = 1;
  Map<ProductVariant, int> variantQuantities = {};

  @override
  void initState() {
    super.initState();
    // Inicializar cantidades de variantes
    for (var variant in widget.product.variantes) {
      variantQuantities[variant] = 0;
    }
  }

  double get totalPrice {
    double total = 0.0;
    
    if (widget.product.variantes.isEmpty) {
      // Producto sin variantes
      total = widget.product.precio * selectedQuantity;
    } else {
      // Producto con variantes
      for (var entry in variantQuantities.entries) {
        total += entry.key.precio * entry.value;
      }
    }
    
    return total;
  }

  int get maxQuantityForProduct {
    return widget.product.cantidad;
  }

  int maxQuantityForVariant(ProductVariant variant) {
    return variant.cantidad;
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
          widget.product.denominacion,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Foto del producto centrada con fondo azul
          Container(
            width: double.infinity,
            height: 250,
            decoration: const BoxDecoration(
              color: Color(0xFF4A90E2),
            ),
            child: Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.1),
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: widget.product.foto != null
                      ? Image.network(
                          widget.product.foto!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.3),
                                    Colors.white.withOpacity(0.1),
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.inventory_2,
                                color: Colors.white,
                                size: 80,
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.2),
                                    Colors.white.withOpacity(0.1),
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.3),
                                Colors.white.withOpacity(0.1),
                              ],
                            ),
                          ),
                          child: const Icon(
                            Icons.inventory_2,
                            color: Colors.white,
                            size: 80,
                          ),
                        ),
                ),
              ),
            ),
          ),
          // Contenido principal con fondo blanco
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              // Agregamos clipBehavior para cortar el contenido que se salga
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre del producto
                    Text(
                      widget.product.denominacion,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Descripción
                    if (widget.product.descripcion != null) ...[
                      Text(
                        widget.product.descripcion!,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[700],
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    // Precio base (si no hay variantes)
                    if (widget.product.variantes.isEmpty) ...[
                      Row(
                        children: [
                          Text(
                            'Precio: ',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            '\$${widget.product.precio.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: widget.categoryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Selector de cantidad para producto sin variantes
                      _buildQuantitySelector(
                        'Cantidad',
                        selectedQuantity,
                        maxQuantityForProduct,
                        (quantity) {
                          setState(() {
                            selectedQuantity = quantity;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                    // Variantes del producto (si existen)
                    if (widget.product.variantes.isNotEmpty) ...[
                      Text(
                        'Variantes disponibles',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: widget.categoryColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...widget.product.variantes.map((variant) => 
                        _buildVariantCard(variant),
                      ).toList(),
                      const SizedBox(height: 24),
                    ],
                    // Total de la compra
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: widget.categoryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: widget.categoryColor.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Total de la compra',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: widget.categoryColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$${totalPrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: widget.categoryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Botón de agregar al carrito
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: totalPrice > 0 ? _addToCart : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.categoryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 3,
                        ),
                        child: const Text(
                          'Agregar al carrito',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantCard(ProductVariant variant) {
    int currentQuantity = variantQuantities[variant] ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: currentQuantity > 0 
              ? widget.categoryColor.withOpacity(0.5)
              : Colors.grey.withOpacity(0.3),
          width: currentQuantity > 0 ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: currentQuantity > 0 
                ? widget.categoryColor.withOpacity(0.1)
                : Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant.nombre,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    if (variant.descripcion != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        variant.descripcion!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '\$${variant.precio.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: widget.categoryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Stock: ${variant.cantidad}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const Spacer(),
              if (currentQuantity > 0) ...[
                Text(
                  'Subtotal: \$${(variant.precio * currentQuantity).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: widget.categoryColor,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _buildQuantitySelector(
            'Cantidad',
            currentQuantity,
            maxQuantityForVariant(variant),
            (quantity) {
              setState(() {
                variantQuantities[variant] = quantity;
              });
            },
          ),
        ],
      ),
    );
  }



  Widget _buildQuantitySelector(
    String label,
    int currentQuantity,
    int maxQuantity,
    Function(int) onQuantityChanged,
  ) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50),
          ),
        ),
        const SizedBox(width: 16),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: currentQuantity > 0 
                    ? () => onQuantityChanged(currentQuantity - 1)
                    : null,
                icon: const Icon(Icons.remove),
                color: widget.categoryColor,
              ),
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: widget.categoryColor.withOpacity(0.1),
                ),
                child: Text(
                  '$currentQuantity',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: widget.categoryColor,
                  ),
                ),
              ),
              IconButton(
                onPressed: currentQuantity < maxQuantity 
                    ? () => onQuantityChanged(currentQuantity + 1)
                    : null,
                icon: const Icon(Icons.add),
                color: widget.categoryColor,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Max: $maxQuantity',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _addToCart() {
    // Aquí implementarías la lógica para agregar al carrito
    String message = '';
    
    if (widget.product.variantes.isEmpty) {
      message = 'Agregado: ${widget.product.denominacion} (x$selectedQuantity)';
    } else {
      List<String> items = [];
      for (var entry in variantQuantities.entries) {
        if (entry.value > 0) {
          items.add('${entry.key.nombre} (x${entry.value})');
        }
      }
      message = items.isNotEmpty 
          ? 'Agregado: ${items.join(', ')}'
          : 'Selecciona al menos una variante';
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: widget.categoryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
