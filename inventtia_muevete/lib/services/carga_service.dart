import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/carga_model.dart';
import '../models/estado_carga_model.dart';

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
      final int newId = data['id'] as int;
      debugPrint('[CargaService] Carga publicada id=$newId');
      // Registrar estado inicial en la bitácora
      await _registrarEstado(
        cargaId: newId,
        estadoCodigo: 'publicada',
        usuarioUuid: carga.shipperId,
        motivo: 'Carga creada',
      );
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

  Future<void> cancelarCarga(int id, {String? usuarioUuid}) async {
    try {
      await _registrarEstado(
        cargaId: id,
        estadoCodigo: 'cancelada',
        usuarioUuid: usuarioUuid,
        motivo: 'Cancelada por el shipper',
      );
      debugPrint('[CargaService] Carga $id cancelada');
    } catch (e) {
      debugPrint('[CargaService] Error cancelarCarga: $e');
      rethrow;
    }
  }

  /// Cambia el estado de una carga insertando en la bitácora [app_dat_estado_carga].
  /// La columna `estado` de [cargas] se mantiene sincronizada automáticamente
  /// por la función SQL [fn_cambiar_estado_carga].
  Future<void> actualizarEstado(
    int id,
    String nuevoEstado, {
    String? usuarioUuid,
    int? driverId,
    String? motivo,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _registrarEstado(
        cargaId: id,
        estadoCodigo: nuevoEstado,
        usuarioUuid: usuarioUuid,
        driverId: driverId,
        motivo: motivo,
        metadata: metadata,
      );
      debugPrint('[CargaService] Carga $id → estado=$nuevoEstado');
    } catch (e) {
      debugPrint('[CargaService] Error actualizarEstado: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HISTORIAL DE ESTADOS
  // ──────────────────────────────────────────────────────────────────────────

  /// Devuelve la bitácora completa de cambios de estado para una carga,
  /// ordenada de más reciente a más antigua.
  Future<List<EstadoCargaModel>> getHistorialEstados(int cargaId) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('app_dat_estado_carga')
          .select('*, app_nom_estado(nombre)')
          .eq('carga_id', cargaId)
          .order('created_at', ascending: false);
      return (data as List).map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        // Aplanar el join anidado
        final nomMap = row['app_nom_estado'];
        if (nomMap is Map) {
          row['estado_nombre'] = nomMap['nombre'];
        }
        return EstadoCargaModel.fromJson(row);
      }).toList();
    } catch (e) {
      debugPrint('[CargaService] Error getHistorialEstados: $e');
      return [];
    }
  }

  /// Devuelve el catálogo completo de estados activos.
  Future<List<NomEstadoModel>> getNomEstados() async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('app_nom_estado')
          .select()
          .eq('activo', true)
          .order('orden');
      return (data as List).map((e) => NomEstadoModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[CargaService] Error getNomEstados: $e');
      return [];
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

  Future<void> asignarCargaACarrier(int cargaId, int carrierDriverId,
      {String? usuarioUuid}) async {
    try {
      await _supabase.schema('muevete').from('cargas').update({
        'carrier_driver_id': carrierDriverId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', cargaId);
      await _registrarEstado(
        cargaId: cargaId,
        estadoCodigo: 'aceptada',
        usuarioUuid: usuarioUuid,
        driverId: carrierDriverId,
        motivo: 'Asignado por dispatcher',
      );
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

  Future<void> confirmarRecogida(int cargaId, {int? driverId}) =>
      actualizarEstado(
        cargaId,
        'en_transito',
        driverId: driverId,
        motivo: 'Recogida confirmada por carrier',
      );

  Future<void> confirmarEntrega(int cargaId, {int? driverId}) =>
      actualizarEstado(
        cargaId,
        'entregada',
        driverId: driverId,
        motivo: 'Entrega confirmada por carrier',
      );

  // ──────────────────────────────────────────────────────────────────────────
  // Helper privado: inserta en la bitácora vía RPC
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _registrarEstado({
    required int cargaId,
    required String estadoCodigo,
    String? usuarioUuid,
    int? driverId,
    String? motivo,
    Map<String, dynamic>? metadata,
  }) async {
    await _supabase.schema('muevete').rpc('fn_cambiar_estado_carga', params: {
      'p_carga_id':      cargaId,
      'p_estado_codigo': estadoCodigo,
      if (usuarioUuid != null) 'p_usuario_uuid': usuarioUuid,
      if (driverId != null)    'p_driver_id':    driverId,
      if (motivo != null)      'p_motivo':       motivo,
      if (metadata != null)    'p_metadata':     metadata,
    });
  }
}
