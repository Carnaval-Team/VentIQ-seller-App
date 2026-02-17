import 'package:supabase_flutter/supabase_flutter.dart';

class RepartidorService {
  static final RepartidorService _instance = RepartidorService._internal();
  factory RepartidorService() => _instance;
  RepartidorService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getRepartidoresActivos() async {
    final response = await _supabase
        .schema('carnavalapp')
        .from('posicion_repartidor')
        .select('id, uuid, repartidor_id, nombre, latitud, longitud, ultima_actualizacion')
        .order('ultima_actualizacion', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }
}
