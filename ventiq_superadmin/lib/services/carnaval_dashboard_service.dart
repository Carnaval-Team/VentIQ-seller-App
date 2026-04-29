import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/carnaval_dashboard_data.dart';

class CarnavalDashboardService {
  final _supabase = Supabase.instance.client;

  Future<CarnavalDashboardData> loadDashboardData(
    DateTime from,
    DateTime to,
  ) async {
    final fromStr = '${from.toIso8601String().substring(0, 10)}T00:00:00';
    final toStr = '${to.toIso8601String().substring(0, 10)}T23:59:59';

    // Fetch all data in parallel - only needed columns, minimal data
    final results = await Future.wait([
      _fetchUsuariosCounts(fromStr, toStr),    // Only date + count grouped
      _fetchOrders(fromStr, toStr),            // Orders with needed fields
      _fetchProductos(),                        // id, name, proveedor only
      _fetchProveedores(),                      // id, name only
      _fetchOrderDetails(fromStr, toStr),       // For product/provider sales
      _fetchUsuariosTotal(fromStr, toStr),      // Just the count
      _fetchProveedoresTotal(),                 // Just the count
    ]);

    final usuariosPorDiaRaw = results[0] as List<Map<String, dynamic>>;
    final orders = results[1] as List<Map<String, dynamic>>;
    final productos = results[2] as List<Map<String, dynamic>>;
    final proveedoresRaw = results[3] as List<Map<String, dynamic>>;
    final orderDetails = results[4] as List<Map<String, dynamic>>;
    final totalUsuarios = results[5] as int;
    final totalProveedores = results[6] as int;

    // Build lookup maps
    final proveedorNames = <int, String>{
      for (final p in proveedoresRaw)
        p['id'] as int: (p['name'] ?? 'Sin nombre').toString()
    };

    final productoNames = <int, String>{};
    final productoProveedor = <int, int>{};
    for (final p in productos) {
      productoNames[p['id'] as int] = (p['name'] ?? 'Sin nombre').toString();
      if (p['proveedor'] != null) {
        productoProveedor[p['id'] as int] = _toInt(p['proveedor']);
      }
    }

    // 2: Usuarios por día (already grouped from query)
    final usuariosPorDia = usuariosPorDiaRaw
        .map((e) => DateCount(
            DateTime.parse(_extractDate(e['date'])), _toInt(e['count'])))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // 3-6: Orders metrics - single pass
    int totalOrdenes = orders.length;
    int ordenesCompletadas = 0;
    int ordenesCanceladas = 0;
    double dineroRecaudado = 0;
    final metodoPagoGroups = <String, Map<String, int>>{};
    final dineroMetodoGroups = <String, Map<String, double>>{};
    final dineroPorMoneda = <String, double>{};
    final userOrderTotals = <int, double>{};
    final nuevoRevisionGroups = <String, Map<String, int>>{};
    final pendientePagoByDate = <String, int>{};

    for (final o in orders) {
      final status = (o['status'] ?? '').toString();
      final isCompletado = status == 'Completado';
      final isCancelado = status == 'Cancelado';
      final total = _toDouble(o['total']);
      final metodo = (o['metodo_pago'] ?? 'Sin especificar').toString();
      final dateStr = _extractDate(o['created_at']);

      if (isCompletado) {
        ordenesCompletadas++;
        dineroRecaudado += total;

        // 8: Dinero por método de pago
        dineroMetodoGroups.putIfAbsent(metodo, () => {});
        dineroMetodoGroups[metodo]![dateStr] =
            (dineroMetodoGroups[metodo]![dateStr] ?? 0) + total;

        // 9: Dinero por moneda
        final moneda = (o['moneda'] ?? 'CUP').toString();
        double amount;
        if (moneda == 'USD') {
          amount = _toDouble(o['totalUsd']);
        } else if (moneda == 'EUR') {
          amount = _toDouble(o['totalEuro']);
        } else {
          amount = total;
        }
        dineroPorMoneda[moneda] = (dineroPorMoneda[moneda] ?? 0) + amount;
      }
      if (isCancelado) ordenesCanceladas++;

      // Órdenes Nuevo / En Revision por día
      if (status == 'Nuevo' || status == 'En Revision') {
        nuevoRevisionGroups.putIfAbsent(status, () => {});
        nuevoRevisionGroups[status]![dateStr] =
            (nuevoRevisionGroups[status]![dateStr] ?? 0) + 1;
      }
      // Órdenes Pendiente de Pago por día
      if (status == 'Pendiente de Pago') {
        pendientePagoByDate[dateStr] =
            (pendientePagoByDate[dateStr] ?? 0) + 1;
      }

      // 7: Ordenes por método de pago
      metodoPagoGroups.putIfAbsent(metodo, () => {});
      metodoPagoGroups[metodo]![dateStr] =
          (metodoPagoGroups[metodo]![dateStr] ?? 0) + 1;

      // Top compradores accumulation
      final uid = _toInt(o['user_id']);
      if (uid > 0) {
        userOrderTotals[uid] = (userOrderTotals[uid] ?? 0) + total;
      }
    }

    // Convert grouped maps to sorted lists
    final ordenesPorMetodoPago = <String, List<DateCount>>{};
    for (final entry in metodoPagoGroups.entries) {
      final sorted = entry.value.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      ordenesPorMetodoPago[entry.key] =
          sorted.map((e) => DateCount(DateTime.parse(e.key), e.value)).toList();
    }

    final dineroPorMetodoPago = <String, List<DateValue>>{};
    for (final entry in dineroMetodoGroups.entries) {
      final sorted = entry.value.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      dineroPorMetodoPago[entry.key] =
          sorted.map((e) => DateValue(DateTime.parse(e.key), e.value)).toList();
    }

    // 11: Productos por proveedor
    final prodCountByProv = <int, int>{};
    for (final p in productos) {
      final provId = _toInt(p['proveedor']);
      if (provId > 0) {
        prodCountByProv[provId] = (prodCountByProv[provId] ?? 0) + 1;
      }
    }
    final productosPorProveedor = prodCountByProv.entries
        .map((e) => NameCount(proveedorNames[e.key] ?? 'ID ${e.key}', e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    // 12 & 13: Process OrderDetails in single pass
    final vendidosByProv = <int, int>{};
    final prodSales = <int, int>{};
    for (final od in orderDetails) {
      final qty = _toInt(od['quantity'], fallback: 1);
      final provId = _toInt(od['proveedor']);
      final prodId = _toInt(od['product_id']);

      if (provId > 0) {
        vendidosByProv[provId] = (vendidosByProv[provId] ?? 0) + qty;
      }
      if (prodId > 0) {
        prodSales[prodId] = (prodSales[prodId] ?? 0) + qty;
      }
    }

    final productosVendidosPorProveedor = vendidosByProv.entries
        .map((e) => NameCount(proveedorNames[e.key] ?? 'ID ${e.key}', e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    // Top 5 productos
    final top5Productos = (prodSales.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) =>
            NameCount(productoNames[e.key] ?? 'Producto ${e.key}', e.value))
        .toList();

    // Top 5 compradores - get only the 5 user IDs we need
    final sortedBuyers = userOrderTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5BuyerIds = sortedBuyers.take(5).map((e) => e.key).toList();

    // Fetch only those 5 user names
    final userNames = top5BuyerIds.isNotEmpty
        ? await _fetchUserNamesByIds(top5BuyerIds)
        : <int, String>{};

    final top5Compradores = sortedBuyers
        .take(5)
        .map((e) => NameValue(
            userNames[e.key] ?? 'Usuario ${e.key}', e.value))
        .toList();

    // Top 5 proveedores
    final top5Proveedores = (vendidosByProv.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => NameCount(proveedorNames[e.key] ?? 'ID ${e.key}', e.value))
        .toList();

    // Nuevo/En Revision grouped by status
    final ordenesNuevoRevisionPorDia = <String, List<DateCount>>{};
    for (final entry in nuevoRevisionGroups.entries) {
      final sorted = entry.value.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      ordenesNuevoRevisionPorDia[entry.key] =
          sorted.map((e) => DateCount(DateTime.parse(e.key), e.value)).toList();
    }

    // Pendiente de Pago sorted by date
    final sortedPendiente = pendientePagoByDate.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final ordenesPendientePagoPorDia = sortedPendiente
        .map((e) => DateCount(DateTime.parse(e.key), e.value))
        .toList();

    return CarnavalDashboardData(
      totalUsuarios: totalUsuarios,
      usuariosPorDia: usuariosPorDia,
      totalOrdenes: totalOrdenes,
      dineroRecaudado: dineroRecaudado,
      ordenesCompletadas: ordenesCompletadas,
      ordenesCanceladas: ordenesCanceladas,
      ordenesPorMetodoPago: ordenesPorMetodoPago,
      dineroPorMetodoPago: dineroPorMetodoPago,
      dineroPorMoneda: dineroPorMoneda,
      totalProveedores: totalProveedores,
      productosPorProveedor: productosPorProveedor,
      productosVendidosPorProveedor: productosVendidosPorProveedor,
      top5Productos: top5Productos,
      top5Compradores: top5Compradores,
      top5Proveedores: top5Proveedores,
      ordenesNuevoRevisionPorDia: ordenesNuevoRevisionPorDia,
      ordenesPendientePagoPorDia: ordenesPendientePagoPorDia,
    );
  }

  // Grouped count by date - returns [{date, count}]
  Future<List<Map<String, dynamic>>> _fetchUsuariosCounts(
      String from, String to) async {
    // Supabase doesn't support GROUP BY directly, so we fetch minimal data
    final response = await _supabase
        .schema('carnavalapp')
        .from('Usuarios')
        .select('created_at')
        .gte('created_at', from)
        .lte('created_at', to);
    // Group client-side but only fetched 1 column
    final grouped = <String, int>{};
    for (final r in response) {
      final dateStr = _extractDate(r['created_at']);
      grouped[dateStr] = (grouped[dateStr] ?? 0) + 1;
    }
    return grouped.entries
        .map((e) => {'date': e.key, 'count': e.value})
        .toList();
  }

  Future<int> _fetchUsuariosTotal(String from, String to) async {
    final response = await _supabase
        .schema('carnavalapp')
        .from('Usuarios')
        .select('id')
        .gte('created_at', from)
        .lte('created_at', to)
        .count();
    return response.count;
  }

  Future<List<Map<String, dynamic>>> _fetchOrders(
      String from, String to) async {
    final response = await _supabase
        .schema('carnavalapp')
        .from('Orders')
        .select(
            'id, created_at, total, status, metodo_pago, moneda, totalUsd, totalEuro, user_id')
        .gte('created_at', from)
        .lte('created_at', to);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _fetchProductos() async {
    final response = await _supabase
        .schema('carnavalapp')
        .from('Productos')
        .select('id, name, proveedor');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _fetchProveedores() async {
    final response = await _supabase
        .schema('carnavalapp')
        .from('proveedores')
        .select('id, name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<int> _fetchProveedoresTotal() async {
    final response = await _supabase
        .schema('carnavalapp')
        .from('proveedores')
        .select('id')
        .count();
    return response.count;
  }

  Future<List<Map<String, dynamic>>> _fetchOrderDetails(
      String from, String to) async {
    final response = await _supabase
        .schema('carnavalapp')
        .from('OrderDetails')
        .select('product_id, quantity, proveedor, created_at')
        .gte('created_at', from)
        .lte('created_at', to);
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch names for specific user IDs only (max ~5)
  Future<Map<int, String>> _fetchUserNamesByIds(List<int> ids) async {
    if (ids.isEmpty) return {};
    final response = await _supabase
        .schema('carnavalapp')
        .from('Usuarios')
        .select('id, name, email')
        .inFilter('id', ids);
    final map = <int, String>{};
    for (final u in response) {
      final name = (u['name'] ?? '').toString().trim();
      final email = (u['email'] ?? '').toString().trim();
      map[u['id'] as int] =
          name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Usuario ${u['id']}');
    }
    return map;
  }

  String _extractDate(dynamic value) {
    if (value == null) return '2000-01-01';
    final str = value.toString();
    if (str.length >= 10) return str.substring(0, 10);
    return str;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? fallback;
  }
}
