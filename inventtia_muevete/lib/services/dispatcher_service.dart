import 'package:supabase_flutter/supabase_flutter.dart';

class DispatcherService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Map<String, dynamic> _carroceriaPayload(Map<String, dynamic> t, int driverId) {
    final marca = (t['marca'] as String?)?.trim();
    final modelo = (t['modelo'] as String?)?.trim();
    final matricula = (t['matricula'] as String?)?.trim();
    return {
      'driver_id': driverId,
      'tipo_carroceria': (t['tipo_carroceria'] as String?)?.trim().isNotEmpty == true
          ? t['tipo_carroceria']
          : 'otro',
      if (marca != null && marca.isNotEmpty) 'marca': marca,
      if (modelo != null && modelo.isNotEmpty) 'modelo': modelo,
      if (matricula != null && matricula.isNotEmpty) 'matricula': matricula,
      if (t['capacidad_ton'] != null) 'capacidad_ton': t['capacidad_ton'],
      if (t['longitud_m'] != null) 'longitud_m': t['longitud_m'],
      'seguro_vigente': t['seguro_vigente'] ?? false,
    };
  }

  /// Registers a list of drivers under a dispatcher during registration.
  /// Drivers are stored in muevete.drivers linked via dispatcher_id.
  /// No auth account is created — they are operational data only.
  Future<void> registrarTransportistas({
    required String dispatcherUuid,
    required int dispatcherDriverId,
    required List<Map<String, dynamic>> transportistas,
  }) async {
    for (final t in transportistas) {
      final driverRow = await _supabase
          .schema('muevete')
          .from('drivers')
          .insert({
            'name': t['name'] as String,
            'email': t['email'] as String?,
            'telefono': t['telefono'] as String?,
            'estado': true,
            'kyc': false,
            'tipo_usuario': 'carrier_carga',
            'dispatcher_id': dispatcherDriverId,
            if (t['lic_conduccion_frente_url'] != null)
              'lic_conduccion_frente_url': t['lic_conduccion_frente_url'],
            if (t['lic_conduccion_dorso_url'] != null)
              'lic_conduccion_dorso_url': t['lic_conduccion_dorso_url'],
            if (t['lic_circulacion_frente_url'] != null)
              'lic_circulacion_frente_url': t['lic_circulacion_frente_url'],
            if (t['lic_circulacion_dorso_url'] != null)
              'lic_circulacion_dorso_url': t['lic_circulacion_dorso_url'],
            if (t['lic_operativa_frente_url'] != null)
              'lic_operativa_frente_url': t['lic_operativa_frente_url'],
            if (t['lic_operativa_dorso_url'] != null)
              'lic_operativa_dorso_url': t['lic_operativa_dorso_url'],
          })
          .select('id')
          .single();

      final driverId = driverRow['id'] as int;
      await _supabase
          .schema('muevete')
          .from('carrocerias')
          .insert(_carroceriaPayload(t, driverId));
    }
  }

  /// Adds a single driver to the dispatcher's fleet.
  /// No auth account is created — driver is operational data only.
  Future<void> invitarTransportista({
    required String dispatcherUuid,
    required int dispatcherDriverId,
    required Map<String, dynamic> transportista,
  }) async {
    final t = transportista;

    final driverRow = await _supabase
        .schema('muevete')
        .from('drivers')
        .insert({
          'name': t['name'] as String,
          'email': t['email'] as String?,
          'telefono': t['telefono'] as String?,
          'estado': true,
          'kyc': false,
          'tipo_usuario': 'carrier_carga',
          'dispatcher_id': dispatcherDriverId,
          if (t['lic_conduccion_frente_url'] != null)
            'lic_conduccion_frente_url': t['lic_conduccion_frente_url'],
          if (t['lic_conduccion_dorso_url'] != null)
            'lic_conduccion_dorso_url': t['lic_conduccion_dorso_url'],
          if (t['lic_circulacion_frente_url'] != null)
            'lic_circulacion_frente_url': t['lic_circulacion_frente_url'],
          if (t['lic_circulacion_dorso_url'] != null)
            'lic_circulacion_dorso_url': t['lic_circulacion_dorso_url'],
          if (t['lic_operativa_frente_url'] != null)
            'lic_operativa_frente_url': t['lic_operativa_frente_url'],
          if (t['lic_operativa_dorso_url'] != null)
            'lic_operativa_dorso_url': t['lic_operativa_dorso_url'],
        })
        .select('id')
        .single();

    final driverId = driverRow['id'] as int;
    await _supabase
        .schema('muevete')
        .from('carrocerias')
        .insert(_carroceriaPayload(t, driverId));
  }

  /// Updates a driver's profile and vehicle (carroceria) data.
  Future<void> actualizarTransportista({
    required int driverId,
    required Map<String, dynamic> driverData,
    Map<String, dynamic>? carroceriaData,
    int? carroceriaId,
    int? dispatcherDriverId,
  }) async {
    await _supabase
        .schema('muevete')
        .from('drivers')
        .update(driverData)
        .eq('id', driverId);

    if (carroceriaData != null && carroceriaData.isNotEmpty) {
      if (carroceriaId != null) {
        await _supabase
            .schema('muevete')
            .from('carrocerias')
            .update(carroceriaData)
            .eq('id', carroceriaId);
      } else {
        await _supabase.schema('muevete').from('carrocerias').insert({
          'driver_id': driverId,
          ...carroceriaData,
        });
      }
    }
  }

  /// Deletes a driver and their carroceria from the dispatcher's fleet.
  Future<void> eliminarTransportista(int driverId) async {
    // Clean up legacy sub_usuarios rows that may reference this driver
    await _supabase
        .schema('muevete')
        .from('sub_usuarios')
        .delete()
        .eq('sub_driver_id', driverId);

    await _supabase
        .schema('muevete')
        .from('carrocerias')
        .delete()
        .eq('driver_id', driverId);

    await _supabase
        .schema('muevete')
        .from('drivers')
        .delete()
        .eq('id', driverId);
  }
}
