import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';

class DetalleContratoConsignacionScreen extends StatefulWidget {
  final Map<String, dynamic> contrato;

  const DetalleContratoConsignacionScreen({
    Key? key,
    required this.contrato,
  }) : super(key: key);

  @override
  State<DetalleContratoConsignacionScreen> createState() =>
      _DetalleContratoConsignacionScreenState();
}

class _DetalleContratoConsignacionScreenState
    extends State<DetalleContratoConsignacionScreen> {
  List<Map<String, dynamic>> _productos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProductos();
  }

  Future<void> _loadProductos() async {
    setState(() => _isLoading = true);

    try {
      final productos =
          await ConsignacionService.getProductosConsignacion(widget.contrato['id']);
      setState(() {
        _productos = productos;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando productos: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esConsignadora =
        widget.contrato['id_tienda_consignadora'] == widget.contrato['id_tienda_actual'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Contrato'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Información del contrato
                  _buildContratoInfo(),

                  // Productos en consignación
                  _buildProductosSection(esConsignadora),
                ],
              ),
            ),
    );
  }

  Widget _buildContratoInfo() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.handshake,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Información del Contrato',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ID: ${widget.contrato['id']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tiendas
            _buildInfoRow(
              'Tienda Consignadora:',
              widget.contrato['tienda_consignadora']['denominacion'],
              Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              'Tienda Consignataria:',
              widget.contrato['tienda_consignataria']['denominacion'],
              Colors.green,
            ),
            const SizedBox(height: 12),

            // Comisión y plazo
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'Comisión',
                    '${widget.contrato['porcentaje_comision']}%',
                    Icons.percent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoBox(
                    'Plazo',
                    widget.contrato['plazo_dias'] != null
                        ? '${widget.contrato['plazo_dias']} días'
                        : 'Sin límite',
                    Icons.calendar_today,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Fechas
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'Inicio',
                    widget.contrato['fecha_inicio'] ?? 'N/A',
                    Icons.event_available,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoBox(
                    'Fin',
                    widget.contrato['fecha_fin'] ?? 'Sin fecha',
                    Icons.event,
                  ),
                ),
              ],
            ),

            // Condiciones
            if (widget.contrato['condiciones'] != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Condiciones:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.contrato['condiciones'],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductosSection(bool esConsignadora) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Productos en Consignación',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_productos.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_productos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No hay productos en consignación',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _productos.length,
              itemBuilder: (context, index) {
                final prod = _productos[index];
                return _buildProductoCard(prod, esConsignadora);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProductoCard(Map<String, dynamic> producto, bool esConsignadora) {
    final cantidadDisponible = (producto['cantidad_enviada'] as num).toDouble() -
        (producto['cantidad_vendida'] as num).toDouble() -
        (producto['cantidad_devuelta'] as num).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre del producto
            Text(
              producto['producto']['denominacion'],
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'SKU: ${producto['producto']['sku'] ?? 'N/A'}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),

            // Cantidades
            Row(
              children: [
                Expanded(
                  child: _buildCantidadBox(
                    'Enviada',
                    '${producto['cantidad_enviada']}',
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCantidadBox(
                    'Vendida',
                    '${producto['cantidad_vendida']}',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCantidadBox(
                    'Devuelta',
                    '${producto['cantidad_devuelta']}',
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCantidadBox(
                    'Disponible',
                    '$cantidadDisponible',
                    cantidadDisponible > 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Precio sugerido
            if (producto['precio_venta_sugerido'] != null)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.attach_money, size: 16, color: Colors.purple),
                    const SizedBox(width: 6),
                    Text(
                      'Precio sugerido: \$${producto['precio_venta_sugerido']}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Botones de acción
            if (esConsignadora)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _mostrarDialogoVenta(producto),
                      icon: const Icon(Icons.shopping_cart, size: 18),
                      label: const Text('Registrar Venta'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _mostrarDialogoDevolucion(producto),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Registrar Devolución'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
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

  Widget _buildCantidadBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoVenta(Map<String, dynamic> producto) {
    final cantidadDisponible = (producto['cantidad_enviada'] as num).toDouble() -
        (producto['cantidad_vendida'] as num).toDouble() -
        (producto['cantidad_devuelta'] as num).toDouble();

    final cantidadController = TextEditingController();
    final precioController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Venta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Producto: ${producto['producto']['denominacion']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Stock disponible: $cantidadDisponible',
              style: TextStyle(
                color: cantidadDisponible > 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: cantidadController,
              decoration: const InputDecoration(
                labelText: 'Cantidad vendida',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: precioController,
              decoration: const InputDecoration(
                labelText: 'Precio unitario',
                border: OutlineInputBorder(),
                prefixText: '\$',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cantidad = double.tryParse(cantidadController.text);
              final precio = double.tryParse(precioController.text);

              if (cantidad == null || precio == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ingrese valores válidos')),
                );
                return;
              }

              if (cantidad > cantidadDisponible) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('La cantidad excede el stock disponible'),
                  ),
                );
                return;
              }

              final success = await ConsignacionService.registrarVenta(
                idProductoConsignacion: producto['id'],
                cantidad: cantidad,
                precioUnitario: precio,
              );

              if (!mounted) return;

              if (success) {
                Navigator.pop(context);
                _loadProductos();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Venta registrada exitosamente'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Error al registrar venta'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoDevolucion(Map<String, dynamic> producto) {
    final cantidadVendida = (producto['cantidad_vendida'] as num).toDouble();
    final cantidadDevuelta = (producto['cantidad_devuelta'] as num).toDouble();
    final cantidadDisponibleDevolver = cantidadVendida - cantidadDevuelta;

    final cantidadController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Devolución'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Producto: ${producto['producto']['denominacion']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Disponible para devolver: $cantidadDisponibleDevolver',
              style: TextStyle(
                color: cantidadDisponibleDevolver > 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: cantidadController,
              decoration: const InputDecoration(
                labelText: 'Cantidad a devolver',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cantidad = double.tryParse(cantidadController.text);

              if (cantidad == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ingrese una cantidad válida')),
                );
                return;
              }

              if (cantidad > cantidadDisponibleDevolver) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('La cantidad excede lo disponible para devolver'),
                  ),
                );
                return;
              }

              final success = await ConsignacionService.registrarDevolucion(
                idProductoConsignacion: producto['id'],
                cantidad: cantidad,
              );

              if (!mounted) return;

              if (success) {
                Navigator.pop(context);
                _loadProductos();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Devolución registrada exitosamente'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Error al registrar devolución'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }
}
