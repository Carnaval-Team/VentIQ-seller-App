import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wapi_licencia.dart';

/// Servicio de licencias del módulo WAPI (Notificación a Clientes).
///
/// Independiente de `SubscriptionService` — gestiona las tablas
/// `app_wapi_licencia_plan` y `app_wapi_licencia`.
///
/// Flujo:
///  1. `getPlanVigente()` → trae el plan activo (por ahora único).
///  2. `getLicenciaActual(idTienda)` → última licencia (activa, en verificación,
///      vencida o rechazada) de la tienda.
///  3. `solicitarLicencia(...)` → INSERT en estado `enVerificacion`. Un admin
///      la acredita manualmente (estado=2) fuera de la app.
class WapiLicenciaService {
  WapiLicenciaService._();
  static final WapiLicenciaService instance = WapiLicenciaService._();

  final _sb = Supabase.instance.client;

  // ── Caché en memoria con TTL ────────────────────────────────────────────
  static const Duration _ttl = Duration(minutes: 5);

  final Map<int, WapiLicencia?> _licCache = {};
  final Map<int, DateTime> _licCacheTime = {};

  WapiLicenciaPlan? _planCache;
  DateTime? _planCacheTime;

  /// Invalida caché de licencia. Llamar tras `solicitarLicencia`.
  void invalidate([int? idTienda]) {
    if (idTienda != null) {
      _licCache.remove(idTienda);
      _licCacheTime.remove(idTienda);
    } else {
      _licCache.clear();
      _licCacheTime.clear();
      _planCache = null;
      _planCacheTime = null;
    }
  }

  // ── Plan vigente ────────────────────────────────────────────────────────

  /// Devuelve el plan WAPI vigente. Por ahora hay un único registro activo,
  /// así que tomamos el primero ordenado por id.
  Future<WapiLicenciaPlan?> getPlanVigente() async {
    if (_planCache != null &&
        _planCacheTime != null &&
        DateTime.now().difference(_planCacheTime!) < _ttl) {
      return _planCache;
    }
    try {
      final row = await _sb
          .from('app_wapi_licencia_plan')
          .select()
          .eq('es_activo', true)
          .order('id', ascending: true)
          .limit(1)
          .maybeSingle();
      if (row == null) {
        _planCache = null;
        _planCacheTime = DateTime.now();
        return null;
      }
      _planCache = WapiLicenciaPlan.fromJson(row);
      _planCacheTime = DateTime.now();
      return _planCache;
    } catch (e) {
      print('❌ [WapiLicencia] getPlanVigente: $e');
      return null;
    }
  }

  // ── Licencia actual ─────────────────────────────────────────────────────

  /// Última licencia registrada para la tienda (cualquier estado),
  /// con el plan asociado vía join.
  Future<WapiLicencia?> getLicenciaActual(int idTienda) async {
    final cachedTime = _licCacheTime[idTienda];
    if (cachedTime != null && DateTime.now().difference(cachedTime) < _ttl) {
      return _licCache[idTienda];
    }
    try {
      final row = await _sb
          .from('app_wapi_licencia')
          .select('''
            *,
            app_wapi_licencia_plan (
              id,
              denominacion,
              descripcion,
              precio_mensual,
              precio_promocional,
              duracion_meses_default,
              es_activo
            )
          ''')
          .eq('id_tienda', idTienda)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) {
        _licCache[idTienda] = null;
        _licCacheTime[idTienda] = DateTime.now();
        return null;
      }
      final lic = WapiLicencia.fromJson(row);
      _licCache[idTienda] = lic;
      _licCacheTime[idTienda] = DateTime.now();
      return lic;
    } catch (e) {
      print('❌ [WapiLicencia] getLicenciaActual($idTienda): $e');
      return null;
    }
  }

  /// Atajo: ¿tiene la tienda licencia WAPI viable hoy?
  Future<bool> tieneLicenciaActiva(int idTienda) async {
    final lic = await getLicenciaActual(idTienda);
    return lic?.isActive == true;
  }

  // ── Solicitud de licencia ───────────────────────────────────────────────

  /// Crea una solicitud de licencia en estado `enVerificacion`.
  /// Devuelve la licencia recién creada.
  ///
  /// Reglas:
  ///  - `monto_pagado` se snapshotea desde el `precioVigente` del plan.
  ///  - `duracion_meses` toma el override o el default del plan.
  ///  - Incluso durante la prueba gratuita ($0), el estado inicial es
  ///    `enVerificacion` (debe acreditarlo un admin).
  Future<WapiLicencia> solicitarLicencia({
    required int idTienda,
    required int idPlan,
    int? duracionMeses,
    String? referenciaPago,
    String? notas,
    required String solicitadoPor,
  }) async {
    try {
      final plan = await getPlanVigente();
      final monto = plan?.precioVigente ?? 0;
      final meses = duracionMeses ?? plan?.duracionMesesDefault ?? 1;

      final payload = {
        'id_tienda': idTienda,
        'id_plan': idPlan,
        'estado': WapiLicenciaEstado.enVerificacion.value,
        'duracion_meses': meses,
        'monto_pagado': monto,
        'referencia_pago': referenciaPago,
        'notas': notas,
        'solicitado_por': solicitadoPor,
      };

      final row = await _sb
          .from('app_wapi_licencia')
          .insert(payload)
          .select('''
            *,
            app_wapi_licencia_plan (
              id,
              denominacion,
              descripcion,
              precio_mensual,
              precio_promocional,
              duracion_meses_default,
              es_activo
            )
          ''')
          .single();

      final lic = WapiLicencia.fromJson(row);
      invalidate(idTienda);
      _licCache[idTienda] = lic;
      _licCacheTime[idTienda] = DateTime.now();
      print('✅ [WapiLicencia] Solicitud creada: id=${lic.id} tienda=$idTienda');
      return lic;
    } catch (e) {
      print('❌ [WapiLicencia] solicitarLicencia: $e');
      rethrow;
    }
  }
}
