import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de negocio de documentos legales / consentimientos.
class MueveteLegalException implements Exception {
  final String mensaje;

  const MueveteLegalException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Resumen «X de Y usuarios aceptaron la v1.1.0» para un documento.
class AceptacionDocumento {
  final String codigo;
  final String titulo;
  final String version;
  final int aceptaron;
  final int totalUsuarios;
  final bool obligatorio;
  final bool publicado;

  const AceptacionDocumento({
    required this.codigo,
    required this.titulo,
    required this.version,
    required this.aceptaron,
    required this.totalUsuarios,
    required this.obligatorio,
    required this.publicado,
  });

  double get porcentaje =>
      totalUsuarios <= 0 ? 0 : (aceptaron * 100 / totalUsuarios);
}

/// Documentos legales versionados y auditoría de consentimientos (H1).
///
/// Reglas que esta capa respeta y que la pantalla sólo refleja:
/// * El `hash_contenido` lo recalcula **siempre** el trigger
///   `muevete.trg_documentos_legales_hash` con
///   `encode(digest(contenido_md, 'sha256'), 'hex')`. Aquí se calcula el mismo
///   valor con `crypto` para poder mostrarlo antes de guardar y para verificar
///   la integridad de lo ya publicado. `fn_doc_legal_hash()` no está expuesta
///   por RPC (es una función de trigger), así que el cálculo local es la única
///   vía para previsualizar y auditar.
/// * El texto publicado es inmutable: cambiarlo exige **versión nueva**, y eso
///   obliga a todos los usuarios a re-aceptar.
/// * `consentimientos` es evidencia: la consola **lee**, nunca edita ni borra.
class MueveteDocumentosService {
  static final _supabase = Supabase.instance.client;

  /// Filas por página en la auditoría.
  static const int filasPorPagina = 20;

  /// Tope duro al contar usuarios/aceptaciones de un documento.
  static const int topeAgregado = 5000;

  /// Códigos conocidos del seed (la tabla no limita `codigo` con un CHECK, así
  /// que la lista es sólo para etiquetar; los códigos reales manda la BD).
  static const Map<String, String> etiquetasCodigo = {
    'privacidad': 'Política de Privacidad',
    'terminos': 'Términos y Condiciones',
    'kyc': 'Consentimiento de verificación de identidad',
    'consentimiento_datos': 'Consentimiento de datos personales',
    'consentimiento_geolocalizacion': 'Consentimiento de geolocalización',
    'consentimiento_identidad': 'Consentimiento de identidad',
    'consentimiento_contactos_emergencia':
        'Consentimiento de contactos de emergencia',
  };

  // ─── Hash ─────────────────────────────────────────────────────────────

  /// SHA-256 en hexadecimal minúsculas de los bytes UTF-8 del texto.
  ///
  /// Es exactamente lo que calcula `muevete.fn_doc_legal_hash()` en Postgres
  /// (`encode(digest(coalesce(contenido_md, ''), 'sha256'), 'hex')`).
  static String calcularHash(String contenidoMd) =>
      sha256.convert(utf8.encode(contenidoMd)).toString();

  /// `true` cuando el hash guardado coincide con el texto guardado.
  static bool hashCoincide(Map<String, dynamic> documento) {
    final guardado = (documento['hash_contenido'] as String?)?.trim() ?? '';
    final texto = (documento['contenido_md'] as String?) ?? '';
    if (guardado.isEmpty) return false;
    return guardado == calcularHash(texto);
  }

  // ─── Documentos ───────────────────────────────────────────────────────

