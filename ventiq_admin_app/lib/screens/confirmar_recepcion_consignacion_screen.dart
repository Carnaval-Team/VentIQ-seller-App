import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/consignacion_envio_service.dart';
import '../services/consignacion_envio_listado_service.dart';
import '../services/currency_display_service.dart';

class ConfirmarRecepcionConsignacionScreen extends StatefulWidget {
  final int idContrato;
  final int idTiendaOrigen;
  final int idTiendaDestino;
  final int idAlmacenOrigen;
  final int idAlmacenDestino;
  final int? idEnvio; // Opcional: si viene de un envío específico

  const ConfirmarRecepcionConsignacionScreen({
    Key? key,
    required this.idContrato,
    required this.idTiendaOrigen,
    required this.idTiendaDestino,
    required this.idAlmacenOrigen,
    required this.idAlmacenDestino,
    this.idEnvio,
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
  // El consignatario define el precio real de venta
  final Map<int, double> _preciosVentaConfigurables = {};
  
  // Mapa para guardar TextEditingControllers: {idProductoConsignacion: TextEditingController}
  final Map<int, TextEditingController> _precioControllers = {};
  
  // Mapa para guardar margen %: {idProductoConsignacion: margenPorcentaje}
  final Map<int, double> _margenPorcentaje = {};
  
  // Mapa para guardar controladores de margen: {idProductoConsignacion: TextEditingController}
  final Map<int, TextEditingController> _margenControllers = {};
  
  // Tasa de cambio USD a CUP
  double _tasaCambio = 440.0;

  @override
  void initState() {
    super.initState();
    _loadProductosPendientes();
    _loadTasaCambio();
  }
  
  Future<void> _loadTasaCambio() async {
    try {
      final rate = await CurrencyDisplayService.getExchangeRateForDisplay('USD', 'CUP');
      if (mounted) {
        setState(() {
          _tasaCambio = rate;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error cargando tasa de cambio: $e');
      // Usa el valor por defecto de 440.0
    }
  }

  @override
  void dispose() {
    // Limpiar todos los TextEditingControllers de precio
    for (final controller in _precioControllers.values) {
      controller.dispose();
    }
    // Limpiar todos los TextEditingControllers de margen
    for (final controller in _margenControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProductosPendientes() async {
    setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> productos;
      
      if (widget.idEnvio != null) {
        // Si viene de un envío específico, obtener productos del envío
        final productosEnvio = await ConsignacionEnvioListadoService.obtenerProductosEnvio(widget.idEnvio!);
        
        // Transformar formato de productos del envío al formato esperado
        productos = productosEnvio.map((p) {
          return {
            'id': p['id_envio_producto'],
            'id_producto': p['id_producto'],
            'cantidad_enviada': p['cantidad_propuesta'],
            'precio_costo_unitario': p['precio_costo_cup'], // Precio configurado por consignador en CUP
            'precio_costo_usd': p['precio_costo_usd'], // Precio de costo en USD (de productopresentacion)
            'precio_venta_sugerido': p['precio_costo_cup'], // Base para calcular precio de venta
            'puede_modificar_precio': true,
            'producto': {
              'id': p['id_producto'],
              'denominacion': p['nombre_producto'],
              'sku': p['sku'],
            },
          };
        }).toList();
      } else {
        // Flujo antiguo: obtener productos pendientes del contrato
        productos = await ConsignacionService.getProductosPendientesConsignacion(widget.idContrato);
      }

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
        title: const Text('Revisar Envío de Productos'),
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
          // Precio de costo en CUP configurado por el consignador (precio_costo_cup)
          final precioCostoCUP = (producto['precio_venta_sugerido'] as num?)?.toDouble() ?? 0.0;
          // Precio de costo en USD (del producto original)
          final precioCostoUSD = (producto['precio_costo_usd'] as num?)?.toDouble() ?? 0.0;
          final puedeModificarPrecio = (producto['puede_modificar_precio'] as bool?) ?? false;
          // Precio de venta en CUP configurado por el consignatario
          final precioConfigurable = _preciosVentaConfigurables[idProductoConsignacion] ?? precioCostoCUP;
          
          // Si no puede modificar, establecer automáticamente el precio sugerido (ya está en CUP)
          if (!puedeModificarPrecio && !_preciosVentaConfigurables.containsKey(idProductoConsignacion)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                // ✅ El precio ya está en CUP, no necesita conversión
                _preciosVentaConfigurables[idProductoConsignacion] = precioCostoCUP;
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
                  // Fila 2: Precio de costo (informativo), margen % y precio de venta
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Precio Costo (del Consignador)',
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
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Precio Costo Original (USD)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '\$${precioCostoUSD.toStringAsFixed(2)} USD',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Precio Costo Consignación (CUP)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        '\$${precioCostoCUP.toStringAsFixed(2)} CUP',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '(\$${precioCostoUSD.toStringAsFixed(2)} USD)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Margen %',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Precio de Venta * CUP',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildPrecioTextField(
                              idProductoConsignacion,
                              precioCostoCUP,
                              puedeModificarPrecio,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: ElevatedButton.icon(
                          onPressed: () => _rechazarEnvio(idProductoConsignacion),
                          icon: const Icon(Icons.close),
                          label: const Text('Rechazar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
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
  /// El consignatario configura el precio de venta en CUP
  /// El precio sugerido ya viene en CUP (precio_costo_cup del consignador)
  Widget _buildPrecioTextField(
    int idProductoConsignacion,
    double precioCostoCUP,
    bool puedeModificarPrecio,
  ) {
    // Obtener o crear el controller
    if (!_precioControllers.containsKey(idProductoConsignacion)) {
      // ✅ El precio ya está en CUP, no necesita conversión
      final precioInicial = _preciosVentaConfigurables[idProductoConsignacion] ?? precioCostoCUP;
      _precioControllers[idProductoConsignacion] = TextEditingController(
        text: precioInicial > 0 ? precioInicial.toStringAsFixed(2) : precioCostoCUP.toStringAsFixed(2),
      );
      // Guardar el precio inicial en el mapa (en CUP)
      if (!_preciosVentaConfigurables.containsKey(idProductoConsignacion)) {
        _preciosVentaConfigurables[idProductoConsignacion] = precioInicial > 0 ? precioInicial : precioCostoCUP;
      }
    }

    final controller = _precioControllers[idProductoConsignacion]!;

    return TextField(
      // ✅ Siempre editable - El consignatario define el precio de venta
      enabled: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      controller: controller,
      decoration: InputDecoration(
        hintText: precioCostoCUP.toStringAsFixed(2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: Colors.grey[400]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: Colors.grey[400]!,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        isDense: true,
        prefixText: '\$ ',
      ),
      onChanged: (value) {
        final precio = double.tryParse(value);
        if (precio != null && precio > 0) {
          setState(() {
            _preciosVentaConfigurables[idProductoConsignacion] = precio;
          });
        }
      },
      onSubmitted: (value) {
        final precio = double.tryParse(value);
        if (precio != null && precio > 0) {
          setState(() {
            _preciosVentaConfigurables[idProductoConsignacion] = precio;
          });
        }
      },
    );
  }

  /// Construye el TextField para el margen % con cálculo automático de precio
 
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
            // ✅ Deshabilitado mientras se confirma
            onPressed: _isConfirming ? null : _confirmarEnvio,
            icon: _isConfirming
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(
              _isConfirming ? 'Aceptando envío...' : 'Aceptar Envío Completo',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              disabledBackgroundColor: Colors.grey[400],
              disabledForegroundColor: Colors.white,
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
        // Obtener usuario actual
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Error: Usuario no autenticado'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _isConfirming = false);
          return;
        }

        // Buscar envío pendiente para este contrato
        // Primero buscar en estado EN_TRANSITO, luego en PROPUESTO
        late int idEnvio;
        
        // Si viene de un envío específico (idEnvio proporcionado), usarlo directamente
        if (widget.idEnvio != null) {
          idEnvio = widget.idEnvio!;
          debugPrint('📦 Usando envío específico: $idEnvio');
        } else {
          // Buscar envío en estado EN_TRANSITO
          var enviosPendientes = await ConsignacionEnvioService.obtenerEnviosPorEstado(
            idContrato: widget.idContrato,
            estado: ConsignacionEnvioService.ESTADO_EN_TRANSITO,
          );

          if (enviosPendientes.isEmpty) {
            // Si no hay EN_TRANSITO, buscar en PROPUESTO
            debugPrint('⚠️ No hay envío EN_TRANSITO, buscando PROPUESTO...');
            enviosPendientes = await ConsignacionEnvioService.obtenerEnviosPorEstado(
              idContrato: widget.idContrato,
              estado: ConsignacionEnvioService.ESTADO_PROPUESTO,
            );
          }

          if (enviosPendientes.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⚠️ No hay envío pendiente para aceptar'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            setState(() => _isConfirming = false);
            return;
          }

          idEnvio = enviosPendientes[0]['id'] as int;
          debugPrint('📦 Envío encontrado: $idEnvio');
        }

        // Aceptar envío completo con ConsignacionEnvioService
        final aceptarResult = await ConsignacionEnvioService.aceptarEnvio(
          idEnvio: idEnvio,
          idUsuario: user.id,
        );

        if (!mounted) return;

        setState(() => _isConfirming = false);

        if (aceptarResult != null && aceptarResult['success'] == true) {
          // ✅ NUEVO: Actualizar monto_total del contrato
          try {
            await ConsignacionService.actualizarMontoTotalContrato(
              contratoId: widget.idContrato,
              productosConfirmados: _productosPendientes,
            );
            debugPrint('✅ Monto total del contrato actualizado');
          } catch (e) {
            debugPrint('⚠️ Error actualizando monto total (no crítico): $e');
          }

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Envío aceptado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );

          // ✅ Navegar a la vista de operaciones de inventario
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/inventory');
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error al aceptar envío: ${aceptarResult?['mensaje'] ?? 'Error desconocido'}'),
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

  Future<void> _rechazarEnvio(int idProductoConsignacion) async {
    final motivoController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar Envío'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Rechazar este producto?'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoController,
              decoration: InputDecoration(
                labelText: 'Motivo del rechazo',
                hintText: 'Ingrese el motivo...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              minLines: 3,
              maxLines: 5,
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
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final motivo = motivoController.text.trim();
      if (motivo.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Por favor ingrese un motivo'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      try {
        // Actualizar el estado del producto consignación a 2 (rechazado)
        // y guardar el motivo en observaciones
        final supabase = Supabase.instance.client;
        
        await supabase
            .from('app_dat_producto_consignacion')
            .update({
              'estado': 2, // Estado rechazado
              'observaciones': motivo,
            })
            .eq('id', idProductoConsignacion);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Producto rechazado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Recargar la lista de productos
          _loadProductosPendientes();
        }
      } catch (e) {
        debugPrint('❌ Error al rechazar producto: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        motivoController.dispose();
      }
    }
  }
}
