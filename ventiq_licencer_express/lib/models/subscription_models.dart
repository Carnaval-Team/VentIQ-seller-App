import 'license_models.dart';

class StoreProfile {
  const StoreProfile({
    required this.id,
    required this.name,
    required this.owner,
    required this.email,
    this.phone,
    this.state,
    this.country,
  });

  final int? id;
  final String name;
  final String owner;
  final String? email;
  final String? phone;
  final String? state;
  final String? country;

  String get initials {
    if (name.trim().isEmpty) {
      return 'TI';
    }
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 2).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.durationDays,
    required this.periodMonths,
    required this.trialDays,
    required this.currency,
  });

  final int? id;
  final String name;
  final double price;
  final int? durationDays;
  final int periodMonths;
  final int trialDays;
  final String currency;

  bool get isCatalogPlan => id == 5;
}

class SubscriptionRecord {
  const SubscriptionRecord({
    required this.id,
    required this.store,
    required this.plan,
    required this.amount,
    required this.startAt,
    required this.endAt,
    required this.autoRenews,
    required this.status,
    required this.daysLeft,
    required this.rawStatus,
  });

  final int? id;
  final StoreProfile store;
  final SubscriptionPlan plan;
  final double amount;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool autoRenews;
  final LicenseStatus status;
  final int daysLeft;
  final String? rawStatus;
}

class SubscriptionHistory {
  const SubscriptionHistory({
    required this.id,
    required this.subscriptionId,
    required this.amount,
    required this.paidAt,
  });

  final int? id;
  final int? subscriptionId;
  final double amount;
  final DateTime? paidAt;
}

class LicensesSnapshot {
  const LicensesSnapshot({
    required this.subscriptions,
    required this.histories,
  });

  final List<SubscriptionRecord> subscriptions;
  final List<SubscriptionHistory> histories;
}

class DashboardData {
  const DashboardData({
    required this.totalStores,
    required this.activeStores,
    required this.revenueThisMonth,
    required this.revenueLastMonth,
    required this.renewalRevenue,
    required this.recentLicenses,
  });

  final int totalStores;
  final int activeStores;
  final double revenueThisMonth;
  final double revenueLastMonth;
  final double renewalRevenue;
  final List<LicenseInfo> recentLicenses;
}

class StatsData {
  const StatsData({
    required this.projectedRenewalRevenue,
    required this.paidThisMonth,
    required this.paidAmount,
    required this.dueTodayLicenses,
    required this.revenueTrend,
    required this.totalSubscriptions,
  });

  final double projectedRenewalRevenue;
  final int paidThisMonth;
  final double paidAmount;
  final List<LicenseInfo> dueTodayLicenses;
  final List<RevenuePoint> revenueTrend;
  final int totalSubscriptions;
}
