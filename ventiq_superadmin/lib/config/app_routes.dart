/// Rutas protegidas disponibles en la app y sus etiquetas para la UI de permisos.
class AppRoute {
  final String route;
  final String label;
  final String? group;

  const AppRoute({required this.route, required this.label, this.group});
}

class AppRoutes {
  // Rutas publicas / siempre accesibles
  static const String login = '/login';
  static const String dashboard = '/dashboard';

  // Rutas protegidas agrupadas
  static const List<AppRoute> protected = [
    AppRoute(route: '/tiendas', label: 'Gestión de Tiendas', group: 'Tiendas'),
    AppRoute(route: '/tiendas-catalogo', label: 'Tiendas en Catálogo', group: 'Tiendas'),
    AppRoute(route: '/administradores', label: 'Administradores', group: 'Tiendas'),
    AppRoute(route: '/trabajadores', label: 'Trabajadores', group: 'Tiendas'),
    AppRoute(route: '/carnaval-tiendas', label: 'Carnaval App Tiendas', group: 'Tiendas'),
    AppRoute(route: '/productos-carnaval-inventtia', label: 'Productos Carnaval - Inventtia', group: 'Tiendas'),
    AppRoute(route: '/pago-proveedores', label: 'Pago a Proveedores', group: 'Tiendas'),
    AppRoute(route: '/pago-inventtia', label: 'Pago a Inventtia', group: 'Tiendas'),
    AppRoute(route: '/referral-payments', label: 'Pago a Referidos', group: 'Tiendas'),
    AppRoute(route: '/eliminacion-tiendas', label: 'Eliminación de Tiendas', group: 'Tiendas'),
    AppRoute(route: '/licencias', label: 'Gestión de Licencias', group: 'Licencias'),
    AppRoute(route: '/renovaciones', label: 'Renovaciones', group: 'Licencias'),
    AppRoute(route: '/configuracion', label: 'Planes / Configuración', group: 'Licencias'),
    AppRoute(route: '/agentes', label: 'Agentes', group: 'Licencias'),
    AppRoute(route: '/usuarios', label: 'Gestión de Usuarios', group: 'Usuarios'),
    AppRoute(route: '/control-flota', label: 'Control de Flota', group: 'Operaciones'),
    AppRoute(route: '/movimientos', label: 'Movimientos en tiempo real', group: 'Operaciones'),
    AppRoute(route: '/muevete/dashboard', label: 'Panel Muévete', group: 'Muévete'),
    AppRoute(route: '/muevete/conductores', label: 'Conductores', group: 'Muévete'),
    AppRoute(route: '/muevete/viajes', label: 'Viajes', group: 'Muévete'),
    AppRoute(route: '/muevete/solicitudes', label: 'Solicitudes y Ofertas', group: 'Muévete'),
    AppRoute(route: '/muevete/mapa', label: 'Mapa en Vivo', group: 'Muévete'),
    AppRoute(route: '/muevete/mapa-offline', label: 'Subir Mapa Offline', group: 'Muévete'),
    AppRoute(route: '/muevete/valoraciones', label: 'Valoraciones', group: 'Muévete'),
    AppRoute(route: '/muevete/billeteras', label: 'Billeteras', group: 'Muévete'),
    AppRoute(route: '/muevete/kyc', label: 'Verificación KYC', group: 'Muévete'),
    AppRoute(route: '/muevete/planes', label: 'Solicitudes de Plan', group: 'Muévete'),
    AppRoute(route: '/muevete/cargas', label: 'Gestión de Cargas', group: 'Muévete'),
    AppRoute(route: '/carnaval-dashboard', label: 'Info de Carnaval', group: 'Carnaval'),
    AppRoute(route: '/roles', label: 'Gestión de Roles', group: 'Sistema'),
    AppRoute(route: '/configuracion', label: 'Configuración', group: 'Sistema'),
  ];

  static List<String> get allProtectedRoutes =>
      protected.map((r) => r.route).toList();

  /// Dashboard y login siempre deben estar disponibles.
  static List<String> get alwaysAllowed => [dashboard, login, '/'];
}
