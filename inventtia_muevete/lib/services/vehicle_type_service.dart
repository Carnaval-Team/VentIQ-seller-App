import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/vehicle_type_model.dart';

class VehicleTypeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  /// Fetches all active vehicle types from muevete.vehicle_type.
  Future<List<VehicleTypeModel>> getActiveTypes() async {
    final response = await _supabase
        .schema('muevete')
        .from('vehicle_type')
        .select()
        .eq('status', true)
        .order('id');

    return (response as List)
        .map((e) => VehicleTypeModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Subscribes to any change on muevete.vehicle_type and invokes [onChange]
  /// so the caller can re-fetch. Returns early if already subscribed.
  void subscribeToChanges(void Function() onChange) {
    if (_channel != null) return;
    _channel = _supabase
        .channel('vehicle_type_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'muevete',
          table: 'vehicle_type',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Removes the realtime subscription.
  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }
}
