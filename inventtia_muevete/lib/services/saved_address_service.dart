import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/saved_address_model.dart';

class SavedAddressService {
  final _db = Supabase.instance.client;

  Future<List<SavedAddressModel>> getAddresses(String userId) async {
    final data = await _db
        .schema('muevete')
        .from('direcciones_rapidas')
        .select()
        .eq('user_id', userId)
        .order('created_at');
    return (data as List).map((e) => SavedAddressModel.fromJson(e)).toList();
  }

  Future<SavedAddressModel> createAddress({
    required String userId,
    required String label,
    required String icon,
    required String direccion,
    required double latitud,
    required double longitud,
  }) async {
    final data = await _db
        .schema('muevete')
        .from('direcciones_rapidas')
        .insert({
          'user_id': userId,
          'label': label,
          'icon': icon,
          'direccion': direccion,
          'latitud': latitud,
          'longitud': longitud,
        })
        .select()
        .single();
    return SavedAddressModel.fromJson(data);
  }

  Future<void> updateAddress(int id, {
    String? label,
    String? icon,
    String? direccion,
    double? latitud,
    double? longitud,
  }) async {
    final updates = <String, dynamic>{};
    if (label != null) updates['label'] = label;
    if (icon != null) updates['icon'] = icon;
    if (direccion != null) updates['direccion'] = direccion;
    if (latitud != null) updates['latitud'] = latitud;
    if (longitud != null) updates['longitud'] = longitud;
    if (updates.isEmpty) return;

    await _db
        .schema('muevete')
        .from('direcciones_rapidas')
        .update(updates)
        .eq('id', id);
  }

  Future<void> deleteAddress(int id) async {
    await _db
        .schema('muevete')
        .from('direcciones_rapidas')
        .delete()
        .eq('id', id);
  }

  /// Update or insert user photo_url in muevete.users
  Future<void> updateUserPhoto(String uuid, String photoUrl) async {
    await _db
        .schema('muevete')
        .from('users')
        .update({'photo_url': photoUrl})
        .eq('uuid', uuid);
  }
}
