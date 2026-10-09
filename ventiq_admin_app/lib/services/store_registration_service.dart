import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'subscription_service.dart';

class StoreRegistrationService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final SubscriptionService _subscriptionService = SubscriptionService();

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
          'full_name': fullName,
        },
        emailRedirectTo: null, // No redirigir, confirmar automáticamente
      );

      if (response.user == null) {
        throw Exception('Error al crear usuario: Usuario nulo en respuesta');
      }

      // Con protección contra enumeración de emails, el servidor puede
      // devolver un usuario "fantasma" (sin identities) si el email ya existe.
      if (response.user!.identities != null &&
          response.user!.identities!.isEmpty) {
        throw Exception('User already registered');
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

      // Manejar caso específico de usuario ya existente
      if (e.toString().contains('user_already_exists') ||
          e.toString().contains('User already registered')) {
        print(
          '⚠️ Usuario ya existe, intentando obtener información del usuario existente...',
        );

        try {
          // Intentar hacer login para obtener el usuario existente
          final loginResponse = await _supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (loginResponse.user != null) {
            print('✅ Usuario existente autenticado exitosamente:');
            print('  - ID: ${loginResponse.user!.id}');
            print('  - Email: ${loginResponse.user!.email}');
            print('  - Nota: Usuario ya existía en el sistema');

            return {
              'success': true,
              'user': loginResponse.user,
              'session': loginResponse.session,
              'message': 'Usuario ya existía, continuando con el proceso',
              'user_already_existed': true,
            };
          }
        } catch (loginError) {
          print('❌ Error al autenticar usuario existente: $loginError');
          return {
            'success': false,
            'error':
                'Usuario ya existe pero no se pudo autenticar con las credenciales proporcionadas',
            'message':
                'El email ya está registrado. Verifica la contraseña o usa otro email.',
          };
        }
      }

      return {
        'success': false,
        'error': e.toString(),
        'message': 'Error al registrar usuario: $e',
      };
    }
  }

  /// Crea o vincula un usuario de acceso sin perder la sesión del creador.
  ///
  /// `signUp` / `signInWithPassword` del SDK de cliente reemplazan la sesión
  /// activa, por eso se guarda y restaura al terminar.
  ///
  /// Lanza si el usuario no pudo crearse ni verificarse.
  Future<({String uuid, bool alreadyExisted})> resolveAccessUser({
    required String email,
    required String password,
    required String nombres,
    required String apellidos,
  }) async {
    final adminSession = _supabase.auth.currentSession;
    final adminUserId = adminSession?.user.id;
    final adminSessionJson =
        adminSession == null ? null : jsonEncode(adminSession.toJson());

    String? userUuid;
    var alreadyExisted = false;

    try {
      print('🔐 Resolviendo usuario de acceso para $email ...');

      try {
        final authResponse = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'nombres': nombres,
            'apellidos': apellidos,
            'full_name': '$nombres $apellidos',
          },
          emailRedirectTo: null,
        );

        final user = authResponse.user;
        if (user == null) {
          throw Exception('Error al registrar usuario en Supabase Auth');
        }

        if (user.identities != null && user.identities!.isEmpty) {
          throw StateError('user_already_exists');
        }

        userUuid = user.id;
        print('✅ Usuario registrado con UUID: $userUuid');
      } catch (signUpError) {
        final msg = signUpError.toString();
        final yaExiste =
            msg.contains('user_already_exists') ||
            msg.contains('User already registered');

        if (!yaExiste) rethrow;

        print(
          '⚠️ Usuario ya existe, verificando credenciales para vincular...',
        );

        try {
          final loginResponse = await _supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (loginResponse.user == null) {
            throw Exception(
              'No se pudo obtener el UUID del usuario existente',
            );
          }

          userUuid = loginResponse.user!.id;
          alreadyExisted = true;
          print('✅ Usuario existente verificado con UUID: $userUuid');
        } catch (loginError) {
          print('❌ Error al autenticar usuario existente: $loginError');
          throw Exception(
            'El email $email ya está registrado pero las credenciales no coinciden. '
            'Verifica la contraseña del trabajador.',
          );
        }
      }
    } finally {
      if (adminSessionJson != null && adminUserId != null) {
        try {
          final currentUserId = _supabase.auth.currentSession?.user.id;
          if (currentUserId != adminUserId) {
            await _supabase.auth.recoverSession(adminSessionJson);
            print('🔄 Sesión del usuario creador restaurada');
          }
        } catch (e) {
          print('⚠️ No se pudo restaurar la sesión del usuario creador: $e');
        }
      }
    }

    final resolvedUuid = userUuid ?? '';
    if (resolvedUuid.isEmpty) {
      throw Exception(
        'No se pudo crear ni verificar el usuario de acceso para $email',
      );
    }

    return (uuid: resolvedUuid, alreadyExisted: alreadyExisted);
  }

  /// Crea la estructura completa de la tienda usando la función RPC
  Future<Map<String, dynamic>> createStoreStructure({
    required String usuarioCreador, // UUID del usuario creador
    required String denominacionTienda,
    required String direccionTienda,
    required String ubicacionTienda,
    String? pais,
    String? estado,
    String? nombrePais,
    String? nombreEstado,
    double? latitude,
    double? longitude,
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
      print('  - País: $pais ($nombrePais)');
      print('  - Estado: $estado ($nombreEstado)');
      print('  - Coordenadas: Lat $latitude, Lng $longitude');

      // Preparar parámetros para la función RPC (orden correcto: almacenes primero)
      final params = {
        'usuario_creador': usuarioCreador,
        'denominacion_tienda': denominacionTienda,
        'direccion_tienda': direccionTienda,
        'ubicacion_tienda': ubicacionTienda,
        'pais': pais,
        'estado': estado,
        'nombre_pais': nombrePais,
        'nombre_estado': nombreEstado,
        'latitude': latitude,
        'longitude': longitude,
        'almacenes_data': almacenesData, // Almacenes PRIMERO
        'tpv_data': tpvData, // TPVs después (necesitan id_almacen)
        'personal_data': personalData, // Personal después (necesitan id_almacen/id_tpv)
        'layouts_data': layoutsData, // Layouts al final
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
    String? pais,
    String? estado,
    String? nombrePais,
    String? nombreEstado,
    double? latitude,
    double? longitude,
    List<Map<String, dynamic>>? tpvData,
    List<Map<String, dynamic>>? almacenesData,
    List<Map<String, dynamic>>? layoutsData,
    List<Map<String, dynamic>>? personalData,
  }) async {
    try {
      print('🚀 Iniciando proceso completo de registro...');

      // Paso 1: Registrar usuario principal
      final userResult = await registerUser(
        email: email,
        password: password,
        fullName: fullName,
      );

      if (userResult['success'] != true) {
        return userResult;
      }

      final user = userResult['user'] as User?;
      if (user == null) {
        return {
          'success': false,
          'error': 'Usuario principal nulo tras el registro',
          'message':
              'No se pudo verificar la creación del usuario principal. El proceso se detuvo.',
        };
      }

      final userAlreadyExisted = userResult['user_already_existed'] == true;

      if (userAlreadyExisted) {
        print('ℹ️ Nota: El usuario con email $email ya existía en el sistema');
      }

      // Paso 2: Crear/verificar usuarios Auth de trabajadores adicionales
      // ANTES de crear la tienda. Antes se reemplazaba PLACEHOLDER_USER_UUID
      // con el UUID del principal, por lo que nunca se creaban cuentas reales.
      List<Map<String, dynamic>>? updatedPersonalData;
      if (personalData != null) {
        updatedPersonalData = [];

        for (final personal in personalData) {
          final updatedPersonal = Map<String, dynamic>.from(personal);
          final isMainUser = updatedPersonal['is_main_user'] == true;
          final uuidMarker = (updatedPersonal['uuid'] ?? '').toString();
          final workerEmail = (updatedPersonal['email'] ?? '').toString().trim();
          final workerPassword =
              (updatedPersonal['password'] ?? '').toString();
          final nombres = (updatedPersonal['nombres'] ?? '').toString().trim();
          final apellidos =
              (updatedPersonal['apellidos'] ?? '').toString().trim();
          final rol = (updatedPersonal['tipo_rol'] ?? '').toString();

          if (isMainUser || uuidMarker == 'MAIN_USER_UUID') {
            updatedPersonal['uuid'] = user.id;
            print(
              '🔄 UUID principal asignado a $nombres $apellidos ($rol)',
            );
          } else if (uuidMarker == 'PLACEHOLDER_USER_UUID' ||
              uuidMarker.isEmpty) {
            if (workerEmail.isEmpty || workerPassword.isEmpty) {
              return {
                'success': false,
                'error': 'Credenciales incompletas',
                'message':
                    'El trabajador $nombres $apellidos no tiene email/contraseña. '
                    'No se creó la tienda.',
                'user_created': true,
                'user_id': user.id,
              };
            }

            if (workerEmail.toLowerCase() == email.trim().toLowerCase()) {
              // Mismo email que el principal: reutilizar su UUID
              updatedPersonal['uuid'] = user.id;
              print(
                '🔄 Trabajador adicional con mismo email del principal → UUID principal',
              );
            } else {
              try {
                final resolved = await resolveAccessUser(
                  email: workerEmail,
                  password: workerPassword,
                  nombres: nombres.isEmpty ? 'Trabajador' : nombres,
                  apellidos: apellidos.isEmpty ? rol : apellidos,
                );
                updatedPersonal['uuid'] = resolved.uuid;
                print(
                  '✅ Usuario Auth OK para $nombres $apellidos ($rol) → ${resolved.uuid}'
                  '${resolved.alreadyExisted ? ' (ya existía)' : ''}',
                );
              } catch (e) {
                print('❌ Falló creación de usuario para $workerEmail: $e');
                return {
                  'success': false,
                  'error': e.toString(),
                  'message':
                      'No se pudo crear el usuario de acceso para '
                      '$nombres $apellidos ($workerEmail): $e\n\n'
                      'El proceso se detuvo antes de crear la tienda.',
                  'user_created': true,
                  'user_id': user.id,
                };
              }
            }
          }

          // No enviar contraseñas al RPC
          updatedPersonal.remove('password');
          updatedPersonalData.add(updatedPersonal);
        }

        // Verificación final: ningún placeholder debe quedar
        final unresolved = updatedPersonalData.where((p) {
          final uuid = (p['uuid'] ?? '').toString();
          return uuid.isEmpty ||
              uuid == 'PLACEHOLDER_USER_UUID' ||
              uuid == 'MAIN_USER_UUID';
        }).toList();

        if (unresolved.isNotEmpty) {
          final names = unresolved
              .map((p) => '${p['nombres']} ${p['apellidos']}')
              .join(', ');
          return {
            'success': false,
            'error': 'UUIDs sin resolver',
            'message':
                'No se pudo verificar el usuario Auth de: $names. '
                'El proceso se detuvo antes de crear la tienda.',
            'user_created': true,
            'user_id': user.id,
          };
        }

        print('👥 Personal listo con UUIDs reales:');
        for (final personal in updatedPersonalData) {
          print(
            '  - ${personal['nombres']} ${personal['apellidos']} '
            '(${personal['tipo_rol']}) → UUID: ${personal['uuid']}',
          );
        }
      }

      // Paso 3: Crear estructura de tienda
      final storeResult = await createStoreStructure(
        usuarioCreador: user.id,
        denominacionTienda: denominacionTienda,
        direccionTienda: direccionTienda,
        ubicacionTienda: ubicacionTienda,
        pais: pais,
        estado: estado,
        nombrePais: nombrePais,
        nombreEstado: nombreEstado,
        latitude: latitude,
        longitude: longitude,
        tpvData: tpvData,
        almacenesData: almacenesData,
        layoutsData: layoutsData,
        personalData: updatedPersonalData,
      );

      if (storeResult['success'] != true) {
        print('⚠️ Error creando tienda, pero usuario ya fue registrado');
        return {
          'success': false,
          'error': storeResult['error'],
          'message':
              'Usuario registrado pero error al crear tienda: ${storeResult['error']}',
          'user_created': true,
          'user_id': user.id,
        };
      }

      // Paso 4: Crear suscripción por defecto con plan ID 1
      final tiendaId = storeResult['data']?['tienda_id'];
      if (tiendaId != null) {
        print('📋 Creando suscripción por defecto para tienda ID: $tiendaId');
        try {
          final subscription =
              await _subscriptionService.createDefaultSubscription(
            tiendaId,
            user.id,
          );

          if (subscription != null) {
            print('✅ Suscripción por defecto creada exitosamente');
            print('  - Plan: ${subscription.planDenominacion}');
            print('  - Estado: ${subscription.estadoText}');
          } else {
            print(
              '⚠️ No se pudo crear la suscripción por defecto, pero la tienda fue creada',
            );
          }
        } catch (e) {
          print('❌ Error creando suscripción por defecto: $e');
          // No fallar el proceso completo por error de suscripción
        }
      } else {
        print('⚠️ No se pudo obtener ID de tienda para crear suscripción');
      }

      print('🎉 Proceso completo exitoso!');

      final successMessage = userAlreadyExisted
          ? 'Usuario existente autenticado y tienda creada exitosamente'
          : 'Usuario y tienda creados exitosamente';

      return {
        'success': true,
        'user': user,
        'store_data': storeResult['data'],
        'message': successMessage,
        'user_already_existed': userAlreadyExisted,
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
