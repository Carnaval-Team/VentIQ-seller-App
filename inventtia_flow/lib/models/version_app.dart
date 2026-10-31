import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Tipo de un cambio del changelog.
///
/// El servidor manda el token en inglés (`type`: `feature|improvement|fix`) y
/// `assets/changelog.json` usa exactamente la misma forma, así que un solo
/// modelo sirve para las dos fuentes.
enum TipoCambio {
  feature,
  improvement,
  fix,

  /// Red de seguridad: un tipo desconocido no debe romper la lista ni mentir
  /// diciendo que es una mejora.
  otro;

  static TipoCambio desde(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'feature':
      case 'novedad':
      case 'nuevo':
        return TipoCambio.feature;
      case 'improvement':
      case 'mejora':
        return TipoCambio.improvement;
      case 'fix':
      case 'correccion':
      case 'corrección':
      case 'arreglo':
        return TipoCambio.fix;
      default:
        return TipoCambio.otro;
    }
  }

  /// Etiqueta corta que se pinta como cinta en la tarjeta del cambio.
  String get etiqueta {
    switch (this) {
      case TipoCambio.feature:
        return 'Novedad';
      case TipoCambio.improvement:
        return 'Mejora';
      case TipoCambio.fix:
        return 'Corrección';
      case TipoCambio.otro:
        return 'Cambio';
    }
  }

  IconData get icono {
    switch (this) {
      case TipoCambio.feature:
        return Icons.auto_awesome_rounded;
      case TipoCambio.improvement:
        return Icons.trending_up_rounded;
      case TipoCambio.fix:
        return Icons.build_rounded;
      case TipoCambio.otro:
        return Icons.label_outline_rounded;
    }
  }

  Color get color {
    switch (this) {
      case TipoCambio.feature:
        return AppTheme.primary;
      case TipoCambio.improvement:
        return AppTheme.success;
      case TipoCambio.fix:
        return AppTheme.warning;
      case TipoCambio.otro:
        return AppTheme.textSecondary;
    }
  }
}

/// Un cambio concreto de una versión.
class CambioVersion {
  const CambioVersion({
    required this.tipo,
    required this.titulo,
    this.descripcion = '',
  });

  final TipoCambio tipo;
  final String titulo;
  final String descripcion;

  bool get vacio => titulo.trim().isEmpty && descripcion.trim().isEmpty;

