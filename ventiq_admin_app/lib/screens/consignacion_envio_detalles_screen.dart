import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/consignacion_envio_listado_service.dart';
import '../services/consignacion_envio_service.dart';
import '../services/user_preferences_service.dart';
import '../services/currency_display_service.dart';
import 'confirmar_recepcion_consignacion_screen.dart';

class ConsignacionEnvioDetallesScreen extends StatefulWidget {
  final int idEnvio;
  final String? rol;

  const ConsignacionEnvioDetallesScreen({
    Key? key,
    required this.idEnvio,
    this.rol,
  }) : super(key: key);

  @override
  State<ConsignacionEnvioDetallesScreen> createState() =>
      _ConsignacionEnvioDetallesScreenState();
}

class _ConsignacionEnvioDetallesScreenState
    extends State<ConsignacionEnvioDetallesScreen> {
  late Future<Map<String, dynamic>?> _detallesFuture;
  late Future<List<Map<String, dynamic>>> _productosFuture;
  
  double _tasaCambio = 440.0; // Valor por defecto
  bool _isLoadingTasa = true;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    _loadTasaCambio();
    _refrescar();
  }

  Future<void> _loadTasaCambio() async {
    try {
      final rate = await CurrencyDisplayService.getExchangeRateForDisplay('USD', 'CUP');
      if (mounted) {
        setState(() {
          _tasaCambio = rate;
          _isLoadingTasa = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error cargando tasa de cambio: $e');
      if (mounted) {
        setState(() => _isLoadingTasa = false);
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _refrescar() {
    print('🔄 Refrescando detalles del envío ${widget.idEnvio}');
    setState(() {
      _detallesFuture =
          ConsignacionEnvioListadoService.obtenerDetallesEnvio(widget.idEnvio)
              .then((detalles) {
            if (detalles != null) {
              print('📋 Detalles recibidos en pantalla:');
              print('   - Almacén Origen: ${detalles['almacen_origen']}');
              print('   - Almacén Destino: ${detalles['almacen_destino']}');
              print('   - Porcentaje Comisión: ${detalles['porcentaje_comision']}');
              print('   - Todas las claves: ${detalles.keys.toList()}');
            }
            return detalles;
          });
      _productosFuture =
          ConsignacionEnvioListadoService.obtenerProductosEnvio(widget.idEnvio);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles del Envío'),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _detallesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Error al cargar detalles'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Volver'),
                  ),
                ],
              ),
            );
          }

          final detalles = snapshot.data!;
          final estadoEnvioRaw = detalles['estado_envio'];
          final estadoEnvio = estadoEnvioRaw is num
              ? estadoEnvioRaw.toInt()
              : int.tryParse(estadoEnvioRaw?.toString() ?? '');
          
          final tipoEnvioRaw = detalles['tipo_envio'];
          final tipoEnvio = tipoEnvioRaw is num
              ? tipoEnvioRaw.toInt()
              : int.tryParse(tipoEnvioRaw?.toString() ?? '') ?? 1;

          // Lógica de permisos de edición
          // El consignatario PUEDE editar precios en PROPUESTO y EN_TRANSITO
          bool puedeEditar = false;
          if (tipoEnvio == 1 && widget.rol == 'consignatario' && 
              (estadoEnvio == ConsignacionEnvioListadoService.ESTADO_PROPUESTO || 
               estadoEnvio == ConsignacionEnvioListadoService.ESTADO_EN_TRANSITO)) {
            puedeEditar = true;
          }

          // Acciones para que el CONSIGNADOR gestione la devolución desde el detalle
          bool puedeGestionarDevolucionConsignador = (tipoEnvio == 2 && widget.rol == 'consignador' && estadoEnvio == 1);
          
          // Botón "Verificar Envío" para CONSIGNATARIO cuando envío está PROPUESTO
          bool puedeVerificarEnvio = (tipoEnvio == 1 && widget.rol == 'consignatario' && estadoEnvio == ConsignacionEnvioListadoService.ESTADO_PROPUESTO);

          // Acciones de CANCELACIÓN (quien crea, puede cancelar antes de avanzar)
          bool puedeCancelar = (
            (tipoEnvio == 1 && widget.rol == 'consignador' && estadoEnvio == 1) || // Consignador cancela envío propuesto
            (tipoEnvio == 2 && widget.rol == 'consignatario' && estadoEnvio == 1)    // Consignatario cancela devolución propuesta
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSeccionDetalles(detalles),
                const SizedBox(height: 24),
                _buildSeccionProductos(puedeEditar: puedeEditar),
                
                if (puedeVerificarEnvio) ...[
                  const SizedBox(height: 24),
                  _buildBotonVerificarEnvio(detalles),
                ],

                if (puedeGestionarDevolucionConsignador) ...[
                  const SizedBox(height: 24),
                  _buildAccionesDevolucionConsignador(detalles),
                ],

                if (puedeCancelar) ...[
                  const SizedBox(height: 24),
                  _buildBotonCancelar(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSeccionDetalles(Map<String, dynamic> detalles) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información General',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildFilaDetalle('Envío', detalles['numero_envio']),
            _buildFilaDetalle('Estado', detalles['estado_envio_texto']),
            _buildFilaDetalle('Consignadora', detalles['tienda_consignadora']),
            _buildFilaDetalle('Consignataria', detalles['tienda_consignataria']),
            _buildFilaDetalle('Almacén Origen', detalles['almacen_origen'] ?? 'N/A'),
            _buildFilaDetalle('Almacén Destino', detalles['almacen_destino'] ?? 'N/A'),
            _buildFilaDetalle(
              'Cantidad Total Unidades',
              '${(detalles['cantidad_total_unidades'] as num?)?.toStringAsFixed(0) ?? '0'} u.',
            ),
            _buildFilaDetalle(
              'Valor Total Costo (USD)',
              '\$${((detalles['valor_total_costo'] as num?) ?? 0).toStringAsFixed(2)} USD',
            ),
            if (((detalles['valor_total_venta'] as num?) ?? 0) > 0)
              _buildFilaDetalle(
                'Valor Total Venta (CUP)',
                '\$${((detalles['valor_total_venta'] as num?) ?? 0).toStringAsFixed(2)} CUP',
              ),
            const SizedBox(height: 16),
            const Text(
              'Fechas',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildFilaDetalle(
              'Propuesto',
              _formatearFecha(detalles['fecha_propuesta']),
            ),
            if (detalles['fecha_aceptacion'] != null)
              _buildFilaDetalle(
                'Aceptado',
                _formatearFecha(detalles['fecha_aceptacion']),
              ),
            if (detalles['fecha_rechazo'] != null)
              _buildFilaDetalle(
                'Rechazado',
                _formatearFecha(detalles['fecha_rechazo']),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeccionProductos({required bool puedeEditar}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Productos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (puedeEditar)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Text(
                  'Tasa: $_tasaCambio',
                  style: TextStyle(fontSize: 12, color: Colors.blue[800]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _productosFuture,
          builder: (context, snapshot) {
            debugPrint('🔍 Estado FutureBuilder productos: ${snapshot.connectionState}');
            
            if (snapshot.connectionState == ConnectionState.waiting) {
              debugPrint('⏳ Cargando productos...');
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              debugPrint('❌ Error en FutureBuilder: ${snapshot.error}');
              debugPrint('   Stack trace: ${snapshot.stackTrace}');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 8),
                    Text('Error: ${snapshot.error}'),
                  ],
                ),
              );
            }

            final productos = snapshot.data ?? [];
            debugPrint('📦 Productos recibidos: ${productos.length}');
            
            if (productos.isNotEmpty) {
              debugPrint('📋 Primer producto: ${productos[0]}');
            }

            if (productos.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('No hay productos en este envío'),
                  ],
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: productos.length,
              itemBuilder: (context, index) {
                // Adaptamos el item builder al estilo "Confirmar Recepción"
                return _buildProductoItemRefinado(
                  productos[index],
                  puedeEditar: puedeEditar,
                );
              },
            );
          },
        ),
      ],
    );
  }

  // Versión simplificada para PROPUESTO y EN_TRANSITO
  Widget _buildProductoItemRefinado(
    Map<String, dynamic> producto, {
    required bool puedeEditar,
  }) {
    final nombreProducto = producto['producto_denominacion'] as String? ?? producto['nombre_producto'] as String? ?? 'N/A';
    final sku = producto['producto_sku'] as String? ?? producto['sku'] as String? ?? 'N/A';
    final cantidad = producto['cantidad_propuesta'] ?? 0;
    final precioCostoUsd = (producto['precio_costo_usd'] as num?)?.toDouble() ?? 0.0;
    final precioVentaCup = (producto['precio_venta_cup'] as num?)?.toDouble();

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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Costo: \$${precioCostoUsd.toStringAsFixed(2)} USD',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                if (precioVentaCup != null && precioVentaCup > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Venta: \$${precioVentaCup.toStringAsFixed(2)} CUP',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.purple[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  
  Widget _buildProductoInfo(String label, String valor) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
        Text(
          valor,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildFilaDetalle(String label, dynamic valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
          Text(
            valor.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatearFecha(dynamic fecha) {
    if (fecha == null) return 'N/A';
    if (fecha is DateTime) {
      return DateFormat('dd/MM/yyyy HH:mm').format(fecha);
    }
    if (fecha is String) {
      final parsed = DateTime.tryParse(fecha);
      if (parsed != null) {
        return DateFormat('dd/MM/yyyy HH:mm').format(parsed);
      }
      return fecha;
    }
    return fecha.toString();
  }
  
  // Botones flotantes o al final
  // --- Funciones de Acción ---

  Future<void> _rechazarProducto({required int idEnvioProducto}) async {
    final motivoController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar producto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Rechazar este producto del envío?'),
            const SizedBox(height: 12),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo del rechazo',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
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

    if (confirmed != true) return;
    
    final motivo = motivoController.text.trim();
    if (motivo.isEmpty) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese motivo')));
      return;
    }
    
    final userId = await UserPreferencesService().getUserId();
    
    try {
      final result = await ConsignacionEnvioListadoService.rechazarProductoEnvio(
        widget.idEnvio,
        idEnvioProducto,
        userId!,
        motivo,
      );
      
      if (mounted) {
         _refrescar();
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Producto rechazado')));
      }
    } catch(e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _rechazarEnvioGlobal() async {
    final motivoController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar Envío Completo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Estás seguro de que deseas rechazar este envío por completo? '
              'Esta acción devolverá los productos al stock del consignador.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo del rechazo',
                border: OutlineInputBorder(),
                hintText: 'Ej: Diferencia en cantidades, mal estado, etc.',
              ),
              minLines: 2,
              maxLines: 4,
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
            child: const Text('Confirmar Rechazo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final motivo = motivoController.text.trim();
    if (motivo.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, indica un motivo de rechazo')),
        );
      }
      return;
    }

    setState(() => _isAccepting = true);

    try {
      final userId = await UserPreferencesService().getUserId();
      if (userId == null) throw Exception('Usuario no identificado');

      final success = await ConsignacionEnvioService.rechazarEnvio(
        idEnvio: widget.idEnvio,
        idUsuario: userId,
        motivoRechazo: motivo,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Envío rechazado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Retornar true para refrescar lista
        }
      } else {
        throw Exception('No se pudo rechazar el envío');
      }
    } catch (e) {
      debugPrint('❌ Error rechazando envío: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Widget _buildBotonVerificarEnvio(Map<String, dynamic> detalles) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _navegarAVerificarEnvio(detalles),
        icon: const Icon(Icons.fact_check),
        label: const Text(
          'Verificar Envío',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Future<void> _navegarAVerificarEnvio(Map<String, dynamic> detalles) async {
    // Logging: Mostrar todos los detalles recibidos
    debugPrint('📋 ===== VERIFICAR ENVÍO =====');
    debugPrint('📋 Detalles completos recibidos:');
    detalles.forEach((key, value) {
      debugPrint('   - $key: $value (${value.runtimeType})');
    });
    
    // Navegar a ConfirmarRecepcionConsignacionScreen
    final idContrato = detalles['id_contrato_consignacion'];
    final idTiendaOrigen = detalles['id_tienda_consignadora'];
    final idTiendaDestino = detalles['id_tienda_consignataria'];
    final idAlmacenOrigen = detalles['id_almacen_origen'];
    final idAlmacenDestino = detalles['id_almacen_destino'];

    debugPrint('📋 Datos extraídos:');
    debugPrint('   - idContrato: $idContrato');
    debugPrint('   - idTiendaOrigen: $idTiendaOrigen');
    debugPrint('   - idTiendaDestino: $idTiendaDestino');
    debugPrint('   - idAlmacenOrigen: $idAlmacenOrigen');
    debugPrint('   - idAlmacenDestino: $idAlmacenDestino');

    // Validar datos y mostrar cuál falta
    List<String> datosFaltantes = [];
    if (idContrato == null) datosFaltantes.add('Contrato');
    if (idTiendaOrigen == null) datosFaltantes.add('Tienda Origen');
    if (idTiendaDestino == null) datosFaltantes.add('Tienda Destino');
    if (idAlmacenOrigen == null) datosFaltantes.add('Almacén Origen');
    if (idAlmacenDestino == null) datosFaltantes.add('Almacén Destino');

    if (datosFaltantes.isNotEmpty) {
      debugPrint('❌ DATOS FALTANTES: ${datosFaltantes.join(', ')}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Faltan datos: ${datosFaltantes.join(', ')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    debugPrint('✅ Todos los datos están presentes. Navegando a ConfirmarRecepcionConsignacionScreen...');

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfirmarRecepcionConsignacionScreen(
          idContrato: idContrato,
          idTiendaOrigen: idTiendaOrigen,
          idTiendaDestino: idTiendaDestino,
          idAlmacenOrigen: idAlmacenOrigen,
          idAlmacenDestino: idAlmacenDestino,
          idEnvio: widget.idEnvio, // Pasar el ID del envío
        ),
      ),
    );

    // Si se confirmó la recepción, cerrar esta pantalla y refrescar
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _buildAccionesDevolucionConsignador(Map<String, dynamic> detalles) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _mostrarDialogoAprobarDevolucion(detalles),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text(
              'Aprobar y Recibir Devolución',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _rechazarEnvioGlobal(),
            icon: const Icon(Icons.close),
            label: const Text(
              'Rechazar Solicitud de Devolución',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _mostrarDialogoAprobarDevolucion(Map<String, dynamic> envio) async {
    int? idAlmacenSeleccionado;
    bool cargandoAlmacenes = true;
    List<Map<String, dynamic>> almacenes = [];

    // Cargar almacenes del consignador (tienda consignadora)
    try {
      final idTiendaConsignadora = envio['id_tienda_consignadora'];
      if (idTiendaConsignadora != null) {
        final response = await Supabase.instance.client
            .from('app_dat_almacen')
            .select('id, denominacion')
            .eq('id_tienda', idTiendaConsignadora);
        almacenes = List<Map<String, dynamic>>.from(response);
        if (almacenes.isNotEmpty) idAlmacenSeleccionado = almacenes[0]['id'];
      }
      cargandoAlmacenes = false;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error cargando almacenes: $e');
    }

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Aprobar Devolución'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Al aprobar la devolución se reintegrarán los productos a tu inventario. Selecciona el almacén de recepción:'),
              const SizedBox(height: 16),
              if (cargandoAlmacenes)
                const Center(child: CircularProgressIndicator())
              else if (almacenes.isEmpty)
                const Text('No tienes almacenes configurados', style: TextStyle(color: Colors.red))
              else
                DropdownButtonFormField<int>(
                  value: idAlmacenSeleccionado,
                  items: almacenes.map((a) => DropdownMenuItem<int>(
                    value: a['id'],
                    child: Text(a['denominacion']),
                  )).toList(),
                  onChanged: (val) => setDialogState(() => idAlmacenSeleccionado = val),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Almacén de Recepción',
                    border: OutlineInputBorder()
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR')
            ),
            ElevatedButton(
              onPressed: idAlmacenSeleccionado == null ? null : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text('APROBAR Y RECIBIR'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && idAlmacenSeleccionado != null) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      setState(() => _isAccepting = true);

      final result = await ConsignacionEnvioService.aprobarDevolucion(
        idEnvio: widget.idEnvio,
        idAlmacenRecepcion: idAlmacenSeleccionado!,
        idUsuario: user.id,
      );

      if (mounted) setState(() => _isAccepting = false);

      if (result != null && result['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Devolución procesada y stock reintegrado exitosamente'),
          backgroundColor: Colors.green
        ));
        Navigator.pop(context, true); // Volver avisando que hubo cambios
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ Error: ${result?['mensaje'] ?? 'Error desconocido'}'),
          backgroundColor: Colors.red
        ));
      }
    }
  }

  Widget _buildBotonCancelar() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isAccepting ? null : _mostrarDialogoCancelar,
        icon: const Icon(Icons.cancel_outlined),
        label: const Text(
          'Cancelar Solicitud',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.orange,
          side: const BorderSide(color: Colors.orange),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Future<void> _mostrarDialogoCancelar() async {
    final motivoController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Solicitud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Estás seguro de que deseas cancelar esta solicitud? Los productos reservados volverán al inventario.'),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO, VOLVER')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('SÍ, CANCELAR'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isAccepting = true);
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return;

        final result = await ConsignacionEnvioListadoService.cancelarEnvio(
          widget.idEnvio,
          user.id,
          motivoController.text.trim().isEmpty ? null : motivoController.text.trim(),
        );

        if (mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ Solicitud cancelada exitosamente'),
              backgroundColor: Colors.green
            ));
            Navigator.pop(context, true);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('❌ Error: ${result['mensaje']}'),
              backgroundColor: Colors.red
            ));
          }
        }
      } catch (e) {
        debugPrint(e.toString());
      } finally {
        if (mounted) setState(() => _isAccepting = false);
      }
    }
  }
}
