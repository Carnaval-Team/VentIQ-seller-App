import 'package:supabase_flutter/supabase_flutter.dart';

/// Tipo de actividad de un servicio: `flow.nom_tipo_actividad_servicio`.
///
/// Es la categoría que el administrador asigna al crear un servicio y la que el
/// Home del cliente usa para su riel de categorías. `app_dat_servicios.
/// id_tipo_actividad` es NOT NULL, así que todo servicio tiene exactamente una.
class TipoActividad {
  const TipoActividad({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.activo = true,
  });

  final int id;

  /// Clave estable (`general`, `unas`, `transporte_omnibus`…). Viaja al cliente
  /// dentro de `cliente_obtener_servicios` y no debería cambiar tras crearse.
  final String codigo;

  final String nombre;
  final bool activo;

  factory TipoActividad.fromJson(Map<String, dynamic> json) => TipoActividad(
    id: (json['id'] as num).toInt(),
    codigo: json['codigo'] as String? ?? '',
    nombre: json['nombre'] as String? ?? '',
    activo: json['activo'] as bool? ?? true,
  );

  /// Código propuesto a partir del nombre: minúsculas, sin acentos y con `_`.
  ///
  /// Replica exactamente la normalización de `admin_guardar_tipo_actividad`
  /// (`translate` de acentos → `regexp_replace` de no alfanuméricos → `trim` de
  /// guiones bajos), para que lo que ve el usuario sea lo que se guarda.
  static String codigoDesdeNombre(String nombre) {
    const reemplazos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var valor = nombre.trim().toLowerCase();
    reemplazos.forEach((k, v) => valor = valor.replaceAll(k, v));
    valor = valor.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    valor = valor.replaceAll(RegExp(r'^_+|_+$'), '');
    return valor;
  }

  /// Mismo formato que valida `flow.admin_guardar_tipo_actividad`.
  static bool codigoValido(String codigo) =>
      RegExp(r'^[a-z0-9_]{3,64}$').hasMatch(codigo);
}

/// Lectura y gestión de categorías de servicio.
///
/// La lectura va directo a la tabla (RLS `nom_tipo_actividad_select_all` es
/// pública). La escritura pasa por RPC para validar el código y no permitir
/// borrar una categoría con servicios asociados.
///
/// Los RPC **no** reciben el uuid del usuario: la autorización la resuelve
/// `auth.uid()` en el servidor a partir del token de la sesión. Aun así hace
/// falta estar autenticado, así que las pantallas comprueban la sesión antes.
class TipoActividadService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Categorías disponibles. `soloActivos` filtra las desactivadas, que es lo
  /// que debe ver el cliente.
  static Future<List<TipoActividad>> listar({bool soloActivos = false}) async {
    var query = _supabase
        .schema(_schema)
        .from('nom_tipo_actividad_servicio')
        .select('id, codigo, nombre, activo');
    if (soloActivos) query = query.eq('activo', true);
    final res = await query.order('nombre');
    return (res as List)
        .map((e) => TipoActividad.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<int> guardar({
    required String nombre,
    required String codigo,
    required bool activo,
    int? id,
  }) async {
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
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar la categoría');
    }
    return ((json['data'] as Map<String, dynamic>)['id'] as num).toInt();
  }

  static Future<void> eliminar({required int id}) async {
    final res = await _supabase
        .schema(_schema)
        .rpc('admin_eliminar_tipo_actividad', params: {'p_id': id});
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar la categoría');
    }
  }
}
