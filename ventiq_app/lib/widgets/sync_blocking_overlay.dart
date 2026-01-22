import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auto_sync_service.dart';
import '../services/smart_offline_manager.dart';

class SyncBlockingOverlay extends StatefulWidget {
  final Widget child;

  const SyncBlockingOverlay({super.key, required this.child});

  @override
  State<SyncBlockingOverlay> createState() => _SyncBlockingOverlayState();
}

class _SyncBlockingOverlayState extends State<SyncBlockingOverlay> {
  final AutoSyncService _autoSyncService = AutoSyncService();
  final SmartOfflineManager _smartOfflineManager = SmartOfflineManager();

  StreamSubscription<AutoSyncEvent>? _syncSubscription;
  StreamSubscription<SmartOfflineEvent>? _smartSubscription;

  bool _pendingOfflineSync = false;
  bool _isVisible = false;
  String _detailMessage = 'Preparando sincronización...';

  @override
  void initState() {
    super.initState();
    _syncSubscription = _autoSyncService.syncEventStream.listen(_onSyncEvent);
    _smartSubscription = _smartOfflineManager.eventStream.listen(_onSmartEvent);
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _smartSubscription?.cancel();
    super.dispose();
  }

  void _onSmartEvent(SmartOfflineEvent event) {
    switch (event.type) {
      case SmartOfflineEventType.offlineModeAutoDeactivated:
      case SmartOfflineEventType.offlineModeManuallyDisabled:
        _detailMessage = 'Iniciando sincronización...';
        if (_autoSyncService.isSyncing && _pendingOfflineSync) {
          _isVisible = true;
          _pendingOfflineSync = false;
        }
        break;
      case SmartOfflineEventType.offlineModeAutoActivated:
      case SmartOfflineEventType.offlineModeManuallyEnabled:
      case SmartOfflineEventType.offlineModeActive:
      case SmartOfflineEventType.connectionRestoredWhileOffline:
        _pendingOfflineSync = true;
        _isVisible = false;
        break;
      default:
        return;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _onSyncEvent(AutoSyncEvent event) {
    switch (event.type) {
      case AutoSyncEventType.syncStarted:
        if (!_pendingOfflineSync) return;
        _isVisible = true;
        _pendingOfflineSync = false;
        _detailMessage = 'Iniciando sincronización...';
        break;
      case AutoSyncEventType.syncProgress:
        if (!_isVisible) return;
        _detailMessage = _formatProgressMessage(event.message);
        break;
      case AutoSyncEventType.syncCompleted:
      case AutoSyncEventType.syncFailed:
      case AutoSyncEventType.stopped:
        _isVisible = false;
        _pendingOfflineSync = false;
        break;
      case AutoSyncEventType.started:
        return;
    }

    if (mounted) {
      setState(() {});
    }
  }

  String _formatProgressMessage(String? message) {
    if (message == null || message.trim().isEmpty) {
      return 'Sincronizando datos...';
    }

    return 'Sincronizando: $message';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [widget.child, if (_isVisible) _buildOverlay(context)],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Stack(
          children: [
            Container(color: colorScheme.scrim.withOpacity(0.55)),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Material(
                  color: colorScheme.surface,
                  elevation: 12,
                  shadowColor: colorScheme.shadow.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary,
                                colorScheme.primaryContainer,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    colorScheme.onPrimary,
                                  ),
                                  backgroundColor: colorScheme.onPrimary
                                      .withOpacity(0.25),
                                ),
                              ),
                              Icon(
                                Icons.cloud_sync,
                                color: colorScheme.onPrimary,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sincronizando datos',
                          textAlign: TextAlign.center,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _detailMessage,
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'No cierres la app mientras sincroniza',
                                  textAlign: TextAlign.center,
                                  style: textTheme.labelMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