  /// Todos los documentos (borradores incluidos), del más nuevo al más viejo.
  static Future<List<Map<String, dynamic>>> listarDocumentos() {
    return _guard('No se pudieron cargar los documentos legales', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .select()
          .order('codigo', ascending: true)
          .order('vigente_desde', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  /// Guarda el texto de un documento.
  ///
  /// El trigger de la base de datos recalcula `hash_contenido` al vuelo; se
  /// devuelve la fila resultante para comprobar que el hash calculado aquí y
  /// el guardado coinciden (si no, es un incidente de integridad).
  static Future<Map<String, dynamic>> guardarContenido(
    int id, {
    required String contenidoMd,
    String? titulo,
  }) {
    final texto = contenidoMd;
    if (texto.trim().isEmpty) {
      throw const MueveteLegalException(
        'El contenido del documento no puede quedar vacío.',
      );
    }
    final cambios = <String, dynamic>{
      'contenido_md': texto,
      'hash_contenido': calcularHash(texto),
    };
    if (titulo != null && titulo.trim().isNotEmpty) {
      cambios['titulo'] = titulo.trim();
    }

    return _guard('No se pudo guardar el documento legal', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .update(cambios)
          .eq('id', id)
          .select();
      if ((rows as List).isEmpty) {
        throw const MueveteLegalException(
          'El documento ya no existe o no tienes permisos para editarlo.',
        );
      }
      return Map<String, dynamic>.from(rows.first as Map);
    });
  }

  /// Publica una versión y cierra la anterior (histórico, nunca se borra).
  ///
  /// Orden obligatorio por el índice único parcial
  /// `documentos_legales_vigente_uidx (codigo) WHERE publicado AND
  /// vigente_hasta IS NULL`: primero se cierra lo abierto, después se publica.
  static Future<void> publicar(int id) {
    return _guard('No se pudo publicar la versión', () async {
      final fila =
          await _supabase
              .schema('muevete')
              .from('documentos_legales')
              .select('id, codigo, publicado')
              .eq('id', id)
              .maybeSingle();
      if (fila == null) {
        throw const MueveteLegalException('El documento ya no existe.');
      }
      final codigo = fila['codigo'] as String;
      final ahora = DateTime.now().toUtc();

      final abiertas = await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .select('id, vigente_desde')
          .eq('codigo', codigo)
          .isFilter('vigente_hasta', null);

      for (final otra in List<Map<String, dynamic>>.from(abiertas)) {
        if ((otra['id'] as num).toInt() == id) continue;
        final desde = DateTime.tryParse('${otra['vigente_desde']}')?.toUtc();
        // `documentos_legales_vigencia_chk` exige vigente_hasta > vigente_desde.
        final hasta =
            (desde == null || ahora.isAfter(desde))
                ? ahora
                : desde.add(const Duration(seconds: 1));
        await _supabase
            .schema('muevete')
            .from('documentos_legales')
            .update({'vigente_hasta': hasta.toIso8601String()})
            .eq('id', (otra['id'] as num).toInt());
      }

      final filas = await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .update({
            'publicado': true,
            'vigente_desde': ahora.toIso8601String(),
            // Se reabre la vigencia: un borrador pudo quedar cerrado al
            // publicar otra versión, y `vigente_hasta > vigente_desde` es un
            // CHECK de la tabla.
            'vigente_hasta': null,
          })
          .eq('id', id)
          .select('id');
      if ((filas as List).isEmpty) {
        throw const MueveteLegalException(
          'No tienes permisos de superadministrador para publicar.',
        );
      }
    });
  }

  /// Quita un documento de la circulación sin borrarlo.
  static Future<void> despublicar(int id) {
    return _guard('No se pudo despublicar la versión', () async {
      final filas = await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .update({'publicado': false})
          .eq('id', id)
          .select('id');
      if ((filas as List).isEmpty) {
        throw const MueveteLegalException(
          'No tienes permisos de superadministrador para despublicar.',
        );
      }
    });
  }

  /// Crea una versión nueva copiando el texto de la actual.
  ///
  /// Nace como **borrador** (`publicado = false`) para que publicarla sea un
  /// acto explícito y consciente: publicar obliga a re-aceptar.
  static Future<void> crearNuevaVersion({
    required Map<String, dynamic> base,
    required String versionNueva,
    String? titulo,
    String? contenidoMd,
    bool? esObligatorio,
  }) {
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(versionNueva.trim())) {
      throw const MueveteLegalException(
        'La versión debe tener el formato x.y.z (por ejemplo 1.1.0).',
      );
    }
    final texto =
        contenidoMd ?? (base['contenido_md'] as String?) ?? '';
    if (texto.trim().isEmpty) {
      throw const MueveteLegalException(
        'El contenido del documento no puede quedar vacío.',
      );
    }
    final codigo = base['codigo'] as String;
    final ahora = DateTime.now().toUtc();

    final payload = <String, dynamic>{
      'codigo': codigo,
      'version': versionNueva.trim(),
      'titulo':
          (titulo ?? (base['titulo'] as String?) ?? codigo).trim(),
      'resumen': base['resumen'],
      'contenido_md': texto,
      'es_obligatorio': esObligatorio ?? (base['es_obligatorio'] ?? true),
      'publicado': false,
      'vigente_desde': ahora.toIso8601String(),
      'hash_contenido': calcularHash(texto),
      'created_by': _supabase.auth.currentUser?.id,
    };

    return _guard('No se pudo crear la versión nueva', () async {
      final existe = await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .select('id')
          .eq('codigo', codigo)
          .eq('version', versionNueva.trim())
          .maybeSingle();
      if (existe != null) {
        throw MueveteLegalException(
          'La versión ${versionNueva.trim()} de «$codigo» ya existe. Sube el '
          'número antes de crearla.',
        );
      }
      await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .insert(payload);
    });
  }

  /// `1.0.0` → `1.0.1`; si no se puede interpretar, devuelve `1.0.0`.
  static String siguienteVersion(String? actual) {
    final partes = (actual ?? '').trim().split('.');
    if (partes.length != 3) return '1.0.0';
    final mayor = int.tryParse(partes[0]);
    final menor = int.tryParse(partes[1]);
    final parche = int.tryParse(partes[2]);
    if (mayor == null || menor == null || parche == null) return '1.0.0';
    return '$mayor.$menor.${parche + 1}';
  }

  /// Etiqueta legible para un código, con respaldo al `titulo` de la fila.
  static String etiquetaCodigo(String? codigo, [String? titulo]) {
    final c = (codigo ?? '').trim();
    if (c.isEmpty) return (titulo ?? 'Documento').trim();
    return etiquetasCodigo[c] ?? (titulo ?? c);
  }

  // ─── Auditoría de consentimientos ─────────────────────────────────────

  /// Página de `consentimientos` con filtros opcionales.
  ///
  /// Pide una fila de más para saber si hay página siguiente sin depender del
  /// conteo exacto de PostgREST.
  static Future<List<Map<String, dynamic>>> listarConsentimientos({
    String? codigo,
    DateTime? desde,
    DateTime? hasta,
    bool? aceptado,
    int page = 0,
    int filas = filasPorPagina,
  }) {
    return _guard('No se pudieron cargar los consentimientos', () async {
      var query = _supabase.schema('muevete').from('consentimientos').select();
      if (codigo != null && codigo.isNotEmpty) {
        query = query.eq('documento_codigo', codigo);
      }
      if (desde != null) {
        query = query.gte('aceptado_at', desde.toUtc().toIso8601String());
      }
      if (hasta != null) {
        query = query.lte('aceptado_at', hasta.toUtc().toIso8601String());
      }
      if (aceptado != null) {
        query = query.eq('aceptado', aceptado);
      }
      final desdeFila = page * filas;
      final rows = await query
          .order('aceptado_at', ascending: false)
          .range(desdeFila, desdeFila + filas);
      return List<Map<String, dynamic>>.from(rows);
    });
  }

  /// Nombres y contactos de los usuarios de una página de consentimientos.
  ///
  /// No hay FK de `consentimientos.user_uuid` hacia `muevete.users` (apunta a
  /// `auth.users`), así que el join se resuelve aquí.
  static Future<Map<String, Map<String, dynamic>>> usuariosPorUuid(
    Iterable<String> uuids,
  ) {
    final lista = uuids.where((u) => u.isNotEmpty).toSet().toList();
    if (lista.isEmpty) return Future.value({});
    return _guard('No se pudieron resolver los usuarios', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('users')
          .select('uuid, name, email, phone')
          .inFilter('uuid', lista);
      final mapa = <String, Map<String, dynamic>>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        mapa['${r['uuid']}'] = r;
      }
      return mapa;
    });
  }

