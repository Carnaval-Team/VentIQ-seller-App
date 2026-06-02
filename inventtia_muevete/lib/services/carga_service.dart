import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/carga_model.dart';
import '../models/estado_carga_model.dart';

class CargaService {
  final _supabase = Supabase.instance.client;

  /// Select base para cargas: incluye JOINs a los cuatro nomencladores
  static const _selectCargas = '''
    *,
    app_nom_tipo_carga(nombre, abreviacion),
    app_nom_tipo_equipo(nombre, abreviacion),
    app_nom_tipo_mercancia(nombre, codigo, nmfc_codigo),
    app_nom_commodity(nombre, codigo),
    cargas_equipo_manejo(equipo_manejo_id, app_nom_equipo_manejo_carga(nombre, codigo))
  ''';

  /// Aplana los objetos anidados del JOIN en el mapa plano que espera [CargaModel.fromJson]
  static Map<String, dynamic> _aplanarCarga(Map<String, dynamic> row) {
    final m = Map<String, dynamic>.from(row);
    final tc = m.remove('app_nom_tipo_carga');
    if (tc is Map) {
      m['tipo_carga_nombre']      = tc['nombre'];
      m['tipo_carga_abreviacion'] = tc['abreviacion'];
    }
    final te = m.remove('app_nom_tipo_equipo');
    if (te is Map) {
      m['tipo_equipo_nombre']      = te['nombre'];
      m['tipo_equipo_abreviacion'] = te['abreviacion'];
    }
    final tm = m.remove('app_nom_tipo_mercancia');
    if (tm is Map) {
      m['tipo_mercancia_nombre'] = tm['nombre'];
      m['tipo_mercancia_codigo'] = tm['codigo'];
      m['tipo_mercancia_nmfc']   = tm['nmfc_codigo'];
    }
    final co = m.remove('app_nom_commodity');
    if (co is Map) {
      m['commodity_nom_nombre'] = co['nombre'];
      m['commodity_nom_codigo'] = co['codigo'];
    }
    // M:N opciones de manejo — lista de objetos anidados
    final pivotList = m.remove('cargas_equipo_manejo');
    if (pivotList is List) {
      final ids     = <int>[];
      final nombres = <String>[];
      final codigos = <String>[];
      for (final row in pivotList) {
        if (row is! Map) continue;
        ids.add(row['equipo_manejo_id'] as int);
        final nom = row['app_nom_equipo_manejo_carga'];
        if (nom is Map) {
          nombres.add(nom['nombre'] as String? ?? '');
          codigos.add(nom['codigo']  as String? ?? '');
        }
      }
      m['opciones_equipo_manejo_ids']     = ids;
      m['opciones_equipo_manejo_nombres'] = nombres;
      m['opciones_equipo_manejo_codigos'] = codigos;
    }
    return m;
  }

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
          .select(_selectCargas)
          .single();
      final int newId = data['id'] as int;
      debugPrint('[CargaService] Carga publicada id=$newId');
      // Insertar opciones de manejo en la tabla pivot M:N
      if (carga.opcionesEquipoManejo.isNotEmpty) {
        final rows = carga.opcionesEquipoManejo
            .map((eid) => {'carga_id': newId, 'equipo_manejo_id': eid})
            .toList();
        await _supabase
            .schema('muevete')
            .from('cargas_equipo_manejo')
            .upsert(rows, onConflict: 'carga_id,equipo_manejo_id');
      }
      // Registrar estado inicial en la bitácora
      await _registrarEstado(
        cargaId: newId,
        estadoCodigo: 'publicada',
        usuarioUuid: carga.shipperId,
        motivo: 'Carga creada',
      );
      return CargaModel.fromJson(_aplanarCarga(data));
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
          .select(_selectCargas)
          .eq('shipper_id', shipperUuid)
          .order('created_at', ascending: false);
      final list = (data as List)
          .map((e) => CargaModel.fromJson(_aplanarCarga(Map<String, dynamic>.from(e as Map))))
          .toList();
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
          .select(_selectCargas)
          .eq('id', id)
          .single();
      return CargaModel.fromJson(_aplanarCarga(data));
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
          .select(_selectCargas)
          .inFilter('estado', ['publicada', 'en_matching', 'ofertada']);

