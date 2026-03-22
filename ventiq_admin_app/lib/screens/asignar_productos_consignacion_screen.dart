import 'dart:async';
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
  State<AsignarProductosConsignacionScreen> createState() =>
      _AsignarProductosConsignacionScreenState();
}

class _AsignarProductosConsignacionScreenState
    extends State<AsignarProductosConsignacionScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _almacenes = [];
  Map<int, Map<String, dynamic>> _productosSeleccionados =
      {}; // id_inventario -> {seleccionado, cantidad}
  bool _procediendo = false; // ✅ Estado de carga

  // Extracción en tiempo real
  int? _idExtraccion; // ID de la operación de extracción activa
  Map<int, int> _idExtraccionProducto = {}; // idInventario -> id de app_dat_extraccion_productos
  bool _aplicandoMovimiento = false; // evita doble llamada

  // Controladores por producto para debounce y detección de foco
  final Map<int, TextEditingController> _cantControllers = {};
  final Map<int, FocusNode> _cantFocusNodes = {};
  final Map<int, Timer> _cantTimers = {};

  // Estados de expansión
  Map<String, bool> _expandedAlmacenes = {}; // almacen_id -> expandido
  Map<String, bool> _expandedZonas = {}; // almacen_id_zona_id -> expandido
  Map<String, List<Map<String, dynamic>>> _zonasInventario =
      {}; // almacen_id_zona_id -> productos
  Map<String, bool> _loadingZonas = {}; // almacen_id_zona_id -> cargando
  Map<String, TextEditingController> _zonaSearchControllers = {}; // key -> buscador
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAlmacenes();
  }

  @override
  void dispose() {
    for (final c in _cantControllers.values) {
      c.dispose();
    }
    for (final f in _cantFocusNodes.values) {
      f.dispose();
    }
    for (final t in _cantTimers.values) {
      t.cancel();
    }
    for (final c in _zonaSearchControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Devuelve (y crea si no existe) el TextEditingController para un producto.
  TextEditingController _controllerFor(int idInv) {
    return _cantControllers.putIfAbsent(
      idInv,
      () => TextEditingController(
        text: () {
          final c =
              _productosSeleccionados[idInv]?['cantidad'] as double? ?? 0.0;
          return c > 0 ? c.toStringAsFixed(0) : '';
        }(),
      ),
    );
  }

  /// Devuelve (y crea si no existe) el FocusNode para un producto.
  /// Al perder el foco dispara inmediatamente la confirmación.
  FocusNode _focusNodeFor(int idInv, Map<String, dynamic> producto) {
    if (_cantFocusNodes.containsKey(idInv)) return _cantFocusNodes[idInv]!;
    final fn = FocusNode();
    fn.addListener(() {
      if (!fn.hasFocus) {
        _cantTimers[idInv]?.cancel();
        _confirmarCantidadProducto(idInv, producto);
      }
    });
    _cantFocusNodes[idInv] = fn;
    return fn;
  }

  /// Inicia/reinicia el timer de debounce de 4 segundos para un producto.
  void _scheduleConfirmar(int idInv, Map<String, dynamic> producto) {
    _cantTimers[idInv]?.cancel();
    _cantTimers[idInv] = Timer(
      const Duration(seconds: 4),
      () => _confirmarCantidadProducto(idInv, producto),
    );
  }

  Future<void> _loadAlmacenes() async {
    setState(() => _isLoading = true);

    try {
      final List<dynamic> response;

      if (widget.isDevolucion) {
        // En devoluciones: solo mostrar el almacén destino del contrato (donde están los productos consignados)
        final idAlmacen = widget.contrato['id_almacen_destino'] as int?;
        if (idAlmacen == null) {
          throw Exception(
            'El contrato no tiene un almacén destino configurado',
          );
        }

        response = await _supabase
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
            .eq('id', idAlmacen);
      } else {
        // Para envíos normales: obtener todos los almacenes de la tienda consignadora
        final idTienda = widget.contrato['id_tienda_consignadora'] as int;

        response = await _supabase
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
      }

      final almacenesConZonas =
          response.map((almacen) {
            final zonas = almacen['app_dat_layout_almacen'] as List? ?? [];
            return {...almacen as Map<String, dynamic>, 'zonas': zonas};
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
    final yaSeleccionado =
        _productosSeleccionados[idInventario]?['seleccionado'] == true;
    if (yaSeleccionado) {
      // Si tiene cantidad en la extracción, revertir primero
      if (_idExtraccionProducto.containsKey(idInventario)) {
        _quitarProductoDeExtraccion(idInventario);
      }
    }
    setState(() {
      if (yaSeleccionado) {
        _productosSeleccionados[idInventario] = {
          'seleccionado': false,
          'cantidad': 0.0,
        };
      } else {
        _productosSeleccionados[idInventario] = {
          'seleccionado': true,
          'cantidad': 0.0,
        };
      }
    });
  }

  void _actualizarCantidad(
    int idInventario,
    double cantidad,
    double cantidadDisponible,
  ) {
    // Validar que la cantidad no exceda la disponible
    if (cantidad > cantidadDisponible) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La cantidad no puede exceder $cantidadDisponible unidades disponibles',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      if (_productosSeleccionados[idInventario] == null) {
        _productosSeleccionados[idInventario] = {
          'seleccionado': false,
          'cantidad': cantidad,
        };
      } else {
        _productosSeleccionados[idInventario]!['cantidad'] = cantidad;
      }
    });
  }

  // ────────────────────────────────────────────────────────────────────────
  // Extracción en tiempo real
  // ────────────────────────────────────────────────────────────────────────

  /// Llamado cuando el usuario termina de introducir la cantidad de un producto.
  /// Si no existe extracción la crea; si ya existe agrega el producto.
  Future<void> _confirmarCantidadProducto(
    int idInventario,
    Map<String, dynamic> productoInventario,
  ) async {
    final cantidad =
        _productosSeleccionados[idInventario]?['cantidad'] as double? ?? 0.0;
    if (cantidad <= 0) return;
    if (_aplicandoMovimiento) return;

    _aplicandoMovimiento = true;

    try {
      final uuid = _supabase.auth.currentUser?.id;
      final email = _supabase.auth.currentUser?.email ?? 'Sistema';
      if (uuid == null) throw Exception('Usuario no autenticado');

      final idProducto = productoInventario['id_producto'] as int;
      final idUbicacion = productoInventario['id_ubicacion'] as int?;
      final idPresentacion = productoInventario['id_presentacion'] as int?;
      final idVariante = productoInventario['id_variante'] as int?;
      final idOpcionVariante = productoInventario['id_opcion_variante'] as int?;
      final skuProducto = productoInventario['sku_producto'] as String?;
      final idTiendaConsignadora =
          widget.contrato['id_tienda_consignadora'] as int;

      if (_idExtraccion == null) {
        // ── Primera vez: crear la extracción completa ──────────────────────
        final result = await _supabase.rpc(
          'fn_crear_extraccion_con_movimiento',
          params: {
            'p_autorizado_por': email,
            'p_estado_inicial': 1,
            'p_id_motivo_operacion': 21,
            'p_id_tienda': idTiendaConsignadora,
            'p_observaciones':
                'Envío a consignación - Contrato #${widget.idContrato} (Reserva inicial)',
            'p_productos': [
              {
                'id_producto': idProducto,
                'cantidad': cantidad,
                'id_presentacion': idPresentacion,
                'id_ubicacion': idUbicacion,
                'id_variante': idVariante,
                'id_opcion_variante': idOpcionVariante,
                'precio_unitario': 0,
                'sku_producto': skuProducto,
              }
            ],
            'p_uuid': uuid,
          },
        );

        if (result['status'] != 'success') {
          throw Exception(result['message'] ?? 'Error creando extracción');
        }

        final idOp = result['id_operacion'] as int;

        // Obtener el id de app_dat_extraccion_productos recién creado
        final epRow = await _supabase
            .from('app_dat_extraccion_productos')
            .select('id')
            .eq('id_operacion', idOp)
            .eq('id_producto', idProducto)
            .order('created_at', ascending: false)
            .limit(1)
            .single();

        setState(() {
          _idExtraccion = idOp;
          _idExtraccionProducto[idInventario] = epRow['id'] as int;
        });

        debugPrint(
          '✅ Extracción #$idOp creada con producto inventario #$idInventario',
        );
      } else {
        // ── Extracción ya existe ────────────────────────────────────────────
        final idEPExistente = _idExtraccionProducto[idInventario];

        if (idEPExistente != null) {
          // ── Producto YA está en extracción: actualizar cantidad ───────────
          // 1. Obtener el movimiento de inventario anterior vinculado a este EP
          final invAnterior = await _supabase
              .from('app_dat_inventario_productos')
              .select(
                'id, id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, sku_producto',
              )
              .eq('id_extraccion', idEPExistente)
              .order('created_at', ascending: false)
              .limit(1);

          if ((invAnterior as List).isEmpty) {
            throw Exception(
              'No se encontró movimiento de inventario para EP #$idEPExistente',
            );
          }

          final invPrev = invAnterior[0];
          // cantidad_inicial del movimiento anterior = saldo antes de la extracción original
          final saldoOriginal =
              (invPrev['cantidad_inicial'] as num?)?.toDouble() ?? 0.0;
          final nuevaCantidadFinal = saldoOriginal - cantidad;

          // 2. Revertir movimiento anterior (insertar compensación)
          await _supabase.from('app_dat_inventario_productos').insert({
            'id_producto': invPrev['id_producto'],
            'id_variante': invPrev['id_variante'],
            'id_opcion_variante': invPrev['id_opcion_variante'],
            'id_ubicacion': invPrev['id_ubicacion'],
            'id_presentacion': invPrev['id_presentacion'],
            'cantidad_inicial': invPrev['cantidad_final'],
            'cantidad_final': saldoOriginal,
            'sku_producto': invPrev['sku_producto'],
            'origen_cambio': 2,
            'id_extraccion': idEPExistente,
            'created_at': DateTime.now().toIso8601String(),
          });

          // 3. Actualizar cantidad en extraccion_productos
          await _supabase
              .from('app_dat_extraccion_productos')
              .update({'cantidad': cantidad})
              .eq('id', idEPExistente);

          // 4. Insertar nuevo movimiento con la cantidad actualizada
          await _supabase.from('app_dat_inventario_productos').insert({
            'id_producto': idProducto,
            'id_variante': idVariante,
            'id_opcion_variante': idOpcionVariante,
            'id_ubicacion': idUbicacion,
            'id_presentacion': idPresentacion,
            'cantidad_inicial': saldoOriginal,
            'cantidad_final': nuevaCantidadFinal,
            'sku_producto': skuProducto,
            'origen_cambio': 2,
            'id_extraccion': idEPExistente,
            'created_at': DateTime.now().toIso8601String(),
          });

          debugPrint(
            '🔄 Cantidad actualizada para EP #$idEPExistente: $cantidad (saldo: $nuevaCantidadFinal)',
          );
        } else {
          // ── Producto NUEVO en extracción existente: agregar ───────────────
          // Obtener saldo actual de inventario
          final invRows = await _supabase
              .from('app_dat_inventario_productos')
              .select('cantidad_final')
              .eq('id_producto', idProducto)
              .filter('id_ubicacion', 'eq', idUbicacion)
              .filter(
                'id_presentacion',
                idPresentacion == null ? 'is' : 'eq',
                idPresentacion,
              )
              .filter(
                'id_variante',
                idVariante == null ? 'is' : 'eq',
                idVariante,
              )
              .filter(
                'id_opcion_variante',
                idOpcionVariante == null ? 'is' : 'eq',
                idOpcionVariante,
              )
              .order('created_at', ascending: false)
              .limit(1);

          final cantidadInicial =
              (invRows as List).isNotEmpty
                  ? (invRows[0]['cantidad_final'] as num?)?.toDouble() ?? 0.0
                  : 0.0;
          final cantidadFinal = cantidadInicial - cantidad;

          // Insertar en extraccion_productos
          final epInsert = await _supabase
              .from('app_dat_extraccion_productos')
              .insert({
                'id_operacion': _idExtraccion,
                'id_producto': idProducto,
                'id_variante': idVariante,
                'id_opcion_variante': idOpcionVariante,
                'id_ubicacion': idUbicacion,
                'id_presentacion': idPresentacion,
                'cantidad': cantidad,
                'precio_unitario': 0,
                'sku_producto': skuProducto,
                'created_at': DateTime.now().toIso8601String(),
              })
              .select('id')
              .single();

          final idEP = epInsert['id'] as int;

          // Insertar movimiento de inventario
          await _supabase.from('app_dat_inventario_productos').insert({
            'id_producto': idProducto,
            'id_variante': idVariante,
            'id_opcion_variante': idOpcionVariante,
            'id_ubicacion': idUbicacion,
            'id_presentacion': idPresentacion,
            'cantidad_inicial': cantidadInicial,
            'cantidad_final': cantidadFinal,
            'sku_producto': skuProducto,
            'origen_cambio': 2,
            'id_extraccion': idEP,
            'created_at': DateTime.now().toIso8601String(),
          });

          setState(() {
            _idExtraccionProducto[idInventario] = idEP;
          });

          debugPrint(
            '✅ Producto inventario #$idInventario agregado a extracción #$_idExtraccion',
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cantidad $cantidad reservada para ${productoInventario['denominacion_producto'] ?? 'producto'}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error aplicando movimiento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error aplicando movimiento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _aplicandoMovimiento = false;
    }
  }

  /// Quita un producto de la extracción activa y revierte el movimiento de inventario.
  Future<void> _quitarProductoDeExtraccion(int idInventario) async {
    final idEP = _idExtraccionProducto[idInventario];
    if (idEP == null || _idExtraccion == null) return;

    try {
      // Obtener el movimiento de inventario vinculado a este registro de extracción
      final invRows = await _supabase
          .from('app_dat_inventario_productos')
          .select('id, id_producto, id_variante, id_opcion_variante, id_ubicacion, id_presentacion, cantidad_inicial, cantidad_final, sku_producto')
          .eq('id_extraccion', idEP)
          .order('created_at', ascending: false)
          .limit(1);

      if ((invRows as List).isNotEmpty) {
        final inv = invRows[0];
        // Revertir: el nuevo saldo es cantidad_inicial (antes de la extracción)
        await _supabase.from('app_dat_inventario_productos').insert({
          'id_producto': inv['id_producto'],
          'id_variante': inv['id_variante'],
          'id_opcion_variante': inv['id_opcion_variante'],
          'id_ubicacion': inv['id_ubicacion'],
          'id_presentacion': inv['id_presentacion'],
          'cantidad_inicial': inv['cantidad_final'], // saldo después de extracción
          'cantidad_final': inv['cantidad_inicial'], // revertir al saldo original
          'sku_producto': inv['sku_producto'],
          'origen_cambio': 2,
          'id_extraccion': idEP,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Eliminar de extraccion_productos
      await _supabase
          .from('app_dat_extraccion_productos')
          .delete()
          .eq('id', idEP);

      setState(() {
        _idExtraccionProducto.remove(idInventario);
        // Si no quedan productos en extracción, limpiar el ID
        if (_idExtraccionProducto.isEmpty) {
          _idExtraccion = null;
        }
      });

      debugPrint(
        '↩️ Producto inventario #$idInventario quitado de extracción',
      );
    } catch (e) {
      debugPrint('❌ Error quitando producto de extracción: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error revirtiendo movimiento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Cancela la extracción activa completa y revierte todos los movimientos de inventario.
  Future<void> _cancelarExtraccionPendiente() async {
    if (_idExtraccion == null) return;

    final idOp = _idExtraccion!;
    try {
      // 1. Revertir todos los movimientos de inventario de esta extracción
      for (final idInv in _idExtraccionProducto.keys.toList()) {
        await _quitarProductoDeExtraccion(idInv);
      }

      // 2. Cancelar la operación de extracción (estado 4 = cancelado)
      final uuid = _supabase.auth.currentUser?.id;
      await _supabase.rpc(
        'fn_registrar_cambio_estado_operacion',
        params: {
          'p_id_operacion': idOp,
          'p_nuevo_estado': 4,
          'p_uuid_usuario': uuid,
        },
      );

      debugPrint('↩️ Extracción #$idOp cancelada por regreso del usuario');
    } catch (e) {
      debugPrint('❌ Error cancelando extracción pendiente: $e');
    }
  }

  /// Muestra diálogo de confirmación de cancelación y navega atrás si se confirma.
  Future<void> _onBackPressed() async {
    if (_idExtraccion != null) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Cancelar extracción'),
              content: const Text(
                '¿Desea cancelar la extracción en curso? Se revertirán todos los movimientos de inventario.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('Sí, cancelar'),
                ),
              ],
            ),
      );
      if (confirmar == true) {
        await _cancelarExtraccionPendiente();
        if (mounted) Navigator.pop(context);
      }
    } else {
      Navigator.pop(context);
    }
  }

  /// Verifica que la extracción activa contenga exactamente los productos seleccionados.
  /// Retorna true si todo coincide o no hay extracción aún.
  Future<bool> _reconciliarExtraccion() async {
    if (_idExtraccion == null) return true;

    final seleccionados =
        _productosSeleccionados.entries
            .where((e) => e.value['seleccionado'] == true)
            .map((e) => e.key)
            .toSet();

    final enExtraccion = _idExtraccionProducto.keys.toSet();

    if (seleccionados.length != enExtraccion.length ||
        !seleccionados.containsAll(enExtraccion)) {
      debugPrint(
        '⚠️ Reconciliación: seleccionados=$seleccionados, en extracción=$enExtraccion',
      );

      // Agregar los que faltan en extracción
      for (final idInv in seleccionados.difference(enExtraccion)) {
        // Buscar datos del producto en las zonas cargadas
        Map<String, dynamic>? prodData;
        for (final prods in _zonasInventario.values) {
          for (final p in prods) {
            if (p['id'] == idInv) {
              prodData = p;
              break;
            }
          }
          if (prodData != null) break;
        }
        if (prodData != null) {
          await _confirmarCantidadProducto(idInv, prodData);
        }
      }

      // Quitar los que sobran en extracción
      for (final idInv in enExtraccion.difference(seleccionados)) {
        await _quitarProductoDeExtraccion(idInv);
      }
    }

    // Verificar cantidades
    bool todasCoinciden = true;
    for (final idInv in seleccionados) {
      final cantSel =
          _productosSeleccionados[idInv]?['cantidad'] as double? ?? 0.0;
      final idEP = _idExtraccionProducto[idInv];
      if (idEP == null) {
        todasCoinciden = false;
        break;
      }
      final epRow = await _supabase
          .from('app_dat_extraccion_productos')
          .select('cantidad')
          .eq('id', idEP)
          .maybeSingle();
      if (epRow == null) {
        todasCoinciden = false;
        break;
      }
      final cantEP = (epRow['cantidad'] as num?)?.toDouble() ?? 0.0;
      if ((cantSel - cantEP).abs() > 0.001) {
        todasCoinciden = false;
        debugPrint(
          '⚠️ Cantidad discrepante para inventario #$idInv: sel=$cantSel, extracción=$cantEP',
        );
        break;
      }
    }

    return todasCoinciden;
  }

  // ────────────────────────────────────────────────────────────────────────

  Future<void> _procederConConfiguracion() async {
    final productosIds =
        _productosSeleccionados.entries
            .where((e) => e.value['seleccionado'] == true)
            .map((e) => e.key)
            .toList();

    if (productosIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validar cantidades
    for (final id in productosIds) {
      if ((_productosSeleccionados[id]?['cantidad'] ?? 0) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Todos los productos seleccionados deben tener cantidad > 0',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _procediendo = true);

    try {
      // Verificar que la extracción esté sincronizada con los productos seleccionados
      final reconciliado = await _reconciliarExtraccion();
      if (!reconciliado) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Hay discrepancias entre los productos seleccionados y la extracción. Revise las cantidades.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        setState(() => _procediendo = false);
        return;
      }

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
        final cantSel =
            _productosSeleccionados[idInv]?['cantidad'] as double? ?? 0.0;
        p['cantidad_seleccionada'] = cantSel;
        p['tasa_cambio'] = tasaCambio;

        // Precios: El consignador configura el precio_costo_usd que quiere cobrar
        // Este precio es independiente de los precios en la tienda consignadora
        final idProducto = p['id_producto'];

        // ⚠️ NO obtener precio_venta del producto original - No se debe tocar
        // El precio_venta de la tienda consignadora debe permanecer intacto
        p['precio_venta'] =
            0.0; // Inicializar en 0, el consignador lo configurará

        // Obtener precio_promedio de la presentación para usar como precio_costo_usd
        double costUSD = 0.0;
        final idPresentacion = p['id_presentacion'];
        if (idPresentacion != null) {
          final presResp = await _supabase
              .from('app_dat_producto_presentacion')
              .select('precio_promedio')
              .eq('id_producto', idProducto)
              .eq('id_presentacion', idPresentacion)
              .limit(1);

          if ((presResp as List).isNotEmpty) {
            costUSD = (presResp[0]['precio_promedio'] ?? 0).toDouble();
          }
        }

        // Si no hay precio_promedio en la presentación, intentar obtener del producto base
        if (costUSD == 0.0) {
          final presBaseResp = await _supabase
              .from('app_dat_producto_presentacion')
              .select('precio_promedio')
              .eq('id_producto', idProducto)
              .eq('es_base', true)
              .limit(1);

          if ((presBaseResp as List).isNotEmpty) {
            costUSD = (presBaseResp[0]['precio_promedio'] ?? 0).toDouble();
          }
        }

        p['precio_costo_usd'] = costUSD;
        p['precio_costo_cup'] = costUSD * tasaCambio;
      }

      if (widget.isDevolucion) {
        await _procederConCreacionDevolucion(productosData);
        return;
      }

      // Proceso normal de envío (congelar stock y configurar precios)
      final idTiendaConsignadora =
          widget.contrato['id_tienda_consignadora'] as int;
      // Usar la extracción creada en tiempo real, o crearla si no existe aún
      int? idOperacionReserva;
      if (_idExtraccion != null) {
        idOperacionReserva = _idExtraccion;
        debugPrint('✅ Usando extracción existente #$idOperacionReserva');
      } else {
        idOperacionReserva = await ConsignacionService.crearReservaStock(
          idContrato: widget.idContrato,
          productos:
              productosData
                  .map(
                    (p) => {
                      'id_producto': p['id_producto'],
                      'cantidad': p['cantidad_seleccionada'],
                      'id_presentacion': p['id_presentacion'],
                      'id_ubicacion': p['id_ubicacion'],
                      'id_variante': p['id_variante'],
                      'id_opcion_variante': p['id_opcion_variante'],
                      'precio_costo_unitario': p['precio_costo_usd'],
                    },
                  )
                  .toList(),
          idTiendaOrigen: idTiendaConsignadora,
        );
      }

      setState(() => _procediendo = false);
      if (!mounted) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) => ConsignacionProductosConfigScreen(
                productos: productosData,
                contrato: widget.contrato,
                idOperacionExtraccion: idOperacionReserva,
                onConfirm: (finalProductos, opId) async {
                  final user = _supabase.auth.currentUser;
                  if (user == null) return;

                  final idAlmacenDestino =
                      widget.contrato['id_almacen_destino'] as int?;
                  if (idAlmacenDestino == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Error: El contrato no tiene un almacén destino configurado',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _procederConCreacionDevolucion(
    List<Map<String, dynamic>> productos,
  ) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final idTiendaConsignataria =
          widget.contrato['id_tienda_consignataria'] as int;
      final almacenes = await _supabase
          .from('app_dat_almacen')
          .select('id')
          .eq('id_tienda', idTiendaConsignataria)
          .limit(1);
      final idAlmacenOrigen =
          (almacenes as List).isNotEmpty ? almacenes[0]['id'] as int : 0;

      final productosParaDevolucion =
          productos
              .map(
                (p) => {
                  'id_inventario': p['id'] as int,
                  'id_producto': p['id_producto'],
                  'cantidad': p['cantidad_seleccionada'],
                  'precio_costo_usd': p['precio_costo_usd'],
                  'precio_costo_cup': p['precio_costo_cup'],
                  'tasa_cambio': p['tasa_cambio'],
                },
              )
              .toList();

      final result = await ConsignacionEnvioService.crearDevolucion(
        idContrato: widget.idContrato,
        idAlmacenOrigen: idAlmacenOrigen,
        idUsuario: user.id,
        productos: productosParaDevolucion,
        descripcion:
            'Devolución de productos - ${widget.contrato['tienda_consignataria']['denominacion']}',
      );

      setState(() => _procediendo = false);
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Devolución solicitada: ${result['numero_envio']}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error creando devolución: $e');
      setState(() => _procediendo = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool haySeleccion = _productosSeleccionados.values.any(
      (v) => v['seleccionado'] == true,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onBackPressed();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isDevolucion
              ? 'Crear Devolución'
              : 'Asignar Productos en Consignación',
        ),
        backgroundColor:
            widget.isDevolucion ? Colors.deepOrange : AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBackPressed,
        ),
      ),
      body:
          _isLoading
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
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child:
                        _almacenes.isEmpty
                            ? const Center(
                              child: Text('No hay almacenes disponibles'),
                            )
                            : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _almacenes.length,
                              itemBuilder:
                                  (context, index) =>
                                      _buildAlmacenCard(_almacenes[index]),
                            ),
                  ),
                  if (haySeleccion)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 4),
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed:
                              _procediendo ? null : _procederConConfiguracion,
                          icon:
                              _procediendo
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : Icon(
                                    widget.isDevolucion
                                        ? Icons.replay
                                        : Icons.arrow_forward,
                                  ),
                          label: Text(
                            _procediendo
                                ? 'Procesando...'
                                : (widget.isDevolucion
                                    ? 'Solicitar Devolución'
                                    : 'Configurar Productos'),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                widget.isDevolucion
                                    ? Colors.deepOrange
                                    : AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
            onTap:
                () => setState(() => _expandedAlmacenes[idStr] = !isExpanded),
          ),
          if (isExpanded)
            ...zonas.map((z) => _buildZonaCard(idStr, z)).toList(),
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
              if (!isExp && _zonasInventario[key] == null)
                await _loadZonaProductos(key, zonaId);
              setState(() => _expandedZonas[key] = !isExp);
            },
            child: Row(
              children: [
                Icon(
                  isExp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    zona['denominacion'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          if (isExp) ...[
            const SizedBox(height: 8),
            if (prods.isNotEmpty) ...[
              TextField(
                controller: _zonaSearchControllers.putIfAbsent(
                  key,
                  () => TextEditingController(),
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar producto...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: (_zonaSearchControllers[key]?.text.isNotEmpty ?? false)
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _zonaSearchControllers[key]!.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Builder(
              builder: (context) {
                final query = (_zonaSearchControllers[key]?.text ?? '').toLowerCase().trim();
                final filtered = query.isEmpty
                    ? prods
                    : prods.where((p) {
                        final nombre = (p['denominacion_producto'] as String? ?? '').toLowerCase();
                        final sku = (p['sku_producto'] as String? ?? '').toLowerCase();
                        return nombre.contains(query) || sku.contains(query);
                      }).toList();
                if (prods.isEmpty && !loading) {
                  return const Text(
                    'Sin productos en esta zona',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  );
                }
                if (filtered.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No se encontraron productos con ese nombre',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  );
                }
                return Column(
                  children: filtered.map((p) => _buildProductoTile(p)).toList(),
                );
              },
            ),
          ],
          const Divider(),
        ],
      ),
    );
  }

  Widget _buildProductoTile(Map<String, dynamic> producto) {
    final idInv = producto['id'] as int;
    final isSelected = _productosSeleccionados[idInv]?['seleccionado'] == true;
    final cantidadDisponible =
        (producto['cantidad_final'] as num?)?.toDouble() ?? 0.0;
    final tieneMovimiento = _idExtraccionProducto.containsKey(idInv);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:
            isSelected ? AppColors.primary.withOpacity(0.05) : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? AppColors.primary : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (_) => _toggleProductoSeleccion(idInv),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  producto['denominacion_producto'] ?? 'Producto',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'SKU: ${producto['sku_producto'] ?? 'N/A'}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                if (isSelected && tieneMovimiento)
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 12,
                        color: Colors.green[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Reservado',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (isSelected)
            SizedBox(
              width: 110,
              child: TextField(
                controller: _controllerFor(idInv),
                focusNode: _focusNodeFor(idInv, producto),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Cantidad',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  border: const OutlineInputBorder(),
                  suffixIcon:
                      tieneMovimiento
                          ? Icon(
                            Icons.lock_outline,
                            size: 14,
                            color: Colors.green[600],
                          )
                          : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (val) {
                  _actualizarCantidad(
                    idInv,
                    double.tryParse(val) ?? 0.0,
                    cantidadDisponible,
                  );
                  _scheduleConfirmar(idInv, producto);
                },
                onSubmitted: (_) {
                  _cantTimers[idInv]?.cancel();
                  _confirmarCantidadProducto(idInv, producto);
                },
              ),
            ),
          const SizedBox(width: 8),
          Text(
            '${cantidadDisponible.toInt()}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _loadZonaProductos(String key, String zonaId) async {
    setState(() => _loadingZonas[key] = true);
    try {
      List<dynamic> response;

      if (widget.isDevolucion) {
        // Para devoluciones: solo productos que están en la zona del contrato de consignación
        // Verificar primero si esta zona pertenece al contrato
        final zonaContratoCheck = await _supabase
            .from('app_dat_consignacion_zona')
            .select('id')
            .eq('id_contrato', widget.idContrato)
            .eq('id_zona', int.parse(zonaId))
            .limit(1);

        if ((zonaContratoCheck as List).isEmpty) {
          // Esta zona NO pertenece al contrato, no mostrar productos
          setState(() {
            _zonasInventario[key] = [];
            _loadingZonas[key] = false;
          });
          return;
        }

        // Obtener productos del inventario en esta zona específica del contrato
        // Como app_dat_inventario_productos es una tabla de movimientos,
        // necesitamos obtener solo el último registro (más reciente) por cada combinación única
        final inventarioResponse = await _supabase
            .from('app_dat_inventario_productos')
            .select('''
              id,
              cantidad_final,
              id_producto,
              id_ubicacion,
              id_presentacion,
              id_variante,
              id_opcion_variante,
              created_at,
              app_dat_producto!inner(
                id,
                denominacion,
                sku
              ),
              app_dat_producto_presentacion(
                app_nom_presentacion(
                  denominacion
                )
              ),
              app_dat_variantes(
                app_dat_atributos(
                  denominacion
                )
              ),
              app_dat_atributo_opcion(
                valor
              )
            ''')
            .eq('id_ubicacion', int.parse(zonaId))
            .order('created_at', ascending: false);

        // 1. Agrupar por combinación única → último registro por combinación
        final Map<String, dynamic> productosUnicos = {};
        for (final item in inventarioResponse) {
          final key =
              '${item['id_producto']}_${item['id_variante'] ?? 'null'}_${item['id_presentacion'] ?? 'null'}_${item['id_opcion_variante'] ?? 'null'}';
          if (!productosUnicos.containsKey(key)) {
            productosUnicos[key] = item;
          }
        }

        // 2. Solo los que realmente tienen disponibilidad (cantidad_final > 0 en el último registro)
        response = productosUnicos.values
            .where((item) => ((item['cantidad_final'] as num?) ?? 0) > 0)
            .toList();

        // Mapear la respuesta para tener la estructura esperada con información de variante/presentación
        response =
            response.map((item) {
              final producto = item['app_dat_producto'] as Map<String, dynamic>;
              final presentacionData =
                  item['app_dat_producto_presentacion']
                      as Map<String, dynamic>?;
              final varianteData =
                  item['app_dat_variantes'] as Map<String, dynamic>?;
              final atributoOpcion =
                  item['app_dat_atributo_opcion'] as Map<String, dynamic>?;

              // Extraer denominación de presentación
              String? presentacionNombre;
              if (presentacionData != null) {
                final nomPresentacion =
                    presentacionData['app_nom_presentacion']
                        as Map<String, dynamic>?;
                presentacionNombre =
                    nomPresentacion?['denominacion'] as String?;
              }

              // Extraer denominación de atributo (variante)
              String? atributoNombre;
              if (varianteData != null) {
                final atributos =
                    varianteData['app_dat_atributos'] as Map<String, dynamic>?;
                atributoNombre = atributos?['denominacion'] as String?;
              }

              // Extraer valor de opción de variante
              String? opcionValor = atributoOpcion?['valor'] as String?;

              // Construir denominación completa con variante/presentación
              String denominacionCompleta =
                  producto['denominacion'] ?? 'Producto';
              if (presentacionNombre != null && presentacionNombre.isNotEmpty) {
                denominacionCompleta += ' - $presentacionNombre';
              }
              if (atributoNombre != null && atributoNombre.isNotEmpty) {
                denominacionCompleta += ' ($atributoNombre';
                if (opcionValor != null && opcionValor.isNotEmpty) {
                  denominacionCompleta += ': $opcionValor';
                }
                denominacionCompleta += ')';
              }

              return {
                'id': item['id'],
                'cantidad_final': item['cantidad_final'],
                'id_producto': item['id_producto'],
                'id_ubicacion': item['id_ubicacion'],
                'id_presentacion': item['id_presentacion'],
                'id_variante': item['id_variante'],
                'id_opcion_variante': item['id_opcion_variante'],
                'denominacion_producto': denominacionCompleta,
                'sku_producto': producto['sku'],
              };
            }).toList();
      } else {
        // Para envíos normales: obtener todos los registros de la zona, sin filtro previo
        final inventarioResponse = await _supabase
            .from('app_dat_inventario_productos')
            .select('''
              id,
              cantidad_final,
              id_producto,
              id_ubicacion,
              id_presentacion,
              id_variante,
              id_opcion_variante,
              created_at,
              app_dat_producto!inner(
                id,
                denominacion,
                sku
              ),
              app_dat_producto_presentacion(
                app_nom_presentacion(
                  denominacion
                )
              ),
              app_dat_variantes(
                app_dat_atributos(
                  denominacion
                )
              ),
              app_dat_atributo_opcion(
                valor
              )
            ''')
            .eq('id_ubicacion', int.parse(zonaId))
            .order('created_at', ascending: false);

        // 1. Agrupar por combinación única → último registro por combinación
        final Map<String, dynamic> productosUnicos = {};
        for (final item in inventarioResponse) {
          final key =
              '${item['id_producto']}_${item['id_variante'] ?? 'null'}_${item['id_presentacion'] ?? 'null'}_${item['id_opcion_variante'] ?? 'null'}';
          if (!productosUnicos.containsKey(key)) {
            productosUnicos[key] = item;
          }
        }

        // 2. Solo los que realmente tienen disponibilidad (cantidad_final > 0 en el último registro)
        response =
            productosUnicos.values
                .where((item) => ((item['cantidad_final'] as num?) ?? 0) > 0)
                .map((item) {
              final producto = item['app_dat_producto'] as Map<String, dynamic>;
              final presentacionData =
                  item['app_dat_producto_presentacion']
                      as Map<String, dynamic>?;
              final varianteData =
                  item['app_dat_variantes'] as Map<String, dynamic>?;
              final atributoOpcion =
                  item['app_dat_atributo_opcion'] as Map<String, dynamic>?;

              // Extraer denominación de presentación
              String? presentacionNombre;
              if (presentacionData != null) {
                final nomPresentacion =
                    presentacionData['app_nom_presentacion']
                        as Map<String, dynamic>?;
                presentacionNombre =
                    nomPresentacion?['denominacion'] as String?;
              }

              // Extraer denominación de atributo (variante)
              String? atributoNombre;
              if (varianteData != null) {
                final atributos =
                    varianteData['app_dat_atributos'] as Map<String, dynamic>?;
                atributoNombre = atributos?['denominacion'] as String?;
              }

              // Extraer valor de opción de variante
              String? opcionValor = atributoOpcion?['valor'] as String?;

              // Construir denominación completa con variante/presentación
              String denominacionCompleta =
                  producto['denominacion'] ?? 'Producto';
              if (presentacionNombre != null && presentacionNombre.isNotEmpty) {
                denominacionCompleta += ' - $presentacionNombre';
              }
              if (atributoNombre != null && atributoNombre.isNotEmpty) {
                denominacionCompleta += ' ($atributoNombre';
                if (opcionValor != null && opcionValor.isNotEmpty) {
                  denominacionCompleta += ': $opcionValor';
                }
                denominacionCompleta += ')';
              }

              return {
                'id': item['id'],
                'cantidad_final': item['cantidad_final'],
                'id_producto': item['id_producto'],
                'id_ubicacion': item['id_ubicacion'],
                'id_presentacion': item['id_presentacion'],
                'id_variante': item['id_variante'],
                'id_opcion_variante': item['id_opcion_variante'],
                'denominacion_producto': denominacionCompleta,
                'sku_producto': producto['sku'],
              };
            }).toList();
      }

      // Ordenar productos alfabéticamente por nombre
      final productosOrdenados = List<Map<String, dynamic>>.from(response);
      productosOrdenados.sort((a, b) {
        final nombreA =
            (a['denominacion_producto'] as String? ?? '').toLowerCase();
        final nombreB =
            (b['denominacion_producto'] as String? ?? '').toLowerCase();
        return nombreA.compareTo(nombreB);
      });

      setState(() {
        _zonasInventario[key] = productosOrdenados;
        _loadingZonas[key] = false;
      });
    } catch (e) {
      debugPrint('Error cargando productos de zona: $e');
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
  State<ConsignacionProductosConfigScreen> createState() =>
      _ConsignacionProductosConfigScreenState();
}

class _ConsignacionProductosConfigScreenState
    extends State<ConsignacionProductosConfigScreen> {
  late Map<int, Map<String, dynamic>> _productosConfig;
  late Map<int, TextEditingController> _precioVentaControllers;
  bool _guardando = false;
  double _tasaCambio = 440.0;

  @override
  void initState() {
    super.initState();
    _productosConfig = {};
    _precioVentaControllers = {};
    for (var p in widget.productos) {
      _productosConfig[p['id']] = {
        'cantidad': p['cantidad_seleccionada'],
        'precio_venta': p['precio_venta'] > 0 ? p['precio_venta'] : null,
        'margen_porcentaje': 1.0,
      };
      // Crear controller para cada producto
      final precioInicial =
          (p['precio_venta'] > 0 ? p['precio_venta'] : '').toString();
      _precioVentaControllers[p['id']] = TextEditingController(
        text: precioInicial,
      );
    }
    // Cargar tasa de cambio desde la base de datos
    _cargarTasaCambio();
  }

  Future<void> _cargarTasaCambio() async {
    try {
      debugPrint('Iniciando carga de tasa de cambio (efectiva USD→CUP)...');

      final tasaCargada = await CurrencyService.getEffectiveUsdToCupRate();
      debugPrint('Tasa cargada (efectiva): $tasaCargada');

      if (mounted) {
        setState(() {
          _tasaCambio = tasaCargada;
          debugPrint('Tasa actualizada en estado: $_tasaCambio');
        });
      }
    } catch (e) {
      debugPrint('Error cargando tasa de cambio: $e');
      // Mantener valor por defecto si hay error
    }
  }

  @override
  void dispose() {
    for (var controller in _precioVentaControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _confirmar() {
    for (var config in _productosConfig.values) {
      if ((config['precio_venta'] ?? 0) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todos los productos deben tener un precio de venta'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // Construir productos en el formato que espera ConsignacionEnvioService.crearEnvio()
    final finalProds =
        widget.productos.map((p) {
          final config = _productosConfig[p['id']]!;
          return {
            'id_inventario': p['id'],
            'id_producto': p['id_producto'],
            'id_variante': p['id_variante'],
            'id_presentacion': p['id_presentacion'],
            'id_ubicacion': p['id_ubicacion'],
            'cantidad': config['cantidad'],
            'precio_costo_usd': p['precio_costo_usd'] ?? 0.0,
            'precio_costo_cup': p['precio_costo_cup'] ?? 0.0,
            'tasa_cambio': p['tasa_cambio'] ?? 440.0,
            'precio_venta': config['precio_venta'],
          };
        }).toList();

    widget.onConfirm(finalProds, widget.idOperacionExtraccion);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Precios de Venta'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.productos.length,
              itemBuilder: (context, index) {
                final p = widget.productos[index];
                final config = _productosConfig[p['id']]!;
                final precioCostoUSD = (p['precio_costo_usd'] ?? 0).toDouble();
                final precioCostoCUP =
                    precioCostoUSD *
                    _tasaCambio; // Convertir USD a CUP usando tasa de cambio
                final precioVentaCUP = (config['precio_venta'] ?? 0).toDouble();
                final precioVentaUSD =
                    precioVentaCUP > 0 ? precioVentaCUP / _tasaCambio : 0.0;
                final gananciaUSD = precioVentaUSD - precioCostoUSD;
                final margenPorcentaje = config['margen_porcentaje'] ?? 0.0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['app_dat_producto']?['denominacion'] ?? 'Producto',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Sección de Precio Costo
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Precio Costo Original (USD)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blue[700],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '\$${precioCostoUSD.toStringAsFixed(2)} USD',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Precio Costo en CUP',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                  Text(
                                    '% Diferencia',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '\$${precioCostoCUP.toStringAsFixed(2)} CUP',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                          ),
                                        ),
                                        /* Text(
                                          '(\$${precioCostoUSD.toStringAsFixed(2)} USD)',
                                          style: TextStyle(fontSize: 11, color: Colors.blue[600]),
                                        ), */
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: DropdownButton<double>(
                                      isExpanded: true,
                                      value: margenPorcentaje,
                                      items:
                                          [
                                                1,
                                                2,
                                                3,
                                                4,
                                                5,
                                                6,
                                                7,
                                                8,
                                                9,
                                                10,
                                                11,
                                                12,
                                                13,
                                                14,
                                                15,
                                              ]
                                              .map(
                                                (val) =>
                                                    DropdownMenuItem<double>(
                                                      value: val.toDouble(),
                                                      child: Text(
                                                        '${val}%',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                              )
                                              .toList(),
                                      onChanged: (newVal) {
                                        if (newVal != null) {
                                          setState(() {
                                            config['margen_porcentaje'] =
                                                newVal;
                                            // Calcular precio de venta: precio_costo_cup * (1 + porcentaje/100)
                                            final precioVentaCalculado =
                                                precioCostoCUP *
                                                (1 + (newVal / 100));
                                            config['precio_venta'] =
                                                precioVentaCalculado;
                                            // Actualizar el controller del TextField
                                            _precioVentaControllers[p['id']]
                                                ?.text = precioVentaCalculado
                                                .toStringAsFixed(2);
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Campo de Precio de Venta
                        TextField(
                          controller: _precioVentaControllers[p['id']],
                          decoration: const InputDecoration(
                            labelText: 'Precio de Venta Final (CUP)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.attach_money),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged:
                              (val) => setState(
                                () =>
                                    config['precio_venta'] = double.tryParse(
                                      val,
                                    ),
                              ),
                        ),
                        const SizedBox(height: 8),
                        // Información de Precio de Venta en USD y Ganancia
                        if (precioVentaCUP > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'En USD: \$${precioVentaUSD.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        gananciaUSD >= 0
                                            ? Colors.green[100]
                                            : Colors.red[100],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Ganancia: \$${gananciaUSD.toStringAsFixed(2)} USD',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color:
                                          gananciaUSD >= 0
                                              ? Colors.green[700]
                                              : Colors.red[700],
                                    ),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _confirmar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('CONFIRMAR ENVÍO'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
