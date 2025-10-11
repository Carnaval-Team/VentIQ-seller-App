import 'package:flutter/material.dart';
import '../services/user_preferences_service.dart';
import '../services/auth_service.dart';
import '../services/settings_integration_service.dart';
import '../services/auto_sync_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _userPreferencesService = UserPreferencesService();
  final _authService = AuthService();
  final _integrationService = SettingsIntegrationService();

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Add a small delay for splash screen effect
    await Future.delayed(const Duration(seconds: 2));

    try {
      // Check if user has a valid session
      final hasValidSession = await _userPreferencesService.hasValidSession();
      
      if (hasValidSession) {
        // User has valid session, initialize smart services and go to categories
        print('✅ Sesión válida encontrada - Inicializando servicios inteligentes...');
        _initializeSmartServices();
        
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/categories');
        }
      } else {
        // Check if user has saved credentials for auto-login
        final shouldRemember = await _userPreferencesService.shouldRememberMe();
        
        if (shouldRemember) {
          final credentials = await _userPreferencesService.getSavedCredentials();
          final email = credentials['email'];
          final password = credentials['password'];
          
          if (email != null && password != null && email.isNotEmpty && password.isNotEmpty) {
            // Attempt automatic login
            await _attemptAutoLogin(email, password);
            return;
          }
        }
        
        // No valid session or saved credentials, go to login
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      print('Error checking auth status: $e');
      // On error, go to login screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  Future<void> _attemptAutoLogin(String email, String password) async {
    try {
      final response = await _authService.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        // Update user data with new token
        await _userPreferencesService.saveUserData(
          userId: response.user!.id,
          email: response.user!.email ?? email,
          accessToken: response.session?.accessToken ?? '',
        );
        
        // Auto-login successful, initialize smart services and go to categories
        print('✅ Auto-login exitoso - Inicializando servicios inteligentes...');
        _initializeSmartServices();
        
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/categories');
        }
      } else {
        // Auto-login failed, go to login screen
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      }
    } catch (e) {
      print('Auto-login failed: $e');
      // Auto-login failed, go to login screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  /// Inicializar servicios inteligentes después del login exitoso
  Future<void> _initializeSmartServices() async {
    try {
      print('🚀 Inicializando servicios inteligentes desde SplashScreen...');
      
      // ✅ MEJORADO: Ejecutar primera sincronización inmediatamente
      // Inicializar el servicio de integración en segundo plano
      _integrationService.initialize().then((_) {
        print('✅ Servicios inteligentes inicializados correctamente desde SplashScreen');
      }).catchError((e) {
        print('❌ Error inicializando servicios inteligentes desde SplashScreen: $e');
        // No mostramos error al usuario ya que no es crítico para la navegación
      });
      
      // Ejecutar primera sincronización inmediatamente sin esperar la inicialización completa
      print('⚡ Ejecutando primera sincronización inmediata desde SplashScreen...');
      final autoSyncService = AutoSyncService();
      autoSyncService.performImmediateSync().then((_) {
        print('✅ Primera sincronización inmediata completada desde SplashScreen');
      }).catchError((e) {
        print('❌ Error en primera sincronización inmediata desde SplashScreen: $e');
      });
      
    } catch (e) {
      print('❌ Error configurando servicios inteligentes desde SplashScreen: $e');
      // No lanzamos el error para no afectar el flujo de navegación
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF4A90E2),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
                child: Image.asset(
                  'assets/ventas.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 32),
              // Loading indicator
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 3,
              ),
              const SizedBox(height: 24),
              // Loading text
              const Text(
                'Iniciando Vendedor Cuba...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
