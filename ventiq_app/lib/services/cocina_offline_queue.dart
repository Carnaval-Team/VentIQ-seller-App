import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pedido_resultado.dart';
import '../utils/uuid_generator.dart';

/// Cola PERSISTENTE de operaciones de cocina hechas sin red.
///
/// POR QUE NO SE USA NetworkRequestQueue
/// -------------------------------------
/// `NetworkRequestQueue` guarda closures en memoria: si la app se cierra (y la
/// tablet de un restaurante se cierra sola todo el tiempo) la cola se pierde y
/// el pedido nunca llega a cocina. Aqui se persiste el JSON de la operacion en
/// SharedPreferences, asi sobrevive a reinicios.
///
/// IDEMPOTENCIA
/// ------------
/// Cada operacion lleva un `client_uuid` generado en el DISPOSITIVO al crearla,
/// no al enviarla. Es lo unico que sobrevive a un reintento: el backend
/// (`fn_pedir_item_cuenta_offline`) lo usa para no duplicar el pedido. Reenviar
/// diez veces la misma operacion mueve inventario UNA vez.
///
/// El uuid NO se regenera nunca al reintentar. Si se regenerara, cada reintento
/// seria un pedido nuevo: doble descuento de materia prima y comandas de mas.
class CocinaOfflineQueue {
  static final CocinaOfflineQueue _instance = CocinaOfflineQueue._internal();
  factory CocinaOfflineQueue() => _instance;
  CocinaOfflineQueue._internal();

  static const String _key = 'cocina_offline_queue_v1';

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Evita que dos disparos concurrentes (reconexion + timer) procesen la misma
  /// operacion a la vez.
  bool _sincronizando = false;

