import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tipo_actividad.dart';

/// Taxonomía de servicios de Inventtia Flow (`flow.nom_tipo_actividad_servicio`).
///
/// Es la que usa el Home de la app del cliente para el riel de categorías y los
/// chips de subcategorías, y la que el admin de cada entidad asigna a sus
/// servicios. Aquí el superadmin la **gobierna entera**: crear, renombrar,
/// reordenar, activar/desactivar y borrar, en los dos niveles.
///
/// LECTURA: directo a la tabla. La política `nom_tipo_actividad_select_all` es
/// pública, así que no hace falta RPC ni uuid de usuario.
///
/// ESCRITURA: por RPC. Los mismos que usa el admin de entidad
/// (`admin_guardar_tipo_actividad`, `admin_alternar_tipo_actividad`,
/// `admin_eliminar_tipo_actividad`) pero autorizados por
/// `public.fn_is_superadmin_full_access()` dentro del servidor. La app no decide
/// permisos: solo los refleja.
class CategoriaAdminService {
  static final _supabase = Supabase.instance.client;
  static const String _schema = 'flow';
  static const String _tabla = 'nom_tipo_actividad_servicio';

  /// Columnas de la taxonomía de dos niveles (migración 47).
  static const String _columnas = 'id, codigo, nombre, activo, id_padre, orden';

  /// Columnas previas a la migración 47: sin jerarquía ni orden.
  static const String _columnasLegado = 'id, codigo, nombre, activo';

  /// Filas crudas. Si la migración 47 no está aplicada se reintenta sin
  /// `id_padre`/`orden` y la taxonomía se comporta como plana: es mejor una
  /// pantalla de consulta usable que un error de columna.
  static Future<List<Map<String, dynamic>>> listarMapas() async {
    Future<List<dynamic>> consulta(String columnas) async {
      return await _supabase
              .schema(_schema)
              .from(_tabla)
              .select(columnas)
              .order('nombre')
          as List<dynamic>;
    }

    List<dynamic> res;
    try {
      res = await consulta(_columnas);
    } catch (e) {
      if (!_esColumnaInexistente(e)) rethrow;
      res = await consulta(_columnasLegado);
    }

    return res
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
  }

  static Future<List<TipoActividad>> listar() async {
    final filas = await listarMapas();
    return filas.map(TipoActividad.fromJson).toList(growable: false);
  }

  static Future<Taxonomia> taxonomia() async => Taxonomia(await listar());

  /// Alta o edición. Devuelve el id del nodo guardado.
  ///
  /// [idPadre] se envía **siempre** (aunque sea `null`): el RPC lo usa para fijar
  /// el nivel, así que omitirlo convertiría una subcategoría en categoría al
  /// guardar un simple cambio de nombre.
  static Future<int> guardar({
    required String nombre,
    required String codigo,
    required bool activo,
    int? id,
    int? idPadre,
    int orden = 0,
  }) async {
    final params = <String, dynamic>{
      'p_codigo': codigo,
      'p_nombre': nombre,
      'p_activo': activo,
      'p_id_padre': idPadre,
      'p_orden': orden,
      if (id != null) 'p_id': id,
    };

    Map<String, dynamic> json;
    try {
      final res = await _supabase
          .schema(_schema)
          .rpc('admin_guardar_tipo_actividad', params: params);
      json = res is Map ? Map<String, dynamic>.from(res) : const {};
    } catch (e) {
      // Migración 47 sin aplicar: el RPC solo acepta 4 argumentos.
      if (!_esRpcSinParametrosNuevos(e)) rethrow;
      final res = await _supabase
          .schema(_schema)
          .rpc(
            'admin_guardar_tipo_actividad',
            params: {
              'p_codigo': codigo,
              'p_nombre': nombre,
              'p_activo': activo,
              if (id != null) 'p_id': id,
            },
          );
      json = res is Map ? Map<String, dynamic>.from(res) : const {};
    }

    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar');
    }
    return ((json['data'] as Map<String, dynamic>)['id'] as num).toInt();
  }

  /// Enciende o apaga un nodo. Apagar una categoría apaga sus subcategorías (lo
  /// hace el RPC): dejarlas encendidas las sacaría en un riel que ya no se ve.
  static Future<void> alternar({
    required int id,
    required bool activo,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .rpc(
            'admin_alternar_tipo_actividad',
            params: {'p_id': id, 'p_activo': activo},
          );
      final json = res is Map ? Map<String, dynamic>.from(res) : const {};
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'No se pudo cambiar el estado');
      }
    } catch (e) {
      // Migración 47 sin aplicar: se cae al guardado, que ya soporta cambiar
      // `activo` sin tocar el resto.
      if (!_esRpcSinParametrosNuevos(e)) rethrow;
      final actual = await porId(id);
      if (actual == null) throw Exception('Categoría inexistente');
      await guardar(
        id: actual.id,
        nombre: actual.nombre,
        codigo: actual.codigo,
        activo: activo,
        idPadre: actual.idPadre,
        orden: actual.orden,
      );
    }
  }

  static Future<TipoActividad?> porId(int id) async {
    final filas = await listarMapas();
    for (final fila in filas) {
      final nodo = TipoActividad.fromJson(fila);
      if (nodo.id == id) return nodo;
    }
    return null;
  }

  static Future<void> eliminar({required int id}) async {
    final res = await _supabase
        .schema(_schema)
        .rpc('admin_eliminar_tipo_actividad', params: {'p_id': id});
    final json = res is Map ? Map<String, dynamic>.from(res) : const {};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar');
    }
  }

  static bool _esColumnaInexistente(Object e) {
    final t = e.toString();
    return t.contains('42703') ||
        t.contains('PGRST204') ||
        t.contains('id_padre') ||
        t.contains('"orden"') ||
        (t.contains('column') && t.contains('does not exist'));
  }

  static bool _esRpcSinParametrosNuevos(Object e) {
    final t = e.toString();
    return t.contains('PGRST202') ||
        t.contains('Could not find the function') ||
        t.contains('schema cache') ||
        t.contains('p_id_padre') ||
        t.contains('p_orden');
  }
}
