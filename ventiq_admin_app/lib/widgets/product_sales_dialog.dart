import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_service.dart';

class ProductSalesDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final int? storeId;
  final int? localProductId;

  const ProductSalesDialog({
    super.key,
    required this.product,
    this.storeId,
    this.localProductId,
  });

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

  Future<void> _changeLocation() async {
    // Validar que tenemos los datos necesarios
    if (widget.storeId == null || widget.localProductId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se puede cambiar la ubicación: faltan datos del producto. '
              'Por favor, contacta al administrador.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    try {
      final carnavalProductId = widget.product['id'] as int;

      // Mostrar diálogo de selección de ubicación
      final location = await showDialog<Map<String, dynamic>>(
        context: context,
        builder:
            (context) => _LocationSelectionDialog(
              storeId: widget.storeId!,
              productId: widget.localProductId!,
            ),
      );

      if (location == null || !mounted) return; // Usuario canceló

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Actualizar la ubicación del producto
      final success = await CarnavalService.updateProductLocation(
        carnavalProductId: carnavalProductId,
        newLocationId: location['id_ubicacion'],
        localProductId: widget.localProductId!,
      );

      if (mounted) {
        // Cerrar indicador de carga
        Navigator.pop(context);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Ubicación actualizada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
          // Cerrar diálogo y retornar true para refrescar
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Error al actualizar la ubicación'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Cerrar indicador de carga si está abierto
        try {
          Navigator.pop(context);
        } catch (_) {}
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

                  const SizedBox(height: 12),

                  // Ubicación del producto - siempre visible
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          widget.product['almacen'] != null &&
                                  widget.product['ubicacion'] != null
                              ? Colors.grey.shade100
                              : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            widget.product['almacen'] != null &&
                                    widget.product['ubicacion'] != null
                                ? Colors.grey.shade300
                                : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.product['almacen'] != null &&
                                  widget.product['ubicacion'] != null
                              ? Icons.location_on
                              : Icons.location_off,
                          size: 20,
                          color:
                              widget.product['almacen'] != null &&
                                      widget.product['ubicacion'] != null
                                  ? AppColors.primary
                                  : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ubicación',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.product['almacen'] != null &&
                                        widget.product['ubicacion'] != null
                                    ? '${widget.product['almacen']} - ${widget.product['ubicacion']}'
                                    : 'Sin ubicación asignada',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      widget.product['almacen'] != null &&
                                              widget.product['ubicacion'] !=
                                                  null
                                          ? Colors.black
                                          : Colors.orange.shade700,
                                  fontStyle:
                                      widget.product['almacen'] == null ||
                                              widget.product['ubicacion'] ==
                                                  null
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _changeLocation,
                          icon: Icon(
                            widget.product['almacen'] != null &&
                                    widget.product['ubicacion'] != null
                                ? Icons.edit
                                : Icons.add_location,
                            size: 16,
                          ),
                          label: Text(
                            widget.product['almacen'] != null &&
                                    widget.product['ubicacion'] != null
                                ? 'Cambiar'
                                : 'Asignar',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                widget.product['almacen'] != null &&
                                        widget.product['ubicacion'] != null
                                    ? Colors.grey.shade200
                                    : Colors.orange,
                            foregroundColor:
                                widget.product['almacen'] != null &&
                                        widget.product['ubicacion'] != null
                                    ? Colors.black87
                                    : Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
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

// Dialog for selecting product location
class _LocationSelectionDialog extends StatefulWidget {
  final int storeId;
  final int productId;

  const _LocationSelectionDialog({
    required this.storeId,
    required this.productId,
  });

  @override
  State<_LocationSelectionDialog> createState() =>
      __LocationSelectionDialogState();
}

class __LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _locations = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final locations = await CarnavalService.getProductLocations(
        widget.storeId,
        widget.productId,
      );

      if (mounted) {
        setState(() {
          _locations = locations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar ubicaciones: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleccionar Ubicación'),
      content: SizedBox(
        width: double.maxFinite,
        child:
            _isLoading
                ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                )
                : _errorMessage != null
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
                : _locations.isEmpty
                ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No se encontraron ubicaciones para este producto',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
                : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _locations.length,
                  itemBuilder: (context, index) {
                    final location = _locations[index];
                    final stock = location['cantidad_existente'] ?? 0;

                    return ListTile(
                      leading: const Icon(
                        Icons.location_on,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        location['almacen'] ?? 'Sin almacén',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(location['ubicacion'] ?? 'Sin ubicación'),
                          const SizedBox(height: 4),
                          Text(
                            'Stock: $stock',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).pop(location),
                    );
                  },
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
