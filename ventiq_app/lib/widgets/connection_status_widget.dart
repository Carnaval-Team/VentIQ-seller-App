import 'package:flutter/material.dart';
import 'dart:async';
import '../services/smart_offline_manager.dart';

/// Widget que muestra el estado de conexión y sincronización.
/// En modo compacto, al tocarlo permite cambiar entre online/offline.
class ConnectionStatusWidget extends StatefulWidget {
  final bool showDetails;
  final bool compact;

  const ConnectionStatusWidget({
    Key? key,
    this.showDetails = false,
    this.compact = true,
  }) : super(key: key);

  @override
  State<ConnectionStatusWidget> createState() => _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<ConnectionStatusWidget> {
  final SmartOfflineManager _smartOfflineManager = SmartOfflineManager();

  StreamSubscription<SmartOfflineEvent>? _smartOfflineSubscription;
  SmartOfflineStatus? _status;
  bool _isLoading = true;
  bool _isSwitching = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _setupListeners();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadStatus(),
    );
  }

  @override
  void dispose() {
    _smartOfflineSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _smartOfflineManager.getStatus();
      if (mounted) {
        setState(() {
          _status = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando estado de conexión: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setupListeners() {
    _smartOfflineSubscription = _smartOfflineManager.eventStream.listen(
      (event) {
        print('📡 Evento SmartOffline: ${event.type} - ${event.message}');
        _loadStatus();
      },
      onError: (error) {
        print('❌ Error en stream SmartOffline: $error');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (_status == null) {
      return _buildErrorWidget();
    }

    if (widget.compact) {
      return _buildCompactWidget();
    } else {
      return _buildDetailedWidget();
    }
  }

  Widget _buildLoadingWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Cargando...',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 12, color: Colors.red[600]),
          const SizedBox(width: 6),
          Text(
            'Error',
            style: TextStyle(
              fontSize: 11,
              color: Colors.red[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWidget() {
    final status = _status!;

    Color backgroundColor;
    Color borderColor;
    Color iconColor;
    Color textColor;
    IconData icon;
    String text;

    if (status.isOfflineModeEnabled) {
      backgroundColor = Colors.orange[50]!;
      borderColor = Colors.orange[200]!;
      iconColor = Colors.orange[600]!;
      textColor = Colors.orange[700]!;
      icon = Icons.cloud_off;
      text = 'Offline';
    } else if (status.isConnected) {
      if (status.isAutoSyncRunning) {
        backgroundColor = Colors.green[50]!;
        borderColor = Colors.green[200]!;
        iconColor = Colors.green[600]!;
        textColor = Colors.green[700]!;
        icon = Icons.sync;
        text = 'Sincronizando';
      } else {
        backgroundColor = Colors.blue[50]!;
        borderColor = Colors.blue[200]!;
        iconColor = Colors.blue[600]!;
        textColor = Colors.blue[700]!;
        icon = Icons.wifi;
        text = 'Online';
      }
    } else {
      backgroundColor = Colors.red[50]!;
      borderColor = Colors.red[200]!;
      iconColor = Colors.red[600]!;
      textColor = Colors.red[700]!;
      icon = Icons.wifi_off;
      text = 'Sin conexión';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _isSwitching ? null : _showModeControlSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSwitching)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                )
              else
                Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.tune, size: 10, color: textColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedWidget({bool decorated = true}) {
    final status = _status!;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (decorated) ...[
          Row(
            children: [
              Icon(
                status.isConnected ? Icons.wifi : Icons.wifi_off,
                color: status.isConnected ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Estado de Conexión',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _buildStatusRow(
          'Conexión',
          status.isConnected ? 'Conectado' : 'Desconectado',
          status.isConnected ? Colors.green : Colors.red,
        ),
        _buildStatusRow(
          'Modo Offline',
          status.isOfflineModeEnabled ? 'Activado' : 'Desactivado',
          status.isOfflineModeEnabled ? Colors.orange : Colors.grey,
        ),
        _buildStatusRow(
          'Sincronización Auto',
          status.isAutoSyncRunning ? 'Ejecutándose' : 'Detenida',
          status.isAutoSyncRunning ? Colors.blue : Colors.grey,
        ),
        if (status.syncStats['lastSyncTime'] != null) ...[
          const SizedBox(height: 8),
          Text(
            'Última sincronización: ${_formatDateTime(DateTime.parse(status.syncStats['lastSyncTime']))}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(
            'Sincronizaciones: ${status.syncStats['syncCount']}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ],
    );

    if (!decorated) return content;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: content,
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showModeControlSheet() async {
    final status = _status;
    if (status == null || !mounted) return;

    final fullOffline = await _smartOfflineManager.isFullOfflinePrepared();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  status.isOfflineModeEnabled
                      ? 'Modo offline activo'
                      : 'Modo en línea',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status.isOfflineModeEnabled
                      ? 'Las ventas y turnos se guardan en el dispositivo. '
                          'Al volver a online se sincronizarán con el servidor.'
                      : 'La app usa el servidor. Si pierdes conexión, puedes '
                          'pasar a offline para seguir vendiendo.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                _buildDetailedWidget(decorated: false),
                if (fullOffline) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: const Text(
                      'Este dispositivo está preparado para full-offline. '
                      'Solo un administrador puede volver a modo en línea '
                      '(se eliminará esa preparación).',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (status.isOfflineModeEnabled)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _switchToOnline();
                    },
                    icon: const Icon(Icons.cloud_done_outlined),
                    label: const Text('Cambiar a modo en línea'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90E2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _switchToOffline();
                    },
                    icon: const Icon(Icons.cloud_off_outlined),
                    label: const Text('Cambiar a modo offline'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _switchToOffline() async {
    if (_isSwitching) return;
    setState(() => _isSwitching = true);
    try {
      final error = await _smartOfflineManager.enableOfflineModeFromUi();
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Modo offline activado'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      await _loadStatus();
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  Future<void> _switchToOnline() async {
    if (_isSwitching) return;
    setState(() => _isSwitching = true);
    try {
      var clearFullOffline = false;
      final fullOffline = await _smartOfflineManager.isFullOfflinePrepared();
      if (fullOffline) {
        final canAdmin =
            await _smartOfflineManager.canDisableFullOfflineAsAdmin();
        if (!canAdmin) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Solo el administrador puede desactivar el modo offline '
                  'en este dispositivo.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Volver a modo en línea'),
                content: const Text(
                  'Este dispositivo está preparado para trabajar 100% offline. '
                  'Al continuar se desactivará el modo offline y se eliminará '
                  'la preparación full-offline (habrá que volver a prepararla '
                  'si quieres reactivarla). ¿Deseas continuar?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sí, volver a online'),
                  ),
                ],
              ),
        );
        if (confirmed != true) return;
        clearFullOffline = true;
      }

      final error = await _smartOfflineManager.disableOfflineModeFromUi(
        clearFullOfflinePrep: clearFullOffline,
      );
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              clearFullOffline
                  ? 'Modo en línea activado. Se sincronizarán los pendientes.'
                  : 'Modo en línea activado. Sincronizando pendientes…',
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      await _loadStatus();
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Hace unos segundos';
    } else if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours}h';
    } else {
      return '${dateTime.day}/${dateTime.month} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}

/// Widget simple para mostrar solo el ícono de estado (también tappable).
class ConnectionStatusIcon extends StatefulWidget {
  const ConnectionStatusIcon({Key? key}) : super(key: key);

  @override
  State<ConnectionStatusIcon> createState() => _ConnectionStatusIconState();
}

class _ConnectionStatusIconState extends State<ConnectionStatusIcon> {
  @override
  Widget build(BuildContext context) {
    return const ConnectionStatusWidget(showDetails: true, compact: true);
  }
}
