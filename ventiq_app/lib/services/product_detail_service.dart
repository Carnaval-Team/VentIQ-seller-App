import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
// FASE 7 P0: cascada de presentaciones local (replica `fn_presentaciones_producto`)
// para resolver el equivalente base de cada ingrediente. Ver
// `getProductIngredients` y `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md`.
import '../utils/presentacion_cadena_local.dart';
import 'user_preferences_service.dart';

class ProductDetailService {
  static final ProductDetailService _instance =
      ProductDetailService._internal();
  factory ProductDetailService() => _instance;
  ProductDetailService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  /// Alcance con el que `getProductIngredients` midió el stock.
  ///
  /// FASE 7 P1 (task-12): el servidor valida con UN almacén
  /// (`fn_validar_ingredientes_elaborado(..., p_id_almacen)`), así que el
  /// cliente debe medir con el mismo. Estos valores viajan en el mapa de cada
  /// ingrediente bajo `alcance_stock` para que la UI no mienta.
  ///
  /// - [alcanceAlmacenTpv]: se midió con el almacén que la venta va a usar, el
  ///   que resuelve `fn_resolver_origen_venta(elaborado, tpv)`: normalmente el
  ///   del TPV y el de la cocina en las rutas de cocina. Es el caso bueno.
  /// - [alcanceTodosLosAlmacenes]: no se pudo resolver el almacén, se midió con
  ///   `p_id_almacen = NULL`. Puede SOBREESTIMAR respecto al servidor.
  /// - [alcanceDesconocido]: fallback (sin cadena de presentaciones o RPC no
  ///   disponible): una sola fila, sin alcance de almacén.
  /// - [alcanceCacheOffline]: dato del cache offline, no del servidor.
  /// - [alcanceTienda]: RESERVADO. Si la decisión pendiente del plan (Fase 5,
  ///   «alcance del consumo») pasa a tienda, `p_alcance` deberá propagarse aquí:
  ///   el punto de cambio es `_disponibleBaseIngrediente`, que hoy llama
  ///   `fn_stock_producto_almacen_detalle` (p_id_almacen). Mientras esa decisión
  ///   no exista, NO se usa.
  static const String alcanceAlmacenTpv = 'almacen_tpv';
  static const String alcanceTodosLosAlmacenes = 'todos_los_almacenes';
  static const String alcanceDesconocido = 'desconocido';
  static const String alcanceCacheOffline = 'cache_offline';
  static const String alcanceTienda = 'tienda_reservado';

  /// Fetch detailed product information.
  ///
  /// Offline-aware: si el modo offline está activado, NO llama a Supabase;
  /// reconstruye el producto desde `detalles_completos` ya sincronizado en
  /// `offline_data['products']` (misma forma que get_detalle_producto), usando
  /// el mismo parser `_transformToProduct`. Así los flujos de venta (Fluido,
  /// paquetería, órdenes) funcionan sin conexión con variantes/inventario.
  Future<Product> getProductDetail(
    int productId, {
    double? fallbackStock,
  }) async {
    try {
      final isOffline = await _userPrefs.shouldUseLocalData();
      if (isOffline) {
        final offlineDetail = await _getProductDetailOffline(productId);
        if (offlineDetail != null) {
          debugPrint('🔌 Detalles del producto $productId desde cache offline');
          return offlineDetail;
        }
        // Sin detalles completos en cache: lanzar para que el llamador caiga a
        // su fallback (producto básico) en vez de intentar la red.
        throw Exception('Sin detalles offline para el producto $productId');
      }

      debugPrint('🔍 Obteniendo detalles del producto ID: $productId');

      final response = await _supabase.rpc(
        'get_detalle_producto',
        params: {'id_producto_param': productId},
      );

      if (response == null) {
        throw Exception('No se recibieron datos del producto');
      }

      debugPrint('📦 Respuesta de detalles recibida');

      // Transform Supabase response to Product model
      return _transformToProduct(response, fallbackStock: fallbackStock);
    } catch (e, stackTrace) {
      debugPrint('❌ Error obteniendo detalles del producto: $e');
      debugPrint('📍 Stack trace completo:\n$stackTrace');
      rethrow;
    }
  }

