import 'package:flutter/material.dart';

/// Observador global que recuerda la ruta visible.
///
/// Lo necesita [HomeWidgetLauncher] para no re-navegar al destino en el que ya
/// estamos: el widget de Resumen apunta a `/dashboard`, que es justo la pantalla
/// que dispara el enrutado, y sin esta comprobación se produce el ciclo
/// push → initState del Dashboard → enrutado → push.
///
/// Se guarda la propia [Route] (no solo su nombre) porque
/// `pushNamedAndRemoveUntil('/dashboard')` retira la instancia anterior del
/// Dashboard, que tiene el MISMO nombre que la nueva: comparando por nombre se
/// borraría por error la ruta actual recién empujada.
class AppRouteObserver extends NavigatorObserver {
  AppRouteObserver._();

  static final AppRouteObserver instance = AppRouteObserver._();

  Route<dynamic>? _currentRoute;

  /// Nombre de la ruta actualmente visible (null antes del primer push).
  String? get currentRouteName => _currentRoute?.settings.name;

  bool isCurrent(String routeName) => currentRouteName == routeName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _currentRoute = route;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null || identical(oldRoute, _currentRoute)) {
      _currentRoute = newRoute;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, _currentRoute)) {
      _currentRoute = previousRoute;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // `pushNamedAndRemoveUntil` retira rutas por debajo de la nueva; solo se
    // corrige si la retirada era exactamente la visible.
    if (identical(route, _currentRoute)) {
      _currentRoute = previousRoute;
    }
  }
}
