import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/stop_model.dart';

class StopService {
  final _supabase = Supabase.instance.client;

  Future<StopModel> createStop(int idViaje, int driverId, double lat, double lon) async {
    final res = await _supabase
        .schema('muevete')
        .from('paradas_viaje')
        .insert({
          'id_viaje': idViaje,
          'driver_id': driverId,
          'latitud': lat,
          'longitud': lon,
        })
        .select()
        .single();
    return StopModel.fromJson(res);
  }

  Future<void> endStop(int stopId) async {
    final now = DateTime.now().toUtc();
    // Fetch stop to calculate elapsed time
    final row = await _supabase
        .schema('muevete')
        .from('paradas_viaje')
        .select()
        .eq('id', stopId)
        .single();
    final createdAt = DateTime.parse(row['created_at'] as String);
    final seconds = now.difference(createdAt).inSeconds;
    await _supabase
        .schema('muevete')
        .from('paradas_viaje')
        .update({
          'salida_at': now.toIso8601String(),
          'tiempo_detenido': seconds,
        })
        .eq('id', stopId);
  }

  Future<List<StopModel>> getStopsForTrip(int idViaje) async {
    final res = await _supabase
        .schema('muevete')
        .from('paradas_viaje')
        .select()
        .eq('id_viaje', idViaje)
        .order('created_at');
    return (res as List).map((e) => StopModel.fromJson(e)).toList();
  }

  Future<StopModel?> getActiveStop(int idViaje) async {
    final res = await _supabase
        .schema('muevete')
        .from('paradas_viaje')
        .select()
        .eq('id_viaje', idViaje)
        .isFilter('salida_at', null)
        .maybeSingle();
    if (res == null) return null;
    return StopModel.fromJson(res);
  }

  Future<int> getTotalWaitSeconds(int idViaje) async {
    final res = await _supabase
        .schema('muevete')
        .from('paradas_viaje')
        .select('tiempo_detenido')
        .eq('id_viaje', idViaje);
    int total = 0;
    for (final row in res) {
      total += (row['tiempo_detenido'] as num?)?.toInt() ?? 0;
    }
    return total;
  }
}
