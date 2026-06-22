import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  String _statusText = 'Iniciando...';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
    _init();
  }

  Future<void> _init() async {
    // Mínimo visual para que la animación se vea
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;
    _setStatus('Verificando sesión...');

    final auth = context.read<AuthProvider>();

    // Esperar a que el AuthProvider resuelva el estado inicial
    // (supabase_flutter puede tardar un tick en emitir el estado)
    int attempts = 0;
    while (!auth.isLoggedIn && attempts < 10) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
      if (!mounted) return;
    }

    if (auth.isLoggedIn) {
      _setStatus('Cargando perfil...');
      // Dar tiempo a que el perfil se cargue si ya está en proceso
      int profileAttempts = 0;
      while (!auth.hasPerfil && profileAttempts < 15) {
        await Future.delayed(const Duration(milliseconds: 200));
        profileAttempts++;
        if (!mounted) return;
      }
    }

    if (!mounted) return;

    FlutterNativeSplash.remove();

    if (auth.isLoggedIn) {
      if (auth.hasPerfil) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/perfil-setup');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _setStatus(String text) {
    if (mounted) setState(() => _statusText = text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            // Fondo con degradado sutil
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    AppTheme.primary.withOpacity(0.06),
                  ],
                ),
              ),
            ),
            // Contenido central
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo con animación de escala
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 140,
                      height: 140,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Flow',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Gestión de turnos inteligente',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            // Indicador de carga en la parte inferior
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: Column(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.primary.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _statusText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
