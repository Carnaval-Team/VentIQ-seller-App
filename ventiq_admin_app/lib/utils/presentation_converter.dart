import '../services/product_service.dart';

class PresentationConverter {
  /// Procesa un producto aplicando conversión automática a presentación base
  /// y ajustando el precio de compra para que sea unitario por presentación base
  static Future<Map<String, dynamic>> processProductForReception({
    required String productId,
    required Map<String, dynamic>? selectedPresentation,
    required double cantidad,
    required double precioUnitario,
    required Map<String, dynamic> baseProductData,
  }) async {
    try {
      print('🔄 ===== PROCESANDO PRODUCTO PARA RECEPCIÓN =====');
      print('🔄 Producto: $productId');
      print('🔄 Presentación seleccionada: ${selectedPresentation?['id']}');
      print('🔄 Cantidad original: $cantidad');
      print('🔄 Precio unitario ingresado: $precioUnitario');
      print('🔄 DEBUG: selectedPresentation completo: $selectedPresentation');
      print('🔄 DEBUG: Denominación presentación seleccionada: ${selectedPresentation?['denominacion']}');

      // Variables para conversión
      double cantidadFinal = cantidad;
      double precioUnitarioFinal = precioUnitario;
      int? presentacionFinal = selectedPresentation?['id'];
      bool conversionAplicada = false;
      
      // Normalizar la denominación de la presentación seleccionada
      Map<String, dynamic>? normalizedPresentation;
      if (selectedPresentation != null) {
        normalizedPresentation = Map<String, dynamic>.from(selectedPresentation);
        if (normalizedPresentation['denominacion'] == null) {
          normalizedPresentation['denominacion'] = 
            normalizedPresentation['presentacion'] ?? 
            normalizedPresentation['nombre'] ?? 
            normalizedPresentation['tipo'] ?? 
            'Presentación';
        }
      }
      
      // Si hay presentación seleccionada, aplicar conversión automática
      if (selectedPresentation != null && normalizedPresentation != null) {
        // Obtener presentación base
        final productIdInt = int.tryParse(productId);
        if (productIdInt != null) {
          // Obtener presentación base específica del producto seleccionado
          final basePresentation = await ProductService.getBasePresentacion(productIdInt);
          
          print('🔍 DEBUG: Producto ID: $productIdInt');
          print('🔍 DEBUG: Presentación base del producto: $basePresentation');
          
          if (basePresentation != null) {
            final basePresentacionId = basePresentation['id_presentacion'] as int;
            final selectedPresentacionId = normalizedPresentation['id'] as int;
            
            print('🔍 DEBUG: ID presentación base: $basePresentacionId');
            print('🔍 DEBUG: ID presentación seleccionada: $selectedPresentacionId');
            
            // Solo convertir si no es ya la presentación base
            if (selectedPresentacionId != basePresentacionId) {
              print('🔄 Aplicando conversión a presentación base...');
              
              // Convertir cantidad a presentación base usando la cantidad de la presentación seleccionada
              final cantidadPorPresentacion = normalizedPresentation['cantidad'] as double? ?? 1.0;
              cantidadFinal = cantidad * cantidadPorPresentacion;
              
              print('🔄 Conversión directa aplicada:');
              print('   - Cantidad ingresada: $cantidad ${normalizedPresentation['denominacion']}');
              print('   - Cantidad por presentación: $cantidadPorPresentacion');
              print('   - Cantidad final: $cantidadFinal ${basePresentation['denominacion']}');
              
              // El precio ingresado siempre es por presentación base
              // No necesitamos ajustar el precio, se mantiene igual
              precioUnitarioFinal = precioUnitario;
              
              print('🔄 Conversión aplicada (precio por presentación base):');
              print('   - Precio ingresado por ${basePresentation['denominacion']}: $precioUnitario');
              print('   - Precio final por ${basePresentation['denominacion']}: $precioUnitarioFinal');
              print('   - Cantidad convertida: $cantidad ${normalizedPresentation['denominacion']} → $cantidadFinal ${basePresentation['denominacion']}');
              
              presentacionFinal = basePresentacionId;
              conversionAplicada = true;
              
              print('✅ Conversión aplicada:');
              print('   - Cantidad: $cantidad → $cantidadFinal');
              print('   - Presentación: $selectedPresentacionId → $basePresentacionId');
              print('   - Precio unitario: $precioUnitario → $precioUnitarioFinal (sin cambio - precio por presentación base)');
            } else {
              print('✅ Ya es presentación base, no se requiere conversión');
            }
          } else {
            print('⚠️ No se encontró presentación base para el producto, utilizando presentación seleccionada como fallback');
            presentacionFinal = selectedPresentation['id'];
            cantidadFinal = cantidad;
            precioUnitarioFinal = precioUnitario;
            conversionAplicada = false;
          }
        }
      }

      // Crear datos del producto procesado
      final processedData = Map<String, dynamic>.from(baseProductData);
      processedData.addAll({
        'cantidad': cantidadFinal,
        'precio_unitario': precioUnitarioFinal,
        'id_presentacion': presentacionFinal,
        
        // Información para el widget de conversión
        'cantidad_original': cantidad,
        'presentacion_original': selectedPresentation?['id'],
        'precio_original': precioUnitario,
        'conversion_applied': conversionAplicada,
        
        // Agregar información de presentación original para mostrar (usar versión normalizada si existe)
        'presentacion_original_info': normalizedPresentation ?? selectedPresentation,
      });

      // Agregar información de presentación para mostrar
      if (presentacionFinal != null) {
        if (conversionAplicada) {
          final basePresentation = await ProductService.getBasePresentacion(int.tryParse(productId)!);
          if (basePresentation != null) {
            processedData['presentation_info'] = {
              'id': basePresentation['id_presentacion'],
              'denominacion': basePresentation['denominacion'],
              'cantidad': basePresentation['cantidad'],
            };
          }
        } else {
          processedData['presentation_info'] = selectedPresentation;
        }
      }

      print('✅ Producto procesado para recepción:');
      print('   - Cantidad final: $cantidadFinal');
      print('   - Precio unitario final: $precioUnitarioFinal');
      print('   - Presentación final: $presentacionFinal');
      print('   - Conversión aplicada: $conversionAplicada');

      return processedData;
      
    } catch (e) {
      print('❌ Error procesando producto: $e');
      // En caso de error, retornar datos originales
      final fallbackData = Map<String, dynamic>.from(baseProductData);
      fallbackData.addAll({
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
        'id_presentacion': selectedPresentation?['id'],
        'conversion_applied': false,
      });
      return fallbackData;
    }
  }

