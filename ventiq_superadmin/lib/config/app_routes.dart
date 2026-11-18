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
  static const String homeBanners = '/banners-inicio';
  static const String patrocinados = '/patrocinados';
  static const String colecciones = '/colecciones';
  static const String fidelidad = '/fidelidad';
  static const String versiones = '/versiones';

  // Rutas protegidas agrupadas
  static const List<AppRoute> protected = [
    AppRoute(route: '/tiendas', label: 'Gestión de Tiendas', group: 'Tiendas'),
    AppRoute(
      route: '/tiendas-catalogo',
      label: 'Tiendas en Catálogo',
      group: 'Tiendas',
    ),
    AppRoute(
      route: '/administradores',
      label: 'Administradores',
      group: 'Tiendas',
    ),
    AppRoute(route: '/trabajadores', label: 'Trabajadores', group: 'Tiendas'),
    AppRoute(
      route: '/carnaval-tiendas',
      label: 'Carnaval App Tiendas',
      group: 'Tiendas',
    ),
    AppRoute(
      route: '/productos-carnaval-inventtia',
      label: 'Productos Carnaval - Inventtia',
      group: 'Tiendas',
    ),
    AppRoute(
      route: '/pago-proveedores',
      label: 'Pago a Proveedores',
      group: 'Tiendas',
    ),
    AppRoute(
      route: '/pago-inventtia',
      label: 'Pago a Inventtia',
      group: 'Tiendas',
    ),
    AppRoute(
      route: '/referral-payments',
      label: 'Pago a Referidos',
      group: 'Tiendas',
    ),
    AppRoute(
      route: '/eliminacion-tiendas',
      label: 'Eliminación de Tiendas',
      group: 'Tiendas',
    ),
    AppRoute(
      route: '/licencias',
      label: 'Gestión de Licencias',
      group: 'Licencias',
    ),
    AppRoute(route: '/renovaciones', label: 'Renovaciones', group: 'Licencias'),
    AppRoute(
      route: '/configuracion',
      label: 'Planes / Configuración',
      group: 'Licencias',
    ),
    AppRoute(route: '/agentes', label: 'Agentes', group: 'Licencias'),
    AppRoute(
      route: '/usuarios',
      label: 'Gestión de Usuarios',
      group: 'Usuarios',
    ),
    AppRoute(
      route: '/usuarios-bloqueados',
      label: 'Usuarios bloqueados',
      group: 'Usuarios',
    ),
    AppRoute(
      route: '/control-flota',
      label: 'Control de Flota',
      group: 'Operaciones',
    ),
    AppRoute(
      route: '/movimientos',
      label: 'Movimientos en tiempo real',
      group: 'Operaciones',
    ),
    AppRoute(
      route: '/muevete/dashboard',
      label: 'Panel Muévete',
      group: 'Muévete',
    ),
    AppRoute(
      route: '/muevete/conductores',
      label: 'Conductores',
      group: 'Muévete',
    ),
    AppRoute(route: '/muevete/viajes', label: 'Viajes', group: 'Muévete'),
    AppRoute(
      route: '/muevete/solicitudes',
      label: 'Solicitudes y Ofertas',
      group: 'Muévete',
    ),
    AppRoute(route: '/muevete/mapa', label: 'Mapa en Vivo', group: 'Muévete'),
    AppRoute(
      route: '/muevete/mapa-offline',
      label: 'Subir Mapa Offline',
      group: 'Muévete',
    ),
    AppRoute(
      route: '/muevete/valoraciones',
      label: 'Valoraciones',
      group: 'Muévete',
    ),
    AppRoute(
      route: '/muevete/billeteras',
      label: 'Billeteras',
      group: 'Muévete',
    ),
    AppRoute(
      route: '/muevete/kyc',
      label: 'Verificación KYC',
      group: 'Muévete',
    ),
    AppRoute(
      route: '/muevete/planes',
      label: 'Solicitudes de Plan',
      group: 'Muévete',
    ),
    AppRoute(
      route: '/muevete/cargas',
      label: 'Gestión de Cargas',
      group: 'Muévete',
    ),
    // H6: configuración tarifaria del taxi (parámetros, multiplicadores,
    // fallback municipal y simulador de cotización).
    AppRoute(
      route: '/muevete/tarifas',
      label: 'Tarifas y Zonas',
      group: 'Muévete',
    ),
    // H6 (segunda mitad): lista de zonas tarifarias y editor de polígonos.
    AppRoute(
      route: '/muevete/zonas',
      label: 'Zonas y Polígonos',
      group: 'Muévete',
    ),
    // H1: catálogo de tipos de vehículo (nombre visible, orden, capacidad y
    // visibilidad). Se cambia sin recompilar la app del cliente.
    AppRoute(
      route: '/muevete/vehiculos',
      label: 'Catálogo de Vehículos',
      group: 'Muévete',
    ),
    // H1: versiones de los documentos legales y auditoría de consentimientos.
    AppRoute(
      route: '/muevete/documentos',
      label: 'Documentos y Consentimientos',
      group: 'Muévete',
    ),
    // H2: bandeja de incidentes, pánico reciente y puerta de identidad.
    AppRoute(
      route: '/muevete/incidentes',
      label: 'Incidentes y Bloqueos',
      group: 'Muévete',
    ),
    AppRoute(
      route: '/carnaval-dashboard',
      label: 'Info de Carnaval',
      group: 'Carnaval',
    ),
    AppRoute(
      route: '/carnaval-precios-tiendas',
      label: 'Recargos Carnaval por Tienda',
      group: 'Carnaval',
    ),
    AppRoute(
      route: '/carnaval-productos-tienda',
      label: 'Productos por Tienda en Carnaval',
      group: 'Carnaval',
    ),
    AppRoute(
      route: '/banners-inicio',
      label: 'Banners inicio',
      group: 'Marketing',
    ),
    AppRoute(
      route: '/patrocinados',
      label: 'Espacio patrocinado',
      group: 'Marketing',
    ),
    AppRoute(
      route: '/colecciones',
      label: 'Colecciones temáticas',
      group: 'Marketing',
    ),
    AppRoute(
      route: '/fidelidad',
      label: 'Programa de fidelidad',
      group: 'Marketing',
    ),
    AppRoute(
      route: '/flow-suscripciones',
      label: 'Suscripciones Flow',
      group: 'Flow',
    ),
    AppRoute(
      route: '/flow-planes',
      label: 'Planes de suscripción Flow',
      group: 'Flow',
    ),
    AppRoute(
      route: '/flow-config',
      label: 'Configuración de suscripciones',
      group: 'Flow',
    ),
    AppRoute(
      route: '/flow-categorias',
      label: 'Categorías y subcategorías Flow',
      group: 'Flow',
    ),
    AppRoute(
      route: '/versiones',
      label: 'Versiones de las apps',
      group: 'Aplicaciones',
    ),
    AppRoute(
      route: '/costos-nomenclador',
      label: 'Nomencladores de costo',
      group: 'Finanzas',
    ),
    AppRoute(route: '/roles', label: 'Gestión de Roles', group: 'Sistema'),
    // Catálogo global de monedas (plan multimoneda, Fase 1).
    AppRoute(route: '/monedas', label: 'Monedas', group: 'Sistema'),
    AppRoute(route: '/configuracion', label: 'Configuración', group: 'Sistema'),
  ];

  static List<String> get allProtectedRoutes =>
      protected.map((r) => r.route).toList();

  /// Dashboard y login siempre deben estar disponibles.
  static List<String> get alwaysAllowed => [dashboard, login, '/'];
}
