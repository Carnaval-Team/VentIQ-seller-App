import 'dart:convert';

import 'package:flutter/services.dart';
// `package_info_plus` llega hoy como dependencia transitiva (vía share_plus) y
// el plugin ya está registrado en el proyecto, así que se puede importar y usar.
// Lo correcto es declararla en `pubspec.yaml`; mientras eso no ocurra el lint
// `depend_on_referenced_packages` se silencia aquí a propósito (ver informe).
// ignore: depend_on_referenced_packages
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/version_app.dart';
import '../utils/esquema_pendiente.dart';

/// Versión instalada, aviso de actualización e historial de cambios.
///
/// La versión que se reporta al servidor sale de **`package_info_plus`** (lo que
/// de verdad está instalado en el dispositivo), no de `assets/changelog.json`.
/// El asset queda como respaldo offline y como fuente de los textos: nació con
/// `current_version: 1.4.8` mientras `pubspec.yaml` dice `1.4.0+8`, y esa
/// delantera hacía que la app se creyera más nueva que la base de datos y por eso
/// `fn_check_update` nunca avisaba.
class UpdateService {
  static final _supabase = Supabase.instance.client;

  static const String appName = 'inventtia_flow';

  /// Enlace por defecto cuando la versión no trae uno propio
  /// (`url_descarga` nulo).
  static const String downloadUrl =
      'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/goreservas.apk';

  /// Ruta del changelog local, con el historial completo 1.0.0 → 1.4.8.
  static const String _rutaAsset = 'assets/changelog.json';

  static VersionApp? _instalada;
  static List<VersionApp>? _cacheAsset;

  // ── Versión instalada ──────────────────────────────────────────────────────

