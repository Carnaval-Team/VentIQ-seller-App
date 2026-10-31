import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tasa_cambio.dart';

/// Obtiene la tasa de cambio del día («el toque») para calcular precios.
///
/// Orden de intentos (de más barato a más lento):
///
///  1. **Edge Function `flow-tasas`** (`functions.invoke`): una sola llamada,
///     cachea en la tabla y devuelve la matriz de conversiones.
///  2. **Respaldo `pg_net`** (migración 64), para cuando la función no está
///     desplegada: `flow.tasas_refrescar()` pide la tasa al proveedor desde
///     Postgres y devuelve un `request_id`; se sondea `flow.tasas_ingest()`
///     hasta 6 veces cada 250 ms hasta que la respuesta esté ingerida. Tarda
///     ~1-2 s, por eso el primero es la función.
///  3. **`flow.tasas_actuales()`**: última lectura, aunque la tasa no sea de hoy
///     (la UI puede avisar con la fecha).
///  4. Si nada funciona: `null`.
///
/// **Nunca lanza**: cualquier fallo se registra y se traduce en `null`, porque
/// el formulario de precios no puede romperse por no tener tasa; sólo deja de
/// calcular y avisa al admin.
///
/// La caché vive en memoria y dura lo que la sesión de la app. Sólo se reutiliza
/// si la tasa es `vigente` (de hoy); con `forzar: true` se ignora siempre.
class TasaCambioService {
  TasaCambioService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';
  static const String _funcion = 'flow-tasas';

  /// Sondeos del respaldo `pg_net`. Un proyecto recién despertado puede tardar
/// más de 1,5 s en tener la respuesta, así que se espera hasta ~3 s.
  static const int _intentosIngest = 10;
  static const Duration _esperaIngest = Duration(milliseconds: 300);

  static TasasDia? _cache;

  /// Petición `pg_net` lanzada y todavía sin ingerir.
  ///
  /// Se guarda para reutilizarla en la siguiente llamada: si el admin sigue
  /// escribiendo precios, la respuesta que llegó mientras tanto se recoge sin
  /// lanzar otra petición HTTP al proveedor.
  static Object? _requestPendiente;

  /// Tasa del día, o `null` si no se pudo obtener.
  ///
  /// [forzar] ignora la caché en memoria y pide un refresco al backend.
  static Future<TasasDia?> obtener({bool forzar = false}) async {
    if (!forzar) {
      final cache = _cache;
      if (cache != null && cache.vigente) return cache;
    }

    final desdeFuncion = await _porFuncion(forzar: forzar);
    if (desdeFuncion != null) return _guardar(desdeFuncion);

    final desdeRespaldo = await _porRpc(forzar: forzar);
    if (desdeRespaldo != null) return _guardar(desdeRespaldo);

    // Última lectura: sirve una tasa vieja antes que no calcular nada.
    final actuales = await _leerActuales();
    if (actuales != null) return _guardar(actuales);

    return null;
  }

  /// Olvida la tasa cacheada (por ejemplo al cambiar de entidad o de sesión).
  static void limpiarCache() => _cache = null;

  static TasasDia _guardar(TasasDia tasas) {
    _cache = tasas;
    return tasas;
  }

  /// Camino principal: la Edge Function `flow-tasas`.
  static Future<TasasDia?> _porFuncion({required bool forzar}) async {
    try {
      final res = await _supabase.functions.invoke(
        _funcion,
        body: {'forzar': forzar},
      );
      return TasasDia.desdeRespuesta(res.data);
    } catch (e) {
      // Lo normal mientras la función no esté desplegada: no es un error de la
      // app, se cae al respaldo por RPC.
      debugPrint(
        '[flow] TasaCambioService: la Edge Function $_funcion no respondió '
        '($e); se usa el respaldo por RPC.',
      );
      return null;
    }
  }

  /// Respaldo sin Edge Function: `tasas_refrescar` + sondeo de `tasas_ingest`.
  static Future<TasasDia?> _porRpc({required bool forzar}) async {
    try {
      // 0) Si la vez anterior quedó un sondeo a medias, se recoge primero: la
      //    respuesta de pg_net puede haber llegado mientras el admin seguía
      //    escribiendo. Cuesta una llamada y ahorra una petición HTTP.
      final pendiente = _requestPendiente;
      if (pendiente != null) {
        final recogido = await _ingerir(pendiente);
        if (recogido != null) return recogido;
      }

      final refresco = await _rpc('tasas_refrescar', {'p_forzar': forzar});
      if (refresco == null || refresco['ok'] == false) return null;

      final estado = refresco['estado']?.toString();
      if (estado == 'vigente') return await _leerActuales();
      if (estado != 'solicitado') return null;

      final requestId = refresco['request_id'];
      if (requestId == null) return null;
      _requestPendiente = requestId;

      final ingerido = await _ingerir(requestId);
      if (ingerido != null) return ingerido;

      // Se agotaron los sondeos: puede haber una tasa anterior en caché y la
      // petición queda apuntada para la próxima vez que se pida la tasa.
      return await _leerActuales();
    } catch (e) {
      debugPrint('[flow] TasaCambioService: falló el respaldo por RPC: $e');
      return null;
    }
  }

  /// Sondea `tasas_ingest` hasta que la respuesta de `pg_net` esté lista.
  ///
  /// Devuelve la tasa ya cacheada cuando se ingiere, o `null` si sigue
  /// pendiente / el proveedor falló (en cuyo caso se olvida la petición).
  static Future<TasasDia?> _ingerir(Object requestId) async {
    for (var intento = 0; intento < _intentosIngest; intento++) {
      // Se prueba ANTES de esperar: si la respuesta ya llegó (sondeo de una
      // llamada anterior), no hay motivo para dormir 300 ms.
      final ingest = await _rpc('tasas_ingest', {'p_request_id': requestId});
      if (ingest == null) return null;
      final estado = ingest['estado']?.toString();
      if (estado == 'ingerido') {
        _requestPendiente = null;
        return await _leerActuales();
      }
      if (estado == 'error') {
        _requestPendiente = null;
        return null;
      }
      await Future<void>.delayed(_esperaIngest);
    }
    return null;
  }

  static Future<TasasDia?> _leerActuales() async {
    final json = await _rpc('tasas_actuales', const {});
    if (json == null) return null;
    return TasasDia.desdeRespuesta(json);
  }

  static Future<Map<String, dynamic>?> _rpc(
    String nombre,
    Map<String, dynamic> params,
  ) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .rpc(nombre, params: params);
      return _mapa(res);
    } catch (e) {
      debugPrint('[flow] TasaCambioService.$nombre: $e');
      return null;
    }
  }

  static Map<String, dynamic>? _mapa(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return {for (final e in raw.entries) e.key.toString(): e.value};
    }
    return null;
  }
}