import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/plan_model.dart';

class PlanService {
  final _supabase = Supabase.instance.client;

  static const Map<String, String> planPorDefectoRegistro = {
    'shipper': 'shipper_plan',
    'carrier': 'carrier_basico_v2',
    'dispatcher': 'dispatcher_plan',
  };

  // ────────────────────────────────────────────────────────────────────────────
  // Obtener planes activos por tipo de usuario
  // ────────────────────────────────────────────────────────────────────────────

  Future<List<PlanModel>> getPlanes(String tipoUsuario) async {
    try {
      debugPrint('[PlanService] Cargando planes para tipo=$tipoUsuario');
      final data = await _supabase
          .schema('muevete')
          .from('planes')
          .select()
          .eq('tipo_usuario', tipoUsuario)
          .eq('activo', true)
          .order('precio_mensual', ascending: true);
      final list = (data as List).map((e) => PlanModel.fromJson(e)).toList();
      debugPrint('[PlanService] ${list.length} planes encontrados');
      return list;
    } catch (e) {
      debugPrint('[PlanService] Error getPlanes: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Obtener todos los planes activos de una vez (útil para cachear)
  // ────────────────────────────────────────────────────────────────────────────

  Future<List<PlanModel>> getTodosLosPlanes() async {
    try {
      debugPrint('[PlanService] Cargando todos los planes');
      final data = await _supabase
          .schema('muevete')
          .from('planes')
          .select()
          .eq('activo', true)
          .order('tipo_usuario')
          .order('precio_mensual', ascending: true);
      return (data as List).map((e) => PlanModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[PlanService] Error getTodosLosPlanes: $e');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Obtener plan por código (ej: 'shipper_basico')
  // ────────────────────────────────────────────────────────────────────────────

  /// Plan estándar asignado al registrarse (con promoción primer mes).
  Future<PlanModel?> getPlanPorDefectoRegistro(String tipoUsuario) async {
    final codigo = planPorDefectoRegistro[tipoUsuario];
    if (codigo == null) return null;
    return getPlanPorCodigo(codigo);
  }

  /// Planes de pago activos (excluye variantes *_gratis del catálogo).
  Future<List<PlanModel>> getPlanesPago(String tipoUsuario) async {
    final list = await getPlanes(tipoUsuario);
    return list.where((p) => !p.esGratis).toList();
  }

  Future<PlanModel?> getPlanPorCodigo(String codigo) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('planes')
          .select()
          .eq('codigo', codigo)
          .eq('activo', true)
          .maybeSingle();
      return data != null ? PlanModel.fromJson(data) : null;
    } catch (e) {
      debugPrint('[PlanService] Error getPlanPorCodigo($codigo): $e');
      return null;
    }
  }
}
