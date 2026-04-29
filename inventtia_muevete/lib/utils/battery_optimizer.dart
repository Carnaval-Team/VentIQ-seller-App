import 'dart:io';

import 'package:flutter/services.dart';

/// Requests the system to disable battery optimization for this app.
/// This prevents Android (especially Samsung, Xiaomi, Huawei) from killing
/// the background service.
class BatteryOptimizer {
  static const _channel = MethodChannel('com.inventtia.muevete/battery');

  static Future<void> requestDisable() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      // Silently fail — not critical, just a UX improvement
    }
  }
}
