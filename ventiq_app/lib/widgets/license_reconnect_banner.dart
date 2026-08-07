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

  Future<void> _refresh() async {
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

      final status = await _licenseService.validateLocalLicense(
        storeId: storeId,
      );

      final days = status.daysUntilForcedReconnect;
      final show = !status.isValid || (days != null && days <= 3);

      if (mounted) {
        setState(() {
          _status = status;
          _visible = show;
        });
      }

      // Bloqueo total: si la licencia no es válida y no estamos en
      // pantallas permitidas, redirigir a subscription-detail.
      if (!status.isValid) {
        final nav = globalNavigatorKey.currentState;
        final route = ModalRoute.of(globalNavigatorKey.currentContext ?? context)
            ?.settings
            .name;
        const allowed = {'/subscription-detail', '/login', '/'};
        if (nav != null && (route == null || !allowed.contains(route))) {
          nav.pushNamedAndRemoveUntil('/subscription-detail', (r) => false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _visible = false);
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