      if (tipoEquipo != null && tipoEquipo.isNotEmpty) {
        // tipo_equipo_id es FK bigint — el parámetro es la abreviación,
        // el filtrado real por ID se hace en el provider/UI via tipoEquipo getter
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

      final data = await query
          .order('fecha_recogida', ascending: true, nullsFirst: false)
          .order('prioridad', ascending: false)
          .order('created_at', ascending: true);
      final list = (data as List)
          .map((e) => CargaModel.fromJson(_aplanarCarga(Map<String, dynamic>.from(e as Map))))
          .toList();
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
          .select(_selectCargas)
          .inFilter('carrier_driver_id', carrierDriverIds)
          .order('created_at', ascending: false);
      final list = (data as List)
          .map((e) => CargaModel.fromJson(_aplanarCarga(Map<String, dynamic>.from(e as Map))))
          .toList();
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
          .select(_selectCargas)
          .eq('carrier_driver_id', driverId)
          .inFilter('estado', ['tomada', 'en_transito', 'completada_carrier'])
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => CargaModel.fromJson(_aplanarCarga(Map<String, dynamic>.from(e as Map))))
          .toList();
    } catch (e) {
      debugPrint('[CargaService] Error getCargasCarrier: $e');
      rethrow;
    }
  }

  /// Carrier también puede consultar cargas por su UUID (asignadas sin oferta)
  Future<List<CargaModel>> getCargasCarrierByUuid(String carrierUuid) async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('cargas')
          .select(_selectCargas)
          .eq('carrier_uuid', carrierUuid)
          .inFilter('estado', ['tomada', 'en_transito', 'completada_carrier'])
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => CargaModel.fromJson(_aplanarCarga(Map<String, dynamic>.from(e as Map))))
          .toList();
    } catch (e) {
      debugPrint('[CargaService] Error getCargasCarrierByUuid: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SHIPPER: marcar carga como tomada (asignar carrier)
  // ──────────────────────────────────────────────────────────────────────────

  /// El shipper selecciona un carrier del directorio y marca la carga como tomada.
  /// La carga queda oculta de [getCargasDisponibles] y visible en el panel del carrier.
  Future<void> marcarComoTomada(
    int cargaId, {
    required int carrierDriverId,
    required String carrierUuid,
    String? shipperUuid,
  }) async {
    try {
      await _supabase.schema('muevete').rpc('fn_marcar_carga_tomada', params: {
        'p_carga_id':           cargaId,
        'p_carrier_driver_id':  carrierDriverId,
        'p_carrier_uuid':       carrierUuid,
        if (shipperUuid != null) 'p_usuario_uuid': shipperUuid,
      });
      debugPrint('[CargaService] Carga $cargaId marcada como tomada por carrier $carrierDriverId');
    } catch (e) {
      debugPrint('[CargaService] Error marcarComoTomada: $e');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CARRIER: confirmar recogida y completar
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> confirmarRecogida(int cargaId, {int? driverId}) =>
      actualizarEstado(
        cargaId,
        'en_transito',
        driverId: driverId,
        motivo: 'Recogida confirmada por carrier',
      );

  /// Carrier marca la carga como completada (entregada por su parte).
  Future<void> completarCargaCarrier(int cargaId, {int? driverId}) =>
      actualizarEstado(
        cargaId,
        'completada_carrier',
        driverId: driverId,
        motivo: 'Entrega confirmada por carrier',
      );

  // ──────────────────────────────────────────────────────────────────────────
  // SHIPPER: confirmar completación final
  // ──────────────────────────────────────────────────────────────────────────

  /// Shipper confirma que la carga fue completada. Cierra el ciclo.
  Future<void> completarCargaShipper(int cargaId, {String? shipperUuid}) =>
      actualizarEstado(
        cargaId,
        'completada',
        usuarioUuid: shipperUuid,
        motivo: 'Completación confirmada por shipper',
      );

  /// Mantener por compatibilidad – redirige a completarCargaCarrier
  Future<void> confirmarEntrega(int cargaId, {int? driverId}) =>
      completarCargaCarrier(cargaId, driverId: driverId);

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