  /// Versión y build reales del paquete instalado.
  ///
  /// [refrescar] vuelve a preguntarle al sistema (útil tras una actualización en
  /// caliente); por defecto se cachea porque `PackageInfo.fromPlatform()` habla
  /// con la plataforma.
  static Future<VersionApp> appInstalada({bool refrescar = false}) async {
    final cacheada = _instalada;
    if (cacheada != null && !refrescar) return cacheada;

    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber.trim()) ?? 0;
      final version = info.version.trim();
      final instalada = VersionApp(
        version: version.isEmpty ? '0.0.0' : version,
        build: build,
      );
      _instalada = instalada;
      return instalada;
    } catch (e) {
      // `package_info_plus` no debería fallar en un dispositivo real, pero si
      // falla preferimos la versión del asset (única pista que queda) antes que
      // reportar 1.0.0 y provocar un aviso de actualización falso.
      print('[flow] UpdateService.appInstalada ERROR: $e');
      final respaldo = await _versionesDelAsset();
      final instalada = respaldo.isNotEmpty
          ? respaldo.first
          : const VersionApp(version: '0.0.0', build: 0);
      _instalada = instalada;
      return instalada;
    }
  }

  /// Compatibilidad con el código que ya consumía este mapa.
  static Future<Map<String, dynamic>> getCurrentVersionInfo() async {
    final instalada = await appInstalada();
    return {
      'app_name': appName,
      'current_version': instalada.version,
      'build': instalada.build,
    };
  }

  /// Enlace de descarga efectivo: el que manda el servidor para esa versión o,
  /// si no viene, la constante de siempre.
  static String urlDeDescarga(VersionApp? version) {
    final propia = version?.urlDescarga?.trim();
    if (propia != null && propia.isNotEmpty) return propia;
    return downloadUrl;
  }

  // ── Comprobación de actualización ──────────────────────────────────────────

  /// Pregunta a `fn_check_update` con la versión instalada de verdad.
  ///
  /// Si la consulta falla (sin red, o RPC sin desplegar) cae al historial local
  /// del asset y devuelve el aviso marcado con [AvisoActualizacion.desdeRespaldo]
  /// para que la UI lo advierta. La comparación de builds la hace el servidor:
  /// aquí no se inventa lógica de versiones.
  static Future<AvisoActualizacion> avisoActual() async {
    final instalada = await appInstalada();

    try {
      final response = await _supabase.rpc(
        'fn_check_update',
        params: {
          'p_app_name': appName,
          'p_version_actual': instalada.version,
          'p_build_actual': instalada.build,
        },
      );

      if (response == null) {
        return _avisoDesdeRespaldo(
          instalada,
          error: 'Sin respuesta del servidor',
        );
      }

      final json = Map<String, dynamic>.from(response as Map);
      if (json['hay_actualizacion'] != true) {
        print('[flow] UpdateService → app actualizada');
        return AvisoActualizacion(instalada: instalada);
      }

      // El servidor puede no mandar todavía `titulo`/`novedades` (migración 75
      // sin pegar): se completan con el asset, que tiene los mismos textos.
      final cruda = VersionApp.fromJson(json);
      final disponible = _fusionarConAsset(
        cruda.copyWith(urlDescarga: urlDeDescarga(cruda)),
        await _versionesDelAsset(),
      );
      print(
        '[flow] UpdateService → nueva versión: ${disponible.version} '
        '(build ${disponible.build}) | obligatoria: ${json['obligatoria'] == true}',
      );
      return AvisoActualizacion(
        instalada: instalada,
        disponible: disponible,
        obligatoria: json['obligatoria'] == true || disponible.obligatoria,
      );
    } catch (e) {
      print('[flow] UpdateService.avisoActual ERROR: $e');
      return _avisoDesdeRespaldo(instalada, error: e.toString());
    }
  }

  /// Compatibilidad: mapa con la forma antigua más los campos nuevos.
  static Future<Map<String, dynamic>> checkForUpdates() async {
    final aviso = await avisoActual();
    final instalada = aviso.instalada;
    final salida = <String, dynamic>{
      'success': aviso.error == null,
      'hay_actualizacion': aviso.hayActualizacion,
      'obligatoria': aviso.obligatoria,
      'current_version': instalada.version,
      'current_build': instalada.build,
      'app_name': appName,
      'desde_respaldo': aviso.desdeRespaldo,
    };
    if (aviso.error != null) salida['error'] = aviso.error;

    final nueva = aviso.disponible;
    if (nueva != null) {
      salida.addAll({
        'version_disponible': nueva.version,
        'id_version': nueva.id,
        'build_disponible': nueva.build,
        'titulo': nueva.titulo,
        'novedades': nueva.cambios.map((c) => c.toJson()).toList(),
        'url_descarga': nueva.urlDescarga,
        'fecha_lanzamiento': nueva.fecha,
        'version_minima': nueva.versionMinima,
      });
    }
    return salida;
  }

  // ── Historial de versiones ─────────────────────────────────────────────────

  /// Historial completo, más nueva primero.
  ///
  /// Primero `fn_app_versiones`; si el RPC no está desplegado o falla la red,
  /// el historial del asset (que es el mismo changelog con el que se publicó
  /// cada versión).
  static Future<HistorialVersiones> historial({int limite = 30}) async {
    final instalada = await appInstalada();

    try {
      final response = await _supabase.rpc(
        'fn_app_versiones',
        params: {'p_app_name': appName, 'p_limit': limite},
      );

      final json = response is Map
          ? Map<String, dynamic>.from(response)
          : <String, dynamic>{};
      final data = json['data'];

      if (json['ok'] == true && data is List && data.isNotEmpty) {
        final local = await _versionesDelAsset();
        final versiones = <VersionApp>[];
        for (final item in data) {
          if (item is! Map) continue;
          versiones.add(
            _fusionarConAsset(
              VersionApp.fromJson(Map<String, dynamic>.from(item)),
              local,
            ),
          );
        }
        versiones.sort((a, b) => b.build.compareTo(a.build));
        return HistorialVersiones(instalada: instalada, versiones: versiones);
      }

      final pendiente = json['ok'] != true;
      // El RPC contestó, pero sin historial publicado (o con una forma rara):
      // se muestra el del asset y se explica, sin hablar de «sin conexión».
      return HistorialVersiones(
        instalada: instalada,
        versiones: await _versionesDelAsset(),
        desdeRespaldo: true,
        esquemaPendiente: true,
        error: pendiente
            ? 'El servidor todavía no publica el historial de versiones'
            : 'El servidor no devolvió el historial de versiones',
      );
    } catch (e) {
      print('[flow] UpdateService.historial ERROR: $e');
      return HistorialVersiones(
        instalada: instalada,
        versiones: await _versionesDelAsset(),
        desdeRespaldo: true,
        esquemaPendiente: esErrorDeEsquemaAusente(e),
        error: e.toString(),
      );
    }
  }

  // ── Respaldo local (assets/changelog.json) ─────────────────────────────────

  /// Aviso armado con el asset cuando el servidor no responde.
  static Future<AvisoActualizacion> _avisoDesdeRespaldo(
    VersionApp instalada, {
    required String error,
  }) async {
    final local = await _versionesDelAsset();
    final pendiente = esErrorDeEsquemaAusente(error);
    // El asset ya viene ordenado de más nueva a más vieja.
    final ultima = local.isNotEmpty ? local.first : null;
    final hay = ultima != null && ultima.build > instalada.build;
    return AvisoActualizacion(
      instalada: instalada,
      disponible: hay ? ultima : null,
      obligatoria: hay && ultima.obligatoria,
      desdeRespaldo: true,
      esquemaPendiente: pendiente,
      error: error,
    );
  }

  /// Lee y cachea el historial del asset.
  ///
  /// El asset no trae número de build por entrada, solo uno global para la
  /// última (`current_version`/`build`): ese se le asigna a la versión que
  /// coincide, que es la que interesa para comparar con lo instalado.
  static Future<List<VersionApp>> _versionesDelAsset() async {
    final cacheado = _cacheAsset;
    if (cacheado != null) return cacheado;

    try {
      final texto = await rootBundle.loadString(_rutaAsset);
      final data = json.decode(texto);
      if (data is! Map) {
        _cacheAsset = const [];
        return _cacheAsset!;
      }

      final mapa = Map<String, dynamic>.from(data);
      final versionActual = mapa['current_version']?.toString().trim();
      final buildActual = int.tryParse(mapa['build']?.toString() ?? '') ?? 0;
      final lista = mapa['changelogs'];

      final versiones = <VersionApp>[];
      if (lista is List) {
        for (final item in lista) {
          if (item is! Map) continue;
          final version = VersionApp.fromJson(Map<String, dynamic>.from(item));
          versiones.add(
            version.copyWith(
              urlDescarga: urlDeDescarga(version),
              build: (buildActual > 0 && version.version == versionActual)
                  ? buildActual
                  : version.build,
            ),
          );
        }
      }
      versiones.sort((a, b) => b.build.compareTo(a.build));
      _cacheAsset = versiones;
      return versiones;
    } catch (e) {
      print('[flow] UpdateService._versionesDelAsset ERROR: $e');
      _cacheAsset = const [];
      return _cacheAsset!;
    }
  }

  /// Rellena huecos (título, cambios, fecha) usando la entrada del asset que
  /// corresponde a la misma versión. Lo que venga del servidor siempre gana.
  static VersionApp _fusionarConAsset(
    VersionApp version,
    List<VersionApp> local,
  ) {
    VersionApp? match;
    for (final candidata in local) {
      if (candidata.version.trim() == version.version.trim()) {
        match = candidata;
        break;
      }
    }
    return version.copyWith(
      titulo: version.tieneTitulo ? version.titulo : match?.titulo,
      cambios: version.tieneCambios
          ? version.cambios
          : (match?.cambios ?? const []),
      fecha: version.fecha ?? match?.fecha,
      urlDescarga: urlDeDescarga(version),
    );
  }
}
