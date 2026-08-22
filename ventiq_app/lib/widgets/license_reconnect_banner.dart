import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../services/offline_license_service.dart';
import '../services/store_config_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/global_navigator.dart';

/// Banner con cuenta regresiva para reconectar y revalidar la licencia.
/// Visible cuando el modo offline completo está activo y quedan ≤ 3 días.
class LicenseReconnectBanner extends StatefulWidget {
  const LicenseReconnectBanner({super.key});

  @override
  State<LicenseReconnectBanner> createState() => _LicenseReconnectBannerState();
}

class _LicenseReconnectBannerState extends State<LicenseReconnectBanner> {
  final OfflineLicenseService _licenseService = OfflineLicenseService();
  final UserPreferencesService _prefs = UserPreferencesService();
  final ConnectivityService _connectivity = ConnectivityService();

  StreamSubscription<bool>? _connectivitySub;
  Timer? _refreshTimer;

  OfflineLicenseStatus? _status;
  bool _visible = false;
  bool _refreshInFlight = false;
  DateTime? _lastOnlineFetchAt;

  static const _onlineFetchThrottle = Duration(minutes: 10);
  static const _allowedRoutes = {
    '/subscription-detail',
    '/login',
    '/login-mobile',
    '/login-web',
    '/',
  };

  @override
  void initState() {
    super.initState();
    _refresh();
    _connectivitySub = _connectivity.connectionStatusStream.listen((_) {
      _refresh();
    });
    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool _shouldForceOnlineRefresh() {
    if (!_connectivity.isConnected) return false;
    final last = _lastOnlineFetchAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _onlineFetchThrottle;
  }

  /// Ruta nombrada actual del navigator raíz. Null si no se puede determinar.
  String? _currentRouteName() {
    final nav = globalNavigatorKey.currentState;
    if (nav == null) return null;

    String? name;
    nav.popUntil((route) {
      name = route.settings.name;
      return true; // no pop
    });
    return name;
  }

  Future<void> _refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final storeId = await _prefs.getIdTienda();
      if (storeId == null) {
        if (mounted) setState(() => _visible = false);
        return;
      }

      final permitido =
          await StoreConfigService.getPermitirModoOfflineCompleto(storeId);
      if (!permitido) {
        if (mounted) setState(() => _visible = false);
        return;
      }

      final forceOnline = _shouldForceOnlineRefresh();
      if (forceOnline) {
        _lastOnlineFetchAt = DateTime.now();
      }

      // Nunca bloquear por fallo transitorio de fetch si la licencia local
      // sigue válida (requireOnlineSuccess: false).
      final status = await _licenseService.validate(
        storeId: storeId,
        forceOnlineRefresh: forceOnline,
        requireOnlineSuccess: false,
      );

      final days = status.daysUntilForcedReconnect;
      final show = !status.isValid || (days != null && days <= 3);

      if (mounted) {
        setState(() {
          _status = status;
          _visible = show;
        });
      }

      // Bloqueo total solo con licencia inválida y ruta conocida fuera de
      // las permitidas. Si route == null, no redirigir (evita bounce).
      if (!status.isValid) {
        final nav = globalNavigatorKey.currentState;
        final route = _currentRouteName();
        if (nav != null &&
            route != null &&
            !_allowedRoutes.contains(route)) {
          nav.pushNamedAndRemoveUntil('/subscription-detail', (r) => false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _visible = false);
    } finally {
      _refreshInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _status == null) {
      return const SizedBox.shrink();
    }

    final status = _status!;
    final days = status.daysUntilForcedReconnect;
    final isBlocked = !status.isValid;

    final Color bg =
        isBlocked
            ? Colors.red.shade700
            : (days != null && days <= 1
                ? Colors.orange.shade800
                : Colors.deepPurple.shade700);

    final String text;
    if (isBlocked) {
      text = status.message;
    } else if (days == null) {
      text = 'Conéctate pronto para revalidar la licencia';
    } else if (days <= 0) {
      text = 'Debes conectarte hoy para revalidar la licencia';
    } else {
      text =
          'Debes conectarte en $days día${days == 1 ? '' : 's'} '
          'para revalidar la licencia';
    }

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: () {
            globalNavigatorKey.currentState?.pushNamed('/subscription-detail');
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: bg,
            child: Row(
              children: [
                Icon(
                  isBlocked ? Icons.lock : Icons.wifi_off,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
