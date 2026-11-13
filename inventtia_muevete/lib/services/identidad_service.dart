import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_error.dart';

/// Convierte un array jsonb (`["a","b"]`) en `List<String>`.
///
/// Los `faltantes`/`motivos` del servidor son arrays de texto; si llegara algo
/// raro (null, números) se normaliza a texto y se descartan los vacíos para no
/// romper las comparaciones de la UI.
List<String> _lista(Object? value) {
  if (value is List) {
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

/// Versión de la app que se registra en cada consentimiento (auditoría legal).
const String kAppVersion = '1.0.0';

/// `User-Agent` que viaja con el consentimiento. El servidor guarda además su
/// propia IP y su propio user-agent: esto es sólo el dato del cliente.
String get kUserAgent {
  if (kIsWeb) return 'muevete-web/$kAppVersion';
  return 'muevete-${defaultTargetPlatform.name}/$kAppVersion';
}

/// Paso del flujo de habilitación que le falta al usuario.
///
/// El orden es el del producto: primero identidad, después consentimiento y
/// por último el contacto de emergencia. `listo` significa que puede operar.
enum PasoSeguridad { listo, identidad, consentimiento, contactos, bloqueado }

/// Documento legal publicado (`muevete.documentos_legales`).
class DocumentoLegal {
  final String codigo;
  final String version;
  final String titulo;
  final String? resumen;
  final String contenidoMd;
  final bool obligatorio;

  const DocumentoLegal({
    required this.codigo,
    required this.version,
    required this.titulo,
    required this.contenidoMd,
    this.resumen,
    this.obligatorio = true,
  });

  factory DocumentoLegal.fromJson(Map<String, dynamic> json) {
    return DocumentoLegal(
      codigo: (json['codigo'] ?? '').toString(),
      version: (json['version'] ?? '').toString(),
      titulo: (json['titulo'] ?? '').toString(),
      resumen: json['resumen']?.toString(),
      contenidoMd: (json['contenido_md'] ?? '').toString(),
      obligatorio:
          json['es_obligatorio'] != false && json['obligatorio'] != false,
    );
  }

  /// Clave que devuelve `fn_usuario_habilitado` en `consentimiento.faltantes`.
  String get clave => '$codigo@$version';
}

/// Documento pendiente de aceptar, extraído de `codigo@version`.
class DocumentoPendiente {
  final String codigo;
  final String version;

  const DocumentoPendiente(this.codigo, this.version);

  /// Clave con el formato que usa el servidor en `consentimiento.faltantes`:
  /// `codigo@version`. La usan las pantallas para comparar contra los documentos.
  String get clave => version.isEmpty ? codigo : '$codigo@$version';

  static DocumentoPendiente? parsear(String clave) {
    final partes = clave.split('@');
    if (partes.isEmpty || partes.first.trim().isEmpty) return null;
    return DocumentoPendiente(
      partes.first.trim(),
      partes.length > 1 ? partes[1].trim() : '',
    );
  }

  @override
  String toString() => clave;
}

/// Estado del perfil dentro del gate.
class EstadoPerfilIdentidad {
  final bool ok;
  final List<String> faltantes;
  final String? kycEstado;

  const EstadoPerfilIdentidad({
    required this.ok,
    required this.faltantes,
    this.kycEstado,
  });
}

/// Estado de los consentimientos obligatorios.
class EstadoConsentimiento {
  final bool ok;
  final List<DocumentoPendiente> faltantes;

  const EstadoConsentimiento({required this.ok, required this.faltantes});
}

/// Resultado completo de `muevete.fn_usuario_habilitado`.
class EstadoIdentidad {
  final bool habilitado;
  final String? rol;
  final EstadoPerfilIdentidad perfil;
  final EstadoConsentimiento consentimiento;
  final List<String> motivos;
  final String? mensaje;
  final bool operarPermitido;
  final bool kycObligatorio;
  final bool consentimientoObligatorio;

  const EstadoIdentidad({
    required this.habilitado,
    required this.rol,
    required this.perfil,
    required this.consentimiento,
    required this.motivos,
    required this.operarPermitido,
    this.mensaje,
    this.kycObligatorio = false,
    this.consentimientoObligatorio = false,
  });

  static const EstadoIdentidad desconocido = EstadoIdentidad(
    habilitado: false,
    rol: null,
    perfil: EstadoPerfilIdentidad(ok: false, faltantes: []),
    consentimiento: EstadoConsentimiento(ok: true, faltantes: []),
    motivos: [],
    operarPermitido: false,
  );

  factory EstadoIdentidad.fromJson(Map<String, dynamic> json) {
    final perfil = json['perfil'];
    final consentimiento = json['consentimiento'];

    return EstadoIdentidad(
      habilitado: json['habilitado'] == true,
      rol: json['rol']?.toString(),
      perfil: perfil is Map
          ? EstadoPerfilIdentidad(
              ok: perfil['ok'] == true,
              faltantes: _lista(perfil['faltantes']),
              kycEstado: perfil['kyc_estado']?.toString(),
            )
          : const EstadoPerfilIdentidad(ok: false, faltantes: []),
      consentimiento: consentimiento is Map
          ? EstadoConsentimiento(
              ok: consentimiento['ok'] == true,
              faltantes: _lista(consentimiento['faltantes'])
                  .map(DocumentoPendiente.parsear)
                  .whereType<DocumentoPendiente>()
                  .toList(),
            )
          : const EstadoConsentimiento(ok: true, faltantes: []),
      motivos: _lista(json['motivos']),
      mensaje: json['mensaje']?.toString(),
      operarPermitido: json['operar_permitido'] == true,
      kycObligatorio: json['kyc_obligatorio'] == true,
      consentimientoObligatorio: json['consentimiento_obligatorio'] == true,
    );
  }

  /// Paso que toca ahora (el orden manda: identidad → consentimiento → contactos).
  PasoSeguridad get siguientePaso {
    if (motivos.contains('bloqueado')) return PasoSeguridad.bloqueado;
    if (!perfil.ok) return PasoSeguridad.identidad;
    if (!consentimiento.ok) return PasoSeguridad.consentimiento;
    return PasoSeguridad.listo;
  }
}

/// Resultado de `muevete.fn_gate_seguridad`.
class EstadoGateSeguridad {
  final bool ok;
  final List<String> motivos;
  final bool contactoVerificado;
  final DateTime? bloqueadoHasta;
  final String? motivoBloqueoPublico;

  const EstadoGateSeguridad({
    required this.ok,
    required this.motivos,
    required this.contactoVerificado,
    this.bloqueadoHasta,
    this.motivoBloqueoPublico,
  });

  factory EstadoGateSeguridad.fromJson(Map<String, dynamic> json) {
    return EstadoGateSeguridad(
      ok: json['ok'] == true,
      motivos: _lista(json['motivos']),
      contactoVerificado: json['contacto_verificado'] == true,
      bloqueadoHasta: DateTime.tryParse(
        (json['bloqueado_hasta'] ?? '').toString(),
      ),
      motivoBloqueoPublico:
          json['bloqueo_motivo_publico']?.toString() ??
          json['motivo_bloqueo_publico']?.toString(),
    );
  }
}

/// Error propio del dominio: mensaje ya en español y clave estable.
class IdentidadException implements Exception {
  final String mensaje;
  final String? clave;

  const IdentidadException(this.mensaje, {this.clave});

  @override
  String toString() => mensaje;
}

/// Acceso a las RPC de identidad, consentimiento y gate.
///
/// Contrato: `docs/plan-taxi-precio-fijo/13-contrato-app-rpc.md` (§4) y
/// `docs/migrations/036_taxi_identidad_consentimiento.sql`. Todas las RPC son
/// `SECURITY DEFINER`: el cliente sólo manda datos, nunca el veredicto.
class IdentidadService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// `uuid` de la sesión actual, o `null` si no hay sesión.
  static String? get uidActual => Supabase.instance.client.auth.currentUser?.id;

  // ── Gate de habilitación ────────────────────────────────────────────────

  /// `fn_usuario_habilitado(p_uuid, p_rol)`. Sin `p_rol` el servidor
  /// autodetecta el rol (chofer si existe fila en `drivers`).
  Future<EstadoIdentidad> estado({String? rol}) async {
    final res = await _rpc(
      'fn_usuario_habilitado',
      params: {if (rol != null && rol.trim().isNotEmpty) 'p_rol': rol.trim()},
      accion: 'consultar el estado del perfil',
    );
    final map = _asMap(res);
    if (map.isEmpty) return EstadoIdentidad.desconocido;
    return EstadoIdentidad.fromJson(map);
  }

  /// Igual que [estado] pero para un rol concreto.
  Future<EstadoIdentidad> habilitadoPara(String rol) => estado(rol: rol);

  /// `fn_gate_seguridad(p_user_uuid, p_driver_id)`.
  Future<EstadoGateSeguridad> gateSeguridad({
    required String userUuid,
    int? driverId,
  }) async {
    final res = await _rpc(
      'fn_gate_seguridad',
      params: {'p_user_uuid': userUuid, 'p_driver_id': driverId},
      accion: 'verificar los requisitos de seguridad',
    );
    final map = _asMap(res);
    if (map.isEmpty) {
      return const EstadoGateSeguridad(
        ok: false,
        motivos: ['sin_contacto_emergencia'],
        contactoVerificado: false,
      );
    }
    return EstadoGateSeguridad.fromJson(map);
  }

  // ── Identidad ───────────────────────────────────────────────────────────

  /// `fn_guardar_identidad(p_rol, p_datos)`. Sólo se envían los campos con
  /// valor: el servidor hace `coalesce(campo, valor_actual)`.
  Future<EstadoIdentidad> guardarIdentidad({
    required String rol,
    String? ci,
    String? poblado,
    String? direccion,
    String? provincia,
    String? municipio,
    String? tipoDocumento,
    String? docFrenteUrl,
    String? docDorsoUrl,
    String? nombre,
    String? telefono,
  }) async {
    final datos = <String, dynamic>{};

    void put(String key, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) datos[key] = v;
    }

    put('ci', ci);
    put('poblado', poblado);
    put('direccion', direccion);
    put('province', provincia);
    put('municipality', municipio);
    put('tipo_documento', tipoDocumento);
    put('doc_frente_url', docFrenteUrl);
    put('doc_dorso_url', docDorsoUrl);
    put('name', nombre);
    put('telefono', telefono);

    if (datos.isEmpty) {
      throw const IdentidadException('No hay datos nuevos que guardar');
    }

    final res = await _rpc(
      'fn_guardar_identidad',
      params: {'p_rol': rol, 'p_datos': datos},
      accion: 'guardar tu identidad',
    );
    final map = _asMap(res);
    final gate = map['gate'];
    if (gate is Map) {
      return EstadoIdentidad.fromJson(Map<String, dynamic>.from(gate));
    }
    return estado(rol: rol);
  }

  /// Valida el formato cubano de CI igual que `muevete.fn_ci_valido`:
  /// 11 dígitos con mes 01-12 y día 01-31 en las posiciones 3-4 y 5-6.
  static bool ciValido(String? ci) {
    final v = (ci ?? '').replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[0-9]{11}$').hasMatch(v)) return false;
    final mes = int.tryParse(v.substring(2, 4)) ?? 0;
    final dia = int.tryParse(v.substring(4, 6)) ?? 0;
    if (mes < 1 || mes > 12) return false;
    if (dia < 1 || dia > 31) return false;
    return true;
  }

  /// Motivo legible de cada clave que devuelve el gate.
  static String etiquetaMotivo(String motivo) {
    const mapa = <String, String>{
      'ci': 'Carnet de identidad',
      'tipo_documento': 'Tipo de documento',
      'doc_frente': 'Foto del carnet (frente)',
      'doc_dorso': 'Foto del carnet (dorso)',
      'provincia': 'Provincia',
      'municipio': 'Municipio',
      'poblado': 'Poblado',
      'direccion': 'Dirección',
      'perfil_cliente': 'Perfil de pasajero',
      'perfil_chofer': 'Perfil de chofer',
      'kyc_pendiente_aprobacion': 'Verificación de identidad en revisión',
      'kyc_rechazado': 'Verificación de identidad rechazada',
      'consentimiento_pendiente': 'Documentos legales por aceptar',
      'sin_contacto_emergencia': 'Contacto de emergencia',
      'bloqueado': 'Cuenta con reportes de seguridad confirmados',
      'telefono': 'Teléfono',
      'name': 'Nombre',
    };
    return mapa[motivo] ?? motivo.replaceAll('_', ' ');
  }

  // ── Documentos legales y consentimiento ─────────────────────────────────

  /// Documentos publicados y obligatorios desde `muevete.documentos_legales`.
  Future<List<DocumentoLegal>> documentosLegales() async {
    try {
      final rows = await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .select(
            'codigo, version, titulo, resumen, contenido_md, '
            'es_obligatorio, publicado',
          )
          .eq('publicado', true)
          .eq('es_obligatorio', true)
          .order('codigo');

      return List<Map<String, dynamic>>.from(rows)
          .map(DocumentoLegal.fromJson)
          .where((d) => d.codigo.isNotEmpty && d.version.isNotEmpty)
          .toList();
    } catch (e) {
      throw IdentidadException(
        AppError.message(e, action: 'cargar los documentos legales'),
        clave: 'documentos',
      );
    }
  }

  /// Documentos ya aceptados por el usuario (`muevete.consentimientos`).
  Future<Set<String>> documentosAceptados() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      if (uid == null) return <String>{};
      final rows = await _supabase
          .schema('muevete')
          .from('consentimientos')
          .select('documento_codigo, documento_version')
          .eq('user_uuid', uid)
          .eq('aceptado', true);

      return List<Map<String, dynamic>>.from(rows)
          .map((r) => '${r['documento_codigo']}@${r['documento_version']}')
          .toSet();
    } catch (_) {
      // Sin permiso de lectura se resuelve por el gate del servidor.
      return <String>{};
    }
  }

  /// `consentimiento.faltantes` del gate, como documentos tipados.
  Future<List<DocumentoPendiente>> documentosPendientes() async {
    final est = await estado();
    return est.consentimiento.faltantes;
  }

  /// `fn_aceptar_consentimiento(p_codigo, p_version, ...)`.
  Future<void> aceptar(
    String codigo,
    String version, {
    String metodo = 'app',
    Map<String, dynamic>? metadata,
  }) async {
    await _rpc(
      'fn_aceptar_consentimiento',
      params: {
        'p_codigo': codigo,
        'p_version': version,
        'p_metodo': metodo,
        'p_app_version': kAppVersion,
        'p_user_agent': kUserAgent,
        'p_metadata': metadata ?? const <String, dynamic>{},
      },
      accion: 'registrar tu aceptación',
    );
  }

  /// Versión publicada y vigente de un documento, si existe.
  Future<String?> versionVigente(String codigo) async {
    try {
      final row = await _supabase
          .schema('muevete')
          .from('documentos_legales')
          .select('version')
          .eq('codigo', codigo)
          .eq('publicado', true)
          .isFilter('vigente_hasta', null)
          .order('vigente_desde', ascending: false)
          .limit(1)
          .maybeSingle();
      return row?['version']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Acepta un consentimiento que no es obligatorio para operar (por ejemplo
  /// `contacto_emergencia`, la declaración de autorización del tercero).
  ///
  /// Devuelve `false` si el documento no está publicado: en ese caso no se
  /// registra evidencia inventada, simplemente queda sin constancia.
  Future<bool> aceptarDocumentoOpcional(
    String codigo, {
    String versionFallback = '1.0.0',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final version = await versionVigente(codigo) ?? versionFallback;
      await aceptar(codigo, version, metadata: metadata);
      return true;
    } on IdentidadException catch (e) {
      if (e.clave == 'documento_no_existe' ||
          e.clave == 'documento_no_vigente') {
        return false;
      }
      rethrow;
    }
  }

  /// Acepta todos los documentos que el gate marca como pendientes.
  ///
  /// Devuelve cuántos se aceptaron. Si un documento cambió de versión, la
  /// pendiente trae la versión nueva (`codigo@version`) y se acepta esa.
  Future<int> aceptarTodos({Map<String, dynamic>? metadata}) async {
    final pendientes = await documentosPendientes();
    if (pendientes.isEmpty) return 0;

    var aceptados = 0;
    for (final doc in pendientes) {
      if (doc.version.isEmpty) continue;
      await aceptar(doc.codigo, doc.version, metadata: metadata);
      aceptados++;
    }
    return aceptados;
  }

  // ── Interno ─────────────────────────────────────────────────────────────

  /// Ejecuta una RPC del esquema `muevete` traduciendo cualquier error a
  /// [IdentidadException] con texto en español.
  Future<dynamic> _rpc(
    String nombre, {
    required Map<String, dynamic> params,
    required String accion,
  }) async {
    try {
      return await _supabase.schema('muevete').rpc(nombre, params: params);
    } on PostgrestException catch (e) {
      throw IdentidadException(_mensajePostgrest(e, accion), clave: _clave(e));
    } catch (e) {
      throw IdentidadException(AppError.message(e, action: accion));
    }
  }

  static String _mensajePostgrest(PostgrestException e, String accion) {
    final clave = _clave(e);
    const mapa = <String, String>{
      'ci_invalido':
          'El carnet debe tener 11 dígitos con una fecha válida (mes 01-12, día 01-31)',
      'rol_invalido': 'El tipo de cuenta no es válido',
      'perfil_no_existe': 'No encontramos tu perfil de pasajero',
      'perfil_chofer_no_existe': 'No encontramos tu perfil de chofer',
      'documento_no_existe': 'Ese documento legal ya no está disponible',
      'documento_no_vigente':
          'Ese documento legal tiene una versión nueva. Vuelve a cargar la lista',
      'contacto_no_existe': 'Ese contacto ya no existe',
      'codigo_invalido': 'El código no es correcto o venció',
      'no_autorizado': 'No puedes hacer esta operación con tu cuenta',
      'no_autenticado': 'Tu sesión expiró. Vuelve a iniciar sesión',
      'fuera_de_ventana': 'Pasó el tiempo para hacer esta operación',
      'usuario_sin_perfil': 'Tu cuenta aún no tiene perfil completo',
      'funcion_no_disponible':
          'Esta función todavía no está disponible en el servidor',
    };
    if (clave != null && mapa.containsKey(clave)) return mapa[clave]!;

    final texto = '${e.message} ${e.details ?? ''}'.toLowerCase();
    for (final entry in mapa.entries) {
      if (texto.contains(entry.key)) return entry.value;
    }

    if (texto.contains('could not find the function') ||
        (e.code ?? '') == 'PGRST202') {
      return 'Esta función todavía no está disponible en el servidor';
    }
    return AppError.message(e, action: accion);
  }

  static String? _clave(PostgrestException e) {
    final codigo = (e.code ?? '').toUpperCase();
    const porCodigo = <String, String>{
      'P0042': 'documento_no_existe',
      'P0043': 'documento_no_vigente',
      'P0044': 'ci_invalido',
      'P0045': 'perfil_no_existe',
      'P0111': 'no_puedes_borrar_el_ultimo_contacto_aceptado',
      'P0112': 'contacto_invalido',
      'P0113': 'maximo_contactos_alcanzado',
      'P0114': 'contacto_no_existe',
      'P0115': 'codigo_invalido',
      'P0117': 'fuera_de_ventana',
      '42501': 'no_autorizado',
      '28000': 'no_autenticado',
      'PGRST202': 'funcion_no_disponible',
    };
    if (porCodigo.containsKey(codigo)) return porCodigo[codigo];

    final texto = '${e.message} ${e.details ?? ''}'.toLowerCase();
    for (final clave in porCodigo.values) {
      if (texto.contains(clave)) return clave;
    }
    if (texto.contains('could not find the function')) {
      return 'funcion_no_disponible';
    }
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return const <String, dynamic>{};
  }

  static List<String> _lista(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const [];
  }
}
