import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class FinancialService {
  static final FinancialService _instance = FinancialService._internal();
  factory FinancialService() => _instance;
  FinancialService._internal();

  final _supabase = Supabase.instance.client;

  // ==================== CATEGORÍAS DE GASTOS ====================

  /// Crear categorías de gastos estándar del sistema
  Future<void> createStandardExpenseCategories() async {
    try {
      final standardCategories = [
        {
          'denominacion': 'Compra de Mercancía',
          'descripcion': 'Gastos relacionados con la adquisición de productos para la venta',
        },
        {
          'denominacion': 'Gastos Operativos',
          'descripcion': 'Gastos necesarios para la operación diaria del negocio',
        },
        {
          'denominacion': 'Gastos Administrativos',
          'descripcion': 'Gastos relacionados con la administración y gestión del negocio',
        },
        {
          'denominacion': 'Servicios Públicos',
          'descripcion': 'Electricidad, agua, gas, internet, teléfono',
        },
        {
          'denominacion': 'Mantenimiento',
          'descripcion': 'Reparaciones y mantenimiento de equipos e instalaciones',
        },
        {
          'denominacion': 'Transporte y Logística',
          'descripcion': 'Gastos de transporte, combustible, envíos',
        },
      ];

      for (final category in standardCategories) {
        try {
          await _supabase.from('app_nom_categoria_gasto').insert(category);
        } catch (e) {
          // Ignorar errores de duplicados
          if (!e.toString().contains('duplicate') && !e.toString().contains('unique')) {
            rethrow;
          }
        }
      }

      print('✅ Categorías de gastos estándar creadas exitosamente');
    } catch (e) {
      print('❌ Error creando categorías de gastos: $e');
      rethrow;
    }
  }

  /// Crear subcategorías de gastos estándar
  Future<void> createStandardExpenseSubcategories() async {
    try {
      // Obtener categorías existentes
      final categories = await getExpenseCategories();
      final categoryMap = {for (var cat in categories) cat['denominacion']: cat['id']};

      final standardSubcategories = [
        {
          'id_categoria_gasto': categoryMap['Compra de Mercancía'],
          'denominacion': 'Productos Alimentarios',
          'descripcion': 'Compra de productos alimentarios para venta',
        },
        {
          'id_categoria_gasto': categoryMap['Compra de Mercancía'],
          'denominacion': 'Productos No Alimentarios',
          'descripcion': 'Compra de productos no alimentarios para venta',
        },
        {
          'id_categoria_gasto': categoryMap['Gastos Operativos'],
          'denominacion': 'Limpieza y Aseo',
          'descripcion': 'Productos de limpieza y aseo para el local',
        },
        {
          'id_categoria_gasto': categoryMap['Gastos Operativos'],
          'denominacion': 'Merma y Pérdidas',
          'descripcion': 'Productos vencidos, dañados o perdidos',
        },
        {
          'id_categoria_gasto': categoryMap['Gastos Administrativos'],
          'denominacion': 'Papelería y Oficina',
          'descripcion': 'Materiales de oficina y papelería',
        },
        {
          'id_categoria_gasto': categoryMap['Servicios Públicos'],
          'denominacion': 'Electricidad',
          'descripcion': 'Consumo de energía eléctrica',
        },
        {
          'id_categoria_gasto': categoryMap['Servicios Públicos'],
          'denominacion': 'Agua y Alcantarillado',
          'descripcion': 'Consumo de agua y servicios de alcantarillado',
        },
        {
          'id_categoria_gasto': categoryMap['Servicios Públicos'],
          'denominacion': 'Internet y Telefonía',
          'descripcion': 'Servicios de internet y comunicaciones',
        },
      ];

      for (final subcategory in standardSubcategories) {
        if (subcategory['id_categoria_gasto'] != null) {
          try {
            await _supabase.from('app_nom_subcategoria_gasto').insert(subcategory);
          } catch (e) {
            // Ignorar errores de duplicados
            if (!e.toString().contains('duplicate') && !e.toString().contains('unique')) {
              rethrow;
            }
          }
        }
      }

      print('✅ Subcategorías de gastos estándar creadas exitosamente');
    } catch (e) {
      print('❌ Error creando subcategorías de gastos: $e');
      rethrow;
    }
  }

  /// Obtener todas las categorías de gastos
  Future<List<Map<String, dynamic>>> getExpenseCategories() async {
    try {
      final response = await _supabase
          .from('app_nom_categoria_gasto')
          .select('id, denominacion, descripcion, created_at')
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo categorías de gastos: $e');
      return [];
    }
  }

  /// Obtener subcategorías de gastos por categoría
  Future<List<Map<String, dynamic>>> getExpenseSubcategories({int? categoryId}) async {
    try {
      var query = _supabase
          .from('app_nom_subcategoria_gasto')
          .select('''
            id, 
            id_categoria_gasto, 
            denominacion, 
            descripcion, 
            created_at,
            app_nom_categoria_gasto!inner(denominacion)
          ''');

      if (categoryId != null) {
        query = query.filter('id_categoria_gasto', 'eq', categoryId);
      }

      final response = await query.order('denominacion');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo subcategorías de gastos: $e');
      return [];
    }
  }

  /// Obtener estructura jerárquica de categorías y subcategorías de gastos
  Future<List<Map<String, dynamic>>> getExpenseCategoriesHierarchy() async {
    try {
      // Obtener todas las categorías
      final categories = await getExpenseCategories();
      
      // Obtener todas las subcategorías con información de categoría
      final subcategories = await getExpenseSubcategories();
      
      // Crear estructura jerárquica
      final hierarchy = <Map<String, dynamic>>[];
      
      for (final category in categories) {
        final categoryId = category['id'];
        
        // Filtrar subcategorías que pertenecen a esta categoría
        final categorySubcategories = subcategories
            .where((sub) => sub['id_categoria_gasto'] == categoryId)
            .toList();
        
        hierarchy.add({
          'id': 'cat_$categoryId',
          'type': 'category',
          'category_id': categoryId,
          'name': category['denominacion'],
          'description': category['descripcion'],
          'children': categorySubcategories.map((sub) => {
            'id': 'sub_${sub['id']}',
            'type': 'subcategory',
            'subcategory_id': sub['id'],
            'category_id': categoryId,
            'name': sub['denominacion'],
            'description': sub['descripcion'],
          }).toList(),
        });
      }
      
      return hierarchy;
    } catch (e) {
      print('❌ Error obteniendo jerarquía de categorías: $e');
      return [];
    }
  }

  /// Obtener operaciones pendientes de registrar como gastos
  Future<List<Map<String, dynamic>>> getPendingExpenseOperations({
    String? startDate,
    String? endDate,
    List<String>? categoryIds,
  }) async {
    try {
      final storeId = await _getStoreId();
      final pendingOperations = <Map<String, dynamic>>[];

      // 1. Obtener recepciones de inventario pendientes
      final receptions = await _getPendingReceptions(storeId, startDate, endDate);
      pendingOperations.addAll(receptions);

      // 2. Obtener entregas parciales de caja pendientes
      final cashWithdrawals = await _getPendingCashWithdrawals(storeId, startDate, endDate);
      pendingOperations.addAll(cashWithdrawals);

      // Filtrar por categorías si se especifican
      if (categoryIds != null && categoryIds.isNotEmpty) {
        return pendingOperations.where((op) => 
          categoryIds.contains(op['id_subcategoria_gasto']?.toString())
        ).toList();
      }

      // Ordenar por fecha descendente
      pendingOperations.sort((a, b) => 
        (b['fecha_operacion'] ?? '').compareTo(a['fecha_operacion'] ?? '')
      );

      return pendingOperations;
    } catch (e) {
      print('❌ Error obteniendo operaciones pendientes: $e');
      return [];
    }
  }

  /// Obtener recepciones de inventario pendientes de registrar como gastos
  Future<List<Map<String, dynamic>>> _getPendingReceptions(
    int storeId, 
    String? startDate, 
    String? endDate
  ) async {
    try {
      // Obtener recepciones que no han sido registradas como gastos
      var query = _supabase
          .from('app_dat_operaciones')
          .select('''
            id,
            created_at,
            observaciones,
            uuid,
            app_dat_operacion_recepcion!inner(
              monto_total,
              entregado_por,
              recibido_por,
              observaciones_compra,
              motivo
            ),
            app_dat_recepcion_productos(
              id,
              cantidad,
              precio_unitario,
              descuento_monto,
              bonificacion_cantidad,
              costo_real,
              app_dat_producto(denominacion)
            )
          ''')
          .eq('id_tienda', storeId)
          .eq('id_tipo_operacion', 1) // Tipo operación recepción
          .eq('app_dat_operacion_recepcion.motivo', 1); // Solo recepciones por compra (motivo = 1)

      if (startDate != null) {
        query = query.gte('created_at', startDate);
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate);
      }

      final response = await query.order('created_at', ascending: false);
      
      // Filtrar recepciones que ya no tienen gastos registrados
      final pendingReceptions = <Map<String, dynamic>>[];
      
      for (final reception in response) {
        // Verificar si ya existe un gasto registrado para esta recepción
        final existingExpense = await _supabase
            .from('app_cont_gastos')
            .select('id')
            .eq('tipo_origen', 'operacion_recepcion')
            .eq('id_referencia_origen', reception['id'])
            .maybeSingle();
            
        if (existingExpense == null) {
          // Esta recepción no tiene gasto registrado, agregarla a pendientes
          final products = reception['app_dat_recepcion_productos'] as List<dynamic>? ?? [];
          final productNames = products
              .map((p) => (p as Map<String, dynamic>?)?['app_dat_producto']?['denominacion'] ?? 'Producto')
              .take(3)
              .join(', ');
          
          final receptionData = reception['app_dat_operacion_recepcion'] as Map<String, dynamic>?;
          final totalAmount = receptionData?['monto_total'] as num? ?? 0.0;
          final entregadoPor = receptionData?['entregado_por'] ?? 'Sin proveedor';
          
          pendingReceptions.add({
            'id': reception['id'],
            'tipo_operacion': 'recepcion',
            'descripcion': 'Recepción por Compra: $productNames${products.length > 3 ? '...' : ''}',
            'monto': totalAmount.toDouble(),
            'fecha_operacion': reception['created_at']?.toString().split('T')[0] ?? '',
            'proveedor': entregadoPor,
            'motivo': 'Compra',
            'observaciones': receptionData?['observaciones_compra'] ?? reception['observaciones'],
            'id_subcategoria_gasto': 1, // Compra de Mercancía
            'id_centro_costo': 1, // Centro de costo por defecto
            'original_data': reception,
          });
        }
      }
      
      return pendingReceptions;
    } catch (e) {
      print('❌ Error obteniendo recepciones pendientes: $e');
      return [];
    }
  }

  /// Obtener entregas parciales de caja pendientes de registrar como gastos
  Future<List<Map<String, dynamic>>> _getPendingCashWithdrawals(
    int storeId,
    String? startDate,
    String? endDate
  ) async {
    try {
      // Obtener entregas de efectivo que no han sido registradas como gastos
      // Buscar directamente en la tabla app_dat_entregas_parciales_caja
      var query = _supabase
          .from('app_dat_entregas_parciales_caja')
          .select('''
            id,
            id_turno,
            monto_entrega,
            motivo_entrega,
            nombre_recibe,
            nombre_autoriza,
            fecha_entrega,
            id_medio_pago,
            app_dat_caja_turno!inner(
              id_tienda,
              id_vendedor,
              app_dat_vendedor(denominacion)
            )
          ''')
          .eq('app_dat_caja_turno.id_tienda', storeId);

      if (startDate != null) {
        query = query.gte('fecha_entrega', startDate);
      }
      if (endDate != null) {
        query = query.lte('fecha_entrega', endDate);
      }

      final response = await query.order('fecha_entrega', ascending: false);
      
      // Filtrar entregas que ya no tienen gastos registrados
      final pendingWithdrawals = <Map<String, dynamic>>[];
      
      for (final withdrawal in response) {
        // Verificar si ya existe un gasto registrado para esta entrega
        final existingExpense = await _supabase
            .from('app_cont_gastos')
            .select('id')
            .eq('tipo_origen', 'egreso_efectivo') // Cambiar a tipo_origen para egresos
            .eq('id_referencia_origen', withdrawal['id']) // Agregar referencia específica
            .maybeSingle();
            
        // También verificar si el egreso fue rechazado
        final rejectedWithdrawal = await _supabase
            .from('app_cont_egresos_procesados')
            .select('id')
            .eq('id_egreso', withdrawal['id'])
            .eq('estado', 'rechazado')
            .maybeSingle();
            
        if (existingExpense == null && rejectedWithdrawal == null) {
          // Esta entrega no tiene gasto registrado, agregarla a pendientes
          final amount = withdrawal['monto_entrega'] as num? ?? 0.0;
          final motivo = withdrawal['motivo_entrega'] ?? 'Entrega de efectivo';
          final nombreRecibe = withdrawal['nombre_recibe'] ?? 'Sin especificar';
          final nombreAutoriza = withdrawal['nombre_autoriza'] ?? 'Sin especificar';
          
          // Obtener información del vendedor del turno
          final turnoData = withdrawal['app_dat_caja_turno'] as Map<String, dynamic>?;
          final vendedorData = turnoData?['app_dat_vendedor'] as Map<String, dynamic>?;
          String vendedorName = 'Vendedor desconocido';
          if (vendedorData != null) {
            vendedorName = vendedorData['denominacion'] ?? 'Vendedor desconocido';
          }
          
          pendingWithdrawals.add({
            'id': withdrawal['id'],
            'tipo_operacion': 'entrega_efectivo',
            'descripcion': 'Entrega de efectivo: $motivo',
            'monto': amount.toDouble(),
            'fecha_operacion': withdrawal['fecha_entrega']?.toString().split('T')[0] ?? '',
            'usuario': vendedorName,
            'motivo': motivo,
            'nombre_recibe': nombreRecibe,
            'nombre_autoriza': nombreAutoriza,
            'observaciones': 'Recibe: $nombreRecibe, Autoriza: $nombreAutoriza',
            'id_subcategoria_gasto': 2, // Gastos Operativos por defecto
            'id_centro_costo': 1, // Centro de costo por defecto
            'original_data': withdrawal,
          });
        }
      }
      
      return pendingWithdrawals;
    } catch (e) {
      print('❌ Error obteniendo entregas de efectivo pendientes: $e');
      return [];
    }
  }

  /// Registrar gasto desde operación pendiente
  Future<bool> registerExpenseFromOperation(Map<String, dynamic> operation, {
    int? subcategoryId,
    int? costCenterId,
    String? customDescription,
  }) async {
    try {
      final storeId = await _getStoreId();
      final userId = await _getUserId();

      final expenseData = {
        'descripcion': customDescription ?? operation['descripcion'],
        'monto': operation['monto'],
        'fecha_gasto': operation['fecha_operacion'],
        'id_subcategoria_gasto': subcategoryId ?? operation['id_subcategoria_gasto'],
        'id_centro_costo': costCenterId ?? operation['id_centro_costo'],
        'id_tienda': storeId,
        'usuario_creador': userId,
        'observaciones': operation['observaciones'],
        'tipo_origen': operation['tipo_operacion'], // Cambiar a tipo_origen
        'id_referencia_origen': operation['id'], // Agregar referencia específica
      };

      await _supabase.from('app_cont_gastos').insert(expenseData);

      // Marcar operación como procesada (opcional)
      await _markOperationAsProcessed(operation);

      print('✅ Gasto registrado desde operación exitosamente');
      return true;
    } catch (e) {
      print('❌ Error registrando gasto desde operación: $e');
      return false;
    }
  }

  /// Marcar operación como procesada
  Future<void> _markOperationAsProcessed(Map<String, dynamic> operation) async {
    try {
      // Crear registro en tabla de control de operaciones procesadas
      await _supabase.from('app_cont_operacion_gasto').insert({
        'id_operacion': operation['id'],
        'tipo_operacion': operation['tipo_operacion'],
        'fecha_procesado': DateTime.now().toIso8601String(),
        'procesado': true,
      });
    } catch (e) {
      // No es crítico si falla, solo para auditoría
      print('⚠️ No se pudo marcar operación como procesada: $e');
    }
  }

  /// Omitir registro de gasto para una operación
  Future<bool> skipExpenseFromOperation(Map<String, dynamic> operation, String reason) async {
    try {
      await _supabase.from('app_cont_operacion_gasto').insert({
        'id_operacion': operation['id'],
        'tipo_operacion': operation['tipo_operacion'],
        'fecha_procesado': DateTime.now().toIso8601String(),
        'procesado': false,
        'motivo_omision': reason,
      });

      print('✅ Operación omitida exitosamente');
      return true;
    } catch (e) {
      print('❌ Error omitiendo operación: $e');
      return false;
    }
  }

  // ==================== TIPOS DE COSTO ====================

  /// Crear tipos de costo estándar
  Future<void> createStandardCostTypes() async {
    try {
      final standardCostTypes = [
        {
          'denominacion': 'Costo Directo',
          'descripcion': 'Costos directamente relacionados con la producción o venta',
          'naturaleza': 1, // Gasto
          'afecta_margen': true,
        },
        {
          'denominacion': 'Costo Indirecto',
          'descripcion': 'Costos indirectos de operación y administración',
          'naturaleza': 1, // Gasto
          'afecta_margen': true,
        },
        {
          'denominacion': 'Costo Fijo',
          'descripcion': 'Costos que no varían con el volumen de ventas',
          'naturaleza': 1, // Gasto
          'afecta_margen': false,
        },
        {
          'denominacion': 'Costo Variable',
          'descripcion': 'Costos que varían proporcionalmente con las ventas',
          'naturaleza': 1, // Gasto
          'afecta_margen': true,
        },
      ];

      for (final costType in standardCostTypes) {
        try {
          await _supabase.from('app_cont_tipo_costo').insert(costType);
        } catch (e) {
          // Ignorar errores de duplicados
          if (!e.toString().contains('duplicate') && !e.toString().contains('unique')) {
            rethrow;
          }
        }
      }

      print('✅ Tipos de costo estándar creados exitosamente');
    } catch (e) {
      print('❌ Error creando tipos de costo: $e');
      rethrow;
    }
  }

  /// Obtener todos los tipos de costo
  Future<List<Map<String, dynamic>>> getCostTypes() async {
    try {
      final response = await _supabase
          .from('app_cont_tipo_costo')
          .select('''
            id, 
            denominacion, 
            descripcion, 
            naturaleza, 
            afecta_margen, 
            created_at,
            app_nom_naturaleza_costo!inner(denominacion)
          ''')
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo tipos de costo: $e');
      return [];
    }
  }

  /// Crear nuevo tipo de costo
  Future<void> createCostType(String name, String description, {int naturaleza = 1, bool afectaMargen = true}) async {
    try {
      await _supabase.from('app_cont_tipo_costo').insert({
        'denominacion': name,
        'descripcion': description,
        'naturaleza': naturaleza,
        'afecta_margen': afectaMargen,
      });
    } catch (e) {
      print('❌ Error creando tipo de costo: $e');
      rethrow;
    }
  }

  /// Actualizar tipo de costo
  Future<void> updateCostType(int id, String name, String description, {int? naturaleza, bool? afectaMargen}) async {
    try {
      final updateData = <String, dynamic>{
        'denominacion': name,
        'descripcion': description,
      };
      
      if (naturaleza != null) updateData['naturaleza'] = naturaleza;
      if (afectaMargen != null) updateData['afecta_margen'] = afectaMargen;
      
      await _supabase
          .from('app_cont_tipo_costo')
          .update(updateData)
          .filter('id', 'eq', id);
    } catch (e) {
      print('❌ Error actualizando tipo de costo: $e');
      rethrow;
    }
  }

  /// Eliminar tipo de costo
  Future<void> deleteCostType(int id) async {
    try {
      await _supabase
          .from('app_cont_tipo_costo')
          .delete()
          .filter('id', 'eq', id);
    } catch (e) {
      print('❌ Error eliminando tipo de costo: $e');
      rethrow;
    }
  }

  // ==================== CENTROS DE COSTO ====================

  /// Crear centros de costo basados en las tiendas existentes
  Future<void> createCostCentersFromStores() async {
    try {
      print('🏪 Creando centros de costo desde tiendas...');
      
      final storeId = await _getStoreId();
      
      // Verificar si ya existen centros de costo para esta tienda
      final existingCenters = await _supabase
          .from('app_cont_centro_costo')
          .select('id')
          .eq('id_tienda', storeId)
          .count(CountOption.exact);
      
      if ((existingCenters.count ?? 0) > 0) {
        print('✅ Centros de costo ya existen para la tienda $storeId');
        return;
      }

      // Obtener información de la tienda del usuario
      final storeResponse = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion, direccion')
          .filter('id', 'eq', storeId)
          .single();

      final storeName = storeResponse['denominacion'] ?? 'Tienda $storeId';
      final storeDescription = storeResponse['direccion'] ?? 'Tienda principal';

      // Crear centros de costo estándar para la tienda
      final standardCostCenters = [
        {
          'id_tienda': storeId,
          'denominacion': storeName,
          'descripcion': storeDescription,
          'codigo': 'CC-PRINCIPAL-$storeId',
          'sku_codigo': 'TIENDA-$storeId',
          'id_padre': null,
        },
        {
          'id_tienda': storeId,
          'denominacion': 'Administración',
          'descripcion': 'Área administrativa de $storeName',
          'codigo': 'CC-ADMIN-$storeId',
          'sku_codigo': 'ADMIN-$storeId',
          'id_padre': null,
        },
        {
          'id_tienda': storeId,
          'denominacion': 'Ventas',
          'descripcion': 'Área de ventas de $storeName',
          'codigo': 'CC-VENTAS-$storeId',
          'sku_codigo': 'VENTAS-$storeId',
          'id_padre': null,
        },
        {
          'id_tienda': storeId,
          'denominacion': 'Almacén',
          'descripcion': 'Almacén e inventario de $storeName',
          'codigo': 'CC-ALMACEN-$storeId',
          'sku_codigo': 'ALM-$storeId',
          'id_padre': null,
        },
        {
          'id_tienda': storeId,
          'denominacion': 'Marketing',
          'descripcion': 'Actividades de marketing de $storeName',
          'codigo': 'CC-MKT-$storeId',
          'sku_codigo': 'MKT-$storeId',
          'id_padre': null,
        },
      ];

      for (final costCenter in standardCostCenters) {
        try {
          await _supabase.from('app_cont_centro_costo').insert(costCenter);
          print('✅ Centro de costo creado: ${costCenter['denominacion']}');
        } catch (e) {
          // Ignorar errores de duplicados
          if (!e.toString().contains('duplicate') && !e.toString().contains('unique')) {
            print('❌ Error creando centro ${costCenter['denominacion']}: $e');
          }
        }
      }

      print('✅ Centros de costo creados para tienda $storeId');
    } catch (e) {
      print('❌ Error creando centros de costo: $e');
      rethrow;
    }
  }

  /// Obtener centros de costo
  Future<List<Map<String, dynamic>>> getCostCenters({int? storeId}) async {
    try {
      storeId ??= await _getStoreId();
      
      var query = _supabase
          .from('app_cont_centro_costo')
          .select('''
            id, 
            id_padre, 
            id_tienda, 
            denominacion, 
            descripcion, 
            codigo, 
            sku_codigo, 
            created_at,
            app_dat_tienda(denominacion)
          ''')
          .eq('id_tienda', storeId);

      final response = await query.order('denominacion');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo centros de costo: $e');
      return [];
    }
  }

  // ==================== MÁRGENES COMERCIALES ====================

  /// Crear márgenes comerciales por defecto
  Future<void> createDefaultProfitMargins() async {
    try {
      final storeId = await _getStoreId();
      
      // Obtener productos de la tienda
      final products = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion')
          .eq('id_tienda', storeId);

      for (final product in products) {
        // Obtener precios activos para este producto
        final precios = await _supabase
            .from('app_dat_precio_venta')
            .select('id, precio_venta_cup, id_variante, fecha_desde, fecha_hasta')
            .eq('id_producto', product['id'])
            .isFilter('fecha_hasta', null)
            .lte('fecha_desde', DateTime.now().toIso8601String().split('T')[0]);
        
        for (final precio in precios) {
          // Verificar si ya existe un margen definido para esta variante
          final existingMargin = await _supabase
              .from('app_cont_margen_comercial')
              .select('id')
              .eq('id_producto', product['id'])
              .eq('id_tienda', storeId)
              .eq('id_variante', precio['id_variante'] ?? 0)
              .maybeSingle();

          if (existingMargin == null) {
            final precioVenta = precio['precio_venta_cup'] ?? 0.0;
            final margin = {
              'id_producto': product['id'],
              'id_variante': precio['id_variante'],
              'id_tienda': storeId,
              'margen_deseado': 30.0, // Margen por defecto del 30%
              'tipo_margen': 1, // 1 = porcentaje, 2 = valor fijo
              'fecha_desde': DateTime.now().toIso8601String().split('T')[0],
            };

            try {
              await _supabase.from('app_cont_margen_comercial').insert(margin);
            } catch (e) {
              // Ignorar errores de duplicados
              if (!e.toString().contains('duplicate') && !e.toString().contains('unique')) {
                rethrow;
              }
            }
          }
        }
      }

      print('✅ Márgenes comerciales por defecto creados exitosamente');
    } catch (e) {
      print('❌ Error creando márgenes comerciales: $e');
      rethrow;
    }
  }

  /// Obtener márgenes comerciales
  Future<List<Map<String, dynamic>>> getProfitMargins({int? productId, int? storeId}) async {
    try {
      storeId ??= await _getStoreId();
      
      var query = _supabase
          .from('app_cont_margen_comercial')
          .select('''
            id, 
            id_producto, 
            id_variante, 
            id_tienda, 
            margen_deseado, 
            tipo_margen, 
            fecha_desde, 
            fecha_hasta, 
            created_at
          ''')
          .eq('id_tienda', storeId);

      if (productId != null) {
        query = query.eq('id_producto', productId);
      }

      final response = await query.order('fecha_desde', ascending: false);
      
      // Enriquecer con datos de productos manualmente
      final enrichedResponse = <Map<String, dynamic>>[];
      for (final margin in response) {
        final enrichedMargin = Map<String, dynamic>.from(margin);
        
        // Obtener nombre del producto
        try {
          final product = await _supabase
              .from('app_dat_producto')
              .select('denominacion')
              .eq('id', margin['id_producto'])
              .single();
          enrichedMargin['producto_nombre'] = product['denominacion'];
        } catch (e) {
          enrichedMargin['producto_nombre'] = 'Producto ${margin['id_producto']}';
        }
        
        // Obtener nombre de variante si existe
        if (margin['id_variante'] != null) {
          try {
            final variant = await _supabase
                .from('app_dat_variantes')
                .select('denominacion')
                .eq('id', margin['id_variante'])
                .single();
            enrichedMargin['variante_nombre'] = variant['denominacion'];
          } catch (e) {
            enrichedMargin['variante_nombre'] = 'Variante ${margin['id_variante']}';
          }
        }
        
        enrichedResponse.add(enrichedMargin);
      }
      
      return enrichedResponse;
    } catch (e) {
      print('❌ Error obteniendo márgenes comerciales: $e');
      return [];
    }
  }

  /// Actualizar margen comercial
  Future<bool> updateProfitMargin({
    required int productId,
    int? variantId,
    required double marginDesired,
    required int marginType,
  }) async {
    try {
      final storeId = await _getStoreId();
      final userId = await _getUserId();

      // Cerrar margen actual si existe
      await _supabase
          .from('app_cont_margen_comercial')
          .update({'fecha_hasta': DateTime.now().toIso8601String().split('T')[0]})
          .eq('id_producto', productId)
          .eq('id_tienda', storeId)
          .isFilter('fecha_hasta', null);

      // Crear nuevo margen
      final newMargin = {
        'id_producto': productId,
        'id_variante': variantId,
        'id_tienda': storeId,
        'margen_deseado': marginDesired,
        'tipo_margen': marginType,
        'fecha_desde': DateTime.now().toIso8601String().split('T')[0],
      };

      await _supabase.from('app_cont_margen_comercial').insert(newMargin);

      print('✅ Margen comercial actualizado exitosamente');
      return true;
    } catch (e) {
      print('❌ Error actualizando margen comercial: $e');
      return false;
    }
  }

  /// Eliminar margen comercial
  Future<void> deleteProfitMargin(int id) async {
    try {
      await _supabase
          .from('app_cont_margen_comercial')
          .delete()
          .eq('id', id);
    } catch (e) {
      print('❌ Error eliminando margen comercial: $e');
      rethrow;
    }
  }

  // ==================== NATURALEZA DE COSTOS ====================

  /// Crear naturalezas de costo estándar
  Future<void> createStandardCostNatures() async {
    try {
      final standardNatures = [
        {
          'id': 1,
          'denominacion': 'Gasto',
          'descripcion': 'Erogaciones que afectan negativamente el resultado',
        },
        {
          'id': 2,
          'denominacion': 'Ingreso',
          'descripcion': 'Entradas que afectan positivamente el resultado',
        },
      ];

      for (final nature in standardNatures) {
        try {
          await _supabase.from('app_nom_naturaleza_costo').insert(nature);
        } catch (e) {
          // Ignorar errores de duplicados
          if (!e.toString().contains('duplicate') && !e.toString().contains('unique')) {
            rethrow;
          }
        }
      }

      print('✅ Naturalezas de costo estándar creadas exitosamente');
    } catch (e) {
      print('❌ Error creando naturalezas de costo: $e');
      rethrow;
    }
  }

  /// Obtener naturalezas de costo
  Future<List<Map<String, dynamic>>> getCostNatures() async {
    try {
      final response = await _supabase
          .from('app_nom_naturaleza_costo')
          .select('id, denominacion, descripcion, created_at')
          .order('id');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo naturalezas de costo: $e');
      return [];
    }
  }

  // ==================== INICIALIZACIÓN COMPLETA ====================

  /// Inicializar todo el sistema financiero básico
  Future<void> initializeFinancialSystem() async {
    try {
      print('🚀 Iniciando configuración del sistema financiero...');
      
      await createStandardCostNatures();
      // Omitir categorías y subcategorías ya que existen datos
      // await createStandardExpenseCategories();
      // await createStandardExpenseSubcategories();
      // Omitir tipos de costos ya que existen datos
      // await createStandardCostTypes();
      // Crear centros de costo para la tienda del usuario autenticado
      await createCostCentersFromStores();
      await createDefaultProfitMargins();
      
      print('✅ Sistema financiero inicializado correctamente');
    } catch (e) {
      print('❌ Error inicializando sistema financiero: $e');
      rethrow;
    }
  }

  // ==================== UTILIDADES PRIVADAS ====================

  Future<int> _getStoreId() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      return storeId ?? 1; // Valor por defecto si no hay tienda configurada
    } catch (e) {
      print('❌ Error obteniendo store ID: $e');
      return 1; // Valor por defecto
    }
  }

  Future<String> _getUserId() async {
    try {
      final userPrefs = UserPreferencesService();
      final userId = await userPrefs.getUserId();
      return userId ?? 'default-user'; // Valor por defecto si no hay usuario
    } catch (e) {
      print('❌ Error obteniendo user ID: $e');
      return 'default-user'; // Valor por defecto
    }
  }

  // ==================== PRODUCTOS Y VARIANTES ====================

  /// Obtener productos para márgenes comerciales
  Future<List<Map<String, dynamic>>> getProducts() async {
    try {
      final storeId = await _getStoreId();
      final products = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion, descripcion')
          .eq('id_tienda', storeId)
          .order('denominacion');
      return List<Map<String, dynamic>>.from(products);
    } catch (e) {
      print('❌ Error obteniendo productos: $e');
      rethrow;
    }
  }

  /// Obtener variantes de un producto
  Future<List<Map<String, dynamic>>> getProductVariants(int productId) async {
    try {
      final variants = await _supabase
          .from('app_dat_variantes')
          .select('id, denominacion, descripcion')
          .eq('id_producto', productId)
          .order('denominacion');
      return List<Map<String, dynamic>>.from(variants);
    } catch (e) {
      print('❌ Error obteniendo variantes: $e');
      rethrow;
    }
  }

  // ==================== CRUD CATEGORÍAS DE GASTOS ====================

  /// Crear nueva categoría de gastos
  Future<void> createExpenseCategory(String name, String description) async {
    try {
      await _supabase.from('app_nom_categoria_gasto').insert({
        'denominacion': name,
        'descripcion': description,
      });
    } catch (e) {
      print('❌ Error creando categoría: $e');
      rethrow;
    }
  }

  /// Actualizar categoría de gastos
  Future<void> updateExpenseCategory(int id, String name, String description) async {
    try {
      await _supabase
          .from('app_nom_categoria_gasto')
          .update({
            'denominacion': name,
            'descripcion': description,
          })
          .eq('id', id);
    } catch (e) {
      print('❌ Error actualizando categoría: $e');
      rethrow;
    }
  }

  /// Eliminar categoría de gastos
  Future<void> deleteExpenseCategory(int id) async {
    try {
      await _supabase
          .from('app_nom_categoria_gasto')
          .delete()
          .eq('id', id);
    } catch (e) {
      print('❌ Error eliminando categoría: $e');
      rethrow;
    }
  }

  /// Crear nueva subcategoría de gastos
  Future<void> createExpenseSubcategory(String name, String description, int categoryId) async {
    try {
      await _supabase.from('app_nom_subcategoria_gasto').insert({
        'denominacion': name,
        'descripcion': description,
        'id_categoria_gasto': categoryId,
      });
    } catch (e) {
      print('❌ Error creando subcategoría: $e');
      rethrow;
    }
  }

  /// Actualizar subcategoría de gastos
  Future<void> updateExpenseSubcategory(int id, String name, String description, int categoryId) async {
    try {
      await _supabase
          .from('app_nom_subcategoria_gasto')
          .update({
            'denominacion': name,
            'descripcion': description,
            'id_categoria_gasto': categoryId,
          })
          .eq('id', id);
    } catch (e) {
      print('❌ Error actualizando subcategoría: $e');
      rethrow;
    }
  }

  /// Eliminar subcategoría de gastos
  Future<void> deleteExpenseSubcategory(int id) async {
    try {
      await _supabase
          .from('app_nom_subcategoria_gasto')
          .delete()
          .eq('id', id);
    } catch (e) {
      print('❌ Error eliminando subcategoría: $e');
      rethrow;
    }
  }

  // ==================== CRUD CENTROS DE COSTO ====================

  /// Crear nuevo centro de costo
  Future<void> createCostCenter(String name, String? description, String? code, String? skuCode, int? parentId) async {
    try {
      final storeId = await _getStoreId();
      await _supabase.from('app_cont_centro_costo').insert({
        'denominacion': name,
        'descripcion': description,
        'codigo': code,
        'sku_codigo': skuCode,
        'id_padre': parentId,
        'id_tienda': storeId,
      });
    } catch (e) {
      print('❌ Error creando centro de costo: $e');
      rethrow;
    }
  }

  /// Actualizar centro de costo
  Future<void> updateCostCenter(int id, String name, String? description, String? code, String? skuCode, int? parentId) async {
    try {
      await _supabase
          .from('app_cont_centro_costo')
          .update({
            'denominacion': name,
            'descripcion': description,
            'codigo': code,
            'sku_codigo': skuCode,
            'id_padre': parentId,
          })
          .eq('id', id);
    } catch (e) {
      print('❌ Error actualizando centro de costo: $e');
      rethrow;
    }
  }

  /// Eliminar centro de costo
  Future<void> deleteCostCenter(int id) async {
    try {
      await _supabase
          .from('app_cont_centro_costo')
          .delete()
          .eq('id', id);
    } catch (e) {
      print('❌ Error eliminando centro de costo: $e');
      rethrow;
    }
  }

  // ==================== CRUD MÁRGENES COMERCIALES ====================

  /// Crear nuevo margen comercial
  Future<void> createProfitMargin({
    required int productId,
    int? variantId,
    required double marginDesired,
    required int marginType,
  }) async {
    try {
      final storeId = await _getStoreId();
      await _supabase.from('app_cont_margen_comercial').insert({
        'id_producto': productId,
        'id_variante': variantId,
        'id_tienda': storeId,
        'margen_deseado': marginDesired,
        'tipo_margen': marginType,
        'fecha_desde': DateTime.now().toIso8601String().split('T')[0],
      });
    } catch (e) {
      print('❌ Error creando margen comercial: $e');
      rethrow;
    }
  }

  /// Desactivar margen comercial (establecer fecha_hasta)
  Future<void> deactivateProfitMargin(int id) async {
    try {
      final now = DateTime.now();
      final dateString = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      await _supabase
          .from('app_cont_margen_comercial')
          .update({
            'fecha_hasta': dateString,
          })
          .eq('id', id);
    } catch (e) {
      print('❌ Error desactivando margen comercial: $e');
      rethrow;
    }
  }

  // ==================== VERIFICACIÓN DE CONFIGURACIÓN ====================

  /// Verificar si el sistema está configurado
  Future<bool> isSystemConfigured() async {
    try {
      final storeId = await _getStoreId();
      print('🔍 Verificando configuración para tienda ID: $storeId');
      
      // Verificar si existen configuraciones básicas para la tienda
      final categoriesResponse = await _supabase
          .from('app_nom_categoria_gasto')
          .select('*')
          .count(CountOption.exact);
      
      final costTypesResponse = await _supabase
          .from('app_cont_tipo_costo')
          .select('*')
          .count(CountOption.exact);
      
      final costCentersResponse = await _supabase
          .from('app_cont_centro_costo')
          .select('*')
          .eq('id_tienda', storeId)
          .count(CountOption.exact);
      
      final categoriesCount = categoriesResponse.count ?? 0;
      final costTypesCount = costTypesResponse.count ?? 0;
      final costCentersCount = costCentersResponse.count ?? 0;
      
      print('🔍 Verificación de configuración:');
      print('  - Categorías: $categoriesCount');
      print('  - Tipos de costo: $costTypesCount');
      print('  - Centros de costo (tienda $storeId): $costCentersCount');
      
      // Verificar si hay centros de costo sin filtro de tienda para debugging
      final allCostCentersResponse = await _supabase
          .from('app_cont_centro_costo')
          .select('*')
          .count(CountOption.exact);
      print('  - Total centros de costo (todas las tiendas): ${allCostCentersResponse.count ?? 0}');
      
      // Verificar qué tiendas tienen centros de costo
      final costCentersWithStores = await _supabase
          .from('app_cont_centro_costo')
          .select('id_tienda')
          .limit(10);
      print('  - Tiendas con centros de costo: ${costCentersWithStores.map((c) => c['id_tienda']).toSet()}');
      
      final isConfigured = categoriesCount > 0 && costTypesCount > 0 && costCentersCount > 0;
      print('📊 Sistema configurado: $isConfigured');
      
      return isConfigured;
    } catch (e) {
      print('❌ Error verificando configuración: $e');
      return false;
    }
  }

  /// Obtener estadísticas de configuración
  Future<Map<String, dynamic>> getConfigurationStats() async {
    try {
      final storeId = await _getStoreId();
      print('📊 Obteniendo estadísticas para tienda: $storeId');
      
      // Contar categorías de gastos
      final categoriesResponse = await _supabase
          .from('app_nom_categoria_gasto')
          .select('*')
          .count(CountOption.exact);
      
      final categoriesCount = categoriesResponse.count ?? 0;
      print('  - Categorías: $categoriesCount');
      
      // Contar tipos de costos
      final costTypesResponse = await _supabase
          .from('app_cont_tipo_costo')
          .select('*')
          .count(CountOption.exact);
      final costTypesCount = costTypesResponse.count ?? 0;
      print('  - Tipos de costo: $costTypesCount');
      
      // Contar centros de costo para esta tienda
      final costCentersResponse = await _supabase
          .from('app_cont_centro_costo')
          .select('*')
          .eq('id_tienda', storeId)
          .count(CountOption.exact);
      final costCentersCount = costCentersResponse.count ?? 0;
      print('  - Centros de costo: $costCentersCount');
      
      // Contar márgenes comerciales para esta tienda
      final marginsResponse = await _supabase
          .from('app_cont_margen_comercial')
          .select('*')
          .eq('id_tienda', storeId)
          .count(CountOption.exact);
      final marginsCount = marginsResponse.count ?? 0;
      print('  - Márgenes comerciales: $marginsCount');
      
      // Obtener estadísticas de márgenes (sin usar columnas problemáticas)
      double avgMargin = 0.0;
      double minMargin = 0.0;
      double maxMargin = 0.0;
      
      if (marginsCount > 0) {
        try {
          final marginsData = await _supabase
              .from('app_cont_margen_comercial')
              .select('margen_deseado')
              .eq('id_tienda', storeId)
              .not('margen_deseado', 'is', null);
          
          if (marginsData.isNotEmpty) {
            final margins = marginsData.map((m) => (m['margen_deseado'] as num).toDouble()).toList();
            avgMargin = margins.reduce((a, b) => a + b) / margins.length;
            minMargin = margins.reduce((a, b) => a < b ? a : b);
            maxMargin = margins.reduce((a, b) => a > b ? a : b);
          }
        } catch (e) {
          print('⚠️ Error calculando estadísticas de márgenes: $e');
        }
      }
      
      // Contar asignaciones de costos para esta tienda
      final assignmentsResponse = await _supabase
          .from('app_cont_asignacion_costos')
          .select('*')
          .eq('id_tienda', storeId)
          .count(CountOption.exact);
      final assignmentsCount = assignmentsResponse.count ?? 0;
      print('  - Asignaciones: $assignmentsCount');
      
      final stats = {
        'categories_count': categoriesCount,
        'cost_types_count': costTypesCount,
        'cost_centers_count': costCentersCount,
        'margins_count': marginsCount,
        'avg_margin': avgMargin,
        'min_margin': minMargin,
        'max_margin': maxMargin,
        'assignments_count': assignmentsCount,
      };
      
      print('📈 Estadísticas obtenidas: $stats');
      return stats;
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {
        'categories_count': 0,
        'cost_types_count': 0,
        'cost_centers_count': 0,
        'margins_count': 0,
        'avg_margin': 0.0,
        'min_margin': 0.0,
        'max_margin': 0.0,
        'assignments_count': 0,
      };
    }
  }

  // ==================== CRUD ASIGNACIONES DE COSTOS ====================

  /// Obtener asignaciones de costos
  Future<List<Map<String, dynamic>>> getCostAssignments() async {
    try {
      final storeId = await _getStoreId();
      
      final response = await _supabase
          .from('app_cont_asignacion_costos')
          .select('''
            id, 
            id_tipo_costo, 
            id_producto, 
            id_centro_costo, 
            porcentaje_asignacion, 
            metodo_asignacion, 
            created_at
          ''')
          .eq('id_tienda', storeId)
          .order('created_at', ascending: false);

      // Enriquecer con nombres
      final enrichedResponse = <Map<String, dynamic>>[];
      for (final assignment in response) {
        final enrichedAssignment = Map<String, dynamic>.from(assignment);
        
        // Obtener nombre del tipo de costo
        try {
          final costType = await _supabase
              .from('app_cont_tipo_costo')
              .select('denominacion')
              .eq('id', assignment['id_tipo_costo'])
              .single();
          enrichedAssignment['tipo_costo_nombre'] = costType['denominacion'];
        } catch (e) {
          enrichedAssignment['tipo_costo_nombre'] = 'Tipo ${assignment['id_tipo_costo']}';
        }
        
        // Obtener nombre del centro de costo
        if (assignment['id_centro_costo'] != null) {
          try {
            final costCenter = await _supabase
                .from('app_cont_centro_costo')
                .select('denominacion')
                .eq('id', assignment['id_centro_costo'])
                .single();
            enrichedAssignment['centro_costo_nombre'] = costCenter['denominacion'];
          } catch (e) {
            enrichedAssignment['centro_costo_nombre'] = 'Centro ${assignment['id_centro_costo']}';
          }
        }
        
        // Obtener nombre del producto si existe
        if (assignment['id_producto'] != null) {
          try {
            final product = await _supabase
                .from('app_dat_producto')
                .select('denominacion')
                .eq('id', assignment['id_producto'])
                .single();
            enrichedAssignment['producto_nombre'] = product['denominacion'];
          } catch (e) {
            enrichedAssignment['producto_nombre'] = 'Producto ${assignment['id_producto']}';
          }
        }
        
        enrichedResponse.add(enrichedAssignment);
      }
      
      return enrichedResponse;
    } catch (e) {
      print('Error obteniendo asignaciones de costos: $e');
      throw Exception('Error obteniendo asignaciones de costos: $e');
    }
  }

  /// Crear asignación de costo
  Future<void> createCostAssignment(Map<String, dynamic> assignment) async {
    try {
      final storeId = await _getStoreId();
      
      final newAssignment = {
        ...assignment,
        'id_tienda': storeId,
      };
      
      await _supabase.from('app_cont_asignacion_costos').insert(newAssignment);
    } catch (e) {
      print('Error creando asignación de costo: $e');
      throw Exception('Error creando asignación de costo: $e');
    }
  }

  /// Actualizar asignación de costo
  Future<void> updateCostAssignment(int id, Map<String, dynamic> assignment) async {
    try {
      await _supabase
          .from('app_cont_asignacion_costos')
          .update(assignment)
          .eq('id', id);
    } catch (e) {
      print('Error actualizando asignación de costo: $e');
      throw Exception('Error actualizando asignación de costo: $e');
    }
  }

  /// Eliminar asignación de costo
  Future<void> deleteCostAssignment(int id) async {
    try {
      await _supabase
          .from('app_cont_asignacion_costos')
          .delete()
          .eq('id', id);
    } catch (e) {
      print('Error eliminando asignación de costo: $e');
      throw Exception('Error eliminando asignación de costo: $e');
    }
  }
}
