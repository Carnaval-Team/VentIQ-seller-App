import 'package:flutter/material.dart';
import 'dart:async';
import '../services/auto_sync_service.dart';

/// Widget global que muestra el estado de sincronización
/// Aparece como un chip flotante similar al del valor USD
class SyncStatusChip extends StatefulWidget {
  const SyncStatusChip({Key? key}) : super(key: key);

  @override
  State<SyncStatusChip> createState() => _SyncStatusChipState();
}

class _SyncStatusChipState extends State<SyncStatusChip> with SingleTickerProviderStateMixin {
  final AutoSyncService _autoSyncService = AutoSyncService();
  StreamSubscription<AutoSyncEvent>? _syncSubscription;
  
  bool _isSyncing = false;
  bool _isVisible = true;
  double _syncProgress = 0.0;
  String _syncMessage = 'Sincronizado';
  DateTime? _lastSyncTime;
  Timer? _autoHideTimer; // Timer para auto-ocultar
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    // Configurar animación de pulso
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _setupSyncListener();
    _checkInitialState();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _autoHideTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// Verificar estado inicial del servicio
  void _checkInitialState() {
    final isRunning = _autoSyncService.isRunning;
    final isSyncing = _autoSyncService.isSyncing;
    final lastSync = _autoSyncService.lastSyncTime;
    
    if (mounted) {
      setState(() {
        _isSyncing = isSyncing;
        _lastSyncTime = lastSync;
        if (!isSyncing && lastSync != null) {
          _syncProgress = 1.0;
          _syncMessage = 'Sincronizado';
        }
      });
    }
  }

  /// Configurar listener para eventos de sincronización
  void _setupSyncListener() {
    _syncSubscription = _autoSyncService.syncEventStream.listen((event) {
      if (!mounted) return;
      
      print('🔄 SyncStatusChip recibió evento: ${event.type} - ${event.message}');
      
      switch (event.type) {
        case AutoSyncEventType.started:
          setState(() {
            _isVisible = true;
            _isSyncing = false;
            _syncProgress = 0.0;
            _syncMessage = 'Iniciando...';
          });
          break;
          
        case AutoSyncEventType.syncStarted:
          // Cancelar timer de auto-ocultado si existe
          _autoHideTimer?.cancel();
          
          print('📊 SyncStatusChip: Mostrando widget - Sincronización iniciada');
          setState(() {
            _isVisible = true; // ✅ Asegurar que se muestre al iniciar sincronización
            _isSyncing = true;
            _syncProgress = 0.1;
            _syncMessage = 'Sincronizando...';
          });
          _pulseController.repeat(reverse: true);
          break;
          
        case AutoSyncEventType.syncProgress:
          final fraction = event.progressFraction;
          setState(() {
            _isVisible = true;
            _syncProgress = fraction ?? _calculateProgress(event.message);
            _syncMessage = event.message;
          });
          break;
          
        case AutoSyncEventType.syncCompleted:
          _pulseController.stop();
          _pulseController.reset();
          
          // Cancelar timer anterior si existe
          _autoHideTimer?.cancel();
          
          final partial = event.isPartial;
          print(
            partial
                ? '⚠️ SyncStatusChip: Sync parcial — Ocultando en 5s'
                : '✅ SyncStatusChip: Sincronización completada - Ocultando en 3s',
          );
          setState(() {
            _isSyncing = false;
            _syncProgress = 1.0;
            _syncMessage =
                partial
                    ? (event.message.length > 48
                        ? 'Parcial · ver detalle'
                        : event.message)
                    : 'Sincronizado';
            _lastSyncTime = event.timestamp;
          });
          
          _autoHideTimer = Timer(
            Duration(seconds: partial ? 5 : 3),
            () {
              if (mounted && !_isSyncing) {
                setState(() {
                  _isVisible = false;
                });
              }
            },
          );
          break;
          
        case AutoSyncEventType.syncFailed:
          _pulseController.stop();
          _pulseController.reset();
          _autoHideTimer?.cancel();
          setState(() {
            _isSyncing = false;
            _syncProgress = 0.0;
            _syncMessage =
                event.itemsSynced != null && event.itemsSynced!.isNotEmpty
                    ? 'Parcial con errores'
                    : 'Error en sincronización';
          });
          _autoHideTimer = Timer(const Duration(seconds: 5), () {
            if (mounted && !_isSyncing) {
              setState(() {
                _isVisible = false;
              });
            }
          });
          break;
          
        case AutoSyncEventType.stopped:
          _pulseController.stop();
          _pulseController.reset();
          setState(() {
            _isSyncing = false;
            _isVisible = false;
          });
          break;
      }
    });
  }

  /// Calcular progreso basado en el mensaje
  double _calculateProgress(String? message) {
    if (message == null) return 0.1;
    
    // Mapear mensajes a porcentajes de progreso
    if (message.contains('Credenciales')) return 0.2;
    if (message.contains('Promociones')) return 0.3;
    if (message.contains('Configuración')) return 0.4;
    if (message.contains('Métodos de pago')) return 0.5;
    if (message.contains('Categorías')) return 0.6;
    if (message.contains('Productos')) return 0.8;
    if (message.contains('Turno')) return 0.9;
    if (message.contains('completada')) return 1.0;
    
    return _syncProgress;
  }

  /// Obtener color según el estado
  Color _getStatusColor() {
    if (!_isSyncing && _syncProgress == 1.0) {
      return Colors.green;
    } else if (_isSyncing) {
      return Colors.blue;
    } else {
      return Colors.orange;
    }
  }

  /// Obtener icono según el estado
  IconData _getStatusIcon() {
    if (!_isSyncing && _syncProgress == 1.0) {
      return Icons.cloud_done;
    } else if (_isSyncing) {
      return Icons.cloud_sync;
    } else {
      return Icons.cloud_upload;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible) return const SizedBox.shrink();
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isSyncing ? _pulseAnimation.value : 1.0,
          child: child,
        );
      },
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _getStatusColor().withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono de estado
              Icon(
                _getStatusIcon(),
                size: 18,
                color: _getStatusColor(),
              ),
              const SizedBox(width: 8),
              
              // Contenido principal
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mensaje de estado
                  Text(
                    _isSyncing 
                        ? 'Sincronizando...' 
                        : _syncProgress == 1.0 
                            ? 'Sincronizado' 
                            : 'Preparando...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(),
                    ),
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Barra de progreso
                  SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _syncProgress,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getStatusColor(),
                            ),
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${(_syncProgress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(width: 8),
              
              // Botón de cerrar
              InkWell(
                onTap: () {
                  setState(() {
                    _isVisible = false;
                  });
                },
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
