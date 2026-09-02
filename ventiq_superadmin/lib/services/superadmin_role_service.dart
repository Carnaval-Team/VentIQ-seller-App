import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/superadmin_role.dart';

class SuperAdminRoleService {
  final _supabase = Supabase.instance.client;

  Future<List<SuperAdminRole>> getRoles({bool soloActivos = true}) async {
    try {
      var query = _supabase.from('app_dat_superadmin_roles').select();
      if (soloActivos) {
        query = query.eq('activo', true);
      }
      final response = await query.order('nombre') as List<dynamic>;

      return response.map((json) => SuperAdminRole.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Error cargando roles: $e');
    }
  }

  Future<SuperAdminRole?> getRoleById(int id) async {
    try {
      final response = await _supabase
          .from('app_dat_superadmin_roles')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return SuperAdminRole.fromJson(response);
    } catch (e) {
      throw Exception('Error cargando rol: $e');
    }
  }

  Future<SuperAdminRole> createRole(SuperAdminRole role) async {
    try {
      final response = await _supabase
          .from('app_dat_superadmin_roles')
          .insert({
            'nombre': role.nombre,
            'descripcion': role.descripcion,
            'permisos': role.permisos,
            'activo': role.activo,
          })
          .select()
          .single();

      return SuperAdminRole.fromJson(response);
    } catch (e) {
      throw Exception('Error creando rol: $e');
    }
  }

  Future<SuperAdminRole> updateRole(SuperAdminRole role) async {
    if (role.id == null) {
      throw Exception('El rol no tiene id');
    }
    try {
      final response = await _supabase
          .from('app_dat_superadmin_roles')
          .update({
            'nombre': role.nombre,
            'descripcion': role.descripcion,
            'permisos': role.permisos,
            'activo': role.activo,
          })
          .eq('id', role.id!)
          .select()
          .single();

      return SuperAdminRole.fromJson(response);
    } catch (e) {
      throw Exception('Error actualizando rol: $e');
    }
  }

  Future<void> deleteRole(int id) async {
    try {
      await _supabase.from('app_dat_superadmin_roles').delete().eq('id', id);
    } catch (e) {
      throw Exception('Error eliminando rol: $e');
    }
  }

  Future<void> assignRoleToSuperAdmin(int superAdminId, int? roleId) async {
    try {
      await _supabase.from('app_dat_superadmin').update({
        'id_rol': roleId,
      }).eq('id', superAdminId);
    } catch (e) {
      throw Exception('Error asignando rol: $e');
    }
  }
}
