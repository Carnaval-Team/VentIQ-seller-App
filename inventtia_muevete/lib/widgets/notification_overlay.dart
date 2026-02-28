import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationOverlay extends StatefulWidget {
  final Widget child;

  const NotificationOverlay({super.key, required this.child});

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay>
    with SingleTickerProviderStateMixin {
  final NotificationService _service = NotificationService();
  StreamSubscription<NotificationModel>? _subscription;

  NotificationModel? _current;
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _subscription = _service.notificationStream.listen(_onNotification);
  }

  void _onNotification(NotificationModel notification) {
    _hideTimer?.cancel();
    setState(() => _current = notification);
    _animController.forward(from: 0);
    _hideTimer = Timer(const Duration(seconds: 5), _hide);
  }

  void _hide() {
    _animController.reverse().then((_) {
      if (mounted) setState(() => _current = null);
    });
  }

  IconData _iconForType(NotificationType tipo) {
    switch (tipo) {
      case NotificationType.nuevaSolicitud:
        return Icons.local_taxi;
      case NotificationType.nuevaOferta:
        return Icons.local_offer;
      case NotificationType.ofertaAceptada:
        return Icons.check_circle;
      case NotificationType.viajeIniciado:
        return Icons.directions_car;
      case NotificationType.driverEsperando:
        return Icons.hourglass_top;
      case NotificationType.viajeCompletado:
        return Icons.flag;
    }
  }

  Color _colorForType(NotificationType tipo) {
    switch (tipo) {
      case NotificationType.nuevaSolicitud:
        return const Color(0xFF1A6FBF);
      case NotificationType.nuevaOferta:
        return const Color(0xFF2E7D32);
      case NotificationType.ofertaAceptada:
        return const Color(0xFF1565C0);
      case NotificationType.viajeIniciado:
        return const Color(0xFFE65100);
      case NotificationType.driverEsperando:
        return const Color(0xFFF9A825);
      case NotificationType.viajeCompletado:
        return const Color(0xFF2E7D32);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _hideTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: SlideTransition(
              position: _slideAnimation,
              child: GestureDetector(
                onTap: _hide,
                onVerticalDragEnd: (d) {
                  if (d.primaryVelocity != null && d.primaryVelocity! < 0) {
                    _hide();
                  }
                },
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _colorForType(_current!.tipo),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _iconForType(_current!.tipo),
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _current!.titulo,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _current!.mensaje,
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.close,
                          color: Colors.white.withOpacity(0.7),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
