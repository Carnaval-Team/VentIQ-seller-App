import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/license_models.dart';
import '../models/subscription_models.dart';

class SubscriptionService {
  SubscriptionService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const String _renewalSummaryTable =
      'app_suscripciones_renovaciones_resumen';

  void _log(String message) {
    debugPrint('🧭 [SubscriptionService] $message');
  }

  Future<DashboardData> fetchDashboardData() async {
    _log('Cargando datos del dashboard...');
    final snapshot = await fetchSubscriptionsSnapshot();
    final subscriptions = snapshot.subscriptions;
    final histories = snapshot.histories;
    final now = DateTime.now();

    final totalStores = subscriptions
        .map((record) => record.store.id)
        .whereType<int>()
        .toSet()
        .length;
    final activeStores = subscriptions
        .where((record) => record.status == LicenseStatus.active)
        .map((record) => record.store.id)
        .whereType<int>()
        .toSet()
        .length;
    final revenueThisMonth = _sumHistories(histories, now.year, now.month);
    final previousMonth = DateTime(now.year, now.month - 1, 1);
    final revenueLastMonth = _sumHistories(
      histories,
      previousMonth.year,
      previousMonth.month,
    );
    final renewalRevenue = _sumUpcomingRenewals(subscriptions);

    final recentLicenses = _buildRecentLicenses(subscriptions);

    _log(
      'Dashboard listo: tiendas=$totalStores, activas=$activeStores, renovaciones=$renewalRevenue, licencias recientes=${recentLicenses.length}',
    );

    return DashboardData(
      totalStores: totalStores,
      activeStores: activeStores,
      revenueThisMonth: revenueThisMonth,
      revenueLastMonth: revenueLastMonth,
      renewalRevenue: renewalRevenue,
      recentLicenses: recentLicenses,
    );
  }

  Future<StatsData> fetchStatsData() async {
    _log('Cargando datos de estadisticas...');
    final snapshot = await fetchSubscriptionsSnapshot();
    final subscriptions = snapshot.subscriptions;
    final histories = snapshot.histories;
    final now = DateTime.now();

    final revenueThisMonth = _sumHistories(histories, now.year, now.month);
    final previousMonth = DateTime(now.year, now.month - 1, 1);
    final revenueLastMonth = _sumHistories(
      histories,
      previousMonth.year,
      previousMonth.month,
    );
    final renewalRevenue = _sumUpcomingRenewals(subscriptions);
    final paidThisMonth = histories
        .where((history) => _isSameMonth(history.paidAt, now))
        .length;
    final paidAmount = revenueThisMonth;
    final dueTodayLicenses = subscriptions
        .where((record) => record.daysLeft == 0)
        .map(_licenseFromRecord)
        .toList();
    final revenueTrend = _buildRevenueTrend(histories);
    final renewalSummary = await _fetchRenewalSummaries();

    _log(
      'Stats listas: suscripciones=${subscriptions.length}, '
      'pagadas=$paidThisMonth, vencen hoy=${dueTodayLicenses.length}',
    );

    return StatsData(
      projectedRenewalRevenue: renewalRevenue,
      paidThisMonth: paidThisMonth,
      paidAmount: paidAmount,
      revenueLastMonth: revenueLastMonth,
      renewalTotal: renewalSummary.total,
      renewalSummaries: renewalSummary.summaries,
      dueTodayLicenses: dueTodayLicenses,
      revenueTrend: revenueTrend,
      totalSubscriptions: subscriptions.length,
    );
  }

  Future<List<StoreInfo>> fetchStores() async {
    _log('Cargando lista de tiendas...');
    final snapshot = await fetchSubscriptionsSnapshot();
    final histories = snapshot.histories;
    final lastPaymentBySubscription = _latestPaymentBySubscription(histories);
    final stores = snapshot.subscriptions.map((record) {
      final lastPayment = lastPaymentBySubscription[record.id];
      return _storeFromRecord(record, lastPayment);
    }).toList();

    _log('Tiendas cargadas: ${stores.length}');
    return stores;
  }

