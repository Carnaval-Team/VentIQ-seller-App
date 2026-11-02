import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/turno_service.dart';
import '../theme/ventiq_home_theme.dart';

/// Widget de notificaciones que se muestra en la parte superior
class NotificationWidget extends StatefulWidget {
  const NotificationWidget({Key? key}) : super(key: key);

  @override
  State<NotificationWidget> createState() => _NotificationWidgetState();
}

class _NotificationWidgetState extends State<NotificationWidget> {
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    // Configurar locale español para timeago
    timeago.setLocaleMessages('es', timeago.EsMessages());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _notificationService.unreadCountStream,
      initialData: _notificationService.unreadCount,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Stack(
          children: [
            // Botón de notificaciones
            IconButton(
              icon: Icon(
                unreadCount > 0
                    ? Icons.notifications_active
                    : Icons.notifications_outlined,
                color: Colors.white,
              ),
              onPressed: () {
                _showNotificationsPanel(context);
              },
            ),
            // Badge de contador
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: VentiqHomeTheme.danger,
                    shape: BoxShape.circle,
                    boxShadow: VentiqHomeTheme.shadowCard,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Mostrar panel de notificaciones
  void _showNotificationsPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationsPanel(),
    );
  }
}

/// Panel de notificaciones
class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel({Key? key}) : super(key: key);

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  final NotificationService _notificationService = NotificationService();
  bool _showOnlyUnread = false;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: VentiqHomeTheme.card,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(VentiqHomeTheme.radiusBlock),
            ),
            border: Border.all(color: VentiqHomeTheme.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x142B3A67),
                blurRadius: 24,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              _buildHeader(),
              const Divider(height: 1, color: VentiqHomeTheme.border),
              // Lista de notificaciones
              Expanded(
                child: StreamBuilder<List<NotificationModel>>(
                  stream: _notificationService.notificationsStream,
                  initialData: _notificationService.notifications,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return _buildEmptyState();
                    }

                    var notifications = snapshot.data!;

                    // Filtrar por no leídas si está activado
                    if (_showOnlyUnread) {
                      notifications =
                          notifications.where((n) => !n.leida).toList();
                    }

                    if (notifications.isEmpty) {
                      return _buildEmptyState();
                    }

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: notifications.length,
                      separatorBuilder:
                          (context, index) => const Divider(
                            height: 1,
                            color: VentiqHomeTheme.border,
                          ),
                      itemBuilder: (context, index) {
                        return NotificationItem(
                          notification: notifications[index],
                          notificationService: _notificationService,
                          onTap:
                              () =>
                                  _handleNotificationTap(notifications[index]),
                          onDismiss:
                              () => _handleNotificationDismiss(
                                notifications[index],
                              ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Header del panel
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: VentiqHomeTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.notifications_active,
              color: VentiqHomeTheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Notificaciones',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
          ),
          const Spacer(),
          // Filtro de no leídas
          StreamBuilder<int>(
            stream: _notificationService.unreadCountStream,
            initialData: _notificationService.unreadCount,
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;
              if (unreadCount == 0) return const SizedBox.shrink();

              return FilterChip(
                label: Text('No leídas ($unreadCount)'),
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      _showOnlyUnread
                          ? VentiqHomeTheme.primary
                          : VentiqHomeTheme.textSecondary,
                ),
                selected: _showOnlyUnread,
                onSelected: (value) {
                  setState(() {
                    _showOnlyUnread = value;
                  });
                },
                backgroundColor: VentiqHomeTheme.card,
                selectedColor: VentiqHomeTheme.primary.withValues(alpha: 0.12),
                checkmarkColor: VentiqHomeTheme.primary,
                side: BorderSide(
                  color:
                      _showOnlyUnread
                          ? VentiqHomeTheme.primary.withValues(alpha: 0.30)
                          : VentiqHomeTheme.border,
                ),
                visualDensity: VisualDensity.compact,
              );
            },
          ),
          const SizedBox(width: 4),
          // Botón marcar todas como leídas
          IconButton(
            icon: const Icon(Icons.done_all, color: VentiqHomeTheme.success),
            tooltip: 'Marcar todas como leídas',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await _notificationService.markAllAsRead();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '✅ Todas las notificaciones marcadas como leídas',
                    ),
                    backgroundColor: VentiqHomeTheme.success,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// Estado vacío
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: VentiqHomeTheme.primary.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _showOnlyUnread
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_none,
              size: 42,
              color: VentiqHomeTheme.primary.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _showOnlyUnread
                ? 'No hay notificaciones sin leer'
                : 'No hay notificaciones',
            style: const TextStyle(
              fontSize: 16,
              color: VentiqHomeTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _showOnlyUnread
                ? 'Todas tus notificaciones están al día'
                : 'Aquí aparecerán tus notificaciones',
            style: const TextStyle(
              fontSize: 13,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Manejar tap en notificación
  void _handleNotificationTap(NotificationModel notification) async {
    // Marcar como leída si no lo está
    if (!notification.leida) {
      await _notificationService.markAsRead(notification.id);
    }

    // Ejecutar acción si existe
    if (notification.accion != null && notification.accion!.isNotEmpty) {
      // Aquí puedes implementar navegación según la acción
      print('🎯 Acción: ${notification.accion}');
      // Navigator.of(context).pushNamed(notification.accion!);
    }
  }

  /// Manejar deslizar para eliminar
  void _handleNotificationDismiss(NotificationModel notification) async {
    await _notificationService.deleteNotification(notification.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🗑️ Notificación eliminada'),
          backgroundColor: VentiqHomeTheme.textPrimary,
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Deshacer',
            textColor: Colors.white,
            onPressed: () {
              // Aquí podrías implementar lógica de deshacer
            },
          ),
        ),
      );
    }
  }
}