  /// Busca `detalles_completos` del producto en el cache offline y lo
  /// transforma a Product. Devuelve null si no hay datos completos guardados.
  Future<Product?> _getProductDetailOffline(int productId) async {
    final offlineData = await _userPrefs.getOfflineData();
    final products = offlineData?['products'];
    if (products is! Map) return null;

    for (final categoryProducts in products.values) {
      if (categoryProducts is! List) continue;
      for (final prod in categoryProducts) {
        if (prod is! Map) continue;
        final map = Map<String, dynamic>.from(prod);
        final pid = map['id'];
        final id = pid is int ? pid : (pid is num ? pid.toInt() : null);
        if (id != productId) continue;

        final detalle = map['detalles_completos'];
        if (detalle is Map) {
          final fallback = (map['cantidad'] as num?)?.toDouble();
          return _transformToProduct(
            Map<String, dynamic>.from(detalle),
            fallbackStock: fallback,
          );
        }
        return null; // producto encontrado pero sin detalles completos
      }
    }
    return null;
  }

  /// Obtiene los detalles completos de MÚLTIPLES productos en UNA sola llamada
  /// (RPC batch get_detalles_productos_batch). Elimina el patrón N+1 al
  /// sincronizar el catálogo offline.
  ///
  /// Devuelve un mapa { id_producto : { 'producto': {...}, 'inventario': [...] } }
  /// con la MISMA forma que get_detalle_producto por producto.
  ///
  /// Si el RPC batch no existe aún en el servidor (no se ha subido el .sql),
  /// hace fallback automático a llamadas individuales para no romper la app.
  Future<Map<int, dynamic>> getProductDetailsBatch(List<int> productIds) async {
    final Map<int, dynamic> result = {};
    if (productIds.isEmpty) return result;

    try {
      final response = await _supabase.rpc(
        'get_detalles_productos_batch',
        params: {'ids_param': productIds},
      );

      if (response is Map) {
        response.forEach((key, value) {
          final id = int.tryParse(key.toString());
          if (id != null) result[id] = value;
        });
        debugPrint(
          '✅ Batch detalles: ${result.length}/${productIds.length} productos en 1 RPC',
        );
        return result;
      }
    } catch (e) {
      debugPrint(
        '⚠️ RPC batch get_detalles_productos_batch no disponible ($e). '
        'Fallback a llamadas individuales.',
      );
    }

    // Fallback: una llamada por producto (comportamiento previo).
    for (final id in productIds) {
      try {
        final detail = await _supabase.rpc(
          'get_detalle_producto',
          params: {'id_producto_param': id},
        );
        if (detail != null) result[id] = detail;
      } catch (e) {
        debugPrint('⚠️ Error detalle producto $id (fallback): $e');
      }
    }
    return result;
  }

