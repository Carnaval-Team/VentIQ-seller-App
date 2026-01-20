enum LicenseStatus { active, expiringSoon, dueToday, overdue }

class LicenseInfo {
  const LicenseInfo({
    this.subscriptionId,
    this.storeId,
    required this.storeName,
    required this.plan,
    required this.owner,
    required this.avatarLabel,
    required this.renewalAmount,
    required this.daysLeft,
    required this.autoRenews,
    required this.status,
    this.phone,
    this.state,
    this.country,
    this.currency,
  });

  final int? subscriptionId;
  final int? storeId;
  final String storeName;
  final String plan;
  final String owner;
  final String avatarLabel;
  final double renewalAmount;
  final int daysLeft;
  final bool autoRenews;
  final LicenseStatus status;
  final String? phone;
  final String? state;
  final String? country;
  final String? currency;

  String get daysLeftLabel {
    if (daysLeft < 0) {
      return 'Vencida';
    }
    if (daysLeft == 0) {
      return 'Hoy';
    }
    if (daysLeft == 1) {
      return '1 dia';
    }
    return '$daysLeft dias';
  }

  String get statusLabel {
    switch (status) {
      case LicenseStatus.active:
        return autoRenews ? 'Auto-renueva' : 'Activo';
      case LicenseStatus.expiringSoon:
        return 'Expira pronto';
      case LicenseStatus.dueToday:
        return 'Vence hoy';
      case LicenseStatus.overdue:
        return 'Vencida';
    }
  }
}

class StoreInfo {
  const StoreInfo({
    this.subscriptionId,
    this.storeId,
    required this.storeName,
    required this.plan,
    required this.owner,
    required this.renewalAmount,
    required this.daysLeft,
    required this.lastPayment,
    required this.status,
    this.phone,
    this.state,
    this.country,
    this.currency,
  });

  final int? subscriptionId;
  final int? storeId;
  final String storeName;
  final String plan;
  final String owner;
  final double renewalAmount;
  final int daysLeft;
  final String lastPayment;
  final LicenseStatus status;
  final String? phone;
  final String? state;
  final String? country;
  final String? currency;
}

class RevenuePoint {
  const RevenuePoint({required this.label, required this.value});

  final String label;
  final double value;
}
