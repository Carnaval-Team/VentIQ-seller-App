import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../services/consignacion_envio_service.dart';
import '../services/currency_service.dart';

class AsignarProductosConsignacionScreen extends StatefulWidget {
  final int idContrato;
  final Map<String, dynamic> contrato;
  final bool isDevolucion;

  const AsignarProductosConsignacionScreen({
    Key? key,
    required this.idContrato,
    required this.contrato,
    this.isDevolucion = false,
  }) : super(key: key);

  @override
  State<AsignarProductosConsignacionScreen> createState() => _AsignarProductosConsignacionScreenState();
}

class _AsignarProductosConsignacionScreenState extends State<AsignarProductosConsignacionScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _almacenes = [];
  Map<int, Map<String, dynamic>> _productosSeleccionados = {}; // id_inventario -> {seleccionado, cantidad}
  bool _procediendo = false; // ✅ Estado de carga
  
  // Estados de expansión
  Map<String, bool> _expandedAlmacenes = {}; // almacen_id -> expandido
  Map<String, bool> _expandedZonas = {}; // almacen_id_zona_id -> expandido
  Map<String, List<Map<String, dynamic>>> _zonasInventario = {}; // almacen_id_zona_id -> productos
  Map<String, bool> _loadingZonas = {}; // almacen_id_zona_id -> cargando
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlmacenes();
  }

  Future<void> _loadAlmacenes() async {
    setState(() => _isLoading = true);

    try {
      final idTienda = widget.isDevolucion 
          ? widget.contrato['id_tienda_consignataria'] as int
          : widget.contrato['id_tienda_consignadora'] as int;

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
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _toggleProductoSeleccion(int idInventario) {
    setState(() {
      if (_productosSeleccionados[idInventario]?['seleccionado'] == true) {
        _productosSeleccionados[idInventario] = {'seleccionado': false, 'cantidad': 0.0};
      } else {
        _productosSeleccionados[idInventario] = {'seleccionado': true, 'cantidad': 0.0};
      }
    });
  }

  void _actualizarCantidad(int idInventario, double cantidad) {
    setState(() {
      if (_productosSeleccionados[idInventario] == null) {
        _productosSeleccionados[idInventario] = {'seleccionado': false, 'cantidad': cantidad};
      } else {
        _productosSeleccionados[idInventario]!['cantidad'] = cantidad;
      }
    });
  }

  Future<void> _procederConConfiguracion() async {
    final productosIds = _productosSeleccionados.entries
        .where((e) => e.value['seleccionado'] == true)
        .map((e) => e.key)
        .toList();

    if (productosIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar al menos un producto'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Validar cantidades
    for (final id in productosIds) {
      if ((_productosSeleccionados[id]?['cantidad'] ?? 0) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todos los productos seleccionados deben tener cantidad > 0'), backgroundColor: Colors.orange),
        );
        return;
      }
    }

    setState(() => _procediendo = true);

    try {
      final tasaCambio = await _obtenerTasaCambio();
      
      final response = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id,
            cantidad_final,
            id_producto,
            id_ubicacion,
            id_presentacion,
            id_variante,
            id_opcion_variante,
            app_dat_producto(
              id,
              denominacion,
              sku
            ),
            app_dat_producto_presentacion(
              precio_promedio
            )
          ''')
          .inFilter('id', productosIds);

      final productosData = List<Map<String, dynamic>>.from(response);
      
      for (final p in productosData) {
        final idInv = p['id'] as int;
        final cantSel = _productosSeleccionados[idInv]?['cantidad'] as double? ?? 0.0;
        p['cantidad_seleccionada'] = cantSel;
        p['tasa_cambio'] = tasaCambio;

        // Precios
        final idProducto = p['id_producto'];
        final precioVentaResp = await _supabase.from('app_dat_precio_venta').select('precio_venta_cup').eq('id_producto', idProducto).limit(1);
        p['precio_venta'] = (precioVentaResp as List).isNotEmpty ? (precioVentaResp[0]['precio_venta_cup'] ?? 0).toDouble() : 0.0;

        final pres = p['app_dat_producto_presentacion'];
        double costUSD = 0.0;
        if (pres != null) {
          costUSD = (pres is List && pres.isNotEmpty) ? (pres[0]['precio_promedio'] ?? 0).toDouble() : (pres is Map ? (pres['precio_promedio'] ?? 0).toDouble() : 0.0);
        }
        p['precio_costo_usd'] = costUSD;
        p['precio_costo_cup'] = costUSD * tasaCambio;
      }

      if (widget.isDevolucion) {
        await _procederConCreacionDevolucion(productosData);
        return;
      }

      // Proceso normal de envío (congelar stock y configurar precios)
      final idTiendaConsignadora = widget.contrato['id_tienda_consignadora'] as int;
      final idOperacionReserva = await ConsignacionService.crearReservaStock(
        idContrato: widget.idContrato,
        productos: productosData.map((p) => {
          'id_producto': p['id_producto'],
          'cantidad': p['cantidad_seleccionada'],
          'id_presentacion': p['id_presentacion'],
          'id_ubicacion': p['id_ubicacion'],
          'id_variante': p['id_variante'],
          'id_opcion_variante': p['id_opcion_variante'],
          'precio_costo_unitario': p['precio_costo_usd'],
        }).toList(),
        idTiendaOrigen: idTiendaConsignadora,
      );

      setState(() => _procediendo = false);
      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ConsignacionProductosConfigScreen(
            productos: productosData,
            contrato: widget.contrato,
            idOperacionExtraccion: idOperacionReserva,
            onConfirm: (finalProductos, opId) async {
              final user = _supabase.auth.currentUser;
              if (user == null) return;

              final idAlmacenDestino = widget.contrato['id_almacen_destino'] as int?;
              if (idAlmacenDestino == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: El contrato no tiene un almacén destino configurado'), backgroundColor: Colors.red));
                }
                return;
              }

              final envioResult = await ConsignacionEnvioService.crearEnvio(
                idContrato: widget.idContrato,
                idAlmacenOrigen: productosData[0]['id_ubicacion'],
                idAlmacenDestino: idAlmacenDestino,
                idUsuario: user.id,
                productos: finalProductos,
                idOperacionExtraccion: opId,
              );

              if (envioResult != null) {
                Navigator.pop(context); // Cerrar config
                Navigator.pop(context, true); // Volver al listado
              }
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error en el proceso: $e');
      setState(() => _procediendo = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _procederConCreacionDevolucion(List<Map<String, dynamic>> productos) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final idTiendaConsignataria = widget.contrato['id_tienda_consignataria'] as int;
      final almacenes = await _supabase.from('app_dat_almacen').select('id').eq('id_tienda', idTiendaConsignataria).limit(1);
      final idAlmacenOrigen = (almacenes as List).isNotEmpty ? almacenes[0]['id'] as int : 0;

      final productosParaDevolucion = productos.map((p) => {
        'id_inventario': p['id'] as int,
        'id_producto': p['id_producto'],
        'cantidad': p['cantidad_seleccionada'],
        'precio_costo_usd': p['precio_costo_usd'],
        'precio_costo_cup': p['precio_costo_cup'],
        'tasa_cambio': p['tasa_cambio'],
      }).toList();

      final result = await ConsignacionEnvioService.crearDevolucion(
        idContrato: widget.idContrato,
        idAlmacenOrigen: idAlmacenOrigen,
        idUsuario: user.id,
        productos: productosParaDevolucion,
        descripcion: 'Devolución de productos - ${widget.contrato['tienda_consignataria']['denominacion']}',
      );

      setState(() => _procediendo = false);
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Devolución solicitada: ${result['numero_envio']}'), backgroundColor: Colors.green));
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error creando devolución: $e');
      setState(() => _procediendo = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool haySeleccion = _productosSeleccionados.values.any((v) => v['seleccionado'] == true);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDevolucion ? 'Crear Devolución' : 'Asignar Productos en Consignación'),
        backgroundColor: widget.isDevolucion ? Colors.deepOrange : AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.handshake, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.isDevolucion 
                            ? 'Devolver a: ${widget.contrato['tienda_consignadora']['denominacion']}'
                            : 'Contrato con: ${widget.contrato['tienda_consignataria']['denominacion']}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _almacenes.isEmpty
                      ? const Center(child: Text('No hay almacenes disponibles'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _almacenes.length,
                          itemBuilder: (context, index) => _buildAlmacenCard(_almacenes[index]),
                        ),
                ),
                if (haySeleccion)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _procediendo ? null : _procederConConfiguracion,
                        icon: _procediendo ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(widget.isDevolucion ? Icons.replay : Icons.arrow_forward),
                        label: Text(_procediendo ? 'Procesando...' : (widget.isDevolucion ? 'Solicitar Devolución' : 'Configurar Productos')),
                        style: ElevatedButton.styleFrom(backgroundColor: widget.isDevolucion ? Colors.deepOrange : AppColors.primary, foregroundColor: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildAlmacenCard(Map<String, dynamic> almacen) {
    final idStr = almacen['id'].toString();
    final isExpanded = _expandedAlmacenes[idStr] ?? false;
    final zonas = almacen['zonas'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.warehouse, color: AppColors.primary),
            title: Text(almacen['denominacion']),
            subtitle: Text('${zonas.length} zonas'),
            trailing: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expandedAlmacenes[idStr] = !isExpanded),
          ),
          if (isExpanded) ...zonas.map((z) => _buildZonaCard(idStr, z)).toList(),
        ],
      ),
    );
  }

  Widget _buildZonaCard(String almId, Map<String, dynamic> zona) {
    final zonaId = zona['id'].toString();
    final key = '${almId}_$zonaId';
    final isExp = _expandedZonas[key] ?? false;
    final loading = _loadingZonas[key] ?? false;
    final prods = _zonasInventario[key] ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              if (!isExp && _zonasInventario[key] == null) await _loadZonaProductos(key, zonaId);
              setState(() => _expandedZonas[key] = !isExp);
            },
            child: Row(
              children: [
                Icon(isExp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(zona['denominacion'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                if (loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          if (isExp) ...[
            const SizedBox(height: 8),
            if (prods.isEmpty && !loading) const Text('Sin productos en esta zona', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ...prods.map((p) => _buildProductoTile(p)).toList(),
          ],
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildProductoTile(Map<String, dynamic> producto) {
    final idInv = producto['id'] as int;
    final isSelected = _productosSeleccionados[idInv]?['seleccionado'] == true;
    final cant = _productosSeleccionados[idInv]?['cantidad'] as double? ?? 0.0;
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? AppColors.primary : Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Checkbox(value: isSelected, onChanged: (_) => _toggleProductoSeleccion(idInv)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(producto['denominacion_producto'] ?? 'Producto', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('SKU: ${producto['sku_producto'] ?? 'N/A'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          if (isSelected)
            SizedBox(
              width: 70,
              child: TextFormField(
                initialValue: cant > 0 ? cant.toString() : '',
                decoration: const InputDecoration(isDense: true, labelText: 'Cant.', contentPadding: EdgeInsets.all(8), border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) => _actualizarCantidad(idInv, double.tryParse(val) ?? 0.0),
              ),
            ),
          const SizedBox(width: 8),
          Text('${(producto['cantidad_final'] ?? 0).toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _loadZonaProductos(String key, String zonaId) async {
    setState(() => _loadingZonas[key] = true);
    try {
      final response = await _supabase.rpc('get_productos_zona_consignacion', params: {'p_id_ubicacion': int.parse(zonaId)}) as List;
      setState(() {
        _zonasInventario[key] = List<Map<String, dynamic>>.from(response);
        _loadingZonas[key] = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _loadingZonas[key] = false);
    }
  }

  Future<double> _obtenerTasaCambio() async {
    try {
      final rates = await CurrencyService.fetchExchangeRates();
      return rates.usd.value;
    } catch (e) {
      return 440.0;
    }
  }
}

class ConsignacionProductosConfigScreen extends StatefulWidget {
  final List<Map<String, dynamic>> productos;
  final Map<String, dynamic> contrato;
  final int? idOperacionExtraccion;
  final Function(List<Map<String, dynamic>>, int?) onConfirm;

  const ConsignacionProductosConfigScreen({
    Key? key,
    required this.productos,
    required this.contrato,
    this.idOperacionExtraccion,
    required this.onConfirm,
  }) : super(key: key);

  @override
  State<ConsignacionProductosConfigScreen> createState() => _ConsignacionProductosConfigScreenState();
}

class _ConsignacionProductosConfigScreenState extends State<ConsignacionProductosConfigScreen> {
  late Map<int, Map<String, dynamic>> _productosConfig;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _productosConfig = {};
    for (var p in widget.productos) {
      _productosConfig[p['id']] = {
        'cantidad': p['cantidad_seleccionada'],
        'precio_venta': p['precio_venta'] > 0 ? p['precio_venta'] : null,
      };
    }
  }

  void _confirmar() {
    for (var config in _productosConfig.values) {
      if ((config['precio_venta'] ?? 0) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todos los productos deben tener un precio de venta'), backgroundColor: Colors.orange));
        return;
      }
    }

    final finalProds = widget.productos.map((p) {
      final config = _productosConfig[p['id']]!;
      final tasa = p['tasa_cambio'] ?? 440.0;
      return {
        'id_producto': p['id_producto'],
        'id_variante': p['id_variante'],
        'id_ubicacion': p['id_ubicacion'],
        'id_presentacion': p['id_presentacion'],
        'cantidad': config['cantidad'],
        'precio_costo_unitario': (config['precio_venta'] as double) / tasa,
        'puede_modificar_precio': false,
        'nombre_producto': p['app_dat_producto']?['denominacion'] ?? 'Producto',
      };
    }).toList();

    widget.onConfirm(finalProds, widget.idOperacionExtraccion);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar Precios de Venta'), backgroundColor: AppColors.primary, foregroundColor: Colors.white),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.productos.length,
              itemBuilder: (context, index) {
                final p = widget.productos[index];
                final config = _productosConfig[p['id']]!;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['app_dat_producto']?['denominacion'] ?? 'Producto', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Precio Costo Sugerido: \$${(p['precio_costo_cup'] ?? 0).toStringAsFixed(2)} CUP'),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: config['precio_venta']?.toString() ?? '',
                          decoration: const InputDecoration(labelText: 'Precio de Venta Final (CUP)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.attach_money)),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (val) => setState(() => config['precio_venta'] = double.tryParse(val)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(onPressed: _confirmar, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white), child: const Text('CONFIRMAR ENVÍO')),
            ),
          ),
        ],
      ),
    );
  }
}