/// Item individual de notificación con funcionalidad de acordeón
class NotificationItem extends StatefulWidget {
  final NotificationModel notification;
  final NotificationService notificationService;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const NotificationItem({
    Key? key,
    required this.notification,
    required this.notificationService,
    required this.onTap,
    required this.onDismiss,
  }) : super(key: key);

  @override
  State<NotificationItem> createState() => _NotificationItemState();
}

class _NotificationItemState extends State<NotificationItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.notification.getColor();
    final icon = widget.notification.getIcon();

    return Dismissible(
      key: Key('notification_${widget.notification.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDismiss(),
      background: Container(
        color: VentiqHomeTheme.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
          // Marcar como leída al expandir
          if (!_isExpanded && !widget.notification.leida) {
            widget.onTap();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color:
              widget.notification.leida
                  ? VentiqHomeTheme.card
                  : VentiqHomeTheme.primary.withValues(alpha: 0.04),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icono
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 12),
              // Contenido
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título y badge de prioridad
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.notification.titulo,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  widget.notification.leida
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                              color: VentiqHomeTheme.textPrimary,
                            ),
                            maxLines: _isExpanded ? null : 2,
                            overflow:
                                _isExpanded ? null : TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.notification.isUrgent)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: VentiqHomeTheme.danger,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'URGENTE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Mensaje con animación de expansión
                    AnimatedCrossFade(
                      firstChild: Text(
                        widget.notification.mensaje,
                        style: TextStyle(
                          fontSize: 14,
                          color: VentiqHomeTheme.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      secondChild: Text(
                        widget.notification.mensaje,
                        style: TextStyle(
                          fontSize: 14,
                          color: VentiqHomeTheme.textSecondary,
                          height: 1.3,
                        ),
                      ),
                      crossFadeState:
                          _isExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 300),
                    ),
                    const SizedBox(height: 6),
                    // Tiempo, estado e indicador de expansión
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: VentiqHomeTheme.textSecondary.withValues(
                            alpha: 0.8,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeago.format(
                            widget.notification.createdAt,
                            locale: 'es',
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: VentiqHomeTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Indicador de expansión
                        Icon(
                          _isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: VentiqHomeTheme.primary,
                        ),
                        Text(
                          _isExpanded ? 'Ver menos' : 'Ver más',
                          style: const TextStyle(
                            fontSize: 11,
                            color: VentiqHomeTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (!widget.notification.leida)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: VentiqHomeTheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    // Botón "Recibir Orden" para notificaciones tipo venta
                    if (_isExpanded && _shouldShowReceiveOrderButton())
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _handleReceiveOrder,
                            icon: const Icon(
                              Icons.check_circle_outline,
                              size: 20,
                            ),
                            label: const Text(
                              'Recibir Orden',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: VentiqHomeTheme.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
    );
  }

  /// Determinar si se debe mostrar el botón "Recibir Orden"
  bool _shouldShowReceiveOrderButton() {
    // Solo para notificaciones tipo "venta" y no leídas
    if (widget.notification.tipo != NotificationType.venta ||
        widget.notification.leida) {
      return false;
    }

    // Verificar que tenga data con orden_id y operacion_id
    final data = widget.notification.data;
    if (data == null) return false;

    final ordenId = data['orden_id'];
    final operacionId = data['operacion_id'];

    return ordenId != null && operacionId != null;
  }

  /// Manejar acción de "Recibir Orden"
  Future<void> _handleReceiveOrder() async {
    try {
      final data = widget.notification.data;
      if (data == null) return;

      final operacionId = data['operacion_id'];
      if (operacionId == null) {
        _showErrorMessage('No se encontró el ID de operación');
        return;
      }

      // Mostrar indicador de carga
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const Center(
              child: CircularProgressIndicator(
                valueColor: const AlwaysStoppedAnimation<Color>(
                  VentiqHomeTheme.success,
                ),
              ),
            ),
      );

      // 1. Verificar si el usuario tiene un turno abierto
      final turnoAbierto = await TurnoService.getTurnoAbierto();

      if (turnoAbierto == null) {
        if (mounted) Navigator.pop(context); // Cerrar loading
        _showErrorMessage('No tienes un turno abierto');
        return;
      }

      final fechaTurno = DateTime.parse(
        turnoAbierto['fecha_apertura'] as String,
      );

      // 2. Obtener la operación y verificar su fecha de creación
      final supabase = Supabase.instance.client;
      final operacionResponse =
          await supabase
              .from('app_dat_operaciones')
              .select('created_at')
              .eq('id', operacionId)
              .single();

      final fechaOperacion = DateTime.parse(
        operacionResponse['created_at'] as String,
      );

      // 2.5 Verificar que el último estado de la operación sea 1 (pendiente)
      final estadoResponse = await supabase
          .from('app_dat_estado_operacion')
          .select('estado')
          .eq('id_operacion', operacionId)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      final ultimoEstado = estadoResponse?['estado'] as int?;
      if (ultimoEstado != null && ultimoEstado != 1) {
        if (mounted) Navigator.pop(context); // Cerrar loading
        _showErrorMessage(
          'Esta orden ya fue procesada (estado: $ultimoEstado) y no se puede recibir',
        );
        return;
      }

      // 3. Validar que la fecha de creación de la operación sea menor que la del turno
      if (!fechaOperacion.isBefore(fechaTurno)) {
        // if (mounted) Navigator.pop(context); // Cerrar loading
        print(
          'La operación fue creada después del turno actual. No se puede recibir.',
        );
      } else {
        // 4. Actualizar la fecha de creación de la operación a now()
        await supabase
            .from('app_dat_operaciones')
            .update({'created_at': DateTime.now().toIso8601String()})
            .eq('id', operacionId);
      }
      // 5. Marcar la notificación como leída
      await widget.notificationService.markAsRead(widget.notification.id);

      // Refrescar la lista de notificaciones para actualizar la vista

      if (mounted) {
        Navigator.pop(context); // Cerrar loading

        // Mostrar mensaje de éxito
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Orden recibida exitosamente'),
            backgroundColor: VentiqHomeTheme.success,
            duration: Duration(seconds: 3),
          ),
        );

        await widget.notificationService.loadNotifications();
        // Colapsar el item
        setState(() {
          _isExpanded = false;
        });
      }
    } catch (e) {
      print('❌ Error recibiendo orden: $e');
      if (mounted) {
        Navigator.pop(context); // Cerrar loading si está abierto
        _showErrorMessage('Error al recibir la orden: ${e.toString()}');
      }
    }
  }

  /// Mostrar mensaje de error
  void _showErrorMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $message'),
        backgroundColor: VentiqHomeTheme.danger,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
