import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import 'data/widget_config_store.dart';
import 'home_widget_service.dart';
import 'widget_keys.dart';

/// Nombre único de la tarea periódica que refresca los widgets.
const String kWidgetRefreshTask = 'vq_home_widget_refresh';

/// Punto de entrada de WorkManager. Debe ser una función top-level anotada con
/// `vm:entry-point` para que sobreviva al tree-shaking en release.
@pragma('vm:entry-point')
void widgetWorkmanagerDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != kWidgetRefreshTask) return true;
    try {
      await HomeWidgetService.refreshAll();
      return true;
    } catch (error) {
      debugPrint('❌ Widgets: refresco periódico falló: $error');
      // Devolver true evita el backoff agresivo: el siguiente ciclo reintenta.
      return true;
    }
  });
}

/// Callback que ejecuta home_widget cuando se toca un control del widget
/// (botón "Ver TPVs"). Corre en un isolate headless propio.
@pragma('vm:entry-point')
Future<void> widgetInteractivityCallback(Uri? uri) async {
  if (uri == null) return;

  final type = HomeWidgetType.fromPrefix(uri.queryParameters['type'] ?? '');
  final appWidgetId = int.tryParse(uri.queryParameters['id'] ?? '');
  if (type == null || appWidgetId == null) return;

  switch (uri.host) {
    case WidgetKeys.hostToggle:
      await HomeWidgetService.toggleSalesBreakdown(appWidgetId);
      break;
    case WidgetKeys.hostRefresh:
      final config = await WidgetConfigStore.load(type, appWidgetId);
      if (config != null) {
        await HomeWidgetService.refreshOne(config);
      }
      break;
  }
}

/// Registro del refresco en background y de la interactividad.
///
/// Se llama una sola vez desde `main()`. Android impone un mínimo de 15 minutos
/// para el trabajo periódico, así que ese es el intervalo real más agresivo
/// posible para el modo "Tiempo Real".
class WidgetBackgroundScheduler {
  WidgetBackgroundScheduler._();

  static const Duration _frequency = Duration(minutes: 15);

  static Future<void> initialize() async {
    try {
      await HomeWidget.registerInteractivityCallback(
        widgetInteractivityCallback,
      );
    } catch (error) {
      debugPrint('⚠️ Widgets: no se pudo registrar la interactividad: $error');
    }

    try {
      await Workmanager().initialize(widgetWorkmanagerDispatcher);
    } catch (error) {
      debugPrint('⚠️ Widgets: no se pudo inicializar WorkManager: $error');
      return;
    }

    await schedulePeriodicRefresh();
  }

  /// Programa (o reprograma) el refresco periódico.
  static Future<void> schedulePeriodicRefresh() async {
    try {
      await Workmanager().registerPeriodicTask(
        kWidgetRefreshTask,
        kWidgetRefreshTask,
        frequency: _frequency,
        initialDelay: const Duration(minutes: 1),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (error) {
      debugPrint('⚠️ Widgets: no se pudo programar el refresco: $error');
    }
  }

  /// Cancela el refresco (p. ej. al cerrar sesión).
  static Future<void> cancelPeriodicRefresh() async {
    try {
      await Workmanager().cancelByUniqueName(kWidgetRefreshTask);
    } catch (error) {
      debugPrint('⚠️ Widgets: no se pudo cancelar el refresco: $error');
    }
  }
}