  /// Acepta tanto la forma del servidor (`type|title|description`) como la del
  /// asset (`type|title|description`, idéntica) y tolera las claves en español.
  factory CambioVersion.fromJson(Map<String, dynamic> json) {
    return CambioVersion(
      tipo: TipoCambio.desde((json['type'] ?? json['tipo'])?.toString()),
      titulo: _texto(json['title'] ?? json['titulo']) ?? '',
      descripcion: _texto(json['description'] ?? json['descripcion']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': tipo.name,
    'title': titulo,
    'description': descripcion,
  };

  /// Normaliza lo que llega como `novedades`/`changes`/`cambios`.
  ///
  /// Puede venir ya como lista (jsonb de PostgREST) o como texto JSON (cuando un
  /// `returns json` anida el array dentro de otra cadena). Un valor raro
  /// devuelve lista vacía en vez de lanzar: el aviso debe abrirse igual.
  static List<CambioVersion> listaDesde(dynamic raw) {
    dynamic valor = raw;
    if (valor is String) {
      final texto = valor.trim();
      if (texto.isEmpty) return const [];
      try {
        valor = json.decode(texto);
      } catch (_) {
        return const [];
      }
    }
    if (valor is! List) return const [];
    final salida = <CambioVersion>[];
    for (final item in valor) {
      if (item is! Map) continue;
      final cambio = CambioVersion.fromJson(Map<String, dynamic>.from(item));
      if (!cambio.vacio) salida.add(cambio);
    }
    return salida;
  }
}

/// Una versión con su changelog.
///
/// El mismo modelo se construye desde `fn_check_update`, desde
/// `fn_app_versiones` y desde `assets/changelog.json`: [fromJson] entiende las
/// tres formas de nombrar los campos.
class VersionApp {
  const VersionApp({
    this.id,
    required this.version,
    required this.build,
    this.titulo,
    this.fecha,
    this.obligatoria = false,
    this.urlDescarga,
    this.versionMinima,
    this.cambios = const [],
  });

  final int? id;
  final String version;
  final int build;
  final String? titulo;

  /// Fecha de lanzamiento tal como la manda el origen (`2026-10-12` o ISO).
  final String? fecha;
  final bool obligatoria;
  final String? urlDescarga;
  final String? versionMinima;
  final List<CambioVersion> cambios;

  bool get tieneTitulo => (titulo ?? '').trim().isNotEmpty;
  bool get tieneCambios => cambios.isNotEmpty;

  /// `v1.4.7 · build 15`. El build se omite si el origen no lo trae (el asset
  /// solo lo declara para la última versión).
  String get etiquetaVersion =>
      build > 0 ? 'v$version · build $build' : 'v$version';

  /// `12 oct 2026`. Se formatea a mano para no depender de que la app haya
  /// inicializado los símbolos de fecha de `intl` en español.
  String? get fechaLegible {
    final d = fechaComoDate;
    if (d == null) return fecha;
    const meses = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${d.day} ${meses[d.month - 1]} ${d.year}';
  }

  DateTime? get fechaComoDate {
    final raw = fecha?.trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// `true` si esta versión es la que el usuario tiene instalada.
  ///
  /// Se compara por versión y por build porque el historial del asset no trae
  /// número de build en cada entrada.
  bool esLaInstalada(VersionApp instalada) {
    if (version.trim() == instalada.version.trim()) return true;
    return build > 0 && instalada.build > 0 && build == instalada.build;
  }

  VersionApp copyWith({
    int? id,
    String? version,
    int? build,
    String? titulo,
    String? fecha,
    bool? obligatoria,
    String? urlDescarga,
    String? versionMinima,
    List<CambioVersion>? cambios,
  }) {
    return VersionApp(
      id: id ?? this.id,
      version: version ?? this.version,
      build: build ?? this.build,
      titulo: titulo ?? this.titulo,
      fecha: fecha ?? this.fecha,
      obligatoria: obligatoria ?? this.obligatoria,
      urlDescarga: urlDescarga ?? this.urlDescarga,
      versionMinima: versionMinima ?? this.versionMinima,
      cambios: cambios ?? this.cambios,
    );
  }

  /// Único punto de parseo para las tres fuentes.
  ///
  /// | origen | id | versión | build | título | fecha | cambios |
  /// |---|---|---|---|---|---|---|
  /// | `fn_check_update` | `id_version` | `version_disponible` | `build_disponible` | `titulo` | `fecha_lanzamiento` | `novedades` |
  /// | `fn_app_versiones` | `id` | `version_actual` | `build_number` | `titulo` | `fecha_lanzamiento` | `novedades` |
  /// | `changelog.json` | — | `version` | `build` | `title` | `date` | `changes` |
  factory VersionApp.fromJson(Map<String, dynamic> json) {
    return VersionApp(
      id: _entero(json['id'] ?? json['id_version']),
      version:
          _texto(
            json['version'] ??
                json['version_actual'] ??
                json['version_disponible'],
          ) ??
          '0.0.0',
      build:
          _entero(
            json['build'] ?? json['build_number'] ?? json['build_disponible'],
          ) ??
          0,
      titulo: _texto(json['titulo'] ?? json['title']),
      fecha: _texto(json['fecha'] ?? json['date'] ?? json['fecha_lanzamiento']),
      obligatoria: json['obligatoria'] == true,
      urlDescarga: _texto(json['url_descarga'] ?? json['urlDescarga']),
      versionMinima: _texto(json['version_minima']),
      cambios: CambioVersion.listaDesde(
        json['novedades'] ?? json['cambios'] ?? json['changes'],
      ),
    );
  }
}

/// Resultado de comprobar si hay una versión nueva.
class AvisoActualizacion {
  const AvisoActualizacion({
    required this.instalada,
    this.disponible,
    this.obligatoria = false,
    this.desdeRespaldo = false,
    this.esquemaPendiente = false,
    this.error,
  });

  /// Versión realmente instalada (`package_info_plus`).
  final VersionApp instalada;

  /// Versión nueva. `null` = no hay nada que descargar.
  final VersionApp? disponible;

  final bool obligatoria;

  /// `true` cuando el aviso se armó con `assets/changelog.json` porque la
  /// consulta al servidor falló. La UI lo dice en voz alta: puede que no sea la
  /// última publicada.
  final bool desdeRespaldo;

  /// El respaldo se usó porque el RPC todavía no existe en la base (migración
  /// sin pegar), no porque no haya red. Cambia el texto que ve el usuario.
  final bool esquemaPendiente;

  /// Motivo del fallo de red / RPC ausente, si lo hubo.
  final String? error;

  bool get hayActualizacion => disponible != null;

  /// Frase corta para explicar de dónde salen los datos.
  String get mensajeRespaldo => esquemaPendiente
      ? 'El servidor todavía no publica novedades; te mostramos las que trae la app.'
      : 'Sin conexión: te mostramos la última versión que conoce la app.';
}

/// Historial completo de versiones para la pantalla de novedades.
class HistorialVersiones {
  const HistorialVersiones({
    required this.instalada,
    this.versiones = const [],
    this.desdeRespaldo = false,
    this.esquemaPendiente = false,
    this.error,
  });

  final VersionApp instalada;

  /// Más nueva primero.
  final List<VersionApp> versiones;

  /// `true` si la lista viene del asset (sin conexión o RPC aún no desplegado).
  final bool desdeRespaldo;

  /// El respaldo se usó porque el RPC del historial no existe todavía.
  final bool esquemaPendiente;
  final String? error;

  bool get vacio => versiones.isEmpty;

  /// Frase corta para explicar de dónde sale el historial.
  String get mensajeRespaldo => esquemaPendiente
      ? 'El servidor todavía no publica el historial; te mostramos el que trae la app.'
      : 'Sin conexión: te mostramos el historial guardado en la app.';
}

// ── Normalizadores tolerantes ────────────────────────────────────────────────
// El servidor puede mandar `build_number` como number o como texto ("15") según
// cómo lo devuelva el RPC; el asset siempre number. Ninguno debe lanzar.

String? _texto(dynamic valor) {
  if (valor == null) return null;
  final texto = valor.toString().trim();
  return texto.isEmpty ? null : texto;
}

int? _entero(dynamic valor) {
  if (valor == null) return null;
  if (valor is int) return valor;
  if (valor is num) return valor.toInt();
  return int.tryParse(valor.toString().trim());
}
