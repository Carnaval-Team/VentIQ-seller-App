import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/web_reload_stub.dart'
    if (dart.library.html) '../utils/web_reload_web.dart';

/// Servicio de actualización. Lee la versión local desde
/// [assets/changelog.json] y consulta en Supabase si hay una versión
/// más reciente mediante la función RPC `fn_check_update`.
class UpdateService {
  static final _supabase = Supabase.instance.client;
  static bool _checkedThisSession = false;

  /// Lee la versión actual y las URLs de actualización desde
  /// `assets/changelog.json`.
  static Future<Map<String, dynamic>> getCurrentVersionInfo() async {
    try {
      final String response =
          await rootBundle.loadString('assets/changelog.json');
      final Map<String, dynamic> data = json.decode(response);

      return {
        'app_name': data['app_name'] ?? 'inventtia_muevete',
        'current_version': data['current_version'] ?? '1.0.0',
        'build': data['build'] ?? 1,
        'download_url_apk': data['download_url_apk'] ?? '',
        'download_url_web': data['download_url_web'] ?? '',
      };
    } catch (e) {
      print('❌ Error leyendo changelog.json: $e');
      return {
        'app_name': 'inventtia_muevete',
        'current_version': '1.0.0',
        'build': 1,
        'download_url_apk': '',
        'download_url_web': '',
      };
    }
  }

  /// Consulta en Supabase si existe una versión más reciente.
  ///
  /// Usa [force] para saltar el control de una única verificación por sesión.
  static Future<Map<String, dynamic>> checkForUpdates({bool force = false}) async {
    if (!force && _checkedThisSession) {
      print(
        '⏭️ Verificación de actualización omitida: ya se realizó en esta sesión',
      );
      return {
        'success': true,
        'hay_actualizacion': false,
        'skipped': true,
      };
    }
    _checkedThisSession = true;

    try {
      print('🔍 Verificando actualizaciones disponibles...');

      final currentInfo = await getCurrentVersionInfo();
      final String appName = currentInfo['app_name'];
      final String currentVersion = currentInfo['current_version'];
      final int currentBuild = currentInfo['build'];

      print('📱 Versión actual: $currentVersion (build $currentBuild)');

      final response = await _supabase.rpc(
        'fn_check_update',
        params: {
          'p_app_name': appName,
          'p_version_actual': currentVersion,
          'p_build_actual': currentBuild,
        },
      );

      print('📊 Respuesta del servidor: $response');

      if (response != null) {
        final Map<String, dynamic> updateInfo =
            response as Map<String, dynamic>;
        updateInfo['current_version'] = currentVersion;
        updateInfo['current_build'] = currentBuild;
        updateInfo['app_name'] = appName;
        updateInfo['download_url_apk'] = currentInfo['download_url_apk'];
        updateInfo['download_url_web'] = currentInfo['download_url_web'];

        if (updateInfo['hay_actualizacion'] == true) {
          print(
            '🆕 Nueva versión disponible: ${updateInfo['version_disponible']}',
          );
          print('⚠️ Actualización obligatoria: ${updateInfo['obligatoria']}');
        } else {
          print('✅ La aplicación está actualizada');
        }

        return updateInfo;
      } else {
        return {
          'success': false,
          'error': 'No se pudo obtener información de actualizaciones',
          'hay_actualizacion': false,
        };
      }
    } catch (e) {
      print('❌ Error verificando actualizaciones: $e');
      return {
        'success': false,
        'error': e.toString(),
        'hay_actualizacion': false,
      };
    }
  }

  /// Abre la URL de actualización correspondiente a la plataforma.
  ///
  /// - APK: abre [download_url_apk] con `url_launcher`.
  /// - Web: abre [download_url_web] o, si no está configurada, recarga la
  ///   página para obtener la nueva versión desplegada.
  ///
  /// Retorna `true` si pudo iniciar la acción y `false` si no hay URL
  /// configurada (solo APK) o falló la apertura.
  static Future<bool> openUpdate(Map<String, dynamic> updateInfo) async {
    final apkUrl = updateInfo['download_url_apk']?.toString() ?? '';
    final webUrl = updateInfo['download_url_web']?.toString() ?? '';

    if (kIsWeb) {
      if (webUrl.isNotEmpty) {
        final launched = await _launchUrl(Uri.parse(webUrl));
        if (!launched) {
          reloadWeb();
        }
      } else {
        reloadWeb();
      }
      return true;
    }

    if (apkUrl.isEmpty) {
      return false;
    }

    return _launchUrl(Uri.parse(apkUrl));
  }

  static Future<bool> _launchUrl(Uri url) async {
    bool launched = false;

    try {
      launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      print('✅ Método externalApplication: $launched');
    } catch (e) {
      print('❌ Método externalApplication falló: $e');
    }

    if (!launched) {
      try {
        launched = await launchUrl(url, mode: LaunchMode.inAppWebView);
        print('✅ Método inAppWebView: $launched');
      } catch (e) {
        print('❌ Método inAppWebView falló: $e');
      }
    }

    if (!launched) {
      try {
        launched = await launchUrl(url);
        print('✅ Método default: $launched');
      } catch (e) {
        print('❌ Método default falló: $e');
      }
    }

    return launched;
  }
}
