import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'store_service.dart';
import 'user_preferences_service.dart';

class CarnavalService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene la información de la tienda actual
  static Future<Map<String, dynamic>?> getStoreInfo(int storeId) async {
    try {
      print('🔍 Obteniendo información de tienda ID: $storeId');

      final response =
          await _supabase
              .from('app_dat_tienda')
              .select('*')
              .eq('id', storeId)
              .maybeSingle();

      if (response != null) {
        print('✅ Información de tienda obtenida');
        return response;
      }

      print('⚠️ No se encontró la tienda');
      return null;
    } catch (e) {
      print('❌ Error al obtener información de tienda: $e');
      rethrow;
    }
  }

  /// Verifica si la tienda está sincronizada con Carnaval
  static Future<bool> isStoreSyncedWithCarnaval(int storeId) async {
    try {
      final storeInfo = await getStoreInfo(storeId);
      return storeInfo?['admin_carnaval'] == true;
    } catch (e) {
      print('❌ Error al verificar sincronización con Carnaval: $e');
      return false;
    }
  }

  /// Obtiene el ID de la tienda en Carnaval
  static Future<int?> getCarnavalStoreId(int storeId) async {
    try {
      final storeInfo = await getStoreInfo(storeId);
      return storeInfo?['id_tienda_carnaval'];
    } catch (e) {
      print('❌ Error al obtener ID de tienda en Carnaval: $e');
      return null;
    }
  }

  /// Obtiene la cantidad de productos sincronizados en Carnaval
  static Future<int> getSyncedProductsCount(int carnavalStoreId) async {
    try {
      print(
        '🔍 Obteniendo productos sincronizados para proveedor ID: $carnavalStoreId',
      );

      final response = await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .select('id')
          .eq('proveedor', carnavalStoreId);

      final count = response.length;
      print('✅ Productos sincronizados: $count');
      return count;
    } catch (e) {
      print('❌ Error al obtener productos sincronizados: $e');
      return 0;
    }
  }

  /// Obtiene información del proveedor en Carnaval
  static Future<Map<String, dynamic>?> getCarnavalProviderInfo(
    int carnavalStoreId,
  ) async {
    try {
      print(
        '🔍 Obteniendo información del proveedor en Carnaval ID: $carnavalStoreId',
      );

      final response =
          await _supabase
              .schema('carnavalapp')
              .from('proveedores')
              .select('*')
              .eq('id', carnavalStoreId)
              .maybeSingle();

      if (response != null) {
        print('✅ Información del proveedor obtenida');
        return response;
      }

      print('⚠️ No se encontró el proveedor en Carnaval');
      return null;
    } catch (e) {
      print('❌ Error al obtener información del proveedor: $e');
      return null;
    }
  }

  /// Valida que la tienda tenga todos los datos necesarios para sincronizar
  static Future<Map<String, dynamic>> validateStoreData(int storeId) async {
    try {
      final storeInfo = await getStoreInfo(storeId);

      if (storeInfo == null) {
        return {
          'isValid': false,
          'missingFields': ['Tienda no encontrada'],
        };
      }

      final missingFields = <String>[];

      // Validar campos obligatorios para carnavalapp.proveedores
      // denominacion → name (obligatorio)
      if (storeInfo['denominacion'] == null ||
          storeInfo['denominacion'].toString().isEmpty) {
        missingFields.add('Denominación (nombre de la tienda)');
      }

      // imagen_url → logo (obligatorio)
      if (storeInfo['imagen_url'] == null ||
          storeInfo['imagen_url'].toString().isEmpty) {
        missingFields.add('Foto de la tienda (logo)');
      }

      // Campos opcionales pero recomendados:
      // - direccion
      // - ubicacion
      // - phone → contacto

      return {
        'isValid': missingFields.isEmpty,
        'missingFields': missingFields,
        'storeInfo': storeInfo,
      };
    } catch (e) {
      print('❌ Error al validar datos de tienda: $e');
      return {
        'isValid': false,
        'missingFields': ['Error al validar: $e'],
      };
    }
  }

  /// Obtiene o crea el usuario admin en carnavalapp.Usuarios
  /// Flujo: UUID del usuario actual → app_dat_supervisor → app_dat_trabajadores → carnavalapp.Usuarios
  static Future<int?> getOrCreateCarnavalAdmin(
    int storeId,
    String currentUserUuid,
  ) async {
    try {
      print(
        '🔍 Buscando admin para tienda ID: $storeId, UUID: $currentUserUuid',
      );

      // 1. Buscar en app_dat_supervisor por uuid y id_tienda para obtener id_trabajador
      final supervisorData =
          await _supabase
              .from('app_dat_gerente')
              .select('id_trabajador')
              .eq('uuid', currentUserUuid)
              .eq('id_tienda', storeId)
              .maybeSingle();

      if (supervisorData == null || supervisorData['id_trabajador'] == null) {
        print('⚠️ No se encontró supervisor para este usuario en esta tienda');
        return null;
      }

      final idTrabajador = supervisorData['id_trabajador'] as int;
      print('✅ ID Trabajador encontrado: $idTrabajador');

      // 2. Buscar datos del trabajador en app_dat_trabajadores
      final trabajadorData =
          await _supabase
              .from('app_dat_trabajadores')
              .select('id, nombres, apellidos, uuid')
              .eq('id', idTrabajador)
              .maybeSingle();

      if (trabajadorData == null) {
        print('⚠️ No se encontró el trabajador con ID: $idTrabajador');
        return null;
      }

      print(
        '✅ Datos del trabajador obtenidos: ${trabajadorData['nombres']} ${trabajadorData['apellidos']}',
      );

      final trabajadorUuid = trabajadorData['uuid'] as String;

      // 3. Obtener email del usuario desde preferencias
      String email = '';
      try {
        final data = await UserPreferencesService().getUserData();
        email = data['email'] ?? '';
      } catch (e) {
        print('⚠️ No se pudo obtener email del usuario: $e');
        // Continuar sin email
      }

      // 4. Verificar si ya existe el usuario en carnavalapp.Usuarios
      final existingUser =
          await _supabase
              .schema('carnavalapp')
              .from('Usuarios')
              .select('id')
              .eq('uuid', trabajadorUuid)
              .maybeSingle();

      if (existingUser != null) {
        final userId = existingUser['id'] as int;
        print('✅ Usuario ya existe en carnavalapp.Usuarios con ID: $userId');
        return userId;
      }

      // 5. Crear usuario en carnavalapp.Usuarios
      print('🔧 Creando usuario en carnavalapp.Usuarios...');

      final newUserData = {
        'uuid': trabajadorUuid,
        'email': email,
        'name':
            '${trabajadorData['nombres'] ?? ''} ${trabajadorData['apellidos'] ?? ''}'
                .trim(),
        'rol': 'Admin', // Rol para administradores de tienda
        'email_confirmacion': true,
        // tienda se asignará después cuando se cree el proveedor
      };

      final newUser =
          await _supabase
              .schema('carnavalapp')
              .from('Usuarios')
              .insert(newUserData)
              .select('id')
              .single();

      final newUserId = newUser['id'] as int;
      print('✅ Usuario creado en carnavalapp.Usuarios con ID: $newUserId');

      return newUserId;
    } catch (e) {
      print('❌ Error al obtener/crear admin en Carnaval: $e');
      // No lanzar error, solo retornar null para que el proveedor se cree sin admin
      return null;
    }
  }

  /// Crea un proveedor en Carnaval App
  static Future<Map<String, dynamic>?> createCarnavalProvider(
    int storeId,
  ) async {
    try {
      print('🔧 Creando proveedor en Carnaval para tienda ID: $storeId');

      // Primero validar que la tienda tenga todos los datos necesarios
      final validation = await validateStoreData(storeId);

      if (validation['isValid'] != true) {
        throw Exception(
          'La tienda no tiene todos los datos necesarios: ${validation['missingFields'].join(', ')}',
        );
      }

      final storeInfo = validation['storeInfo'] as Map<String, dynamic>;

      // Obtener UUID del usuario actual para crear/obtener el admin
      final currentUserUuid = await StoreService.getCurrentUserUuid();
      int? adminId;

      if (currentUserUuid != null) {
        print('🔍 Obteniendo o creando admin en carnavalapp.Usuarios...');
        adminId = await getOrCreateCarnavalAdmin(storeId, currentUserUuid);
        if (adminId != null) {
          print('✅ Admin ID obtenido: $adminId');
        } else {
          print(
            '⚠️ No se pudo obtener admin ID, el proveedor se creará sin admin',
          );
        }
      } else {
        print('⚠️ No se pudo obtener UUID del usuario actual');
      }

      // Crear el proveedor en carnavalapp.proveedores
      // Mapeo correcto de campos según esquemas:
      // app_dat_tienda.denominacion → carnavalapp.proveedores.name
      // app_dat_tienda.imagen_url → carnavalapp.proveedores.logo
      // app_dat_tienda.phone → carnavalapp.proveedores.contacto
      final providerData = {
        'name': storeInfo['denominacion'],
        'logo': storeInfo['imagen_url'],
        'direccion': storeInfo['direccion'],
        'ubicacion': storeInfo['ubicacion'],
        'contacto':
            storeInfo['phone'] != null
                ? num.tryParse(storeInfo['phone'].toString())
                : null,
        'status': true,
        'es_alimento': false,
        'banner': storeInfo['imagen_url'],
        'admin': adminId, // ID del usuario admin en carnavalapp.Usuarios
        // Campos opcionales que pueden agregarse después:
        // 'descripcion': storeInfo['descripcion'],
        // 'orden': storeInfo['orden'],
        // 'categoria': storeInfo['categoria'],
        // 'chat_id': storeInfo['chat_id'],
      };

      final response =
          await _supabase
              .schema('carnavalapp')
              .from('proveedores')
              .insert(providerData)
              .select()
              .single();

      final carnavalProviderId = response['id'];
      print('✅ Proveedor creado en Carnaval con ID: $carnavalProviderId');

      // Actualizar el campo 'tienda' del usuario admin en carnavalapp.Usuarios
      if (adminId != null) {
        try {
          await _supabase
              .schema('carnavalapp')
              .from('Usuarios')
              .update({'tienda': carnavalProviderId})
              .eq('id', adminId);
          print(
            '✅ Usuario admin actualizado con tienda ID: $carnavalProviderId',
          );
        } catch (e) {
          print('⚠️ Error al actualizar tienda del usuario admin: $e');
          // No lanzar error, el proveedor ya está creado
        }
      }

      // Actualizar app_dat_tienda con el ID del proveedor en Carnaval
      await _supabase
          .from('app_dat_tienda')
          .update({
            'admin_carnaval': true,
            'id_tienda_carnaval': carnavalProviderId,
          })
          .eq('id', storeId);

      print('✅ Tienda actualizada con información de Carnaval');

      return response;
    } catch (e) {
      print('❌ Error al crear proveedor en Carnaval: $e');
      rethrow;
    }
  }

  /// Desincroniza la tienda de Carnaval, eliminando productos, relaciones y proveedor.
  /// Lanza una excepción con mensaje descriptivo si no se puede desvincular.
  static Future<void> unsyncStoreFromCarnaval(int storeId) async {
    try {
      print('🔧 Desincronizando tienda ID: $storeId de Carnaval');

      // 1. Obtener el id_tienda_carnaval (proveedor en carnavalapp)
      final storeData = await _supabase
          .from('app_dat_tienda')
          .select('id_tienda_carnaval')
          .eq('id', storeId)
          .single();

      final carnavalStoreId = storeData['id_tienda_carnaval'];

      if (carnavalStoreId != null) {
        // 2. Obtener relaciones de productos de esta tienda
        final relations = await _supabase
            .from('relation_products_carnaval')
            .select('id, id_producto, id_producto_carnaval')
            .inFilter(
              'id_producto',
              (await _supabase
                      .from('app_dat_producto')
                      .select('id')
                      .eq('id_tienda', storeId))
                  .map((p) => p['id'])
                  .toList(),
            );

        final relationList = List<Map<String, dynamic>>.from(relations);

        if (relationList.isNotEmpty) {
          final carnavalProductIds =
              relationList.map((r) => r['id_producto_carnaval']).toList();
          final relationIds = relationList.map((r) => r['id']).toList();
          final localProductIds =
              relationList.map((r) => r['id_producto']).toList();

          // 3. Eliminar productos de carnavalapp.Productos
          await _supabase
              .schema('carnavalapp')
              .from('Productos')
              .delete()
              .inFilter('id', carnavalProductIds);

          print('✅ Eliminados ${carnavalProductIds.length} productos de Carnaval');

          // 4. Eliminar relaciones
          await _supabase
              .from('relation_products_carnaval')
              .delete()
              .inFilter('id', relationIds);

          print('✅ Eliminadas ${relationIds.length} relaciones');

          // 5. Limpiar id_vendedor_app en productos locales
          await _supabase
              .from('app_dat_producto')
              .update({'id_vendedor_app': null})
              .inFilter('id', localProductIds);

          print('✅ Limpiado id_vendedor_app de productos locales');
        }

        // 6. Eliminar proveedor de carnavalapp.Proveedores
        try {
          await _supabase
              .schema('carnavalapp')
              .from('Proveedores')
              .delete()
              .eq('id', carnavalStoreId);

          print('✅ Proveedor $carnavalStoreId eliminado de Carnaval');
        } catch (e) {
          print('❌ No se pudo eliminar el proveedor: $e');
          throw Exception(
            'No se puede desvincular la tienda porque aún tiene productos, órdenes u otros datos asociados en Carnaval.',
          );
        }
      }

      // 7. Actualizar la tienda
      await _supabase
          .from('app_dat_tienda')
          .update({'admin_carnaval': false, 'id_tienda_carnaval': null})
          .eq('id', storeId);

      print('✅ Tienda desincronizada de Carnaval');
    } catch (e) {
      print('❌ Error al desincronizar tienda: $e');
      rethrow;
    }
  }

  /// Sube una imagen de tienda al bucket de Supabase Storage
  static Future<String?> uploadStoreImage(
    Uint8List imageBytes,
    String fileName,
  ) async {
    try {
      print('📤 Subiendo imagen de tienda: $fileName');

      // Generar nombre único para evitar conflictos
      final uniqueFileName =
          'store_${DateTime.now().millisecondsSinceEpoch}_$fileName';

      // Subir imagen al bucket 'images_back' (usando el mismo bucket que categorías)
      final response = await _supabase.storage
          .from('images_back')
          .uploadBinary(
            uniqueFileName,
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true, // Permite sobrescribir si existe
            ),
          );

      if (response.isEmpty) {
        throw Exception('Error al subir imagen');
      }

      // Obtener URL pública de la imagen
      final imageUrl = _supabase.storage
          .from('images_back')
          .getPublicUrl(uniqueFileName);

      print('✅ Imagen de tienda subida exitosamente: $imageUrl');
      return imageUrl;
    } catch (e) {
      print('❌ Error al subir imagen de tienda: $e');
      return null;
    }
  }

  /// Actualiza la información de la tienda
  static Future<bool> updateStoreInfo(
    int storeId,
    Map<String, dynamic> data,
  ) async {
    try {
      print('✏️ Actualizando información de tienda ID: $storeId');
      print('📦 Datos a actualizar: $data');

      await _supabase.from('app_dat_tienda').update(data).eq('id', storeId);

      print('✅ Información de tienda actualizada exitosamente');
      return true;
    } catch (e) {
      print('❌ Error al actualizar información de la tienda: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // PRODUCT SYNCHRONIZATION
  // ---------------------------------------------------------------------------

  /// Obtiene las categorías disponibles en Carnaval App
  static Future<List<Map<String, dynamic>>> getCarnavalCategories() async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Categorias')
          .select('id, name, icon')
          .order('name');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener categorías de Carnaval: $e');
      return [];
    }
  }

  /// Obtiene los productos de la tienda local que aún no están en Carnaval App
  /// Filtra aquellos que no tienen imagen.
  static Future<List<Map<String, dynamic>>> getUnsyncedProducts(
    int storeId,
    int carnavalStoreId,
  ) async {
    try {
      // 1. Obtener productos locales con imagen
      final localProductsResponse = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion, imagen')
          .eq('id_tienda', storeId)
          .neq('imagen', ''); // No debe estar vacía

      final localProducts =
          List<Map<String, dynamic>>.from(
            localProductsResponse,
          ).where((p) => p['imagen'] != null).toList(); // Filtrar nulos en Dart

      // 2. Obtener IDs de productos ya sincronizados via relation_products_carnaval
      final localProductIds = localProducts.map((p) => p['id']).toList();
      final relationResponse = await _supabase
          .from('relation_products_carnaval')
          .select('id_producto')
          .inFilter('id_producto', localProductIds);

      final syncedProductIds =
          List<Map<String, dynamic>>.from(relationResponse)
              .map((r) => r['id_producto'])
              .toSet();

      // 3. Filtrar productos que ya tienen relación
      final unsyncedProducts =
          localProducts.where((p) => !syncedProductIds.contains(p['id'])).toList();

      return unsyncedProducts;
    } catch (e) {
      print('❌ Error al obtener productos no sincronizados: $e');
      return [];
    }
  }

  /// Sincroniza un producto local con Carnaval App
  static Future<bool> syncProductToCarnaval({
    required int localProductId,
    required int carnavalCategoryId,
    required int carnavalStoreId,
    required int idUbicacion,
  }) async {
    try {
      print('comenzando');

      // 0. Verificar que no exista ya una relación para este producto
      final existingRelation = await _supabase
          .from('relation_products_carnaval')
          .select('id')
          .eq('id_producto', localProductId)
          .maybeSingle();

      if (existingRelation != null) {
        print('⚠️ Producto $localProductId ya está sincronizado en Carnaval');
        return false;
      }

      // 1. Obtener datos del producto local
      final productData =
          await _supabase
              .from('app_dat_producto')
              .select('denominacion, descripcion, imagen, id_tienda')
              .eq('id', localProductId)
              .single();

      // 2. Obtener precio actual (el más reciente activo)
      final priceData =
          await _supabase
              .from('app_dat_precio_venta')
              .select('precio_venta_cup')
              .eq('id_producto', localProductId)
              .lte('fecha_desde', DateTime.now().toIso8601String())
              .order('fecha_desde', ascending: false)
              .limit(1)
              .maybeSingle();

      final double basePrice =
          ((priceData?['precio_venta_cup'] as num?) ?? 0).toDouble();

      // 2.1 Obtener configuración de porcentajes para Carnaval (con fallback)
      final priceConfig = await _getCarnavalPriceConfig(
        productData['id_tienda'],
      );

      // Calcular precios con markup dinámico (permitiendo valores negativos)
      // precio_descuento = basePrice + porcentaje carnaval
      // price (oficial) = basePrice + porcentaje transferencia
      double precioDescuento =
          (basePrice * (1 + priceConfig['precio_venta_carnaval']! / 100))
              .roundToDouble();

      if (carnavalStoreId == 1 || carnavalStoreId == 177) {
        precioDescuento = basePrice;
      }
      final precioOficial =
          (basePrice *
                  (1 +
                      priceConfig['precio_venta_carnaval_transferencia']! /
                          100))
              .roundToDouble();

      // 3. Obtener stock actual de la ubicación específica
      final stockData =
          await _supabase
              .from('app_dat_inventario_productos')
              .select('cantidad_final')
              .eq('id_producto', localProductId)
              .eq('id_ubicacion', idUbicacion)
              .order('id', ascending: false).order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

      final stock = stockData?['cantidad_final'] ?? 0;

      // 4. Insertar en Carnaval App y obtener el ID del producto insertado
      final carnavalProductResponse =
          await _supabase
              .schema('carnavalapp')
              .from('Productos')
              .insert({
                'name': productData['denominacion'],
                'description': productData['descripcion'] ?? '',
                'price': precioOficial,
                'precio_descuento': precioDescuento,
                'stock':
                    stock
                        .toInt(), // Convertir a int para evitar error de bigint
                'category_id': carnavalCategoryId,
                'image': productData['imagen'],
                'proveedor': carnavalStoreId,
                'status': true,
                'created_at': DateTime.now().toIso8601String(),
              })
              .select('id')
              .single();

      final carnavalProductId = carnavalProductResponse['id'];
      print('✅ Producto insertado en Carnaval con ID: $carnavalProductId');

      // 5. Actualizar el producto local con el id_vendedor_app
      await _supabase
          .from('app_dat_producto')
          .update({'id_vendedor_app': carnavalProductId})
          .eq('id', localProductId);

      print(
        '✅ Producto local actualizado con id_vendedor_app: $carnavalProductId',
      );

      // 6. Insertar en relation_products_carnaval para trackear la ubicación
      await _supabase.from('relation_products_carnaval').insert({
        'id_producto': localProductId,
        'id_producto_carnaval': carnavalProductId,
        'id_ubicacion': idUbicacion,
        'created_at': DateTime.now().toIso8601String(),
      });

      print(
        '✅ Relación guardada en relation_products_carnaval con ubicación ID: $idUbicacion',
      );

      return true;
    } catch (e, stackTrace) {
      print('❌ Error al sincronizar producto: $e');
      print(stackTrace);
      return false;
    }
  }

  /// Obtiene configuración de porcentajes de precio para Carnaval.
  /// Si no existe registro, retorna defaults (5.3% y 11.1%).
  static Future<Map<String, double>> _getCarnavalPriceConfig(
    int storeId,
  ) async {
    const defaults = {
      'precio_venta_carnaval': 5.3,
      'precio_venta_carnaval_transferencia': 11.1,
    };

    try {
      final config =
          await _supabase
              .from('app_dat_precio_general_tienda')
              .select(
                'precio_venta_carnaval, precio_venta_carnaval_transferencia',
              )
              .eq('id_tienda', storeId)
              .maybeSingle();

      if (config == null) return defaults;

      return {
        'precio_venta_carnaval':
            (config['precio_venta_carnaval'] as num?)?.toDouble() ??
            defaults['precio_venta_carnaval']!,
        'precio_venta_carnaval_transferencia':
            (config['precio_venta_carnaval_transferencia'] as num?)
                ?.toDouble() ??
            defaults['precio_venta_carnaval_transferencia']!,
      };
    } catch (e) {
      print('❌ Error obteniendo config de precio carnaval: $e');
      return defaults;
    }
  }

  /// Obtiene los productos sincronizados agrupados por categoría
  static Future<Map<String, List<Map<String, dynamic>>>>
  getSyncedProductsGrouped(int carnavalStoreId) async {
    try {
      // Obtener productos con sus categorías (activos e inactivos)
      final response = await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .select('*, Categorias(name)')
          .eq('proveedor', carnavalStoreId)
          .order('name');

      final products = List<Map<String, dynamic>>.from(response);

      // Obtener relaciones de productos para tener id_producto (local)
      final relationResponse = await _supabase
          .from('relation_products_carnaval')
          .select('id_producto_carnaval, id_producto')
          .inFilter(
            'id_producto_carnaval',
            products.map((p) => p['id']).toList(),
          );

      final relations = List<Map<String, dynamic>>.from(relationResponse ?? []);

      // Crear mapa de relaciones para búsqueda rápida
      final relationMap = <int, int>{};
      for (var relation in relations) {
        relationMap[relation['id_producto_carnaval']] = relation['id_producto'];
      }

      final grouped = <String, List<Map<String, dynamic>>>{};

      for (var product in products) {
        final categoryName =
            product['Categorias']?['name']?.toString() ?? 'Sin Categoría';
        if (!grouped.containsKey(categoryName)) {
          grouped[categoryName] = [];
        }

        // Agregar id_producto del producto local si existe
        product['id_producto'] = relationMap[product['id']];

        grouped[categoryName]!.add(product);
      }

      return grouped;
    } catch (e) {
      print('❌ Error al obtener productos sincronizados: $e');
      return {};
    }
  }

  /// Obtiene estadísticas de ventas de un producto en Carnaval
  /// Retorna el total de ventas completadas (completada=true, status='Completado')
  static Future<double> getProductSalesStats(int carnavalProductId) async {
    try {
      print(
        '🔍 Obteniendo estadísticas de ventas para producto ID: $carnavalProductId',
      );

      // Consultar OrderDetails con join a Orders
      final response = await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .select('price, quantity, Orders!inner(status)')
          .eq('product_id', carnavalProductId)
          .eq('completada', true)
          .eq('Orders.status', 'Completado');

      double totalSales = 0;
      for (var detail in response) {
        final price = (detail['price'] ?? 0).toDouble();
        final quantity = (detail['quantity'] ?? 0).toInt();
        totalSales += price * quantity;
      }

      print('✅ Total de ventas: \$${totalSales.toStringAsFixed(2)}');
      return totalSales;
    } catch (e) {
      print('❌ Error al obtener estadísticas de ventas: $e');
      return 0;
    }
  }

  /// Obtiene estadísticas de pedidos cancelados de un producto
  /// Retorna el total de pedidos cancelados (status='Cancelado')
  static Future<double> getProductCancelledStats(int carnavalProductId) async {
    try {
      print(
        '🔍 Obteniendo estadísticas de cancelaciones para producto ID: $carnavalProductId',
      );

      // Consultar OrderDetails con join a Orders
      final response = await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .select('price, quantity, Orders!inner(status)')
          .eq('product_id', carnavalProductId)
          .eq('Orders.status', 'Cancelado');

      double totalCancelled = 0;
      for (var detail in response) {
        final price = (detail['price'] ?? 0).toDouble();
        final quantity = (detail['quantity'] ?? 0).toInt();
        totalCancelled += price * quantity;
      }

      print('✅ Total de cancelaciones: \$${totalCancelled.toStringAsFixed(2)}');
      return totalCancelled;
    } catch (e) {
      print('❌ Error al obtener estadísticas de cancelaciones: $e');
      return 0;
    }
  }

  /// Oculta un producto de Carnaval App (establece status = false)
  static Future<bool> hideProductFromCarnaval(int carnavalProductId) async {
    try {
      print('🔧 Ocultando producto ID: $carnavalProductId de Carnaval');

      await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .update({'status': false})
          .eq('id', carnavalProductId);

      print('✅ Producto ocultado de Carnaval exitosamente');
      return true;
    } catch (e) {
      print('❌ Error al ocultar producto: $e');
      return false;
    }
  }

  /// Muestra un producto en Carnaval App (establece status = true)
  static Future<bool> showProductInCarnaval(int carnavalProductId) async {
    try {
      print('🔧 Mostrando producto ID: $carnavalProductId en Carnaval');

      await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .update({'status': true})
          .eq('id', carnavalProductId);

      print('✅ Producto mostrado en Carnaval exitosamente');
      return true;
    } catch (e) {
      print('❌ Error al mostrar producto: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // PRODUCT LOCATION MANAGEMENT
  // ---------------------------------------------------------------------------

  /// Obtiene las ubicaciones disponibles para un producto usando fn_obtener_ubicaciones_prodcuto
  static Future<List<Map<String, dynamic>>> getProductLocations(
    int storeId,
    int productId,
  ) async {
    try {
      print(
        '🔍 Obteniendo ubicaciones para producto ID: $productId en tienda ID: $storeId',
      );

      final response = await _supabase.rpc(
        'fn_obtener_ubicaciones_prodcuto',
        params: {'p_id_tienda': storeId, 'p_id_producto': productId},
      );

      final locations = List<Map<String, dynamic>>.from(response ?? []);
      print('✅ Ubicaciones obtenidas: ${locations.length}');
      return locations;
    } catch (e) {
      print('❌ Error al obtener ubicaciones del producto: $e');
      return [];
    }
  }

  /// Obtiene productos sincronizados con información de ubicación (evita N+1)
  /// Retorna productos agrupados por categoría incluyendo almacén y ubicación
  static Future<Map<String, List<Map<String, dynamic>>>>
  getSyncedProductsWithLocation(int carnavalStoreId) async {
    try {
      print(
        '🔍 Obteniendo productos sincronizados con ubicación para proveedor ID: $carnavalStoreId',
      );

      // Query único con JOINs para incluir ubicación y almacén
      final response = await _supabase.rpc(
        'get_synced_products_with_location_v2',
        params: {'p_carnaval_store_id': carnavalStoreId},
      );

      final products = List<Map<String, dynamic>>.from(response ?? []);
      final grouped = <String, List<Map<String, dynamic>>>{};

      for (var product in products) {
        final categoryName =
            product['category_name']?.toString() ?? 'Sin Categoría';
        if (!grouped.containsKey(categoryName)) {
          grouped[categoryName] = [];
        }
        grouped[categoryName]!.add(product);
      }

      print('✅ Productos con ubicación obtenidos: ${products.length}');
      return grouped;
    } catch (e) {
      print('❌ Error al obtener productos con ubicación (usando fallback): $e');
      // Fallback: usar el método anterior si la función no existe
      return await getSyncedProductsGrouped(carnavalStoreId);
    }
  }

  /// Actualiza la ubicación de un producto y recalcula el stock
  static Future<bool> updateProductLocation({
    required int carnavalProductId,
    required int newLocationId,
    required int localProductId,
  }) async {
    try {
      print(
        '🔧 Actualizando ubicación del producto Carnaval ID: $carnavalProductId a ubicación ID: $newLocationId',
      );

      // 1. Obtener nuevo stock de la ubicación
      final stockData =
          await _supabase
              .from('app_dat_inventario_productos')
              .select('cantidad_final')
              .eq('id_producto', localProductId)
              .eq('id_ubicacion', newLocationId)
              .order('id', ascending: false).order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

      final newStock = stockData?['cantidad_final'] ?? 0;
      print('📦 Nuevo stock calculado: $newStock');

      // 2. Actualizar stock en carnavalapp.Productos
      await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .update({'stock': newStock.toInt()})
          .eq('id', carnavalProductId);

      print('✅ Stock actualizado en Carnaval');

      // 3. Verificar si existe relación en relation_products_carnaval
      final existingRelation =
          await _supabase
              .from('relation_products_carnaval')
              .select('id')
              .eq('id_producto_carnaval', carnavalProductId)
              .maybeSingle();

      if (existingRelation != null) {
        // 3a. Si existe, hacer UPDATE
        print('🔄 Actualizando ubicación existente...');
        await _supabase
            .from('relation_products_carnaval')
            .update({'id_ubicacion': newLocationId})
            .eq('id_producto_carnaval', carnavalProductId);
        print('✅ Ubicación actualizada en relation_products_carnaval');
      } else {
        // 3b. Si NO existe, hacer INSERT
        print('➕ Creando nueva relación con ubicación...');
        await _supabase.from('relation_products_carnaval').insert({
          'id_producto': localProductId,
          'id_producto_carnaval': carnavalProductId,
          'id_ubicacion': newLocationId,
        });
        print('✅ Relación creada en relation_products_carnaval');
      }
      return true;
    } catch (e) {
      print('❌ Error al actualizar ubicación del producto: $e');
      return false;
    }
  }

  /// Obtiene los porcentajes globales de comisión
  static Future<Map<String, double>> getGlobalPercentages() async {
    try {
      final response = await _supabase
          .from('precio_global_productos_carnaval')
          .select('porciento_efectivo, porciento_transferencia')
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return {'efectivo': 5.0, 'transferencia': 15.0};
      }
      return {
        'efectivo': (response['porciento_efectivo'] as num?)?.toDouble() ?? 5.0,
        'transferencia':
            (response['porciento_transferencia'] as num?)?.toDouble() ?? 15.0,
      };
    } catch (e) {
      print('❌ Error obteniendo porcentajes globales: $e');
      return {'efectivo': 5.0, 'transferencia': 15.0};
    }
  }

  // =============================================
  // ÓRDENES DE CARNAVAL
  // =============================================

  /// Obtiene órdenes paginadas del carnaval
  /// Admin (id in [3,29,38]): órdenes donde proveedor_id = 3
  /// No-admin: órdenes donde proveedores contiene su ID
  static Future<List<Map<String, dynamic>>> getCarnavalOrders(
    int carnavalStoreId,
    bool isAdmin, {
    int page = 0,
    int pageSize = 20,
    String? statusFilter,
    int? orderIdFilter,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize - 1;

      var query = _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select('*, Usuarios:user_id(name, telefono)');

      if (!isAdmin) {
        query = query.contains('proveedores', ['$carnavalStoreId']);
      }

      if (statusFilter != null) {
        if (statusFilter == 'Nuevo') {
          query = query.inFilter('status', ['Nuevo', 'En Revision', 'Pendiente de Pago']);
        } else {
          query = query.eq('status', statusFilter);
        }
      }

      if (orderIdFilter != null) {
        query = query.eq('id', orderIdFilter);
      }

      final response = await query
          .order('id', ascending: false)
          .order('created_at', ascending: false)
          .range(from, to);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener órdenes de carnaval: $e');
      return [];
    }
  }

  /// Obtiene todas las órdenes completadas en un rango de fecha para dashboard
  static Future<List<Map<String, dynamic>>> getCompletedOrdersForDashboard({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select('*')
          .eq('status', 'Completado')
          .gte('created_at', from.toIso8601String().split('T')[0])
          .lte('created_at', to.toIso8601String().split('T')[0])
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener órdenes completadas: $e');
      return [];
    }
  }

  /// Obtiene conteo de órdenes por status
  static Future<Map<String, int>> getOrderStatusCounts() async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select('status');
      final counts = <String, int>{};
      for (final r in response) {
        final s = r['status'] as String? ?? 'Desconocido';
        counts[s] = (counts[s] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      print('❌ Error al obtener conteos: $e');
      return {};
    }
  }

  /// Obtiene nombres de proveedores por IDs
  static Future<Map<int, String>> getProveedoresNames(List<int> ids) async {
    try {
      if (ids.isEmpty) return {};
      final response = await _supabase
          .schema('carnavalapp')
          .from('proveedores')
          .select('id, name')
          .inFilter('id', ids);
      final map = <int, String>{};
      for (final r in response) {
        map[r['id'] as int] = r['name'] as String? ?? 'Proveedor #${r['id']}';
      }
      return map;
    } catch (e) {
      print('❌ Error al obtener nombres de proveedores: $e');
      return {};
    }
  }

  /// Obtiene detalles de una orden con join a Productos
  static Future<List<Map<String, dynamic>>> getOrderDetails(
    int orderId, {
    int? proveedorFilter,
  }) async {
    try {
      var query = _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .select('*, Productos(id, name, image, price, proveedor, proveedores(id, name))')
          .eq('order_id', orderId);

      if (proveedorFilter != null) {
        query = query.eq('Productos.proveedor', proveedorFilter);
      }

      final response = await query;
      // Filter out items where Productos is null (when proveedorFilter filtered them)
      if (proveedorFilter != null) {
        return List<Map<String, dynamic>>.from(
          response.where((item) => item['Productos'] != null),
        );
      }
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener detalles de orden: $e');
      return [];
    }
  }

  /// Actualiza el status de una orden
  static Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    try {
      await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      return true;
    } catch (e) {
      print('❌ Error al actualizar status de orden: $e');
      return false;
    }
  }

  /// Asigna un repartidor a una orden. Si es recogida, marca Completado.
  static Future<bool> assignDelivery(
    int orderId,
    int repartidorId, {
    String metodoEntrega = 'Domicilio',
  }) async {
    try {
      final isRecogida = metodoEntrega == 'Entrega Cliente';
      await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .update({
            'status': isRecogida ? 'Completado' : 'Asignado',
            'repartidor_id': repartidorId,
          })
          .eq('id', orderId);
      return true;
    } catch (e) {
      print('❌ Error al asignar repartidor: $e');
      return false;
    }
  }

  /// Lista repartidores activos
  static Future<List<Map<String, dynamic>>> getRepartidores() async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('repartidores')
          .select('*')
          .eq('status', true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener repartidores: $e');
      return [];
    }
  }

  /// Actualiza la cantidad de un detalle de orden
  static Future<bool> updateOrderDetailQuantity(
    int detailId,
    int newQuantity,
  ) async {
    try {
      await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .update({'quantity': newQuantity})
          .eq('id', detailId);
      return true;
    } catch (e) {
      print('❌ Error al actualizar cantidad: $e');
      return false;
    }
  }

  /// Elimina un detalle de orden
  static Future<bool> deleteOrderDetail(int detailId) async {
    try {
      await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .delete()
          .eq('id', detailId);
      return true;
    } catch (e) {
      print('❌ Error al eliminar detalle: $e');
      return false;
    }
  }

  /// Recalcula el total de una orden sumando price*quantity de sus detalles
  static Future<bool> recalculateOrderTotal(int orderId) async {
    try {
      final details = await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .select('price, quantity')
          .eq('order_id', orderId);

      double total = 0;
      for (final d in details) {
        final price = (d['price'] as num?)?.toDouble() ?? 0;
        final qty = (d['quantity'] as num?)?.toInt() ?? 0;
        total += price * qty;
      }

      await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .update({'total': total})
          .eq('id', orderId);

      return true;
    } catch (e) {
      print('❌ Error al recalcular total: $e');
      return false;
    }
  }

  /// Obtiene info del usuario de una orden desde carnavalapp.Usuarios
  static Future<Map<String, dynamic>?> getOrderUserInfo(int userId) async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Usuarios')
          .select('name, email, telefono, carnet_id')
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      print('❌ Error al obtener info de usuario: $e');
      return null;
    }
  }

  /// Obtiene provincia y municipio de una dirección por su texto
  static Future<Map<String, dynamic>?> getOrderDireccion(
      String direccionText) async {
    try {
      final dirResponse = await _supabase
          .schema('carnavalapp')
          .from('Direcciones')
          .select('id, address, provincia, municipio')
          .eq('address', direccionText)
          .limit(1)
          .maybeSingle();

      if (dirResponse == null) return null;

      final result = Map<String, dynamic>.from(dirResponse);
      final provinciaId = dirResponse['provincia'];
      final municipioId = dirResponse['municipio'];

      if (provinciaId != null) {
        final prov = await _supabase
            .schema('carnavalapp')
            .from('Provincias')
            .select('nombre')
            .eq('id', provinciaId)
            .maybeSingle();
        result['provincia_nombre'] = prov?['nombre'];
      }

      if (municipioId != null) {
        final mun = await _supabase
            .schema('carnavalapp')
            .from('municipios')
            .select('municipio')
            .eq('id', municipioId)
            .maybeSingle();
        result['municipio_nombre'] = mun?['nombre'];
      }

      return result;
    } catch (e) {
      print('❌ Error al obtener dirección: $e');
      return null;
    }
  }

  /// Obtiene el ID de operación VentIQ asociada a una orden de Carnaval
  static Future<int?> getVentiqOperationId(int carnavalOrderId) async {
    try {
      final response = await _supabase
          .from('app_dat_operaciones')
          .select('id')
          .ilike('observaciones', '%Venta desde orden $carnavalOrderId%')
          .limit(1)
          .maybeSingle();
      return response?['id'] as int?;
    } catch (e) {
      print('❌ Error al obtener operación VentIQ: $e');
      return null;
    }
  }

  /// Obtiene una orden por ID
  static Future<Map<String, dynamic>?> getOrderById(int orderId) async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select('*')
          .eq('id', orderId)
          .maybeSingle();
      return response;
    } catch (e) {
      print('❌ Error al obtener orden: $e');
      return null;
    }
  }
}
