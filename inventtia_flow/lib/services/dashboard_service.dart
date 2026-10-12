import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/dashboard_entidad.dart';

/// Datos del dashboard de la vista de Gestión (punto 1 del plan de mejoras).
///
/// Una sola RPC (`flow.admin_dashboard_entidad`) devuelve los cuatro totales, la
/// serie de reservas de los últimos [dias] días y el top de servicios. Se
/// calcula en la base de datos a propósito: traer las 125+ reservas al móvil
/// para contarlas en Dart sería más lento y más frágil.
class DashboardService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Devuelve el dashboard de [idEntidad] o `null` si la RPC contesta
  /// `ok: false` (entidad ajena al usuario).
  ///
  /// Lanza si hay un fallo de red o de permisos, para que la pantalla pueda
  /// distinguir "no hay datos" de "no se pudo consultar".
  static Future<DashboardEntidad?> obtener({
    required String uuidUsuario,
    required int idEntidad,
    int dias = 30,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_dashboard_entidad',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_entidad': idEntidad,
            'p_dias': dias,
          },
        );
    if (res is! Map<String, dynamic>) return null;
    if (res['ok'] != true) return null;
    return DashboardEntidad.fromJson(res);
  }
}
