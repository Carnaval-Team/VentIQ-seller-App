import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/consignacion_envio_service.dart';
import '../services/consignacion_envio_listado_service.dart';
import '../services/currency_service.dart';
import '../services/user_preferences_service.dart';

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
      final rate = await CurrencyService.getEffectiveUsdToCupRate();
      if (mounted) {
        setState(() {
          _tasaCambio = rate;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error cargando tasa de cambio: $e');
    }
  }

  /// Convierte precio de venta CUP a USD usando la tasa efectiva de la tienda.
  double _calcularPrecioVentaUsd(double precioVentaCup) {
    if (precioVentaCup <= 0 || _tasaCambio <= 0) return 0.0;
    return double.parse((precioVentaCup / _tasaCambio).toStringAsFixed(4));
  }

  @override
  void dispose() {
    // Limpiar todos los TextEditingControllers de precio
    for (final controller in _precioControllers.values) {
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
        
        debugPrint('📦 Productos obtenidos del envío: ${productosEnvio.length}');
        if (productosEnvio.isNotEmpty) {
          debugPrint('📋 Campos disponibles: ${productosEnvio[0].keys.toList()}');
        }
        
        // Transformar formato de productos del envío al formato esperado
        productos = productosEnvio.map((p) {
          final idEnvioProducto = (p['id'] as num?)?.toInt() ?? 0;
          final idProducto = (p['id_producto'] as num?)?.toInt() ?? 0;
          final nombreProducto = (p['denominacion'] as String?) ?? 'Producto sin nombre';
          final sku = (p['sku'] as String?) ?? 'N/A';
          final cantidadPropuesta = (p['cantidad_propuesta'] as num?)?.toDouble() ?? 0;
          final precioCostoCup = (p['precio_costo_cup'] as num?)?.toDouble() ?? 0;
          final precioCostoUsd = (p['precio_costo_usd'] as num?)?.toDouble() ?? 0;
          final precioVentaCup = (p['precio_venta_cup'] as num?)?.toDouble() ?? 0;
          final estadoProducto = (p['estado_producto'] as num?)?.toInt() ?? 0;
          
          debugPrint('✅ Producto mapeado: id=$idEnvioProducto, nombre=$nombreProducto, cantidad=$cantidadPropuesta, estado=$estadoProducto');
          
          return {
            'id': idEnvioProducto,
            'id_producto': idProducto,
            'id_envio': widget.idEnvio ?? p['id_envio'], // ✅ Asegurar id_envio
            'cantidad_enviada': cantidadPropuesta,
            'precio_costo_unitario': precioCostoCup,
            'precio_costo_usd': precioCostoUsd,
            'precio_venta_sugerido': precioCostoCup,
            'precio_venta_cup': precioVentaCup,
            'puede_modificar_precio': true,
            'estado_producto': estadoProducto,  // ✅ Agregar estado_producto del RPC
            'producto': {
              'id': idProducto,
              'denominacion': nombreProducto,
              'sku': sku,
            },
          };
        }).toList();
      } else {
        // Flujo antiguo: obtener productos pendientes del contrato
        productos = await ConsignacionService.getProductosPendientesConsignacion(widget.idContrato);
      }

      // ✅ FILTRAR: Excluir productos rechazados (estado_producto 2)
      final productosNoRechazados = productos.where((p) {
        // Intentar obtener estado_producto primero (para envíos), luego estado (para contrato directo)
        final estadoProducto = (p['estado_producto'] as num?)?.toInt();
        final estado = (p['estado'] as num?)?.toInt() ?? 0;
        final estadoFinal = estadoProducto ?? estado;
        return estadoFinal != 2; // Excluir rechazados (estado 2)
      }).toList();
      
      debugPrint('📊 Productos totales: ${productos.length}, No rechazados: ${productosNoRechazados.length}');

      setState(() {
        _productosPendientes = productosNoRechazados;
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
    // ✅ FILTRAR: Solo productos NO rechazados (estado_producto != 2)
    final productosNoRechazados = _productosPendientes.where((p) {
      // Intentar obtener estado_producto primero (para envíos), luego estado (para contrato directo)
      final estadoProducto = (p['estado_producto'] as num?)?.toInt();
      final estado = (p['estado'] as num?)?.toInt() ?? 0;
      final estadoFinal = estadoProducto ?? estado;
      return estadoFinal != 2; // Excluir rechazados
    }).toList();
    
    final totalProductos = productosNoRechazados.length;
    final totalCantidad = productosNoRechazados.fold<double>(
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
          final idProductoConsignacion = (producto['id'] as num?)?.toInt() ?? 0;
          final nombreProducto = producto['producto']['denominacion'] ?? 'Producto';
          final sku = producto['producto']['sku'] ?? 'N/A';
          
          // Obtener estado_producto (para envíos) o estado (para contrato directo)
          final estadoProducto = (producto['estado_producto'] as num?)?.toInt();
          final estado = (producto['estado'] as num?)?.toInt() ?? 0;
          final estadoFinal = estadoProducto ?? estado;
          final estadoTexto = _obtenerTextoEstadoProducto(estadoFinal);
          
          // Obtener estado de app_dat_producto_consignacion
          final estadoConsignacion = (producto['estado'] as num?)?.toInt() ?? 0;
          final estadoConsignacionTexto = _obtenerTextoEstadoProducto(estadoConsignacion);
          
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                          '$cantidad un.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Estados del producto
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estado Envío',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _obtenerColorEstadoProducto(estadoFinal).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                estadoTexto,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _obtenerColorEstadoProducto(estadoFinal),
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
                            Text(
                              'Estado Consignación',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _obtenerColorEstadoProducto(estadoConsignacion).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                estadoConsignacionTexto,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _obtenerColorEstadoProducto(estadoConsignacion),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Layout Responsive: Detectar tamaño de pantalla
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isSmallScreen = constraints.maxWidth < 600;
                      
                      if (isSmallScreen) {
                        // Layout vertical para pantallas pequeñas
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Precio de costo
                            _buildPriceSection(
                              'Precio Costo',
                              precioCostoUSD,
                              precioCostoCUP,
                              Colors.blue,
                            ),
                            const SizedBox(height: 12),
                            // Precio de venta
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Precio de Venta (CUP)',
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
                            const SizedBox(height: 12),
                            // Ganancias
                            _buildGananciasColumn(
                              idProductoConsignacion,
                              precioCostoCUP,
                              precioCostoUSD,
                            ),
                            const SizedBox(height: 12),
                            // Botón Rechazar (ancho completo)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _rechazarEnvio(idProductoConsignacion),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text('Rechazar Producto'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        );
                      } else {
                        // Layout horizontal para pantallas grandes
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildPriceSection(
                                'Precio Costo',
                                precioCostoUSD,
                                precioCostoCUP,
                                Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Precio de Venta (CUP)',
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
                              flex: 2,
                              child: _buildGananciasColumn(
                                idProductoConsignacion,
                                precioCostoCUP,
                                precioCostoUSD,
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
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Widget reutilizable para mostrar sección de precio
  Widget _buildPriceSection(
    String label,
    double priceUSD,
    double priceCUP,
    Color color,
  ) {
    return Column(
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\$${priceUSD.toStringAsFixed(2)} USD',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '\$${priceCUP.toStringAsFixed(2)} CUP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Construye el TextField para el precio de venta con controller persistente
  /// El consignatario configura el precio de venta en CUP
  /// SIN precio preconfigurado - El consignatario debe ingresar el precio
  Widget _buildPrecioTextField(
    int idProductoConsignacion,
    double precioCostoCUP,
    bool puedeModificarPrecio,
  ) {
    // Obtener o crear el controller
    if (!_precioControllers.containsKey(idProductoConsignacion)) {
      // ✅ SIN precio preconfigurado - Campo vacío para que el consignatario ingrese el precio
      _precioControllers[idProductoConsignacion] = TextEditingController(text: '');
    }

    final controller = _precioControllers[idProductoConsignacion]!;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[400]!),
      ),
      child: TextField(
        // ✅ Siempre editable - El consignatario define el precio de venta
        enabled: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        controller: controller,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          hintText: 'Precio',
          hintStyle: TextStyle(
            fontSize: 12,
            color: Colors.grey[400],
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          isDense: true,
          prefixText: '\$ ',
          prefixStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
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
      ),
    );
  }

  /// Construye la columna de ganancias con cálculos en USD, CUP y porcentaje
  Widget _buildGananciasColumn(
    int idProductoConsignacion,
    double precioCostoCUP,
    double precioCostoUSD,
  ) {
    final precioVentaCUP = _preciosVentaConfigurables[idProductoConsignacion] ?? 0.0;
    final precioVentaUSD = precioVentaCUP > 0 ? precioVentaCUP / _tasaCambio : 0.0;
    final gananciaUSD = precioVentaUSD - precioCostoUSD;
    final gananciaCUP = precioVentaCUP - precioCostoCUP;
    final porcentajeGanancia = precioCostoCUP > 0 ? ((gananciaCUP / precioCostoCUP) * 100) : 0.0;
    final esPositiva = gananciaUSD >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ganancias',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: esPositiva ? Colors.green[50] : Colors.red[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: esPositiva ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '\$${gananciaUSD.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: esPositiva ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ),
                  Text(
                    'USD',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: esPositiva ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '\$${gananciaCUP.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: esPositiva ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ),
                  Text(
                    'CUP',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: esPositiva ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: esPositiva ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${porcentajeGanancia.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: esPositiva ? Colors.green[900] : Colors.red[900],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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

        // ✅ FILTRAR: Solo productos NO rechazados (estado_producto != 2)
        final productosNoRechazados = _productosPendientes.where((p) {
          final estadoProducto = (p['estado_producto'] as num?)?.toInt();
          final estado = (p['estado'] as num?)?.toInt() ?? 0;
          final estadoFinal = estadoProducto ?? estado;
          return estadoFinal != 2; // Excluir rechazados
        }).toList();
        
        debugPrint('📊 Productos a procesar: ${productosNoRechazados.length} (excluidos rechazados)');

        // Refrescar tasa de la tienda antes de calcular precios USD
        try {
          _tasaCambio = await CurrencyService.getEffectiveUsdToCupRate();
          debugPrint('💱 Tasa USD→CUP efectiva de la tienda: $_tasaCambio');
        } catch (e) {
          debugPrint('⚠️ No se pudo refrescar tasa, usando $_tasaCambio: $e');
        }
        
        // Construir JSON de precios del formulario
        final preciosProductos = <Map<String, dynamic>>[];
        final productosConPrecioInvalido = <String>[];
        
        debugPrint('📋 Precios configurados en _preciosVentaConfigurables: $_preciosVentaConfigurables');
        
        for (final producto in productosNoRechazados) {
          final idProductoConsignacion = producto['id'] as int;
          final idProducto = producto['id_producto'] as int;
          final nombreProducto = producto['producto']['denominacion'] as String? ?? 'Producto';
          final precioSugerido = (producto['precio_venta_sugerido'] as num?)?.toDouble() ?? 0.0;
          final precioCostoUsd = (producto['precio_costo_usd'] as num?)?.toDouble() ?? 0.0;
          final estadoProducto = (producto['estado_producto'] as num?)?.toInt() ?? 0;
          
          debugPrint('🔍 Procesando producto: $nombreProducto (ID consignación: $idProductoConsignacion, estado: $estadoProducto)');
          debugPrint('   - Precio sugerido: $precioSugerido');
          debugPrint('   - Precio en _preciosVentaConfigurables: ${_preciosVentaConfigurables[idProductoConsignacion]}');
          
          // ✅ USAR el precio configurado por el usuario, o el precio sugerido como fallback
          final precioConfigurable = _preciosVentaConfigurables[idProductoConsignacion] ?? precioSugerido;
          
          debugPrint('   - Precio final a usar: $precioConfigurable');
          
          // ✅ VALIDAR: precio_venta_cup debe ser > 0 y NO null
          if (precioConfigurable == null || precioConfigurable <= 0) {
            debugPrint('❌ Producto $nombreProducto (ID: $idProducto) tiene precio inválido: $precioConfigurable');
            productosConPrecioInvalido.add(nombreProducto);
            continue; // Saltar este producto
          }
          
          final precioVentaUsd = _calcularPrecioVentaUsd(precioConfigurable);
          debugPrint(
            '✅ Producto $nombreProducto: precio_venta_cup=$precioConfigurable, '
            'precio_venta_usd=$precioVentaUsd (tasa=$_tasaCambio)',
          );
          
          preciosProductos.add({
            'id_producto': idProducto,
            'precio_venta_cup': precioConfigurable,
            'precio_venta_usd': precioVentaUsd,
            'precio_costo_usd': precioCostoUsd,
          });
        }
        
        debugPrint('💰 Precios del formulario: $preciosProductos');
        debugPrint('📊 Total productos a enviar: ${preciosProductos.length}');
        
        // ✅ VALIDAR: Si hay productos con precio inválido, NO aceptar el envío
        if (productosConPrecioInvalido.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ No se puede aceptar el envío. Los siguientes productos tienen precio inválido: ${productosConPrecioInvalido.join(", ")}. Por favor, configura los precios correctamente.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
          if (mounted) {
            setState(() => _isConfirming = false);
          }
          return;
        }
        
        if (preciosProductos.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ No hay productos para confirmar (todos fueron rechazados)'),
              backgroundColor: Colors.orange,
            ),
          );
          if (mounted) {
            setState(() => _isConfirming = false);
          }
          return;
        }
        
        bool success = false;
        
        // ✅ Validar que preciosProductos no esté vacío
        if (preciosProductos.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ No hay productos con precios válidos para confirmar'),
              backgroundColor: Colors.red,
            ),
          );
          if (mounted) {
            setState(() => _isConfirming = false);
          }
          return;
        }
        
        // ✅ Validar que todos los precios sean válidos (no null, > 0)
        for (final precio in preciosProductos) {
          final precioVentaCup = precio['precio_venta_cup'];
          if (precioVentaCup == null || precioVentaCup <= 0) {
            debugPrint('❌ Precio inválido en preciosProductos: $precioVentaCup');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Error: Hay precios inválidos en los datos a enviar'),
                backgroundColor: Colors.red,
              ),
            );
            if (mounted) {
              setState(() => _isConfirming = false);
            }
            return;
          }
        }
        
        debugPrint('✅ Validación de precios completada correctamente');
        
        // ✅ Decidir qué método usar según el flujo
        final envioId = widget.idEnvio ?? idEnvio;
        if (envioId != null) {
          // FLUJO DE ENVÍO: Usar aceptarEnvio del RPC
          debugPrint('📦 Usando flujo de envío específico: $envioId');
          final userPrefs = UserPreferencesService();
          final userId = await userPrefs.getUserId();
          
          final aceptarResult = await ConsignacionEnvioService.aceptarEnvio(
            idEnvio: envioId,
            idUsuario: userId ?? '',
            idTiendaDestino: widget.idTiendaDestino,
            preciosProductos: preciosProductos,
          );
          
          success = aceptarResult != null && aceptarResult['success'] == true;
        } else {
          // FLUJO DE CONTRATO DIRECTO: Usar confirmarRecepcionProductosConsignacion
          debugPrint('📋 Usando flujo de contrato directo');
          
          // ✅ FILTRAR: Solo productos NO rechazados (estado_producto != 2)
          final productosAConfirmar = _productosPendientes.where((p) {
            // Intentar obtener estado_producto primero (para envíos), luego estado (para contrato directo)
            final estadoProducto = (p['estado_producto'] as num?)?.toInt();
            final estado = (p['estado'] as num?)?.toInt() ?? 0;
            final estadoFinal = estadoProducto ?? estado;
            return estadoFinal != 2; // Excluir rechazados
          }).toList();
          
          debugPrint('📊 Productos a confirmar: ${productosAConfirmar.length} (excluidos rechazados)');
          
          if (productosAConfirmar.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ No hay productos para confirmar (todos fueron rechazados)'),
                backgroundColor: Colors.orange,
              ),
            );
            if (mounted) {
              setState(() => _isConfirming = false);
            }
            return;
          }
          
          // Preparar IDs de productos consignación y mapa de precios
          final idsProductosConsignacion = productosAConfirmar
              .map((p) => p['id'] as int)
              .toList();
          
          final preciosVentaMap = <int, double>{};
          for (final producto in productosAConfirmar) {
            final idProductoConsignacion = (producto['id'] as num?)?.toInt() ?? 0;
            if (idProductoConsignacion == 0) continue;
            final precioSugerido = (producto['precio_venta_sugerido'] as num?)?.toDouble() ?? 0.0;
            final precioConfigurable = _preciosVentaConfigurables[idProductoConsignacion] ?? precioSugerido;
            preciosVentaMap[idProductoConsignacion] = precioConfigurable;
          }
          
          debugPrint('📋 IDs productos consignación: $idsProductosConsignacion');
          debugPrint('💰 Precios de venta: $preciosVentaMap');
          
          success = await ConsignacionService.confirmarRecepcionProductosConsignacion(
            idContrato: widget.idContrato,
            idTiendaOrigen: widget.idTiendaOrigen,
            idTiendaDestino: widget.idTiendaDestino,
            idAlmacenOrigen: widget.idAlmacenOrigen,
            idAlmacenDestino: widget.idAlmacenDestino,
            idsProductosConsignacion: idsProductosConsignacion,
            preciosVenta: preciosVentaMap,
            idEnvio: idEnvio,
          );
        }

        if (!mounted) return;

        setState(() => _isConfirming = false);

        if (success) {
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

  Future<void> _rechazarEnvio(int idEnvioProducto) async {
    final motivoController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar Envío'),
        content: SingleChildScrollView(
          child: Column(
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
        motivoController.dispose();
        return;
      }

      try {
        final userId = await UserPreferencesService().getUserId();
        if (userId == null) throw Exception('Usuario no identificado');

        // Obtener el id_envio de forma segura
        final producto = _productosPendientes.firstWhere(
          (p) => p['id'] == idEnvioProducto,
          orElse: () => {},
        );
        
        final idEnvioNum = widget.idEnvio ?? producto['id_envio'];
        
        if (idEnvioNum == null) {
          throw Exception('No se pudo identificar el envío asociado al producto');
        }
        
        final idEnvio = (idEnvioNum as num).toInt();

        final result = await ConsignacionEnvioService.rechazarProductoEnvio(
          idEnvio: idEnvio,
          idEnvioProducto: idEnvioProducto,
          idUsuario: userId,
          motivoRechazo: motivo,
        );

        final success = result['success'] as bool? ?? false;
        final mensaje = result['mensaje'] as String? ?? '';

        if (!success) {
          throw Exception(mensaje.isNotEmpty ? mensaje : 'Error al procesar el rechazo en el servidor');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $mensaje'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Si el mensaje indica que se rechazó todo el envío, volvemos atrás
          if (mensaje.contains('RECHAZADO globalmente')) {
            Navigator.of(context).pop(true);
          } else {
            // Recargar la lista de productos
            _loadProductosPendientes();
          }
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
        if (mounted) {
          motivoController.dispose();
        }
      }
    } else {
      motivoController.dispose();
    }
  }

  /// Obtiene el texto del estado del producto
  /// 0 = Pendiente, 1 = Confirmado, 2 = Rechazado
  String _obtenerTextoEstadoProducto(int estado) {
    switch (estado) {
      case 0:
        return 'Pendiente';
      case 1:
        return 'Confirmado';
      case 2:
        return 'Rechazado';
      default:
        return 'Desconocido';
    }
  }

  /// Obtiene el color del estado del producto
  /// 0 = Pendiente (naranja), 1 = Confirmado (verde), 2 = Rechazado (rojo)
  Color _obtenerColorEstadoProducto(int estado) {
    switch (estado) {
      case 0:
        return Colors.orange;
      case 1:
        return Colors.green;
      case 2:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
