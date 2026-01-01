import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateService {
  static final _supabase = Supabase.instance.client;

  /// Detectar si la aplicación se ejecuta en web
  static bool isWeb() {
    try {
      return !Platform.isAndroid && !Platform.isIOS;
    } catch (e) {
      // En web, Platform.isAndroid y Platform.isIOS lanzan excepción
      return true;
    }
  }

  /// Detectar si la aplicación se ejecuta en APK (Android)
  static bool isAPK() {
    try {
      return Platform.isAndroid;
    } catch (e) {
      return false;
    }
  }

  /// Obtener información de la versión actual desde changelog.json
  static Future<Map<String, dynamic>> getCurrentVersionInfo() async {
    try {
      final String response = await rootBundle.loadString('assets/changelog.json');
      final Map<String, dynamic> data = json.decode(response);
      
      return {
        'app_name': data['app_name'] ?? 'ventiq_admin',
        'current_version': data['current_version'] ?? '1.0.0',
        'build': data['build'] ?? 100,
      };
    } catch (e) {
      print('❌ Error leyendo changelog.json: $e');
      // Valores por defecto en caso de error
      return {
        'app_name': 'ventiq_admin',
        'current_version': '1.0.0',
        'build': 100,
      };
    }
  }

  /// Verificar si hay actualizaciones disponibles
  /// Para APK: Retorna actualización obligatoria si hay cambios
  /// Para Web: Retorna información para mostrar diálogo informativo
  static Future<Map<String, dynamic>> checkForUpdates() async {
    try {
      print('🔍 Verificando actualizaciones disponibles...');
      
      // Obtener información de la versión actual
      final currentInfo = await getCurrentVersionInfo();
      final String appName = currentInfo['app_name'];
      final String currentVersion = currentInfo['current_version'];
      final int currentBuild = currentInfo['build'];
      
      print('📱 Versión actual: $currentVersion (build $currentBuild)');
      print('🌐 Plataforma: ${isWeb() ? 'WEB' : 'APK'}');
      
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
        updateInfo['is_web'] = isWeb();
        updateInfo['is_apk'] = isAPK();
        
        if (updateInfo['hay_actualizacion'] == true) {
          print('🆕 Nueva versión disponible: ${updateInfo['version_disponible']}');
          
          if (isWeb()) {
            // Para WEB: Mostrar como informativo (no obligatorio)
            print('ℹ️ En WEB: Mostrar diálogo informativo para limpiar cache');
            updateInfo['obligatoria'] = false;
            updateInfo['es_web'] = true;
          } else if (isAPK()) {
            // Para APK: Mantener como obligatorio
            print('⚠️ En APK: Actualización obligatoria');
            updateInfo['obligatoria'] = true;
            updateInfo['es_apk'] = true;
          }
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

  /// URL de descarga de la aplicación admin
  static const String downloadUrl = 'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/vendedor%20admin.apk';
}