  /// Transform Supabase response to Product model.
  /// [fallbackStock] se usa cuando inventario viene vacío (p.ej. sync admin
  /// sin almacenes de vendedor) para alinear con el stock del listado offline.
  Product _transformToProduct(
    Map<String, dynamic> response, {
    double? fallbackStock,
  }) {
    final productRaw = response['producto'];
    if (productRaw is! Map) {
      throw Exception('Detalle offline sin bloque producto');
    }
    final productData = Map<String, dynamic>.from(productRaw);
    final inventoryData = List<dynamic>.from(
      response['inventario'] as List? ?? [],
    );
    print('elaborado: ${productData['es_elaborado']}');
    debugPrint(
      '🔍 Transformando producto con ${inventoryData.length} items de inventario',
    );

    // Extract basic product information
    final id = productData['id'] as int;
    final denominacion = productData['denominacion'] as String? ?? 'Sin nombre';
    final descripcion = productData['descripcion'] as String?;
    final precioActual =
        (productData['precio_actual'] as num?)?.toDouble() ?? 0.0;
    final esRefrigerado = productData['es_refrigerado'] as bool? ?? false;
    final esFragil = productData['es_fragil'] as bool? ?? false;
    final esPeligroso = productData['es_peligroso'] as bool? ?? false;
    final esElaborado = productData['es_elaborado'] as bool? ?? false;

    // Extract category information
    final categoria = productData['categoria'] as Map<String, dynamic>?;
    final categoryName =
        categoria?['denominacion'] as String? ?? 'Sin categoría';

    // Transform inventory data to variants
    final variants = _transformInventoryToVariants(inventoryData, precioActual);

    // Calculate total stock from all variants
    double totalStock = 0;
    double totalReservadoCarnaval = 0;
    double totalEnOrdenesCarnaval = 0;
    Map<String, dynamic>? productInventoryMetadata;

    if (variants.isNotEmpty) {
      totalStock = variants.fold<double>(
        0,
        (sum, variant) => sum + variant.cantidad.toDouble(),
      );
      totalReservadoCarnaval = variants.fold<double>(
        0,
        (sum, variant) => sum + variant.reservadoCarnaval.toDouble(),
      );
      totalEnOrdenesCarnaval = variants.fold<double>(
        0,
        (sum, variant) => sum + variant.enOrdenesCarnaval.toDouble(),
      );
    } else {
      // If no variants, use inventory data for the product itself
      Map<String, dynamic>? firstInventory;
      for (final e in inventoryData) {
        if (e is Map) {
          firstInventory = Map<String, dynamic>.from(e);
          break;
        }
      }
      if (firstInventory != null) {
        totalStock =
            (firstInventory['cantidad_disponible'] as num?)?.toDouble() ?? 0;

        // Store inventory metadata for products without variants
        productInventoryMetadata = _extractInventoryMetadata(firstInventory);
        debugPrint(
          '📦 Producto sin variantes - metadata: $productInventoryMetadata',
        );
      } else {
        totalStock = 0;
      }
    }

    // Alinear con stock del listado cuando el inventario filtrado viene vacío.
    if (totalStock <= 0 && fallbackStock != null && fallbackStock > 0) {
      debugPrint(
        '📦 Usando stock del listado ($fallbackStock) — inventario vacío/filtrado',
      );
      totalStock = fallbackStock;
    }

    // Generate product image URL from multimedias or fallback
    String? imageUrl;

    // Debug output for raw image data
    print('📸 Raw data from Supabase for product ${productData['id']}:');
    print('   - multimedias: ${productData['multimedias']}');
    print('   - foto: ${productData['foto']}');

    if (productData['multimedias'] != null &&
        productData['multimedias'] is List) {
      final multimedias = productData['multimedias'] as List;
      if (multimedias.isNotEmpty) {
        final firstMedia = multimedias[0];
        if (firstMedia is Map && firstMedia['url'] != null) {
          imageUrl = firstMedia['url'];
        }
      }
    }

    // Fallback to foto field if multimedias is empty or null
    if (imageUrl == null &&
        productData['foto'] != null &&
        productData['foto'].toString().isNotEmpty) {
      imageUrl = productData['foto'];
    }

    if (imageUrl == null && productData['imagen'] != null) {
      imageUrl = productData['imagen'];
    }

    // Final fallback to random image
    if (imageUrl == null) {
      final hash = denominacion.hashCode.abs();
      final imageId = 200 + (hash % 800); // Range 200-999
      imageUrl = 'https://picsum.photos/id/$imageId/400/400';
    }

    return Product(
      id: id,
      denominacion: denominacion,
      descripcion: descripcion,
      foto: imageUrl,
      precio: precioActual,
      cantidad: totalStock,
      esRefrigerado: esRefrigerado,
      esFragil: esFragil,
      esPeligroso: esPeligroso,
      esVendible: true, // Default value
      esComprable: true, // Default value
      esInventariable: true, // Default value
      esPorLotes: productData['es_por_lotes'] as bool? ?? false,
      esElaborado: productData['es_elaborado'] as bool? ?? false,
      esServicio: productData['es_servicio'] as bool? ?? false,
      esPaquete: productData['es_paquete'] as bool? ?? false,
      categoria: categoryName,
      variantes: variants,
      inventoryMetadata: productInventoryMetadata,
      reservadoCarnaval: totalReservadoCarnaval,
      enOrdenesCarnaval: totalEnOrdenesCarnaval,
    );
  }

  /// Transform inventory data to ProductVariant objects
  List<ProductVariant> _transformInventoryToVariants(
    List<dynamic> inventoryData, [
    double? productPrice,
  ]) {
    final List<ProductVariant> variants = [];

    for (int i = 0; i < inventoryData.length; i++) {
      final raw = inventoryData[i];
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);

      // Extract variant information
      final variante =
          item['variante'] is Map
              ? Map<String, dynamic>.from(item['variante'] as Map)
              : null;
      final presentacion =
          item['presentacion'] is Map
              ? Map<String, dynamic>.from(item['presentacion'] as Map)
              : null;
      final cantidadDisponible =
          (item['cantidad_disponible'] as num?)?.toDouble() ?? 0;
      final reservadoCarnaval =
          (item['reservado_carnaval'] as num?)?.toDouble() ?? 0;
      final enOrdenesCarnaval =
          (item['en_ordenes_carnaval'] as num?)?.toDouble() ?? 0;

      String variantName = 'Variante ${i + 1}';
      String variantDescription = '';

      if (variante != null) {
        final opcion = variante['opcion'] as Map<String, dynamic>?;
        final atributo = variante['atributo'] as Map<String, dynamic>?;

        if (opcion != null && atributo != null) {
          final valor = opcion['valor'] as String? ?? '';
          final label = atributo['label'] as String? ?? '';
          variantName = '$label: $valor';
          variantDescription = 'Variante de $label con valor $valor';
        }
      }

      if (presentacion != null) {
        final presentacionNombre =
            presentacion['denominacion'] as String? ?? '';
        final cantidad = (presentacion['cantidad'] as num?)?.toInt() ?? 1;
        if (presentacionNombre.isNotEmpty) {
          variantName += ' - $presentacionNombre';
          if (cantidad > 1) {
            variantDescription += ' (Presentación: $cantidad unidades)';
          }
        }
      }

      // Extract variant price or use product price as fallback
      double precio = productPrice ?? 0.0;

      // Try to get variant-specific price from the data
      if (item['precio'] != null) {
        precio = (item['precio'] as num).toDouble();
      } else if (variante != null && variante['precio'] != null) {
        precio = (variante['precio'] as num).toDouble();
      } else if (presentacion != null && presentacion['precio'] != null) {
        precio = (presentacion['precio'] as num).toDouble();
      }

      // Extract inventory metadata for this variant
      final variantInventoryMetadata = _extractInventoryMetadata(item);
      debugPrint('🔧 Variante ${i + 1} - metadata: $variantInventoryMetadata');

      variants.add(
        ProductVariant(
          id: i + 1, // Generate sequential IDs
          nombre: variantName,
          precio: precio,
          cantidad: cantidadDisponible,
          descripcion:
              variantDescription.isNotEmpty ? variantDescription : null,
          inventoryMetadata: variantInventoryMetadata,
          reservadoCarnaval: reservadoCarnaval,
          enOrdenesCarnaval: enOrdenesCarnaval,
        ),
      );
    }

