class InventtiaPaymentModel {
  final double totalUsd;
  final double totalEuro;
  final double totalCup;
  final double commissionUsd;
  final double commissionEuro;
  final double commissionCup;
  final double commissionPercentage;
  final int ordersCount;
  final List<OrderDetail> orders;

  InventtiaPaymentModel({
    required this.totalUsd,
    required this.totalEuro,
    required this.totalCup,
    required this.commissionUsd,
    required this.commissionEuro,
    required this.commissionCup,
    required this.commissionPercentage,
    required this.ordersCount,
    required this.orders,
  });
}

class OrderDetail {
  final int orderId;
  final DateTime createdAt;
  final String moneda;
  final double totalOriginal;
  final double totalInCurrency;
  final String metodoPago;
  final String status;

  OrderDetail({
    required this.orderId,
    required this.createdAt,
    required this.moneda,
    required this.totalOriginal,
    required this.totalInCurrency,
    required this.metodoPago,
    required this.status,
  });
}

class ExchangeRates {
  final double valorUsd;
  final double valorEuro;

  ExchangeRates({required this.valorUsd, required this.valorEuro});
}
