import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/plan_model.dart';

class PlanService {
  final _supabase = Supabase.instance.client;

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
