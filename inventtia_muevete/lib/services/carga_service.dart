import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/carga_model.dart';

class CargaService {
  final _supabase = Supabase.instance.client;

  // ──────────────────────────────────────────────────────────────────────────
  // SHIPPER: publicar y gestionar cargas propias
  // ──────────────────────────────────────────────────────────────────────────

  Future<CargaModel?> publicarCarga(CargaModel carga) async {
    try {
      debugPrint('[CargaService] Publicando carga...');
      final data = await _supabase
          .schema('muevete')
          .from('cargas')
          .insert(carga.toInsertJson())
          .select()
          .single();
      debugPrint('[CargaService] Carga publicada id=${data['id']}');
      return CargaModel.fromJson(data);
    } catch (e) {
      debugPrint('[CargaService] Error publicarCarga: $e');
      rethrow;
    }
  }

  Future<List<CargaModel>> getCargasShipper(String shipperUuid) async {
    try {
      debugPrint('[CargaService] Cargando cargas shipper=$shipperUuid');
      final data = await _supabase
          .schema('muevete')
          .from('cargas')
          .select()
          .eq('shipper_id', shipperUuid)
          .order('created_at', ascending: false);
      final list =
          (data as List).map((e) => CargaModel.fromJson(e)).toList();
      debugPrint('[CargaService] ${list.length} cargas del shipper');
      return list;
    } catch (e) {
      debugPrint('[CargaService] Error getCargasShipper: $e');
      rethrow;
    }
  }

  Future<CargaModel?> getCargaById(int id) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('cargas')
          .select()
          .eq('id', id)
          .single();
      return CargaModel.fromJson(data);
    } catch (e) {
      debugPrint('[CargaService] Error getCargaById: $e');
      return null;
    }
  }

  Future<void> cancelarCarga(int id) async {
    try {
      await _supabase
          .schema('muevete')
          .from('cargas')
          .update({'estado': 'cancelada', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', id);
      debugPrint('[CargaService] Carga $id cancelada');
    } catch (e) {
      debugPrint('[CargaService] Error cancelarCarga: $e');
      rethrow;
    }
  }

  Future<void> actualizarEstado(int id, String nuevoEstado) async {
    try {
      await _supabase
          .schema('muevete')
          .from('cargas')
          .update({'estado': nuevoEstado, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', id);
      debugPrint('[CargaService] Carga $id → estado=$nuevoEstado');
    } catch (e) {
      debugPrint('[CargaService] Error actualizarEstado: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CARRIER: cargas disponibles para ofertar
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<CargaModel>> getCargasDisponibles({
    String? tipoEquipo,
    String? ciudadOrigen,
    String? ciudadDestino,
    double? pesoMaxKg,
    double? precioMin,
    double? precioMax,
  }) async {
    try {
      debugPrint('[CargaService] Cargando cargas disponibles...');
      var query = _supabase
          .schema('muevete')
          .from('cargas')
          .select()
          .inFilter('estado', ['publicada', 'en_matching', 'ofertada']);

      if (tipoEquipo != null && tipoEquipo.isNotEmpty) {
        query = query.eq('tipo_equipo', tipoEquipo);
      }
      if (ciudadOrigen != null && ciudadOrigen.isNotEmpty) {
        query = query.ilike('ciudad_origen', '%$ciudadOrigen%');
      }
      if (ciudadDestino != null && ciudadDestino.isNotEmpty) {
        query = query.ilike('ciudad_destino', '%$ciudadDestino%');
      }
      if (pesoMaxKg != null) {
        query = query.lte('peso_kg', pesoMaxKg);
      }
      if (precioMin != null) {
        query = query.gte('precio_ofertado', precioMin);
      }
      if (precioMax != null) {
        query = query.lte('precio_ofertado', precioMax);
      }

      final data = await query.order('created_at', ascending: false);
      final list =
          (data as List).map((e) => CargaModel.fromJson(e)).toList();
      debugPrint('[CargaService] ${list.length} cargas disponibles');
      return list;
    } catch (e) {
      debugPrint('[CargaService] Error getCargasDisponibles: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DISPATCHER: cargas gestionadas por su flota
  // ──────────────────────────────────────────────────────────────────────────

  /// Obtiene todas las cargas asignadas a transportistas del dispatcher.
  Future<List<CargaModel>> getCargasDispatcher(
      List<int> carrierDriverIds) async {
    try {
      if (carrierDriverIds.isEmpty) return [];
      debugPrint(
          '[CargaService] Cargas dispatcher, carriers=$carrierDriverIds');
      final data = await _supabase
          .schema('muevete')
          .from('cargas')
          .select()
          .inFilter('carrier_driver_id', carrierDriverIds)
          .order('created_at', ascending: false);
      final list =
          (data as List).map((e) => CargaModel.fromJson(e)).toList();
      debugPrint('[CargaService] ${list.length} cargas del dispatcher');
      return list;
    } catch (e) {
      debugPrint('[CargaService] Error getCargasDispatcher: $e');
      rethrow;
    }
  }

  /// Asigna una carga disponible a un transportista de la flota del dispatcher.
  Future<void> asignarCargaACarrier(int cargaId, int carrierDriverId) async {
    try {
      await _supabase.schema('muevete').from('cargas').update({
        'carrier_driver_id': carrierDriverId,
        'estado': 'aceptada',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', cargaId);
      debugPrint(
          '[CargaService] Carga $cargaId asignada a carrier $carrierDriverId');
    } catch (e) {
      debugPrint('[CargaService] Error asignarCargaACarrier: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CARRIER: cargas activas propias
  // ──────────────────────────────────────────────────────────────────────────

  Future<List<CargaModel>> getCargasCarrier(int driverId) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('cargas')
          .select()
          .eq('carrier_driver_id', driverId)
          .order('created_at', ascending: false);
      return (data as List).map((e) => CargaModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[CargaService] Error getCargasCarrier: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CARRIER: confirmar recogida y entrega
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> confirmarRecogida(int cargaId) =>
      actualizarEstado(cargaId, 'en_transito');

  Future<void> confirmarEntrega(int cargaId) =>
      actualizarEstado(cargaId, 'entregada');
}
