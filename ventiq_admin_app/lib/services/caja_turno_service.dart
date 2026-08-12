import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/caja_turno.dart';
import 'store_selector_service.dart';

/// Servicio para listar turnos de caja (app_dat_caja_turno) con sus
/// agregados de venta, cobros y egresos.
///
/// Ruta principal: RPC `fn_listar_turnos_admin` — una sola consulta que
/// pagina primero y agrega despues (ver docs/migrations/fn_listar_turnos_admin.sql).
/// Si la funcion aun no esta desplegada, cae a un select PostgREST con
/// recursos embebidos: mantiene el tab usable, pero sin los KPIs.
class CajaTurnoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final StoreSelectorService _storeSelectorService =
      StoreSelectorService();

  /// Se apaga tras el primer 404 para no reintentar la RPC en cada scroll.
  static bool _rpcDisponible = true;

  static Future<int?> _getStoreId([int? providedStoreId]) async {
    if (providedStoreId != null) return providedStoreId;

    final selectedStoreId = _storeSelectorService.getSelectedStoreId();
    if (selectedStoreId != null) return selectedStoreId;

    if (!_storeSelectorService.isInitialized) {
      await _storeSelectorService.initialize();
      return _storeSelectorService.getSelectedStoreId();
    }

    if (_storeSelectorService.userStores.isNotEmpty) {
      return _storeSelectorService.userStores.first.id;
    }

    return null;
  }

  static Future<CajaTurnoResponse> listTurnos({
    int? storeId,
    int? idTpv,
    int? idVendedor,
    int? estado,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    bool soloDiscrepancias = false,
    String? busqueda,
    int limite = 20,
    int pagina = 1,
  }) async {
    final resolvedStoreId = await _getStoreId(storeId);
    if (resolvedStoreId == null) {
      throw Exception('No se pudo obtener el ID de la tienda');
    }

    // Las fechas del picker vienen a medianoche: se extiende el "hasta"
    // al final del dia para no cortar los turnos de la tarde.
    final desde = fechaDesde == null
        ? null
        : DateTime(fechaDesde.year, fechaDesde.month, fechaDesde.day);
    final hasta = fechaHasta == null
        ? null
        : DateTime(
            fechaHasta.year,
            fechaHasta.month,
            fechaHasta.day,
            23,
            59,
            59,
          );

    final query = _TurnoQuery(
      storeId: resolvedStoreId,
      idTpv: idTpv,
      idVendedor: idVendedor,
      estado: estado,
      desde: desde,
      hasta: hasta,
      soloDiscrepancias: soloDiscrepancias,
      busqueda: (busqueda == null || busqueda.trim().isEmpty)
          ? null
          : busqueda.trim(),
      limite: limite,
      pagina: pagina,
    );

    if (_rpcDisponible) {
      try {
        return await _listViaRpc(query);
      } catch (e) {
        if (_esFuncionInexistente(e)) {
          _rpcDisponible = false;
          print(
            '⚠️ fn_listar_turnos_admin no esta desplegada, usando fallback PostgREST',
          );
        } else {
          print('❌ Error listando turnos: $e');
          rethrow;
        }
      }
    }

    return _listViaPostgrest(query);
  }

  static Future<CajaTurnoResponse> _listViaRpc(_TurnoQuery q) async {
    final params = {
      'p_id_tienda': q.storeId,
      'p_id_tpv': q.idTpv,
      'p_id_vendedor': q.idVendedor,
      'p_estado': q.estado,
      'p_fecha_desde': q.desde?.toIso8601String(),
      'p_fecha_hasta': q.hasta?.toIso8601String(),
      'p_solo_discrepancias': q.soloDiscrepancias,
      'p_busqueda': q.busqueda,
      'p_limite': q.limite,
      'p_pagina': q.pagina,
    };
    print('📡 RPC fn_listar_turnos_admin params: $params');

    final response = await _supabase.rpc(
      'fn_listar_turnos_admin',
      params: params,
    );

    if (response == null || response is! List || response.isEmpty) {
      return CajaTurnoResponse.empty();
    }

    final turnos = response
        .map((item) => CajaTurno.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    final total =
        (response.first as Map<String, dynamic>)['total_registros'] ??
        turnos.length;

    return CajaTurnoResponse(
      turnos: turnos,
      totalCount: total is int ? total : (total as num).toInt(),
    );
  }

  /// Fallback sin RPC: un solo request con recursos embebidos por FK
  /// (tpv, vendedor -> trabajador, estado). Sin KPIs de venta/cobros.
  /// El scope de tienda se aplica con `!inner` sobre el TPV embebido.
  static Future<CajaTurnoResponse> _listViaPostgrest(_TurnoQuery q) async {
    try {
      var filtros = _supabase
          .from('app_dat_caja_turno')
          .select('''
            id, id_tpv, id_vendedor, estado, observaciones,
            efectivo_inicial, efectivo_esperado, efectivo_real, diferencia,
            fecha_apertura, fecha_cierre, maneja_inventario,
            id_operacion_apertura, id_operacion_cierre,
            tpv:app_dat_tpv!inner(id, denominacion, id_tienda),
            vendedor:app_dat_vendedor(
              id, uuid, id_trabajador,
              trabajador:app_dat_trabajadores(id, nombres, apellidos)
            ),
            estado_operacion:app_nom_estado_operacion(id, denominacion)
          ''')
          .eq('tpv.id_tienda', q.storeId);

      if (q.idTpv != null) filtros = filtros.eq('id_tpv', q.idTpv!);
      if (q.idVendedor != null) {
        filtros = filtros.eq('id_vendedor', q.idVendedor!);
      }
      if (q.estado != null) filtros = filtros.eq('estado', q.estado!);
      if (q.desde != null) {
        filtros = filtros.gte('fecha_apertura', q.desde!.toIso8601String());
      }
      if (q.hasta != null) {
        filtros = filtros.lte('fecha_apertura', q.hasta!.toIso8601String());
      }
      if (q.soloDiscrepancias) {
        filtros = filtros.not('observaciones', 'is', null);
      }
      // Sin RPC no se puede buscar en varias tablas a la vez: se limita a
      // observaciones, que es el campo mas util para auditar.
      if (q.busqueda != null) {
        filtros = filtros.ilike('observaciones', '%${q.busqueda}%');
      }

      final offset = (q.pagina - 1) * q.limite;
      final response = await filtros
          .order('fecha_apertura', ascending: false)
          .range(offset, offset + q.limite - 1)
          .count(CountOption.exact);

      final turnos = response.data
          .map((row) => CajaTurno.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      return CajaTurnoResponse(turnos: turnos, totalCount: response.count);
    } catch (e) {
      print('❌ Error listando turnos (fallback PostgREST): $e');
      rethrow;
    }
  }

  static bool _esFuncionInexistente(Object e) {
    if (e is PostgrestException) {
      // PGRST202 = function not found in schema cache; 42883 = undefined_function
      return e.code == 'PGRST202' ||
          e.code == '404' ||
          e.code == '42883' ||
          e.message.contains('Could not find the function');
    }
    return false;
  }
}

/// Filtros normalizados que comparten la RPC y el fallback.
class _TurnoQuery {
  final int storeId;
  final int? idTpv;
  final int? idVendedor;
  final int? estado;
  final DateTime? desde;
  final DateTime? hasta;
  final bool soloDiscrepancias;
  final String? busqueda;
  final int limite;
  final int pagina;

  const _TurnoQuery({
    required this.storeId,
    this.idTpv,
    this.idVendedor,
    this.estado,
    this.desde,
    this.hasta,
    required this.soloDiscrepancias,
    this.busqueda,
    required this.limite,
    required this.pagina,
  });
}
