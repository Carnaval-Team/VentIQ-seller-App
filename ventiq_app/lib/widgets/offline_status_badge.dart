import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../services/auto_sync_service.dart';
import '../services/user_preferences_service.dart';

/// Badge compacto que muestra el estado del modo offline al usuario:
///   - 🟢 Online        : hay conexión y no se está sincronizando.
///   - 🔄 Sincronizando : sincronización en curso.
///   - 🟠 Offline       : sin conexión / modo offline activo.
/// Junto al estado muestra el número de elementos pendientes de sincronizar
/// (órdenes/operaciones/egresos), para que el usuario sepa qué falta enviar.
///
/// Pensado para colocarse en el `actions` de un AppBar.
class OfflineStatusBadge extends StatefulWidget {
  /// Si true, muestra también el texto del estado; si false, solo el icono.
  final bool showLabel;

  const OfflineStatusBadge({super.key, this.showLabel = true});

  @override
  State<OfflineStatusBadge> createState() => _OfflineStatusBadgeState();
}

enum _SyncUiState { online, syncing, offline }

class _OfflineStatusBadgeState extends State<OfflineStatusBadge> {
  final ConnectivityService _connectivity = ConnectivityService();
  final AutoSyncService _autoSync = AutoSyncService();
  final UserPreferencesService _prefs = UserPreferencesService();

  StreamSubscription<bool>? _connSub;
  StreamSubscription<AutoSyncEvent>? _syncSub;
  Timer? _pendingTimer;

  bool _isConnected = true;
  bool _isSyncing = false;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _isConnected = _connectivity.isConnected;

    _connSub = _connectivity.connectionStatusStream.listen((connected) {
      if (mounted) setState(() => _isConnected = connected);
    });

    _syncSub = _autoSync.syncEventStream.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event.type) {
          case AutoSyncEventType.syncStarted:
          case AutoSyncEventType.syncProgress:
            _isSyncing = true;
            break;
          case AutoSyncEventType.syncCompleted:
          case AutoSyncEventType.syncFailed:
          case AutoSyncEventType.stopped:
            _isSyncing = false;
            break;
          case AutoSyncEventType.started:
            break;
        }
      });
      _refreshPendingCount();
    });

    _refreshPendingCount();
    // Refrescar el contador periódicamente (creación de órdenes offline, etc.).
    _pendingTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshPendingCount(),
    );
  }

  Future<void> _refreshPendingCount() async {
    try {
      final orders = await _prefs.getPendingOrdersCount();
      final egresos = await _prefs.getEgresosOfflineCount();
      final ops = (await _prefs.getPendingOperations()).length;
      final total = orders + egresos + ops;
      if (mounted) setState(() => _pendingCount = total);
    } catch (_) {
      // Silencioso: el badge no debe romper la UI.
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _syncSub?.cancel();
    _pendingTimer?.cancel();
    super.dispose();
  }

  _SyncUiState get _state {
    if (_isSyncing) return _SyncUiState.syncing;
    if (!_isConnected) return _SyncUiState.offline;
    return _SyncUiState.online;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final Color color;
    final IconData icon;
    final String label;

    switch (state) {
      case _SyncUiState.online:
        color = Colors.green;
        icon = Icons.cloud_done;
        label = 'En línea';
        break;
      case _SyncUiState.syncing:
        color = Colors.blue;
        icon = Icons.sync;
        label = 'Sincronizando';
        break;
      case _SyncUiState.offline:
        color = Colors.orange;
        icon = Icons.cloud_off;
        label = 'Offline';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Tooltip(
        message:
            _pendingCount > 0
                ? '$label · $_pendingCount pendiente(s) de sincronizar'
                : label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state == _SyncUiState.syncing)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              Icon(icon, size: 18, color: color),
            if (widget.showLabel) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_pendingCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_pendingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
