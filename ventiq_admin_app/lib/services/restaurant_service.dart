import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../models/restaurant_models.dart';
import 'user_preferences_service.dart';
import 'store_selector_service.dart';

/// Servicio para gestión completa del módulo de restaurante
/// Incluye: unidades de medida, disponibilidad, costos y descuentos automáticos
class RestaurantService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static StoreSelectorService? _storeSelectorService;

  // ============================================================================
  // GESTIÓN DE UNIDADES DE MEDIDA
  // ============================================================================

  /// Obtiene todas las unidades de medida disponibles
  static Future<List<UnidadMedida>> getUnidadesMedida() async {
    try {
      final response = await _supabase
          .from('app_nom_unidades_medida')
          .select('*')
          .order('tipo_unidad, denominacion');

      final unidades = (response as List)
          .map((json) => UnidadMedida.fromJson(json))
          .toList();
          
      print('🔍 DEBUG: Unidades cargadas desde BD: ${unidades.length}');
      for (final unidad in unidades) {
        print('📋 DEBUG: ID=${unidad.id}, denominacion="${unidad.denominacion}", abreviatura="${unidad.abreviatura}", tipo=${unidad.tipoUnidad}');
      }
      
      // Si no hay unidades, inicializar con unidades básicas
      if (unidades.isEmpty) {
        print('⚠️ No hay unidades en BD, inicializando unidades básicas...');
        await _initializeBasicUnits();
        // Volver a cargar después de inicializar
        return await getUnidadesMedida();
      }

      return unidades;
    } catch (e) {
      print('❌ Error obteniendo unidades de medida: $e');
      throw Exception('Error al obtener unidades de medida: $e');
    }
  }

  /// Inicializa unidades básicas si la tabla está vacía
  static Future<void> _initializeBasicUnits() async {
    try {
      final basicUnits = [
        {
          'denominacion': 'Gramos',
          'abreviatura': 'g',
          'tipo_unidad': 1, // Peso
          'es_base': true,
          'factor_base': 1.0,
          'descripcion': 'Unidad básica de peso'
        },
        {
          'denominacion': 'Kilogramos',
          'abreviatura': 'kg',
          'tipo_unidad': 1, // Peso
          'es_base': false,
          'factor_base': 1000.0,
          'descripcion': 'Múltiplo de gramos'
        },
        {
          'denominacion': 'Mililitros',
          'abreviatura': 'ml',
          'tipo_unidad': 2, // Volumen
          'es_base': true,
          'factor_base': 1.0,
          'descripcion': 'Unidad básica de volumen'
        },
        {
          'denominacion': 'Litros',
          'abreviatura': 'l',
          'tipo_unidad': 2, // Volumen
          'es_base': false,
          'factor_base': 1000.0,
          'descripcion': 'Múltiplo de mililitros'
        },
        {
          'denominacion': 'Unidades',
          'abreviatura': 'u',
          'tipo_unidad': 4, // Unidad
          'es_base': true,
          'factor_base': 1.0,
          'descripcion': 'Unidad de conteo'
        },
      ];

      for (final unit in basicUnits) {
        await _supabase.from('app_nom_unidades_medida').insert(unit);
        print('✅ Unidad creada: ${unit['denominacion']}');
      }
      
      print('✅ Unidades básicas inicializadas correctamente');
    } catch (e) {
      print('❌ Error inicializando unidades básicas: $e');
      throw Exception('Error al inicializar unidades básicas: $e');
    }
  }

  /// Obtiene conversiones de unidades disponibles
  static Future<List<ConversionUnidad>> getConversiones() async {
    try {
      final response = await _supabase
          .from('app_nom_conversiones_unidades')
          .select('''
            *,
            unidad_origen:app_nom_unidades_medida!id_unidad_origen(denominacion, abreviatura),
            unidad_destino:app_nom_unidades_medida!id_unidad_destino(denominacion, abreviatura)
          ''')
          .order('id_unidad_origen');

      final conversiones = (response as List)
          .map((json) => ConversionUnidad.fromJson(json))
          .toList();
          
      print('🔍 DEBUG: Conversiones cargadas desde BD: ${conversiones.length}');
      for (final conversion in conversiones) {
        print('📋 DEBUG: ID=${conversion.id}, ${conversion.unidadOrigen?.denominacion ?? 'N/A'} → ${conversion.unidadDestino?.denominacion ?? 'N/A'}, factor=${conversion.factorConversion}');
      }
      
      // Si no hay conversiones, inicializar conversiones básicas
      if (conversiones.isEmpty) {
        print('⚠️ No hay conversiones en BD, inicializando conversiones básicas...');
        await _initializeBasicConversions();
        // Volver a cargar después de inicializar
        return await getConversiones();
      }

      return conversiones;
    } catch (e) {
      print('❌ Error obteniendo conversiones: $e');
      throw Exception('Error al obtener conversiones: $e');
    }
  }

  /// Inicializa conversiones básicas si la tabla está vacía
  static Future<void> _initializeBasicConversions() async {
    try {
      // Primero verificar que existan las unidades básicas
      final unidades = await getUnidadesMedida();
      if (unidades.length < 5) {
        print('⚠️ No hay suficientes unidades básicas, no se pueden crear conversiones');
        return;
      }
      
      // Buscar IDs de unidades básicas
      final gramos = unidades.firstWhere((u) => u.abreviatura.toLowerCase() == 'g', orElse: () => throw Exception('Unidad gramos no encontrada'));
      final kilogramos = unidades.firstWhere((u) => u.abreviatura.toLowerCase() == 'kg', orElse: () => throw Exception('Unidad kilogramos no encontrada'));
      final mililitros = unidades.firstWhere((u) => u.abreviatura.toLowerCase() == 'ml', orElse: () => throw Exception('Unidad mililitros no encontrada'));
      final litros = unidades.firstWhere((u) => u.abreviatura.toLowerCase() == 'l', orElse: () => throw Exception('Unidad litros no encontrada'));

      final basicConversions = [
        {
          'id_unidad_origen': gramos.id,
          'id_unidad_destino': kilogramos.id,
          'factor_conversion': 0.001, // 1g = 0.001kg
          'es_aproximada': false,
          'observaciones': 'Conversión exacta gramos a kilogramos'
        },
        {
          'id_unidad_origen': kilogramos.id,
          'id_unidad_destino': gramos.id,
          'factor_conversion': 1000.0, // 1kg = 1000g
          'es_aproximada': false,
          'observaciones': 'Conversión exacta kilogramos a gramos'
        },
        {
          'id_unidad_origen': mililitros.id,
          'id_unidad_destino': litros.id,
          'factor_conversion': 0.001, // 1ml = 0.001L
          'es_aproximada': false,
          'observaciones': 'Conversión exacta mililitros a litros'
        },
        {
          'id_unidad_origen': litros.id,
          'id_unidad_destino': mililitros.id,
          'factor_conversion': 1000.0, // 1L = 1000ml
          'es_aproximada': false,
          'observaciones': 'Conversión exacta litros a mililitros'
        },
      ];

      for (final conversion in basicConversions) {
        await _supabase.from('app_nom_conversiones_unidades').insert(conversion);
        print('✅ Conversión creada: ${conversion['observaciones']}');
      }
      
      print('✅ Conversiones básicas inicializadas correctamente');
    } catch (e) {
      print('❌ Error inicializando conversiones básicas: $e');
      throw Exception('Error al inicializar conversiones básicas: $e');
    }
  }

  /// Convierte cantidad entre unidades usando los datos de la base de datos
  static Future<double> convertirUnidades({
    required double cantidad,
    required int unidadOrigen,
    required int unidadDestino,
    required int idProducto,
  }) async {
    try {
      print('🔄 Convirtiendo unidades: $cantidad de $unidadOrigen a $unidadDestino para producto $idProducto');

      // Si las unidades son iguales, no hay conversión
      if (unidadOrigen == unidadDestino) {
        print('✅ Unidades iguales, no se requiere conversión');
        return cantidad;
      }

      // Intentar usar la función RPC primero
      try {
        final resultado = await _supabase.rpc(
          'fn_convertir_unidades',
          params: {
            'p_cantidad': cantidad,
            'p_id_unidad_origen': unidadOrigen,
            'p_id_unidad_destino': unidadDestino,
            'p_id_producto': idProducto,
          },
        );

        if (resultado != null) {
          final cantidadConvertida = (resultado as num).toDouble();
          print('✅ Conversión RPC exitosa: $cantidad → $cantidadConvertida');
          return cantidadConvertida;
        }
      } catch (rpcError) {
        print('⚠️ Error en RPC fn_convertir_unidades: $rpcError');
        print('🔄 Intentando conversión manual...');
      }

      // Fallback: buscar conversión directa en tabla
      final conversion = await _supabase
          .from('app_nom_conversiones_unidades')
          .select('factor_conversion')
          .eq('id_unidad_origen', unidadOrigen)
          .eq('id_unidad_destino', unidadDestino)
          .limit(1);

      if (conversion.isNotEmpty) {
        final factor = (conversion[0]['factor_conversion'] as num).toDouble();
        final resultado = cantidad * factor;
        print('✅ Conversión directa: $cantidad × $factor = $resultado');
        return resultado;
      }

      // Fallback: conversión inversa
      final invConversion = await _supabase
          .from('app_nom_conversiones_unidades')
          .select('factor_conversion')
          .eq('id_unidad_origen', unidadDestino)
          .eq('id_unidad_destino', unidadOrigen)
          .limit(1);

      if (invConversion.isNotEmpty) {
        final factor = (invConversion[0]['factor_conversion'] as num).toDouble();
        final resultado = cantidad / factor;
        print('✅ Conversión inversa: $cantidad ÷ $factor = $resultado');
        return resultado;
      }

      // Fallback: conversión vía unidad base
      final resultado = await _convertirViaUnidadBase(cantidad, unidadOrigen, unidadDestino);
      if (resultado != null) {
        print('✅ Conversión vía unidad base: $resultado');
        return resultado;
      }

      // Si no se encuentra conversión, usar fallback básico
      print('⚠️ No se encontró conversión en BD, usando fallback básico');
      return _convertirUnidadesBasico(cantidad, unidadOrigen, unidadDestino);

    } catch (e) {
      print('❌ Error en conversión de unidades: $e');
      print('🔄 Usando conversión básica como fallback');
      return _convertirUnidadesBasico(cantidad, unidadOrigen, unidadDestino);
    }
  }

  /// Convierte unidades a través de la unidad base cuando no hay conversión directa
  static Future<double?> _convertirViaUnidadBase(double cantidad, int unidadOrigen, int unidadDestino) async {
    try {
      // Obtener información de ambas unidades
      final unidades = await _supabase
          .from('app_nom_unidades_medida')
          .select('id, denominacion, tipo_unidad, es_base, factor_base')
          .inFilter('id', [unidadOrigen, unidadDestino]);

      if (unidades.length != 2) {
        print('⚠️ No se encontraron ambas unidades en la BD');
        return null;
      }

      final unidadOrigenData = unidades.firstWhere((u) => u['id'] == unidadOrigen);
      final unidadDestinoData = unidades.firstWhere((u) => u['id'] == unidadDestino);

      // Verificar que sean del mismo tipo
      if (unidadOrigenData['tipo_unidad'] != unidadDestinoData['tipo_unidad']) {
        print('⚠️ Las unidades son de diferentes tipos, no se puede convertir');
        return null;
      }

      // Convertir a unidad base y luego a unidad destino
      double cantidadEnBase = cantidad;
      
      // Si la unidad origen no es base, convertir a base
      if (unidadOrigenData['es_base'] != true && unidadOrigenData['factor_base'] != null) {
        final factorBase = (unidadOrigenData['factor_base'] as num).toDouble();
        cantidadEnBase = cantidad / factorBase;
        print('🔄 Conversión a base: $cantidad ÷ $factorBase = $cantidadEnBase');
      }

      // Si la unidad destino no es base, convertir desde base
      if (unidadDestinoData['es_base'] != true && unidadDestinoData['factor_base'] != null) {
        final factorBase = (unidadDestinoData['factor_base'] as num).toDouble();
        final resultado = cantidadEnBase * factorBase;
        print('🔄 Conversión desde base: $cantidadEnBase × $factorBase = $resultado');
        return resultado;
      }

      return cantidadEnBase;
    } catch (e) {
      print('❌ Error en conversión vía unidad base: $e');
      return null;
    }
  }

  /// Conversión básica como último recurso
  static double _convertirUnidadesBasico(double cantidad, int unidadOrigen, int unidadDestino) {
    print('🔄 Usando conversión básica hardcodeada');
    
    // Conversiones básicas comunes (basadas en IDs típicos)
    // Gramos (1) a Kilogramos (2)
    if (unidadOrigen == 1 && unidadDestino == 2) {
      return cantidad / 1000; // 1000g = 1kg
    }
    
    // Kilogramos (2) a Gramos (1)
    if (unidadOrigen == 2 && unidadDestino == 1) {
      return cantidad * 1000; // 1kg = 1000g
    }
    
    // Mililitros (3) a Litros (4)
    if (unidadOrigen == 3 && unidadDestino == 4) {
      return cantidad / 1000; // 1000ml = 1L
    }
    
    // Litros (4) a Mililitros (3)
    if (unidadOrigen == 4 && unidadDestino == 3) {
      return cantidad * 1000; // 1L = 1000ml
    }
    
    print('⚠️ Conversión no disponible de unidad $unidadOrigen a $unidadDestino - retornando cantidad original');
    return cantidad; // Sin conversión disponible
  }

  /// Configura unidades específicas para un producto
  static Future<void> configurarUnidadesProducto({
    required int idProducto,
    required List<ProductoUnidad> unidades,
  }) async {
    try {
      // Eliminar configuraciones existentes
      await _supabase
          .from('app_dat_producto_unidades')
          .delete()
          .eq('id_producto', idProducto);

      // Insertar nuevas configuraciones
      for (final unidad in unidades) {
        await _supabase.from('app_dat_producto_unidades').insert({
          'id_producto': idProducto,
          'id_unidad_medida': unidad.idUnidadMedida,
          'factor_producto': unidad.factorProducto,
          'es_unidad_compra': unidad.esUnidadCompra,
          'es_unidad_venta': unidad.esUnidadVenta,
          'es_unidad_inventario': unidad.esUnidadInventario,
          'observaciones': unidad.observaciones,
        });
      }
    } catch (e) {
      print('❌ Error configurando unidades del producto: $e');
      throw Exception('Error al configurar unidades del producto: $e');
    }
  }

  // ============================================================================
  // GESTIÓN DE PLATOS ELABORADOS
  // ============================================================================

  /// Obtiene platos elaborados con sus recetas
  static Future<List<PlatoElaborado>> getPlatosElaborados({
    int? idCategoria,
    bool soloActivos = true,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      var query = _supabase
          .from('app_rest_platos_elaborados')
          .select('''
            *,
            categoria:app_rest_categorias_platos(nombre, descripcion),
            recetas:app_rest_recetas(
              *,
              producto:app_dat_producto(denominacion, sku, um)
            )
          ''');

      if (soloActivos) {
        query = query.eq('es_activo', true);
      }

      if (idCategoria != null) {
        query = query.eq('id_categoria', idCategoria);
      }

      final response = await query.order('nombre');

      return (response as List)
          .map((json) => PlatoElaborado.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo platos elaborados: $e');
      throw Exception('Error al obtener platos elaborados: $e');
    }
  }

  /// Verifica disponibilidad de un plato usando la función SQL
  static Future<DisponibilidadPlato> verificarDisponibilidadPlato({
    required int idPlato,
    int cantidad = 1,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      final response = await _supabase.rpc(
        'fn_verificar_disponibilidad_plato',
        params: {
          'p_id_plato': idPlato,
          'p_id_tienda': idTienda,
          'p_cantidad': cantidad,
        },
      );

      return DisponibilidadPlato.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      print('❌ Error verificando disponibilidad: $e');
      throw Exception('Error al verificar disponibilidad: $e');
    }
  }

  /// Actualiza disponibilidad manual de un plato
  static Future<void> actualizarDisponibilidadPlato({
    required int idPlato,
    required bool disponible,
    String? motivo,
    int stockDisponible = 0,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      final userId = _supabase.auth.currentUser?.id;

      if (idTienda == null || userId == null) {
        throw Exception('Faltan datos de tienda o usuario');
      }

      await _supabase.from('app_rest_disponibilidad_platos').upsert({
        'id_plato': idPlato,
        'id_tienda': idTienda,
        'fecha_revision': DateTime.now().toIso8601String().split('T')[0],
        'stock_disponible': stockDisponible,
        'ingredientes_suficientes': disponible,
        'motivo_no_disponible': motivo,
        'revisado_por': userId,
        'proxima_revision': DateTime.now().add(Duration(hours: 2)).toIso8601String(),
      });
    } catch (e) {
      print('❌ Error actualizando disponibilidad: $e');
      throw Exception('Error al actualizar disponibilidad: $e');
    }
  }

  // ============================================================================
  // GESTIÓN DE COSTOS DE PRODUCCIÓN
  // ============================================================================

  /// Calcula costo de producción de un plato
  static Future<CostoProduccion> calcularCostoProduccion(int idPlato) async {
    try {
      // Obtener recetas del plato
      final recetas = await _supabase
          .from('app_rest_recetas')
          .select('''
            *,
            producto:app_dat_producto(denominacion, sku)
          ''')
          .eq('id_plato', idPlato);

      double costoIngredientes = 0;

      // Calcular costo de cada ingrediente
      for (final receta in recetas) {
        final idProducto = receta['id_producto_inventario'];
        final cantidadRequerida = (receta['cantidad_requerida'] as num).toDouble();

        // Obtener precio más reciente del producto
        final precioResponse = await _supabase
            .from('app_dat_recepcion_productos')
            .select('precio_unitario, costo_real')
            .eq('id_producto', idProducto)
            .order('created_at', ascending: false)
            .limit(1);

        if (precioResponse.isNotEmpty) {
          final precio = (precioResponse[0]['costo_real'] ?? 
                         precioResponse[0]['precio_unitario'] ?? 0) as num;
          costoIngredientes += cantidadRequerida * precio.toDouble();
        }
      }

      return CostoProduccion(
        idPlato: idPlato,
        fechaCalculo: DateTime.now(),
        costoIngredientes: costoIngredientes,
        costoManoObra: 0, // Se puede configurar por plato
        costoIndirecto: 0, // Se puede configurar por plato
        margenDeseado: 30.0, // Margen por defecto
      );
    } catch (e) {
      print('❌ Error calculando costo de producción: $e');
      throw Exception('Error al calcular costo de producción: $e');
    }
  }

  /// Guarda costo de producción calculado
  static Future<void> guardarCostoProduccion(CostoProduccion costo) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Usuario no autenticado');
      }

      await _supabase.from('app_rest_costos_produccion').insert({
        'id_plato': costo.idPlato,
        'fecha_calculo': costo.fechaCalculo.toIso8601String().split('T')[0],
        'costo_ingredientes': costo.costoIngredientes,
        'costo_mano_obra': costo.costoManoObra,
        'costo_indirecto': costo.costoIndirecto,
        'margen_deseado': costo.margenDeseado,
        'calculado_por': userId,
        'observaciones': costo.observaciones,
      });
    } catch (e) {
      print('❌ Error guardando costo de producción: $e');
      throw Exception('Error al guardar costo de producción: $e');
    }
  }

  /// Obtiene historial de costos de un plato
  static Future<List<CostoProduccion>> getCostosProduccion(int idPlato) async {
    try {
      final response = await _supabase
          .from('app_rest_costos_produccion')
          .select('*')
          .eq('id_plato', idPlato)
          .order('fecha_calculo', ascending: false);

      return (response as List)
          .map((json) => CostoProduccion.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo costos de producción: $e');
      throw Exception('Error al obtener costos de producción: $e');
    }
  }

  // ============================================================================
  // DESCUENTO AUTOMÁTICO DE INVENTARIO
  // ============================================================================

  /// Procesa venta de plato con descuento automático de inventario
  static Future<ResultadoDescuento> procesarVentaPlato({
    required int idVentaPlato,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      final userId = _supabase.auth.currentUser?.id;

      if (idTienda == null || userId == null) {
        throw Exception('Faltan datos de tienda o usuario');
      }

      final response = await _supabase.rpc(
        'fn_descontar_inventario_plato',
        params: {
          'p_id_venta_plato': idVentaPlato,
          'p_id_tienda': idTienda,
          'p_uuid_usuario': userId,
        },
      );

      return ResultadoDescuento.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      print('❌ Error procesando venta de plato: $e');
      throw Exception('Error al procesar venta de plato: $e');
    }
  }

  /// Obtiene historial de descuentos de inventario
  static Future<List<DescuentoInventario>> getDescuentosInventario({
    int? idVentaPlato,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    try {
      var query = _supabase
          .from('app_rest_descuentos_inventario')
          .select('''
            *,
            venta_plato:app_rest_venta_platos(
              cantidad,
              plato:app_rest_platos_elaborados(nombre)
            ),
            producto:app_dat_producto(denominacion, sku),
            ubicacion:app_dat_layout_almacen(sku_codigo)
          ''');

      if (idVentaPlato != null) {
        query = query.eq('id_venta_plato', idVentaPlato);
      }

      if (fechaInicio != null) {
        query = query.gte('fecha_descuento', fechaInicio.toIso8601String());
      }

      if (fechaFin != null) {
        query = query.lte('fecha_descuento', fechaFin.toIso8601String());
      }

      final response = await query.order('fecha_descuento', ascending: false);

      return (response as List)
          .map((json) => DescuentoInventario.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo descuentos de inventario: $e');
      throw Exception('Error al obtener descuentos de inventario: $e');
    }
  }

  // ============================================================================
  // GESTIÓN DE DESPERDICIOS
  // ============================================================================

  /// Registra desperdicio de ingredientes
  static Future<void> registrarDesperdicio({
    required int idProductoInventario,
    int? idPlato,
    required double cantidadDesperdiciada,
    required int idUnidadMedida,
    required String motivoDesperdicio,
    double? costoDesperdicio,
    String? observaciones,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Usuario no autenticado');
      }

      await _supabase.from('app_rest_desperdicios').insert({
        'id_producto_inventario': idProductoInventario,
        'id_plato': idPlato,
        'cantidad_desperdiciada': cantidadDesperdiciada,
        'id_unidad_medida': idUnidadMedida,
        'motivo_desperdicio': motivoDesperdicio,
        'costo_desperdicio': costoDesperdicio,
        'fecha_desperdicio': DateTime.now().toIso8601String(),
        'registrado_por': userId,
        'observaciones': observaciones,
      });
    } catch (e) {
      print('❌ Error registrando desperdicio: $e');
      throw Exception('Error al registrar desperdicio: $e');
    }
  }

  /// Obtiene desperdicios registrados
  static Future<List<Desperdicio>> getDesperdicios({
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? idPlato,
  }) async {
    try {
      var query = _supabase
          .from('app_rest_desperdicios')
          .select('''
            *,
            producto:app_dat_producto(denominacion, sku),
            plato:app_rest_platos_elaborados(nombre),
            unidad:app_nom_unidades_medida(denominacion, abreviatura)
          ''');

      if (fechaInicio != null) {
        query = query.gte('fecha_desperdicio', fechaInicio.toIso8601String());
      }

      if (fechaFin != null) {
        query = query.lte('fecha_desperdicio', fechaFin.toIso8601String());
      }

      if (idPlato != null) {
        query = query.eq('id_plato', idPlato);
      }

      final response = await query.order('fecha_desperdicio', ascending: false);

      return (response as List)
          .map((json) => Desperdicio.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo desperdicios: $e');
      throw Exception('Error al obtener desperdicios: $e');
    }
  }

  // ============================================================================
  // ESTADOS DE PREPARACIÓN
  // ============================================================================

  /// Actualiza estado de preparación de un plato
  static Future<void> actualizarEstadoPreparacion({
    required int idVentaPlato,
    required int estado, // 1=Pendiente, 2=En preparación, 3=Listo, 4=Entregado
    int? tiempoReal,
    String? asignadoA,
    String? observacionesCocina,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Usuario no autenticado');
      }

      await _supabase.from('app_rest_estados_preparacion').insert({
        'id_venta_plato': idVentaPlato,
        'estado': estado,
        'tiempo_real': tiempoReal,
        'asignado_a': asignadoA,
        'observaciones_cocina': observacionesCocina,
        'fecha_cambio_estado': DateTime.now().toIso8601String(),
        'cambiado_por': userId,
      });
    } catch (e) {
      print('❌ Error actualizando estado de preparación: $e');
      throw Exception('Error al actualizar estado de preparación: $e');
    }
  }

  /// Obtiene estados de preparación de platos
  static Future<List<EstadoPreparacion>> getEstadosPreparacion({
    int? idVentaPlato,
    int? estado,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    try {
      var query = _supabase
          .from('app_rest_estados_preparacion')
          .select('''
            *,
            venta_plato:app_rest_venta_platos(
              cantidad,
              plato:app_rest_platos_elaborados(nombre, tiempo_preparacion)
            )
          ''');

      if (idVentaPlato != null) {
        query = query.eq('id_venta_plato', idVentaPlato);
      }

      if (estado != null) {
        query = query.eq('estado', estado);
      }

      if (fechaInicio != null) {
        query = query.gte('fecha_cambio_estado', fechaInicio.toIso8601String());
      }

      if (fechaFin != null) {
        query = query.lte('fecha_cambio_estado', fechaFin.toIso8601String());
      }

      final response = await query.order('fecha_cambio_estado', ascending: false);

      return (response as List)
          .map((json) => EstadoPreparacion.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo estados de preparación: $e');
      throw Exception('Error al obtener estados de preparación: $e');
    }
  }

  // ============================================================================
  // REPORTES Y ANÁLISIS
  // ============================================================================

  /// Genera reporte de eficiencia por plato
  static Future<Map<String, dynamic>> getReporteEficiencia({
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      // Este sería un RPC personalizado para generar reportes
      final response = await _supabase.rpc(
        'fn_reporte_eficiencia_restaurante',
        params: {
          'p_id_tienda': idTienda,
          'p_fecha_inicio': fechaInicio?.toIso8601String(),
          'p_fecha_fin': fechaFin?.toIso8601String(),
        },
      );

      return response as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error generando reporte de eficiencia: $e');
      throw Exception('Error al generar reporte de eficiencia: $e');
    }
  }
}
