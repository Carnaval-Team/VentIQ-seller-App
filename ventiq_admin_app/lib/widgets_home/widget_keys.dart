/// Contrato de claves compartido con los widgets nativos de Android.
///
/// Espejo exacto de:
/// `android/app/src/main/kotlin/com/example/ventiq_admin_app/widgets/WidgetKeys.kt`
///
/// REGLA IMPORTANTE: todos los valores numéricos se persisten como String.
/// `home_widget` serializa los `double` como los bits crudos de un Long más una
/// clave auxiliar `home_widget.double.<key>`; guardar texto evita esa
/// ambigüedad y mantiene el contrato legible desde Kotlin.
class WidgetKeys {
  const WidgetKeys._();

  // ── Claves globales ────────────────────────────────────────────────────────
  static const String usdRate = 'vq_usd_rate';
  static const String lastSync = 'vq_last_sync';
  static const String sessionOk = 'vq_session_ok';

  // ── Prefijos por tipo de widget ───────────────────────────────────────────
  static const String prefixMiniDashboard = 'vq_md';
  static const String prefixSales = 'vq_sv';
  static const String prefixProduct = 'vq_pt';

  // ── Campos comunes ────────────────────────────────────────────────────────
  static const String fieldState = 'state';
  static const String fieldError = 'error';
  static const String fieldUpdatedAt = 'updated_at';
  static const String fieldStoreId = 'tienda_id';
  static const String fieldStoreName = 'tienda_nombre';

  // ── Mini Dashboard ────────────────────────────────────────────────────────
  static const String fieldPeriodo = 'periodo';
  static const String fieldVentas = 'ventas';
  static const String fieldGastos = 'gastos';
  static const String fieldGananciaNeta = 'ganancia_neta';
  static const String fieldOrdenes = 'ordenes';
  static const String fieldDeltaPct = 'delta_pct';
  static const String fieldTrend = 'trend';
  static const String fieldTrendLabels = 'trend_labels';

  // ── Sales / TPV ───────────────────────────────────────────────────────────
  static const String fieldModo = 'modo';
  static const String modoRealtime = 'realtime';
  static const String modoRange = 'range';
  static const String fieldDesde = 'desde';
  static const String fieldHasta = 'hasta';
  static const String fieldTotal = 'total';
  static const String fieldEfectivo = 'efectivo';
  static const String fieldTransferencia = 'transferencia';
  static const String fieldEgresos = 'egresos';
  static const String fieldTpvs = 'tpvs';
  static const String fieldExpanded = 'expanded';

  // ── Product Tracking ──────────────────────────────────────────────────────
  static const String fieldProductoId = 'producto_id';
  static const String fieldProductoNombre = 'producto_nombre';
  static const String fieldPrecioVenta = 'precio_venta';
  static const String fieldCostoCup = 'costo_cup';
  static const String fieldCostoUsd = 'costo_usd';
  static const String fieldTotalVendido = 'total_vendido';
  static const String fieldIngresos = 'ingresos';
  static const String fieldStock = 'stock';

  // ── Estados ───────────────────────────────────────────────────────────────
  static const String stateUnconfigured = 'unconfigured';
  static const String stateLoading = 'loading';
  static const String stateOk = 'ok';
  static const String stateError = 'error';

  /// Construye `<prefijo>_<appWidgetId>_<campo>`.
  static String key(String prefix, int appWidgetId, String field) =>
      '${prefix}_${appWidgetId}_$field';

  /// Separador de las series del mini-gráfico y de las etiquetas.
  static const String seriesSeparator = ';';

  // ── URIs de acciones ──────────────────────────────────────────────────────
  static const String uriScheme = 'ventiqwidget';
  static const String hostRefresh = 'refresh';
  static const String hostToggle = 'toggle';
}

/// Tipos de widget disponibles, con el nombre de la clase nativa que
/// `HomeWidget.updateWidget` necesita para disparar el redibujado.
enum HomeWidgetType {
  miniDashboard(
    prefix: WidgetKeys.prefixMiniDashboard,
    androidProvider: 'MiniDashboardWidgetReceiver',
    qualifiedAndroidName:
        'com.example.ventiq_admin_app.widgets.MiniDashboardWidgetReceiver',
    label: 'Mini Dashboard',
  ),
  sales(
    prefix: WidgetKeys.prefixSales,
    androidProvider: 'SalesTpvWidgetReceiver',
    qualifiedAndroidName:
        'com.example.ventiq_admin_app.widgets.SalesTpvWidgetReceiver',
    label: 'Ventas / TPV',
  ),
  product(
    prefix: WidgetKeys.prefixProduct,
    androidProvider: 'ProductTrackingWidgetReceiver',
    qualifiedAndroidName:
        'com.example.ventiq_admin_app.widgets.ProductTrackingWidgetReceiver',
    label: 'Seguimiento de Producto',
  );

  const HomeWidgetType({
    required this.prefix,
    required this.androidProvider,
    required this.qualifiedAndroidName,
    required this.label,
  });

  final String prefix;
  final String androidProvider;
  final String qualifiedAndroidName;
  final String label;

  static HomeWidgetType? fromPrefix(String prefix) {
    for (final type in HomeWidgetType.values) {
      if (type.prefix == prefix) return type;
    }
    return null;
  }

  /// Resuelve el tipo a partir del nombre de clase del AppWidgetProvider,
  /// que es lo que devuelve el canal nativo al configurar una instancia.
  static HomeWidgetType? fromProviderClassName(String className) {
    for (final type in HomeWidgetType.values) {
      if (className.endsWith(type.androidProvider)) return type;
    }
    return null;
  }

  String keyFor(int appWidgetId, String field) =>
      WidgetKeys.key(prefix, appWidgetId, field);
}