  Future<List<SubscriptionPlan>> fetchActivePlans() async {
    _log('Cargando planes activos...');
    final rawPlans = await _client
        .from('app_suscripciones_plan')
        .select(
          'id, denominacion, precio_mensual, duracion_trial_dias, periodo, moneda',
        )
        .eq('es_activo', true)
        .order('id', ascending: true);

    return (rawPlans as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(_mapPlanOption)
        .toList();
  }

  Future<void> renewSubscription({
    required int subscriptionId,
    required int storeId,
    required int? previousPlanId,
    required int newPlanId,
    required int? previousStatusId,
    required DateTime newEndDate,
    required double planAmount,
  }) async {
    _log('Renovando suscripcion $subscriptionId...');
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw Exception('Usuario no autenticado');
    }

    final now = DateTime.now();

    await _client.from('app_suscripciones_historial').insert({
      'id_suscripcion': subscriptionId,
      'id_plan_anterior': previousPlanId ?? newPlanId,
      'id_plan_nuevo': newPlanId,
      'estado_anterior': previousStatusId ?? 1,
      'estado_nuevo': 1,
      'motivo': 'Renovación de licencia',
      'cambiado_por': currentUser.id,
    });

    await _client
        .from('app_suscripciones')
        .update({
          'id_plan': newPlanId,
          'fecha_fin': newEndDate.toIso8601String(),
          'estado': 1,
          'updated_at': now.toIso8601String(),
        })
        .eq('id', subscriptionId);

    await _upsertRenewalSummary(
      month: now.month,
      year: now.year,
      storeId: storeId,
      planId: newPlanId,
      amount: planAmount,
    );
  }

