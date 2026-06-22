import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateService {
  static final _supabase = Supabase.instance.client;

  static const String downloadUrl =
      'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/flow.apk';

  static Future<Map<String, dynamic>> getCurrentVersionInfo() async {
    try {
      final String response =
          await rootBundle.loadString('assets/changelog.json');
      final Map<String, dynamic> data = json.decode(response);
      return {
        'app_name': data['app_name'] ?? 'inventtia_flow',
        'current_version': data['current_version'] ?? '1.0.0',
        'build': data['build'] ?? 1,
      };
    } catch (e) {
      print('[flow] UpdateService.getCurrentVersionInfo ERROR: $e');
      return {
        'app_name': 'inventtia_flow',
        'current_version': '1.0.0',
        'build': 1,
      };
    }
  }

  static Future<Map<String, dynamic>> checkForUpdates() async {
    try {
      print('[flow] UpdateService.checkForUpdates → iniciando...');

      final currentInfo = await getCurrentVersionInfo();
      final String appName = currentInfo['app_name'];
      final String currentVersion = currentInfo['current_version'];
      final int currentBuild = currentInfo['build'];

      print(
          '[flow] UpdateService → versión actual: $currentVersion (build $currentBuild)');

      final response = await _supabase.rpc('fn_check_update', params: {
        'p_app_name': appName,
        'p_version_actual': currentVersion,
        'p_build_actual': currentBuild,
      });

      if (response != null) {
        final Map<String, dynamic> updateInfo =
            response as Map<String, dynamic>;
        updateInfo['current_version'] = currentVersion;
        updateInfo['current_build'] = currentBuild;
        updateInfo['app_name'] = appName;

        if (updateInfo['hay_actualizacion'] == true) {
          print(
              '[flow] UpdateService → nueva versión: ${updateInfo['version_disponible']} | obligatoria: ${updateInfo['obligatoria']}');
        } else {
          print('[flow] UpdateService → app actualizada');
        }
        return updateInfo;
      } else {
        return {
          'success': false,
          'error': 'Sin respuesta del servidor',
          'hay_actualizacion': false,
        };
      }
    } catch (e) {
      print('[flow] UpdateService.checkForUpdates ERROR: $e');
      return {
        'success': false,
        'error': e.toString(),
        'hay_actualizacion': false,
      };
    }
  }
}
