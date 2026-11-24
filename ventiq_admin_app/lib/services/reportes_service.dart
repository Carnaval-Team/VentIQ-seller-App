import 'package:supabase_flutter/supabase_flutter.dart';

/// Lecturas de la fase 8 del módulo Fondo de Inversión → Compras:
/// dinero, conciliación, aging y descuadres.
///
/// Todo es `fn_fdi_reporte_*` / `fn_fdi_conciliacion*` en modo lectura: aquí
/// no se escribe nada. El servicio devuelve el jsonb tal cual (sin modelos),
/// porque los reportes son tablas de solo lectura y cada pantalla decide qué
/// columnas pinta; `reportes_calculos.dart` normaliza las cifras.
///
/// Las RPC con ventana reciben `desde`/`hasta` opcionales. **Si son `null` no
/// se mandan**: el servidor aplica su ventana de 30 días y devuelve en el
/// payload el `desde`/`hasta` que realmente usó (la UI muestra eso, no una
/// fecha inventada en cliente).
class ReportesService {
  static final ReportesService _instance = ReportesService._internal();
  factory ReportesService() => _instance;
  ReportesService._internal();

  final _supabase = Supabase.instance.client;

  Map<String, dynamic> _asMap(dynamic resp) =>
      resp is Map ? Map<String, dynamic>.from(resp) : <String, dynamic>{};

  /// Las columnas `date` viajan como `YYYY-MM-DD`, igual que en
  /// `CompraService._fecha`.
  String? _fecha(DateTime? x) => x?.toIso8601String().split('T').first;

  /// Parámetros de una RPC con ventana: la tienda primero y las fechas solo si
  /// existen (`DEFAULT NULL` en el servidor).
  Map<String, dynamic> _paramsVentana(
    int idTienda,
    DateTime? desde,
    DateTime? hasta,
  ) {
    return {
      'p_id_tienda': idTienda,
      if (desde != null) 'p_desde': _fecha(desde),
      if (hasta != null) 'p_hasta': _fecha(hasta),
    };
  }

  /// ¿El error dice que esa firma con fechas no existe en el proyecto?
  ///
  /// `PGRST202` es «function not found in schema cache» de PostgREST y `42883`
  /// el `undefined_function` de PostgreSQL.
  bool _firmaSinFechas(PostgrestException error) =>
      error.code == 'PGRST202' || error.code == '42883';

