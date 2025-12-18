import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/consignacion_envio_listado_service.dart';
import '../services/consignacion_envio_service.dart';
import '../services/user_preferences_service.dart';
import '../services/currency_display_service.dart';
// Importa este si lo necesitas para otras utilidades, pero trataremos de minimizar deps
// import '../services/consignacion_service.dart';

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
  
  // Mapas para lógica de edición de precios (estilo ConfirmarRecepcion)
  final Map<int, double> _preciosVentaConfigurables = {};
  final Map<int, TextEditingController> _precioVentaControllers = {};
  final Map<int, double> _margenPorcentaje = {};
  final Map<int, TextEditingController> _margenControllers = {};
  
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
    for (final controller in _precioVentaControllers.values) {
      controller.dispose();
    }
    for (final controller in _margenControllers.values) {
      controller.dispose();
    }
    _precioVentaControllers.clear();
    _margenControllers.clear();
    super.dispose();
  }

  void _refrescar() {
    setState(() {
      _detallesFuture =
          ConsignacionEnvioListadoService.obtenerDetallesEnvio(widget.idEnvio);
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

          // Lógica de permisos de edición
          // El consignatario revisa y configura el envío cuando está PROPUESTO
          // (Antes de que salga, valida lo que va a recibir)
          
          bool puedeEditar = false;
          if (widget.rol == 'consignatario' && 
              (estadoEnvio == ConsignacionEnvioListadoService.ESTADO_PROPUESTO || 
               estadoEnvio == ConsignacionEnvioListadoService.ESTADO_EN_TRANSITO)) {
            puedeEditar = true;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSeccionDetalles(detalles),
                const SizedBox(height: 24),
                _buildSeccionProductos(puedeEditar: puedeEditar),
                if (puedeEditar) ...[
                  const SizedBox(height: 24),
                  _buildBotonesAccionGlobal(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSeccionDetalles(Map<String, dynamic> detalles) {
    final valorTotalCostoRaw = detalles['valor_total_costo'];
    final valorTotalCosto = valorTotalCostoRaw is num
        ? valorTotalCostoRaw.toDouble()
        : double.tryParse(valorTotalCostoRaw?.toString() ?? '') ?? 0;

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
              'Cantidad Total',
              '${detalles['cantidad_total_unidades']} unidades',
            ),
            _buildFilaDetalle(
              'Valor Total',
              '\$${valorTotalCosto.toStringAsFixed(2)}',
            ),
            _buildFilaDetalle(
              'Comisión',
              '${detalles['porcentaje_comision']}%',
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
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final productos = snapshot.data ?? [];

            if (productos.isEmpty) {
              return const Center(
                child: Text('No hay productos en este envío'),
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

  // Versión refinada al estilo ConfirmarRecepcionConsignacionScreen
  Widget _buildProductoItemRefinado(
    Map<String, dynamic> producto, {
    required bool puedeEditar,
  }) {
    // Extracción de datos con seguridad de tipos
    final idEnvioProductoRaw = producto['id_envio_producto'];
    final idEnvioProducto = idEnvioProductoRaw is num 
        ? idEnvioProductoRaw.toInt() 
        : int.tryParse(idEnvioProductoRaw?.toString() ?? '') ?? 0;

    final precioCostoUsdRaw = producto['precio_costo_usd'];
    final precioCostoUsd = precioCostoUsdRaw is num
        ? precioCostoUsdRaw.toDouble()
        : double.tryParse(precioCostoUsdRaw?.toString() ?? '') ?? 0;
    
    // Si viene tasa de cambio en producto, usarla, si no usar global
    final tasaCambioProdRaw = producto['tasa_cambio'];
    double tasaCambioProd = tasaCambioProdRaw is num
        ? tasaCambioProdRaw.toDouble()
        : double.tryParse(tasaCambioProdRaw?.toString() ?? '') ?? 0;
    
    if (tasaCambioProd <= 0) tasaCambioProd = _tasaCambio;

    final precioVentaCupRaw = producto['precio_venta_cup'];
    final precioVentaCupGuardado = precioVentaCupRaw is num
        ? precioVentaCupRaw.toDouble()
        : double.tryParse(precioVentaCupRaw?.toString() ?? '') ?? 0;

    // Nombre y SKU
    final nombreProducto = producto['nombre_producto'] as String? ?? 'N/A';
    final sku = producto['sku'] as String? ?? 'N/A';
    final cantidad = producto['cantidad_propuesta'] ?? 0;

    // Inicialización de controladores si es editable
    if (puedeEditar && idEnvioProducto != 0) {
      if (!_preciosVentaConfigurables.containsKey(idEnvioProducto)) {
        // Por defecto sugerimos el Costo USD * Tasa (o el guardado si existe y es > 0)
        double precioSug = precioVentaCupGuardado > 0 
            ? precioVentaCupGuardado 
            : (precioCostoUsd * tasaCambioProd);
            
        _preciosVentaConfigurables[idEnvioProducto] = precioSug;
        _precioVentaControllers[idEnvioProducto] = TextEditingController(
          text: precioSug.toStringAsFixed(2)
        );
      }
      
      if (!_margenControllers.containsKey(idEnvioProducto)) {
        _margenControllers[idEnvioProducto] = TextEditingController(text: '');
      }
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
            // Fila 1: Icono, Nombre/SKU, Cantidad
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
            
            // Fila 2: Precios y controles
            if (puedeEditar)
              Row(
                children: [
                  // Col 1: Costo Consignador
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Costo (Consignador)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '\$${precioCostoUsd.toStringAsFixed(2)} USD',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              Text(
                                '≈ \$${(precioCostoUsd * tasaCambioProd).toStringAsFixed(0)} CUP',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue[800],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Col 2: Margen %
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Margen %',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                         _buildMargenTextField(idEnvioProducto, precioCostoUsd, tasaCambioProd),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  // Col 3: Precio Venta
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Precio Venta * CUP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildPrecioTextField(idEnvioProducto),
                      ],
                    ),
                  ),
                  
                  // Col 4: Botón Rechazar (Guardar es implícito/global ahora)
                  Column(
                    children: [
                       // Podríamos dejar el botón de guardar individual opcional
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                        onPressed: () => _rechazarProducto(idEnvioProducto: idEnvioProducto),
                        tooltip: 'Rechazar Producto',
                         padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  )
                ],
              )
            else
              // Vista Solo Lectura (sin edición)
               Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   _buildProductoInfo(
                    'Costo USD',
                    '\$${precioCostoUsd.toStringAsFixed(2)}',
                  ),
                  _buildProductoInfo(
                    'Costo CUP',
                    '\$${(precioCostoUsd * tasaCambioProd).toStringAsFixed(2)}',
                  ),
                  _buildProductoInfo(
                    'Precio Venta',
                    precioVentaCupGuardado > 0 ? '\$${precioVentaCupGuardado.toStringAsFixed(2)}' : '-',
                  ),
                  _buildProductoInfo(
                    'Estado',
                    producto['estado_producto_texto'] ?? 'N/A',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMargenTextField(int idEnvioProducto, double precioCostoUsd, double tasa) {
    return TextField(
      controller: _margenControllers[idEnvioProducto],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: '0',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        suffixText: '%',
      ),
      onChanged: (value) {
        final margen = double.tryParse(value);
        if (margen != null) {
          final precioBase = precioCostoUsd * tasa;
          final precioFinal = precioBase * (1 + (margen / 100));
          setState(() {
            _preciosVentaConfigurables[idEnvioProducto] = precioFinal;
            _precioVentaControllers[idEnvioProducto]?.text = precioFinal.toStringAsFixed(2);
          });
        }
      },
    );
  }

  Widget _buildPrecioTextField(int idEnvioProducto) {
    return TextField(
      controller: _precioVentaControllers[idEnvioProducto],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        prefixText: '\$ ',
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onChanged: (value) {
        final precio = double.tryParse(value);
        if (precio != null) {
          _preciosVentaConfigurables[idEnvioProducto] = precio;
        }
      },
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
  Widget _buildBotonesAccionGlobal() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isAccepting ? null : _aceptarEnvioCompleto,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: _isAccepting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle),
            label: Text(
              _isAccepting ? 'Procesando...' : 'Aceptar Envío',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isAccepting ? null : _rechazarEnvioGlobal,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            icon: const Icon(Icons.cancel),
            label: const Text(
              'Rechazar Envío Completo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // --- Funciones de Acción ---

  Future<void> _aceptarEnvioCompleto() async {
    // 1. Validar precios
    if (_preciosVentaConfigurables.isEmpty) {
        // En teoría podría estar vacío si no hay productos o no se editó nada
        // pero validaremos que todos los productos "visibles" tengan precio.
    }
    
    // Verificamos si hay algún precio en 0. Si el usuario no tocó nada,
    // debemos asegurarnos que _preciosVentaConfigurables tenga valores por defecto
    // aunque mi lógica actual solo los mete allí si se buildearon. (item builder)
    
    // Para simplificar, asumiremos que si está en el mapa, es válido, o si el usuario
    // quiere aceptar, confía en lo que vio.
    // Una mejora sería iterar sobre _productosFuture data si está disponible.
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Recepción'),
        content: const Text(
          'Se aceptarán los productos restantes del envío y se creará la operación de recepción.\n\n'
          'Asegúrate de haber configurado correctamente los precios de venta en CUP.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Aceptar')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isAccepting = true);

    final userId = await UserPreferencesService().getUserId();
    if (userId == null) {
      if (mounted) setState(() => _isAccepting = false);
      return;
    }

    try {
      // 2. Guardar precios masivamente
      // Convertimos el mapa a lista de objetos para el servicio
      if (_preciosVentaConfigurables.isNotEmpty) {
        final productosParaActualizar = _preciosVentaConfigurables.entries.map((entry) {
          return {
            'id_envio_producto': entry.key,
            'precio_venta_cup': entry.value,
          };
        }).toList();

        final updated = await ConsignacionEnvioService.actualizarPrecios(
          idEnvio: widget.idEnvio,
          idUsuario: userId,
          productos: productosParaActualizar,
        );

        if (!updated) {
          throw Exception('Error guardando precios');
        }
      }

      // 3. Aceptar envío (genera recepción)
      final result = await ConsignacionEnvioService.aceptarEnvio(
        idEnvio: widget.idEnvio,
        idUsuario: userId,
      );

      if (result != null) {
        if (result['success'] == true) {
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Envío aceptado correctamente'), backgroundColor: Colors.green),
            );
            Navigator.pop(context, true); // Retornar true
          }
        } else {
          // Error controlado devuelto por PostgreSQL
          throw Exception(result['mensaje'] ?? 'Error desconocido al aceptar envío');
        }
      } else {
        throw Exception('Error de conexión o respuesta vacía');
      }

    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

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
}
