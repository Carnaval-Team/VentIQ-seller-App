import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/superadmin.dart';
import '../models/usuario.dart';

class SuperAdminUserService {
  final _supabase = Supabase.instance.client;

  Future<List<SuperAdmin>> getSuperAdmins({bool soloActivos = true}) async {
    try {
      var query = _supabase
          .from('app_dat_superadmin')
          .select('*, app_dat_superadmin_roles(*)');
      if (soloActivos) {
        query = query.eq('activo', true);
      }
      final response = await query.order('nombre');

      return (response as List<dynamic>)
          .map((json) => SuperAdmin.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Error cargando superadministradores: $e');
    }
  }

  Future<SuperAdmin> createOrEnableSuperAdmin(Usuario user, int? roleId) async {
    try {
      final existing = await _supabase
          .from('app_dat_superadmin')
          .select('*, app_dat_superadmin_roles(*)')
          .eq('uuid', user.id)
          .maybeSingle();

      if (existing != null) {
        final response = await _supabase
            .from('app_dat_superadmin')
            .update({
              'activo': true,
              'id_rol': roleId,
            })
            .eq('uuid', user.id)
            .select('*, app_dat_superadmin_roles(*)')
            .single();
        return SuperAdmin.fromJson(response);
      }

      final response = await _supabase
          .from('app_dat_superadmin')
          .insert({
            'uuid': user.id,
            'nombre': user.nombre.isNotEmpty ? user.nombre : 'Usuario',
            'apellidos': user.apellido,
            'email': user.email,
            'id_rol': roleId,
            'activo': true,
          })
          .select('*, app_dat_superadmin_roles(*)')
          .single();

      return SuperAdmin.fromJson(response);
    } catch (e) {
      throw Exception('Error creando superadministrador: $e');
    }
  }

  Future<SuperAdmin> toggleSuperAdmin(int superAdminId, bool activo) async {
    try {
      final response = await _supabase
          .from('app_dat_superadmin')
          .update({'activo': activo})
          .eq('id', superAdminId)
          .select('*, app_dat_superadmin_roles(*)')
          .single();

      return SuperAdmin.fromJson(response);
    } catch (e) {
      throw Exception('Error cambiando estado del superadmin: $e');
    }
  }

  Future<void> assignRole(int superAdminId, int? roleId) async {
    try {
      await _supabase.from('app_dat_superadmin').update({
        'id_rol': roleId,
      }).eq('id', superAdminId);
    } catch (e) {
      throw Exception('Error asignando rol: $e');
    }
  }
}
