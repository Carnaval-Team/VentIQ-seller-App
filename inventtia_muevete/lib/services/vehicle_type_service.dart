import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/vehicle_type_model.dart';

class VehicleTypeService {
  final SupabaseClient _supabase = Supabase.instance.client;

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
}
