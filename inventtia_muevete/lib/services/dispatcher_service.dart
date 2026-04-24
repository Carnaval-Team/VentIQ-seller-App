import 'package:supabase_flutter/supabase_flutter.dart';

class DispatcherService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Registers a list of carriers under a dispatcher.
  /// Creates a row in muevete.drivers (tipo_usuario='carrier_carga') for each
  /// carrier and links them in muevete.sub_usuarios with estado='pendiente'.
  /// Called immediately after the dispatcher's own profile is created.
  Future<void> registrarTransportistas({
    required String dispatcherUuid,
    required int dispatcherDriverId,
    required List<Map<String, dynamic>> transportistas,
  }) async {
    for (final t in transportistas) {
      // 1. Create a carrier_carga profile in drivers (estado=false = not yet active)
      final driverRow = await _supabase
          .schema('muevete')
          .from('drivers')
          .insert({
            'name': t['name'] as String,
            'email': t['email'] as String,
            'telefono': t['telefono'] as String?,
            'estado': false,
            'kyc': false,
            'tipo_usuario': 'carrier_carga',
            'dispatcher_id': dispatcherDriverId,
            if (t['tipo_carroceria'] != null)
              'tipo_carroceria': t['tipo_carroceria'],
            if (t['marca'] != null) 'categoria': t['marca'],
            if (t['capacidad_ton'] != null) 'capacidad_ton': t['capacidad_ton'],
            if (t['mc_number'] != null && (t['mc_number'] as String).isNotEmpty)
              'mc_number': t['mc_number'],
            if (t['dot_number'] != null &&
                (t['dot_number'] as String).isNotEmpty)
              'dot_number': t['dot_number'],
          })
          .select('id')
          .single();

      final subDriverId = driverRow['id'] as int;

      // 2. Create a placeholder auth.users entry is NOT possible from the client
      //    (Supabase admin API only). Instead, we store the invitation in
      //    sub_usuarios with invitacion_estado='pendiente' and a placeholder uuid.
      //    The carrier will use a magic-link / sign-up flow to activate.
      //    We use the dispatcher uuid temporarily; it will be replaced when
      //    the carrier activates their account via the invitation token.
      await _supabase.schema('muevete').from('sub_usuarios').insert({
        'propietario_uuid': dispatcherUuid,
        'tipo_propietario': 'dispatcher',
        'sub_uuid': dispatcherUuid, // placeholder — updated on activation
        'sub_driver_id': subDriverId,
        'rol': 'conductor',
        'invitacion_estado': 'pendiente',
        'invitacion_email': t['email'] as String,
        'activo': false,
      });
    }
  }

  /// Invites a single new carrier to join a dispatcher's fleet post-registration.
  Future<void> invitarTransportista({
    required String dispatcherUuid,
    required int dispatcherDriverId,
    required Map<String, dynamic> transportista,
  }) async {
    final driverRow = await _supabase
        .schema('muevete')
        .from('drivers')
        .insert({
          'name': transportista['name'] as String,
          'email': transportista['email'] as String,
          'telefono': transportista['telefono'] as String?,
          'estado': false,
          'kyc': false,
          'tipo_usuario': 'carrier_carga',
          'dispatcher_id': dispatcherDriverId,
          if (transportista['tipo_carroceria'] != null)
            'tipo_carroceria': transportista['tipo_carroceria'],
          if (transportista['capacidad_ton'] != null)
            'capacidad_ton': transportista['capacidad_ton'],
          if (transportista['mc_number'] != null &&
              (transportista['mc_number'] as String).isNotEmpty)
            'mc_number': transportista['mc_number'],
          if (transportista['dot_number'] != null &&
              (transportista['dot_number'] as String).isNotEmpty)
            'dot_number': transportista['dot_number'],
        })
        .select('id')
        .single();

    final subDriverId = driverRow['id'] as int;

    await _supabase.schema('muevete').from('sub_usuarios').insert({
      'propietario_uuid': dispatcherUuid,
      'tipo_propietario': 'dispatcher',
      'sub_uuid': dispatcherUuid,
      'sub_driver_id': subDriverId,
      'rol': 'conductor',
      'invitacion_estado': 'pendiente',
      'invitacion_email': transportista['email'] as String,
      'activo': false,
    });
  }

  /// Returns all carriers linked to a dispatcher, with their invitation state.
  Future<List<Map<String, dynamic>>> getTransportistas(
      int dispatcherDriverId) async {
    final rows = await _supabase
        .schema('muevete')
        .from('sub_usuarios')
        .select('*, drivers:sub_driver_id(*)')
        .eq('tipo_propietario', 'dispatcher')
        .eq('sub_driver_id', dispatcherDriverId);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Revokes a carrier from the dispatcher's fleet.
  Future<void> revocarTransportista(int subUsuarioId) async {
    await _supabase
        .schema('muevete')
        .from('sub_usuarios')
        .update({'invitacion_estado': 'revocado', 'activo': false})
        .eq('id', subUsuarioId);
  }
}
