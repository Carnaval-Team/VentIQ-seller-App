import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso del panel a `public.app_versiones`: versiones y changelogs de las 5
/// apps del ecosistema Inventtia.
///
/// **Escritura** por los RPC de la migración 75 (`fn_app_version_guardar` y
/// `fn_app_version_eliminar`), que validan en el servidor que quien llama es
/// superadmin y devuelven siempre `{ok, data | error}`.
///
/// **Lectura del panel** por PostgREST con `select('*')` sobre la tabla (es
/// pública de lectura) en vez de por `fn_app_versiones(app, limit)`: el panel
/// necesita ver también las versiones **inactivas** (`activa = false`) para
/// poder reactivarlas o corregirlas, y el RPC está pensado para la info que
/// consume la app. Así una sola consulta trae lo mismo que vería el panel más
/// el histórico completo. Si la tabla no tuviera los campos nuevos todavía
/// (migración 75 sin pegar), `select('*')` sigue funcionando y devuelve las
/// columnas antiguas.
class VersionesService {
  const VersionesService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Tabla de versiones en el schema `public`.
  static const String tabla = 'app_versiones';

  /// Cuántas versiones se traen por app en el historial del panel.
  static const int limiteHistorial = 60;

  /// Historial de una app, de la build más nueva a la más vieja.
  static Future<List<Map<String, dynamic>>> historial(
    String appName, {
    int limite = limiteHistorial,
  }) async {
    final filas = await _sb
        .from(tabla)
        .select('*')
        .eq('app_name', appName)
        .order('build_number', ascending: false)
        .limit(limite);
    return _listaDeMapas(filas);
  }

  /// Crea (`id` nulo) o actualiza una versión. En UPDATE, `null` conserva.
  ///
  /// [novedades]: se manda siempre como lista (array jsonb). Una lista vacía
  /// borra el changelog.
  /// [versionMinima]: **obligatoria al crear** (`version_minima` es NOT NULL en
  /// la tabla y el RPC responde `Falta la version minima (version_minima)` si se
  /// omite); en UPDATE `null` conserva la actual. El editor la exige y sugiere
  /// la versión nueva mientras el superadmin no escriba una propia.
  /// [obligatoria] y [activa] se mandan siempre desde el editor.
  /// [urlDescarga]: cadena vacía quita la URL; `null` conserva la actual.
  /// [titulo]: cadena vacía quita el título; `null` conserva.
  ///
  /// Devuelve el `data` del RPC, que trae `id` y `creado`. Hoy (migración 75)
  /// guardar **no** manda `aviso`: la pantalla lo lee de forma tolerante por si
  /// el servidor lo añade en el futuro; el único `aviso` real de versiones es el
  /// de [eliminar] al borrar la última versión activa.
  static Future<Map<String, dynamic>> guardar({
    int? id,
    required String appName,
    required String versionActual,
    required int buildNumber,
    String? versionMinima,
    bool? obligatoria,
    String? titulo,
    List<NovedadVersion>? novedades,
    String? urlDescarga,
    bool? activa,
  }) async {
    final data = await _rpc(
      'fn_app_version_guardar',
      params: {
        'p_id': id,
        'p_app_name': appName,
        'p_version_actual': versionActual,
        'p_build_number': buildNumber,
        'p_version_minima': versionMinima,
        'p_obligatoria': obligatoria,
        'p_titulo': titulo,
        'p_novedades':
            novedades == null
                ? null
                : [for (final novedad in novedades) novedad.aJson()],
        'p_url_descarga': urlDescarga,
        'p_activa': activa,
      },
    );
    return _mapaDe(data);
  }

  /// Borra una versión. El servidor puede negarse y devolver `aviso` (p. ej. si
  /// era la última versión activa de la app).
  static Future<Map<String, dynamic>> eliminar(int id) async {
    final data = await _rpc('fn_app_version_eliminar', params: {'p_id': id});
    return _mapaDe(data);
  }

  // ── Utilidades ───────────────────────────────────────────────────────────

  /// Llama a un RPC `{ok, data | error}` del schema `public` y devuelve `data`.
  static Future<dynamic> _rpc(
    String funcion, {
    Map<String, dynamic>? params,
  }) async {
    final res = await _sb.rpc(funcion, params: params);
    if (res is! Map) {
      throw const VersionesException('Respuesta inesperada del servidor');
    }
    final mapa = Map<String, dynamic>.from(res);
    if (mapa['ok'] == false) {
      throw VersionesException(
        mapa['error'] as String? ?? 'La operación no se pudo completar',
      );
    }
    return mapa['data'];
  }

  static Map<String, dynamic> _mapaDe(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _listaDeMapas(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}

/// Error de un RPC de versiones con el mensaje que redactó el servidor.
class VersionesException implements Exception {
  const VersionesException(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Un cambio del changelog de una versión.
///
/// Se serializa como `{"type":"feature|improvement|fix","title":"...","description":"..."}`,
/// que es el formato que consume la app para pintar "Novedades".
class NovedadVersion {
  const NovedadVersion({
    required this.tipo,
    required this.titulo,
    this.descripcion = '',
  });

  /// Nueva funcionalidad.
  static const String tipoNovedad = 'feature';

  /// Mejora de algo existente.
  static const String tipoMejora = 'improvement';

  /// Corrección de un fallo.
  static const String tipoCorreccion = 'fix';

  /// Tipos válidos del contrato (en orden de presentación).
  static const List<String> tipos = [tipoNovedad, tipoMejora, tipoCorreccion];

  final String tipo;
  final String titulo;
  final String descripcion;

  /// Lee una novedad de un mapa jsonb, tolerante a campos ausentes o tipos raros.
  static NovedadVersion desdeJson(dynamic json) {
    if (json is! Map) {
      return const NovedadVersion(tipo: tipoNovedad, titulo: '');
    }
    final tipoCrudo = (json['type'] as String?)?.trim().toLowerCase() ?? '';
    return NovedadVersion(
      tipo: tipos.contains(tipoCrudo) ? tipoCrudo : tipoNovedad,
      titulo: (json['title'] as String?)?.trim() ?? '',
      descripcion: (json['description'] as String?)?.trim() ?? '',
    );
  }

  /// Lee la lista completa de novedades, aceptando lista o texto JSON.
  static List<NovedadVersion> listaDesde(dynamic raw) {
    dynamic valor = raw;
    if (valor is String && valor.trim().isNotEmpty) {
      try {
        valor = jsonDecode(valor);
      } catch (_) {
        return const [];
      }
    }
    if (valor is! List) return const [];

    final salida = <NovedadVersion>[];
    for (final item in valor) {
      if (item is! Map) continue;
      final novedad = desdeJson(item);
      // Una novedad sin título no se puede pintar en la app: se descarta.
      if (novedad.titulo.isEmpty) continue;
      salida.add(novedad);
    }
    return salida;
  }

  Map<String, dynamic> aJson() => <String, dynamic>{
    'type': tipo,
    'title': titulo,
    'description': descripcion,
  };

  NovedadVersion copyWith({String? tipo, String? titulo, String? descripcion}) {
    return NovedadVersion(
      tipo: tipo ?? this.tipo,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
    );
  }
}
