import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';

class ConfirmarRecepcionConsignacionScreen extends StatefulWidget {
  final int idContrato;
  final int idTiendaOrigen;
  final int idTiendaDestino;
  final int idAlmacenOrigen;
  final int idAlmacenDestino;

  const ConfirmarRecepcionConsignacionScreen({
    Key? key,
    required this.idContrato,
    required this.idTiendaOrigen,
    required this.idTiendaDestino,
    required this.idAlmacenOrigen,
    required this.idAlmacenDestino,
  }) : super(key: key);

  @override
  State<ConfirmarRecepcionConsignacionScreen> createState() =>
      _ConfirmarRecepcionConsignacionScreenState();
}

class _ConfirmarRecepcionConsignacionScreenState
    extends State<ConfirmarRecepcionConsignacionScreen> {
  List<Map<String, dynamic>> _productosPendientes = [];
  bool _isLoading = true;
  bool _isConfirming = false;
  bool _aceptarTodo = false;
  
  // Mapa para guardar precios de venta configurados: {idProductoConsignacion: precioVenta}
  final Map<int, double> _preciosVentaConfigurables = {};
  
  // Mapa para guardar TextEditingControllers: {idProductoConsignacion: TextEditingController}
  final Map<int, TextEditingController> _precioControllers = {};

  @override
  void initState() {
    super.initState();
    _loadProductosPendientes();
  }

  @override
  void dispose() {
    // Limpiar todos los TextEditingControllers
    for (final controller in _precioControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProductosPendientes() async {
    setState(() => _isLoading = true);

    try {
      final productos = await ConsignacionService
          .getProductosPendientesConsignacion(widget.idContrato);

      setState(() {
        _productosPendientes = productos;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando productos: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aceptar Envío de Productos'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadProductosPendientes,
              child: _productosPendientes.isEmpty
                  ? _buildEmptyState()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEnvioResumen(),
                          const SizedBox(height: 24),
                          _buildProductosLista(),
                          const SizedBox(height: 24),
                          _buildBotonesAccion(),
                        ],
                      ),
                    ),
            ),
    );
  }

  Widget _buildEnvioResumen() {
    final totalProductos = _productosPendientes.length;
    final totalCantidad = _productosPendientes.fold<double>(
      0,
      (sum, p) => sum + ((p['cantidad_enviada'] as num?) ?? 0).toDouble(),
    );

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    color: Colors.blue,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Resumen del Envío',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Contrato #${widget.idContrato}',
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
            Row(
              children: [
                Expanded(
                  child: _buildStatItem('Productos', '$totalProductos', Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem('Cantidad Total', '${totalCantidad.toStringAsFixed(0)} unidades', Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
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

  Widget _buildProductosLista() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Productos a Aceptar',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_productosPendientes.length, (index) {
          final producto = _productosPendientes[index];
          final idProductoConsignacion = producto['id'] as int;
          final nombreProducto = producto['producto']['denominacion'] ?? 'Producto';
          final sku = producto['producto']['sku'] ?? 'N/A';
          final cantidad = producto['cantidad_enviada'];
          final precioSugerido = (producto['precio_venta_sugerido'] as num?)?.toDouble() ?? 0.0;
          final puedeModificarPrecio = (producto['puede_modificar_precio'] as bool?) ?? false;
          final precioConfigurable = _preciosVentaConfigurables[idProductoConsignacion] ?? precioSugerido;
          
          // Si no puede modificar, establecer automáticamente el precio sugerido
          if (!puedeModificarPrecio && !_preciosVentaConfigurables.containsKey(idProductoConsignacion)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                _preciosVentaConfigurables[idProductoConsignacion] = precioSugerido;
              });
            });
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fila 1: Nombre, SKU y Cantidad
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.inventory_2,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombreProducto,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'SKU: $sku',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$cantidad unidades',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Fila 2: Precio sugerido y campo de precio de venta
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Precio Sugerido',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.withOpacity(0.3)),
                              ),
                              child: Text(
                                '\$${precioSugerido.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Precio de Venta *',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                if (!puedeModificarPrecio)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Fijo',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            _buildPrecioTextField(
                              idProductoConsignacion,
                              precioSugerido,
                              puedeModificarPrecio,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Construye el TextField para el precio de venta con controller persistente
  Widget _buildPrecioTextField(
    int idProductoConsignacion,
    double precioSugerido,
    bool puedeModificarPrecio,
  ) {
    // Obtener o crear el controller
    if (!_precioControllers.containsKey(idProductoConsignacion)) {
      final precioInicial = _preciosVentaConfigurables[idProductoConsignacion] ?? precioSugerido;
      _precioControllers[idProductoConsignacion] = TextEditingController(
        text: precioInicial > 0 ? precioInicial.toStringAsFixed(2) : '',
      );
    }

    final controller = _precioControllers[idProductoConsignacion]!;

    return TextField(
      enabled: puedeModificarPrecio,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      controller: controller,
      decoration: InputDecoration(
        hintText: precioSugerido.toStringAsFixed(2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: puedeModificarPrecio ? Colors.grey[400]! : Colors.grey[300]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: puedeModificarPrecio ? Colors.grey[400]! : Colors.grey[300]!,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: Colors.grey[300]!,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
        prefixText: '\$ ',
        filled: !puedeModificarPrecio,
        fillColor: !puedeModificarPrecio ? Colors.grey[100] : null,
      ),
      onChanged: puedeModificarPrecio
          ? (value) {
              final precio = double.tryParse(value);
              if (precio != null && precio > 0) {
                setState(() {
                  _preciosVentaConfigurables[idProductoConsignacion] = precio;
                });
              }
            }
          : null,
      onSubmitted: puedeModificarPrecio
          ? (value) {
              final precio = double.tryParse(value);
              if (precio != null && precio > 0) {
                setState(() {
                  _preciosVentaConfigurables[idProductoConsignacion] = precio;
                });
              }
            }
          : null,
    );
  }

  Widget _buildBotonesAccion() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.content_copy, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Se duplicarán automáticamente los productos que no existan en tu tienda',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.info, color: Colors.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Se creará una operación de extracción y recepción para todos los productos',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isConfirming ? null : _confirmarEnvio,
            icon: _isConfirming
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_isConfirming ? 'Aceptando...' : 'Aceptar Envío Completo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 64,
              color: Colors.green[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'Todos los productos confirmados',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No hay productos pendientes de confirmación',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarEnvio() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aceptar Envío Completo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Aceptar el envío completo de ${_productosPendientes.length} producto(s)?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final producto in _productosPendientes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  producto['producto']['denominacion'] ?? 'Producto',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${producto['cantidad_enviada']} unidades',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Se creará 1 operación de extracción y 1 de recepción para todos los productos',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Aceptar Envío'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Validar que todos los productos tengan precio de venta configurado
      final productosSinPrecio = _productosPendientes.where((p) {
        final idProductoConsignacion = p['id'] as int;
        final precioSugerido = (p['precio_venta_sugerido'] as num?)?.toDouble() ?? 0.0;
        final precioConfigurable = _preciosVentaConfigurables[idProductoConsignacion] ?? precioSugerido;
        return precioConfigurable <= 0;
      }).toList();

      if (productosSinPrecio.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Todos los productos deben tener un precio de venta configurado'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() => _isConfirming = true);

      try {
        // Obtener IDs de todos los productos
        final idsProductos = _productosPendientes.map((p) => p['id'] as int).toList();
        
        final success = await ConsignacionService.confirmarRecepcionProductosConsignacion(
          idContrato: widget.idContrato,
          idTiendaOrigen: widget.idTiendaOrigen,
          idTiendaDestino: widget.idTiendaDestino,
          idAlmacenOrigen: widget.idAlmacenOrigen,
          idAlmacenDestino: widget.idAlmacenDestino,
          idsProductosConsignacion: idsProductos,
          preciosVenta: _preciosVentaConfigurables,
        );

        if (!mounted) return;

        setState(() => _isConfirming = false);

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Envío aceptado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
          _loadProductosPendientes();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Error al aceptar envío'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error: $e');
        if (mounted) {
          setState(() => _isConfirming = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
