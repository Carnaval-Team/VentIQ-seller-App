import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/carroceria_model.dart';

class VehicleService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Inserts multiple carrocería rows for a given driver in one batch.
  Future<void> createCarrocerias({
    required int driverId,
    required List<Map<String, dynamic>> carrocerias,
  }) async {
    if (carrocerias.isEmpty) return;

    final rows = carrocerias
        .map((c) => {
              'driver_id': driverId,
              'tipo_carroceria': c['tipo_carroceria'],
              if ((c['marca'] as String?)?.isNotEmpty == true) 'marca': c['marca'],
              if ((c['modelo'] as String?)?.isNotEmpty == true) 'modelo': c['modelo'],
              if ((c['matricula'] as String?)?.isNotEmpty == true)
                'matricula': c['matricula'],
              if (c['capacidad_ton'] != null) 'capacidad_ton': c['capacidad_ton'],
              if (c['longitud_m'] != null) 'longitud_m': c['longitud_m'],
              'seguro_vigente': c['seguro_vigente'] as bool? ?? false,
              if ((c['mc_number'] as String?)?.isNotEmpty == true)
                'mc_number': c['mc_number'],
              if ((c['dot_number'] as String?)?.isNotEmpty == true)
                'dot_number': c['dot_number'],
            })
        .toList();

    await _supabase.schema('muevete').from('carrocerias').insert(rows);
  }

  /// Returns all active carrocerías for a given driver.
  Future<List<CarroceriaModel>> getCarroceriasForDriver(int driverId) async {
    final rows = await _supabase
        .schema('muevete')
        .from('carrocerias')
        .select()
        .eq('driver_id', driverId)
        .eq('activo', true)
        .order('created_at');

    return rows.map(CarroceriaModel.fromJson).toList();
  }

  /// Inserts a single carrocería.
  Future<CarroceriaModel> addCarroceria(CarroceriaModel carroceria) async {
    final row = await _supabase
        .schema('muevete')
        .from('carrocerias')
        .insert(carroceria.toJson())
        .select()
        .single();

    return CarroceriaModel.fromJson(row);
  }

  /// Updates an existing carrocería.
  Future<void> updateCarroceria(int id, Map<String, dynamic> data) async {
    await _supabase
        .schema('muevete')
        .from('carrocerias')
        .update(data)
        .eq('id', id);
  }

  /// Soft-deletes a carrocería (sets activo = false).
  Future<void> deleteCarroceria(int id) async {
    await _supabase
        .schema('muevete')
        .from('carrocerias')
        .update({'activo': false})
        .eq('id', id);
  }
}
