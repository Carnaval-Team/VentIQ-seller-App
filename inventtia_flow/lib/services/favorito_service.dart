import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/servicio.dart';

/// Servicio favorito de un cliente: fila de `flow.favorito`.
///
/// La clave primaria es compuesta `(uuid_usuario, id_local_servicio)`, así que
/// guardar el mismo favorito dos veces no duplica y no hace falta consultar
/// antes de insertar.
class Favorito {
  const Favorito({
    required this.uuidUsuario,
    required this.idLocalServicio,
    this.createdAt,
  });

  final String uuidUsuario;
  final int idLocalServicio;
  final DateTime? createdAt;

  factory Favorito.fromJson(Map<String, dynamic> json) => Favorito(
    uuidUsuario: json['uuid_usuario'] as String,
    idLocalServicio: (json['id_local_servicio'] as num).toInt(),
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
  );
}

/// Favoritos del cliente contra `flow.favorito`.
///
/// RLS por `auth.uid()`: estas consultas solo pueden devolver y modificar las
/// filas del usuario con la sesión abierta. El `uuid_usuario` se envía igual
/// porque la tabla tiene esa columna, pero la base **rechaza** cualquier fila que
/// no sea del usuario autenticado (la política tiene `with check`).
///
/// A diferencia de "Mis Listas" —que es la **sala de espera** (`flow.sala_espera`)
/// y dura lo que dura la cola—, un favorito es permanente.
class FavoritoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Ids de `local_servicio` que el usuario tiene guardados.
  ///
  /// Es lo que necesita el Home para pintar los corazones sin traerse las filas
  /// completas ni hacer una consulta por tarjeta.
  static Future<Set<int>> getIdsFavoritos(String uuidUsuario) async {
    final res = await _supabase
        .schema(_schema)
        .from('favorito')
        .select('id_local_servicio')
        .eq('uuid_usuario', uuidUsuario);
    return (res as List)
        .map((e) => (e['id_local_servicio'] as num).toInt())
        .toSet();
  }

  /// Lista completa, más recientes primero. Para la pantalla de favoritos.
  static Future<List<Favorito>> getFavoritos(String uuidUsuario) async {
    final res = await _supabase
        .schema(_schema)
        .from('favorito')
        .select('uuid_usuario, id_local_servicio, created_at')
        .eq('uuid_usuario', uuidUsuario)
        .order('created_at', ascending: false);
    return (res as List)
        .map((e) => Favorito.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Favoritos con el local y el servicio ya resueltos.
  ///
  /// Una sola consulta con el join de PostgREST (`favorito.id_local_servicio →
  /// local_servicio.id`), en vez de pedir el detalle uno por uno desde la
  /// pantalla. El orden lo fija `favorito.created_at`, no el de `local_servicio`.
  static Future<List<LocalServicio>> getLocalServiciosFavoritos(
    String uuidUsuario,
  ) async {
    final res = await _supabase
        .schema(_schema)
        .from('favorito')
        .select(
          'created_at, local_servicio(*, app_dat_locales(*), '
          'app_dat_servicios(*, tipo_actividad:nom_tipo_actividad_servicio(*)))',
        )
        .eq('uuid_usuario', uuidUsuario)
        .order('created_at', ascending: false);

    return (res as List)
        .where((e) => (e as Map)['local_servicio'] != null)
        .map(
          (e) => LocalServicio.fromJson(
            Map<String, dynamic>.from(e['local_servicio'] as Map),
          ),
        )
        .toList();
  }

  /// Guarda un favorito. Idempotente.
  static Future<void> guardar({
    required String uuidUsuario,
    required int idLocalServicio,
  }) async {
    await _supabase
        .schema(_schema)
        .from('favorito')
        .upsert(
          {'uuid_usuario': uuidUsuario, 'id_local_servicio': idLocalServicio},
          onConflict: 'uuid_usuario,id_local_servicio',
          ignoreDuplicates: true,
        );
  }

  /// Quita un favorito.
  static Future<void> quitar({
    required String uuidUsuario,
    required int idLocalServicio,
  }) async {
    await _supabase
        .schema(_schema)
        .from('favorito')
        .delete()
        .eq('uuid_usuario', uuidUsuario)
        .eq('id_local_servicio', idLocalServicio);
  }

  /// Alterna y devuelve el estado resultante (`true` = quedó guardado).
  static Future<bool> alternar({
    required String uuidUsuario,
    required int idLocalServicio,
    required bool estaGuardado,
  }) async {
    if (estaGuardado) {
      await quitar(uuidUsuario: uuidUsuario, idLocalServicio: idLocalServicio);
      return false;
    }
    await guardar(uuidUsuario: uuidUsuario, idLocalServicio: idLocalServicio);
    return true;
  }
}