    return variants;
  }

  /// Extract inventory metadata from inventory item
  Map<String, dynamic> _extractInventoryMetadata(
    Map<String, dynamic> inventoryItem,
  ) {
    final variante =
        inventoryItem['variante'] is Map
            ? Map<String, dynamic>.from(inventoryItem['variante'] as Map)
            : null;
    final presentacion =
        inventoryItem['presentacion'] is Map
            ? Map<String, dynamic>.from(inventoryItem['presentacion'] as Map)
            : null;
    final ubicacion =
        inventoryItem['ubicacion'] is Map
            ? Map<String, dynamic>.from(inventoryItem['ubicacion'] as Map)
            : null;

    return {
      'id_inventario': inventoryItem['id_inventario'],
      'id_variante': variante?['id'],
      'id_opcion_variante': variante?['opcion']?['id'],
      'id_presentacion': presentacion?['id'],
      'id_ubicacion': inventoryItem['id_ubicacion'] ?? ubicacion?['id'],
      'id_almacen': ubicacion?['almacen']?['id'],
      'sku_producto': inventoryItem['sku_producto'],
      'sku_ubicacion':
          inventoryItem['sku_ubicacion'] ?? ubicacion?['sku_codigo'],
      'cantidad_disponible': inventoryItem['cantidad_disponible'],
      'presentacion_nombre': presentacion?['denominacion']?.toString(),
      // En get_detalle_producto, `presentacion.cantidad` es el factor de la
      // presentación respecto a la unidad base (misma idea que factor_rel).
      'presentacion_factor_rel':
          (presentacion?['cantidad'] as num?)?.toDouble() ?? 1.0,
      'ubicacion_nombre':
          (() {
            for (final v in [
              inventoryItem['ubicacion_nombre'],
              inventoryItem['denominacion_ubicacion'],
              inventoryItem['ubicacion_label'],
              ubicacion?['denominacion'],
            ]) {
              final s = v?.toString();
              if (s != null && s.isNotEmpty) return s;
            }
            return null;
          })(),
      'almacen_nombre':
          (() {
            for (final v in [
              inventoryItem['almacen_nombre'],
              ubicacion?['almacen']?['denominacion'],
            ]) {
              final s = v?.toString();
              if (s != null && s.isNotEmpty) return s;
            }
            return null;
          })(),
    };
  }

  /// Verifica si un producto es elaborado o servicio.
  ///
  /// Offline-aware: si el modo offline/full-offline está activo, no llama a
  /// Supabase (fallaría con `Failed host lookup` sin conexión); usa el
  /// mismo cache de `detalles_completos` que [getProductDetail].
  Future<bool> isProductElaborated(int productId) async {
    if (await _userPrefs.shouldUseLocalData()) {
      final offlineDetail = await _getProductDetailOffline(productId);
      return (offlineDetail?.esElaborado ?? false) ||
          (offlineDetail?.esServicio ?? false);
    }

    try {
      debugPrint(
        '🔍 Verificando si producto $productId es elaborado o servicio...',
      );

      final response =
          await _supabase
              .from('app_dat_producto')
              .select('es_elaborado,es_servicio')
              .eq('id', productId)
              .single();

      final isElaborated = response['es_elaborado'] ?? false;
      final isServicio = response['es_servicio'] ?? false;
      debugPrint(
        '🔍 Producto $productId - es_elaborado: $isElaborated, es_servicio: $isServicio',
      );
      debugPrint('🔍 Respuesta completa: $response');

      return isElaborated || isServicio;
    } catch (e) {
      debugPrint(
        '❌ Error verificando si producto $productId es elaborado/servicio: $e',
      );
      return false;
    }
  }

  /// Verifica si un producto es servicio (para diferenciar chip visual).
  /// Offline-aware: ver [isProductElaborated].
  Future<bool> isProductServicio(int productId) async {
    if (await _userPrefs.shouldUseLocalData()) {
      final offlineDetail = await _getProductDetailOffline(productId);
      return offlineDetail?.esServicio ?? false;
    }

    try {
      final response =
          await _supabase
              .from('app_dat_producto')
              .select('es_servicio')
              .eq('id', productId)
              .single();

      return response['es_servicio'] ?? false;
    } catch (e) {
      debugPrint('❌ Error verificando si producto $productId es servicio: $e');
      return false;
    }
  }

  /// Obtiene los ingredientes de un producto elaborado con su cantidad
  /// disponible actual **en unidades base**.
  ///
  /// FASE 7 P0 de `docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md`
  /// (§0 y §2-bis).
  ///
  /// Defecto que corrige: antes se leía UNA sola fila
  /// (`created_at DESC LIMIT 1`) y su `cantidad_final` cruda se devolvía como si
  /// fuera el total. Con Arroz (Unidad 2000 + Kilogramo 2000) eso da 2000 y el
  /// preorden bloquea una venta que necesita 6000 base, mientras el servidor
  /// (`fn_validar_ingredientes_elaborado`) la aprueba con 2.002.000.
  ///
  /// Ahora:
  ///  - `cantidad_disponible` = equivalente base =
  ///    Σ (cantidad_final × factor_rel) de las filas **vigentes** por
  ///    ubicación/variante/opción/presentación. Es lo que se compara contra
  ///    `cantidad_necesaria` (la receta viene en unidades base).
  ///  - `cantidad_disponible_fisica` = Σ cantidad_final sin factor (informativo).
  ///  - `desglose_presentaciones` = detalle por presentación para la UI.
  ///  - `unidad_medida` se rellena con el nombre de la presentación base cuando
  ///    la receta lo trae nulo (caso real: la receta de Arroz Moro).
  ///
  /// Las filas vigentes se piden al servidor con
  /// `fn_stock_producto_almacen_detalle` —la MISMA fuente que usa
  /// `fn_stock_producto_almacen` y con ella la validación del servidor— en vez
  /// de bajar el ledger completo: `app_dat_inventario_productos` tiene ~402k
  /// filas y hay productos con más de 7.900. El factor se aplica con
  /// `PresentacionCadenaLocal`, que replica `fn_presentaciones_producto`.
  ///
  /// Alcance: `idAlmacen` es el **almacén del TPV activo** (mismo origen que
  /// usa la venta: `app_dat_tpv.id_almacen` / `UserPreferencesService.getIdAlmacen()`).
  /// Se pasa tal cual a `fn_stock_producto_almacen_detalle(p_id_almacen)`, que
  /// es lo que hace el servidor al validar. Si es `null` (no se pudo resolver),
  /// se mide con todos los almacenes y cada ingrediente se etiqueta con
  /// [alcanceTodosLosAlmacenes] para no mentir. Parámetro opcional: la firma
  /// pública previa (`getProductIngredients(id)`) sigue funcionando.
  ///
  /// FALLBACK (no empeorar): si el ingrediente no tiene cadena de
  /// presentaciones o si la RPC falla, se devuelve el comportamiento anterior
  /// (una sola fila, la más reciente por `created_at`) etiquetado como
  /// [alcanceDesconocido].
  ///
  /// ⚠️ GATE DE RELEASE — NO PUBLICAR este cambio sin las Fases 0.5 + 1 + 3
  /// aplicadas en AMBOS proyectos. Con el descuento SQL actual
  /// (`fn_descontar_ingredientes_elaborado` con el `LEAST` mixto y
  /// `fn_registrar_venta` que RETORNA el error sin `RAISE`) permitir esta venta
  /// descuenta 2500 u + 2500 kg de Frijoles y deja el almacén saqueado (§0).
  /// Primero el SQL, después este APK.
  Future<List<Map<String, dynamic>>> getProductIngredients(
    int productId, {
    int? idAlmacen,
  }) async {
    try {
      debugPrint(
        '🍽️ Obteniendo ingredientes para producto elaborado: $productId',
      );

      final response = await _supabase
          .from('app_dat_producto_ingredientes')
          .select('''
            id,
            cantidad_necesaria,
            unidad_medida,
            id_ingrediente,
            app_dat_producto!app_dat_producto_ingredientes_ingrediente_fkey(
              id,
              denominacion,
              sku,
              imagen
            )
          ''')
          .eq('id_producto_elaborado', productId);

      if (response.isEmpty) {
        debugPrint(
          '⚠️ No se encontraron ingredientes para el producto $productId',
        );
        return [];
      }

      // Ids de ingredientes (sin duplicados): una sola consulta de cadenas.
      final idsIngredientes = <int>[];
      for (final item in response) {
        final id = (item['id_ingrediente'] as num?)?.toInt();
        if (id != null && !idsIngredientes.contains(id)) {
          idsIngredientes.add(id);
        }
      }

      // Cadena de presentaciones de TODOS los ingredientes: de ahí sale
      // `factor_rel` (el equivalente base) y el nombre de la presentación base.
      final cadenas = await _cadenasDePresentaciones(idsIngredientes);

      final List<Map<String, dynamic>> ingredients = [];

      for (final item in response) {
        final producto =
            item['app_dat_producto'] as Map<String, dynamic>? ?? {};
        final idIngrediente = (item['id_ingrediente'] as num?)?.toInt();

        double? cantidadDisponible; // equivalente base
        double? cantidadFisica;
        var desglose = const <Map<String, dynamic>>[];
        var unidadDePresentacion = '';
        var disponibleResuelto = false;
        // Se etiqueta el alcance real de la medición (task-12): almacén del TPV,
        // todos los almacenes o desconocido (fallback).
        var alcanceStock = ProductDetailService.alcanceDesconocido;
        int? almacenMedido;

        if (idIngrediente != null) {
          final cadena = cadenas[idIngrediente] ?? const <PresentacionLocal>[];
          unidadDePresentacion =
              PresentacionCadenaLocal.base(cadena)?.nombre ?? '';

          if (cadena.isNotEmpty) {
            final resuelto = await _disponibleBaseIngrediente(
              idIngrediente,
              cadena,
              idAlmacen,
            );
            if (resuelto != null) {
              disponibleResuelto = true;
              cantidadDisponible = resuelto.totalBase;
              cantidadFisica = resuelto.totalFisica;
              desglose = resuelto.desglose;
              almacenMedido = idAlmacen;
              alcanceStock = idAlmacen == null
                  ? ProductDetailService.alcanceTodosLosAlmacenes
                  : ProductDetailService.alcanceAlmacenTpv;
              debugPrint(
                '📊 Ingrediente ${producto['denominacion']}: '
                'base=$cantidadDisponible (física=$cantidadFisica, '
                'almacén=${idAlmacen ?? 'todos'})',
              );
            }
          }

          if (!disponibleResuelto) {
            // FALLBACK: comportamiento anterior (una sola fila, la más
            // reciente). Se conserva para no empeorar si el ingrediente no
            // tiene cadena o si la RPC no está disponible en el proyecto.
            try {
              final inventoryResponse = await _supabase
                  .from('app_dat_inventario_productos')
                  .select('cantidad_final')
                  .eq('id_producto', idIngrediente)
                  .order('created_at', ascending: false)
                  .limit(1);

              if (inventoryResponse.isNotEmpty) {
                cantidadDisponible =
                    (inventoryResponse.first['cantidad_final'] as num?)
                        ?.toDouble();
                debugPrint(
                  '📊 Ingrediente ${producto['denominacion']} (fallback, fila '
                  'única): cantidad disponible = $cantidadDisponible',
                );
              }
            } catch (e) {
              debugPrint(
                '⚠️ Error obteniendo inventario (fallback) para ingrediente '
                '$idIngrediente: $e',
              );
            }
          }
        }

        // La unidad que ve el vendedor: la de la receta si existe; si no (caso
        // real, receta con `unidad_medida = null`), la presentación base.
        final unidadReceta = (item['unidad_medida'] as String?)?.trim() ?? '';
        final unidadMostrada =
            unidadReceta.isNotEmpty ? unidadReceta : unidadDePresentacion;

        ingredients.add({
          'producto_id': producto['id'],
          'producto_nombre':
              producto['denominacion'] ?? 'Ingrediente desconocido',
          'cantidad_necesaria': item['cantidad_necesaria'] ?? 0,
          'unidad_medida': unidadMostrada,
          'sku': producto['sku'] ?? '',
          'imagen': producto['imagen'],
          // EQUIVALENTE BASE (Σ cantidad_final × factor_rel). Es lo que debe
          // compararse contra `cantidad_necesaria`, que viene en base.
          'cantidad_disponible': cantidadDisponible,
          // Σ cantidad_final sin factor, solo informativo para la UI.
          'cantidad_disponible_fisica': cantidadFisica,
          'presentacion_base': unidadDePresentacion,
          'desglose_presentaciones': desglose,
          // Alcance real de la medición (task-12). `id_almacen` null con
          // `alcanceTodosLosAlmacenes` = no se pudo resolver el almacén del TPV.
          'id_almacen': almacenMedido,
          'alcance_stock': alcanceStock,
        });
      }

      debugPrint(
        '✅ Encontrados ${ingredients.length} ingredientes con inventario',
      );

      return ingredients;
    } catch (e) {
      debugPrint('❌ Error obteniendo ingredientes del producto $productId: $e');
      return [];
    }
  }

  /// Cadena de presentaciones de cada ingrediente, en UNA sola consulta.
  ///
  /// Devuelve solo los ingredientes con cadena utilizable; los que falten usan
  /// el fallback de [getProductIngredients].
  Future<Map<int, List<PresentacionLocal>>> _cadenasDePresentaciones(
    List<int> idsIngredientes,
  ) async {
    final out = <int, List<PresentacionLocal>>{};
    if (idsIngredientes.isEmpty) return out;

    try {
      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
            id,
            id_producto,
            cantidad,
            es_base,
            presentacion:app_nom_presentacion!inner(
              id,
              denominacion,
              sku_codigo
            )
          ''')
          .inFilter('id_producto', idsIngredientes);

      final crudasPorProducto = <int, List<Map<String, dynamic>>>{};
      for (final raw in response) {
        final fila = Map<String, dynamic>.from(raw);
        final idProducto = (fila['id_producto'] as num?)?.toInt();
        if (idProducto == null) continue;
        (crudasPorProducto[idProducto] ??= []).add(fila);
      }

      for (final entry in crudasPorProducto.entries) {
        // Misma cascada que `fn_presentaciones_producto` (base, orden y
        // factor_rel), sin duplicarla aquí.
        final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(entry.value);
        if (cadena.isNotEmpty) out[entry.key] = cadena;
      }
    } catch (e) {
      debugPrint('⚠️ Error obteniendo cadenas de presentaciones: $e');
    }
    return out;
  }

  /// Equivalente base de un ingrediente = Σ (cantidad_final × factor_rel).
  ///
  /// Las filas vigentes (una por ubicación/variante/opción/presentación, la de
  /// mayor `id`, con `cantidad_final > 0`) las devuelve
  /// `fn_stock_producto_almacen_detalle`, la misma fuente que
  /// `fn_stock_producto_almacen` usa para validar.
  ///
  /// [idAlmacen] acota al almacén del TPV (lo mismo que valida el servidor); si
  /// es `null`, la RPC suma todos los almacenes.
  ///
  /// Punto de cambio reservado: si la Fase 5 decide alcance «tienda», `p_alcance`
  /// debe propagarse aquí (hoy la RPC solo acepta `p_id_almacen`).
  ///
  /// Devuelve `null` si la RPC falla; el llamador cae al comportamiento previo.
  Future<
    ({double totalBase, double totalFisica, List<Map<String, dynamic>> desglose})?
  >
  _disponibleBaseIngrediente(
    int idIngrediente,
    List<PresentacionLocal> cadena,
    int? idAlmacen,
  ) async {
    try {
      final response = await _supabase.rpc(
        'fn_stock_producto_almacen_detalle',
        params: {'p_id_producto': idIngrediente, 'p_id_almacen': idAlmacen},
      );

      final filas = response is List
          ? response
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];

      final factorPorPresentacion = <int, double>{
        for (final p in cadena) p.idPresentacion: p.factorRel,
      };

      var totalBase = 0.0;
      var totalFisica = 0.0;
      final desglose = <Map<String, dynamic>>[];

      for (final fila in filas) {
        final cantidad = (fila['cantidad_final'] as num?)?.toDouble() ?? 0.0;
        // La RPC ya filtra `> 0`; defensivo, igual que el SQL.
        if (cantidad <= 0) continue;

        final idPresentacion = (fila['id_presentacion'] as num?)?.toInt();
        // Igual que el SQL: COALESCE(factor_rel, 1) si la presentación no
        // aparece en la cadena conocida.
        final factor = idPresentacion == null
            ? 1.0
            : (factorPorPresentacion[idPresentacion] ?? 1.0);

        totalFisica += cantidad;
        totalBase += cantidad * factor;

        desglose.add({
          'id_presentacion': idPresentacion,
          'presentacion': _nombrePresentacion(cadena, idPresentacion),
          'cantidad_final': cantidad,
          'factor_rel': factor,
          'equivalente_base': FormatoPresentacion.redondear(cantidad * factor),
        });
      }

      return (
        totalBase: FormatoPresentacion.redondear(totalBase),
        totalFisica: FormatoPresentacion.redondear(totalFisica),
        desglose: desglose,
      );
    } catch (e) {
      debugPrint(
        '⚠️ fn_stock_producto_almacen_detalle falló para ingrediente '
        '$idIngrediente: $e',
      );
      return null;
    }
  }

  /// Nombre de la presentación de la cadena por el id de la fila de inventario.
  String _nombrePresentacion(
    List<PresentacionLocal> cadena,
    int? idPresentacion,
  ) {
    if (idPresentacion == null) return '';
    for (final p in cadena) {
      if (p.idPresentacion == idPresentacion) return p.nombre;
    }
    return '';
  }

  /// Muestra un diálogo con los ingredientes del producto elaborado
  static void showIngredientsPreview(
    BuildContext context,
    List<Map<String, dynamic>> ingredients,
    String productName,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.restaurant_menu, color: Colors.orange[600], size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ingredientes - $productName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child:
                ingredients.isEmpty
                    ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No se encontraron ingredientes para este producto',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    )
                    : ListView.builder(
                      shrinkWrap: true,
                      itemCount: ingredients.length,
                      itemBuilder: (context, index) {
                        final ingredient = ingredients[index];
                        final nombre =
                            ingredient['producto_nombre'] ??
                            'Ingrediente desconocido';
                        final cantidadNecesaria =
                            ingredient['cantidad_necesaria'] ?? 0;
                        final unidadReceta =
                            (ingredient['unidad_medida'] as String?)?.trim();
                        final unidad =
                            (unidadReceta == null || unidadReceta.isEmpty)
                                ? (ingredient['presentacion_base'] as String? ??
                                      '')
                                : unidadReceta;
                        final cantidadDisponible =
                            (ingredient['cantidad_disponible'] as num?)
                                ?.toDouble();

                        // FASE 7 P0: la comparación es base vs base
                        // (`cantidad_disponible` es el equivalente base y
                        // `cantidad_necesaria` viene en unidades base).
                        final bool tieneSuficiente =
                            cantidadDisponible != null &&
                            cantidadDisponible >= cantidadNecesaria;
                        final Color statusColor =
                            cantidadDisponible == null
                                ? Colors.grey
                                : (tieneSuficiente ? Colors.green : Colors.red);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: statusColor.withOpacity(0.2),
                              child: Icon(
                                Icons.inventory_2,
                                color: statusColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              nombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Necesario: $cantidadNecesaria $unidad',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  cantidadDisponible != null
                                      ? 'Disponible: ${cantidadDisponible.toStringAsFixed(2)} $unidad'
                                      : 'Disponible: Sin datos',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            trailing:
                                cantidadDisponible != null
                                    ? Icon(
                                      tieneSuficiente
                                          ? Icons.check_circle
                                          : Icons.warning,
                                      color: statusColor,
                                      size: 20,
                                    )
                                    : null,
                          ),
                        );
                      },
                    ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  /// Obtener presentaciones de un producto específico
  Future<List<ProductPresentation>> getProductPresentations(
    int productId,
  ) async {
    try {
      debugPrint('🔍 Obteniendo presentaciones para producto ID: $productId');

      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
            id,
            id_producto,
            id_presentacion,
            cantidad,
            es_base,
            presentacion:app_nom_presentacion!inner(
              id,
              denominacion,
              descripcion,
              sku_codigo,
              es_fraccionable
            )
          ''')
          .eq('id_producto', productId)
          .order('es_base', ascending: false); // Presentación base primero

      debugPrint('📦 Respuesta presentaciones: $response');

      if (response.isEmpty) {
        debugPrint(
          '⚠️ No se encontraron presentaciones para el producto $productId',
        );
        return [];
      }

      final presentations =
          response.map((item) {
            debugPrint('🔄 Procesando presentación: $item');
            return ProductPresentation.fromJson(item);
          }).toList();

      debugPrint('✅ Se cargaron ${presentations.length} presentaciones');
      for (var presentation in presentations) {
        debugPrint(
          '📋 Presentación: ${presentation.presentacion.denominacion}, Cantidad: ${presentation.cantidad}, Es Base: ${presentation.esBase}',
        );
      }

      return presentations;
    } catch (e, stackTrace) {
      debugPrint('❌ Error obteniendo presentaciones: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return [];
    }
  }
}