  /// Procesa un producto aplicando conversión automática para extracciones (ventas)
  /// Convierte de presentación seleccionada a presentación base para extraer del inventario
  static Future<Map<String, dynamic>> processProductForExtraction({
    required String productId,
    required Map<String, dynamic>? selectedPresentation,
    required double cantidad,
    required Map<String, dynamic> baseProductData,
  }) async {
    try {
      print('🔄 ===== PROCESANDO PRODUCTO PARA EXTRACCIÓN (VENTA) =====');
      print('🔄 Producto: $productId');
      print('🔄 Presentación seleccionada: ${selectedPresentation?['id']}');
      print('🔄 Cantidad a vender: $cantidad');
      print('🔄 DEBUG: selectedPresentation completo: $selectedPresentation');
      print('🔄 DEBUG: Denominación presentación seleccionada: ${selectedPresentation?['denominacion']}');

      // Variables para conversión
      double cantidadFinal = cantidad;
      int? presentacionFinal = selectedPresentation?['id'];
      bool conversionAplicada = false;
      
      // Normalizar la denominación de la presentación seleccionada
      Map<String, dynamic>? normalizedPresentation;
      if (selectedPresentation != null) {
        normalizedPresentation = Map<String, dynamic>.from(selectedPresentation);
        if (normalizedPresentation['denominacion'] == null) {
          normalizedPresentation['denominacion'] = 
            normalizedPresentation['presentacion'] ?? 
            normalizedPresentation['nombre'] ?? 
            normalizedPresentation['tipo'] ?? 
            'Presentación';
        }
      }
      
      // Si hay presentación seleccionada, aplicar conversión automática
      if (selectedPresentation != null && normalizedPresentation != null) {
        final productIdInt = int.tryParse(productId);
        if (productIdInt != null) {
          // Obtener presentación base específica del producto seleccionado
          final basePresentation = await ProductService.getBasePresentacion(productIdInt);
          
          print('🔍 DEBUG: Producto ID: $productIdInt');
          print('🔍 DEBUG: Presentación base del producto: $basePresentation');
          
          if (basePresentation != null) {
            final basePresentacionId = basePresentation['id_presentacion'] as int;
            final selectedPresentacionId = normalizedPresentation['id'] as int;
            
            print('🔍 DEBUG: ID presentación base: $basePresentacionId');
            print('🔍 DEBUG: ID presentación seleccionada: $selectedPresentacionId');
            
            // Solo convertir si no es ya la presentación base
            if (selectedPresentacionId != basePresentacionId) {
              print('🔄 Aplicando conversión para extracción...');
              
              // Convertir cantidad a presentación base usando la cantidad de la presentación seleccionada
              final cantidadPorPresentacion = normalizedPresentation['cantidad'] as double? ?? 1.0;
              cantidadFinal = cantidad * cantidadPorPresentacion;
              
              print('🔄 Conversión para extracción aplicada:');
              print('   - Cantidad a vender: $cantidad ${normalizedPresentation['denominacion']}');
              print('   - Cantidad por presentación: $cantidadPorPresentacion');
              print('   - Cantidad a extraer del inventario: $cantidadFinal ${basePresentation['denominacion']}');
              
              // Para extracciones, guardamos la presentación base para consistencia de inventario
              presentacionFinal = basePresentacionId;
              
              print('🔄 Extracción configurada:');
              print('   - Presentación final en BD: ${basePresentation['denominacion']} (ID: $basePresentacionId)');
              
              conversionAplicada = true;
              
              print('✅ Conversión para extracción aplicada:');
              print('   - Cantidad: $cantidad → $cantidadFinal');
              print('   - Presentación en BD: $selectedPresentacionId → $basePresentacionId');
            } else {
              print('✅ Ya es presentación base, no se requiere conversión');
            }
          } else {
            print('⚠️ No se encontró presentación base para el producto, utilizando presentación seleccionada como fallback');
            presentacionFinal = selectedPresentation['id'];
            cantidadFinal = cantidad;
            conversionAplicada = false;
          }
        }
      }

      // Crear datos del producto procesado para extracción
      final processedData = Map<String, dynamic>.from(baseProductData);
      processedData.addAll({
        'cantidad': cantidadFinal, // Cantidad a extraer del inventario (en presentación base)
        'id_presentacion': presentacionFinal,
        
        // Información para el widget de conversión y UI
        'cantidad_original': cantidad, // Cantidad que el usuario quiere vender
        'presentacion_original': selectedPresentation?['id'],
        'conversion_applied': conversionAplicada,
        
        // Agregar información de presentación original para mostrar (usar versión normalizada si existe)
        'presentacion_original_info': normalizedPresentation ?? selectedPresentation,
      });

      // Agregar información de presentación para mostrar
      if (presentacionFinal != null) {
        if (conversionAplicada) {
          final basePresentation = await ProductService.getBasePresentacion(int.tryParse(productId)!);
          if (basePresentation != null) {
            processedData['presentation_info'] = {
              'id': basePresentation['id_presentacion'],
              'denominacion': basePresentation['denominacion'],
              'cantidad': basePresentation['cantidad'],
            };
          }
        } else {
          processedData['presentation_info'] = selectedPresentation;
        }
      }

      print('✅ Producto procesado para extracción:');
      print('   - Cantidad a extraer: $cantidadFinal');
      print('   - Presentación final: $presentacionFinal');
      print('   - Conversión aplicada: $conversionAplicada');

      return processedData;
      
    } catch (e) {
      print('❌ Error procesando producto para extracción: $e');
      // En caso de error, retornar datos originales
      final fallbackData = Map<String, dynamic>.from(baseProductData);
      fallbackData.addAll({
        'cantidad': cantidad,
        'id_presentacion': selectedPresentation?['id'],
        'conversion_applied': false,
      });
      return fallbackData;
    }
  }
}
