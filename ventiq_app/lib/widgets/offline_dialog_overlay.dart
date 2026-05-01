import 'dart:async';
import 'package:flutter/material.dart';
import '../services/offline_dialog_service.dart';
import '../services/smart_offline_manager.dart';
import '../utils/global_navigator.dart';

/// Overlay global que escucha los eventos del SmartOfflineManager
/// y muestra los diálogos de confirmación al perder o restaurar la conexión.
///
/// Se monta en el `builder` de MaterialApp para estar disponible en cualquier ruta.
class OfflineDialogOverlay extends StatefulWidget {
  final Widget child;

  const OfflineDialogOverlay({super.key, required this.child});

  @override
  State<OfflineDialogOverlay> createState() => _OfflineDialogOverlayState();
}

class _OfflineDialogOverlayState extends State<OfflineDialogOverlay> {
  final SmartOfflineManager _manager = SmartOfflineManager();
  final OfflineDialogService _dialogService = OfflineDialogService();
  StreamSubscription<SmartOfflineEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _manager.eventStream.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _onEvent(SmartOfflineEvent event) async {
    switch (event.type) {
      case SmartOfflineEventType.connectionLostPendingConfirmation:
        await _showLostDialogLoop();
        break;
      case SmartOfflineEventType.connectionRestoredPendingConfirmation:
        await _showRestoredDialog();
        break;
      default:
        break;
    }
  }

  /// Muestra el diálogo de pérdida y, si "Reintentar" falla, lo vuelve a mostrar.
  Future<void> _showLostDialogLoop() async {
    while (true) {
      final result = await _dialogService.showConnectionLostDialog();

      if (result == null) {
        // Otro diálogo ya estaba abierto o no hay context
        return;
      }

      if (result == OfflineDialogResult.retry) {
        final ok = await _manager.userChoseRetry();
        if (ok) return;
        // Mostrar feedback breve antes de re-abrir el diálogo
        globalScaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('❌ Sin conexión. Inténtalo de nuevo.'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.redAccent,
          ),
        );
        // Pequeña pausa para que se vea el snackbar antes de reabrir
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }

      if (result == OfflineDialogResult.goOffline) {
        await _manager.userChoseOffline();
        return;
      }

      return;
    }
  }

  Future<void> _showRestoredDialog() async {
    final result = await _dialogService.showConnectionRestoredDialog();

    if (result == null) return;

    if (result == OnlineDialogResult.goOnline) {
      await _manager.userChoseGoOnline();
    } else if (result == OnlineDialogResult.stayOffline) {
      await _manager.userChoseStayOffline();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
