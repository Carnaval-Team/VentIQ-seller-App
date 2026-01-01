import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateService {
  static final _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>> getCurrentVersionInfo() async {
    try {
      final response = await rootBundle.loadString('assets/changelog.json');
      final data = json.decode(response);

      return {
        'app_name': data['app_name'] ?? 'ventiq_marketplace',
        'current_version': data['current_version'] ?? '1.0.0',
        'build': data['build'] ?? 1,
      };
    } catch (_) {
      return {
        'app_name': 'ventiq_marketplace',
        'current_version': '1.0.0',
        'build': 1,
      };
    }
  }

  static Future<Map<String, dynamic>> checkForUpdates() async {
    try {
      final currentInfo = await getCurrentVersionInfo();
      final String appName = currentInfo['app_name'];
      final String currentVersion = currentInfo['current_version'];
      final int currentBuild = currentInfo['build'];

      final response = await _supabase.rpc(
        'fn_check_update',
        params: {
          'p_app_name': appName,
          'p_version_actual': currentVersion,
          'p_build_actual': currentBuild,
        },
      );

      if (response == null) {
        return {
          'success': false,
          'error': 'No se pudo obtener información de actualizaciones',
          'hay_actualizacion': false,
        };
      }

      final updateInfo = Map<String, dynamic>.from(response as Map);
      updateInfo['current_version'] = currentVersion;
      updateInfo['current_build'] = currentBuild;
      updateInfo['app_name'] = appName;

      return updateInfo;
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'hay_actualizacion': false,
      };
    }
  }

  static const String downloadUrl =
      'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/inventtia%20catalogo.apk';
}
