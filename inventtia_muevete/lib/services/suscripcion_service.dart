import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/suscripcion_model.dart';
import '../models/solicitud_plan_model.dart';

class SuscripcionService {
  final _supabase = Supabase.instance.client;

  // ── Obtener suscripción activa del usuario ───────────────────────────────────

  Future<SuscripcionModel?> getSuscripcionActiva(String userUuid) async {
    try {
      debugPrint('[SuscripcionService] Cargando suscripción para $userUuid');
      final data = await _supabase
          .schema('muevete')
          .from('suscripciones')
          .select()
          .eq('usuario_uuid', userUuid)
          .eq('estado', 'activa')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return SuscripcionModel.fromJson(data);
    } catch (e) {
      debugPrint('[SuscripcionService] Error getSuscripcionActiva: $e');
      return null;
    }
  }

  // ── Crear suscripción gratuita inicial al registrarse ─────────────────────────
  // Llama al RPC fn_crear_suscripcion_gratis definido en migración 018.

  Future<bool> crearSuscripcionGratis(
      String userUuid, String tipoUsuario) async {
    try {
      debugPrint(
          '[SuscripcionService] Creando suscripción gratis: user=$userUuid tipo=$tipoUsuario');
      await _supabase.rpc(
        'fn_crear_suscripcion_gratis',
        params: {
          'p_usuario_uuid': userUuid,
          'p_tipo_usuario': tipoUsuario,
        },
      );
      debugPrint('[SuscripcionService] Suscripción gratis creada OK');
      return true;
    } catch (e) {
      debugPrint('[SuscripcionService] Error crearSuscripcionGratis: $e');
      return false;
    }
  }

  // ── Actualizar plan (upgrade/downgrade) ───────────────────────────────────────
  // Marca la suscripción actual como cancelada e inserta la nueva.
  // En producción esto pasaría por un backend con integración de pago.
  // Por ahora solo actualiza en Supabase con service_role o a través de RPC.

  Future<bool> cambiarPlan({
    required String userUuid,
    required String nuevoPlanCodigo,
  }) async {
    try {
      debugPrint(
          '[SuscripcionService] Cambiando plan: user=$userUuid nuevo=$nuevoPlanCodigo');
      // Cancelar suscripción activa actual
      await _supabase
          .schema('muevete')
          .from('suscripciones')
          .update({'estado': 'cancelada', 'updated_at': DateTime.now().toIso8601String()})
          .eq('usuario_uuid', userUuid)
          .eq('estado', 'activa');

      // Calcular nuevo vencimiento: próximo día 2 después de 1 mes
      final now = DateTime.now();
      final unMes = DateTime(now.year, now.month + 1, now.day);
      DateTime vencimiento;
      if (unMes.day < 2) {
        vencimiento = DateTime(unMes.year, unMes.month, 2);
      } else {
        final nextMonth = unMes.month == 12
            ? DateTime(unMes.year + 1, 1, 2)
            : DateTime(unMes.year, unMes.month + 1, 2);
        vencimiento = nextMonth;
      }

      await _supabase.schema('muevete').from('suscripciones').insert({
        'usuario_uuid': userUuid,
        'plan_codigo': nuevoPlanCodigo,
        'estado': 'activa',
        'inicio': now.toIso8601String().split('T').first,
        'vencimiento': vencimiento.toIso8601String().split('T').first,
        'renovacion_auto': true,
      });

      debugPrint('[SuscripcionService] Plan cambiado OK');
      return true;
    } catch (e) {
      debugPrint('[SuscripcionService] Error cambiarPlan: $e');
      return false;
    }
  }

  // ── Todas las suscripciones del usuario (historial) ───────────────────────────

  Future<List<SuscripcionModel>> getHistorialSuscripciones(
      String userUuid) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('suscripciones')
          .select()
          .eq('usuario_uuid', userUuid)
          .order('created_at', ascending: false);
      return (data as List).map((e) => SuscripcionModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[SuscripcionService] Error getHistorialSuscripciones: $e');
      return [];
    }
  }

  // ── Solicitud de cambio de plan con evidencia de pago ─────────────────────────

  /// Crea una solicitud de activación de plan en estado 'pendiente'.
  /// El administrador revisará la evidencia antes de activar la suscripción.
  Future<SolicitudPlanModel?> solicitarCambioPlan({
    required String userUuid,
    required String planCodigo,
    required String evidenciaUrl,
  }) async {
    try {
      debugPrint(
          '[SuscripcionService] Creando solicitud de plan: user=$userUuid plan=$planCodigo');
      final data = await _supabase
          .schema('muevete')
          .from('solicitudes_plan')
          .insert({
            'usuario_uuid': userUuid,
            'plan_codigo': planCodigo,
            'evidencia_url': evidenciaUrl,
            'estado': 'pendiente',
          })
          .select()
          .single();
      debugPrint('[SuscripcionService] Solicitud creada OK: id=${data['id']}');
      return SolicitudPlanModel.fromJson(data);
    } catch (e) {
      debugPrint('[SuscripcionService] Error solicitarCambioPlan: $e');
      return null;
    }
  }

  // ── Obtener solicitudes del usuario ──────────────────────────────────────────

  Future<List<SolicitudPlanModel>> getMisSolicitudes(String userUuid) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('solicitudes_plan')
          .select()
          .eq('usuario_uuid', userUuid)
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => SolicitudPlanModel.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('[SuscripcionService] Error getMisSolicitudes: $e');
      return [];
    }
  }

  /// Última solicitud pendiente del usuario (si existe).
  Future<SolicitudPlanModel?> getSolicitudPendiente(String userUuid) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('solicitudes_plan')
          .select()
          .eq('usuario_uuid', userUuid)
          .eq('estado', 'pendiente')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return data != null ? SolicitudPlanModel.fromJson(data) : null;
    } catch (e) {
      debugPrint('[SuscripcionService] Error getSolicitudPendiente: $e');
      return null;
    }
  }
}
