import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateService {
  static final _supabase = Supabase.instance.client;

  /// Obtener información de la versión actual desde changelog.json
  static Future<Map<String, dynamic>> getCurrentVersionInfo() async {
    try {
      final String response = await rootBundle.loadString('assets/changelog.json');
      final Map<String, dynamic> data = json.decode(response);
      
      return {
        'app_name': data['app_name'] ?? 'ventiq_app',
        'current_version': data['current_version'] ?? '1.0.0',
        'build': data['build'] ?? 1,
      };
    } catch (e) {
      print('❌ Error leyendo changelog.json: $e');
      // Valores por defecto en caso de error
      return {
        'app_name': 'ventiq_app',
        'current_version': '1.0.0',
        'build': 1,
      };
    }
  }

  /// Verificar si hay actualizaciones disponibles
  static Future<Map<String, dynamic>> checkForUpdates() async {
    try {
      print('🔍 Verificando actualizaciones disponibles...');
      
      // Obtener información de la versión actual
      final currentInfo = await getCurrentVersionInfo();
      final String appName = currentInfo['app_name'];
      final String currentVersion = currentInfo['current_version'];
      final int currentBuild = currentInfo['build'];
      
      print('📱 Versión actual: $currentVersion (build $currentBuild)');
      
      // Llamar a la función RPC para verificar actualizaciones
      final response = await _supabase.rpc('fn_check_update', params: {
        'p_app_name': appName,
        'p_version_actual': currentVersion,
        'p_build_actual': currentBuild,
      });
      
      print('📊 Respuesta del servidor: $response');
      
      if (response != null) {
        final Map<String, dynamic> updateInfo = response as Map<String, dynamic>;
        
        // Agregar información de la versión actual
        updateInfo['current_version'] = currentVersion;
        updateInfo['current_build'] = currentBuild;
        updateInfo['app_name'] = appName;
        
        if (updateInfo['hay_actualizacion'] == true) {
          print('🆕 Nueva versión disponible: ${updateInfo['version_disponible']}');
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

  /// URL de descarga de la aplicación
  static const String downloadUrl = 'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/inventtia%20caja.apk';
}
