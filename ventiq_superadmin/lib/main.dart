import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_theme.dart';
import 'config/supabase_config.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tiendas_screen.dart';
import 'screens/tiendas_catalogo_screen.dart';
import 'screens/usuarios_screen.dart';
import 'screens/administradores_screen.dart';
import 'screens/almacenes_screen.dart';
import 'screens/tpvs_screen.dart';
import 'screens/referral_payments_screen.dart';
import 'screens/trabajadores_screen.dart';
import 'screens/licencias_screen.dart';
import 'screens/renovaciones_screen.dart';
import 'screens/configuracion_screen.dart';
import 'screens/consignacion_screen.dart';
import 'screens/carnaval_store_mapping_screen.dart';
import 'screens/carnaval_inventtia_products_screen.dart';
import 'screens/pago_proveedores_screen.dart';
import 'screens/pago_inventtia_screen.dart';
import 'screens/eliminacion_tiendas_screen.dart';
import 'screens/fleet_control_screen.dart';
import 'screens/movimientos_screen.dart';
import 'screens/muevete/muevete_dashboard_screen.dart';
import 'screens/muevete/muevete_drivers_screen.dart';
import 'screens/muevete/muevete_trips_screen.dart';
import 'screens/muevete/muevete_requests_screen.dart';
import 'screens/muevete/muevete_map_screen.dart';
import 'screens/muevete/muevete_map_upload_screen.dart';
import 'screens/muevete/muevete_ratings_screen.dart';
import 'screens/muevete/muevete_wallets_screen.dart';
import 'screens/muevete/muevete_kyc_screen.dart';
import 'screens/muevete/muevete_planes_screen.dart';
import 'screens/muevete/muevete_cargas_screen.dart';
import 'screens/agentes_screen.dart';
import 'screens/ingresos_distribucion_screen.dart';
import 'screens/carnaval_dashboard_screen.dart';
import 'screens/roles_screen.dart';
import 'widgets/route_guard.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar datos de locale para DateFormat
  await initializeDateFormatting('es_ES', null);

  // Inicializar Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  runApp(const VentIQSuperAdminApp());
}

class VentIQSuperAdminApp extends StatelessWidget {
  const VentIQSuperAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventtia Super Admin',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
      locale: const Locale('es', 'ES'),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const RouteGuard(
              route: '/dashboard',
              child: DashboardScreen(),
            ),
        '/tiendas': (context) => const RouteGuard(
              route: '/tiendas',
              child: TiendasScreen(),
            ),
        '/tiendas-catalogo': (context) => const RouteGuard(
              route: '/tiendas-catalogo',
              child: TiendasCatalogoScreen(),
            ),
        '/usuarios': (context) => const RouteGuard(
              route: '/usuarios',
              child: UsuariosScreen(),
            ),
        '/administradores': (context) => const RouteGuard(
              route: '/administradores',
              child: AdministradoresScreen(),
            ),
        '/almacenes': (context) => const RouteGuard(
              route: '/almacenes',
              child: AlmacenesScreen(),
            ),
        '/tpvs': (context) => const RouteGuard(
              route: '/tpvs',
              child: TpvsScreen(),
            ),
        '/trabajadores': (context) => const RouteGuard(
              route: '/trabajadores',
              child: TrabajadoresScreen(),
            ),
        '/licencias': (context) => const RouteGuard(
              route: '/licencias',
              child: LicenciasScreen(),
            ),
        '/renovaciones': (context) => const RouteGuard(
              route: '/renovaciones',
              child: RenovacionesScreen(),
            ),
        '/configuracion': (context) => const RouteGuard(
              route: '/configuracion',
              child: ConfiguracionScreen(),
            ),
        '/consignacion': (context) => const RouteGuard(
              route: '/consignacion',
              child: ConsignacionScreen(),
            ),
        '/carnaval-tiendas': (context) => const RouteGuard(
              route: '/carnaval-tiendas',
              child: CarnavalStoreMappingScreen(),
            ),
        '/productos-carnaval-inventtia': (context) => const RouteGuard(
              route: '/productos-carnaval-inventtia',
              child: CarnavalInventtiaProductsScreen(),
            ),
        '/pago-proveedores': (context) => const RouteGuard(
              route: '/pago-proveedores',
              child: PagoProveedoresScreen(),
            ),
        '/pago-inventtia': (context) => const RouteGuard(
              route: '/pago-inventtia',
              child: PagoInventtiaScreen(),
            ),
        '/eliminacion-tiendas': (context) => const RouteGuard(
              route: '/eliminacion-tiendas',
              child: EliminacionTiendasScreen(),
            ),
        '/control-flota': (context) => const RouteGuard(
              route: '/control-flota',
              child: FleetControlScreen(),
            ),
        '/movimientos': (context) => const RouteGuard(
              route: '/movimientos',
              child: MovimientosScreen(),
            ),
        '/referral-payments': (context) => const RouteGuard(
              route: '/referral-payments',
              child: ReferralPaymentsScreen(),
            ),
        // Muévete
        '/muevete/dashboard': (context) => const RouteGuard(
              route: '/muevete/dashboard',
              child: MueveteDashboardScreen(),
            ),
        '/muevete/conductores': (context) => const RouteGuard(
              route: '/muevete/conductores',
              child: MueveteDriversScreen(),
            ),
        '/muevete/viajes': (context) => const RouteGuard(
              route: '/muevete/viajes',
              child: MueveteTripsScreen(),
            ),
        '/muevete/solicitudes': (context) => const RouteGuard(
              route: '/muevete/solicitudes',
              child: MueveteRequestsScreen(),
            ),
        '/muevete/mapa': (context) => const RouteGuard(
              route: '/muevete/mapa',
              child: MueveteMapScreen(),
            ),
        '/muevete/mapa-offline': (context) => const RouteGuard(
              route: '/muevete/mapa-offline',
              child: MueveteMapUploadScreen(),
            ),
        '/muevete/valoraciones': (context) => const RouteGuard(
              route: '/muevete/valoraciones',
              child: MueveteRatingsScreen(),
            ),
        '/muevete/billeteras': (context) => const RouteGuard(
              route: '/muevete/billeteras',
              child: MueveteWalletsScreen(),
            ),
        '/muevete/kyc': (context) => const RouteGuard(
              route: '/muevete/kyc',
              child: MueveteKycScreen(),
            ),
        '/muevete/planes': (context) => const RouteGuard(
              route: '/muevete/planes',
              child: MuevetesPlanesScreen(),
            ),
        '/muevete/cargas': (context) => const RouteGuard(
              route: '/muevete/cargas',
              child: MueveteCargasScreen(),
            ),
        '/agentes': (context) => const RouteGuard(
              route: '/agentes',
              child: AgentesScreen(),
            ),
        '/ingresos-distribucion': (context) => const RouteGuard(
              route: '/ingresos-distribucion',
              child: IngresosDistribucionScreen(),
            ),
        '/carnaval-dashboard': (context) => const RouteGuard(
              route: '/carnaval-dashboard',
              child: CarnavalDashboardScreen(),
            ),
        '/roles': (context) => const RouteGuard(
              route: '/roles',
              child: RolesScreen(),
            ),
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final isLoggedIn = await _authService.isLoggedIn();
      if (mounted) {
        setState(() {
          _isLoggedIn = isLoggedIn;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoggedIn = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Verificando autenticación...'),
            ],
          ),
        ),
      );
    }

    return _isLoggedIn ? const DashboardScreen() : const LoginScreen();
  }
}