  Future<Map<String, dynamic>> _rpcVentana(
    String funcion, {
    required int idTienda,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final params = _paramsVentana(idTienda, desde, hasta);
    return _asMap(await _supabase.rpc(funcion, params: params));
  }

  // ==========================================================================
  // R2 — Caja: saldo, reservado, disponible y ejecutado del periodo
  // ==========================================================================

  /// `{id_tienda, ventana_dias, desde, hasta, claves[], totales_por_moneda[]}`.
  ///
  /// La ventana la fija el servidor (30 días) y la devuelve en el payload: la
  /// firma desplegada es `fn_fdi_reporte_caja(bigint)`, sin fechas. El rango del
  /// filtro global no aplica a esta tarjeta; la pantalla muestra la ventana que
  /// el servidor usó.
  Future<Map<String, dynamic>> caja({required int idTienda}) async =>
      _asMap(await _supabase.rpc('fn_fdi_reporte_caja',
          params: {'p_id_tienda': idTienda}));

  // ==========================================================================
  // R3 — Compras por estado
  // ==========================================================================

  /// `{por_estado[], totales_por_moneda[]}`: facturado, aterrizado, pagado,
  /// reservado y diferencia, siempre por estado + moneda.
  Future<Map<String, dynamic>> comprasPorEstado({
    required int idTienda,
    DateTime? desde,
    DateTime? hasta,
  }) => _rpcVentana(
    'fn_fdi_reporte_compras',
    idTienda: idTienda,
    desde: desde,
    hasta: hasta,
  );

  // ==========================================================================
  // R4 — Costo real contra la factura
  // ==========================================================================

  /// `{compras[], resumen:{compras, por_moneda[]}}`. `pct_desvio` puede ser
  /// `null` (compra sin mercancía) y `recibido_pct` es una razón 0..1.
  Future<Map<String, dynamic>> costo({
    required int idTienda,
    DateTime? desde,
    DateTime? hasta,
  }) => _rpcVentana(
    'fn_fdi_reporte_costo',
    idTienda: idTienda,
    desde: desde,
    hasta: hasta,
  );

  // ==========================================================================
  // R5 — Diferencias cambiarias
  // ==========================================================================

  /// `{compras[], totales_por_moneda[]}`. `signo` viaja como `'a favor'`
  /// (diferencia ≤ 0) o `'en contra'` (> 0); no se recalcula en cliente.
  Future<Map<String, dynamic>> cambiario({
    required int idTienda,
    DateTime? desde,
    DateTime? hasta,
  }) => _rpcVentana(
    'fn_fdi_reporte_cambiario',
    idTienda: idTienda,
    desde: desde,
    hasta: hasta,
  );

  // ==========================================================================
  // R6 — Movimientos por día y usuario
  // ==========================================================================

  /// `{desde, hasta, por_dia_usuario[], totales_por_moneda[]}`. `entradas` y
  /// `salidas` vienen en positivo; `neto` = entradas − salidas.
  Future<Map<String, dynamic>> movimientos({
    required int idTienda,
    DateTime? desde,
    DateTime? hasta,
  }) => _rpcVentana(
    'fn_fdi_reporte_movimientos',
    idTienda: idTienda,
    desde: desde,
    hasta: hasta,
  );

  // ==========================================================================
  // R7 — Inversores
  // ==========================================================================

  /// `{inversores[], totales_por_moneda[]}` con importes nativos por moneda.
  /// Sin ventana de fechas: el reporte es el saldo a hoy.
  Future<Map<String, dynamic>> inversores({required int idTienda}) async {
    final resp = await _supabase.rpc(
      'fn_fdi_reporte_inversores',
      params: {'p_id_tienda': idTienda},
    );
    return _asMap(resp);
  }

  // ==========================================================================
  // Aging de reservas y descuadres declarados
  // ==========================================================================

  /// `{reservas_activas[], descuadres[]}`. Sin ventana: la antigüedad se mide
  /// contra `CURRENT_DATE` en el servidor.
  Future<Map<String, dynamic>> aging({required int idTienda}) async {
    final resp = await _supabase.rpc(
      'fn_fdi_reporte_aging',
      params: {'p_id_tienda': idTienda},
    );
    return _asMap(resp);
  }

  // ==========================================================================
  // R1 — Conciliación (ya existía; no se reescribe)
  // ==========================================================================

  /// `{id_tienda, claves, descuadres, filas[]}`.
  ///
  /// **`claves` y `descuadres` son escalares**, no arrays: la UI los pinta como
  /// cifras. `filas` va por (cuenta, medio, moneda) con las dos diferencias.
  Future<Map<String, dynamic>> conciliacion({required int idTienda}) async {
    final resp = await _supabase.rpc(
      'fn_fdi_conciliacion',
      params: {'p_id_tienda': idTienda},
    );
    return _asMap(resp);
  }

  /// Última revisión automática (`fn_fdi_conciliacion_ultima`).
  ///
  /// Devuelve `{ejecutada_at, claves, descuadres, diferencia_total, origen}`,
  /// o `null` si la función todavía no está desplegada, falla o no hay
  /// ejecuciones. **La nota es opcional**: la sección funciona con la
  /// ejecución en vivo, así que este método no propaga errores.
  Future<Map<String, dynamic>?> conciliacionUltima(int idTienda) async {
    try {
      final resp = await _supabase.rpc(
        'fn_fdi_conciliacion_ultima',
        params: {'p_id_tienda': idTienda},
      );
      if (resp is! Map || resp.isEmpty) return null;
      return Map<String, dynamic>.from(resp);
    } catch (_) {
      return null;
    }
  }
}
