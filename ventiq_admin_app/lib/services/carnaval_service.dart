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

      final response = await _supabase
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

      final response = await _supabase
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
      final supervisorData = await _supabase
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
      final trabajadorData = await _supabase
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
      final existingUser = await _supabase
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

      final newUser = await _supabase
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
        'contacto': storeInfo['phone'] != null
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

      final response = await _supabase
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
          final carnavalProductIds = relationList
              .map((r) => r['id_producto_carnaval'])
              .toList();
          final relationIds = relationList.map((r) => r['id']).toList();
          final localProductIds = relationList
              .map((r) => r['id_producto'])
              .toList();

          // 3. Eliminar productos de carnavalapp.Productos
          await _supabase
              .schema('carnavalapp')
              .from('Productos')
              .delete()
              .inFilter('id', carnavalProductIds);

          print(
            '✅ Eliminados ${carnavalProductIds.length} productos de Carnaval',
          );

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
          .select('id, name, icon, descripcion, orden')
          .order('orden');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener categorías de Carnaval: $e');
      return [];
    }
  }

  /// Actualiza la categoría de un producto en carnavalapp.Productos
  static Future<bool> updateProductCategory({
    required int carnavalProductId,
    required int newCategoryId,
  }) async {
    try {
      await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .update({'category_id': newCategoryId})
          .eq('id', carnavalProductId);
      return true;
    } catch (e) {
      print('❌ Error al actualizar categoría: $e');
      return false;
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
          .select('id, denominacion, imagen, sku, descripcion')
          .eq('id_tienda', storeId)
          .neq('imagen', ''); // No debe estar vacía

      final localProducts = List<Map<String, dynamic>>.from(
        localProductsResponse,
      ).where((p) => p['imagen'] != null).toList(); // Filtrar nulos en Dart

      // 2. Obtener IDs de productos ya sincronizados via relation_products_carnaval
      final localProductIds = localProducts.map((p) => p['id']).toList();
      final relationResponse = await _supabase
          .from('relation_products_carnaval')
          .select('id_producto')
          .inFilter('id_producto', localProductIds);

      final syncedProductIds = List<Map<String, dynamic>>.from(
        relationResponse,
      ).map((r) => r['id_producto']).toSet();

      // 3. Filtrar productos que ya tienen relación
      final unsyncedProducts = localProducts
          .where((p) => !syncedProductIds.contains(p['id']))
          .toList();

      return unsyncedProducts;
    } catch (e) {
      print('❌ Error al obtener productos no sincronizados: $e');
      return [];
    }
  }

  /// Valida la integridad de una tupla (producto local, ubicación, tienda local,
  /// proveedor Carnaval) antes de cualquier insert/update sobre
  /// `relation_products_carnaval`. Esto evita que la app guarde relaciones
  /// "cruzadas" donde, por bug en la UI, edición posterior o datos legacy,
  /// el producto/ubicación pertenezcan a una tienda distinta a la activa.
  ///
  /// El trigger `crear_orden_desde_carnaval.sql` ya tiene guardas defensivas
  /// equivalentes, pero ese es un parche curativo. Esta función ataca el
  /// origen.
  ///
  /// Lanza Exception con mensaje específico si algo no cuadra. Devuelve un
  /// Map con datos útiles (producto, ubicación) si pasa.
  static Future<Map<String, dynamic>> _validateRelationIntegrity({
    required int localProductId,
    required int idUbicacion,
    required int expectedStoreId,
    required int expectedCarnavalStoreId,
  }) async {
    // (a) Producto local existe y pertenece a la tienda esperada
    final product = await _supabase
        .from('app_dat_producto')
        .select('id, id_tienda, denominacion, id_vendedor_app')
        .eq('id', localProductId)
        .maybeSingle();

    if (product == null) {
      throw Exception(
        'Producto local $localProductId no existe en app_dat_producto',
      );
    }
    if (product['id_tienda'] != expectedStoreId) {
      throw Exception(
        'Producto $localProductId (${product['denominacion']}) pertenece a '
        'tienda ${product['id_tienda']}, no a la tienda activa '
        '$expectedStoreId. No se puede sincronizar bajo una tienda ajena.',
      );
    }

    // (b) Ubicación existe y su almacén pertenece a la misma tienda.
    // Hacemos dos queries en lugar de un join anidado para evitar
    // ambigüedades del cliente Supabase Dart con relaciones explícitas.
    final layout = await _supabase
        .from('app_dat_layout_almacen')
        .select('id, id_almacen')
        .eq('id', idUbicacion)
        .maybeSingle();

    if (layout == null) {
      throw Exception(
        'Ubicación $idUbicacion no existe en app_dat_layout_almacen',
      );
    }

    final almacen = await _supabase
        .from('app_dat_almacen')
        .select('id, id_tienda, denominacion')
        .eq('id', layout['id_almacen'])
        .maybeSingle();

    if (almacen == null) {
      throw Exception(
        'Almacén ${layout['id_almacen']} (referenciado por ubicación '
        '$idUbicacion) no existe',
      );
    }
    if (almacen['id_tienda'] != expectedStoreId) {
      throw Exception(
        'Ubicación $idUbicacion pertenece al almacén "${almacen['denominacion']}" '
        'de la tienda ${almacen['id_tienda']}, no a la tienda activa '
        '$expectedStoreId. Esto provocaría productos cruzados entre proveedores.',
      );
    }

    // (c) Tienda local está vinculada a Carnaval y al proveedor esperado
    final tienda = await _supabase
        .from('app_dat_tienda')
        .select('id, id_tienda_carnaval, admin_carnaval')
        .eq('id', expectedStoreId)
        .maybeSingle();

    if (tienda == null) {
      throw Exception('Tienda $expectedStoreId no existe');
    }
    if (tienda['admin_carnaval'] != true) {
      throw Exception(
        'Tienda $expectedStoreId no está sincronizada con Carnaval '
        '(admin_carnaval=${tienda['admin_carnaval']}). '
        'Sincroniza la tienda antes de añadir productos.',
      );
    }
    if (tienda['id_tienda_carnaval'] != expectedCarnavalStoreId) {
      throw Exception(
        'Tienda $expectedStoreId está mapeada al proveedor Carnaval '
        '${tienda['id_tienda_carnaval']}, no a $expectedCarnavalStoreId. '
        'Recarga la pantalla para refrescar el ID de proveedor.',
      );
    }

    return {
      'product': product,
      'layout': layout,
      'almacen': almacen,
      'tienda': tienda,
    };
  }

  /// Sincroniza un producto local con Carnaval App
  static Future<bool> syncProductToCarnaval({
    required int localProductId,
    required int carnavalCategoryId,
    required int carnavalStoreId,
    required int idUbicacion,
    required int storeId,
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

      // 0.1 Validación de integridad de la tupla
      // (producto local <-> ubicación <-> tienda <-> proveedor Carnaval).
      // Si algo no cuadra, abortar antes de tocar ninguna tabla.
      await _validateRelationIntegrity(
        localProductId: localProductId,
        idUbicacion: idUbicacion,
        expectedStoreId: storeId,
        expectedCarnavalStoreId: carnavalStoreId,
      );

      // 1. Obtener datos del producto local
      final productData = await _supabase
          .from('app_dat_producto')
          .select('denominacion, descripcion, imagen, id_tienda')
          .eq('id', localProductId)
          .single();

      // 2. Obtener precio actual (el más reciente activo)
      final priceData = await _supabase
          .from('app_dat_precio_venta')
          .select('precio_venta_cup')
          .eq('id_producto', localProductId)
          .lte('fecha_desde', DateTime.now().toIso8601String())
          .order('fecha_desde', ascending: false)
          .limit(1)
          .maybeSingle();

      final double basePrice = ((priceData?['precio_venta_cup'] as num?) ?? 0)
          .toDouble();

      // 2.1 Obtener configuración de porcentajes para Carnaval
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
      final stockData = await _supabase
          .from('app_dat_inventario_productos')
          .select('cantidad_final')
          .eq('id_producto', localProductId)
          .eq('id_ubicacion', idUbicacion)
          .order('id', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final stock = stockData?['cantidad_final'] ?? 0;

      // 4. Insertar en Carnaval App y obtener el ID del producto insertado
      final carnavalProductResponse = await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .insert({
            'name': productData['denominacion'],
            'description': productData['descripcion'] ?? '',
            'price': precioOficial,
            'precio_descuento': precioDescuento,
            'stock': stock
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
      // Re-lanzar la excepción para que el caller pueda mostrar el motivo
      // exacto al usuario (especialmente los mensajes de
      // _validateRelationIntegrity). El caller decide cómo reportar.
      rethrow;
    }
  }

  /// Obtiene configuración de porcentajes de precio para Carnaval.
  static Future<Map<String, double>> _getCarnavalPriceConfig(
    int storeId,
  ) async {
    final config = await _supabase
        .from('app_dat_precio_general_tienda')
        .select('precio_venta_carnaval, precio_venta_carnaval_transferencia')
        .eq('id_tienda', storeId)
        .maybeSingle();

    final precioCarnaval = (config?['precio_venta_carnaval'] as num?)
        ?.toDouble();
    final precioTransferencia =
        (config?['precio_venta_carnaval_transferencia'] as num?)?.toDouble();

    if (precioCarnaval == null || precioTransferencia == null) {
      throw Exception(
        'La tienda no tiene configurados los porcentajes de Carnaval',
      );
    }

    return {
      'precio_venta_carnaval': precioCarnaval,
      'precio_venta_carnaval_transferencia': precioTransferencia,
    };
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
    required int storeId,
    required int carnavalStoreId,
  }) async {
    try {
      print(
        '🔧 Actualizando ubicación del producto Carnaval ID: $carnavalProductId a ubicación ID: $newLocationId',
      );

      // 0. Validación de integridad de la tupla
      // (producto local <-> nueva ubicación <-> tienda <-> proveedor Carnaval).
      await _validateRelationIntegrity(
        localProductId: localProductId,
        idUbicacion: newLocationId,
        expectedStoreId: storeId,
        expectedCarnavalStoreId: carnavalStoreId,
      );

      // 0.1 Verificar que el producto Carnaval pertenece al proveedor esperado.
      // Esto detecta el caso de que un id_vendedor_app local apunte a un
      // Producto de otro proveedor (datos cruzados).
      final carnavalProd = await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .select('id, proveedor')
          .eq('id', carnavalProductId)
          .maybeSingle();

      if (carnavalProd == null) {
        throw Exception(
          'Producto Carnaval $carnavalProductId no existe en carnavalapp.Productos',
        );
      }
      if (carnavalProd['proveedor'] != carnavalStoreId) {
        throw Exception(
          'Producto Carnaval $carnavalProductId pertenece al proveedor '
          '${carnavalProd['proveedor']}, no a $carnavalStoreId. '
          'Esto indica datos cruzados — re-sincroniza el producto.',
        );
      }

      // 1. Obtener nuevo stock de la ubicación
      final stockData = await _supabase
          .from('app_dat_inventario_productos')
          .select('cantidad_final')
          .eq('id_producto', localProductId)
          .eq('id_ubicacion', newLocationId)
          .order('id', ascending: false)
          .order('created_at', ascending: false)
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
      final existingRelation = await _supabase
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
  /// Actualiza el campo 'destacado' de un producto en carnavalapp.Productos
  static Future<bool> updateProductDestacado({
    required int carnavalProductId,
    required bool destacado,
  }) async {
    try {
      await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .update({'destacado': destacado})
          .eq('id', carnavalProductId);
      return true;
    } catch (e) {
      print('❌ Error al actualizar destacado: $e');
      return false;
    }
  }

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
    DateTime? dateFrom,
    DateTime? dateTo,
    bool filterByStatusDate = false,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize - 1;

      Set<int>? orderIdsByStatusDate;
      if (filterByStatusDate && statusFilter != null) {
        var historyQuery = _supabase
            .schema('carnavalapp')
            .from('order_status_history')
            .select('order_id');
        if (statusFilter == 'Nuevo') {
          historyQuery = historyQuery.inFilter('status', [
            'Nuevo',
            'En Revision',
            'Pendiente de Pago',
          ]);
        } else {
          historyQuery = historyQuery.eq('status', statusFilter);
        }
        if (dateFrom != null) {
          historyQuery = historyQuery.gte(
            'created_at',
            DateTime(
              dateFrom.year,
              dateFrom.month,
              dateFrom.day,
            ).toIso8601String(),
          );
        }
        if (dateTo != null) {
          historyQuery = historyQuery.lt(
            'created_at',
            DateTime(
              dateTo.year,
              dateTo.month,
              dateTo.day + 1,
            ).toIso8601String(),
          );
        }
        final historyResponse = await historyQuery;
        orderIdsByStatusDate = historyResponse
            .map<int?>((row) => (row['order_id'] as num?)?.toInt())
            .whereType<int>()
            .toSet();
        if (orderIdsByStatusDate.isEmpty) return [];
      }

      var query = _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select('*, Usuarios:user_id(name, telefono)');

      if (!isAdmin) {
        query = query.contains('proveedores', ['$carnavalStoreId']);
      }

      if (orderIdsByStatusDate != null) {
        query = query.inFilter('id', orderIdsByStatusDate.toList());
      }

      if (statusFilter != null && !filterByStatusDate) {
        if (statusFilter == 'Nuevo') {
          query = query.inFilter('status', [
            'Nuevo',
            'En Revision',
            'Pendiente de Pago',
          ]);
        } else {
          query = query.eq('status', statusFilter);
        }
      }

      if (orderIdFilter != null) {
        query = query.eq('id', orderIdFilter);
      }

      if (!filterByStatusDate && dateFrom != null) {
        query = query.gte(
          'created_at',
          dateFrom.toIso8601String().split('T')[0],
        );
      }

      if (!filterByStatusDate && dateTo != null) {
        final end = DateTime(dateTo.year, dateTo.month, dateTo.day, 23, 59, 59);
        query = query.lte('created_at', end.toIso8601String());
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
          .select(
            '*, Productos(id, name, image, price, proveedor, proveedores(id, name))',
          )
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
  static Future<bool> updateOrderStatus(
    int orderId,
    String newStatus, {
    String? changedBy,
  }) async {
    try {
      await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      await _logOrderStatusChange(orderId, newStatus, changedBy: changedBy);
      return true;
    } catch (e) {
      print('❌ Error al actualizar status de orden: $e');
      return false;
    }
  }

  /// True si el método de entrega es recogida en tienda (no requiere repartidor).
  static bool isMetodoRecogida(String? metodoEntrega) {
    final m = (metodoEntrega ?? '').trim().toLowerCase();
    return m == 'recogida' || m == 'entrega cliente';
  }

  /// Completa una orden de recogida y guarda quién la completó.
  static Future<bool> completePickupOrder(
    int orderId, {
    String? completedBy,
  }) async {
    try {
      final updates = <String, dynamic>{
        'status': 'Completado',
        'completado_en': DateTime.now().toUtc().toIso8601String(),
      };
      if (completedBy != null && completedBy.trim().isNotEmpty) {
        updates['completado_por'] = completedBy.trim();
      }
      await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .update(updates)
          .eq('id', orderId);
      await _logOrderStatusChange(
        orderId,
        'Completado',
        changedBy: completedBy,
      );
      return true;
    } catch (e) {
      print('❌ Error al completar orden de recogida: $e');
      return false;
    }
  }

  /// Asigna un repartidor a una orden de domicilio (status → Asignado).
  static Future<bool> assignDelivery(
    int orderId,
    int repartidorId, {
    String metodoEntrega = 'Domicilio',
    String? changedBy,
  }) async {
    try {
      // Recogida ya no usa este flujo; se completa con [completePickupOrder].
      if (isMetodoRecogida(metodoEntrega)) {
        return completePickupOrder(orderId, completedBy: changedBy);
      }
      await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .update({'status': 'Asignado', 'repartidor': repartidorId})
          .eq('id', orderId);
      await _logOrderStatusChange(orderId, 'Asignado', changedBy: changedBy);
      return true;
    } catch (e) {
      print('❌ Error al asignar repartidor: $e');
      return false;
    }
  }

  /// Reasigna un repartidor a una orden.
  /// Por defecto no cambia el estado. Si [resetToAsignado] es true, devuelve la
  /// orden al estado 'Asignado' (usado al reasignar una orden en 'Entregando').
  static Future<bool> reassignDelivery(
    int orderId,
    int repartidorId, {
    bool resetToAsignado = false,
    String? changedBy,
  }) async {
    try {
      final updates = <String, dynamic>{'repartidor': repartidorId};
      if (resetToAsignado) updates['status'] = 'Asignado';
      await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .update(updates)
          .eq('id', orderId);
      if (resetToAsignado) {
        await _logOrderStatusChange(orderId, 'Asignado', changedBy: changedBy);
      }
      return true;
    } catch (e) {
      print('❌ Error al reasignar repartidor: $e');
      return false;
    }
  }

  static Future<void> _logOrderStatusChange(
    int orderId,
    String status, {
    String? changedBy,
  }) async {
    try {
      await _supabase
          .schema('carnavalapp')
          .from('order_status_history')
          .insert({
            'order_id': orderId,
            'status': status,
            if (changedBy != null && changedBy.trim().isNotEmpty)
              'changed_by': changedBy.trim(),
          });
    } catch (e) {
      // Tabla puede no existir aún si no se aplicó la migración; no bloquear.
      print('⚠️ No se pudo registrar historial de status: $e');
    }
  }

  /// Historial de status de la orden Carnaval (si la tabla existe).
  static Future<List<Map<String, dynamic>>> getOrderStatusHistory(
    int orderId,
  ) async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('order_status_history')
          .select('id, order_id, status, changed_by, created_at')
          .eq('order_id', orderId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('⚠️ Historial Carnaval no disponible: $e');
      return [];
    }
  }

  /// Historial de estados Inventtia ligado a la operación de venta de la orden.
  static Future<List<Map<String, dynamic>>> getVentiqEstadoHistory(
    int operationId,
  ) async {
    try {
      final response = await _supabase
          .from('app_dat_estado_operacion')
          .select('id, id_operacion, estado, created_at, comentario, uuid')
          .eq('id_operacion', operationId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('⚠️ Historial Inventtia no disponible: $e');
      return [];
    }
  }

  // ==========================================================================
  // BITÁCORA DE CAPITÁN
  // ==========================================================================
  // Lee la vista `carnavalapp.v_bitacora_capitan`, que se alimenta del trigger
  // trg_orderdetails_ajustar_erp: cada cambio de cantidad, cambio de precio o
  // borrado de línea en "OrderDetails" deja una fila con quién / qué / cuándo /
  // por qué y qué pasó en el inventario de Inventtia.
  //
  // La tabla es append-only (RLS con política solo de SELECT), así que nadie
  // puede borrar su rastro desde la app.
  //
  // Si el SQL todavía no se aplicó en Supabase, estos métodos devuelven lista
  // vacía en vez de romper la pantalla.

  /// Bitácora de una orden concreta.
  ///
  /// [proveedorFilter] acota a las líneas de una tienda: se pasa cuando quien
  /// mira NO es la tienda principal, igual que en [getOrderDetails], para que
  /// una tienda no vea los movimientos de las líneas de otro proveedor.
  static Future<List<Map<String, dynamic>>> getOrderBitacora(
    int orderId, {
    int? proveedorFilter,
  }) async {
    try {
      var query = _supabase
          .schema('carnavalapp')
          .from('v_bitacora_capitan')
          .select()
          .eq('order_id', orderId);

      if (proveedorFilter != null) {
        query = query.eq('proveedor', proveedorFilter);
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('⚠️ Bitácora de la orden no disponible: $e');
      return [];
    }
  }

  /// Bitácora completa, paginada y filtrable. Alimenta la pantalla de bitácora
  /// de capitán (solo tienda principal).
  ///
  /// [accion] filtra por el valor crudo: aumento | disminucion | eliminacion |
  /// cambio_precio | ajuste_sistema.
  /// [soloSinAplicar] deja solo lo que NO llegó a Inventtia (lo que hay que
  /// revisar a mano).
  static Future<List<Map<String, dynamic>>> getBitacora({
    int page = 0,
    int pageSize = 30,
    int? orderId,
    int? productId,
    int? proveedorFilter,
    String? accion,
    String? buscarQuien,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool soloSinAplicar = false,
  }) async {
    try {
      final from = page * pageSize;
      final to = from + pageSize - 1;

      var query = _supabase
          .schema('carnavalapp')
          .from('v_bitacora_capitan')
          .select();

      if (orderId != null) query = query.eq('order_id', orderId);
      if (productId != null) query = query.eq('product_id', productId);
      if (proveedorFilter != null) {
        query = query.eq('proveedor', proveedorFilter);
      }
      if (accion != null) query = query.eq('accion', accion);
      if (buscarQuien != null && buscarQuien.trim().isNotEmpty) {
        query = query.ilike('quien', '%${buscarQuien.trim()}%');
      }
      if (dateFrom != null) {
        final start = DateTime(dateFrom.year, dateFrom.month, dateFrom.day);
        query = query.gte('created_at', start.toIso8601String());
      }
      if (dateTo != null) {
        final end = DateTime(dateTo.year, dateTo.month, dateTo.day, 23, 59, 59);
        query = query.lte('created_at', end.toIso8601String());
      }
      if (soloSinAplicar) query = query.eq('aplicado_erp', false);

      final response = await query
          .order('created_at', ascending: false)
          .range(from, to);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('⚠️ Bitácora no disponible: $e');
      return [];
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

  /// Mapa `id -> {nombre, telefono}` de TODOS los repartidores (incluidos los
  /// inactivos, para poder resolver el nombre en órdenes históricas).
  /// Se consulta una sola vez y se cachea en memoria: son pocos registros y
  /// evita una query por fila al pintar la lista de órdenes.
  static Map<int, Map<String, dynamic>>? _repartidoresCache;

  static Future<Map<int, Map<String, dynamic>>> getRepartidoresMap({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _repartidoresCache != null) {
      return _repartidoresCache!;
    }
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('repartidores')
          .select('id, nombre, telefono');
      final map = <int, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(response)) {
        final id = row['id'];
        if (id is int) {
          map[id] = row;
        } else if (id != null) {
          final parsed = int.tryParse(id.toString());
          if (parsed != null) map[parsed] = row;
        }
      }
      _repartidoresCache = map;
      return map;
    } catch (e) {
      print('❌ Error al obtener mapa de repartidores: $e');
      return _repartidoresCache ?? {};
    }
  }

  /// Formatea el teléfono (columna `numeric`) quitando el `.0` que añade Dart
  /// al convertir números sin decimales.
  static String? formatRepartidorTelefono(dynamic telefono) {
    if (telefono == null) return null;
    if (telefono is num) {
      if (telefono == telefono.truncate()) {
        return telefono.toInt().toString();
      }
      return telefono.toString();
    }
    final text = telefono.toString().trim();
    if (text.isEmpty) return null;
    final asNum = num.tryParse(text);
    if (asNum != null && asNum == asNum.truncate()) {
      return asNum.toInt().toString();
    }
    return text;
  }

  /// Crea un nuevo repartidor: registra usuario en Supabase Auth (para que pueda
  /// loguearse en la app de repartidor) y luego inserta el registro en
  /// `carnavalapp.repartidores` con su UUID. Si el email ya existe, intenta
  /// reusar la cuenta autenticando con la contraseña provista.
  ///
  /// Retorna `{'repartidor': Map, 'userAlreadyExisted': bool}` en éxito o
  /// `{'error': String}` con el mensaje cuando falla.
  static Future<Map<String, dynamic>> addRepartidor({
    required String nombre,
    required String correo,
    required String password,
    required String telefono,
    String? chatId,
  }) async {
    try {
      String? userUuid;
      bool userAlreadyExisted = false;

      try {
        final authResponse = await _supabase.auth.signUp(
          email: correo,
          password: password,
          data: {'nombre': nombre, 'rol': 'repartidor'},
        );
        if (authResponse.user == null) {
          return {'error': 'No se pudo registrar el usuario en Supabase Auth.'};
        }
        userUuid = authResponse.user!.id;
        print('✅ Repartidor: usuario registrado con UUID: $userUuid');
      } catch (signUpError) {
        final msg = signUpError.toString();
        if (msg.contains('user_already_exists') ||
            msg.contains('User already registered')) {
          try {
            final loginResponse = await _supabase.auth.signInWithPassword(
              email: correo,
              password: password,
            );
            if (loginResponse.user == null) {
              return {
                'error':
                    'El email ya existe pero la contraseña proporcionada es incorrecta.',
              };
            }
            userUuid = loginResponse.user!.id;
            userAlreadyExisted = true;
            print(
              '✅ Repartidor: usuario existente reutilizado UUID: $userUuid',
            );
          } catch (loginError) {
            return {
              'error':
                  'El email ya está registrado y no se pudo autenticar (verifica la contraseña).',
            };
          }
        } else {
          return {'error': 'Error en signUp: $msg'};
        }
      }

      // Insertar en carnavalapp.repartidores con UUID.
      final telefonoNum = num.tryParse(telefono.replaceAll(RegExp(r'\D'), ''));
      final response = await _supabase
          .schema('carnavalapp')
          .from('repartidores')
          .insert({
            'nombre': nombre,
            'correo': correo,
            'telefono': telefonoNum,
            'uuid': userUuid,
            'status': true,
            if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId,
          })
          .select()
          .single();

      // Insertar/actualizar también en carnavalapp.Usuarios con rol 'Repartidor'
      // y el mismo uuid del auth para que ambas tablas queden vinculadas.
      try {
        final existing = await _supabase
            .schema('carnavalapp')
            .from('Usuarios')
            .select('id')
            .eq('uuid', userUuid!)
            .maybeSingle();
        if (existing == null) {
          await _supabase.schema('carnavalapp').from('Usuarios').insert({
            'email': correo,
            'uuid': userUuid,
            'name': nombre,
            'telefono': telefono,
            'rol': 'Repartidor',
            'email_confirmacion': true,
          });
          print('✅ Repartidor: Usuarios creado para uuid $userUuid');
        } else {
          await _supabase
              .schema('carnavalapp')
              .from('Usuarios')
              .update({
                'name': nombre,
                'telefono': telefono,
                'rol': 'Repartidor',
              })
              .eq('uuid', userUuid);
          print('✅ Repartidor: Usuarios actualizado a rol Repartidor');
        }
      } catch (uErr) {
        print('⚠️ No se pudo sincronizar Usuarios: $uErr');
      }

      // El nuevo repartidor debe aparecer en el mapa cacheado.
      _repartidoresCache = null;

      return {
        'repartidor': Map<String, dynamic>.from(response),
        'userAlreadyExisted': userAlreadyExisted,
      };
    } catch (e) {
      print('❌ Error al crear repartidor: $e');
      return {'error': 'Error al guardar repartidor: $e'};
    }
  }

  /// Lista órdenes de paquetería filtradas por id_tienda (operaciones VentIQ).
  /// Usa la tabla puente `paqueteria_ordenes` para encontrar las órdenes
  /// Carnaval asociadas a operaciones VentIQ de la tienda dada en el rango
  /// de fechas indicado.
  static Future<List<Map<String, dynamic>>> getPaqueteriaOrdersByTienda({
    required int idTienda,
    required DateTime from,
    required DateTime to,
    int page = 0,
    int pageSize = 20,
    String? statusFilter,
    int? orderIdFilter,
  }) async {
    try {
      // 1. Obtener IDs de operaciones de la tienda en el rango.
      final opsResponse = await _supabase
          .from('app_dat_operaciones')
          .select('id')
          .eq('id_tienda', idTienda)
          .gte('created_at', from.toIso8601String())
          .lte('created_at', to.toIso8601String());

      final operacionIds = (opsResponse as List)
          .map((o) => o['id'] as int)
          .toList();
      print(
        '🔍 paqueteria: ops encontradas tienda=$idTienda '
        'rango=${from.toIso8601String()}..${to.toIso8601String()} '
        '=> ${operacionIds.length}',
      );
      if (operacionIds.isEmpty) return [];

      // 2. Obtener órdenes carnaval asociadas a esas operaciones via paqueteria_ordenes.
      // Nota: si esta tabla tiene RLS restrictiva la respuesta vendrá vacía.
      final paqResponse = await _supabase
          .from('paqueteria_ordenes')
          .select(
            'id_orden_carnaval, id_operacion, numero_paquete, descripcion',
          )
          .inFilter('id_operacion', operacionIds);

      print(
        '🔍 paqueteria: filas paqueteria_ordenes => '
        '${(paqResponse as List).length}',
      );

      final ordenIdToOpId = <int, int>{};
      for (final row in paqResponse) {
        final ordenId = row['id_orden_carnaval'] as int?;
        final opId = row['id_operacion'] as int?;
        if (ordenId != null && opId != null) {
          ordenIdToOpId[ordenId] = opId;
        }
      }
      // Fallback: si paqueteria_ordenes no devolvió nada (posible RLS) pero la
      // orden Carnaval ya guarda su `paqueteria` JSONB y su `observaciones`
      // VentIQ apunta a la operación, podemos resolver vía observaciones.
      if (ordenIdToOpId.isEmpty) {
        print(
          '⚠️ paqueteria_ordenes vacío. Intentando fallback por '
          'observaciones de operaciones.',
        );
        final opsObs = await _supabase
            .from('app_dat_operaciones')
            .select('id, observaciones')
            .inFilter('id', operacionIds)
            .ilike('observaciones', '%Venta desde orden %');
        final regex = RegExp(r'Venta desde orden\s+(\d+)');
        for (final row in opsObs as List) {
          final obs = row['observaciones']?.toString() ?? '';
          final match = regex.firstMatch(obs);
          if (match != null) {
            final ordenId = int.tryParse(match.group(1)!);
            final opId = row['id'] as int?;
            if (ordenId != null && opId != null) {
              ordenIdToOpId[ordenId] = opId;
            }
          }
        }
        print('🔁 fallback: órdenes derivadas = ${ordenIdToOpId.length}');
        if (ordenIdToOpId.isEmpty) return [];
      }

      final ordenIds = ordenIdToOpId.keys.toList();

      // 3. Cargar las órdenes desde carnavalapp.Orders.
      var query = _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select('*, Usuarios:user_id(name, telefono)')
          .inFilter('id', ordenIds);

      if (statusFilter != null) {
        if (statusFilter == 'Nuevo') {
          query = query.inFilter('status', [
            'Nuevo',
            'En Revision',
            'Pendiente de Pago',
          ]);
        } else {
          query = query.eq('status', statusFilter);
        }
      }
      if (orderIdFilter != null) {
        query = query.eq('id', orderIdFilter);
      }

      final from0 = page * pageSize;
      final to0 = from0 + pageSize - 1;

      final ordersResponse = await query
          .order('id', ascending: false)
          .order('created_at', ascending: false)
          .range(from0, to0);

      final orders = List<Map<String, dynamic>>.from(ordersResponse);
      // 4. Adjuntar id_operacion y filtrar solo las que efectivamente son paquetería.
      final filtered = <Map<String, dynamic>>[];
      for (final o in orders) {
        final opId = ordenIdToOpId[o['id'] as int?];
        if (opId != null) {
          o['_ventiq_operacion_id'] = opId;
        }
        final paq = o['paqueteria'];
        final isPaq = paq is Map && paq.isNotEmpty;
        if (isPaq) filtered.add(o);
      }
      print(
        '✅ paqueteria: órdenes finales = ${filtered.length} '
        '(de ${orders.length} en rango)',
      );
      return filtered;
    } catch (e) {
      print('❌ Error al obtener órdenes de paquetería por tienda: $e');
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

  /// Elimina un detalle de orden y devuelve stock en Carnaval e Inventtia.
  /// Usa RPC `fn_eliminar_order_detail_con_devolucion` (aplicar SQL en Supabase).
  ///
  /// [motivo] queda guardado en la bitácora de capitán. Se manda para poder
  /// distinguir después lo que quitó el repartidor de lo que quitó la oficina.
  static Future<bool> deleteOrderDetail(int detailId, {String? motivo}) async {
    try {
      final response = await _supabase.rpc(
        'fn_eliminar_order_detail_con_devolucion',
        params: {
          'p_detail_id': detailId,
          if (motivo != null && motivo.trim().isNotEmpty)
            'p_motivo': motivo.trim(),
        },
      );

      final result = response is Map
          ? Map<String, dynamic>.from(response)
          : <String, dynamic>{};

      if (result['success'] == true) {
        print(
          '✅ Producto eliminado y stock devuelto '
          '(carnaval: ${result['carnaval_stock_antes']} → '
          '${result['carnaval_stock_despues']}, '
          'operacion: ${result['operacion_id']})',
        );
        return true;
      }

      print('❌ Error al eliminar detalle: ${result['message']}');
      return false;
    } catch (e) {
      print('❌ Error al eliminar detalle: $e');
      return false;
    }
  }

  /// Recalcula el total de una orden sumando price*quantity de sus detalles.
  ///
  /// Con el trigger `trg_orderdetails_ajustar_erp` aplicado esto ya lo hace la
  /// propia base de datos. Se mantiene por si el SQL aún no está aplicado, pero
  /// NO se escribe cuando el total ya está bien: "Orders" tiene dos triggers
  /// (`notificar-proveedores-orden`, `notificar_orden_asignada`) que llaman a
  /// edge functions por HTTP en CADA update, así que un update de gratis son
  /// dos notificaciones de gratis.
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

      final current = await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select('total')
          .eq('id', orderId)
          .maybeSingle();
      final currentTotal = (current?['total'] as num?)?.toDouble();

      // `total` es float4 en la base: se compara con tolerancia porque el
      // redondeo a 32 bits hace que casi nunca sea exactamente igual.
      if (currentTotal != null && (currentTotal - total).abs() < 0.01) {
        return true;
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

  /// Obtiene provincia y municipio de una dirección por su texto.
  /// Solo devuelve nombres de ubicación (nunca `id`), para no pisar
  /// campos de `Orders` al enriquecer la lista.
  static Future<Map<String, dynamic>?> getOrderDireccion(
    String direccionText,
  ) async {
    try {
      final dirResponse = await _supabase
          .schema('carnavalapp')
          .from('Direcciones')
          .select('address, provincia, municipio')
          .eq('address', direccionText)
          .limit(1)
          .maybeSingle();

      if (dirResponse == null) return null;

      final result = <String, dynamic>{'address': dirResponse['address']};
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
        result['municipio_nombre'] = mun?['municipio'];
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

  // ==========================================================================
  // AUDITORÍA CARNIVAL ↔ INVENTTIA
  // ==========================================================================
  // Dos RPCs:
  //  1) fn_audit_carnaval_order_lines  → cantidades en Carnaval
  //  2) fn_audit_inventtia_carnaval_lines → extracciones Inventtia de esas órdenes
  // La app solo cruza ambos resultados y arma las diferencias.

  /// Audita órdenes Carnaval vs operaciones Inventtia vía 2 RPCs.
  ///
  /// Retorna:
  /// `{ ordersChecked, diffsCount, sinOperacion, mismatches, diffs: [...] }`
  /// donde cada diff tiene: `order_id`, `status`, `tipo`, `product_name`,
  /// `carnaval_product_id`, `inventtia_product_id`, `qty_carnaval`,
  /// `qty_inventtia`, `diferencia`, `operation_ids`.
  static Future<Map<String, dynamic>> auditOrdersVsInventtia({
    required int carnavalStoreId,
    required bool isAdmin,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? statusFilter,
    bool excludeCancelled = true,
  }) async {
    try {
      print('🔎 Auditoría vía RPCs Carnaval + Inventtia...');

      DateTime? fechaHasta;
      if (dateTo != null) {
        fechaHasta = DateTime(
          dateTo.year,
          dateTo.month,
          dateTo.day,
          23,
          59,
          59,
        );
      }

      // 1) RPC Carnaval: líneas agregadas por orden + producto
      final carnavalRaw = await _supabase.rpc(
        'fn_audit_carnaval_order_lines',
        params: {
          'p_proveedor_id': isAdmin ? null : carnavalStoreId,
          'p_fecha_desde': dateFrom?.toIso8601String().split('T').first,
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
          'p_status': statusFilter,
          'p_exclude_cancelled': excludeCancelled,
        },
      );

      final carnavalLines = List<Map<String, dynamic>>.from(
        (carnavalRaw as List?) ?? const [],
      );

      if (carnavalLines.isEmpty) {
        return {
          'ordersChecked': 0,
          'diffsCount': 0,
          'sinOperacion': 0,
          'mismatches': 0,
          'diffs': <Map<String, dynamic>>[],
        };
      }

      final orderIds = carnavalLines
          .map((r) => (r['order_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet()
          .toList();

      final orderStatus = <int, String?>{};
      // order_id -> product_id -> {qty, name}
      final carnavalByOrder = <int, Map<int, Map<String, dynamic>>>{};
      for (final row in carnavalLines) {
        final oid = (row['order_id'] as num?)?.toInt();
        final pid = (row['carnaval_product_id'] as num?)?.toInt();
        if (oid == null || pid == null) continue;
        orderStatus[oid] = row['order_status']?.toString();
        final qty = (row['qty_carnaval'] as num?)?.toDouble() ?? 0;
        final name = row['product_name']?.toString();
        final products = carnavalByOrder.putIfAbsent(oid, () => {});
        final existing = products[pid];
        if (existing == null) {
          products[pid] = {'qty': qty, 'name': name};
        } else {
          existing['qty'] = ((existing['qty'] as num?)?.toDouble() ?? 0) + qty;
          existing['name'] ??= name;
        }
      }

      // Tienda Inventtia (solo si no es admin)
      int? inventtiaStoreId;
      if (!isAdmin) {
        try {
          final tienda = await _supabase
              .from('app_dat_tienda')
              .select('id')
              .eq('id_tienda_carnaval', carnavalStoreId)
              .maybeSingle();
          inventtiaStoreId = (tienda?['id'] as num?)?.toInt();
        } catch (_) {}
      }

      // 2) RPC Inventtia: extracciones de esas órdenes
      final inventtiaByOrder = <int, Map<int, Map<String, dynamic>>>{};
      final opsByOrder = <int, Set<int>>{};

      for (final chunk in _chunkList(orderIds, 50)) {
        final inventtiaRaw = await _supabase.rpc(
          'fn_audit_inventtia_carnaval_lines',
          params: {'p_order_ids': chunk, 'p_id_tienda': inventtiaStoreId},
        );

        for (final row in List<Map<String, dynamic>>.from(
          (inventtiaRaw as List?) ?? const [],
        )) {
          final oid = (row['order_id'] as num?)?.toInt();
          if (oid == null) continue;

          final opIdsRaw = row['operation_ids'];
          if (opIdsRaw is List) {
            final set = opsByOrder.putIfAbsent(oid, () => <int>{});
            for (final op in opIdsRaw) {
              final opId = (op as num?)?.toInt();
              if (opId != null) set.add(opId);
            }
          }

          final carnavalPid = (row['carnaval_product_id'] as num?)?.toInt();
          final inventtiaPid = (row['inventtia_product_id'] as num?)?.toInt();
          // Stub de "hay operación sin líneas": solo registra operation_ids.
          if (carnavalPid == null && inventtiaPid == null) continue;

          final key = carnavalPid ?? -inventtiaPid!;

          final qty = (row['qty_inventtia'] as num?)?.toDouble() ?? 0;
          final products = inventtiaByOrder.putIfAbsent(oid, () => {});
          final existing = products[key];
          if (existing == null) {
            products[key] = {
              'qty': qty,
              'name': row['product_name']?.toString(),
              'inventtia_product_id': inventtiaPid,
            };
          } else {
            existing['qty'] =
                ((existing['qty'] as num?)?.toDouble() ?? 0) + qty;
            existing['name'] ??= row['product_name']?.toString();
            existing['inventtia_product_id'] ??= inventtiaPid;
          }
        }
      }

      // 3) Cruzar resultados
      final diffs = <Map<String, dynamic>>[];
      var sinOperacion = 0;
      var mismatches = 0;

      for (final orderId in orderIds) {
        final status = orderStatus[orderId];
        final carnavalProducts = carnavalByOrder[orderId] ?? const {};
        final inventtiaProducts = inventtiaByOrder[orderId] ?? const {};
        final opIds = (opsByOrder[orderId] ?? const <int>{}).toList()..sort();

        if (opIds.isEmpty) {
          if (carnavalProducts.isEmpty) continue;
          sinOperacion++;
          final totalCarnaval = carnavalProducts.values.fold<double>(
            0,
            (a, b) => a + ((b['qty'] as num?)?.toDouble() ?? 0),
          );
          diffs.add({
            'order_id': orderId,
            'status': status,
            'tipo': 'sin_operacion',
            'product_name': null,
            'carnaval_product_id': null,
            'inventtia_product_id': null,
            'qty_carnaval': totalCarnaval,
            'qty_inventtia': 0.0,
            'diferencia': -totalCarnaval,
            'operation_ids': <int>[],
            'lineas_carnaval': carnavalProducts.length,
          });
          continue;
        }

        final allKeys = {...carnavalProducts.keys, ...inventtiaProducts.keys};

        for (final key in allKeys) {
          final c = carnavalProducts[key];
          final i = inventtiaProducts[key];
          final qC = (c?['qty'] as num?)?.toDouble() ?? 0;
          final qI = (i?['qty'] as num?)?.toDouble() ?? 0;
          if ((qC - qI).abs() < 0.0001) continue;

          mismatches++;
          final String tipo;
          if (qC > 0 && qI == 0) {
            tipo = 'solo_carnaval';
          } else if (qI > 0 && qC == 0) {
            tipo = 'solo_inventtia';
          } else {
            tipo = 'cantidad';
          }

          diffs.add({
            'order_id': orderId,
            'status': status,
            'tipo': tipo,
            'product_name':
                c?['name']?.toString() ??
                i?['name']?.toString() ??
                (key > 0
                    ? 'Producto Carnaval #$key'
                    : 'Producto Inventtia #${-key}'),
            'carnaval_product_id': key > 0 ? key : null,
            'inventtia_product_id': i?['inventtia_product_id'],
            'qty_carnaval': qC,
            'qty_inventtia': qI,
            'diferencia': qI - qC,
            'operation_ids': opIds,
          });
        }
      }

      diffs.sort((a, b) {
        final oa = (a['order_id'] as num?)?.toInt() ?? 0;
        final ob = (b['order_id'] as num?)?.toInt() ?? 0;
        if (oa != ob) return ob.compareTo(oa);
        return (a['tipo'] as String).compareTo(b['tipo'] as String);
      });

      print(
        '✅ Auditoría RPC: ${orderIds.length} órdenes, '
        '${diffs.length} diferencias '
        '($sinOperacion sin operación, $mismatches mismatch líneas)',
      );

      return {
        'ordersChecked': orderIds.length,
        'diffsCount': diffs.length,
        'sinOperacion': sinOperacion,
        'mismatches': mismatches,
        'diffs': diffs,
      };
    } catch (e, st) {
      print('❌ Error en auditoría Carnaval ↔ Inventtia: $e');
      print(st);
      rethrow;
    }
  }

  static List<List<T>> _chunkList<T>(List<T> items, int size) {
    if (items.isEmpty) return const [];
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      final end = (i + size > items.length) ? items.length : i + size;
      chunks.add(items.sublist(i, end));
    }
    return chunks;
  }
}
