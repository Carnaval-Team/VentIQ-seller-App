import 'dart:convert';

import '../widget_keys.dart';

/// Configuración persistida de una instancia de widget.
///
/// Cada instancia (appWidgetId) tiene su propia configuración: tienda, y según
/// el tipo, periodo / modo+fechas / producto.
class WidgetConfig {
  const WidgetConfig({
    required this.type,
    required this.appWidgetId,
    this.storeId,
    this.storeName,
    this.periodo,
    this.modo,
    this.desde,
    this.hasta,
    this.productoId,
    this.productoNombre,
    this.expanded = false,
  });

  final HomeWidgetType type;
  final int appWidgetId;

  /// Tienda seleccionada en la configuración del widget (selector multi-tienda).
  final int? storeId;
  final String? storeName;

  /// Mini Dashboard: uno de los periodos del DashboardScreen
  /// ('3 años', '1 año', '6 meses', '3 meses', '1 mes', 'Semana', 'Día').
  final String? periodo;

  /// Sales: [WidgetKeys.modoRealtime] o [WidgetKeys.modoRange].
  final String? modo;
  final DateTime? desde;
  final DateTime? hasta;

  /// Product tracking.
  final int? productoId;
  final String? productoNombre;

  /// Sales: desglose por TPV desplegado.
  final bool expanded;

  bool get isConfigured {
    if (storeId == null) return false;
    switch (type) {
      case HomeWidgetType.miniDashboard:
        return periodo != null && periodo!.isNotEmpty;
      case HomeWidgetType.sales:
        if (modo == WidgetKeys.modoRange) {
          return desde != null && hasta != null;
        }
        return modo != null;
      case HomeWidgetType.product:
        return productoId != null;
    }
  }

  /// Rango efectivo a consultar. En tiempo real es el día de hoy, igual que
  /// `SalesService._getDateRangeForPeriod('Hoy')`.
  ({DateTime desde, DateTime hasta}) resolveRange() {
    if (modo == WidgetKeys.modoRange && desde != null && hasta != null) {
      return (desde: desde!, hasta: hasta!);
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return (
      desde: today,
      hasta: today
          .add(const Duration(days: 1))
          .subtract(const Duration(seconds: 1)),
    );
  }

  WidgetConfig copyWith({
    int? storeId,
    String? storeName,
    String? periodo,
    String? modo,
    DateTime? desde,
    DateTime? hasta,
    int? productoId,
    String? productoNombre,
    bool? expanded,
  }) {
    return WidgetConfig(
      type: type,
      appWidgetId: appWidgetId,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      periodo: periodo ?? this.periodo,
      modo: modo ?? this.modo,
      desde: desde ?? this.desde,
      hasta: hasta ?? this.hasta,
      productoId: productoId ?? this.productoId,
      productoNombre: productoNombre ?? this.productoNombre,
      expanded: expanded ?? this.expanded,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.prefix,
    'appWidgetId': appWidgetId,
    'storeId': storeId,
    'storeName': storeName,
    'periodo': periodo,
    'modo': modo,
    'desde': desde?.toIso8601String(),
    'hasta': hasta?.toIso8601String(),
    'productoId': productoId,
    'productoNombre': productoNombre,
    'expanded': expanded,
  };

  static WidgetConfig? fromJson(Map<String, dynamic> json) {
    final type = HomeWidgetType.fromPrefix(json['type'] as String? ?? '');
    final appWidgetId = json['appWidgetId'] as int?;
    if (type == null || appWidgetId == null) return null;

    DateTime? parseDate(Object? value) {
      if (value is! String || value.isEmpty) return null;
      return DateTime.tryParse(value);
    }

    return WidgetConfig(
      type: type,
      appWidgetId: appWidgetId,
      storeId: json['storeId'] as int?,
      storeName: json['storeName'] as String?,
      periodo: json['periodo'] as String?,
      modo: json['modo'] as String?,
      desde: parseDate(json['desde']),
      hasta: parseDate(json['hasta']),
      productoId: json['productoId'] as int?,
      productoNombre: json['productoNombre'] as String?,
      expanded: json['expanded'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  static WidgetConfig? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Configuración vacía para una instancia recién añadida al escritorio.
  factory WidgetConfig.empty(HomeWidgetType type, int appWidgetId) =>
      WidgetConfig(type: type, appWidgetId: appWidgetId);
}
