import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auto_sync_service.dart';
import '../services/user_preferences_service.dart';

/// FAB que aparece solo cuando hay órdenes pendientes de sincronización.
/// Muestra un badge con el conteo y, al expandirse, un panel con la lista,
/// el último error por orden y acciones de reintentar / descartar.
class PendingOrdersFAB extends StatefulWidget {
  final VoidCallback? onSyncCompleted;

  const PendingOrdersFAB({Key? key, this.onSyncCompleted}) : super(key: key);

  @override
  State<PendingOrdersFAB> createState() => _PendingOrdersFABState();
}

class _PendingOrdersFABState extends State<PendingOrdersFAB>
    with TickerProviderStateMixin {
  final UserPreferencesService _userPrefs = UserPreferencesService();
  final AutoSyncService _autoSyncService = AutoSyncService();

  List<Map<String, dynamic>> _pendingOrders = [];
  bool _isExpanded = false;
  bool _isSyncing = false;
  String? _retryingOrderId;

  StreamSubscription<AutoSyncEvent>? _syncSubscription;
  Timer? _refreshTimer;

  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _loadPendingOrders();

    _syncSubscription = _autoSyncService.syncEventStream.listen((event) {
      if (!mounted) return;
      if (event.type == AutoSyncEventType.syncCompleted ||
          event.type == AutoSyncEventType.syncFailed) {
        // Dar un delay para que se limpie el almacenamiento local primero
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _loadPendingOrders();
        });
      } else if (event.type == AutoSyncEventType.syncStarted) {
        setState(() => _isSyncing = true);
      }
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadPendingOrders();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _refreshTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingOrders() async {
    // Vendedor: no listar órdenes de turnos closed_pending_sync (admin sync).
    final orders = await _userPrefs.getSellerVisiblePendingOrders();
    // Solo las que aún no se subieron al servidor
    final unsynced =
        orders.where((o) => o['synced'] != true).toList(growable: false);
    if (!mounted) return;
    setState(() {
      _pendingOrders = unsynced;
      _isSyncing = _autoSyncService.isSyncing;
      // Si ya no hay órdenes, cerrar el panel
      if (unsynced.isEmpty && _isExpanded) {
        _isExpanded = false;
        _animationController.reverse();
      }
    });
  }

  void _toggleExpansion() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _animationController.forward();
      _loadPendingOrders();
    } else {
      _animationController.reverse();
    }
  }

  /// Confirmación extra si el dispositivo está en offline / full offline.
  Future<bool> _confirmSyncIfOffline({required bool single}) async {
    final offline = await _userPrefs.isOfflineModeEnabled();
    final fullOffline = await _userPrefs.shouldStayFullyOffline();
    if (!offline && !fullOffline) return true;

    final modeLabel = fullOffline ? 'full offline' : 'offline';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizar en modo offline'),
        content: Text(
          single
              ? 'El dispositivo está en modo $modeLabel.\n\n'
                  'Al sincronizar esta orden se usará la conexión al servidor '
                  'solo para subirla y asignar el número de operación. '
                  'El modo offline se mantendrá activo.\n\n'
                  '¿Deseas continuar?'
              : 'El dispositivo está en modo $modeLabel.\n\n'
                  'Al sincronizar se usará la conexión al servidor para subir '
                  'las órdenes pendientes y actualizar su número de operación. '
                  'El modo offline se mantendrá activo.\n\n'
                  '¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _syncAll() async {
    if (_isSyncing) return;
    if (!await _confirmSyncIfOffline(single: false)) return;

    setState(() => _isSyncing = true);
    try {
      // Solo ventas pendientes; no apaga el modo offline (confirmado arriba).
      final synced = await _autoSyncService.forceSyncPendingOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              synced > 0
                  ? '$synced orden(es) sincronizada(s). Número de operación actualizado.'
                  : 'No había órdenes pendientes por sincronizar',
            ),
            backgroundColor: synced > 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ Error en sincronización forzada: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al sincronizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    // Dar tiempo para que se persista id_operacion / synced
    await Future.delayed(const Duration(milliseconds: 500));
    await _loadPendingOrders();
    widget.onSyncCompleted?.call();
    if (mounted) {
      setState(() => _isSyncing = false);
    }
  }

  Future<void> _retryOrder(String orderId) async {
    if (!await _confirmSyncIfOffline(single: true)) return;

    setState(() => _retryingOrderId = orderId);
    final success = await _autoSyncService.syncSinglePendingOrder(orderId);
    if (!mounted) return;
    setState(() => _retryingOrderId = null);

    // Dar tiempo para que se limpie el almacenamiento si fue exitoso
    if (success) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await _loadPendingOrders();
    widget.onSyncCompleted?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Orden sincronizada correctamente'
                : 'No se pudo sincronizar la orden',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _discardOrder(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();
    if (orderId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Descartar orden pendiente'),
            content: Text(
              '¿Deseas descartar esta orden? Esta acción no se puede deshacer y los datos se perderán.\n\nCliente: ${order['buyer_name'] ?? 'Sin nombre'}\nTotal: \$${_formatTotal(order['total'])}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Descartar'),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _userPrefs.discardPendingOrder(orderId);
      await _loadPendingOrders();
      widget.onSyncCompleted?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Orden descartada'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatTotal(dynamic total) {
    if (total == null) return '0.00';
    if (total is num) return total.toStringAsFixed(2);
    return total.toString();
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingOrders.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        AnimatedBuilder(
          animation: _expandAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _expandAnimation.value,
              alignment: Alignment.bottomRight,
              child: Opacity(
                opacity: _expandAnimation.value,
                child:
                    _isExpanded
                        ? _buildPendingPanel()
                        : const SizedBox.shrink(),
              ),
            );
          },
        ),
        _buildFabWithBadge(),
      ],
    );
  }

  Widget _buildFabWithBadge() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton(
          heroTag: 'pendingOrdersFab',
          onPressed: _toggleExpansion,
          backgroundColor: Colors.orange,
          child: AnimatedRotation(
            turns: _isExpanded ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _isExpanded ? Icons.close : Icons.sync_problem,
              color: Colors.white,
            ),
          ),
        ),
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 2),
            ),
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            child: Text(
              '${_pendingOrders.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingPanel() {
    return Container(
      margin: const EdgeInsets.only(right: 16, bottom: 80),
      width: 340,
      constraints: const BoxConstraints(maxHeight: 480),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_off, color: Colors.white, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pendientes (${_pendingOrders.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_isSyncing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  IconButton(
                    tooltip: 'Sincronizar todas',
                    onPressed: _syncAll,
                    icon: const Icon(Icons.cloud_upload, color: Colors.white),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _pendingOrders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = _pendingOrders[index];
                return _buildOrderItem(order);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Map<String, dynamic> order) {
    final orderId = order['id']?.toString() ?? '';
    final buyerName = order['buyer_name'] ?? order['buyerName'] ?? 'Sin nombre';
    final total = _formatTotal(order['total']);
    final createdAt = _formatDate(order['created_offline_at'] as String?);
    final lastError = order['last_sync_error'] as String?;
    final attempts = (order['sync_attempts'] as num?)?.toInt() ?? 0;
    final isRetrying = _retryingOrderId == orderId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buyerName.toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: $orderId',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$$total',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  if (createdAt.isNotEmpty)
                    Text(
                      createdAt,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                ],
              ),
            ],
          ),
          if (lastError != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Intentos: $attempts',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastError,
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: isRetrying ? null : () => _discardOrder(order),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Descartar', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: isRetrying ? null : () => _retryOrder(orderId),
                icon:
                    isRetrying
                        ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : const Icon(Icons.refresh, size: 16),
                label: const Text('Reintentar', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
