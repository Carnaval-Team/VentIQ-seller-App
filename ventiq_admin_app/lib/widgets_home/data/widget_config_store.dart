import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/widget_config.dart';
import '../widget_keys.dart';

/// Registro de las instancias de widget configuradas.
///
/// Vive en las SharedPreferences normales de la app (no en las de home_widget)
/// porque es estado de la app, no datos que pinten los widgets. Guardar aquí la
/// configuración permite que el refresco en background sepa qué recargar sin
/// tener que leer las preferencias nativas del plugin.
class WidgetConfigStore {
  WidgetConfigStore._();

  static const String _registryKey = 'vq_home_widget_registry';

  /// Marca de que el usuario ya vio el tutorial de widgets.
  static const String _tutorialSeenKey = 'vq_home_widget_tutorial_seen';

  /// Devuelve todas las configuraciones guardadas.
  static Future<List<WidgetConfig>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_registryKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(WidgetConfig.fromJson)
          .whereType<WidgetConfig>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<WidgetConfig?> load(HomeWidgetType type, int appWidgetId) async {
    final all = await loadAll();
    for (final config in all) {
      if (config.type == type && config.appWidgetId == appWidgetId) {
        return config;
      }
    }
    return null;
  }

  /// Inserta o reemplaza una configuración (clave: tipo + appWidgetId).
  static Future<void> save(WidgetConfig config) async {
    final all = await loadAll();
    final updated = <WidgetConfig>[
      for (final existing in all)
        if (!(existing.type == config.type &&
            existing.appWidgetId == config.appWidgetId))
          existing,
      config,
    ];
    await _persist(updated);
  }

  static Future<void> remove(HomeWidgetType type, int appWidgetId) async {
    final all = await loadAll();
    final updated = all
        .where(
          (config) =>
              !(config.type == type && config.appWidgetId == appWidgetId),
        )
        .toList();
    await _persist(updated);
  }

  /// Elimina del registro las instancias que ya no existen en el escritorio.
  static Future<void> pruneMissing(Set<int> liveAppWidgetIds) async {
    final all = await loadAll();
    final updated = all
        .where((config) => liveAppWidgetIds.contains(config.appWidgetId))
        .toList();
    if (updated.length != all.length) {
      await _persist(updated);
    }
  }

  static Future<void> _persist(List<WidgetConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(configs.map((c) => c.toJson()).toList());
    await prefs.setString(_registryKey, payload);
  }

  static Future<bool> hasSeenTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_tutorialSeenKey) ?? false;
  }

  static Future<void> markTutorialSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tutorialSeenKey, true);
  }

  /// Permite volver a mostrar el tutorial desde Ajustes.
  static Future<void> resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tutorialSeenKey);
  }
}
