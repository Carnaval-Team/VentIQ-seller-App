import 'package:flutter/material.dart';
import '../utils/global_navigator.dart';

enum OfflineDialogResult { retry, goOffline }

enum OnlineDialogResult { goOnline, stayOffline }

class OfflineDialogService {
  static final OfflineDialogService _instance =
      OfflineDialogService._internal();
  factory OfflineDialogService() => _instance;
  OfflineDialogService._internal();

  bool _isLostDialogShowing = false;
  bool _isRestoredDialogShowing = false;

  bool get isAnyDialogShowing => _isLostDialogShowing || _isRestoredDialogShowing;

  Future<OfflineDialogResult?> showConnectionLostDialog({
    bool isRetrying = false,
  }) async {
    if (_isLostDialogShowing) {
      print('⚠️ OfflineDialogService: diálogo de pérdida ya está abierto');
      return null;
    }

    final ctx = globalNavigatorKey.currentContext;
    if (ctx == null) {
      print('❌ OfflineDialogService: no hay context disponible');
      return null;
    }

    _isLostDialogShowing = true;

    try {
      final result = await showDialog<OfflineDialogResult>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return _ConnectionLostDialog();
        },
      );
      return result;
    } finally {
      _isLostDialogShowing = false;
    }
  }

  Future<OnlineDialogResult?> showConnectionRestoredDialog() async {
    if (_isRestoredDialogShowing) {
      print('⚠️ OfflineDialogService: diálogo de restauración ya está abierto');
      return null;
    }

    final ctx = globalNavigatorKey.currentContext;
    if (ctx == null) {
      print('❌ OfflineDialogService: no hay context disponible');
      return null;
    }

    _isRestoredDialogShowing = true;

    try {
      final result = await showDialog<OnlineDialogResult>(
        context: ctx,
        barrierDismissible: false,
        builder: (dialogCtx) {
          return _ConnectionRestoredDialog();
        },
      );
      return result;
    } finally {
      _isRestoredDialogShowing = false;
    }
  }

  void closeLostDialog() {
    if (!_isLostDialogShowing) return;
    final navigator = globalNavigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    }
    _isLostDialogShowing = false;
  }
}

// ============================================================
// Tema visual compartido
// ============================================================

const Color _kBrandPrimary = Color(0xFF194B8C);
const Color _kWarning = Color(0xFFEF6C00);
const Color _kWarningDark = Color(0xFFC95400);
const Color _kSuccess = Color(0xFF2E7D32);
const Color _kSuccessDark = Color(0xFF1B5E20);

class _DialogShell extends StatelessWidget {
  final Color accentColor;
  final Color accentColorDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget body;
  final List<Widget> actions;

  const _DialogShell({
    required this.accentColor,
    required this.accentColorDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width < 480 ? media.size.width - 32 : 420.0;

    return WillPopScope(
      onWillPop: () async => false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header con gradiente + icono circular
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accentColor, accentColorDark],
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(icon, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                // Cuerpo
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: body,
                ),

                // Acciones
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(children: actions),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool loading;

  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withOpacity(0.55),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _SecondaryActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF455A64),
          side: const BorderSide(color: Color(0xFFCFD8DC), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _StatusInfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _StatusInfoChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Diálogo: Pérdida de conexión
// ============================================================

class _ConnectionLostDialog extends StatefulWidget {
  @override
  State<_ConnectionLostDialog> createState() => _ConnectionLostDialogState();
}

class _ConnectionLostDialogState extends State<_ConnectionLostDialog> {
  bool _isRetrying = false;

  Future<void> _onRetry() async {
    setState(() => _isRetrying = true);
    Navigator.of(context).pop(OfflineDialogResult.retry);
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      accentColor: _kWarning,
      accentColorDark: _kWarningDark,
      icon: Icons.signal_wifi_off_rounded,
      title: 'Sin conexión al servidor',
      subtitle: 'Verifica tu red o continúa trabajando sin conexión',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _StatusInfoChip(
            icon: Icons.info_outline_rounded,
            text:
                'Tus datos en cache siguen disponibles. Las ventas que hagas en modo offline se sincronizarán cuando vuelvas en línea.',
            color: _kWarningDark,
          ),
        ],
      ),
      actions: [
        _PrimaryActionButton(
          icon: Icons.refresh_rounded,
          label: 'Reintentar conexión',
          color: _kBrandPrimary,
          loading: _isRetrying,
          onPressed: _isRetrying ? null : _onRetry,
        ),
        const SizedBox(height: 10),
        _SecondaryActionButton(
          icon: Icons.cloud_off_rounded,
          label: 'Continuar en modo offline',
          onPressed: _isRetrying
              ? null
              : () => Navigator.of(context).pop(OfflineDialogResult.goOffline),
        ),
      ],
    );
  }
}

// ============================================================
// Diálogo: Conexión restaurada
// ============================================================

class _ConnectionRestoredDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      accentColor: _kSuccess,
      accentColorDark: _kSuccessDark,
      icon: Icons.cloud_done_rounded,
      title: 'Conexión restaurada',
      subtitle: 'Tu dispositivo volvió a estar en línea',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _StatusInfoChip(
            icon: Icons.sync_rounded,
            text:
                'Activa el modo en línea para sincronizar las operaciones pendientes y recibir datos actualizados.',
            color: _kSuccessDark,
          ),
        ],
      ),
      actions: [
        _PrimaryActionButton(
          icon: Icons.cloud_done_rounded,
          label: 'Activar modo en línea',
          color: _kSuccess,
          onPressed: () =>
              Navigator.of(context).pop(OnlineDialogResult.goOnline),
        ),
        const SizedBox(height: 10),
        _SecondaryActionButton(
          icon: Icons.cloud_off_rounded,
          label: 'Continuar offline',
          onPressed: () =>
              Navigator.of(context).pop(OnlineDialogResult.stayOffline),
        ),
      ],
    );
  }
}
