import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'package:flutter_map/flutter_map.dart';

/// Mixin that provides smooth compass-based map rotation.
///
/// Uses a low-pass filter with circular averaging (sin/cos + atan2) to handle
/// the 359°→1° wraparound, throttles updates to ~12 FPS, and animates the
/// map rotation toward the target heading over ~200 ms.
///
/// Usage:
/// 1. Add `with SmoothCompassMixin` to your State class.
/// 2. Implement [compassMapController] to return your screen's MapController.
/// 3. Call [toggleAutoRotate] from your compass button.
/// 4. Call [disposeCompass] in your State's `dispose()`.
/// 5. Use [autoRotate] and [smoothHeading] in your build method.
mixin SmoothCompassMixin<T extends StatefulWidget> on State<T> {
  // ── Public state ──────────────────────────────────────────────────────────
  bool get autoRotate => _autoRotate;
  double get smoothHeading => _smoothHeading;

  /// Override in each screen to return the screen's [MapController].
  MapController get compassMapController;

  // ── Private state ─────────────────────────────────────────────────────────
  bool _autoRotate = false;
  double _smoothHeading = 0.0;

  // Low-pass filter accumulators (circular average via sin/cos)
  double _sinAcc = 0.0;
  double _cosAcc = 1.0;
  static const double _alpha = 0.15;

  // Throttle: minimum interval between map updates
  static const Duration _throttleInterval = Duration(milliseconds: 80);
  DateTime _lastUpdate = DateTime(0);

  // Animated rotation
  Timer? _animTimer;
  double _animFrom = 0.0;
  double _animTo = 0.0;
  int _animStep = 0;
  static const int _animSteps = 8; // ~200ms at 25ms per step
  static const Duration _animStepDuration = Duration(milliseconds: 25);

  StreamSubscription<CompassEvent>? _compassSub;

  // ── Public API ────────────────────────────────────────────────────────────

  void toggleAutoRotate() {
    setState(() {
      _autoRotate = !_autoRotate;
      if (_autoRotate) {
        _startCompass();
      } else {
        _stopCompass();
        _animTimer?.cancel();
        _animTimer = null;
        try {
          compassMapController.rotate(0);
        } catch (_) {}
      }
    });
  }

  /// Start compass with a specific initial state (e.g., for auto-enabling).
  void startCompassAutoRotate() {
    if (_autoRotate) return;
    setState(() {
      _autoRotate = true;
      _startCompass();
    });
  }

  void disposeCompass() {
    _compassSub?.cancel();
    _compassSub = null;
    _animTimer?.cancel();
    _animTimer = null;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _startCompass() {
    // Reset filter
    _sinAcc = 0.0;
    _cosAcc = 1.0;
    _lastUpdate = DateTime(0);

    _compassSub?.cancel();
    _compassSub = FlutterCompass.events?.listen(_onCompassEvent);
  }

  void _stopCompass() {
    _compassSub?.cancel();
    _compassSub = null;
  }

  void _onCompassEvent(CompassEvent event) {
    final h = event.heading;
    if (h == null || !mounted || !_autoRotate) return;

    // Low-pass filter using circular average
    final rad = h * pi / 180.0;
    _sinAcc = _sinAcc * (1 - _alpha) + sin(rad) * _alpha;
    _cosAcc = _cosAcc * (1 - _alpha) + cos(rad) * _alpha;
    final filteredRad = atan2(_sinAcc, _cosAcc);
    final filteredDeg = filteredRad * 180.0 / pi;
    // Normalize to [0, 360)
    final normalized = (filteredDeg + 360) % 360;

    // Throttle
    final now = DateTime.now();
    if (now.difference(_lastUpdate) < _throttleInterval) return;
    _lastUpdate = now;

    // Update smooth heading for marker rotation
    setState(() => _smoothHeading = normalized);

    // Animate map rotation toward -normalized
    _animateRotation(-normalized);
  }

  void _animateRotation(double targetRotation) {
    _animTimer?.cancel();

    try {
      _animFrom = compassMapController.camera.rotation;
    } catch (_) {
      _animFrom = 0.0;
    }
    _animTo = targetRotation;

    // Shortest path
    var diff = _animTo - _animFrom;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    _animTo = _animFrom + diff;

    // Skip animation if delta is tiny
    if (diff.abs() < 0.5) {
      try {
        compassMapController.rotate(_animTo);
      } catch (_) {}
      return;
    }

    _animStep = 0;
    _animTimer = Timer.periodic(_animStepDuration, (timer) {
      _animStep++;
      if (_animStep >= _animSteps || !mounted) {
        timer.cancel();
        try {
          compassMapController.rotate(_animTo);
        } catch (_) {}
        return;
      }
      final t = _animStep / _animSteps;
      // Ease-out quadratic
      final ease = 1 - (1 - t) * (1 - t);
      final rot = _animFrom + (_animTo - _animFrom) * ease;
      try {
        compassMapController.rotate(rot);
      } catch (_) {}
    });
  }
}
