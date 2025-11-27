import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/currency_service.dart';

class AsignarProductosConsignacionScreen extends StatefulWidget {
  final int idContrato;
  final Map<String, dynamic> contrato;

  const AsignarProductosConsignacionScreen({
    Key? key,
    required this.idContrato,
    required this.contrato,
  }) : super(key: key);

  @override
  State<AsignarProductosConsignacionScreen> createState() => _AsignarProductosConsignacionScreenState();
}

class _AsignarProductosConsignacionScreenState extends State<AsignarProductosConsignacionScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _almacenes = [];
  Map<int, bool> _productosSeleccionados = {}; // id_inventario -> seleccionado
  
  // Estados de expansión
  Map<String, bool> _expandedAlmacenes = {}; // almacen_id -> expandido
  Map<String, bool> _expandedZonas = {}; // almacen_id_zona_id -> expandido
  Map<String, List<Map<String, dynamic>>> _zonasInventario = {}; // almacen_id_zona_id -> productos
  Map<String, bool> _loadingZonas = {}; // almacen_id_zona_id -> cargando
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAlmacenes();
  }

  Future<void> _loadAlmacenes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final idTienda = widget.contrato['id_tienda_consignadora'] as int;

      final response = await _supabase
          .from('app_dat_almacen')
          .select('''
            id,
            denominacion,
            app_dat_layout_almacen(
              id,
              denominacion,
              sku_codigo
            )
          ''')
          .eq('id_tienda', idTienda);

      // Procesar respuesta para agregar zonas
      final almacenesConZonas = (response as List).map((almacen) {
        final zonas = almacen['app_dat_layout_almacen'] as List? ?? [];
        return {
          ...almacen as Map<String, dynamic>,
          'zonas': zonas,
        };
      }).toList();

      setState(() {
        _almacenes = almacenesConZonas;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error cargando almacenes: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _toggleProductoSeleccion(int idInventario) {
    setState(() {
      _productosSeleccionados[idInventario] = !(_productosSeleccionados[idInventario] ?? false);
    });
  }

  Future<void> _procederConConfiguracion() async {
    final productosSeleccionados = _productosSeleccionados.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    if (productosSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Cargar datos completos de los productos seleccionados
    try {
      // Obtener tasa de cambio USD a CUP
      final tasaCambio = await _obtenerTasaCambio();
      
      final response = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id,
            cantidad_final,
            id_producto,
            id_ubicacion,
            id_presentacion,
            app_dat_producto(
              id,
              denominacion,
              sku
            ),
            app_dat_producto_presentacion(
              precio_promedio
            )
          ''')
          .inFilter('id', productosSeleccionados);

      if (!mounted) return;

      // Obtener precios de venta para cada producto
      final productosData = List<Map<String, dynamic>>.from(response);
      for (final producto in productosData) {
        final idProducto = producto['id_producto'];
        try {
          final precioVentaResponse = await _supabase
              .from('app_dat_precio_venta')
              .select('precio_venta_cup')
              .eq('id_producto', idProducto)
              .limit(1);
          
          final precioVenta = (precioVentaResponse as List).isNotEmpty
              ? (precioVentaResponse[0]['precio_venta_cup'] ?? 0).toDouble()
              : 0.0;
          
          producto['precio_venta'] = precioVenta;
          
          // Convertir precio_promedio (USD) a CUP
          final presentacion = producto['app_dat_producto_presentacion'];
          if (presentacion != null) {
            double precioCostoUSD = 0.0;
            if (presentacion is List && presentacion.isNotEmpty) {
              precioCostoUSD = (presentacion[0]['precio_promedio'] ?? 0).toDouble();
            } else if (presentacion is Map) {
              precioCostoUSD = (presentacion['precio_promedio'] ?? 0).toDouble();
            }
            // Guardar el precio en CUP
            producto['precio_costo_cup'] = precioCostoUSD * tasaCambio;
          }
        } catch (e) {
          debugPrint('Error obteniendo precio de venta: $e');
          producto['precio_venta'] = 0.0;
          producto['precio_costo_cup'] = 0.0;
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConsignacionProductosConfigScreen(
            productos: productosData,
            contrato: widget.contrato,
            onConfirm: (productosConfigurados) async {
              // Obtener datos del contrato para la auditoría
              final idTiendaConsignadora = widget.contrato['id_tienda_consignadora'] as int;
              final idTiendaConsignataria = widget.contrato['id_tienda_consignataria'] as int;
              final nombreTiendaConsignadora = widget.contrato['tienda_consignadora']?['denominacion'] ?? 'Tienda';
              
              // Obtener almacén destino del contrato (ya fue seleccionado en otra vista)
              final idAlmacenDestino = widget.contrato['id_almacen_destino'] as int?;

              /* if (idAlmacenDestino == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ Error: El almacén destino no ha sido seleccionado'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              } */

              // Obtener almacén origen (el primero disponible de la tienda consignadora)
              int? idAlmacenOrigen;
              try {
                final almacenesOrigen = await _supabase
                    .from('app_dat_almacen')
                    .select('id')
                    .eq('id_tienda', idTiendaConsignadora)
                    .limit(1);
                
                if ((almacenesOrigen as List).isNotEmpty) {
                  idAlmacenOrigen = almacenesOrigen[0]['id'] as int;
                }
              } catch (e) {
                debugPrint('Error obteniendo almacén origen: $e');
              }

              final success = await ConsignacionService.asignarProductos(
                idContrato: widget.idContrato,
                productos: productosConfigurados,
                idAlmacenOrigen: idAlmacenOrigen,
                idTiendaOrigen: idTiendaConsignadora,
                idTiendaDestino: idTiendaConsignataria,
                nombreTiendaConsignadora: nombreTiendaConsignadora,
                idAlmacenDestino: idAlmacenDestino,
              );

              if (!mounted) return;

              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Productos asignados exitosamente'),
                    backgroundColor: Colors.green,
                  ),
                );
                // Cerrar pantalla de configuración
                Navigator.pop(context);
                // Esperar un poco y cerrar pantalla de asignación
                await Future.delayed(const Duration(milliseconds: 300));
                if (mounted) {
                  Navigator.pop(context, true);
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Error al asignar productos'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error cargando productos: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asignar Productos en Consignación'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_productosSeleccionados.values.any((v) => v))
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  label: Text('${_productosSeleccionados.values.where((v) => v).length}'),
                  backgroundColor: Colors.white,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Información del contrato
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.handshake, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contrato con: ${widget.contrato['tienda_consignataria']['denominacion']}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            Text(
                              'Comisión: ${widget.contrato['porcentaje_comision']}%',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Almacenes y productos
                Expanded(
                  child: _almacenes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.warehouse_outlined, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No hay almacenes con productos disponibles',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _almacenes.length,
                          itemBuilder: (context, index) {
                            return _buildAlmacenCard(_almacenes[index]);
                          },
                        ),
                ),

                // Botón proceder
                if (_productosSeleccionados.values.any((v) => v))
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _procederConConfiguracion,
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Configurar Productos'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildAlmacenCard(Map<String, dynamic> almacen) {
    final almacenId = almacen['id'].toString();
    final isExpanded = _expandedAlmacenes[almacenId] ?? false;
    final zonas = almacen['zonas'] as List<dynamic>? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header del almacén
          InkWell(
            onTap: () {
              setState(() {
                _expandedAlmacenes[almacenId] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warehouse,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          almacen['denominacion'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${zonas.length} zonas',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Zonas expandidas
          if (isExpanded && zonas.isNotEmpty) ...[
            const Divider(height: 1),
            ...zonas.map((zona) => _buildZonaCard(almacenId, zona as Map<String, dynamic>)).toList(),
          ],
          if (isExpanded && zonas.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: const Center(
                child: Text(
                  'No hay zonas configuradas en este almacén',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildZonaCard(String almacenId, Map<String, dynamic> zona) {
    final zonaId = zona['id'].toString();
    final zonaKey = '${almacenId}_$zonaId';
    final isExpanded = _expandedZonas[zonaKey] ?? false;
    final isLoading = _loadingZonas[zonaKey] ?? false;
    final productos = _zonasInventario[zonaKey] ?? [];

    return Container(
      margin: EdgeInsets.only(left: 16.0, right: 16, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Header de la zona
          InkWell(
            onTap: () async {
              if (!isExpanded && _zonasInventario[zonaKey] == null) {
                await _loadZonaProductos(zonaKey, zonaId);
              }
              setState(() {
                _expandedZonas[zonaKey] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.layers_outlined,
                      color: AppColors.secondary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zona['denominacion'] ?? 'Zona',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          zona['sku_codigo'] ?? 'sin_codigo',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  else
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
          // Productos expandidos
          if (isExpanded) ...[
            const Divider(height: 1),
            if (isLoading)
              Container(
                padding: const EdgeInsets.all(20),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (productos.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'No hay productos en esta zona',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: productos.map((producto) {
                    return _buildProductoTile(producto);
                  }).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductoTile(Map<String, dynamic> producto) {
    final nombreProducto = producto['app_dat_producto']?['denominacion'] ?? 'Producto';
    final sku = producto['app_dat_producto']?['sku'] ?? 'N/A';
    final stockDisponible = (producto['cantidad_final'] ?? 0).toDouble();
    final idInventario = producto['id'] as int;
    final isSelected = _productosSeleccionados[idInventario] ?? false;
    
    // Obtener precio de costo (precio_promedio de presentación)
    double precioCosto = 0.0;
    try {
      final presentacion = producto['app_dat_producto_presentacion'];
      if (presentacion != null) {
        if (presentacion is List && presentacion.isNotEmpty) {
          precioCosto = (presentacion[0]['precio_promedio'] ?? 0).toDouble();
        } else if (presentacion is Map) {
          precioCosto = (presentacion['precio_promedio'] ?? 0).toDouble();
        }
      }
    } catch (e) {
      debugPrint('Error extrayendo precio de costo: $e');
      precioCosto = 0.0;
    }

    // Obtener precio de venta
    double precioVenta = (producto['precio_venta'] ?? 0).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? AppColors.primary : Colors.grey.withOpacity(0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (_) => _toggleProductoSeleccion(idInventario),
            activeColor: AppColors.primary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreProducto,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? AppColors.primary : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Fila con SKU y precios
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'SKU: $sku',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: stockDisponible > 0
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${stockDisponible.toInt()}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: stockDisponible > 0 ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadZonaProductos(String zonaKey, String zonaId) async {
    setState(() {
      _loadingZonas[zonaKey] = true;
    });

    try {
      final response = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id,
            cantidad_final,
            id_producto,
            id_presentacion,
            app_dat_producto(
              id,
              denominacion,
              sku
            ),
            app_dat_producto_presentacion(
              precio_promedio
            )
          ''')
          .eq('id_ubicacion', zonaId)
          .gt('cantidad_final', 0)
          .order('id', ascending: false); // Ordenar por ID descendente para obtener el más reciente

      // Obtener precios de venta para cada producto
      final productosConPrecios = [];
      for (final item in response as List) {
        final idProducto = item['id_producto'];
        try {
          final precioVentaResponse = await _supabase
              .from('app_dat_precio_venta')
              .select('precio_venta_cup')
              .eq('id_producto', idProducto)
              .limit(1);
          
          final precioVenta = (precioVentaResponse as List).isNotEmpty
              ? (precioVentaResponse[0]['precio_venta_cup'] ?? 0).toDouble()
              : 0.0;
          
          item['precio_venta'] = precioVenta;
        } catch (e) {
          debugPrint('Error obteniendo precio de venta: $e');
          item['precio_venta'] = 0.0;
        }
        productosConPrecios.add(item);
      }

      // Agrupar por producto-presentación y obtener solo el último
      final Map<String, Map<String, dynamic>> productosAgrupados = {};
      
      for (final item in productosConPrecios) {
        final idProducto = item['id_producto'];
        final idPresentacion = item['id_presentacion'] ?? 0;
        final key = '${idProducto}_$idPresentacion';
        
        // Solo guardar si no existe (el primero es el más reciente por el order)
        if (!productosAgrupados.containsKey(key)) {
          productosAgrupados[key] = item as Map<String, dynamic>;
        }
      }

      // Convertir a lista y ordenar por nombre de producto
      final productosFiltrados = productosAgrupados.values.toList();
      productosFiltrados.sort((a, b) {
        final nombreA = a['app_dat_producto']?['denominacion'] ?? '';
        final nombreB = b['app_dat_producto']?['denominacion'] ?? '';
        return nombreA.compareTo(nombreB);
      });

      setState(() {
        _zonasInventario[zonaKey] = productosFiltrados;
        _loadingZonas[zonaKey] = false;
      });
    } catch (e) {
      debugPrint('Error cargando productos de zona: $e');
      setState(() {
        _zonasInventario[zonaKey] = [];
        _loadingZonas[zonaKey] = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadProductosAlmacen(int idAlmacen) async {
    try {
      final response = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id,
            cantidad_final,
            id_producto,
            app_dat_producto(
              id,
              denominacion,
              sku
            )
          ''')
          .eq('id_ubicacion', idAlmacen)
          .gt('cantidad_final', 0)
          .order('app_dat_producto(denominacion)');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error cargando productos: $e');
      return [];
    }
  }

  /// Obtiene la tasa de cambio actual USD a CUP
  Future<double> _obtenerTasaCambio() async {
    try {
      // Intentar obtener tasas desde el servicio
      final rates = await CurrencyService.fetchExchangeRates();
      final tasaUSD = rates.usd.value;
      debugPrint('💱 Tasa de cambio USD a CUP: $tasaUSD');
      return tasaUSD;
    } catch (e) {
      debugPrint('❌ Error obteniendo tasa de cambio: $e');
      // Valor por defecto si hay error
      return 440.0;
    }
  }
}

/// Pantalla para configurar múltiples productos en consignación
class ConsignacionProductosConfigScreen extends StatefulWidget {
  final List<Map<String, dynamic>> productos;
  final Map<String, dynamic> contrato;
  final Function(List<Map<String, dynamic>>) onConfirm;

  const ConsignacionProductosConfigScreen({
    Key? key,
    required this.productos,
    required this.contrato,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<ConsignacionProductosConfigScreen> createState() =>
      _ConsignacionProductosConfigScreenState();
}

class _ConsignacionProductosConfigScreenState
    extends State<ConsignacionProductosConfigScreen> {
  late Map<int, Map<String, dynamic>> _productosConfig; // id_inventario -> config
  List<Map<String, dynamic>> _almacenesDestino = [];
  bool _cargandoAlmacenes = true;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _productosConfig = {};
    // Inicializar configuración para cada producto
    for (final producto in widget.productos) {
      _productosConfig[producto['id']] = {
        'cantidad': 0.0,
        'precio_venta_sugerido': null,
        'puede_modificar_precio': false,
      };
    }
    _loadAlmacenes();
  }

  Future<void> _loadAlmacenes() async {
    try {
      final idTiendaConsignataria = widget.contrato['id_tienda_consignataria'] as int;
      final almacenes = await ConsignacionService.getAlmacenesPorTienda(idTiendaConsignataria);
      
      if (mounted) {
        setState(() {
          _almacenesDestino = almacenes;
          _cargandoAlmacenes = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando almacenes: $e');
      if (mounted) {
        setState(() => _cargandoAlmacenes = false);
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _confirmarConfiguracion() {

    // Validar que todos los productos tengan cantidad > 0
    bool todosValidos = true;
    for (final config in _productosConfig.values) {
      if ((config['cantidad'] as double) <= 0) {
        todosValidos = false;
        break;
      }
    }

    if (!todosValidos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Todos los productos deben tener cantidad > 0'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Construir lista de productos configurados
    final productosConfigurados = <Map<String, dynamic>>[];
    for (final producto in widget.productos) {
      final idInventario = producto['id'] as int;
      final config = _productosConfig[idInventario]!;
      
      productosConfigurados.add({
        'id_producto': producto['id_producto'],
        'id_ubicacion': producto['id_ubicacion'], // Guardar ubicación de origen
        'id_presentacion': producto['id_presentacion'],
        'cantidad': config['cantidad'],
        'precio_venta_sugerido': config['precio_venta_sugerido'],
        'puede_modificar_precio': config['puede_modificar_precio'],
        'nombre_producto': producto['app_dat_producto']?['denominacion'] ?? 'Producto',
      });
    }

    widget.onConfirm(productosConfigurados);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Productos'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Información del contrato
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.handshake, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contrato con: ${widget.contrato['tienda_consignataria']['denominacion']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      Text(
                        'Comisión: ${widget.contrato['porcentaje_comision']}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Lista de productos
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.productos.length,
              itemBuilder: (context, index) {
                final producto = widget.productos[index];
                final idInventario = producto['id'] as int;
                final config = _productosConfig[idInventario]!;
                final nombreProducto = producto['app_dat_producto']?['denominacion'] ?? 'Producto';
                final sku = producto['app_dat_producto']?['sku'] ?? 'N/A';
                final stockDisponible = (producto['cantidad_final'] ?? 0).toDouble();

                // Extraer precio de costo (ya convertido a CUP en _procederConConfiguracion)
                double precioCosto = (producto['precio_costo_cup'] ?? 0).toDouble();

                // Extraer precio de venta
                double precioVenta = (producto['precio_venta'] ?? 0).toDouble();

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nombre y SKU
                        Text(
                          nombreProducto,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SKU: $sku',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Stock: ${stockDisponible.toInt()} unidades',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Detalle de precios
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Detalle de Precios',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Precio de costo
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Precio de Costo:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '\$${precioCosto.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange[700],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Precio de venta
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Precio de Venta:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '\$${precioVenta.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green[700],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Margen
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Margen de Ganancia:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '\$${(precioVenta - precioCosto).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[700],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Cantidad
                        TextFormField(
                          initialValue: config['cantidad'] > 0 ? config['cantidad'].toString() : '',
                          decoration: InputDecoration(
                            labelText: 'Cantidad a transferir',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.inventory),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            setState(() {
                              config['cantidad'] = double.tryParse(value) ?? 0.0;
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Precio sugerido
                        TextFormField(
                          initialValue: config['precio_venta_sugerido']?.toString() ?? '',
                          decoration: InputDecoration(
                            labelText: 'Precio sugerido (Opcional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.attach_money),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            setState(() {
                              config['precio_venta_sugerido'] = value.isEmpty ? null : double.tryParse(value);
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Checkbox: Puede modificar precio
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: config['puede_modificar_precio'] as bool,
                                onChanged: (value) {
                                  setState(() {
                                    config['puede_modificar_precio'] = value ?? false;
                                  });
                                },
                                activeColor: AppColors.primary,
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Consignatario puede modificar precio',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Permitir cambiar el precio sugerido',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
              },
            ),
          ),

          // Botón confirmar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _confirmarConfiguracion,
                    icon: const Icon(Icons.check),
                    label: const Text('Confirmar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
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
