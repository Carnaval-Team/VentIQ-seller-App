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
    with TickerProviderStateMixin {
  // Controlador de la entrada (logo + wordmark).
  late final AnimationController _introCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  // Controlador del "halo" que late suavemente detrás del logo.
  late final AnimationController _pulseCtrl;

  String _statusText = 'Iniciando...';

  @override
  void initState() {
    super.initState();

    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    // El logo entra con un rebote sutil.
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _introCtrl,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
    );

    // El wordmark aparece un instante después, deslizándose hacia arriba.
    _textFade = CurvedAnimation(
      parent: _introCtrl,
      curve: const Interval(0.45, 0.9, curve: Curves.easeIn),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introCtrl,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _introCtrl.forward();
    _init();
  }

  Future<void> _init() async {
    // Mínimo visual para que la animación se vea
    await Future.delayed(const Duration(milliseconds: 700));

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
      // Esperar a que _loadPerfil termine (con o sin perfil)
      int profileAttempts = 0;
      while (!auth.perfilLoaded && profileAttempts < 25) {
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
    _introCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Fondo claro premium con un degradado diagonal muy sutil que
        // mantiene los colores del logo como protagonistas.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Color(0xFFEFF4FB),
              Color(0xFFE7EEF8),
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // ── Centro: logo + wordmark ──────────────────────────
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLogo(),
                    const SizedBox(height: 30),
                    _buildWordmark(),
                  ],
                ),
              ),

              // ── Pie: indicador de carga + estado ─────────────────
              Positioned(
                left: 0,
                right: 0,
                bottom: 48,
                child: FadeTransition(
                  opacity: _textFade,
                  child: _buildLoader(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Logo dentro de una tarjeta elevada tipo "glass", con un halo de marca
  // que late suavemente por detrás para dar sensación de vida.
  Widget _buildLogo() {
    return FadeTransition(
      opacity: _logoFade,
      child: ScaleTransition(
        scale: _logoScale,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, child) {
            final t = _pulseCtrl.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                // Halo difuso que respira.
                Container(
                  width: 168 + t * 14,
                  height: 168 + t * 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.18 + t * 0.10),
                        AppTheme.accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                child!,
              ],
            );
          },
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.18),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Image.asset(
              'assets/images/logonew_nobg.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWordmark() {
    return SlideTransition(
      position: _textSlide,
      child: FadeTransition(
        opacity: _textFade,
        child: Column(
          children: [
            // Wordmark con degradado de marca aplicado al texto.
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppTheme.primaryDark, AppTheme.primaryLight],
              ).createShader(bounds),
              child: const Text(
                'GoReserva',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  color: Colors.white, // sustituido por el shader
                  letterSpacing: 1.0,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Gestión de turnos inteligente',
              style: TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary.withValues(alpha: 0.9),
                letterSpacing: 0.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return Column(
      children: [
        // Barra de progreso indeterminada M3, estrecha y con esquinas suaves.
        SizedBox(
          width: 140,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // El texto de estado cambia con un cross-fade suave.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: child,
          ),
          child: Text(
            _statusText,
            key: ValueKey(_statusText),
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}
