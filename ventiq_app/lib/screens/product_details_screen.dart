import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/order_service.dart';

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color.fromARGB(255, 255, 255, 255), size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.product.denominacion,
          style: const TextStyle(
            color: Color.fromARGB(255, 255, 255, 255),
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sección superior: Imagen y información del producto
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagen del producto
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: widget.product.foto != null
                        ? Image.network(
                            widget.product.foto!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey[100],
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.inventory_2,
                                      color: Colors.grey,
                                      size: 32,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Sin imagen',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: Colors.grey[100],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            },
                          )
                        : Container(
                            color: Colors.grey[100],
                            child: const Icon(
                              Icons.inventory_2,
                              color: Colors.grey,
                              size: 40,
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
                      // Denominación
                      Text(
                        widget.product.denominacion,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Categoría
                      Text(
                        widget.product.categoria,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      // Precio del producto
                      Text(
                        '\$${widget.product.precio.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: widget.categoryColor,
                          height: 1.2,
                        ),
                      ),

                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Sección de variantes
            if (widget.product.variantes.isNotEmpty) ...[
              Text(
                'VARIANTES:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              // Grid de variantes (2 columnas, estilo listado de productos)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 3.5, // Para hacer cards más horizontales
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: widget.product.variantes.length,
                itemBuilder: (context, index) {
                  final variant = widget.product.variantes[index];
                  final isSelected = variantQuantities[variant]! > 0;
                  return _buildVariantProductCard(variant, isSelected);
                },
              ),
              const SizedBox(height: 24),
            ],
            // Productos seleccionados
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Productos seleccionados',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Lista de productos seleccionados
                  if (widget.product.variantes.isEmpty && selectedQuantity > 0)
                    _buildSelectedProductItem(
                      widget.product.denominacion,
                      selectedQuantity,
                      widget.product.precio,
                      'Almacén A-1', // Ubicación por defecto
                    ),
                  if (widget.product.variantes.isNotEmpty)
                    ...variantQuantities.entries
                        .where((entry) => entry.value > 0)
                        .map((entry) => _buildSelectedProductItem(
                              '${widget.product.denominacion} - ${entry.key.nombre}',
                              entry.value,
                              entry.key.precio,
                              'Almacén B-${entry.key.nombre.substring(0, 1)}', // Ubicación generada de la variante
                            )),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Fila con total y botón de agregar
            Row(
              children: [
                // Total de productos seleccionados
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL: ${_getTotalItems()} producto${_getTotalItems() == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        Text(
                          '\$${totalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: widget.categoryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Botón de agregar
                SizedBox(
                  width: 120,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: totalPrice > 0 ? _addToCart : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.categoryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Agregar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }




  // Método para construir cards de variantes estilo listado de productos (2 columnas)
  Widget _buildVariantProductCard(ProductVariant variant, bool isSelected) {
    int currentQuantity = variantQuantities[variant] ?? 0;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (currentQuantity == 0) {
            variantQuantities[variant] = 1;
          } else {
            variantQuantities[variant] = 0;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? widget.categoryColor.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? widget.categoryColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Imagen pequeña de la variante (como en el listado de productos)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Colors.grey[100],
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: const Icon(
                Icons.inventory_2,
                color: Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            // Información de la variante
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nombre de la variante
                  Flexible(
                    child: Text(
                      variant.nombre,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? widget.categoryColor : const Color(0xFF1F2937),
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  const SizedBox(height: 1),
                  // Precio y stock
                  Flexible(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '\$${variant.precio.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: widget.categoryColor,
                              height: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 2,
                          height: 2,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Stock: ${variant.cantidad}',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey[600],
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
          ],
        ),
      ),
    );
  }

  // Método para construir items de productos seleccionados
  Widget _buildSelectedProductItem(String name, int quantity, double price, String ubicacion) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila superior: Nombre del producto y total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.categoryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '\$${(price * quantity).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: widget.categoryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Fila media: Ubicación y precio unitario
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  ubicacion,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Precio: \$${price.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Fila inferior: Controles de cantidad
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cantidad:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[800],
                ),
              ),
              // Controles de cantidad mejorados
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (widget.product.variantes.isEmpty) {
                            if (selectedQuantity > 0) selectedQuantity--;
                          } else {
                            // Buscar la variante correspondiente
                            for (var variant in widget.product.variantes) {
                              if (name.contains(variant.nombre)) {
                                if (variantQuantities[variant]! > 0) {
                                  variantQuantities[variant] = variantQuantities[variant]! - 1;
                                }
                                break;
                              }
                            }
                          }
                        });
                      },
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(7),
                        bottomLeft: Radius.circular(7),
                      ),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: quantity > 0 ? widget.categoryColor.withOpacity(0.1) : Colors.grey[50],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(7),
                            bottomLeft: Radius.circular(7),
                          ),
                        ),
                        child: Icon(
                          Icons.remove,
                          size: 18,
                          color: quantity > 0 ? widget.categoryColor : Colors.grey[400],
                        ),
                      ),
                    ),
                    Container(
                      width: 50,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border: Border.symmetric(
                          vertical: BorderSide(color: Colors.grey[300]!, width: 1),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$quantity',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (widget.product.variantes.isEmpty) {
                            if (selectedQuantity < maxQuantityForProduct) selectedQuantity++;
                          } else {
                            // Buscar la variante correspondiente
                            for (var variant in widget.product.variantes) {
                              if (name.contains(variant.nombre)) {
                                if (variantQuantities[variant]! < variant.cantidad) {
                                  variantQuantities[variant] = variantQuantities[variant]! + 1;
                                }
                                break;
                              }
                            }
                          }
                        });
                      },
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(7),
                        bottomRight: Radius.circular(7),
                      ),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: widget.categoryColor.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(7),
                            bottomRight: Radius.circular(7),
                          ),
                        ),
                        child: Icon(
                          Icons.add,
                          size: 18,
                          color: widget.categoryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Método para obtener el total de items
  int _getTotalItems() {
    int total = 0;
    if (widget.product.variantes.isEmpty) {
      total = selectedQuantity;
    } else {
      for (var quantity in variantQuantities.values) {
        total += quantity;
      }
    }
    return total;
  }

  void _addToCart() {
    final orderService = OrderService();
    int totalItemsAdded = 0;
    List<String> addedItems = [];

    try {
      if (widget.product.variantes.isEmpty) {
        // Producto sin variantes
        if (selectedQuantity > 0) {
          orderService.addItemToCurrentOrder(
            producto: widget.product,
            cantidad: selectedQuantity,
            ubicacionAlmacen: 'Almacén A-1',
          );
          totalItemsAdded += selectedQuantity;
          addedItems.add('${widget.product.denominacion} (x$selectedQuantity)');
          
          // Resetear cantidad después de agregar
          setState(() {
            selectedQuantity = 0;
          });
        }
      } else {
        // Producto con variantes
        for (var entry in variantQuantities.entries) {
          if (entry.value > 0) {
            orderService.addItemToCurrentOrder(
              producto: widget.product,
              variante: entry.key,
              cantidad: entry.value,
              ubicacionAlmacen: 'Almacén B-${entry.key.nombre.substring(0, 1)}',
            );
            totalItemsAdded += entry.value;
            addedItems.add('${entry.key.nombre} (x${entry.value})');
          }
        }
        
        // Resetear cantidades después de agregar
        setState(() {
          for (var variant in widget.product.variantes) {
            variantQuantities[variant] = 0;
          }
        });
      }

      // Mostrar mensaje de éxito
      if (totalItemsAdded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✅ Agregado a la orden',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  addedItems.join('\n'),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total en orden: ${orderService.currentOrderItemCount} productos',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
            backgroundColor: widget.categoryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Ver Orden',
              textColor: Colors.white,
              onPressed: () {
                // TODO: Navegar a la pantalla de orden
                Navigator.pushNamed(context, '/preorder');
              },
            ),
          ),
        );
      } else {
        // No hay items seleccionados
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⚠️ Selecciona al menos un producto o variante'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Manejo de errores
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al agregar: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
