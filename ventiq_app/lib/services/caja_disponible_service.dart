import '../models/order.dart';
import '../money/caja_disponible.dart';
import '../utils/price_utils.dart';
import 'connectivity_service.dart';
import 'order_service.dart';
import 'turno_service.dart';
import 'user_preferences_service.dart';

/// Reúne lo que hay en la caja del turno abierto: efectivo inicial, cobros de
/// las órdenes del turno (servidor, caché y pendientes de subir) y egresos
/// (servidor y pendientes de subir). Las mismas fuentes que usa el cierre.
class CajaDisponibleService {
  static final UserPreferencesService _prefs = UserPreferencesService();

  static Future<CajaDisponible> cargar(Map<String, dynamic> turno) async {
    final sinRed =
        await _prefs.isOfflineModeEnabled() ||
        !await ConnectivityService().performImmediateCheck();

    final inicial = await _inicial(turno, sinRed: sinRed);

    final ordenes = OrderService();
    await ordenes.loadOrdersForOpenTurnoUnified();

    final egresos = await _egresos(sinRed: sinRed);

    return CajaDisponible.desdeMapas(
      inicialPorMoneda: inicial,
      pagos: pagosDeOrdenes(ordenes.orders),
      egresos: egresos,
    );
  }

  static Future<Map<String, double>> _inicial(
    Map<String, dynamic> turno, {
    required bool sinRed,
  }) async {
    final delTurno = CajaDisponible.inicialDeMapa(turno);
    if (turno['efectivo_inicial_por_moneda'] is Map) return delTurno;

    Map<String, dynamic>? resumen;
    if (!sinRed) {
      try {
        final raw = turno['id'] ?? turno['server_id_turno'];
        final id = raw is num ? raw.toInt() : int.tryParse('$raw');
        if (id != null) resumen = await TurnoService.getResumenTurnoPorId(id);
        resumen ??= await TurnoService.getResumenTurnoKPI();
      } catch (_) {
        resumen = null;
      }
    }
    resumen ??= await _prefs.getTurnoResumenCache();
    resumen ??= await _prefs.getResumenCierreCache();

    final delResumen = CajaDisponible.inicialDeMapa(resumen);
    return delResumen.isNotEmpty ? delResumen : delTurno;
  }

  /// Egresos del turno. Los pendientes de subir siempre cuentan: el servidor
  /// aún no los conoce. Sin red, el caché ya los incluye (se añaden al crear).
  static Future<List<Map<String, dynamic>>> _egresos({
    required bool sinRed,
  }) async {
    final pendientes = await _prefs.getEgresosOffline();
    final filas = <Map<String, dynamic>>[];

    if (sinRed) {
      final cache = await _prefs.getEgresosCache();
      filas.addAll(cache);
      final enCache = {
        for (final f in cache)
          if (f['offline_id'] != null) f['offline_id'].toString(),
      };
      filas.addAll(
        pendientes.where((p) => !enCache.contains(p['offline_id']?.toString())),
      );
    } else {
      final servidor = await TurnoService.getEgresosEnriquecidos();
      filas.addAll(servidor.map((e) => e.toJson()));
      filas.addAll(pendientes);
    }
    return filas;
  }

  /// Pagos cobrados de las órdenes vendidas del turno (mismo criterio que el
  /// cierre). Una orden offline sin desglose se atribuye a la moneda base.
  static List<Map<String, dynamic>> pagosDeOrdenes(Iterable<Order> ordenes) {
    final pagos = <Map<String, dynamic>>[];
    for (final orden in ordenes) {
      final vendida =
          orden.status == OrderStatus.completada ||
          orden.status == OrderStatus.pagoConfirmado ||
          orden.status == OrderStatus.pendienteDeSincronizacion ||
          orden.status == OrderStatus.enviada;
      if (!vendida) continue;

      var conDesglose = false;
      for (final raw in orden.pagos ?? const []) {
        final pago = PriceUtils.asPaymentMap(raw);
        if (pago == null) continue;
        pagos.add(pago);
        if (!PriceUtils.paymentIsPending(pago)) conDesglose = true;
      }

      if (!conDesglose && orden.isOfflineOrder && orden.total > 0) {
        final medio = (orden.paymentMethod ?? '').toLowerCase();
        final efectivo = medio.contains('efectivo') || medio.contains('cash');
        pagos.add({
          'moneda': PriceUtils.baseCurrency,
          'monto': orden.total,
          'es_efectivo': efectivo,
        });
      }
    }
    return pagos;
  }
}
