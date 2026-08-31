import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

import 'currency_service.dart';

class CatalogoService {
  static final CatalogoService _instance = CatalogoService._internal();
  factory CatalogoService() => _instance;
  CatalogoService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Verifica si una tienda puede habilitar el catálogo
  /// Ahora todos los usuarios pueden habilitar el catálogo con cualquier plan
  Future<bool> tienePlanCatalogo(int idTienda) async {
    try {
      print('✅ Catálogo habilitado para todos los planes (tienda: $idTienda)');
      return true;
    } catch (e) {
      print('❌ Error verificando catálogo: $e');
      return false;
    }
  }

  /// Obtiene el tipo de plan actual de la tienda
  Future<String?> obtenerTipoPlan(int idTienda) async {
    try {
      final response = await _supabase
          .from('app_suscripciones')
          .select('''
            app_suscripciones_plan (
              denominacion
            )
          ''')
          .eq('id_tienda', idTienda)
          .eq('estado', 1)
          .order('fecha_fin', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final planData = response['app_suscripciones_plan'] as Map<String, dynamic>?;
      return planData?['denominacion'] as String?;
    } catch (e) {
      print('❌ Error obteniendo tipo de plan: $e');
      return null;
    }
  }

  /// Obtiene todos los productos de una tienda con validación para catálogo
  Future<List<Map<String, dynamic>>> obtenerProductosCatalogo(int idTienda) async {
    try {
      print('📦 Obteniendo productos para catálogo de tienda: $idTienda');
      
      final response = await _supabase.rpc(
        'get_productos_catalogo_validacion',
        params: {'p_id_tienda': idTienda},
      );

      if (response == null) {
        print('⚠️ Respuesta nula del RPC');
        return [];
      }

      // Convertir respuesta a lista de mapas
      final productos = response is List 
          ? List<Map<String, dynamic>>.from(response)
          : [response as Map<String, dynamic>];
      
      print('✅ Productos obtenidos: ${productos.length}');
      return productos;
    } catch (e) {
      print('❌ Error obteniendo productos: $e');
      rethrow;
    }
  }

  /// Actualiza el estado mostrar_en_catalogo de un producto
  Future<Map<String, dynamic>> actualizarMostrarEnCatalogo(
    int idProducto,
    int idTienda,
    bool mostrarEnCatalogo,
  ) async {
    try {
      print('🔄 Actualizando mostrar_en_catalogo para producto: $idProducto');
      
      final response = await _supabase.rpc(
        'actualizar_mostrar_en_catalogo',
        params: {
          'p_id_producto': idProducto,
          'p_id_tienda': idTienda,
          'p_mostrar_en_catalogo': mostrarEnCatalogo,
        },
      );

      if (response == null || response.isEmpty) {
        throw Exception('Respuesta nula del RPC');
      }

      final result = response.first as Map<String, dynamic>;
      
      if (result['success'] == true) {
        print('✅ Producto actualizado: ${result['message']}');
      } else {
        print('⚠️ Error: ${result['message']}');
      }

      return result;
    } catch (e) {
      print('❌ Error actualizando producto: $e');
      rethrow;
    }
  }

  /// Actualiza el estado mostrar_en_catalogo de la tienda
  /// Todos los usuarios pueden habilitar el catálogo sin restricciones de plan
  Future<bool> actualizarMostrarEnCatalogoTienda(
    int idTienda,
    bool mostrarEnCatalogo, {
    int? layoutCatalogo,
  }) async {
    try {
      print('🏪 Actualizando mostrar_en_catalogo para tienda: $idTienda');
      
      final Map<String, dynamic> updates = {
        'mostrar_en_catalogo': mostrarEnCatalogo
      };

      if (layoutCatalogo != null) {
        updates['layout_catalogo'] = layoutCatalogo;
      }
      
      await _supabase
          .from('app_dat_tienda')
          .update(updates)
          .eq('id', idTienda);

      print('✅ Tienda actualizada - Catálogo ${mostrarEnCatalogo ? 'habilitado' : 'deshabilitado'}');
      return true;
    } catch (e) {
      print('❌ Error actualizando tienda: $e');
      rethrow;
    }
  }

  /// Obtiene el estado mostrar_en_catalogo de la tienda
  Future<bool> obtenerMostrarEnCatalogoTienda(int idTienda) async {
    try {
      print('🔍 Obteniendo estado mostrar_en_catalogo de tienda: $idTienda');
      
      final response = await _supabase
          .from('app_dat_tienda')
          .select('mostrar_en_catalogo')
          .eq('id', idTienda)
          .single();

      final mostrar = response['mostrar_en_catalogo'] as bool? ?? false;
      print('✅ Estado: $mostrar');
      return mostrar;
    } catch (e) {
      print('❌ Error obteniendo estado: $e');
      return false;
    }
  }

  /// Valida si un producto cumple los requisitos para catálogo
  bool validarProductoParaCatalogo(Map<String, dynamic> producto) {
    final tieneDenominacion = producto['tiene_denominacion'] == true;
    final tienePrecio = producto['tiene_precio'] == true;
    final tieneImagen = producto['tiene_imagen'] == true;
    final tienePresentacion = producto['tiene_presentacion'] == true;

    return tieneDenominacion && tienePrecio && tieneImagen && tienePresentacion;
  }

  /// Obtiene los requisitos faltantes de un producto
  List<String> obtenerRequisitosFaltantes(Map<String, dynamic> producto) {
    final faltantes = <String>[];

    if (producto['tiene_denominacion'] != true) {
      faltantes.add('Denominación');
    }
    if (producto['tiene_precio'] != true) {
      faltantes.add('Precio');
    }
    if (producto['tiene_imagen'] != true) {
      faltantes.add('Imagen');
    }
    if (producto['tiene_presentacion'] != true) {
      faltantes.add('Presentación');
    }

    return faltantes;
  }

  /// Actualiza la denominación de un producto
  Future<bool> actualizarDenominacion(int idProducto, String nuevaDenominacion) async {
    try {
      print('🔄 Actualizando denominación del producto: $idProducto');
      
      await _supabase
          .from('app_dat_producto')
          .update({'denominacion': nuevaDenominacion})
          .eq('id', idProducto);

      print('✅ Denominación actualizada');
      return true;
    } catch (e) {
      print('❌ Error actualizando denominación: $e');
      rethrow;
    }
  }

  /// Actualiza el precio de un producto
  Future<bool> actualizarPrecio(int idProducto, double nuevoPrecio) async {
    try {
      print('💰 Actualizando precio del producto: $idProducto');

      double? precioUsd;
      if (nuevoPrecio > 0) {
        final rate = await CurrencyService.getEffectiveUsdToCupRate();
        if (rate > 0) {
          precioUsd = (nuevoPrecio / rate).roundToDouble();
        }
      }

      final precioData = {
        'id_producto': idProducto,
        'precio_venta_cup': nuevoPrecio,
        if (precioUsd != null && precioUsd > 0)
          'precio_venta_usd': precioUsd,
        'fecha_desde':
            DateTime.now().toString().split(' ')[0], // Formato YYYY-MM-DD
      };

      // Insertar nuevo registro de precio con fecha_desde actual
      await _supabase.from('app_dat_precio_venta').insert(precioData);

      print('✅ Precio actualizado (CUP: $nuevoPrecio, USD: $precioUsd)');
      return true;
    } catch (e) {
      print('❌ Error actualizando precio: $e');
      rethrow;
    }
  }

  /// Sube una imagen y actualiza el producto
  Future<bool> actualizarImagen(int idProducto, File imageFile) async {
    try {
      print('📤 Subiendo imagen para producto: $idProducto');
      
      // Generar nombre único para la imagen
      final uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_producto_$idProducto.jpg';
      
      // Leer archivo como bytes
      final imageBytes = await imageFile.readAsBytes();
      
      // Subir imagen al bucket 'images_back'
      final response = await _supabase.storage
          .from('images_back')
          .uploadBinary(
            uniqueFileName,
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      if (response.isEmpty) {
        throw Exception('Error al subir la imagen');
      }

      // Obtener URL pública de la imagen
      final publicUrl = _supabase.storage
          .from('images_back')
          .getPublicUrl(uniqueFileName);

      // Actualizar el producto con la nueva URL de imagen
      await _supabase
          .from('app_dat_producto')
          .update({'imagen': publicUrl})
          .eq('id', idProducto);

      print('✅ Imagen subida y actualizada: $publicUrl');
      return true;
    } catch (e) {
      print('❌ Error subiendo imagen: $e');
      rethrow;
    }
  }

  /// Actualiza múltiples campos del producto
  Future<bool> actualizarProducto({
    required int idProducto,
    String? denominacion,
    double? precio,
    File? imagen,
  }) async {
    try {
      print('🔄 Actualizando producto: $idProducto');
      
      // Actualizar denominación si se proporciona
      if (denominacion != null && denominacion.isNotEmpty) {
        await actualizarDenominacion(idProducto, denominacion);
      }

      // Actualizar precio si se proporciona
      if (precio != null && precio > 0) {
        await actualizarPrecio(idProducto, precio);
      }

      // Actualizar imagen si se proporciona
      if (imagen != null) {
        await actualizarImagen(idProducto, imagen);
      }

      print('✅ Producto actualizado correctamente');
      return true;
    } catch (e) {
      print('❌ Error actualizando producto: $e');
      rethrow;
    }
  }
}