  Future<LicensesSnapshot> fetchSubscriptionsSnapshot() async {
    _log('Consultando app_suscripciones con joins...');
    List<dynamic> rawSubscriptions;
    try {
      rawSubscriptions = await _client
          .from('app_suscripciones')
          .select(
            'id, id_tienda, id_plan, fecha_inicio, fecha_fin, estado, renovacion_automatica, '
            'app_dat_tienda(id, denominacion, phone, nombre_estado, nombre_pais), '
            'app_suscripciones_plan(id, denominacion, precio_mensual, duracion_trial_dias, periodo, moneda)',
          )
          .order('fecha_fin', ascending: true);
    } catch (error) {
      _log('Error cargando suscripciones: $error');
      rethrow;
    }

    _log('Suscripciones recibidas: ${rawSubscriptions.length}');

    final subscriptions = _dedupeSubscriptions(
      rawSubscriptions
          .whereType<Map<String, dynamic>>()
          .map(_mapSubscriptionRecord)
          .toList(),
    );

    final subscriptionIds = subscriptions
        .map((record) => record.id)
        .whereType<int>()
        .toList();

    List<SubscriptionHistory> histories = [];
    if (subscriptionIds.isNotEmpty) {
      _log('Consultando historial (${subscriptionIds.length} ids)...');
      try {
        final rawHistories = await _client
            .from('app_suscripciones_historial')
            .select(
              'id, id_suscripcion, fecha_cambio, '
              'app_suscripciones(id, id_plan, app_suscripciones_plan(id, denominacion, precio_mensual))',
            )
            .filter('id_suscripcion', 'in', '(${subscriptionIds.join(',')})')
            .order('fecha_cambio', ascending: false);

        histories = (rawHistories as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .map(_mapHistory)
            .toList();
      } catch (error) {
        _log('Error cargando historial: $error');
        rethrow;
      }
      _log('Historial recibido: ${histories.length}');
    } else {
      _log('Sin IDs de suscripcion para historial.');
    }

    return LicensesSnapshot(subscriptions: subscriptions, histories: histories);
  }

  SubscriptionRecord _mapSubscriptionRecord(Map<String, dynamic> data) {
    final storeMap = _extractMap(data['app_dat_tienda']);
    final planMap = _extractMap(data['app_suscripciones_plan']);

    final storeName = _stringFrom(storeMap, [
      'denominacion',
    ], fallback: 'Sin tienda');
    final phone = _stringFrom(storeMap, ['phone'], fallback: '');
    final owner = phone.isNotEmpty ? phone : 'Sin contacto';

    final store = StoreProfile(
      id: _intFrom(storeMap, ['id']) ?? _intFrom(data, ['id_tienda']),
      name: storeName,
      owner: owner,
      email: null,
      phone: phone.isEmpty ? null : phone,
      state: _stringFrom(storeMap, ['nombre_estado'], fallback: ''),
      country: _stringFrom(storeMap, ['nombre_pais'], fallback: ''),
    );

    final planName = _stringFrom(planMap, ['denominacion'], fallback: 'Plan');
    final planPeriod = _intFrom(planMap, ['periodo']) ?? 1;
    final trialDays = _intFrom(planMap, ['duracion_trial_dias']) ?? 0;
    final planDays = planPeriod * 30;
    final currency = _stringFrom(planMap, ['moneda'], fallback: 'USD');

    final plan = SubscriptionPlan(
      id: _intFrom(planMap, ['id']) ?? _intFrom(data, ['id_plan']),
      name: planName,
      price: _doubleFrom(planMap, ['precio_mensual'], fallback: 0),
      durationDays: planDays,
      periodMonths: planPeriod,
      trialDays: trialDays,
      currency: currency,
    );

    final startAt = _dateFrom(data, ['fecha_inicio', 'inicio', 'start_at']);
    final rawEndAt = _dateFrom(data, [
      'fecha_fin',
      'fin',
      'end_at',
      'vencimiento',
    ]);
    final endAt =
        rawEndAt ??
        (startAt != null && plan.durationDays != null
            ? startAt.add(Duration(days: plan.durationDays!))
            : null);
    final amount = _doubleFrom(data, ['monto'], fallback: plan.price);
    final autoRenews = _boolFrom(data, ['renovacion_automatica']);
    final rawStatus = _stringFrom(data, ['estado', 'status'], fallback: '');
    final statusId = _intFrom(data, ['estado', 'status']);

    late final int daysLeft;
    late final LicenseStatus status;
    if (endAt == null && plan.isCatalogPlan) {
      daysLeft = 9999;
      status = LicenseStatus.active;
    } else {
      daysLeft = _daysUntil(endAt);
      status = _statusFrom(rawStatus, daysLeft);
    }

    return SubscriptionRecord(
      id: _intFrom(data, ['id']),
      store: store,
      plan: plan,
      amount: amount,
      startAt: startAt,
      endAt: endAt,
      autoRenews: autoRenews,
      status: status,
      statusId: statusId,
      daysLeft: daysLeft,
      rawStatus: rawStatus.isEmpty ? null : rawStatus,
    );
  }

  SubscriptionHistory _mapHistory(Map<String, dynamic> data) {
    final subscriptionMap = _extractMap(data['app_suscripciones']);
    final planMap = _extractMap(subscriptionMap?['app_suscripciones_plan']);

    return SubscriptionHistory(
      id: _intFrom(data, ['id']),
      subscriptionId: _intFrom(data, ['id_suscripcion', 'id_subscription']),
      amount: _doubleFrom(planMap, ['precio_mensual'], fallback: 0),
      paidAt: _dateFrom(data, ['fecha_cambio']),
    );
  }

  LicenseInfo _licenseFromRecord(SubscriptionRecord record) {
    return LicenseInfo(
      subscriptionId: record.id,
      storeId: record.store.id,
      planId: record.plan.id,
      statusId: record.statusId,
      storeName: record.store.name,
      plan: record.plan.name,
      owner: record.store.owner,
      avatarLabel: record.store.initials,
      renewalAmount: record.amount,
      daysLeft: record.daysLeft,
      autoRenews: record.autoRenews,
      status: record.status,
      phone: record.store.phone,
      state: record.store.state,
      country: record.store.country,
      currency: record.plan.currency,
    );
  }

  StoreInfo _storeFromRecord(SubscriptionRecord record, DateTime? lastPayment) {
    return StoreInfo(
      subscriptionId: record.id,
      storeId: record.store.id,
      planId: record.plan.id,
      statusId: record.statusId,
      storeName: record.store.name,
      plan: record.plan.name,
      owner: record.store.owner,
      renewalAmount: record.amount,
      daysLeft: record.daysLeft,
      lastPayment: lastPayment != null
          ? _formatDateShort(lastPayment)
          : 'Sin pagos',
      status: record.status,
      phone: record.store.phone,
      state: record.store.state,
      country: record.store.country,
      currency: record.plan.currency,
    );
  }

  List<SubscriptionRecord> _dedupeSubscriptions(
    List<SubscriptionRecord> records,
  ) {
    final grouped = <int, List<SubscriptionRecord>>{};
    for (final record in records) {
      final storeId = record.store.id;
      if (storeId == null) {
        continue;
      }
      grouped.putIfAbsent(storeId, () => []).add(record);
    }

    final filtered = <SubscriptionRecord>[];
    for (final entries in grouped.values) {
      final nonFree = entries.where((record) => record.plan.id != 1).toList();
      final candidates = nonFree.isNotEmpty ? nonFree : entries;
      candidates.sort((a, b) {
        final dateA = a.endAt ?? a.startAt ?? DateTime(1900);
        final dateB = b.endAt ?? b.startAt ?? DateTime(1900);
        return dateB.compareTo(dateA);
      });
      filtered.add(candidates.first);
    }
    return filtered;
  }

  List<LicenseInfo> _buildRecentLicenses(
    List<SubscriptionRecord> subscriptions,
  ) {
    final upcoming = subscriptions
        .where((record) => record.daysLeft >= 0)
        .toList();
    final target = upcoming.isNotEmpty ? upcoming : subscriptions;
    target.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return target.take(5).map(_licenseFromRecord).toList();
  }

  List<RevenuePoint> _buildRevenueTrend(List<SubscriptionHistory> histories) {
    final now = DateTime.now();
    final anchorMonth = DateTime(now.year, now.month, 1);
    final months = List.generate(
      6,
      (index) => DateTime(anchorMonth.year, anchorMonth.month - (5 - index), 1),
    );

    if (histories.isEmpty) {
      _log('Sin historial de pagos, generando tendencia en cero.');
    }

    return months.map((monthDate) {
      final total = histories
          .where((history) => _isSameMonth(history.paidAt, monthDate))
          .fold<double>(0, (sum, history) => sum + history.amount);
      return RevenuePoint(label: _monthLabel(monthDate.month), value: total);
    }).toList();
  }

  Map<int, DateTime> _latestPaymentBySubscription(
    List<SubscriptionHistory> histories,
  ) {
    final latest = <int, DateTime>{};
    for (final history in histories) {
      final id = history.subscriptionId;
      final paidAt = history.paidAt;
      if (id == null || paidAt == null) {
        continue;
      }
      final current = latest[id];
      if (current == null || paidAt.isAfter(current)) {
        latest[id] = paidAt;
      }
    }
    return latest;
  }

  double _sumHistories(
    List<SubscriptionHistory> histories,
    int year,
    int month,
  ) {
    return histories
        .where(
          (history) =>
              history.paidAt != null &&
              history.paidAt!.year == year &&
              history.paidAt!.month == month,
        )
        .fold<double>(0, (sum, history) => sum + history.amount);
  }

  double _sumUpcomingRenewals(List<SubscriptionRecord> subscriptions) {
    return subscriptions
        .where((record) => record.daysLeft >= 0 && record.daysLeft <= 30)
        .fold<double>(0, (sum, record) => sum + record.amount);
  }

  bool _isSameMonth(DateTime? date, DateTime reference) {
    if (date == null) {
      return false;
    }
    return date.year == reference.year && date.month == reference.month;
  }

  LicenseStatus _statusFrom(String rawStatus, int daysLeft) {
    final normalized = rawStatus.toLowerCase();
    if (normalized.contains('venc') || normalized.contains('overdue')) {
      return LicenseStatus.overdue;
    }
    if (normalized.contains('hoy')) {
      return LicenseStatus.dueToday;
    }
    if (normalized.contains('expir') || normalized.contains('pronto')) {
      return LicenseStatus.expiringSoon;
    }
    if (normalized.contains('activo') || normalized.contains('vigente')) {
      return LicenseStatus.active;
    }

    if (daysLeft < 0) {
      return LicenseStatus.overdue;
    }
    if (daysLeft == 0) {
      return LicenseStatus.dueToday;
    }
    if (daysLeft <= 3) {
      return LicenseStatus.expiringSoon;
    }
    return LicenseStatus.active;
  }

  Map<String, dynamic>? _extractMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  String _normalizeDateString(String raw) {
    var normalized = raw.replaceFirst(' ', 'T');
    if (RegExp(r'[+-]\d{2}$').hasMatch(normalized)) {
      normalized = normalized.replaceFirst(RegExp(r'([+-]\d{2})$'), r'$1:00');
    } else if (RegExp(r'[+-]\d{4}$').hasMatch(normalized)) {
      normalized = normalized.replaceFirst(
        RegExp(r'([+-]\d{2})(\d{2})$'),
        r'$1:$2',
      );
    }
    return normalized;
  }

  int _daysUntil(DateTime? endAt) {
    if (endAt == null) {
      return 0;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = DateTime(endAt.year, endAt.month, endAt.day);
    return (endDate.difference(today).inDays);
  }

  String _stringFrom(
    Map<String, dynamic>? data,
    List<String> keys, {
    String fallback = '',
  }) {
    if (data == null) {
      return fallback;
    }
    for (final key in keys) {
      final value = data[key];
      if (value == null) {
        continue;
      }
      final parsed = value.toString().trim();
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }
    return fallback;
  }

  int? _intFrom(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) {
      return null;
    }
    for (final key in keys) {
      final value = data[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  double _doubleFrom(
    Map<String, dynamic>? data,
    List<String> keys, {
    double fallback = 0,
  }) {
    if (data == null) {
      return fallback;
    }
    for (final key in keys) {
      final value = data[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return fallback;
  }

  bool _boolFrom(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) {
      return false;
    }
    for (final key in keys) {
      final value = data[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        final normalized = value.toLowerCase();
        if (['true', '1', 'si', 'sí', 'yes'].contains(normalized)) {
          return true;
        }
        if (['false', '0', 'no'].contains(normalized)) {
          return false;
        }
      }
    }
    return false;
  }

  DateTime? _dateFrom(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) {
      return null;
    }
    for (final key in keys) {
      final value = data[key];
      if (value == null) {
        continue;
      }
      if (value is DateTime) {
        return value.toLocal();
      }
      if (value is String) {
        final normalized = _normalizeDateString(value);
        final parsed = DateTime.tryParse(normalized);
        if (parsed != null) {
          return parsed.toLocal();
        }
      }
      if (value is int) {
        final millis = value > 1000000000000 ? value : value * 1000;
        return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
      }
    }
    return null;
  }

  String _formatDateShort(DateTime date) {
    final months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    final day = date.day.toString().padLeft(2, '0');
    final monthLabel = months[date.month - 1];
    return '$day $monthLabel ${date.year}';
  }

  String _monthLabel(int month) {
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return months[month - 1];
  }

  SubscriptionPlan _mapPlanOption(Map<String, dynamic> data) {
    final planPeriod = _intFrom(data, ['periodo']) ?? 1;
    final trialDays = _intFrom(data, ['duracion_trial_dias']) ?? 0;
    final planDays = planPeriod * 30;

    return SubscriptionPlan(
      id: _intFrom(data, ['id']),
      name: _stringFrom(data, ['denominacion'], fallback: 'Plan'),
      price: _doubleFrom(data, ['precio_mensual'], fallback: 0),
      durationDays: planDays,
      periodMonths: planPeriod,
      trialDays: trialDays,
      currency: _stringFrom(data, ['moneda'], fallback: 'USD'),
    );
  }

  Future<void> _upsertRenewalSummary({
    required int month,
    required int year,
    required int storeId,
    required int planId,
    required double amount,
  }) async {
    final existing = await _client
        .from(_renewalSummaryTable)
        .select('id, total_pagado')
        .eq('id_mes', month)
        .eq('id_anno', year)
        .eq('id_tienda', storeId)
        .eq('id_plan', planId)
        .maybeSingle();

    if (existing != null && existing['id'] != null) {
      final currentTotal = (existing['total_pagado'] as num?)?.toDouble() ?? 0;
      await _client
          .from(_renewalSummaryTable)
          .update({'total_pagado': currentTotal + amount})
          .eq('id', existing['id']);
    } else {
      await _client.from(_renewalSummaryTable).insert({
        'id_mes': month,
        'id_anno': year,
        'id_tienda': storeId,
        'id_plan': planId,
        'total_pagado': amount,
      });
    }
  }

  Future<_RenewalSummaryResult> _fetchRenewalSummaries() async {
    try {
      final rawRows = await _client
          .from(_renewalSummaryTable)
          .select(
            'id_mes, id_anno, total_pagado, '
            'app_dat_tienda(denominacion), '
            'app_suscripciones_plan(denominacion)',
          )
          .order('id_anno', ascending: false)
          .order('id_mes', ascending: false);

      final grouped = <String, _MutableRenewalSummary>{};
      double total = 0;

      for (final row in (rawRows as List<dynamic>)) {
        if (row is! Map<String, dynamic>) {
          continue;
        }
        final year = (row['id_anno'] as num?)?.toInt() ?? 0;
        final month = (row['id_mes'] as num?)?.toInt() ?? 0;
        if (year == 0 || month == 0) {
          continue;
        }
        final paid = (row['total_pagado'] as num?)?.toDouble() ?? 0;
        total += paid;

        final key = '$year-$month';
        final summary = grouped.putIfAbsent(
          key,
          () => _MutableRenewalSummary(year: year, month: month),
        );
        summary.totalPaid += paid;

        final storeName =
            (row['app_dat_tienda'] as Map<String, dynamic>?)?['denominacion']
                ?.toString() ??
            'Tienda';
        final planName =
            (row['app_suscripciones_plan']
                    as Map<String, dynamic>?)?['denominacion']
                ?.toString() ??
            'Plan';

        summary.details.add(
          RenewalSummaryDetail(
            storeName: storeName,
            planName: planName,
            totalPaid: paid,
          ),
        );
      }

      final summaries = grouped.values.toList()
        ..sort((a, b) {
          if (a.year != b.year) {
            return b.year.compareTo(a.year);
          }
          return b.month.compareTo(a.month);
        });

      final normalized = summaries
          .map(
            (summary) => RenewalMonthlySummary(
              year: summary.year,
              month: summary.month,
              totalPaid: summary.totalPaid,
              details: summary.details
                ..sort((a, b) => b.totalPaid.compareTo(a.totalPaid)),
            ),
          )
          .toList();

      return _RenewalSummaryResult(total: total, summaries: normalized);
    } catch (error) {
      _log('Error cargando resumen de renovaciones: $error');
      return const _RenewalSummaryResult(total: 0, summaries: []);
    }
  }
}

class _RenewalSummaryResult {
  const _RenewalSummaryResult({required this.total, required this.summaries});

  final double total;
  final List<RenewalMonthlySummary> summaries;
}

class _MutableRenewalSummary {
  _MutableRenewalSummary({required this.year, required this.month});

  final int year;
  final int month;
  double totalPaid = 0;
  final List<RenewalSummaryDetail> details = [];
}
