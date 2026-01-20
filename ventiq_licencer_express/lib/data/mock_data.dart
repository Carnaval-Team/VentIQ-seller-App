import '../models/license_models.dart';

class MockData {
  static const int totalStores = 1240;
  static const double revenueThisMonth = 4320;
  static const double revenueLastMonth = 3860;
  static const double projectedRenewalRevenue = 12500;
  static const int paidThisMonth = 218;
  static const double paidAmount = 8420;
  static const int dueTodayCount = 4;

  static const List<LicenseInfo> recentLicenses = [
    LicenseInfo(
      storeName: 'Alice Boutique',
      plan: 'Premium Plan',
      owner: 'Alice George',
      avatarLabel: 'AB',
      renewalAmount: 220,
      daysLeft: 25,
      autoRenews: true,
      status: LicenseStatus.active,
    ),
    LicenseInfo(
      storeName: 'Johns Tech Corner',
      plan: 'Basic Plan',
      owner: 'John Doe',
      avatarLabel: 'JT',
      renewalAmount: 90,
      daysLeft: 3,
      autoRenews: false,
      status: LicenseStatus.expiringSoon,
    ),
    LicenseInfo(
      storeName: 'Sarah Studio',
      plan: 'Enterprise',
      owner: 'Sarah Smith',
      avatarLabel: 'SS',
      renewalAmount: 480,
      daysLeft: 12,
      autoRenews: true,
      status: LicenseStatus.active,
    ),
    LicenseInfo(
      storeName: 'Mikes Market',
      plan: 'Premium Plan',
      owner: 'Mike Johnson',
      avatarLabel: 'MM',
      renewalAmount: 200,
      daysLeft: 45,
      autoRenews: true,
      status: LicenseStatus.active,
    ),
    LicenseInfo(
      storeName: 'Emma Emporium',
      plan: 'Basic Plan',
      owner: 'Emma Brown',
      avatarLabel: 'EE',
      renewalAmount: 110,
      daysLeft: 2,
      autoRenews: false,
      status: LicenseStatus.expiringSoon,
    ),
  ];

  static const List<LicenseInfo> dueTodayLicenses = [
    LicenseInfo(
      storeName: 'TechNova Shop',
      plan: 'Premium Plan',
      owner: 'John Doe',
      avatarLabel: 'TN',
      renewalAmount: 250,
      daysLeft: 0,
      autoRenews: false,
      status: LicenseStatus.dueToday,
    ),
    LicenseInfo(
      storeName: 'Luxe Boutique',
      plan: 'Enterprise',
      owner: 'Sarah Smith',
      avatarLabel: 'LB',
      renewalAmount: 150,
      daysLeft: 0,
      autoRenews: false,
      status: LicenseStatus.dueToday,
    ),
    LicenseInfo(
      storeName: 'FreshMart',
      plan: 'Premium Plan',
      owner: 'Mike Johnson',
      avatarLabel: 'FM',
      renewalAmount: 450,
      daysLeft: 0,
      autoRenews: false,
      status: LicenseStatus.dueToday,
    ),
    LicenseInfo(
      storeName: 'Bean Cafe',
      plan: 'Basic Plan',
      owner: 'Alice Wong',
      avatarLabel: 'BC',
      renewalAmount: 85,
      daysLeft: 0,
      autoRenews: false,
      status: LicenseStatus.dueToday,
    ),
  ];

  static const List<StoreInfo> stores = [
    StoreInfo(
      storeName: 'Alice Boutique',
      plan: 'Premium Plan',
      owner: 'Alice George',
      renewalAmount: 220,
      daysLeft: 25,
      lastPayment: '12 Ene 2026',
      status: LicenseStatus.active,
    ),
    StoreInfo(
      storeName: 'TechNova Shop',
      plan: 'Premium Plan',
      owner: 'John Doe',
      renewalAmount: 250,
      daysLeft: 0,
      lastPayment: '19 Ene 2026',
      status: LicenseStatus.dueToday,
    ),
    StoreInfo(
      storeName: 'Luxe Boutique',
      plan: 'Enterprise',
      owner: 'Sarah Smith',
      renewalAmount: 150,
      daysLeft: 3,
      lastPayment: '05 Ene 2026',
      status: LicenseStatus.expiringSoon,
    ),
    StoreInfo(
      storeName: 'FreshMart',
      plan: 'Premium Plan',
      owner: 'Mike Johnson',
      renewalAmount: 450,
      daysLeft: 14,
      lastPayment: '02 Ene 2026',
      status: LicenseStatus.active,
    ),
    StoreInfo(
      storeName: 'Bean Cafe',
      plan: 'Basic Plan',
      owner: 'Alice Wong',
      renewalAmount: 85,
      daysLeft: -2,
      lastPayment: '12 Dic 2025',
      status: LicenseStatus.overdue,
    ),
  ];

  static const List<RevenuePoint> revenueTrend = [
    RevenuePoint(label: 'Ene', value: 5200),
    RevenuePoint(label: 'Feb', value: 6100),
    RevenuePoint(label: 'Mar', value: 5800),
    RevenuePoint(label: 'Abr', value: 7200),
    RevenuePoint(label: 'May', value: 6800),
    RevenuePoint(label: 'Jun', value: 8400),
    RevenuePoint(label: 'Jul', value: 9100),
    RevenuePoint(label: 'Ago', value: 10200),
  ];
}
