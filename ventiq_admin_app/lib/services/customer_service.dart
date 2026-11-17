import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer.dart';
import 'user_preferences_service.dart';

class CustomerService {
  static final CustomerService _instance = CustomerService._internal();
  factory CustomerService() => _instance;
  CustomerService._internal();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();

  /// Neto comparable en moneda base (CUP) para una venta según su versión.
  ///
  /// - legacy: `importe_total` (ya es el escalar contable de siempre).
  /// - producto-v1: `importe_total` queda NULL en el alta; el comparable es la
  ///   suma de `importe_neto_cup_equivalente` de sus líneas (equivalentes
  ///   históricos fijados, no reconvertidos con la tasa actual).
  ///
  /// Ambas ramas son la misma magnitud —neto contable CUP— así que pueden
  /// sumarse. Lo que no se hace aquí es sumar nativos de divisas distintas.
  static Future<Map<int, double>> _netoComparableCupPorOperacion(
    List<int> idOperacionesV1,
  ) async {
    if (idOperacionesV1.isEmpty) return const {};
    final rows = await _supabase
        .from('app_dat_extraccion_productos')
        .select('id_operacion, importe_neto_cup_equivalente')
        .inFilter('id_operacion', idOperacionesV1)
        .eq('version_monetaria', 'producto-v1');
    final totales = <int, double>{};
    for (final row in rows) {
      final id = (row['id_operacion'] as num?)?.toInt();
      if (id == null) continue;
      final neto = (row['importe_neto_cup_equivalente'] as num?)?.toDouble();
      totales[id] = (totales[id] ?? 0.0) + (neto ?? 0.0);
    }
    return totales;
  }

  /// Importe comparable CUP de una fila de `app_dat_operacion_venta`.
  /// `idOperacion` es obligatorio para resolver las v1; sin él la v1
  /// devuelve 0 — visible, no silenciosamente "equivalente al legacy".
  static double _netoComparableDeVenta(
    Map<String, dynamic> venta,
    Map<int, double> netosV1,
  ) {
    if (venta['version_monetaria'] == 'producto-v1') {
      final id = (venta['id_operacion'] as num?)?.toInt();
      return id == null ? 0.0 : (netosV1[id] ?? 0.0);
    }
    return (venta['importe_total'] as num?)?.toDouble() ?? 0.0;
  }

  // ==================== CRUD BÁSICO ====================

