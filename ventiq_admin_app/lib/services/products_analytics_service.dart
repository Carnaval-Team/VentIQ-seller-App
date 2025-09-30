import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class ProductsAnalyticsService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene KPIs principales del dashboard de productos
  static Future<Map<String, dynamic>> getProductsKPIs() async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('📊 Obteniendo KPIs de productos para tienda: $idTienda');
      print('📊 buscando el rpc');
      final response = await _supabase.rpc(
        'get_inventario_analisis_tienda_json',
        params: {'p_id_tienda': idTienda},
      );
      print(response);
      if (response == null) {
        throw Exception('No se recibieron datos del análisis');
      }

      final metricas = response['metricas_principales'] ?? {};
      final detalles = response['detalles_adicionales'] ?? {};
      final alertas = response['alertas'] ?? [];

      return {
        'totalProductos': metricas['total_productos'] ?? 0,
        'productosActivos': metricas['total_productos'] ?? 0,
        'productosConStock': metricas['productos_con_stock'] ?? 0,
        'productosElaborados': metricas['productos_elaborados'] ?? 0,
        'valorTotalInventario':
            (metricas['valor_inventario'] ?? 0.0).toDouble(),
        'stockTotalUnidades': 0,
        'categoriasPrincipales': 0,
        'productosStockBajo': metricas['stock_bajo'] ?? 0,
        'productosSinMovimiento': metricas['sin_movimiento'] ?? 0,
        'valorPromedioPorProducto':
            (detalles['stock_promedio_por_producto'] ?? 0.0).toDouble(),

        // Nuevos datos con porcentajes
        'porcentajeConStock':
            (metricas['porcentaje_con_stock'] ?? 0.0).toDouble(),
        'porcentajeStockBajo':
            (metricas['porcentaje_stock_bajo'] ?? 0.0).toDouble(),
        'porcentajeSinMovimiento':
            (metricas['porcentaje_sin_movimiento'] ?? 0.0).toDouble(),

        // Detalles adicionales
        'productosSinStock': detalles['productos_sin_stock'] ?? 0,
        'productosNoElaborados': detalles['productos_no_elaborados'] ?? 0,
        'diasSinMovimiento': detalles['dias_sin_movimiento'] ?? 15,

        // Alertas
        'alertas': alertas,
        'fechaGeneracion': response['metadata']?['fecha_generacion'],
      };
    } catch (e) {
      print('❌ Error obteniendo KPIs de productos: $e');
      return _getDefaultKPIs();
    }
  }

  /// Obtiene distribución de productos por categoría
  static Future<List<Map<String, dynamic>>> getCategoryDistribution() async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Consulta con join para obtener categorías y contar productos activos
      final response = await _supabase
          .from('app_dat_producto')
          .select('id_categoria, app_dat_categoria(denominacion)')
          .eq('id_tienda', idTienda);

      // Agrupar por categoría
      final Map<String, int> categoryCounts = {};
      final Map<String, String> categoryNames = {};

      for (final item in response) {
        final categoriaId = item['id_categoria']?.toString() ?? 'sin_categoria';
        final categoriaNombre =
            item['app_dat_categoria']?['denominacion'] ?? 'Sin categoría';

        categoryNames[categoriaId] = categoriaNombre;
        categoryCounts[categoriaId] = (categoryCounts[categoriaId] ?? 0) + 1;
      }

      final total = response.length;

      // Obtener valor de inventario por categoría
      final inventarioResponse = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id_producto,
            cantidad_final,
            cantidad_inicial,
            app_dat_producto!inner(id_tienda, id_categoria)
          ''')
          .eq('app_dat_producto.id_tienda', idTienda);

      // Obtener precios vigentes
      final today = DateTime.now().toIso8601String().split('T')[0];
      final preciosResponse = await _supabase
          .from('app_dat_precio_venta')
          .select('''
            precio_venta_cup, 
            id_producto,
            app_dat_producto!inner(id_tienda)
          ''')
          .eq('app_dat_producto.id_tienda', idTienda)
          .or('fecha_hasta.is.null,fecha_hasta.gte.$today')
          .lte('fecha_desde', today);

      // Calcular valor por categoría
      final Map<String, double> valorPorCategoria = {};
      final Map<String, double> preciosPorProducto = {};

      // Mapear precios
      for (final precio in preciosResponse) {
        final idProducto = precio['id_producto'].toString();
        preciosPorProducto[idProducto] =
            (precio['precio_venta_cup'] ?? 0.0).toDouble();
      }

      // Calcular stock y valor por categoría
      for (final item in inventarioResponse) {
        final idProducto = item['id_producto'].toString();
        final categoriaId =
            item['app_dat_producto']['id_categoria']?.toString() ??
            'sin_categoria';
        final cantidadFinal = item['cantidad_final'] ?? 0;
        final cantidadInicial = item['cantidad_inicial'] ?? 0;
        final cantidad =
            cantidadFinal != null && cantidadFinal > 0
                ? cantidadFinal
                : cantidadInicial;
        final precio = preciosPorProducto[idProducto] ?? 0.0;

        valorPorCategoria[categoriaId] =
            (valorPorCategoria[categoriaId] ?? 0) +
            (cantidad.toDouble() * precio);
      }

      return categoryCounts.entries.map((entry) {
        final cantidad = entry.value;
        final porcentaje = total > 0 ? (cantidad / total * 100) : 0.0;
        final valorInventario = valorPorCategoria[entry.key] ?? 0.0;

        return {
          'categoria': categoryNames[entry.key] ?? 'Sin categoría',
          'cantidad': cantidad,
          'porcentaje': porcentaje,
          'valorInventario': valorInventario,
        };
      }).toList();
    } catch (e) {
      print('❌ Error obteniendo distribución por categorías: $e');
      return _getDefaultCategoryDistribution();
    }
  }

  /// Obtiene productos con mejor rendimiento (más vendidos/rotación)
  static Future<List<Map<String, dynamic>>> getTopPerformingProducts({
    int limit = 10,
    String period = '30', // días
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Obtener productos con su información básica
      final productosResponse = await _supabase
          .from('app_dat_producto')
          .select('''
            id, denominacion, sku, 
            app_dat_categoria(denominacion)
          ''')
          .eq('id_tienda', idTienda);

      // Obtener stock total por producto
      final inventarioResponse = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id_producto,
            cantidad_final,
            cantidad_inicial,
            app_dat_producto!inner(id_tienda)
          ''')
          .eq('app_dat_producto.id_tienda', idTienda);

      // Agrupar stock por producto
      final Map<String, double> stockPorProducto = {};
      for (final item in inventarioResponse) {
        final idProducto = item['id_producto'].toString();
        final cantidadFinal = item['cantidad_final'] ?? 0;
        final cantidadInicial = item['cantidad_inicial'] ?? 0;
        final cantidad =
            cantidadFinal != null && cantidadFinal > 0
                ? cantidadFinal
                : cantidadInicial;

        stockPorProducto[idProducto] =
            (stockPorProducto[idProducto] ?? 0) + cantidad.toDouble();
      }

      // Crear lista de productos con su rendimiento
      final productosConStock =
          productosResponse.map((item) {
            final idProducto = item['id'].toString();
            final stockTotal = stockPorProducto[idProducto] ?? 0.0;

            return {
              'id': item['id'],
              'denominacion': item['denominacion'] ?? 'Producto',
              'sku': item['sku'] ?? '',
              'categoria': item['app_dat_categoria']?['denominacion'] ?? '',
              'stockActual': stockTotal.round(),
              'movimientos':
                  stockTotal.toInt(), // Usar stock como proxy de movimientos
              'rotacion': stockTotal > 0 ? 1.0 : 0.0,
              'valorMovido': stockTotal * 10.0, // Estimación
              'ultimoMovimiento': DateTime.now().toIso8601String(),
            };
          }).toList();

      // Ordenar por stock (proxy de rendimiento) y tomar los top
      productosConStock.sort(
        (a, b) => (b['stockActual'] as int).compareTo(a['stockActual'] as int),
      );

      return productosConStock.take(limit).toList();
    } catch (e) {
      print('❌ Error obteniendo productos top: $e');
      return _getDefaultTopProducts();
    }
  }

  /// Obtiene productos con bajo rendimiento o alertas
  static Future<List<Map<String, dynamic>>> getProductsAlerts() async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Buscar productos con stock bajo o sin stock
      final response = await _supabase
          .from('app_dat_producto')
          .select('''
            id, denominacion, sku,
            app_dat_inventario_productos(cantidad_final)
          ''')
          .eq('id_tienda', idTienda);

      final alerts = <Map<String, dynamic>>[];

      for (final item in response) {
        final inventario = item['app_dat_inventario_productos'] as List?;
        final stockActual =
            inventario?.fold<int>(0, (sum, inv) {
              final cantidad = inv['cantidad_final'];
              final cantidadInt =
                  cantidad is int ? cantidad : (cantidad as double).round();
              return sum + cantidadInt;
            }) ??
            0;
        final stockMinimo = 10; // Valor por defecto ya que la columna no existe

        if (stockActual == 0) {
          alerts.add({
            'id': item['id'],
            'denominacion': item['denominacion'] ?? 'Producto',
            'sku': item['sku'] ?? '',
            'tipoAlerta': 'sin_stock',
            'descripcionAlerta': 'Producto sin stock disponible',
            'stockActual': stockActual,
            'stockMinimo': stockMinimo,
            'diasSinMovimiento': 0,
            'prioridad': 'alta',
          });
        } else if (stockActual <= stockMinimo) {
          alerts.add({
            'id': item['id'],
            'denominacion': item['denominacion'] ?? 'Producto',
            'sku': item['sku'] ?? '',
            'tipoAlerta': 'stock_bajo',
            'descripcionAlerta': 'Stock por debajo del mínimo requerido',
            'stockActual': stockActual,
            'stockMinimo': stockMinimo,
            'diasSinMovimiento': 0,
            'prioridad': 'media',
          });
        }
      }

      return alerts.isEmpty ? _getDefaultAlerts() : alerts;
    } catch (e) {
      print('❌ Error obteniendo alertas de productos: $e');
      return _getDefaultAlerts();
    }
  }

  /// Obtiene análisis ABC de productos
  static Future<Map<String, dynamic>> getABCAnalysis() async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      final response = await _supabase
          .from('app_dat_producto')
          .select('id')
          .eq('id_tienda', idTienda);

      final totalProductos = response.length;

      // Distribución ABC estándar: A=20%, B=30%, C=50%
      final productosA = (totalProductos * 0.2).round();
      final productosB = (totalProductos * 0.3).round();
      final productosC = totalProductos - productosA - productosB;

      return {
        'clasificacionA': {
          'cantidad': productosA,
          'porcentaje': 20.0,
          'valorInventario': 0.0, // TODO: Calcular valor real
        },
        'clasificacionB': {
          'cantidad': productosB,
          'porcentaje': 30.0,
          'valorInventario': 0.0,
        },
        'clasificacionC': {
          'cantidad': productosC,
          'porcentaje': 50.0,
          'valorInventario': 0.0,
        },
        'totalAnalizado': totalProductos,
        'fechaAnalisis': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error obteniendo análisis ABC: $e');
      return _getDefaultABCAnalysis();
    }
  }

  /// Obtiene tendencias de stock en el tiempo
  static Future<List<Map<String, dynamic>>> getStockTrends({
    int days = 30,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Obtener stock actual total como base para simulación
      final inventarioResponse = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            cantidad_final,
            cantidad_inicial,
            app_dat_producto!inner(id_tienda)
          ''')
          .eq('app_dat_producto.id_tienda', idTienda);

      final stockActualTotal = inventarioResponse.fold<int>(0, (sum, item) {
        final cantidadFinal = item['cantidad_final'] ?? 0;
        final cantidadInicial = item['cantidad_inicial'] ?? 0;
        final cantidad =
            cantidadFinal != null && cantidadFinal > 0
                ? cantidadFinal
                : cantidadInicial;
        final cantidadInt =
            cantidad is int ? cantidad : (cantidad as double).round();
        return sum + cantidadInt;
      });

      // Generar datos simulados para los últimos 7 días basados en stock real
      final now = DateTime.now();
      final trends = <Map<String, dynamic>>[];

      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));

        // Simular variación diaria basada en stock real
        final variation =
            (i * 0.05 - 0.15) * stockActualTotal; // Variación del ±15%
        final stockDelDia = (stockActualTotal + variation).round();
        final stockFinal = stockDelDia > 0 ? stockDelDia : 0;

        trends.add({
          'fecha': date.toIso8601String().split('T')[0],
          'stockTotal': stockFinal,
          'valorTotal': stockFinal * 15.0, // Precio promedio estimado
          'movimientos': (stockFinal * 0.1).round(),
          'entradas': (stockFinal * 0.05).round(),
          'salidas': (stockFinal * 0.05).round(),
        });
      }

      return trends;
    } catch (e) {
      print('❌ Error obteniendo tendencias de stock: $e');
      return _getDefaultStockTrends();
    }
  }

  /// Obtiene recomendaciones para gestión de productos
  static Future<List<Map<String, dynamic>>> getRecommendations() async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      final recommendations = <Map<String, dynamic>>[];

      // Obtener productos y su stock agrupado
      final productosResponse = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion, es_activo')
          .eq('id_tienda', idTienda);

      final inventarioResponse = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id_producto,
            cantidad_final,
            cantidad_inicial,
            app_dat_producto!inner(id_tienda)
          ''')
          .eq('app_dat_producto.id_tienda', idTienda);

      // Agrupar stock por producto
      final Map<String, double> stockPorProducto = {};
      for (final item in inventarioResponse) {
        final idProducto = item['id_producto'].toString();
        final cantidadFinal = item['cantidad_final'] ?? 0;
        final cantidadInicial = item['cantidad_inicial'] ?? 0;
        final cantidad =
            cantidadFinal != null && cantidadFinal > 0
                ? cantidadFinal
                : cantidadInicial;

        stockPorProducto[idProducto] =
            (stockPorProducto[idProducto] ?? 0) + cantidad.toDouble();
      }

      // Contar productos sin stock
      final productosSinStock =
          productosResponse.where((producto) {
            final idProducto = producto['id'].toString();
            final stock = stockPorProducto[idProducto] ?? 0.0;
            return producto['es_activo'] == true && stock == 0;
          }).length;

      if (productosSinStock > 0) {
        recommendations.add({
          'tipo': 'reposicion',
          'titulo': 'Productos sin stock',
          'descripcion':
              'Hay productos activos que requieren reposición inmediata',
          'prioridad': 'alta',
          'accion': 'revisar_stock',
          'productosAfectados': productosSinStock,
          'impactoEstimado': 'alto',
        });
      }

      // Contar productos inactivos
      final productosInactivos =
          productosResponse.where((p) => p['es_activo'] == false).length;

      if (productosInactivos > 0) {
        recommendations.add({
          'tipo': 'optimizacion',
          'titulo': 'Productos inactivos',
          'descripcion':
              'Revisar productos marcados como inactivos para posible reactivación',
          'prioridad': 'media',
          'accion': 'revisar_productos',
          'productosAfectados': productosInactivos,
          'impactoEstimado': 'medio',
        });
      }

      // Contar productos con stock bajo
      final productosStockBajo =
          productosResponse.where((producto) {
            final idProducto = producto['id'].toString();
            final stock = stockPorProducto[idProducto] ?? 0.0;
            return producto['es_activo'] == true && stock > 0 && stock <= 5;
          }).length;

      if (productosStockBajo > 0) {
        recommendations.add({
          'tipo': 'alerta',
          'titulo': 'Stock bajo detectado',
          'descripcion':
              'Varios productos tienen stock por debajo del nivel recomendado',
          'prioridad': 'media',
          'accion': 'planificar_reposicion',
          'productosAfectados': productosStockBajo,
          'impactoEstimado': 'medio',
        });
      }

      return recommendations.isEmpty
          ? _getDefaultRecommendations()
          : recommendations;
    } catch (e) {
      print('❌ Error obteniendo recomendaciones: $e');
      return _getDefaultRecommendations();
    }
  }

  // Agregar este método en la clase ProductsBCGChart
  static Future<Map<String, dynamic>> getProductDetails(int productId) async {
    try {
      final supabase = Supabase.instance.client;
      print('🔍 Obteniendo detalles para producto ID: $productId');

      if (productId == 0) {
        print('⚠️ ID de producto inválido (0)');
        return {
          'precio_venta': 0.0,
          'costo_promedio': 0.0,
          'ventas_totales': 0.0,
          'porcentaje_utilidad': 0.0,
          'cantidad_vendida': 0,
        };
      }

      // 1. Obtener precio de venta actual
      final precioResponse =
          await supabase
              .from('app_dat_precio_venta')
              .select('precio_venta_cup')
              .eq('id_producto', productId)
              .or(
                'fecha_hasta.is.null,fecha_hasta.gte.${DateTime.now().toIso8601String().split('T')[0]}',
              )
              .lte(
                'fecha_desde',
                DateTime.now().toIso8601String().split('T')[0],
              )
              .order('fecha_desde', ascending: false)
              .limit(1)
              .maybeSingle();

      final precioVenta = (precioResponse?['precio_venta_cup'] ?? 0.0) as num;
      print('💰 Precio de venta encontrado: \$${precioVenta.toDouble()}');

      // 2. Obtener costo unitario promedio de las RECEPCIONES
      final recepcionesResponse = await supabase
          .from('app_dat_recepcion_productos')
          .select('''
          costo_real,
          app_dat_operaciones!inner(
            id,
            id_tipo_operacion,
            created_at
          )
        ''')
          .eq('id_producto', productId)
          .eq('app_dat_operaciones.id_tipo_operacion', 1) // 1 = Recepción
          .not('costo_real', 'is', null)
          .order('created_at', ascending: false)
          .limit(10);

      print('📦 Recepciones encontradas: ${recepcionesResponse.length}');

      double costoPromedio = 0.0;
      if (recepcionesResponse.isNotEmpty) {
        final costos =
            recepcionesResponse
                .map((e) => (e['costo_real'] ?? 0.0) as num)
                .map((e) => e.toDouble())
                .where((e) => e > 0)
                .toList();

        if (costos.isNotEmpty) {
          costoPromedio = costos.reduce((a, b) => a + b) / costos.length;
          print('💵 Costo promedio: \$${costoPromedio.toStringAsFixed(2)}');
        }
      }

      // 3. Obtener ventas totales de las EXTRACCIONES (últimos 30 días)
      final fechaLimite = DateTime.now().subtract(const Duration(days: 30));

      final extraccionesResponse = await supabase
          .from('app_dat_extraccion_productos')
          .select('''
          cantidad,
          app_dat_operaciones!inner(
            id,
            id_tipo_operacion,
            created_at
          )
        ''')
          .eq('id_producto', productId)
          .eq('app_dat_operaciones.id_tipo_operacion', 3) // 3 = Extracción
          .gte('app_dat_operaciones.created_at', fechaLimite.toIso8601String());

      print('📤 Extracciones encontradas: ${extraccionesResponse.length}');

      double ventasTotales = 0.0;
      int cantidadVendida = 0;

      if (extraccionesResponse.isNotEmpty) {
        for (final extraccion in extraccionesResponse) {
          final cantidad = ((extraccion['cantidad'] ?? 0.0) as num).toDouble();
          cantidadVendida += cantidad.toInt();
          ventasTotales += cantidad * precioVenta.toDouble();
        }
        print('📊 Cantidad vendida: $cantidadVendida unidades');
        print('💸 Ventas totales: \$${ventasTotales.toStringAsFixed(2)}');
      }

      // 4. Calcular porcentaje de utilidad
      double porcentajeUtilidad = 0.0;
      if (costoPromedio > 0 && precioVenta > 0) {
        porcentajeUtilidad =
            ((precioVenta.toDouble() - costoPromedio) / costoPromedio) * 100;
        print('📈 Utilidad: ${porcentajeUtilidad.toStringAsFixed(1)}%');
      }

      final resultado = {
        'precio_venta': precioVenta.toDouble(),
        'costo_promedio': costoPromedio,
        'ventas_totales': ventasTotales,
        'porcentaje_utilidad': porcentajeUtilidad,
        'cantidad_vendida': cantidadVendida,
      };

      print('✅ Detalles: $resultado');
      return resultado;
    } catch (e, stackTrace) {
      print('❌ Error: $e');
      print('Stack: $stackTrace');
      return {
        'precio_venta': 0.0,
        'costo_promedio': 0.0,
        'ventas_totales': 0.0,
        'porcentaje_utilidad': 0.0,
        'cantidad_vendida': 0,
      };
    }
  }
  // MÉTODOS PRIVADOS PARA DATOS POR DEFECTO

  static Map<String, dynamic> _getDefaultKPIs() {
    return {
      'totalProductos': 0,
      'productosActivos': 0,
      'productosConStock': 0,
      'productosElaborados': 0,
      'valorTotalInventario': 0.0,
      'stockTotalUnidades': 0,
      'categoriasPrincipales': 0,
      'productosStockBajo': 0,
      'productosSinMovimiento': 0,
      'valorPromedioPorProducto': 0.0,
    };
  }

  static List<Map<String, dynamic>> _getDefaultCategoryDistribution() {
    return [
      {
        'categoria': 'Sin datos',
        'cantidad': 0,
        'porcentaje': 0.0,
        'valorInventario': 0.0,
      },
    ];
  }

  static List<Map<String, dynamic>> _getDefaultTopProducts() {
    return [
      {
        'id': '0',
        'denominacion': 'Sin datos disponibles',
        'sku': '',
        'categoria': '',
        'stockActual': 0,
        'movimientos': 0,
        'rotacion': 0.0,
        'valorMovido': 0.0,
        'ultimoMovimiento': null,
      },
    ];
  }

  static List<Map<String, dynamic>> _getDefaultAlerts() {
    return [
      {
        'id': '0',
        'denominacion': 'Sin alertas',
        'sku': '',
        'tipoAlerta': 'info',
        'descripcionAlerta': 'No hay alertas pendientes',
        'stockActual': 0,
        'stockMinimo': 0,
        'diasSinMovimiento': 0,
        'prioridad': 'baja',
      },
    ];
  }

  static Map<String, dynamic> _getDefaultABCAnalysis() {
    return {
      'clasificacionA': {
        'cantidad': 0,
        'porcentaje': 0.0,
        'valorInventario': 0.0,
      },
      'clasificacionB': {
        'cantidad': 0,
        'porcentaje': 0.0,
        'valorInventario': 0.0,
      },
      'clasificacionC': {
        'cantidad': 0,
        'porcentaje': 0.0,
        'valorInventario': 0.0,
      },
      'totalAnalizado': 0,
      'fechaAnalisis': DateTime.now().toIso8601String(),
    };
  }

  static List<Map<String, dynamic>> _getDefaultStockTrends() {
    final now = DateTime.now();
    return List.generate(7, (index) {
      final date = now.subtract(Duration(days: 6 - index));
      return {
        'fecha': date.toIso8601String().split('T')[0],
        'stockTotal': 0,
        'valorTotal': 0.0,
        'movimientos': 0,
        'entradas': 0,
        'salidas': 0,
      };
    });
  }

  static List<Map<String, dynamic>> _getDefaultRecommendations() {
    return [
      {
        'tipo': 'info',
        'titulo': 'Sistema en funcionamiento',
        'descripcion': 'No hay recomendaciones específicas en este momento',
        'prioridad': 'baja',
        'accion': 'revisar_periodicamente',
        'productosAfectados': 0,
        'impactoEstimado': 'ninguno',
      },
    ];
  }

  /// Obtiene análisis BCG de productos
  static Future<Map<String, dynamic>> getBCGAnalysis() async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        print('⚠️ No se encontró ID de tienda para análisis BCG');
        return _getDefaultBCGAnalysis();
      }

      print('📊 Obteniendo análisis BCG para tienda: $idTienda');

      final response = await _supabase
          .rpc('get_bcg_productos_sin_log', params: {'p_id_tienda': idTienda})
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              print('⏱️ Timeout obteniendo análisis BCG');
              return _getDefaultBCGAnalysis();
            },
          );

      // Validar que la respuesta tenga la estructura esperada
      if (response == null) {
        print('⚠️ Respuesta nula del análisis BCG');
        return _getDefaultBCGAnalysis();
      }

      final data = response as Map<String, dynamic>;

      // Validar campos requeridos
      if (!data.containsKey('productos') ||
          !data.containsKey('resumen') ||
          !data.containsKey('umbrales')) {
        print('⚠️ Respuesta BCG con estructura incompleta');
        return _getDefaultBCGAnalysis();
      }

      print('✅ Análisis BCG obtenido correctamente');
      return data;
    } catch (e) {
      print('❌ Error obteniendo análisis BCG: $e');
      // No lanzar excepción, retornar datos por defecto
      return _getDefaultBCGAnalysis();
    }
  }

  static Map<String, dynamic> _getDefaultBCGAnalysis() {
    return {
      'metadata': {
        'fecha_generacion': DateTime.now().toIso8601String(),
        'id_tienda': 0,
      },
      'umbrales': {'umbral_cuota': 0.0, 'umbral_crecimiento': 0.0},
      'productos': [],
      'resumen': {
        'total_productos': 0,
        'estrellas': 0,
        'vacas_lecheras': 0,
        'interrogantes': 0,
        'perros': 0,
        'ventas_totales': 0.0,
      },
    };
  }
}
