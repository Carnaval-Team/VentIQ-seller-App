import 'package:flutter/material.dart';
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
import 'screens/trabajadores_screen.dart';
import 'screens/licencias_screen.dart';
import 'screens/renovaciones_screen.dart';
import 'screens/configuracion_screen.dart';
import 'screens/consignacion_screen.dart';
import 'screens/carnaval_store_mapping_screen.dart';
import 'screens/pago_proveedores_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/tiendas': (context) => const TiendasScreen(),
        '/tiendas-catalogo': (context) => const TiendasCatalogoScreen(),
        '/usuarios': (context) => const UsuariosScreen(),
        '/administradores': (context) => const AdministradoresScreen(),
        '/almacenes': (context) => const AlmacenesScreen(),
        '/tpvs': (context) => const TpvsScreen(),
        '/trabajadores': (context) => const TrabajadoresScreen(),
        '/licencias': (context) => const LicenciasScreen(),
        '/renovaciones': (context) => const RenovacionesScreen(),
        '/configuracion': (context) => const ConfiguracionScreen(),
        '/consignacion': (context) => const ConsignacionScreen(),
        '/carnaval-tiendas': (context) => const CarnavalStoreMappingScreen(),
        '/pago-proveedores': (context) => const PagoProveedoresScreen(),
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