  // ── Persistencia ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _leer() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final lista = json.decode(raw);
      if (lista is! List) return [];
      return lista
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      // JSON corrupto: mejor empezar limpio que fallar en cada arranque.
      return [];
    }
  }

  Future<void> _guardar(List<Map<String, dynamic>> ops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(ops));
  }

  /// Operaciones esperando envio.
  Future<int> pendientes() async => (await _leer()).length;

  /// Detalle de lo pendiente, para mostrarlo al usuario.
  Future<List<Map<String, dynamic>>> listarPendientes() async => _leer();

  Future<void> limpiar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // ── Encolar ────────────────────────────────────────────────────────────

  /// Encola un pedido de item. Devuelve el `client_uuid` asignado.
  ///
  /// Se llama cuando `fn_pedir_item_cuenta` falla por red. El pedido queda
  /// guardado con su uuid y se reenvia al recuperar conexion.
  Future<String> encolarPedido({
    required int idCuenta,
    required int idProducto,
    required double cantidad,
    required double precioUnitario,
    int? idVariante,
    int? idOpcionVariante,
    int? idPresentacion,
    int? idUbicacion,
    double? precioBase,
    int? idMetodoPago,
    Map<String, dynamic>? promotionData,
    Map<String, dynamic>? inventoryData,
    String? notas,
    String? skuProducto,
    String? skuUbicacion,
    String? uuidVendedor,
    String? descripcion,
  }) async {
    final clientUuid = UuidGenerator.v4();
    final ops = await _leer();

    ops.add({
      'tipo': 'pedir_item',
      'client_uuid': clientUuid,
      'creado_en': DateTime.now().toIso8601String(),
      'intentos': 0,
      'descripcion': descripcion ?? 'Pedido de producto $idProducto',
      'params': {
        'p_client_uuid': clientUuid,
        'p_id_cuenta': idCuenta,
        'p_id_producto': idProducto,
        'p_cantidad': cantidad,
        'p_precio_unitario': precioUnitario,
        'p_id_variante': idVariante,
        'p_id_opcion_variante': idOpcionVariante,
        'p_id_presentacion': idPresentacion,
        'p_id_ubicacion': idUbicacion,
        'p_precio_base': precioBase,
        'p_id_metodo_pago': idMetodoPago,
        'p_promotion_data': promotionData,
        'p_inventory_data': inventoryData,
        'p_notas': notas,
        'p_sku_producto': skuProducto,
        'p_sku_ubicacion': skuUbicacion,
        'p_uuid_vendedor': uuidVendedor,
        'p_forzar_sin_stock': false,
      },
    });

    await _guardar(ops);
    return clientUuid;
  }

  /// Encola un cambio de estado del KDS (la tablet de cocina tambien pierde red).
  Future<String> encolarCambioEstado({
    required int idComandaItem,
    required int nuevoEstado,
    String? descripcion,
  }) async {
    final clientUuid = UuidGenerator.v4();
    final ops = await _leer();

    ops.add({
      'tipo': 'estado_comanda_item',
      'client_uuid': clientUuid,
      'creado_en': DateTime.now().toIso8601String(),
      'intentos': 0,
      'descripcion': descripcion ?? 'Cambio de estado a $nuevoEstado',
      'params': {
        'p_client_uuid': clientUuid,
        'p_id_item': idComandaItem,
        'p_nuevo_estado': nuevoEstado,
      },
    });

    await _guardar(ops);
    return clientUuid;
  }

  // ── Sincronizar ────────────────────────────────────────────────────────

  /// Reenvia todo lo pendiente. Devuelve un resumen para avisar al usuario.
  ///
  /// Las operaciones se procesan EN ORDEN: pedir el segundo plato antes que el
  /// primero cambiaria el orden de las comandas en cocina.
  ///
  /// Una operacion rechazada por el servidor (no por red) se descarta: si el
  /// stock no alcanzaba, reintentarla mil veces no va a cambiar nada, y dejarla
  /// en la cola bloquearia las demas para siempre.
  Future<ResultadoSync> sincronizar() async {
    if (_sincronizando) {
      return const ResultadoSync(enviadas: 0, duplicadas: 0, fallidas: 0, pendientes: -1);
    }
    _sincronizando = true;

    try {
      final ops = await _leer();
      if (ops.isEmpty) {
        return const ResultadoSync(enviadas: 0, duplicadas: 0, fallidas: 0, pendientes: 0);
      }

      final quedan = <Map<String, dynamic>>[];
      final rechazadas = <String>[];
      int enviadas = 0;
      int duplicadas = 0;

      // Indice explicito, NO for-in con indexOf: dos operaciones del mismo
      // producto pueden ser mapas iguales e indexOf devolveria el primero,
      // reencolando las operaciones equivocadas.
      for (var i = 0; i < ops.length; i++) {
        final op = ops[i];
        final tipo = op['tipo'] as String?;
        final params = op['params'];
        if (tipo == null || params is! Map) continue;

        final rpc = switch (tipo) {
          'pedir_item' => 'fn_pedir_item_cuenta_offline',
          'estado_comanda_item' => 'fn_cambiar_estado_comanda_item_offline',
          _ => null,
        };
        if (rpc == null) continue;

        try {
          final res = await _supabase.rpc(
            rpc,
            params: Map<String, dynamic>.from(params),
          );

          final mapa = res is Map
              ? Map<String, dynamic>.from(res)
              : (res is List && res.isNotEmpty && res.first is Map
                  ? Map<String, dynamic>.from(res.first as Map)
                  : null);

          if (mapa == null || mapa['status'] != 'success') {
            // El servidor la rechazo por negocio (sin stock, cocina no ligada).
            // Reintentar no va a cambiar el resultado: se descarta y se reporta.
            rechazadas.add(
              '${op['descripcion']}: ${mapa?['message'] ?? 'rechazada'}',
            );
            continue;
          }

          // idempotent: true significa que ya se habia aplicado. No es un
          // error: es exactamente lo que debe pasar al reintentar.
          if (mapa['idempotent'] == true) {
            duplicadas++;
          } else {
            enviadas++;
          }
        } catch (e) {
          if (_esErrorDeRed(e)) {
            // Sigue sin red: se conserva con el MISMO client_uuid.
            op['intentos'] = ((op['intentos'] as num?)?.toInt() ?? 0) + 1;
            // Si esta no salio por falta de red, las siguientes tampoco: se
            // conservan todas desde aqui para no romper el orden en que la
            // cocina recibe las comandas.
            quedan.addAll(ops.sublist(i));
            break;
          }
          rechazadas.add('${op['descripcion']}: $e');
        }
      }

      await _guardar(quedan);

      return ResultadoSync(
        enviadas: enviadas,
        duplicadas: duplicadas,
        fallidas: rechazadas.length,
        pendientes: quedan.length,
        rechazos: rechazadas,
      );
    } finally {
      _sincronizando = false;
    }
  }

  /// Envia una operacion de pedido directamente por la RPC offline, con
  /// client_uuid, sin pasar por la cola. Para el camino online normal: si el
  /// envio falla por red, la app puede encolar sabiendo que el uuid es el mismo.
  Future<PedidoResultado> pedirConIdempotencia({
    required String clientUuid,
    required int idCuenta,
    required int idProducto,
    required double cantidad,
    required double precioUnitario,
    int? idVariante,
    int? idOpcionVariante,
    int? idPresentacion,
    int? idUbicacion,
    double? precioBase,
    int? idMetodoPago,
    Map<String, dynamic>? promotionData,
    Map<String, dynamic>? inventoryData,
    String? notas,
    String? skuProducto,
    String? skuUbicacion,
    String? uuidVendedor,
    bool forzarSinStock = false,
  }) async {
    final res = await _supabase.rpc(
      'fn_pedir_item_cuenta_offline',
      params: {
        'p_client_uuid': clientUuid,
        'p_id_cuenta': idCuenta,
        'p_id_producto': idProducto,
        'p_cantidad': cantidad,
        'p_precio_unitario': precioUnitario,
        'p_id_variante': idVariante,
        'p_id_opcion_variante': idOpcionVariante,
        'p_id_presentacion': idPresentacion,
        'p_id_ubicacion': idUbicacion,
        'p_precio_base': precioBase,
        'p_id_metodo_pago': idMetodoPago,
        'p_promotion_data': promotionData,
        'p_inventory_data': inventoryData,
        'p_notas': notas,
        'p_sku_producto': skuProducto,
        'p_sku_ubicacion': skuUbicacion,
        'p_uuid_vendedor': uuidVendedor,
        'p_forzar_sin_stock': forzarSinStock,
      },
    );

    final mapa = res is Map
        ? Map<String, dynamic>.from(res)
        : (res is List && res.isNotEmpty && res.first is Map
            ? Map<String, dynamic>.from(res.first as Map)
            : null);

    if (mapa == null) {
      throw Exception('fn_pedir_item_cuenta_offline devolvio formato inesperado');
    }
    if (mapa['status'] != 'success') {
      throw PedidoException.fromJson(mapa);
    }
    return PedidoResultado.fromJson(mapa);
  }

  static bool _esErrorDeRed(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('timeout') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection') ||
        msg.contains('network') ||
        msg.contains('unreachable');
  }
}

