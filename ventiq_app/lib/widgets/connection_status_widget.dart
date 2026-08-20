import 'package:flutter/material.dart';
import 'dart:async';
import '../services/smart_offline_manager.dart';
import '../services/connectivity_service.dart';
import '../services/auto_sync_service.dart';

/// Widget que muestra el estado de conexión y sincronización
/// Se puede usar en cualquier pantalla para mostrar información en tiempo real
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
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _setupListeners();
    // Red de seguridad: si algún cambio de modo offline/online no dispara un
    // evento de SmartOfflineManager (p.ej. al desactivarlo desde Ajustes),
    // este refresco periódico evita que el indicador quede desactualizado.
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
        _loadStatus(); // Recargar estado cuando hay cambios
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

    return GestureDetector(
      onTap: widget.showDetails ? _showDetailsDialog : null,
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
            if (widget.showDetails) ...[
              const SizedBox(width: 4),
              Icon(Icons.info_outline, size: 10, color: textColor),
            ],
          ],
        ),
      ),
    );
  }

  /// [decorated] controla si se envuelve en una tarjeta con borde propia.
  /// Cuando se muestra dentro de un [AlertDialog] esa tarjeta es redundante
  /// (el diálogo ya actúa como contenedor) y sólo resta espacio útil, así
  /// que ahí se pasa `false`.
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

  void _showDetailsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _status!.isConnected ? Icons.wifi : Icons.wifi_off,
              color: _status!.isConnected ? Colors.green : Colors.red,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text('Estado de Conexión'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          // No se reutiliza el Container con borde/fondo blanco de
          // `_buildDetailedWidget` (decorated=true): dentro del diálogo esa
          // tarjeta es redundante, deja espacio sin usar y provocaba
          // overflow por el padding duplicado. Aquí se pinta el contenido
          // directamente, con el título del diálogo como cabecera.
          child: _buildDetailedWidget(decorated: false),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
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

/// Widget simple para mostrar solo el ícono de estado
class ConnectionStatusIcon extends StatefulWidget {
  const ConnectionStatusIcon({Key? key}) : super(key: key);

  @override
  State<ConnectionStatusIcon> createState() => _ConnectionStatusIconState();
}

class _ConnectionStatusIconState extends State<ConnectionStatusIcon> {
  final SmartOfflineManager _smartOfflineManager = SmartOfflineManager();
  StreamSubscription<SmartOfflineEvent>? _subscription;
  Timer? _refreshTimer;
  bool _isConnected = true;
  bool _isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _setupListener();
    // Red de seguridad: ver comentario en _ConnectionStatusWidgetState.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadStatus(),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _smartOfflineManager.getStatus();
      if (mounted) {
        setState(() {
          _isConnected = status.isConnected;
          _isOfflineMode = status.isOfflineModeEnabled;
        });
      }
    } catch (e) {
      print('❌ Error cargando estado: $e');
    }
  }

  void _setupListener() {
    _subscription = _smartOfflineManager.eventStream.listen(
      (event) => _loadStatus(),
      onError: (error) => print('❌ Error en listener: $error'),
    );
  }

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    if (_isOfflineMode) {
      icon = Icons.cloud_off;
      color = Colors.orange;
    } else if (_isConnected) {
      icon = Icons.wifi;
      color = Colors.green;
    } else {
      icon = Icons.wifi_off;
      color = Colors.red;
    }

    return Icon(icon, color: color, size: 20);
  }
}
