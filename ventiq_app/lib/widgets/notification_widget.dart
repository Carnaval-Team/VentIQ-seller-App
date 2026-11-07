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

  /// Lado del área que responde al toque (56×56).
  ///
  /// Los 48×48 de un `IconButton` son el mínimo de Material y en un TPV se
  /// quedan cortos: la campana se pulsa de pie, a veces con guantes y casi
  /// siempre de paso hacia el buscador. 56 sigue el mínimo recomendado por
  /// guías de accesibilidad táctil (48 lógicos) con margen para el error.
  static const double _kTapTarget = 56;

  /// Lienzo visible de la campana (48×48), el mismo que ocupaba el
  /// `IconButton` anterior.
  ///
  /// Se conserva para que el icono (24) y el badge (desplazado 8/8 sobre este
  /// lienzo) mantengan exactamente la composición de antes: los 8 px extra del
  /// objetivo táctil se reparten como padding alrededor, no dentro del dibujo.
  static const double _kVisualCanvas = 48;

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

        // El objetivo táctil es el CONJUNTO campana + contador, no un
        // `IconButton` suelto: un `InkWell` opaco cubre los 56×56 completos.
        //
        // Lo que fallaba antes: el badge era hermano del `IconButton` dentro
        // del `Stack` y, al pintarse después, se quedaba con los toques de su
        // esquina. El `Text` del contador absorbe el hit test
        // (`RenderParagraph.hitTestSelf` devuelve siempre `true`), así que
        // pulsar justo sobre el número —lo más llamativo del control— no abría
        // nada y había que «buscar» el borde del icono.
        return Semantics(
          // Un único nodo para el lector de pantalla: `container` + `button`
          // aportan etiqueta y rol, y el `Semantics(onTap:)` del `InkWell` se
          // fusiona aquí dentro en vez de crear un segundo botón (sería doble
          // anuncio y dos destinos de foco para un solo control).
          container: true,
          button: true,
          label:
              unreadCount > 0
                  ? 'Notificaciones, $unreadCount sin leer'
                  : 'Notificaciones',
          child: Material(
            // Sólo para que el ripple del `InkWell` se pinte ENCIMA del
            // degradado de la cabecera: sin un `Material` propio el splash
            // quedaría detrás del fondo y no se vería. Es transparente, en
            // reposo no pinta nada.
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => _showNotificationsPanel(context),
              // El ripple circular es la única pista visual del tamaño real
              // del botón; el resto del aspecto no cambia.
              customBorder: const CircleBorder(),
              splashColor: Colors.white.withValues(alpha: 0.16),
              highlightColor: Colors.white.withValues(alpha: 0.08),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              focusColor: Colors.white.withValues(alpha: 0.12),
              child: SizedBox(
                width: _kTapTarget,
                height: _kTapTarget,
                // El lienzo visible sigue siendo 48×48 con el icono de 24: el
                // `Center` convierte los 8 px extra en padding interno, no en
                // un icono mayor ni en un badge desplazado.
                child: Center(
                  child: SizedBox(
                    width: _kVisualCanvas,
                    height: _kVisualCanvas,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        _buildBell(unreadCount > 0),
                        if (unreadCount > 0) _buildUnreadBadge(unreadCount),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Icono de la campana.
  ///
  /// Sin `size`: hereda el `IconTheme` (24), igual que hacía el `IconButton`
  /// sustituido. El color sigue siendo blanco sobre el degradado.
  Widget _buildBell(bool hasUnread) {
    return Icon(
      hasUnread ? Icons.notifications_active : Icons.notifications_outlined,
      color: Colors.white,
    );
  }

  /// Contador de no leídas, sobre la esquina superior derecha del icono.
  ///
  /// Devuelve un [Positioned], así que sólo vale como hijo directo del `Stack`
  /// del botón. Los 8/8 son los mismos de siempre: se miden sobre el lienzo de
  /// 48, de modo que el badge no se mueve respecto al icono.
  ///
  /// * `IgnorePointer`: el badge es decoración sobre el botón, no un control
  ///   aparte; sin esto se quedaba con los toques de su esquina y esa zona
  ///   dejaba de abrir el panel.
  /// * `ExcludeSemantics`: el lector ya anuncia la cuenta en el `label` del
  ///   botón; dejar el `Text` dentro del árbol haría que dijera el número dos
  ///   veces (la segunda suelto, sin contexto).
  Widget _buildUnreadBadge(int unreadCount) {
    return Positioned(
      right: 8,
      top: 8,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: VentiqHomeTheme.danger,
              shape: BoxShape.circle,
              boxShadow: VentiqHomeTheme.shadowCard,
            ),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
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
      ),
    );
  }

  /// Mostrar panel de notificaciones
  void _showNotificationsPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // El panel es un `DraggableScrollableSheet`, así que el contenido de la
      // ruta ocupa TODA la pantalla (aunque solo pinte la tarjeta abajo). Por
      // eso la zona oscura de arriba no era el `barrier` del modal y tocarla no
      // cerraba nada. Con este `Stack`, la zona de encima del panel es un área
      // táctil que cierra; el `Align` del sheet solo ocupa su tarjeta, así que
      // los toques de arriba caen aquí y los de la tarjeta siguen siendo suyos.
      builder: (BuildContext sheetContext) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(sheetContext).pop(),
          ),
          const NotificationsPanel(),
        ],
      ),
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
                      padding: const EdgeInsets.fromLTRB(0, 6, 0, 20),
                      itemCount: notifications.length,
                      separatorBuilder:
                          (context, index) => const SizedBox(height: 2),
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

  /// Header del panel: título a ancho completo y filtro en una segunda línea,
  /// para que «Notificaciones» no se corte a «Notifica…» en pantallas de 360 px.
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: VentiqHomeTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Notificaciones',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.done_all_rounded,
                  color: VentiqHomeTheme.success,
                ),
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
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              StreamBuilder<int>(
                stream: _notificationService.unreadCountStream,
                initialData: _notificationService.unreadCount,
                builder: (context, snapshot) {
                  final int unreadCount = snapshot.data ?? 0;
                  return Text(
                    unreadCount > 0 ? '$unreadCount sin leer' : 'Todo al día',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color:
                          unreadCount > 0
                              ? VentiqHomeTheme.primary
                              : VentiqHomeTheme.textSecondary,
                    ),
                  );
                },
              ),
              const Spacer(),
              StreamBuilder<int>(
                stream: _notificationService.unreadCountStream,
                initialData: _notificationService.unreadCount,
                builder: (context, snapshot) {
                  final int unreadCount = snapshot.data ?? 0;
                  if (unreadCount == 0) return const SizedBox.shrink();

                  return FilterChip(
                    label: Text('No leídas ($unreadCount)'),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color:
                          _showOnlyUnread
                              ? VentiqHomeTheme.primary
                              : VentiqHomeTheme.textSecondary,
                    ),
                    selected: _showOnlyUnread,
                    onSelected: (bool value) {
                      setState(() => _showOnlyUnread = value);
                    },
                    backgroundColor: VentiqHomeTheme.card,
                    selectedColor: VentiqHomeTheme.primary.withValues(
                      alpha: 0.12,
                    ),
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
            ],
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
          if (_showOnlyUnread) ...<Widget>[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showOnlyUnread = false),
              icon: const Icon(Icons.done_all_rounded, size: 17),
              label: const Text('Ver todas'),
            ),
          ],
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
    final bool noLeida = !widget.notification.leida;

    return Dismissible(
      key: Key('notification_${widget.notification.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDismiss(),
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: VentiqHomeTheme.danger,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text(
              'Eliminar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      child: Semantics(
        button: true,
        label: '${noLeida ? 'Sin leer. ' : ''}${widget.notification.titulo}',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() => _isExpanded = !_isExpanded);
                // Marcar como leída al abrirla.
                if (!widget.notification.leida) widget.onTap();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color:
                      noLeida
                          ? VentiqHomeTheme.primary.withValues(alpha: 0.05)
                          : VentiqHomeTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        noLeida
                            ? VentiqHomeTheme.primary.withValues(alpha: 0.22)
                            : VentiqHomeTheme.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                // `IntrinsicHeight` es imprescindible: un `Row` con
                // `CrossAxisAlignment.stretch` dentro de un `ListView` recibe
                // altura INFINITA y el layout revienta («BoxConstraints forces
                // an infinite height»), que dejaba la lista de notificaciones en
                // blanco. Con el alto intrínseco, la barra de acento se estira
                // hasta la altura real del ítem, que es lo que se buscaba.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Barra de acento: solo en no leídas.
                      Container(
                        width: 4,
                        color: noLeida ? color : Colors.transparent,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(icon, color: color, size: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Expanded(
                                              child: Text(
                                                widget.notification.titulo,
                                                maxLines:
                                                    _isExpanded ? null : 2,
                                                overflow:
                                                    _isExpanded
                                                        ? null
                                                        : TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14.5,
                                                  height: 1.2,
                                                  fontWeight:
                                                      noLeida
                                                          ? FontWeight.w800
                                                          : FontWeight.w600,
                                                  color:
                                                      VentiqHomeTheme
                                                          .textPrimary,
                                                ),
                                              ),
                                            ),
                                            if (widget.notification.isUrgent)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                  left: 6,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: VentiqHomeTheme.danger,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
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
                                        AnimatedCrossFade(
                                          firstChild: Text(
                                            widget.notification.mensaje,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              height: 1.35,
                                              color:
                                                  VentiqHomeTheme.textSecondary,
                                            ),
                                          ),
                                          secondChild: Text(
                                            widget.notification.mensaje,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              height: 1.4,
                                              color:
                                                  VentiqHomeTheme.textSecondary,
                                            ),
                                          ),
                                          crossFadeState:
                                              _isExpanded
                                                  ? CrossFadeState.showSecond
                                                  : CrossFadeState.showFirst,
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 13,
                                    color: VentiqHomeTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    timeago.format(
                                      widget.notification.createdAt,
                                      locale: 'es',
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: VentiqHomeTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTypeChip(color),
                                  const Spacer(),
                                  if (noLeida)
                                    Container(
                                      width: 7,
                                      height: 7,
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: const BoxDecoration(
                                        color: VentiqHomeTheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  Icon(
                                    _isExpanded
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                    size: 17,
                                    color: VentiqHomeTheme.textSecondary,
                                  ),
                                ],
                              ),
                              if (_isExpanded &&
                                  _shouldShowReceiveOrderButton())
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: _handleReceiveOrder,
                                      icon: const Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 19,
                                      ),
                                      label: const Text(
                                        'Recibir Orden',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            VentiqHomeTheme.success,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 11,
                                        ),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Píldora con el tipo de notificación (Venta, Pedido, Sistema…).
  Widget _buildTypeChip(Color color) {
    final String label = switch (widget.notification.tipo) {
      NotificationType.alerta => 'Alerta',
      NotificationType.info => 'Info',
      NotificationType.warning => 'Aviso',
      NotificationType.success => 'Hecho',
      NotificationType.error => 'Error',
      NotificationType.promocion => 'Promo',
      NotificationType.sistema => 'Sistema',
      NotificationType.pedido => 'Pedido',
      NotificationType.inventario => 'Inventario',
      NotificationType.venta => 'Venta',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.2,
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
      final estadoResponse =
          await supabase
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
