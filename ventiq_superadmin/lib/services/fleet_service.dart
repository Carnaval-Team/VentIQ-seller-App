import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/fleet_models.dart';

class FleetService {
  static final FleetService _instance = FleetService._internal();
  factory FleetService() => _instance;
  FleetService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene todos los repartidores con su última posición y órdenes en el rango de fechas.
  /// Usa solo 2 queries + combinación en memoria para evitar N+1.
  Future<List<RepartidorFlota>> fetchRepartidoresConOrdenes({
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    // Query 1: Posiciones actuales con info del repartidor (JOIN via FK)
    final posicionesRaw = await _supabase
        .schema('carnavalapp')
        .from('posicion_repartidor')
        .select(
          'id, uuid, repartidor_id, nombre, latitud, longitud, ultima_actualizacion, '
          'repartidores(id, nombre, telefono, correo, status)',
        )
        .order('ultima_actualizacion', ascending: false);

    final posiciones = List<Map<String, dynamic>>.from(posicionesRaw);

    // Recolectar IDs de repartidores para buscar sus órdenes
    final repartidorIds = posiciones
        .map((p) => p['repartidor_id'])
        .where((id) => id != null)
        .toSet()
        .toList();

    // Query 2: Órdenes asignadas con detalles y productos (JOIN via FK)
    Map<int, List<OrdenAsignada>> ordenesPorRepartidor = {};

    if (repartidorIds.isNotEmpty) {
      var ordenesQuery = _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select(
            'id, total, status, direccion, created_at, repartidor, '
            'OrderDetails(id, quantity, price, Productos(id, name, price, image))',
          )
          .inFilter('repartidor', repartidorIds);

      if (fechaDesde != null) {
        ordenesQuery = ordenesQuery.gte(
          'created_at',
          fechaDesde.toIso8601String().split('T')[0],
        );
      }
      if (fechaHasta != null) {
        ordenesQuery = ordenesQuery.lte(
          'created_at',
          fechaHasta.toIso8601String().split('T')[0],
        );
      }

      final ordenesRaw = await ordenesQuery;

      final ordenes = List<Map<String, dynamic>>.from(ordenesRaw);

      for (final orden in ordenes) {
        final repId = orden['repartidor'] is int
            ? orden['repartidor'] as int
            : int.tryParse(orden['repartidor']?.toString() ?? '');
        if (repId == null) continue;

        ordenesPorRepartidor.putIfAbsent(repId, () => []);
        ordenesPorRepartidor[repId]!.add(OrdenAsignada.fromMap(orden));
      }
    }

    // Combinar posiciones + órdenes
    return posiciones.map((posicion) {
      final repId = posicion['repartidor_id'] is int
          ? posicion['repartidor_id'] as int
          : int.tryParse(posicion['repartidor_id']?.toString() ?? '');

      final ordenes = repId != null
          ? (ordenesPorRepartidor[repId] ?? [])
          : <OrdenAsignada>[];

      return RepartidorFlota.fromMap(posicion, ordenes: ordenes);
    }).toList();
  }

  /// Obtiene el historial de posiciones de un repartidor en un rango de fechas.
  Future<List<Map<String, dynamic>>> fetchHistorialRuta(
    int repartidorId, {
    int limit = 100,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    print('[FleetService] fetchHistorialRuta repartidorId=$repartidorId limit=$limit');
    var query = _supabase
        .schema('carnavalapp')
        .from('posicion_repartidor_history')
        .select('id, latitud, longitud, registrado_en')
        .eq('repartidor_id', repartidorId);

    if (fechaDesde != null) {
      query = query.gte('registrado_en', fechaDesde.toIso8601String());
    }
    if (fechaHasta != null) {
      query = query.lte('registrado_en', fechaHasta.toIso8601String());
    }

    final response = await query
        .order('registrado_en', ascending: true)
        .limit(limit);

    final result = List<Map<String, dynamic>>.from(response);
    print('[FleetService] fetchHistorialRuta -> ${result.length} puntos');
    if (result.isNotEmpty) {
      print('[FleetService]   primer punto: lat=${result.first['latitud']} lng=${result.first['longitud']}');
      print('[FleetService]   ultimo punto: lat=${result.last['latitud']} lng=${result.last['longitud']}');
    }
    return result;
  }
}