  /// Total de usuarios registrados (denominador de «X de Y»).
  static Future<int> contarUsuarios() {
    return _guard('No se pudo contar los usuarios', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('users')
          .select('uuid')
          .limit(topeAgregado);
      return (rows as List).length;
    });
  }

  /// Cuántos usuarios distintos aceptaron cada versión de un documento.
  static Future<Map<String, int>> aceptacionesPorVersion(
    String codigo,
  ) {
    return _guard('No se pudieron contar las aceptaciones', () async {
      final rows = await _supabase
          .schema('muevete')
          .from('consentimientos')
          .select('documento_version, user_uuid')
          .eq('documento_codigo', codigo)
          .eq('aceptado', true)
          .limit(topeAgregado);
      final porVersion = <String, Set<String>>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final v = '${r['documento_version']}';
        porVersion.putIfAbsent(v, () => <String>{}).add('${r['user_uuid']}');
      }
      return porVersion.map((k, v) => MapEntry(k, v.length));
    });
  }

  /// Resumen de aceptación de la versión vigente de cada documento.
  static Future<List<AceptacionDocumento>> resumenAceptacion(
    List<Map<String, dynamic>> documentos,
  ) async {
    final totalUsuarios = await contarUsuarios();
    // Sólo la versión más reciente de cada código (la que exige re-aceptar).
    final vigentes = <String, Map<String, dynamic>>{};
    for (final d in documentos) {
      final codigo = '${d['codigo']}';
      final previo = vigentes[codigo];
      if (previo == null ||
          _compararVersiones('${d['version']}', '${previo['version']}') > 0) {
        vigentes[codigo] = d;
      }
    }
    final resumen = <AceptacionDocumento>[];
    for (final d in vigentes.values) {
      final codigo = '${d['codigo']}';
      final version = '${d['version']}';
      final porVersion = await aceptacionesPorVersion(codigo);
      resumen.add(
        AceptacionDocumento(
          codigo: codigo,
          titulo: etiquetaCodigo(codigo, d['titulo'] as String?),
          version: version,
          aceptaron: porVersion[version] ?? 0,
          totalUsuarios: totalUsuarios,
          obligatorio: d['es_obligatorio'] == true,
          publicado: d['publicado'] == true,
        ),
      );
    }
    resumen.sort((a, b) => a.codigo.compareTo(b.codigo));
    return resumen;
  }

  static int _compararVersiones(String a, String b) {
    List<int> parse(String v) {
      final p = v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      while (p.length < 3) {
        p.add(0);
      }
      return p;
    }

    final va = parse(a);
    final vb = parse(b);
    for (var i = 0; i < 3; i++) {
      if (va[i] != vb[i]) return va[i].compareTo(vb[i]);
    }
    return 0;
  }

  // ─── Infraestructura de errores ───────────────────────────────────────

  static Future<T> _guard<T>(String accion, Future<T> Function() cuerpo) async {
    try {
      return await cuerpo();
    } on MueveteLegalException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
        '[MueveteDocumentosService] $accion · code=${e.code} message=${e.message}',
      );
      throw MueveteLegalException('$accion: ${_detalle(e)}.');
    } on AuthException catch (e) {
      debugPrint('[MueveteDocumentosService] $accion · auth=${e.message}');
      throw const MueveteLegalException(
        'La sesión expiró o no es válida. Vuelve a iniciar sesión.',
      );
    } catch (e) {
      debugPrint('[MueveteDocumentosService] $accion · $e');
      throw MueveteLegalException('$accion: $e');
    }
  }

  static String _detalle(PostgrestException e) {
    switch (e.code) {
      case '42501':
        return 'no tienes permisos de superadministrador';
      case '23505':
        return 'ya existe esa versión del documento';
      case '23514':
        return 'los valores están fuera del rango permitido por la base de datos';
      case '23503':
        return 'hay registros relacionados que impiden la operación';
      case '42P01':
        return 'la tabla no existe en el esquema muevete';
      default:
        return e.message;
    }
  }
}