/// Resumen de una pasada de sincronizacion.
class ResultadoSync {
  /// Operaciones aplicadas ahora.
  final int enviadas;

  /// Operaciones que el servidor ya tenia (idempotencia funcionando).
  final int duplicadas;

  /// Rechazadas por el servidor y descartadas.
  final int fallidas;

  /// Lo que sigue en la cola. -1 = habia otra sincronizacion en curso.
  final int pendientes;

  final List<String> rechazos;

  const ResultadoSync({
    required this.enviadas,
    required this.duplicadas,
    required this.fallidas,
    required this.pendientes,
    this.rechazos = const [],
  });

  bool get huboAlgo => enviadas > 0 || duplicadas > 0 || fallidas > 0;
  bool get todoBien => fallidas == 0 && pendientes <= 0;

  /// Mensaje para el usuario. `null` si no hay nada que decir.
  String? get mensaje {
    if (!huboAlgo) return null;
    final partes = <String>[];
    if (enviadas > 0) {
      partes.add(enviadas == 1 ? '1 pedido enviado' : '$enviadas pedidos enviados');
    }
    if (duplicadas > 0) {
      partes.add('$duplicadas ya estaban registrados');
    }
    if (fallidas > 0) {
      partes.add(fallidas == 1 ? '1 rechazado' : '$fallidas rechazados');
    }
    if (pendientes > 0) {
      partes.add('$pendientes sin enviar');
    }
    return partes.join(' · ');
  }
}