  /// Obtener todos los clientes de la tienda (basado en ventas)
  static Future<List<Customer>> getAllCustomers({
    bool activeOnly = true,
    bool includeMetrics = false,
  }) async {
    try {
      print('🔍 Obteniendo clientes...');

      // Obtener ID de tienda del usuario actual
      final storeId = await _prefsService.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de tienda del usuario');
      }

      String selectQuery = '''
        c.id, c.codigo_cliente, c.tipo_cliente, c.nombre_completo,
        c.documento_identidad, c.email, c.telefono, c.direccion,
        c.fecha_nacimiento, c.genero, c.puntos_acumulados, c.nivel_fidelidad,
        c.limite_credito, c.fecha_registro, c.ultima_compra, c.total_compras,
        c.frecuencia_compra, c.preferencias, c.notas, c.activo,
        c.acepta_marketing, c.fecha_optin, c.fecha_optout, c.preferencias_comunicacion
      ''';

      if (includeMetrics) {
        selectQuery += '''
          , COUNT(DISTINCT ov.id_operacion) as total_orders,
          AVG(ov.importe_total) as average_order_value
        ''';
      }

      var query = _supabase
          .from('app_dat_clientes')
          .select('''
            $selectQuery,
            app_dat_operacion_venta!inner(
              id_operacion,
              importe_total,
              app_dat_tpv!inner(
                id_tienda
              )
            )
          ''')
          .eq('app_dat_operacion_venta.app_dat_tpv.id_tienda', storeId);

      if (activeOnly) {
        query = query.eq('activo', true);
      }

      final response = await _supabase
          .from('app_dat_clientes')
          .select('*')
          .eq('activo', true)
          .limit(10); // Limitar para testing

      print('✅ Clientes obtenidos: ${response.length}');

      return response.map<Customer>((json) {
        try {
          print('🔍 Cliente raw: $json');
          return Customer.fromJson(json);
        } catch (e) {
          print('❌ Error: $e');
          rethrow;
        }
      }).toList();
    } catch (e) {
      print('❌ Error al obtener clientes: $e');
      return [];
    }
  }

  /// Obtener cliente por ID
  static Future<Customer?> getCustomerById(
    int id, {
    bool includeMetrics = false,
  }) async {
    try {
      print('🔍 Obteniendo cliente ID: $id');

      // Obtener ID de tienda del usuario actual
      final storeId = await _prefsService.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de tienda del usuario');
      }

      // Verificar que el cliente tenga ventas en esta tienda
      final customerExists = await _supabase
          .from('app_dat_operacion_venta')
          .select('id_operacion')
          .eq('id_cliente', id)
          .eq('app_dat_tpv.id_tienda', storeId)
          .limit(1);

      if (customerExists.isEmpty) {
        print('❌ Cliente $id no tiene ventas en tienda $storeId');
        return null;
      }

      String selectQuery = '''
        id, codigo_cliente, tipo_cliente, nombre_completo,
        documento_identidad, email, telefono, direccion,
        fecha_nacimiento, genero, puntos_acumulados, nivel_fidelidad,
        limite_credito, fecha_registro, ultima_compra, total_compras,
        frecuencia_compra, preferencias, notas, activo,
        acepta_marketing, fecha_optin, fecha_optout, preferencias_comunicacion
      ''';

      final response =
          await _supabase
              .from('app_dat_clientes')
              .select(selectQuery)
              .eq('id', id)
              .single();

      if (includeMetrics) {
        // Obtener métricas de ventas
        final metricsResponse = await _supabase
            .from('app_dat_operacion_venta')
            .select(
              'id_operacion, importe_total, version_monetaria, app_dat_tpv!inner(id_tienda)',
            )
            .eq('id_cliente', id)
            .eq('app_dat_tpv.id_tienda', storeId);

        final netosV1 = await _netoComparableCupPorOperacion([
          for (final v in metricsResponse)
            if (v['version_monetaria'] == 'producto-v1')
              (v['id_operacion'] as num).toInt(),
        ]);
        final totalOrders = metricsResponse.length;
        final totalSales = metricsResponse.fold<double>(
          0.0,
          (sum, item) => sum + _netoComparableDeVenta(item, netosV1),
        );
        final averageOrderValue =
            totalOrders > 0 ? totalSales / totalOrders : 0.0;

        response['total_orders'] = totalOrders;
        response['average_order_value'] = averageOrderValue;
        // El ticket medio es neto contable en moneda base (equivalente CUP
        // histórico por línea en ventas v1).
        response['average_order_value_moneda'] = 'CUP';
      }

      print('✅ Cliente obtenido: ${response['nombre_completo']}');
      return Customer.fromJson(response);
    } catch (e) {
      print('❌ Error al obtener cliente $id: $e');
      return null;
    }
  }

  /// Obtener métricas de clientes para dashboard
  static Future<Map<String, dynamic>> getCustomerMetrics() async {
    try {
      print('📊 Obteniendo métricas de clientes...');

      // Obtener ID de tienda del usuario actual
      final storeId = await _prefsService.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de tienda del usuario');
      }

      // Obtener clientes únicos con ventas en esta tienda
      final clientesResponse = await _supabase
          .from('app_dat_operacion_venta')
          .select('''
            id_cliente,
            id_operacion,
            importe_total,
            version_monetaria,
            created_at,
            app_dat_clientes!inner(
              tipo_cliente,
              activo,
              fecha_registro
            ),
            app_dat_tpv!inner(
              id_tienda
            )
          ''')
          .eq('app_dat_tpv.id_tienda', storeId)
          .eq('app_dat_clientes.activo', true);

      // Procesar datos. El importe es neto comparable CUP por versión: las
      // ventas v1 traen `importe_total` NULL y su equivalente vive en las
      // líneas, así que sin el adaptador contaban como ventas de 0.
      final netosV1 = await _netoComparableCupPorOperacion([
        for (final v in clientesResponse)
          if (v['version_monetaria'] == 'producto-v1')
            (v['id_operacion'] as num).toInt(),
      ]);
      final Map<int, Map<String, dynamic>> clientesMap = {};
      double totalSales = 0.0;
      int totalOrders = 0;

      for (final venta in clientesResponse) {
        final clienteId = venta['id_cliente'];
        final importe = _netoComparableDeVenta(venta, netosV1);
        final tipoCliente = venta['app_dat_clientes']['tipo_cliente'];

        totalSales += importe;
        totalOrders++;

        if (!clientesMap.containsKey(clienteId)) {
          clientesMap[clienteId] = {
            'tipo_cliente': tipoCliente,
            'total_compras': 0.0,
            'total_ordenes': 0,
            'fecha_registro': venta['app_dat_clientes']['fecha_registro'],
          };
        }

        clientesMap[clienteId]!['total_compras'] =
            (clientesMap[clienteId]!['total_compras'] ?? 0.0) + importe;
        clientesMap[clienteId]!['total_ordenes'] =
            (clientesMap[clienteId]!['total_ordenes'] ?? 0) + 1;
      }

      // Calcular métricas
      final totalCustomers = clientesMap.length;
      final vipCustomers =
          clientesMap.values.where((c) => c['tipo_cliente'] == 2).length;
      final corporateCustomers =
          clientesMap.values.where((c) => c['tipo_cliente'] == 3).length;
      final averageOrderValue =
          totalOrders > 0 ? totalSales / totalOrders : 0.0;

      // Clientes nuevos (últimos 30 días)
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final newCustomers =
          clientesMap.values
              .where(
                (c) =>
                    DateTime.parse(c['fecha_registro']).isAfter(thirtyDaysAgo),
              )
              .length;

      print('✅ Métricas calculadas: $totalCustomers clientes');

      return {
        'total_customers': totalCustomers,
        'active_customers': totalCustomers, // Todos son activos por el filtro
        'vip_customers': vipCustomers,
        'corporate_customers': corporateCustomers,
        'new_customers_30d': newCustomers,
        'total_sales': totalSales,
        // Las cifras de ventas son neto contable en moneda base: las líneas
        // v1 aportan su equivalente CUP histórico, no su nativo.
        'total_sales_moneda': 'CUP',
        'total_orders': totalOrders,
        'average_order_value': averageOrderValue,
        'customer_retention_rate':
            totalCustomers > 0
                ? ((totalCustomers - newCustomers) / totalCustomers * 100)
                : 0.0,
      };
    } catch (e) {
      print('❌ Error al obtener métricas de clientes: $e');
      rethrow;
    }
  }

  /// Buscar clientes por texto
  static Future<List<Customer>> searchCustomers(String query) async {
    try {
      if (query.trim().isEmpty) {
        return getAllCustomers();
      }

      print('🔍 Buscando clientes: "$query"');

      // Obtener ID de tienda del usuario actual
      final storeId = await _prefsService.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de tienda del usuario');
      }

      final response = await _supabase
          .from('app_dat_clientes')
          .select('''
            id, codigo_cliente, tipo_cliente, nombre_completo,
            documento_identidad, email, telefono, direccion,
            fecha_nacimiento, genero, puntos_acumulados, nivel_fidelidad,
            limite_credito, fecha_registro, ultima_compra, total_compras,
            frecuencia_compra, preferencias, notas, activo,
            acepta_marketing, fecha_optin, fecha_optout, preferencias_comunicacion,
            app_dat_operacion_venta!inner(
              app_dat_tpv!inner(
                id_tienda
              )
            )
          ''')
          .eq('app_dat_operacion_venta.app_dat_tpv.id_tienda', storeId)
          .or(
            'nombre_completo.ilike.%$query%,codigo_cliente.ilike.%$query%,email.ilike.%$query%,telefono.ilike.%$query%',
          )
          .order('nombre_completo');

      print('✅ Clientes encontrados: ${response.length}');

      // Eliminar duplicados
      final Map<int, Map<String, dynamic>> clientesMap = {};
      for (final item in response) {
        clientesMap[item['id']] = item;
      }

      return clientesMap.values
          .map<Customer>((json) => Customer.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error en búsqueda de clientes: $e');
      rethrow;
    }
  }

  /// Obtener top clientes por ventas
  static Future<List<Customer>> getTopCustomers({int limit = 10}) async {
    try {
      print('🏆 Obteniendo top clientes...');

      // Obtener ID de tienda del usuario actual
      final storeId = await _prefsService.getIdTienda();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de tienda del usuario');
      }

      final response = await _supabase
          .from('app_dat_operacion_venta')
          .select('''
            id_cliente,
            id_operacion,
            importe_total,
            version_monetaria,
            app_dat_clientes!inner(
              id, codigo_cliente, tipo_cliente, nombre_completo,
              documento_identidad, email, telefono, direccion,
              fecha_nacimiento, genero, puntos_acumulados, nivel_fidelidad,
              limite_credito, fecha_registro, ultima_compra, total_compras,
              frecuencia_compra, preferencias, notas, activo,
              acepta_marketing, fecha_optin, fecha_optout, preferencias_comunicacion
            ),
            app_dat_tpv!inner(
              id_tienda
            )
          ''')
          .eq('app_dat_tpv.id_tienda', storeId)
          .eq('app_dat_clientes.activo', true);

      // Agrupar por cliente y sumar ventas (neto comparable CUP por versión:
      // las v1 no traen importe_total, su equivalente está en las líneas).
      final netosV1 = await _netoComparableCupPorOperacion([
        for (final v in response)
          if (v['version_monetaria'] == 'producto-v1')
            (v['id_operacion'] as num).toInt(),
      ]);
      final Map<int, Map<String, dynamic>> clientesMap = {};

      for (final venta in response) {
        final clienteId = venta['id_cliente'];
        final importe = _netoComparableDeVenta(venta, netosV1);

        if (!clientesMap.containsKey(clienteId)) {
          clientesMap[clienteId] = Map<String, dynamic>.from(
            venta['app_dat_clientes'],
          );
          clientesMap[clienteId]!['total_sales'] = 0.0;
          clientesMap[clienteId]!['total_orders'] = 0;
        }

        clientesMap[clienteId]!['total_sales'] =
            (clientesMap[clienteId]!['total_sales'] ?? 0.0) + importe;
        clientesMap[clienteId]!['total_orders'] =
            (clientesMap[clienteId]!['total_orders'] ?? 0) + 1;
      }

      // Ordenar por ventas totales y tomar los top
      final topClientes =
          clientesMap.values.toList()..sort(
            (a, b) =>
                (b['total_sales'] ?? 0.0).compareTo(a['total_sales'] ?? 0.0),
          );

      final limitedClientes = topClientes.take(limit).toList();

      // Calcular average_order_value
      for (final cliente in limitedClientes) {
        final totalOrders = cliente['total_orders'] ?? 0;
        final totalSales = cliente['total_sales'] ?? 0.0;
        cliente['average_order_value'] =
            totalOrders > 0 ? totalSales / totalOrders : 0.0;
      }

      print('✅ Top clientes obtenidos: ${limitedClientes.length}');

      return limitedClientes
          .map<Customer>((json) => Customer.fromJson(json))
          .toList();
    } catch (e) {
      print('❌ Error al obtener top clientes: $e');
      rethrow;
    }
  }
}
