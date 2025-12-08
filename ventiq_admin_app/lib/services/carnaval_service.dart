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

  /// Desincroniza la tienda de Carnaval
  static Future<void> unsyncStoreFromCarnaval(int storeId) async {
    try {
      print('🔧 Desincronizando tienda ID: $storeId de Carnaval');

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

      // 2. Obtener productos ya sincronizados en Carnaval (por nombre)
      // Nota: Idealmente usaríamos un ID externo, pero por ahora usaremos el nombre
      // para evitar duplicados obvios.
      final carnavalProductsResponse = await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .select('name')
          .eq('proveedor', carnavalStoreId);

      final syncedNames =
          List<Map<String, dynamic>>.from(
            carnavalProductsResponse,
          ).map((p) => p['name'].toString().toLowerCase()).toSet();

      // 3. Filtrar
      final unsyncedProducts =
          localProducts.where((p) {
            final name = p['denominacion'].toString().toLowerCase();
            return !syncedNames.contains(name);
          }).toList();

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
  }) async {
    try {
      // 1. Obtener datos del producto local
      final productData =
          await _supabase
              .from('app_dat_producto')
              .select('denominacion, descripcion, imagen')
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

      final basePrice = priceData?['precio_venta_cup'] ?? 0;

      // Calcular precios con markup:
      // precio_descuento = basePrice + 5.35% (redondeado a entero)
      // price (oficial) = basePrice + 11%
      final precioDescuento = (basePrice * 1.0535).round();
      final precioOficial = basePrice * 1.11;

      // 3. Obtener stock actual (último registro de inventario)
      final stockData =
          await _supabase
              .from('app_dat_inventario_productos')
              .select('cantidad_final')
              .eq('id_producto', localProductId)
              .order('created_at', ascending: false)
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

      return true;
    } catch (e) {
      print('❌ Error al sincronizar producto: $e');
      return false;
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
      final grouped = <String, List<Map<String, dynamic>>>{};

      for (var product in products) {
        final categoryName =
            product['Categorias']?['name']?.toString() ?? 'Sin Categoría';
        if (!grouped.containsKey(categoryName)) {
          grouped[categoryName] = [];
        }
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
}
