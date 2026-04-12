class DateCount {
  final DateTime date;
  final int count;
  const DateCount(this.date, this.count);
}

class DateValue {
  final DateTime date;
  final double value;
  const DateValue(this.date, this.value);
}

class NameCount {
  final String name;
  final int count;
  const NameCount(this.name, this.count);
}

class NameValue {
  final String name;
  final double value;
  const NameValue(this.name, this.value);
}

class CarnavalDashboardData {
  final int totalUsuarios;
  final List<DateCount> usuariosPorDia;

  final int totalOrdenes;
  final double dineroRecaudado;
  final int ordenesCompletadas;
  final int ordenesCanceladas;

  final Map<String, List<DateCount>> ordenesPorMetodoPago;
  final Map<String, List<DateValue>> dineroPorMetodoPago;
  final Map<String, double> dineroPorMoneda;

  final int totalProveedores;
  final List<NameCount> productosPorProveedor;
  final List<NameCount> productosVendidosPorProveedor;

  final List<NameCount> top5Productos;
  final List<NameValue> top5Compradores;
  final List<NameCount> top5Proveedores;

  // Órdenes por estado (Nuevo/En Revision) por día
  final Map<String, List<DateCount>> ordenesNuevoRevisionPorDia;
  // Órdenes Pendiente de Pago por día
  final List<DateCount> ordenesPendientePagoPorDia;

  const CarnavalDashboardData({
    required this.totalUsuarios,
    required this.usuariosPorDia,
    required this.totalOrdenes,
    required this.dineroRecaudado,
    required this.ordenesCompletadas,
    required this.ordenesCanceladas,
    required this.ordenesPorMetodoPago,
    required this.dineroPorMetodoPago,
    required this.dineroPorMoneda,
    required this.totalProveedores,
    required this.productosPorProveedor,
    required this.productosVendidosPorProveedor,
    required this.top5Productos,
    required this.top5Compradores,
    required this.top5Proveedores,
    required this.ordenesNuevoRevisionPorDia,
    required this.ordenesPendientePagoPorDia,
  });
}
