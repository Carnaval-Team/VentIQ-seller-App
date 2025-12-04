import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_service.dart';

class ProductSalesDialog extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductSalesDialog({super.key, required this.product});

  @override
  State<ProductSalesDialog> createState() => _ProductSalesDialogState();
}

class _ProductSalesDialogState extends State<ProductSalesDialog> {
  bool _isLoading = true;
  double _totalSales = 0;
  double _totalCancelled = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final productId = widget.product['id'] as int;

      // Cargar estadísticas en paralelo
      final results = await Future.wait([
        CarnavalService.getProductSalesStats(productId),
        CarnavalService.getProductCancelledStats(productId),
      ]);

      setState(() {
        _totalSales = results[0];
        _totalCancelled = results[1];
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error al cargar estadísticas: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleProductVisibility() async {
    final isActive = widget.product['status'] == true;

    // Mostrar diálogo de confirmación
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  isActive ? Icons.warning : Icons.info,
                  color: isActive ? Colors.orange : Colors.blue,
                ),
                const SizedBox(width: 8),
                const Text('Confirmar'),
              ],
            ),
            content: Text(
              isActive
                  ? '¿Estás seguro de que deseas ocultar este producto de Carnaval App?\n\n'
                      'Los clientes no podrán verlo ni comprarlo.'
                  : '¿Estás seguro de que deseas mostrar este producto en Carnaval App?\n\n'
                      'Los clientes podrán verlo y comprarlo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? Colors.red : Colors.green,
                ),
                child: Text(isActive ? 'Ocultar' : 'Mostrar'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    // Mostrar indicador de carga
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final productId = widget.product['id'] as int;
      final success =
          isActive
              ? await CarnavalService.hideProductFromCarnaval(productId)
              : await CarnavalService.showProductInCarnaval(productId);

      if (mounted) {
        // Cerrar indicador de carga
        Navigator.pop(context);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isActive
                    ? '✅ Producto ocultado de Carnaval'
                    : '✅ Producto mostrado en Carnaval',
              ),
              backgroundColor: Colors.green,
            ),
          );
          // Cerrar diálogo y retornar true para refrescar lista
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isActive
                    ? '❌ Error al ocultar producto'
                    : '❌ Error al mostrar producto',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Cerrar indicador de carga
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header con imagen del producto
            Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                image:
                    widget.product['image'] != null
                        ? DecorationImage(
                          image: NetworkImage(widget.product['image']),
                          fit: BoxFit.cover,
                        )
                        : null,
                color: Colors.grey.shade200,
              ),
              child:
                  widget.product['image'] == null
                      ? const Center(
                        child: Icon(
                          Icons.inventory_2,
                          size: 60,
                          color: Colors.grey,
                        ),
                      )
                      : null,
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre del producto
                  Text(
                    widget.product['name'] ?? 'Sin nombre',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Precio
                  Text(
                    'Precio: \$${widget.product['price']?.toStringAsFixed(2) ?? '0.00'}',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Estadísticas
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else ...[
                    const Text(
                      'Estadísticas de Ventas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Total de ventas
                    _buildStatCard(
                      icon: Icons.trending_up,
                      iconColor: Colors.green,
                      title: 'Total Ventas Completadas',
                      value: '\$${_totalSales.toStringAsFixed(2)}',
                      backgroundColor: Colors.green.shade50,
                    ),

                    const SizedBox(height: 12),

                    // Total de cancelaciones
                    _buildStatCard(
                      icon: Icons.cancel,
                      iconColor: Colors.red,
                      title: 'Total Pedidos Cancelados',
                      value: '\$${_totalCancelled.toStringAsFixed(2)}',
                      backgroundColor: Colors.red.shade50,
                    ),

                    const SizedBox(height: 20),

                    // Botón para ocultar/mostrar producto
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _toggleProductVisibility,
                        icon: Icon(
                          widget.product['status'] == true
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 18,
                        ),
                        label: Text(
                          widget.product['status'] == true
                              ? 'No mostrar en Carnaval'
                              : 'Mostrar en Carnaval',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              widget.product['status'] == true
                                  ? Colors.red
                                  : Colors.green,
                          side: BorderSide(
                            color:
                                widget.product['status'] == true
                                    ? Colors.red.shade300
                                    : Colors.green.shade300,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Botón cerrar
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cerrar'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
