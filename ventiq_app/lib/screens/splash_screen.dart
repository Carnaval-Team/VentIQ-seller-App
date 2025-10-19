import 'package:flutter/material.dart';
import '../services/user_preferences_service.dart';
import '../services/auth_service.dart';
import '../services/settings_integration_service.dart';
import '../services/auto_sync_service.dart';
import '../services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
          // Verificar actualizaciones después de navegar
          _checkForUpdatesAfterNavigation();
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
          // Verificar actualizaciones después de navegar
          _checkForUpdatesAfterNavigation();
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

  /// Verificar actualizaciones después de navegar a la vista principal
  Future<void> _checkForUpdatesAfterNavigation() async {
    // Esperar un poco para que la navegación se complete
    await Future.delayed(const Duration(seconds: 1));
    
    try {
      print('🔍 Verificando actualizaciones automáticamente...');
      
      final updateInfo = await UpdateService.checkForUpdates();
      
      if (updateInfo['hay_actualizacion'] == true && mounted) {
        // Solo mostrar si hay actualización disponible
        _showUpdateAvailableDialog(updateInfo);
      } else {
        print('✅ No hay actualizaciones disponibles');
      }
    } catch (e) {
      print('❌ Error verificando actualizaciones automáticamente: $e');
      // No mostrar error al usuario, es una verificación silenciosa
    }
  }

  /// Mostrar diálogo cuando hay actualización disponible
  void _showUpdateAvailableDialog(Map<String, dynamic> updateInfo) {
    final bool isObligatory = updateInfo['obligatoria'] ?? false;
    final String newVersion = updateInfo['version_disponible'] ?? 'Desconocida';
    final String currentVersion = updateInfo['current_version'] ?? 'Desconocida';
    
    showDialog(
      context: context,
      barrierDismissible: !isObligatory,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isObligatory ? Icons.warning : Icons.system_update,
              color: isObligatory ? Colors.orange : Colors.blue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isObligatory ? 'Actualización Obligatoria' : 'Nueva Versión Disponible',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nueva versión disponible: $newVersion'),
            Text('Versión actual: $currentVersion'),
            const SizedBox(height: 16),
            if (isObligatory)
              const Text(
                'Esta actualización es obligatoria y debe instalarse para continuar usando la aplicación.',
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
              )
            else
              const Text('Se recomienda actualizar para obtener las últimas mejoras y correcciones.'),
          ],
        ),
        actions: [
          if (!isObligatory)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Más tarde'),
            ),
          ElevatedButton(
            onPressed: () => _downloadUpdate(),
            style: ElevatedButton.styleFrom(
              backgroundColor: isObligatory ? Colors.orange : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );
  }

  /// Descargar actualización
  Future<void> _downloadUpdate() async {
    try {
      final Uri url = Uri.parse(UpdateService.downloadUrl);
      
      if (await canLaunchUrl(url)) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
        
        // Cerrar diálogo
        if (mounted) {
          Navigator.of(context).pop();
        }
        
        // Mostrar mensaje de confirmación
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📱 Descarga iniciada - Instala la nueva versión'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        throw 'No se puede abrir el enlace de descarga';
      }
    } catch (e) {
      print('❌ Error abriendo enlace de descarga: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error abriendo enlace de descarga: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
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
