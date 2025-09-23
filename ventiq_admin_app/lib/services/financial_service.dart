import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class FinancialService {
  static final FinancialService _instance = FinancialService._internal();
  factory FinancialService() => _instance;
  FinancialService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  // ==================== CONSTANTES DE MÉTODOS DE ASIGNACIÓN ====================
  static const int METODO_AUTOMATICO = 1;
  static const int METODO_MANUAL = 2;
  static const int METODO_PROPORCIONAL = 3;

  // ==================== CATEGORÍAS DE GASTOS ====================

  /// Crear categorías de gastos estándar del sistema
  Future<void> createStandardExpenseCategories() async {
    try {
      final standardCategories = [
        {
          'denominacion': 'Compra de Mercancía',
          'descripcion':
              'Gastos relacionados con la adquisición de productos para la venta',
        },
        {
          'denominacion': 'Gastos Operativos',
          'descripcion':
              'Gastos necesarios para la operación diaria del negocio',
        },
        {
          'denominacion': 'Gastos Administrativos',
          'descripcion':
              'Gastos relacionados con la administración y gestión del negocio',
        },
        {
          'denominacion': 'Servicios Públicos',
          'descripcion': 'Electricidad, agua, gas, internet, teléfono',
        },
        {
          'denominacion': 'Mantenimiento',
          'descripcion':
              'Reparaciones y mantenimiento de equipos e instalaciones',
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
          if (!e.toString().contains('duplicate') &&
              !e.toString().contains('unique')) {
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
      final categoryMap = {
        for (var cat in categories) cat['denominacion']: cat['id'],
      };

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
            await _supabase
                .from('app_nom_subcategoria_gasto')
                .insert(subcategory);
          } catch (e) {
            // Ignorar errores de duplicados
            if (!e.toString().contains('duplicate') &&
                !e.toString().contains('unique')) {
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
  Future<List<Map<String, dynamic>>> getExpenseSubcategories({
    int? categoryId,
  }) async {
    try {
      var query = _supabase.from('app_nom_subcategoria_gasto').select('''
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
        final categorySubcategories =
            subcategories
                .where((sub) => sub['id_categoria_gasto'] == categoryId)
                .toList();

        hierarchy.add({
          'id': 'cat_$categoryId',
          'type': 'category',
          'category_id': categoryId,
          'name': category['denominacion'],
          'description': category['descripcion'],
          'children':
              categorySubcategories
                  .map(
                    (sub) => {
                      'id': 'sub_${sub['id']}',
                      'type': 'subcategory',
                      'subcategory_id': sub['id'],
                      'category_id': categoryId,
                      'name': sub['denominacion'],
                      'description': sub['descripcion'],
                    },
                  )
                  .toList(),
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
      print('🚀 Iniciando búsqueda de operaciones pendientes...');
      print('📅 Rango de fechas: $startDate a $endDate');
      print('🏷️ Categorías filtro: $categoryIds');

      final storeId = await _getStoreId();
      print('🏪 ID de tienda obtenido: $storeId');

      final pendingOperations = <Map<String, dynamic>>[];

      // 1. Obtener recepciones de inventario pendientes
      print('📦 Buscando recepciones pendientes...');
      final receptions = await _getPendingReceptions(
        storeId,
        startDate,
        endDate,
      );
      print('📦 Recepciones encontradas: ${receptions.length}');
      pendingOperations.addAll(receptions);

      // 2. Obtener entregas parciales de caja pendientes
      print('💰 Buscando entregas de efectivo pendientes...');
      final cashWithdrawals = await _getPendingCashWithdrawals(
        storeId,
        startDate,
        endDate,
      );
      print('💰 Entregas de efectivo encontradas: ${cashWithdrawals.length}');
      pendingOperations.addAll(cashWithdrawals);

      print(
        '📊 Total operaciones antes de filtros: ${pendingOperations.length}',
      );

      // Filtrar por categorías si se especifican
      if (categoryIds != null && categoryIds.isNotEmpty) {
        final filteredOps =
            pendingOperations
                .where(
                  (op) => categoryIds.contains(
                    op['id_subcategoria_gasto']?.toString(),
                  ),
                )
                .toList();
        print(
          '🔍 Operaciones después de filtro por categoría: ${filteredOps.length}',
        );

        // Ordenar por fecha descendente
        filteredOps.sort(
          (a, b) => (b['fecha_operacion'] ?? '').compareTo(
            a['fecha_operacion'] ?? '',
          ),
        );

        print('✅ Retornando ${filteredOps.length} operaciones filtradas');
        return filteredOps;
      }

      // Ordenar por fecha descendente
      pendingOperations.sort(
        (a, b) =>
            (b['fecha_operacion'] ?? '').compareTo(a['fecha_operacion'] ?? ''),
      );

      print(
        '✅ Retornando ${pendingOperations.length} operaciones pendientes totales',
      );

      // Mostrar muestra de las operaciones encontradas
      if (pendingOperations.isNotEmpty) {
        print('🔍 Muestra de operaciones pendientes:');
        for (int i = 0; i < pendingOperations.length && i < 3; i++) {
          final op = pendingOperations[i];
          print(
            '  - ${op['tipo_operacion']}: \$${op['monto']} - ${op['descripcion']}',
          );
        }
      }

      return pendingOperations;
    } catch (e) {
      print('❌ Error obteniendo operaciones pendientes: $e');
      return [];
    }
  }

  /// Obtener el conteo de operaciones pendientes de registrar como gastos
  Future<int> getPendingOperationsCount({
    String? startDate,
    String? endDate,
    List<String>? categoryIds,
  }) async {
    try {
      final pendingOperations = await getPendingExpenseOperations(
        startDate: startDate,
        endDate: endDate,
        categoryIds: categoryIds,
      );
      return pendingOperations.length;
    } catch (e) {
      print('❌ Error obteniendo conteo de operaciones pendientes: $e');
      return 0;
    }
  }

  /// Obtener recepciones de inventario pendientes de registrar como gastos
  Future<List<Map<String, dynamic>>> _getPendingReceptions(
    int storeId,
    String? startDate,
    String? endDate,
  ) async {
    try {
      // Obtener recepciones que no han sido registradas como gastos
      var query = _supabase
          .from('app_dat_operaciones')
          .select('''
            id,
            created_at,
            app_dat_operacion_recepcion!inner (
              id_operacion,
              entregado_por,
              recibido_por,
              observaciones,
              monto_total,
              motivo
            ),
            app_dat_recepcion_productos (
              id,
              id_producto,
              cantidad,
              precio_unitario,
              precio_referencia,
              descuento_porcentaje,
              descuento_monto,
              bonificacion_cantidad,
              costo_real,
              app_dat_producto!inner (
                denominacion,
                sku
              )
            )
          ''')
          .eq('id_tienda', storeId)
          .eq('id_tipo_operacion', 1) // Tipo operación recepción
          .eq(
            'app_dat_operacion_recepcion.motivo',
            1,
          ); // Solo recepciones por compra

      // Apply date filters if provided
      if (startDate != null) {
        query = query.gte('created_at', startDate);
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate);
      }

      // Execute the query
      final response = await query.order('created_at', ascending: false);

      // Filtrar recepciones que ya no tienen gastos registrados
      final pendingReceptions = <Map<String, dynamic>>[];

      for (final reception in response) {
        // Verificar si ya existe un gasto registrado para esta recepción
        final existingExpense =
            await _supabase
                .from('app_cont_gastos')
                .select('id')
                .eq('tipo_origen', 'operacion_recepcion')
                .eq('id_referencia_origen', reception['id'])
                .maybeSingle();

        if (existingExpense == null) {
          // Esta recepción no tiene gasto registrado, agregarla a pendientes
          final products =
              reception['app_dat_recepcion_productos'] as List<dynamic>? ?? [];
          final productNames = products
              .map(
                (p) =>
                    (p
                        as Map<
                          String,
                          dynamic
                        >?)?['app_dat_producto']?['denominacion'] ??
                    'Producto',
              )
              .take(3)
              .join(', ');

          final receptionData =
              reception['app_dat_operacion_recepcion'] as Map<String, dynamic>?;
          double computedTotal = 0.0;
          for (final pRaw in products) {
            final p = (pRaw as Map<String, dynamic>?) ?? const {};
            final cantidad = (p['cantidad'] as num?)?.toDouble() ?? 0.0;
            final costoReal = (p['costo_real'] as num?)?.toDouble() ?? 0.0;
            computedTotal += costoReal * cantidad;
          }
          final totalAmount =
              (receptionData?['monto_total'] as num?)?.toDouble() ??
              computedTotal;
          final entregadoPor =
              receptionData?['entregado_por'] ?? 'Sin proveedor';

          pendingReceptions.add({
            'id': reception['id'],
            'tipo_operacion': 'recepcion',
            'descripcion':
                'Recepción por Compra: $productNames${products.length > 3 ? '...' : ''}',
            'monto': totalAmount.toDouble(),
            'fecha_operacion':
                reception['created_at']?.toString().split('T')[0] ?? '',
            'proveedor': entregadoPor,
            'motivo': 'Compra',
            'observaciones': receptionData?['observaciones'] ?? '',
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
    String? endDate,
  ) async {
    try {
      print('🔍 Buscando entregas parciales de caja para tienda: $storeId');
      print('📅 Rango de fechas: $startDate a $endDate');

      // Obtener entregas de efectivo que no han sido registradas como gastos
      // Filtrar por tienda usando la relación: caja_turno -> tpv -> tienda
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
              id,
              id_tpv,
              id_vendedor,
              app_dat_tpv!inner(
                id,
                id_tienda
              ),
              app_dat_vendedor(
                id,
                id_trabajador,
                app_dat_trabajadores(
                  nombres,
                  apellidos
                )
              )
            )
          ''')
          .eq('app_dat_caja_turno.app_dat_tpv.id_tienda', storeId);

      if (startDate != null) {
        query = query.gte('fecha_entrega', startDate);
      }
      if (endDate != null) {
        query = query.lte('fecha_entrega', endDate);
      }

      var response = await query.order('fecha_entrega', ascending: false);
      print(
        '📋 Encontradas ${response.length} entregas parciales para tienda $storeId',
      );

      if (response.isNotEmpty) {
        print('🔍 Muestra de datos recibidos:');
        for (int i = 0; i < response.length && i < 3; i++) {
          final item = response[i];
          print(
            '  - Entrega ${item['id']}: \$${item['monto_entrega']} - ${item['motivo_entrega']}',
          );
          print(
            '    Turno: ${item['id_turno']}, Fecha: ${item['fecha_entrega']}',
          );
        }
      }

      // Filtrar entregas que ya no tienen gastos registrados
      final pendingWithdrawals = <Map<String, dynamic>>[];
      int processedCount = 0;
      int skippedExisting = 0;
      int skippedRejected = 0;

      for (final withdrawal in response) {
        processedCount++;

        // Verificar si ya existe un gasto registrado para esta entrega
        final existingExpense =
            await _supabase
                .from('app_cont_gastos')
                .select('id')
                .eq('tipo_origen', 'egreso_efectivo')
                .eq('id_referencia_origen', withdrawal['id'])
                .maybeSingle();

        if (existingExpense != null) {
          skippedExisting++;
          print('⏭️ Entrega ${withdrawal['id']} ya tiene gasto registrado');
          continue;
        }

        // También verificar si el egreso fue rechazado
        Map<String, dynamic>? rejectedWithdrawal;
        try {
          rejectedWithdrawal =
              await _supabase
                  .from('app_cont_egresos_procesados')
                  .select('id')
                  .eq('id_egreso', withdrawal['id'])
                  .eq('estado', 'rechazado')
                  .maybeSingle();
        } catch (e) {
          print('⚠️ Tabla app_cont_egresos_procesados no existe o error: $e');
          rejectedWithdrawal = null;
        }

        if (rejectedWithdrawal != null) {
          skippedRejected++;
          print('⏭️ Entrega ${withdrawal['id']} fue rechazada previamente');
          continue;
        }

        // Esta entrega no tiene gasto registrado, agregarla a pendientes
        final amount = withdrawal['monto_entrega'] as num? ?? 0.0;
        final motivo = withdrawal['motivo_entrega'] ?? 'Entrega de efectivo';
        final nombreRecibe = withdrawal['nombre_recibe'] ?? 'Sin especificar';
        final nombreAutoriza =
            withdrawal['nombre_autoriza'] ?? 'Sin especificar';

        // Obtener información del trabajador desde la relación vendedor -> trabajador
        String vendedorName = 'Vendedor desconocido';
        try {
          final turnoData =
              withdrawal['app_dat_caja_turno'] as Map<String, dynamic>?;
          if (turnoData != null) {
            final vendedorData =
                turnoData['app_dat_vendedor'] as Map<String, dynamic>?;
            if (vendedorData != null) {
              final trabajadorData =
                  vendedorData['app_dat_trabajadores'] as Map<String, dynamic>?;
              if (trabajadorData != null) {
                final nombres = trabajadorData['nombres'] ?? '';
                final apellidos = trabajadorData['apellidos'] ?? '';
                vendedorName = '$nombres $apellidos'.trim();
                if (vendedorName.isEmpty) {
                  vendedorName = 'Vendedor desconocido';
                }
              }
            }
          }
        } catch (e) {
          print('⚠️ Error obteniendo información del trabajador: $e');
        }

        final pendingOperation = {
          'id': withdrawal['id'],
          'tipo_operacion': 'entrega_efectivo',
          'descripcion': 'Entrega de efectivo: $motivo',
          'monto': amount.toDouble(),
          'fecha_operacion':
              withdrawal['fecha_entrega']?.toString().split('T')[0] ?? '',
          'usuario': vendedorName,
          'motivo': motivo,
          'nombre_recibe': nombreRecibe,
          'nombre_autoriza': nombreAutoriza,
          'observaciones': 'Recibe: $nombreRecibe, Autoriza: $nombreAutoriza',
          'id_subcategoria_gasto': 2, // Gastos Operativos por defecto
          'id_centro_costo': 1, // Centro de costo por defecto
          'original_data': withdrawal,
        };

        pendingWithdrawals.add(pendingOperation);
        print(
          '✅ Agregada entrega pendiente ${withdrawal['id']}: \$${amount} - $vendedorName',
        );
      }

      print('📊 Resumen de procesamiento:');
      print('  - Total entregas encontradas: ${response.length}');
      print('  - Procesadas: $processedCount');
      print('  - Omitidas (ya tienen gasto): $skippedExisting');
      print('  - Omitidas (rechazadas): $skippedRejected');
      print('  - Pendientes finales: ${pendingWithdrawals.length}');

      return pendingWithdrawals;
    } catch (e) {
      print('❌ Error obteniendo entregas de efectivo pendientes: $e');
      return [];
    }
  }

  /// Marcar operación como procesada
  Future<void> _markOperationAsProcessed(Map<String, dynamic> operation) async {
    try {
      // Crear registro en tabla de control de operaciones procesadas
      await _supabase.from('app_cont_operacion_gasto').insert({
        'id_operacion': operation['id'],
        'tipo_operacion': _truncateString(
          operation['tipo_operacion'] ?? '',
          20,
        ), // Truncar para evitar violación
        'fecha_procesado': DateTime.now().toIso8601String(),
        'procesado': true,
      });
    } catch (e) {
      // No es crítico si falla, solo para auditoría
      print('⚠️ No se pudo marcar operación como procesada: $e');
    }
  }

  /// Omitir registro de gasto para una operación
  Future<bool> skipExpenseFromOperation(
    Map<String, dynamic> operation,
    String reason,
  ) async {
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

  /// Eliminar gasto
  Future<bool> deleteExpense(int expenseId) async {
    try {
      await _supabase.from('app_cont_gastos').delete().eq('id', expenseId);

      print('✅ Gasto eliminado exitosamente');
      return true;
    } catch (e) {
      print('❌ Error eliminando gasto: $e');
      return false;
    }
  }

  /// Actualizar gasto
  Future<bool> updateExpense(
    int expenseId,
    Map<String, dynamic> updates,
  ) async {
    try {
      await _supabase
          .from('app_cont_gastos')
          .update(updates)
          .eq('id', expenseId);

      print('✅ Gasto actualizado exitosamente');
      return true;
    } catch (e) {
      print('❌ Error actualizando gasto: $e');
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
          'descripcion':
              'Costos directamente relacionados con la producción o venta',
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
          if (!e.toString().contains('duplicate') &&
              !e.toString().contains('unique')) {
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
            created_at
          ''')
          .order('denominacion');

      print('✅ Tipos de costo cargados: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo tipos de costo: $e');
      return [];
    }
  }

  /// Crear nuevo tipo de costo
  Future<void> createCostType(
    String name,
    String description, {
    int naturaleza = 1,
    bool afectaMargen = true,
  }) async {
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
  Future<void> updateCostType(
    int id,
    String name,
    String description, {
    int? naturaleza,
    bool? afectaMargen,
  }) async {
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
      final storeResponse =
          await _supabase
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
          if (!e.toString().contains('duplicate') &&
              !e.toString().contains('unique')) {
            rethrow;
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
      final fecha_hasta = null;
      // Obtener productos de la tienda
      final products = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion')
          .eq('id_tienda', storeId);

      for (final product in products) {
        // Obtener precios activos para este producto
        final precios = await _supabase
            .from('app_dat_precio_venta')
            .select(
              'id, precio_venta_cup, id_variante, fecha_desde, fecha_hasta',
            )
            .eq('id_producto', product['id'])
            .eq('fecha_hasta', fecha_hasta)
            .lte('fecha_desde', DateTime.now().toIso8601String().split('T')[0]);

        for (final precio in precios) {
          // Verificar si ya existe un margen definido para esta variante
          final existingMargin =
              await _supabase
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
              if (!e.toString().contains('duplicate') &&
                  !e.toString().contains('unique')) {
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
  Future<List<Map<String, dynamic>>> getProfitMargins({
    int? productId,
    int? storeId,
  }) async {
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
          final product =
              await _supabase
                  .from('app_dat_producto')
                  .select('denominacion')
                  .eq('id', margin['id_producto'])
                  .single();
          enrichedMargin['producto_nombre'] = product['denominacion'];
        } catch (e) {
          enrichedMargin['producto_nombre'] =
              'Producto ${margin['id_producto']}';
        }

        // Obtener nombre de variante si existe
        if (margin['id_variante'] != null) {
          try {
            final variant =
                await _supabase
                    .from('app_dat_variantes')
                    .select('denominacion')
                    .eq('id', margin['id_variante'])
                    .single();
            enrichedMargin['variante_nombre'] = variant['denominacion'];
          } catch (e) {
            enrichedMargin['variante_nombre'] =
                'Variante ${margin['id_variante']}';
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
          .update({
            'fecha_hasta': DateTime.now().toIso8601String().split('T')[0],
          })
          .eq('id_producto', productId)
          .eq('id_tienda', storeId);

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
      await _supabase.from('app_cont_margen_comercial').delete().eq('id', id);
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
          if (!e.toString().contains('duplicate') &&
              !e.toString().contains('unique')) {
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
      // Crear tipos de costos si no existen
      await createStandardCostTypes();
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
  Future<void> updateExpenseCategory(
    int id,
    String name,
    String description,
  ) async {
    try {
      await _supabase
          .from('app_nom_categoria_gasto')
          .update({'denominacion': name, 'descripcion': description})
          .eq('id', id);
    } catch (e) {
      print('❌ Error actualizando categoría: $e');
      rethrow;
    }
  }

  /// Eliminar categoría de gastos
  Future<void> deleteExpenseCategory(int id) async {
    try {
      await _supabase.from('app_nom_categoria_gasto').delete().eq('id', id);
    } catch (e) {
      print('❌ Error eliminando categoría: $e');
      rethrow;
    }
  }

  /// Crear nueva subcategoría de gastos
  Future<void> createExpenseSubcategory(
    String name,
    String description,
    int categoryId,
  ) async {
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
  Future<void> updateExpenseSubcategory(
    int id,
    String name,
    String description,
    int categoryId,
  ) async {
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
      await _supabase.from('app_nom_subcategoria_gasto').delete().eq('id', id);
    } catch (e) {
      print('❌ Error eliminando subcategoría: $e');
      rethrow;
    }
  }

  // ==================== CRUD CENTROS DE COSTO ====================

  /// Crear nuevo centro de costo
  Future<void> createCostCenter(
    String name,
    String? description,
    String? code,
    String? skuCode,
    int? parentId,
  ) async {
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
  Future<void> updateCostCenter(
    int id,
    String name,
    String? description,
    String? code,
    String? skuCode,
    int? parentId,
  ) async {
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
      await _supabase.from('app_cont_centro_costo').delete().eq('id', id);
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
      final dateString =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      await _supabase
          .from('app_cont_margen_comercial')
          .update({'fecha_hasta': dateString})
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

      // Verificar qué tiendas tienen centros de costo
      final costCentersWithStores = await _supabase
          .from('app_cont_centro_costo')
          .select('id_tienda')
          .limit(10);
      print(
        '  - Tiendas con centros de costo: ${costCentersWithStores.map((c) => c['id_tienda']).toSet()}',
      );

      final isConfigured =
          categoriesCount > 0 && costTypesCount > 0 && costCentersCount > 0;
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
              .not('margen_deseado', 'eq', null);

          if (marginsData.isNotEmpty) {
            final margins =
                marginsData
                    .map((m) => (m['margen_deseado'] as num).toDouble())
                    .toList();
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
            id_tienda,
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
          final costType =
              await _supabase
                  .from('app_cont_tipo_costo')
                  .select('denominacion')
                  .eq('id', assignment['id_tipo_costo'])
                  .single();
          enrichedAssignment['tipo_costo_nombre'] = costType['denominacion'];
        } catch (e) {
          enrichedAssignment['tipo_costo_nombre'] =
              'Tipo ${assignment['id_tipo_costo']}';
        }

        // Obtener nombre del centro de costo
        if (assignment['id_centro_costo'] != null) {
          try {
            final costCenter =
                await _supabase
                    .from('app_cont_centro_costo')
                    .select('denominacion')
                    .eq('id', assignment['id_centro_costo'])
                    .single();
            enrichedAssignment['centro_costo_nombre'] =
                costCenter['denominacion'];
          } catch (e) {
            enrichedAssignment['centro_costo_nombre'] =
                'Centro ${assignment['id_centro_costo']}';
          }
        } else {
          enrichedAssignment['centro_costo_nombre'] = 'Sin centro de costo';
        }

        // Obtener nombre del producto si existe
        if (assignment['id_producto'] != null) {
          try {
            final product =
                await _supabase
                    .from('app_dat_producto')
                    .select('denominacion')
                    .eq('id', assignment['id_producto'])
                    .single();
            enrichedAssignment['producto_nombre'] = product['denominacion'];
          } catch (e) {
            enrichedAssignment['producto_nombre'] =
                'Producto ${assignment['id_producto']}';
          }
        } else {
          enrichedAssignment['producto_nombre'] = 'Todos los productos';
        }

        enrichedAssignment['metodo_asignacion_nombre'] =
            _getAssignmentMethodName(assignment['metodo_asignacion']);

        enrichedResponse.add(enrichedAssignment);
      }

      return enrichedResponse;
    } catch (e) {
      print('Error obteniendo asignaciones de costos: $e');
      throw Exception('Error obteniendo asignaciones de costos: $e');
    }
  }

  /// Crear asignación de costo
  Future<bool> createCostAssignment(Map<String, dynamic> assignment) async {
    try {
      // Validar datos
      _validateCostAssignment(assignment);

      final storeId = await _getStoreId();

      final newAssignment = {
        'id_tipo_costo': assignment['id_tipo_costo'],
        'id_producto': assignment['id_producto'],
        'id_tienda': storeId,
        'id_centro_costo': assignment['id_centro_costo'],
        'porcentaje_asignacion': assignment['porcentaje_asignacion'],
        'metodo_asignacion': assignment['metodo_asignacion'], // smallint
      };

      await _supabase.from('app_cont_asignacion_costos').insert(newAssignment);
      print('✅ Asignación de costo creada exitosamente');
      return true;
    } catch (e) {
      print('Error creando asignación de costo: $e');
      return false;
    }
  }

  /// Actualizar asignación de costo
  Future<bool> updateCostAssignment(
    int id,
    Map<String, dynamic> assignment,
  ) async {
    try {
      // Validar datos
      _validateCostAssignment(assignment);

      final updateData = {
        'id_tipo_costo': assignment['id_tipo_costo'],
        'id_producto': assignment['id_producto'],
        'id_centro_costo': assignment['id_centro_costo'],
        'porcentaje_asignacion': assignment['porcentaje_asignacion'],
        'metodo_asignacion': assignment['metodo_asignacion'], // smallint
      };

      await _supabase
          .from('app_cont_asignacion_costos')
          .update(updateData)
          .eq('id', id);

      print('✅ Asignación de costo actualizada exitosamente');
      return true;
    } catch (e) {
      print('Error actualizando asignación de costo: $e');
      return false;
    }
  }

  /// Eliminar asignación de costo
  Future<bool> deleteCostAssignment(int id) async {
    try {
      await _supabase.from('app_cont_asignacion_costos').delete().eq('id', id);
      print('✅ Asignación de costo eliminada exitosamente');
      return true;
    } catch (e) {
      print('Error eliminando asignación de costo: $e');
      return false;
    }
  }

  /// Obtener asignaciones de costo por producto
  Future<List<Map<String, dynamic>>> getCostAssignmentsByProduct(
    int productId,
  ) async {
    try {
      final storeId = await _getStoreId();

      final response = await _supabase
          .from('app_cont_asignacion_costos')
          .select('''
            id, 
            id_tipo_costo, 
            id_producto, 
            id_tienda,
            id_centro_costo, 
            porcentaje_asignacion, 
            metodo_asignacion, 
            created_at,
            app_cont_tipo_costo!inner(denominacion),
            app_cont_centro_costo(denominacion)
          ''')
          .eq('id_producto', productId)
          .eq('id_tienda', storeId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo asignaciones por producto: $e');
      return [];
    }
  }

  /// Obtener asignaciones de costo por centro de costo
  Future<List<Map<String, dynamic>>> getCostAssignmentsByCostCenter(
    int costCenterId,
  ) async {
    try {
      final storeId = await _getStoreId();

      final response = await _supabase
          .from('app_cont_asignacion_costos')
          .select('''
            id, 
            id_tipo_costo, 
            id_producto, 
            id_tienda,
            id_centro_costo, 
            porcentaje_asignacion, 
            metodo_asignacion, 
            created_at,
            app_cont_tipo_costo!inner(denominacion),
            app_dat_producto(denominacion)
          ''')
          .eq('id_centro_costo', costCenterId)
          .eq('id_tienda', storeId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo asignaciones por centro de costo: $e');
      return [];
    }
  }

  /// Obtener gastos por período con información completa
  Future<List<Map<String, dynamic>>> getExpensesByPeriod({
    required int storeId,
    String? startDate,
    String? endDate,
    List<String>? categoryIds,
  }) async {
    try {
      var query = _supabase
          .from('app_cont_gastos')
          .select('''
            *,
            app_nom_subcategoria_gasto!inner(denominacion),
            app_cont_centro_costo!inner(denominacion),
            app_cont_tipo_costo!inner(denominacion)
          ''')
          .eq('id_tienda', storeId);

      if (startDate != null) query = query.gte('fecha', startDate);
      if (endDate != null) query = query.lte('fecha', endDate);
      if (categoryIds != null && categoryIds.isNotEmpty) {
        query = query.inFilter('id_subcategoria_gasto', categoryIds);
      }

      final response = await query.order('fecha', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo gastos: $e');
      return [];
    }
  }

  // ==================== HISTORIAL DE ACTIVIDADES ====================

  /// Registrar actividad en el historial
  Future<void> _logActivity({
    required String tipoActividad,
    required String descripcion,
    required String entidadTipo,
    int? entidadId,
    double? monto,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final storeId = await _getStoreId();
      final userId = await _getUserId();

      await _supabase.from('app_cont_historial_actividades').insert({
        'tipo_actividad': tipoActividad,
        'descripcion': descripcion,
        'entidad_tipo': entidadTipo,
        'entidad_id': entidadId,
        'monto': monto,
        'usuario_id': userId,
        'id_tienda': storeId,
        'metadata': metadata,
      });
    } catch (e) {
      print('❌ Error registrando actividad: $e');
    }
  }

  /// Obtener actividades recientes
  Future<List<Map<String, dynamic>>> getRecentActivities({
    int limit = 10,
  }) async {
    try {
      final storeId = await _getStoreId();

      final response = await _supabase
          .from('app_cont_historial_actividades')
          .select('*')
          .eq('id_tienda', storeId)
          .order('fecha_actividad', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo actividades recientes: $e');
      return [];
    }
  }

  /// Obtener historial de actividades con paginación y filtros
  Future<Map<String, dynamic>> getActivityHistory({
    int page = 1,
    int limit = 20,
    String? tipoActividad,
  }) async {
    try {
      final storeId = await _getStoreId();
      final offset = (page - 1) * limit;

      var query = _supabase
          .from('app_cont_historial_actividades')
          .select('*')
          .eq('id_tienda', storeId);

      // Aplicar filtro por tipo de actividad si se especifica
      if (tipoActividad != null && tipoActividad != 'all') {
        query = query.eq('tipo_actividad', tipoActividad);
      }

      // Obtener actividades con paginación
      final response = await _supabase
          .from('app_cont_historial_actividades')
          .select('*')
          .eq('id_tienda', storeId)
          .order('fecha_actividad', ascending: false)
          .range(offset, offset + limit - 1);

      final activities = List<Map<String, dynamic>>.from(response);

      // Verificar si hay más actividades
      final nextPageResponse = await _supabase
          .from('app_cont_historial_actividades')
          .select('id')
          .eq('id_tienda', storeId)
          .range(offset + limit, offset + limit);

      final hasMore = nextPageResponse.isNotEmpty;

      return {
        'data': activities,
        'hasMore': hasMore,
        'page': page,
        'limit': limit,
      };
    } catch (e) {
      print('❌ Error obteniendo historial de actividades: $e');
      return {
        'data': <Map<String, dynamic>>[],
        'hasMore': false,
        'page': page,
        'limit': limit,
      };
    }
  }

  String _truncateString(String str, int maxLength) {
    if (str.length > maxLength) {
      return str.substring(0, maxLength);
    }
    return str;
  }

  // ==================== ASIGNACIONES DE GASTOS ====================

  /// Obtener asignaciones de gastos específicos
  Future<List<Map<String, dynamic>>> getExpenseAssignments({
    int? expenseId,
  }) async {
    try {
      final storeId = await _getStoreId();

      var query = _supabase
          .from('app_cont_gasto_asignacion')
          .select('''
            id_gasto,
            id_asignacion,
            monto_asignado,
            created_at,
            app_cont_gastos!inner(monto, fecha, id_tienda),
            app_cont_asignacion_costos!inner(
              id,
              porcentaje_asignacion,
              metodo_asignacion,
              app_cont_tipo_costo!inner(denominacion),
              app_cont_centro_costo!inner(denominacion)
            )
          ''')
          .eq('app_cont_gastos.id_tienda', storeId);

      if (expenseId != null) {
        query = query.eq('id_gasto', expenseId);
      }

      final response = await query.order('created_at', ascending: false);

      print('✅ Asignaciones de gastos cargadas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo asignaciones de gastos: $e');
      return [];
    }
  }

  /// Crear asignación de gasto
  Future<bool> createExpenseAssignment({
    required int expenseId,
    required int assignmentId,
    required double assignedAmount,
  }) async {
    try {
      await _supabase.from('app_cont_gasto_asignacion').insert({
        'id_gasto': expenseId,
        'id_asignacion': assignmentId,
        'monto_asignado': assignedAmount,
      });

      print('✅ Asignación de gasto creada exitosamente');
      return true;
    } catch (e) {
      print('❌ Error creando asignación de gasto: $e');
      return false;
    }
  }

  /// Registrar gasto desde operación pendiente
  Future<bool> registerExpenseFromOperation(
    Map<String, dynamic> operation, {
    int? subcategoryId,
    int? costCenterId,
    int? costTypeId,
    String? customDescription,
  }) async {
    try {
      final storeId = await _getStoreId();
      final userId = await _getUserId();

      final expenseData = {
        'monto': operation['monto'],
        'fecha':
            operation['fecha_operacion'] ??
            DateTime.now().toIso8601String().split('T')[0],
        'id_subcategoria_gasto':
            subcategoryId ?? operation['id_subcategoria_gasto'] ?? 1,
        'id_centro_costo': costCenterId ?? operation['id_centro_costo'] ?? 1,
        'id_tipo_costo': costTypeId ?? operation['id_tipo_costo'] ?? 1,
        'id_tienda': storeId,
        'uuid': userId,
        'tipo_origen': _truncateString(
          operation['tipo_operacion'] ?? 'recepcion',
          20,
        ),
        'id_referencia_origen': operation['id_referencia'] ?? operation['id'],
      };

      // SOLUCIÓN AL PROBLEMA DE AUDITORÍA: Obtener ID de asignación antes de insertar
      final assignmentId = await _ensureCostAssignmentExists(
        expenseData['id_tipo_costo'],
        expenseData['id_centro_costo'],
        storeId,
      );

      if (assignmentId == null) {
        throw Exception(
          'No se pudo crear o encontrar asignación de costos para el trigger de auditoría',
        );
      }

      print('✅ ID de asignación obtenido para auditoría: $assignmentId');

      // Insertar gasto - el trigger ahora debería encontrar la asignación correcta
      final insertResult =
          await _supabase
              .from('app_cont_gastos')
              .insert(expenseData)
              .select('id')
              .single();
      final expenseId = insertResult['id'] as int;
      print('✅ Gasto insertado exitosamente con ID: $expenseId');

      // CREAR RELACIÓN EXPLÍCITA GASTO-ASIGNACIÓN
      try {
        await _supabase.from('app_cont_gasto_asignacion').insert({
          'id_gasto': expenseId,
          'id_asignacion': assignmentId,
          'monto_asignado':
              double.tryParse(operation['monto'].toString()) ?? 0.0,
        });
        print(
          '✅ Relación gasto-asignación creada: gasto=$expenseId, asignación=$assignmentId',
        );
      } catch (e) {
        print('⚠️ Error creando relación gasto-asignación: $e');
        // No es crítico, continuar
      }

      // Registrar actividad en el historial
      await _logActivity(
        tipoActividad: 'gasto_registrado',
        descripcion:
            'Gasto registrado desde operación: \$${operation['monto']}',
        entidadTipo: 'gasto',
        monto: double.tryParse(operation['monto'].toString()),
        metadata: {
          'origen_operacion': operation['id'],
          'tipo_operacion': operation['tipo_operacion'],
          'assignment_id': assignmentId,
        },
      );

      // Marcar operación como procesada
      await _markOperationAsProcessed(operation);

      return true;
    } catch (e) {
      print('❌ Error registrando gasto desde operación: $e');
      return false;
    }
  }

  /// Obtener logs de auditoría de costos
  Future<List<Map<String, dynamic>>> getCostAuditLogs({
    int? assignmentId,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final storeId = await _getStoreId();

      var query = _supabase
          .from('app_cont_log_costos')
          .select('''
            id,
            id_asignacion,
            accion,
            cambios,
            fecha_operacion,
            realizado_por,
            app_cont_asignacion_costos!inner(
              id,
              porcentaje_asignacion,
              metodo_asignacion,
              app_cont_tipo_costo!inner(denominacion),
              app_cont_centro_costo!inner(denominacion)
            )
          ''')
          .eq('app_cont_asignacion_costos.id_tienda', storeId);

      // Filtrar por asignación específica si se proporciona
      if (assignmentId != null) {
        query = query.eq('id_asignacion', assignmentId);
      }

      // Filtrar por rango de fechas si se proporciona
      if (startDate != null) {
        query = query.gte('fecha_operacion', startDate);
      }
      if (endDate != null) {
        query = query.lte('fecha_operacion', endDate);
      }

      final response = await query.order('fecha_operacion', ascending: false);

      print('✅ Logs de auditoría cargados: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo logs de auditoría: $e');
      return [];
    }
  }

  /// Asegurar que existe una asignación de costos y retornar su ID
  Future<int?> _ensureCostAssignmentExists(
    int costTypeId,
    int costCenterId,
    int storeId, {
    bool forceCreate = false,
  }) async {
    try {
      // Buscar asignaciones existentes
      final existingAssignments = await _supabase
          .from('app_cont_asignacion_costos')
          .select('id, id_producto, porcentaje_asignacion, metodo_asignacion')
          .eq('id_tipo_costo', costTypeId)
          .eq('id_centro_costo', costCenterId)
          .eq('id_tienda', storeId);

      if (existingAssignments.isNotEmpty && !forceCreate) {
        // Buscar asignación general (id_producto = null)
        final generalAssignment = existingAssignments.firstWhere(
          (assignment) => assignment['id_producto'] == null,
          orElse:
              () =>
                  existingAssignments
                      .first, // Usar la primera si no hay general
        );

        print(
          '✅ Asignación existente encontrada: ID ${generalAssignment['id']}',
        );
        return generalAssignment['id'] as int;
      }

      // Crear asignación automática si no existe
      final newAssignment = {
        'id_tipo_costo': costTypeId,
        'id_centro_costo': costCenterId,
        'id_tienda': storeId,
        'id_producto': null,
        'porcentaje_asignacion': 100.0,
        'metodo_asignacion': METODO_AUTOMATICO,
      };

      final result =
          await _supabase
              .from('app_cont_asignacion_costos')
              .insert(newAssignment)
              .select('id')
              .single();

      final assignmentId = result['id'] as int;
      print('✅ Asignación creada automáticamente: ID $assignmentId');
      return assignmentId;
    } catch (e) {
      print('❌ Error asegurando asignación de costos: $e');
      return null;
    }
  }

  /// Calcular asignaciones de costos para un gasto
  Future<List<Map<String, dynamic>>> calculateCostAssignments({
    required double expenseAmount,
    required int costTypeId,
    required int costCenterId,
    int? productId,
  }) async {
    try {
      print(
        '🔍 DEBUGGING: calculateCostAssignments called with costTypeId=$costTypeId, costCenterId=$costCenterId',
      );
      final storeId = await _getStoreId();

      // Obtener asignaciones existentes para este tipo de costo y centro
      final assignments = await _supabase
          .from('app_cont_asignacion_costos')
          .select('''
          id, porcentaje_asignacion, metodo_asignacion,
          id_tipo_costo, id_centro_costo, id_producto, id_tienda
        ''')
          .eq('id_tipo_costo', costTypeId)
          .eq('id_centro_costo', costCenterId)
          .eq('id_tienda', storeId);

      if (assignments.isEmpty) {
        print(
          '⚠️ No se encontraron asignaciones, creando una automáticamente...',
        );

        try {
          // Crear asignación automática
          final newAssignment = {
            'id_tipo_costo': costTypeId,
            'id_centro_costo': costCenterId,
            'id_tienda': storeId,
            'id_producto': null, // Asignación general para todos los productos
            'porcentaje_asignacion': 100.0,
            'metodo_asignacion': METODO_AUTOMATICO,
          };

          final response =
              await _supabase
                  .from('app_cont_asignacion_costos')
                  .insert(newAssignment)
                  .select('id, porcentaje_asignacion, metodo_asignacion')
                  .single();

          print('✅ Asignación automática creada con ID: ${response['id']}');

          // Retornar la nueva asignación
          return [
            {
              'id': response['id'],
              'id_asignacion': response['id'],
              'porcentaje_asignacion': 100.0,
              'monto_asignado': expenseAmount,
              'metodo_asignacion': METODO_AUTOMATICO,
              'created_automatically': true,
            },
          ];
        } catch (e) {
          print('❌ Error creando asignación automática: $e');
          // En caso de error, retornar sin id_asignacion (fallback)
          return [
            {
              'id_asignacion': null,
              'porcentaje_asignacion': 100.0,
              'monto_asignado': expenseAmount,
              'metodo_asignacion': METODO_AUTOMATICO,
              'created_automatically': true,
              'error': 'No se pudo crear asignación automática',
            },
          ];
        }
      }

      // Calcular montos asignados para asignaciones existentes
      return assignments.map((assignment) {
        final percentage =
            (assignment['porcentaje_asignacion'] as num).toDouble();
        return {
          ...assignment,
          'id_asignacion': assignment['id'],
          'monto_asignado': expenseAmount * (percentage / 100),
        };
      }).toList();
    } catch (e) {
      print('❌ Error calculando asignaciones: $e');
      return [];
    }
  }

  /// Validar datos de asignación de costo
  bool _validateCostAssignment(Map<String, dynamic> assignment) {
    // Verificar que al menos uno de los campos requeridos esté presente
    final hasProduct = assignment['id_producto'] != null;
    final hasCostCenter = assignment['id_centro_costo'] != null;

    if (!hasProduct && !hasCostCenter) {
      throw Exception(
        'Debe especificar al menos un producto o centro de costo',
      );
    }

    // Verificar campos obligatorios
    if (assignment['id_tipo_costo'] == null) {
      throw Exception('El tipo de costo es obligatorio');
    }

    if (assignment['porcentaje_asignacion'] == null ||
        assignment['porcentaje_asignacion'] <= 0 ||
        assignment['porcentaje_asignacion'] > 100) {
      throw Exception(
        'El porcentaje de asignación debe estar entre 0.01 y 100',
      );
    }

    if (assignment['metodo_asignacion'] == null ||
        ![
          METODO_AUTOMATICO,
          METODO_MANUAL,
          METODO_PROPORCIONAL,
        ].contains(assignment['metodo_asignacion'])) {
      throw Exception('Método de asignación inválido');
    }

    return true;
  }

  /// Obtener nombre del método de asignación
  String _getAssignmentMethodName(int? metodoAsignacion) {
    switch (metodoAsignacion) {
      case METODO_AUTOMATICO:
        return 'Automático';
      case METODO_MANUAL:
        return 'Manual';
      case METODO_PROPORCIONAL:
        return 'Proporcional';
      default:
        return 'Desconocido';
    }
  }

  /// Obtener el conteo optimizado de operaciones pendientes usando RPC
Future<int> getPendingOperationsCountOptimized({
  String? startDate,
  String? endDate,
}) async {
  try {
    print('🔢 Obteniendo conteo de operaciones pendientes con RPC...');

    final storeId = await _getStoreId();
    final userId = _supabase.auth.currentUser?.id;

    print('📊 Parámetros RPC:');
    print('   - ID Tienda: $storeId');
    print('   - Usuario UUID: $userId');
    print('   - Fecha inicio: $startDate');
    print('   - Fecha fin: $endDate');

    // PRIORIDAD 1: Llamar función RPC optimizada
    final response = await _supabase.rpc(
      'fn_count_pending_operations_optimized',
      params: {
        'p_id_tienda': storeId,
        'p_fecha_inicio': startDate,
        'p_fecha_fin': endDate,
        'p_user_uuid': userId,
      },
    );

    print('📥 Respuesta RPC recibida: $response');

    // Validar respuesta de RPC
    if (response != null) {
      final result = response as Map<String, dynamic>;
      
      print('🔍 Analizando resultado RPC:');
      print('   - Success: ${result['success']}');
      print('   - Error: ${result['error']}');
      print('   - Error Detail: ${result['error_detail']}');
      print('   - Debug Info: ${result['debug_info']}');

      if (result['success'] == true) {
        final totalCount = result['total_count'] as int? ?? 0;
        final recepcionesCount = result['recepciones_count'] as int? ?? 0;
        final entregasCount = result['entregas_count'] as int? ?? 0;

        print('✅ RPC exitosa - Total: $totalCount (Recepciones: $recepcionesCount, Entregas: $entregasCount)');
        return totalCount;
      } else {
        final errorMsg = result['error'] ?? 'Error desconocido';
        final errorDetail = result['error_detail'] ?? '';
        final debugInfo = result['debug_info'] ?? '';
        
        print('⚠️ RPC falló:');
        print('   - Error: $errorMsg');
        print('   - Detalle: $errorDetail');
        print('   - Debug: $debugInfo');
        print('   - SQL State: ${result['error_code']}');
      }
    } else {
      print('⚠️ RPC retornó null - posible error de conexión o permisos');
    }

  } catch (e, stackTrace) {
    print('❌ Error en RPC: $e');
    print('📍 Stack trace: $stackTrace');
    
    // Verificar si es un error específico de Supabase
    if (e.toString().contains('PostgrestException')) {
      print('🔍 Error de PostgreSQL detectado');
    } else if (e.toString().contains('SocketException')) {
      print('🔍 Error de conexión de red detectado');
    } else if (e.toString().contains('TimeoutException')) {
      print('🔍 Error de timeout detectado');
    }
  }

  // PRIORIDAD 2: Fallback simple si RPC falla
  print('🔄 Usando fallback simplificado...');
  return await _getSimplePendingCount();
}

  /// Fallback simplificado para conteo de operaciones pendientes
  Future<int> _getSimplePendingCount() async {
    try {
      final storeId = await _getStoreId();

      // Conteo simple: solo recepciones sin gastos registrados
      final pendingReceptions = await _supabase
          .from('app_dat_operacion_recepcion')
          .select(
            'id_operacion, app_dat_operaciones!inner(id, id_tienda, id_tipo_operacion)',
          )
          .eq('app_dat_operaciones.id_tienda', storeId)
          .eq('app_dat_operaciones.id_tipo_operacion', 1);

      // Obtener gastos ya registrados
      final existingExpenses = await _supabase
          .from('app_cont_gastos')
          .select('id_referencia_origen')
          .inFilter('tipo_origen', ['recepcion', 'operacion_recepcion'])
          .not('id_referencia_origen', 'is', null);

      final existingIds =
          existingExpenses.map((e) => e['id_referencia_origen']).toSet();

      // Filtrar recepciones pendientes
      final pendingCount =
          pendingReceptions
              .where((r) => !existingIds.contains(r['id_operacion']))
              .length;

      print('✅ Fallback completado: $pendingCount operaciones pendientes');
      return pendingCount;
    } catch (e) {
      print('❌ Error en fallback: $e');
      print('✅ Contador de operaciones pendientes cargado: 0 (sin auditoría)');
      return 0;
    }
  }

  /// Obtener detalles del conteo de operaciones pendientes (para debugging)
  Future<Map<String, dynamic>> getPendingOperationsCountDetails({
    String? startDate,
    String? endDate,
  }) async {
    try {
      final storeId = await _getStoreId();
      final userId = _supabase.auth.currentUser?.id;

      final response = await _supabase.rpc(
        'fn_count_pending_operations_optimized',
        params: {
          'p_id_tienda': storeId,
          'p_fecha_inicio': startDate,
          'p_fecha_fin': endDate,
          'p_user_uuid': userId,
        },
      );

      if (response == null || response['success'] != true) {
        return {
          'success': false,
          'error': response?['error'] ?? 'Error desconocido',
          'total_count': 0,
          'recepciones_count': 0,
          'entregas_count': 0,
        };
      }

      return Map<String, dynamic>.from(response);
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'total_count': 0,
        'recepciones_count': 0,
        'entregas_count': 0,
      };
    }
  }

  /// Preview de asignaciones de costos antes de registrar un gasto
  Future<Map<String, dynamic>> previewExpenseAssignments(
    Map<String, dynamic> operation, {
    int? subcategoryId,
    int? costCenterId,
    int? costTypeId,
  }) async {
    try {
      final expenseAmount =
          double.tryParse(operation['monto'].toString()) ?? 0.0;
      final finalCostTypeId = costTypeId ?? operation['id_tipo_costo'] ?? 1;
      final finalCostCenterId =
          costCenterId ?? operation['id_centro_costo'] ?? 1;

      print('🔍 Previewing expense assignments for amount: $expenseAmount');
      print('   - Cost Type ID: $finalCostTypeId');
      print('   - Cost Center ID: $finalCostCenterId');

      // Calcular asignaciones usando el método existente
      final assignments = await calculateCostAssignments(
        expenseAmount: expenseAmount,
        costTypeId: finalCostTypeId,
        costCenterId: finalCostCenterId,
      );

      // Calcular totales
      double totalAssigned = 0.0;
      int automaticAssignments = 0;

      for (final assignment in assignments) {
        totalAssigned += (assignment['monto_asignado'] as num).toDouble();
        if (assignment['created_automatically'] == true) {
          automaticAssignments++;
        }
      }

      final isFullyAssigned =
          (totalAssigned - expenseAmount).abs() <
          0.01; // Tolerancia de 1 centavo

      return {
        'assignments': assignments,
        'summary': {
          'total_expense': expenseAmount,
          'total_assigned': totalAssigned,
          'is_fully_assigned': isFullyAssigned,
          'assignment_count': assignments.length,
          'automatic_assignments': automaticAssignments,
          'coverage_percentage':
              expenseAmount > 0 ? (totalAssigned / expenseAmount * 100) : 0.0,
        },
      };
    } catch (e) {
      print('❌ Error en preview de asignaciones: $e');
      return {
        'assignments': [],
        'summary': {
          'total_expense': 0.0,
          'total_assigned': 0.0,
          'is_fully_assigned': false,
          'assignment_count': 0,
          'automatic_assignments': 0,
          'coverage_percentage': 0.0,
          'error': e.toString(),
        },
      };
    }
  }
}
