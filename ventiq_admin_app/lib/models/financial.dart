class Expense {
  final String id;
  final String description;
  final String category;
  final String costCenter;
  final double amount;
  final String currency;
  final DateTime expenseDate;
  final String paymentMethod;
  final String status; // pendiente, aprobado, pagado, rechazado
  final String? receipt;
  final String userId;
  final String userName;
  final String? approvedBy;
  final DateTime createdAt;

  Expense({
    required this.id,
    required this.description,
    required this.category,
    required this.costCenter,
    required this.amount,
    this.currency = 'USD',
    required this.expenseDate,
    required this.paymentMethod,
    required this.status,
    this.receipt,
    required this.userId,
    required this.userName,
    this.approvedBy,
    required this.createdAt,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      costCenter: json['costCenter'] ?? '',
      amount: (json['amount'] ?? 0.0).toDouble(),
      currency: json['currency'] ?? 'USD',
      expenseDate: DateTime.parse(json['expenseDate'] ?? DateTime.now().toIso8601String()),
      paymentMethod: json['paymentMethod'] ?? '',
      status: json['status'] ?? 'pendiente',
      receipt: json['receipt'],
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      approvedBy: json['approvedBy'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class CostCenter {
  final String id;
  final String name;
  final String code;
  final String description;
  final String type; // operacional, administrativo, ventas, marketing
  final double budget;
  final double spent;
  final bool isActive;
  final String? parentId;

  CostCenter({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    required this.type,
    required this.budget,
    required this.spent,
    this.isActive = true,
    this.parentId,
  });

  factory CostCenter.fromJson(Map<String, dynamic> json) {
    return CostCenter(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? '',
      budget: (json['budget'] ?? 0.0).toDouble(),
      spent: (json['spent'] ?? 0.0).toDouble(),
      isActive: json['isActive'] ?? true,
      parentId: json['parentId'],
    );
  }

  double get remainingBudget => budget - spent;
  double get budgetUsagePercentage => budget > 0 ? (spent / budget) * 100 : 0;
}

class FinancialReport {
  final String period;
  final DateTime startDate;
  final DateTime endDate;
  final double totalRevenue;
  final double totalExpenses;
  final double grossProfit;
  final double netProfit;
  final double profitMargin;
  final Map<String, double> expensesByCategory;
  final Map<String, double> revenueByProduct;

  FinancialReport({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.totalExpenses,
    required this.grossProfit,
    required this.netProfit,
    required this.profitMargin,
    required this.expensesByCategory,
    required this.revenueByProduct,
  });
}
