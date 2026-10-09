import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config/app_colors.dart';
import '../utils/app_route_observer.dart';
import '../widgets/admin_ai_assistant_sheet.dart';

/// Envuelve toda la app y agrega un botón flotante de ayuda (asistente IA)
/// visible en TODAS las pantallas, sin tener que modificar cada Scaffold.
///
/// Se coloca en `MaterialApp.builder`. Escucha los cambios de ruta via
/// [AppRouteObserver] para ocultarse en splash/login, donde no tiene sentido.
class AiAssistantOverlay extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const AiAssistantOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  // Rutas donde NO se muestra el botón (splash / login).
  static const Set<String> _hiddenRoutes = {'/', '/login'};

  @override
  State<AiAssistantOverlay> createState() => _AiAssistantOverlayState();
}

class _AiAssistantOverlayState extends State<AiAssistantOverlay> {
  @override
  void initState() {
    super.initState();
    AppRouteObserver.instance.routeNameNotifier.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    AppRouteObserver.instance.routeNameNotifier.removeListener(_onRouteChanged);
    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  bool get _visible {
    final route = AppRouteObserver.instance.routeNameNotifier.value;
    // Antes del primer push (splash inicial) también se oculta.
    if (route == null) return false;
    return !AiAssistantOverlay._hiddenRoutes.contains(route);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible)
          Positioned(
            right: 16,
            bottom: 150,
            child: _AiAssistantFab(navigatorKey: widget.navigatorKey),
          ),
      ],
    );
  }
}

class _AiAssistantFab extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const _AiAssistantFab({required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) {
            AdminAiAssistantSheet.show(ctx);
          }
        },
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.support_agent,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}
