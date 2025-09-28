import 'package:supabase_flutter/supabase_flutter.dart';

class StoreRegistrationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Registra un nuevo usuario en Supabase Auth
  Future<Map<String, dynamic>> registerUser({
    required String email,
    required String password,
    required String fullName,
  }) async {
    try {
      print('🔐 Registrando usuario en Supabase Auth...');
      
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'email_confirm': true,
          'full_name': fullName,
          
        },
      );

      if (response.user == null) {
        throw Exception('Error al crear usuario: Usuario nulo en respuesta');
      }

      print('✅ Usuario registrado exitosamente:');
      print('  - ID: ${response.user!.id}');
      print('  - Email: ${response.user!.email}');
      print('  - Confirmado: ${response.user!.emailConfirmedAt != null}');

      return {
        'success': true,
        'user': response.user,
        'session': response.session,
        'message': 'Usuario registrado exitosamente',
      };
    } catch (e) {
      print('❌ Error registrando usuario: $e');
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error al registrar usuario: $e',
      };
    }
  }

  /// Crea la estructura completa de la tienda usando la función RPC
  Future<Map<String, dynamic>> createStoreStructure({
    required String usuarioCreador, // UUID del usuario creador
    required String denominacionTienda,
    required String direccionTienda,
    required String ubicacionTienda,
    List<Map<String, dynamic>>? tpvData,
    List<Map<String, dynamic>>? almacenesData,
    List<Map<String, dynamic>>? layoutsData,
    List<Map<String, dynamic>>? personalData,
  }) async {
    try {
      print('🏪 Creando estructura de tienda...');
      print('  - Usuario creador: $usuarioCreador');
      print('  - Denominación: $denominacionTienda');
      print('  - Dirección: $direccionTienda');
      print('  - Ubicación: $ubicacionTienda');

      // Preparar parámetros para la función RPC (orden correcto: almacenes primero)
      final params = {
        'usuario_creador': usuarioCreador,
        'denominacion_tienda': denominacionTienda,
        'direccion_tienda': direccionTienda,
        'ubicacion_tienda': ubicacionTienda,
        'almacenes_data': almacenesData, // Almacenes PRIMERO
        'tpv_data': tpvData,             // TPVs después (necesitan id_almacen)
        'personal_data': personalData,   // Personal después (necesitan id_almacen/id_tpv)
        'layouts_data': layoutsData,     // Layouts al final
      };

      print('📋 Parámetros enviados a RPC:');
      params.forEach((key, value) {
        if (value is List) {
          print('  - $key: ${value.length} elementos');
        } else {
          print('  - $key: $value');
        }
      });

      // Llamar a la función RPC para crear la estructura completa
      final response = await _supabase.rpc(
        'crear_estructura_tienda',
        params: params,
      );

      print('📦 Respuesta de RPC: $response');

      if (response == null) {
        throw Exception('Respuesta nula del servidor');
      }

      // La función RPC retorna un JSONB con la estructura del resultado
      final result = response as Map<String, dynamic>;

      if (result['success'] == true) {
        print('✅ Estructura de tienda creada exitosamente');
        print('  - Tienda ID: ${result['data']?['tienda_id']}');
        
        if (result['data']?['tpvs_creados'] != null) {
          print('  - TPVs creados: ${result['data']['tpvs_creados']}');
        }
        
        if (result['data']?['almacenes_creados'] != null) {
          print('  - Almacenes creados: ${result['data']['almacenes_creados']}');
        }
        
        if (result['data']?['personal_creado'] != null) {
          print('  - Personal creado: ${result['data']['personal_creado']}');
        }

        return {
          'success': true,
          'data': result['data'],
          'message': result['message'] ?? 'Tienda creada exitosamente',
        };
      } else {
        print('❌ Error en creación de tienda: ${result['message']}');
        return {
          'success': false,
          'error': result['message'] ?? 'Error desconocido',
          'error_code': result['error_code'],
        };
      }
    } catch (e) {
      print('❌ Error llamando a RPC fn_crear_estructura_tienda_completa: $e');
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error al crear estructura de tienda: $e',
      };
    }
  }

  /// Proceso completo: registrar usuario y crear tienda
  Future<Map<String, dynamic>> registerUserAndCreateStore({
    required String email,
    required String password,
    required String fullName,
    required String denominacionTienda,
    required String direccionTienda,
    required String ubicacionTienda,
    List<Map<String, dynamic>>? tpvData,
    List<Map<String, dynamic>>? almacenesData,
    List<Map<String, dynamic>>? layoutsData,
    List<Map<String, dynamic>>? personalData,
  }) async {
    try {
      print('🚀 Iniciando proceso completo de registro...');

      // Paso 1: Registrar usuario
      final userResult = await registerUser(
        email: email,
        password: password,
        fullName: fullName,
      );

      if (!userResult['success']) {
        return userResult; // Retornar error del registro de usuario
      }

      final user = userResult['user'] as User;

      // Reemplazar placeholder UUID en personalData con el UUID real del usuario
      List<Map<String, dynamic>>? updatedPersonalData;
      if (personalData != null) {
        updatedPersonalData = personalData.map((personal) {
          final updatedPersonal = Map<String, dynamic>.from(personal);
          if (updatedPersonal['uuid'] == 'PLACEHOLDER_USER_UUID') {
            updatedPersonal['uuid'] = user.id;
          }
          return updatedPersonal;
        }).toList();
      }

      // Paso 2: Crear estructura de tienda
      final storeResult = await createStoreStructure(
        usuarioCreador: user.id,
        denominacionTienda: denominacionTienda,
        direccionTienda: direccionTienda,
        ubicacionTienda: ubicacionTienda,
        tpvData: tpvData,
        almacenesData: almacenesData,
        layoutsData: layoutsData,
        personalData: updatedPersonalData,
      );

      if (!storeResult['success']) {
        print('⚠️ Error creando tienda, pero usuario ya fue registrado');
        return {
          'success': false,
          'error': storeResult['error'],
          'message': 'Usuario registrado pero error al crear tienda: ${storeResult['error']}',
          'user_created': true,
          'user_id': user.id,
        };
      }

      print('🎉 Proceso completo exitoso!');
      return {
        'success': true,
        'user': user,
        'store_data': storeResult['data'],
        'message': 'Usuario y tienda creados exitosamente',
      };
    } catch (e) {
      print('❌ Error en proceso completo: $e');
      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error en el proceso de registro: $e',
      };
    }
  }

  /// Obtiene los roles disponibles para asignar personal
  Future<List<Map<String, dynamic>>> getRoles() async {
    try {
      final response = await _supabase
          .from('app_nom_roll')
          .select('id, denominacion, descripcion')
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo roles: $e');
      return [];
    }
  }

  /// Obtiene los tipos de layout disponibles
  Future<List<Map<String, dynamic>>> getLayoutTypes() async {
    try {
      final response = await _supabase
          .from('app_nom_tipo_layout')
          .select('id, denominacion, descripcion')
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo tipos de layout: $e');
      return [];
    }
  }
}
