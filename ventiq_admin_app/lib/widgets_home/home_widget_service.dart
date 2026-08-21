import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'data/widget_config_store.dart';
import 'data/widget_data_repository.dart';
import 'data/widget_headless_bootstrap.dart';
import 'models/widget_config.dart';
import 'widget_keys.dart';

/// Orquestador de los Home Screen Widgets.
///
/// Único punto que escribe en las preferencias nativas y pide el redibujado.
/// Lo usan tanto la app en primer plano (al cambiar de tienda, al guardar una
/// configuración, al abrir el Dashboard) como los isolates de background.
class HomeWidgetService {
  HomeWidgetService._();

  static final WidgetDataRepository _repository = const WidgetDataRepository();

  /// Persiste la configuración de una instancia y refresca sus datos.
  static Future<void> saveConfigAndRefresh(WidgetConfig config) async {
    await WidgetConfigStore.save(config);
    await refreshOne(config);
  }

  /// Refresca todas las instancias registradas.
  ///
  /// [onlyType] limita el refresco a un tipo (p. ej. al abrir SalesScreen solo
  /// interesa actualizar los widgets de ventas).
  static Future<void> refreshAll({HomeWidgetType? onlyType}) async {
    final sessionReady = await WidgetHeadlessBootstrap.ensureReady();
    await HomeWidget.saveWidgetData<String>(
      WidgetKeys.sessionOk,
      sessionReady ? '1' : '0',
    );

    final configs = await WidgetConfigStore.loadAll();
    if (configs.isEmpty) return;

    if (!sessionReady) {
      // Sin sesión no se consulta nada: se marca error en cada instancia para
      // que el widget invite a abrir la app en lugar de mostrarse vacío.
      for (final config in configs) {
        if (onlyType != null && config.type != onlyType) continue;
        await _writeError(config, 'Inicia sesión en la app');
      }
      return;
    }

    // La tasa del dólar es global; se calcula una vez por ciclo.
    final usdRate = await _repository.fetchUsdRate();
    if (usdRate > 0) {
      await HomeWidget.saveWidgetData<String>(
        WidgetKeys.usdRate,
        usdRate.toStringAsFixed(2),
      );
    }

    for (final config in configs) {
      if (onlyType != null && config.type != onlyType) continue;
      await refreshOne(config, skipSessionCheck: true);
    }

    await HomeWidget.saveWidgetData<String>(
      WidgetKeys.lastSync,
      DateTime.now().toIso8601String(),
    );
  }

  /// Refresca una sola instancia.
  static Future<void> refreshOne(
    WidgetConfig config, {
    bool skipSessionCheck = false,
  }) async {
    if (!config.isConfigured) {
      await _writeState(config, WidgetKeys.stateUnconfigured);
      await _update(config.type);
      return;
    }

    if (!skipSessionCheck) {
      final ready = await WidgetHeadlessBootstrap.ensureReady();
      if (!ready) {
        await _writeError(config, 'Inicia sesión en la app');
        return;
      }
    }

    await _writeState(config, WidgetKeys.stateLoading);
    await _update(config.type);

    final snapshot = switch (config.type) {
      HomeWidgetType.miniDashboard =>
        await _repository.buildMiniDashboard(config),
      HomeWidgetType.sales => await _repository.buildSales(config),
      HomeWidgetType.product => await _repository.buildProduct(config),
    };

    if (snapshot.isError) {
      await _writeError(config, snapshot.error!);
      return;
    }

    for (final entry in snapshot.values.entries) {
      await HomeWidget.saveWidgetData<String>(
        config.type.keyFor(config.appWidgetId, entry.key),
        entry.value,
      );
    }

    await HomeWidget.saveWidgetData<String>(
      config.type.keyFor(config.appWidgetId, WidgetKeys.fieldStoreId),
      config.storeId?.toString() ?? '',
    );
    await HomeWidget.saveWidgetData<String>(
      config.type.keyFor(config.appWidgetId, WidgetKeys.fieldStoreName),
      config.storeName ?? '',
    );
    await HomeWidget.saveWidgetData<String>(
      config.type.keyFor(config.appWidgetId, WidgetKeys.fieldUpdatedAt),
      DateTime.now().toIso8601String(),
    );
    await HomeWidget.saveWidgetData<String>(
      config.type.keyFor(config.appWidgetId, WidgetKeys.fieldError),
      '',
    );
    await _writeState(config, WidgetKeys.stateOk);

    await _update(config.type);
  }

  /// Invierte el desplegado del desglose por TPV y redibuja.
  static Future<void> toggleSalesBreakdown(int appWidgetId) async {
    final config = await WidgetConfigStore.load(
      HomeWidgetType.sales,
      appWidgetId,
    );
    if (config == null) return;

    final updated = config.copyWith(expanded: !config.expanded);
    await WidgetConfigStore.save(updated);

    // Se reescribe solo el flag para que el despliegue sea instantáneo; los
    // datos ya están en las preferencias.
    await HomeWidget.saveWidgetData<String>(
      updated.type.keyFor(appWidgetId, WidgetKeys.fieldExpanded),
      updated.expanded ? '1' : '0',
    );
    await _update(HomeWidgetType.sales);

    // Al desplegar se aprovecha para refrescar en segundo plano.
    if (updated.expanded) {
      await refreshOne(updated);
    }
  }

  /// Limpia del registro las instancias que el usuario quitó del escritorio.
  static Future<void> pruneRemovedWidgets() async {
    try {
      final installed = await HomeWidget.getInstalledWidgets();
      final liveIds = installed
          .map((info) => info.androidWidgetId)
          .whereType<int>()
          .toSet();
      await WidgetConfigStore.pruneMissing(liveIds);
    } catch (error) {
      debugPrint('⚠️ Widgets: no se pudo listar los instalados: $error');
    }
  }

  /// ¿Hay al menos una instancia colocada en el escritorio?
  static Future<bool> hasInstalledWidgets() async {
    try {
      final installed = await HomeWidget.getInstalledWidgets();
      return installed.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Pide al lanzador que fije el widget en la pantalla de inicio (Android 8+).
  ///
  /// Devuelve `false` si el lanzador no lo soporta; en ese caso el usuario debe
  /// añadirlo manualmente desde el selector de widgets.
  static Future<bool> requestPin(HomeWidgetType type) async {
    try {
      final supported = await HomeWidget.isRequestPinWidgetSupported();
      if (supported != true) return false;
      await HomeWidget.requestPinWidget(
        androidName: type.androidProvider,
        qualifiedAndroidName: type.qualifiedAndroidName,
      );
      return true;
    } catch (error) {
      debugPrint('⚠️ Widgets: requestPinWidget falló: $error');
      return false;
    }
  }

  // ── Escrituras auxiliares ─────────────────────────────────────────────────

  static Future<void> _writeState(WidgetConfig config, String state) {
    return HomeWidget.saveWidgetData<String>(
      config.type.keyFor(config.appWidgetId, WidgetKeys.fieldState),
      state,
    );
  }

  static Future<void> _writeError(WidgetConfig config, String message) async {
    await HomeWidget.saveWidgetData<String>(
      config.type.keyFor(config.appWidgetId, WidgetKeys.fieldError),
      message,
    );
    await _writeState(config, WidgetKeys.stateError);
    await _update(config.type);
  }

  static Future<void> _update(HomeWidgetType type) async {
    try {
      await HomeWidget.updateWidget(
        androidName: type.androidProvider,
        qualifiedAndroidName: type.qualifiedAndroidName,
      );
    } catch (error) {
      debugPrint('⚠️ Widgets: updateWidget falló para ${type.label}: $error');
    }
  }
}
