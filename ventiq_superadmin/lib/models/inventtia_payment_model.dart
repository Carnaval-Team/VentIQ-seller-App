class InventtiaPaymentModel {
  /// Base de costo (CUP) — misma lógica que pago a proveedores.
  final double costBaseCup;
  final double costBaseUsd;
  final double costBaseEuro;
  final double commissionUsd;
  final double commissionEuro;
  final double commissionCup;
  final double commissionPercentage;
  final int ordersCount;
  final int linesCount;
  final List<OrderDetail> orders;

  InventtiaPaymentModel({
    required this.costBaseCup,
    required this.costBaseUsd,
    required this.costBaseEuro,
    required this.commissionUsd,
    required this.commissionEuro,
    required this.commissionCup,
    required this.commissionPercentage,
    required this.ordersCount,
    required this.linesCount,
    required this.orders,
  });

  double get totalUsd => costBaseUsd;
  double get totalEuro => costBaseEuro;
  double get totalCup => costBaseCup;
}

class OrderDetail {
  final int orderId;
  final DateTime createdAt;
  final double costCup;
  final double commissionCup;
  final int linesCount;

  OrderDetail({
    required this.orderId,
    required this.createdAt,
    required this.costCup,
    required this.commissionCup,
    required this.linesCount,
  });
}

class ExchangeRates {
  final double valorUsd;
  final double valorEuro;

  ExchangeRates({required this.valorUsd, required this.valorEuro});
}

class InventtiaAgentStore {
  final int proveedorId;
  final String? name;

  const InventtiaAgentStore({required this.proveedorId, this.name});
}

class InventtiaAgent {
  final int id;
  final String nombre;
  final String apellidos;
  final List<InventtiaAgentStore> tiendas;
  final bool activo;

  InventtiaAgent({
    required this.id,
    required this.nombre,
    required this.apellidos,
    required this.tiendas,
    required this.activo,
  });

  String get fullName => '$nombre $apellidos'.trim();

  List<int> get proveedorIds =>
      tiendas.map((t) => t.proveedorId).toList(growable: false);

  String get tiendasLabel {
    if (tiendas.isEmpty) return 'Sin tiendas';
    return tiendas
        .map((t) => t.name ?? 'Tienda #${t.proveedorId}')
        .join(', ');
  }

  factory InventtiaAgent.fromMap(Map<String, dynamic> map) {
    final links = map['inventtia_agente_tiendas'];
    final tiendas = <InventtiaAgentStore>[];
    if (links is List) {
      for (final link in links) {
        if (link is! Map) continue;
        final proveedorId = (link['proveedor_id'] as num?)?.toInt();
        if (proveedorId == null) continue;
        final proveedor = link['proveedores'];
        String? name;
        if (proveedor is Map) {
          name = proveedor['name']?.toString();
        }
        tiendas.add(InventtiaAgentStore(proveedorId: proveedorId, name: name));
      }
    }
    tiendas.sort(
      (a, b) => (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase()),
    );

    return InventtiaAgent(
      id: (map['id'] as num).toInt(),
      nombre: map['nombre']?.toString() ?? '',
      apellidos: map['apellidos']?.toString() ?? '',
      tiendas: tiendas,
      activo: map['activo'] as bool? ?? true,
    );
  }
}

class AgentOrderSummary {
  final int orderId;
  final DateTime? createdAt;
  final double salesCup;
  final double commissionCup;

  const AgentOrderSummary({
    required this.orderId,
    required this.createdAt,
    required this.salesCup,
    required this.commissionCup,
  });
}

class AgentStoreBreakdown {
  final int proveedorId;
  final String? proveedorName;
  final double salesCup;
  final double commissionCup;
  final List<AgentOrderSummary> orders;

  const AgentStoreBreakdown({
    required this.proveedorId,
    required this.proveedorName,
    required this.salesCup,
    required this.commissionCup,
    required this.orders,
  });

  int get ordersCount => orders.length;
}

class AgentPaymentSummary {
  final InventtiaAgent agent;
  final double salesCup;
  final double commissionCup;
  final double commissionUsd;
  final double commissionEuro;
  final double commissionPercentage;
  final List<AgentStoreBreakdown> byStore;

  AgentPaymentSummary({
    required this.agent,
    required this.salesCup,
    required this.commissionCup,
    required this.commissionUsd,
    required this.commissionEuro,
    required this.commissionPercentage,
    required this.byStore,
  });

  int get ordersCount =>
      byStore.fold<int>(0, (s, b) => s + b.ordersCount);
}
