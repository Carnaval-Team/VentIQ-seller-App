import 'user_preferences_service.dart';

class StoreService {
  static final _userPreferencesService = UserPreferencesService();

  // Obtener ID de la tienda actual
  static Future<int?> getCurrentStoreId() async {
    try {
      return await _userPreferencesService.getIdTienda();
    } catch (e) {
      print('❌ Error obteniendo store ID: $e');
      return null;
    }
  }

  // Obtener nombre de la tienda actual
  static Future<String?> getCurrentStoreName() async {
    try {
      final storeInfo = await _userPreferencesService.getCurrentStoreInfo();
      return storeInfo?['denominacion'] as String?;
    } catch (e) {
      print('❌ Error obteniendo store name: $e');
      return null;
    }
  }

  // Obtener UUID del usuario actual
  static Future<String?> getCurrentUserUuid() async {
    try {
      return await _userPreferencesService.getUserId();
    } catch (e) {
      print('❌ Error obteniendo user UUID: $e');
      return null;
    }
  }

  // Guardar datos de la tienda actual (actualizar tienda seleccionada)
  static Future<void> setCurrentStore(int storeId, String storeName) async {
    try {
      await _userPreferencesService.updateSelectedStore(storeId);
      print('✅ Store data updated: ID=$storeId, Name=$storeName');
    } catch (e) {
      print('❌ Error actualizando store data: $e');
    }
  }

  // Guardar UUID del usuario actual (no necesario, se maneja en login)
  static Future<void> setCurrentUserUuid(String userUuid) async {
    // Este método ya no es necesario porque el UUID se guarda durante el login
    print('ℹ️ User UUID is managed by UserPreferencesService during login');
  }

  // Limpiar datos almacenados
  static Future<void> clearStoredData() async {
    try {
      await _userPreferencesService.clearUserData();
      print('✅ Store data cleared');
    } catch (e) {
      print('❌ Error limpiando store data: $e');
    }
  }

  // Verificar si hay datos de tienda guardados
  static Future<bool> hasStoredData() async {
    try {
      final storeId = await getCurrentStoreId();
      final userUuid = await getCurrentUserUuid();
      return storeId != null && userUuid != null;
    } catch (e) {
      print('❌ Error verificando stored data: $e');
      return false;
    }
  }

  // Obtener todos los datos necesarios para trabajadores
  static Future<Map<String, dynamic>?> getWorkerRequiredData() async {
    try {
      final storeId = await getCurrentStoreId();
      final userUuid = await getCurrentUserUuid();
      final storeName = await getCurrentStoreName();

      print('🔍 Obteniendo datos requeridos:');
      print('  - Store ID: $storeId');
      print('  - User UUID: $userUuid');
      print('  - Store Name: $storeName');

      if (storeId == null || userUuid == null) {
        print('❌ Faltan datos requeridos: storeId=$storeId, userUuid=$userUuid');
        return null;
      }

      return {
        'storeId': storeId,
        'userUuid': userUuid,
        'storeName': storeName ?? 'Tienda',
      };
    } catch (e) {
      print('❌ Error obteniendo worker required data: $e');
      return null;
    }
  }

  // Obtener información completa del usuario y tienda
  static Future<Map<String, dynamic>?> getUserAndStoreInfo() async {
    try {
      final userData = await _userPreferencesService.getUserData();
      final storeInfo = await _userPreferencesService.getCurrentStoreInfo();
      
      return {
        'user': userData,
        'store': storeInfo,
      };
    } catch (e) {
      print('❌ Error obteniendo user and store info: $e');
      return null;
    }
  }
}
