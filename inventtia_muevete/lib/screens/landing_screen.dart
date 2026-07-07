import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  static const Color kAccent = Color(0xFFFE6B00);
  static const Color kBlue = Color(0xFF195DE6);

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfLoggedIn());
  }

  Future<void> _redirectIfLoggedIn() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) return;
    int attempts = 0;
    while (auth.tipoUsuario == null && attempts < 15) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
      if (!mounted) return;
    }
    if (!mounted) return;
    if (auth.tipoUsuario != null) {
      Navigator.pushNamedAndRemoveUntil(
          context, auth.homeRoute, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: Stack(
        children: [
          // Layer 1: photographic background
          Positioned.fill(
            child: Image.asset(
              isDark
                  ? 'assets/images/back_oscuro.png'
                  : 'assets/images/back_claro.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) =>
                  Container(color: AppTheme.bg(isDark)),
            ),
          ),
          // Layer 2: gradient overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          AppTheme.darkBg.withValues(alpha: 0.55),
                          AppTheme.darkBg.withValues(alpha: 0.82),
                          AppTheme.darkBg.withValues(alpha: 0.98),
                        ]
                      : [
                          AppTheme.lightBg.withValues(alpha: 0.40),
                          AppTheme.lightBg.withValues(alpha: 0.75),
                          AppTheme.lightBg.withValues(alpha: 0.98),
                        ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          // Layer 3: content
          Column(
            children: [
              _TopBar(isDark: isDark),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroSection(isDark: isDark),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 72),
                                _FeaturesSection(isDark: isDark),
                                const SizedBox(height: 80),
                                _PricingSection(isDark: isDark),
                                const SizedBox(height: 80),
                                _Footer(isDark: isDark),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isDark;
  const _TopBar({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F1117).withValues(alpha: 0.82)
            : Colors.white.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: 24,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  _Logo(isDark: isDark),
                  const Spacer(),
                  if (isWide) ...[
                    _NavLink(label: 'Funciones', isDark: isDark, onTap: () {}),
                    const SizedBox(width: 4),
                    _NavLink(label: 'Precios', isDark: isDark, onTap: () {}),
                    const SizedBox(width: 4),
                    _NavLink(label: 'Contacto', isDark: isDark, onTap: () {}),
                    const SizedBox(width: 12),
                  ],
                  _ThemeToggle(isDark: isDark),
                  const SizedBox(width: 8),
                  if (auth.isAuthenticated)
                    _UserAvatarMenu(isDark: isDark)
                  else
                    _AuthButtons(isWide: isWide, isDark: isDark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final bool isDark;
  const _Logo({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF195DE6), Color(0xFF4B7FFF)],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF195DE6).withValues(alpha: 0.30),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/logo.png',
              height: 36,
              width: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.local_shipping_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Muev',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: AppTheme.textPrimary(isDark),
                ),
              ),
              TextSpan(
                text: 'ete',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: LandingScreen.kAccent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavLink extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _NavLink({required this.label, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary(isDark),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final bool isDark;
  const _ThemeToggle({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        color: AppTheme.iconColor(isDark),
        size: 22,
      ),
      onPressed: () => context.read<ThemeProvider>().toggleTheme(),
    );
  }
}

class _AuthButtons extends StatelessWidget {
  final bool isWide;
  final bool isDark;
  const _AuthButtons({required this.isWide, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isWide) ...[
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/register'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary(isDark),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Registrarse'),
          ),
          const SizedBox(width: 6),
        ],
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF195DE6), Color(0xFF4B7FFF)],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF195DE6).withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Ingresar'),
          ),
        ),
      ],
    );
  }
}

class _UserAvatarMenu extends StatelessWidget {
  final bool isDark;
  const _UserAvatarMenu({required this.isDark});

  String _initials(String? name, String? email) {
    final source = (name?.trim().isNotEmpty ?? false) ? name!.trim() : (email ?? '?');
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.isDriver ? auth.driverProfile : auth.userProfile;
    final name = profile?['name'] as String?;
    final email = auth.user?.email;

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      tooltip: 'Cuenta',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: AppTheme.surface(isDark),
      elevation: 8,
      onSelected: (value) async {
        if (value == 'viajes') {
          Navigator.pushNamedAndRemoveUntil(context, auth.homeRoute, (_) => false);
        } else if (value == 'perfil') {
          Navigator.pushNamed(context, auth.profileRoute);
        } else if (value == 'logout') {
          await auth.signOut();
          if (context.mounted) {
            Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'viajes',
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: LandingScreen.kBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.route_rounded, size: 18, color: LandingScreen.kBlue),
              ),
              const SizedBox(width: 12),
              Text(
                'Ir a mi panel',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(isDark),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
            value: 'perfil',
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person_outline,
                      size: 18, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 12),
                Text(
                  'Mi perfil',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(isDark),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.logout_rounded, size: 18, color: AppTheme.error),
              ),
              const SizedBox(width: 12),
              Text(
                'Cerrar sesion',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: LandingScreen.kAccent, width: 2),
        ),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: LandingScreen.kBlue,
          child: Text(
            _initials(name, email),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// HERO SECTION — asymmetric split layout
// ─────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final bool isDark;
  const _HeroSection({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: isWide ? 500 : 400),
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: isWide ? 72 : 52,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 55, child: _HeroContent(isDark: isDark)),
                    const SizedBox(width: 48),
                    Expanded(flex: 45, child: _HeroStats(isDark: isDark)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroContent(isDark: isDark),
                    const SizedBox(height: 44),
                    _HeroStats(isDark: isDark),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HeroContent extends StatelessWidget {
  final bool isDark;
  const _HeroContent({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: LandingScreen.kBlue.withValues(alpha: isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: LandingScreen.kBlue.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'Plataforma activa en tiempo real',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: LandingScreen.kBlue,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        // Headline
        Text(
          'Logistica\nInteligente.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: isWide ? 58 : 42,
            fontWeight: FontWeight.w900,
            height: 1.04,
            letterSpacing: -2.5,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
        const SizedBox(height: 4),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF195DE6), Color(0xFFFE6B00)],
          ).createShader(bounds),
          child: Text(
            'En Movimiento.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: isWide ? 58 : 42,
              fontWeight: FontWeight.w900,
              height: 1.04,
              letterSpacing: -2.5,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Subtext
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(
            'Conecta transportistas con cargas en tiempo real. Optimiza rutas, encuentra combustible y gestiona tu flota desde un solo lugar.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.6,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
        ),
        const SizedBox(height: 32),
        // CTAs
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF195DE6), Color(0xFF4B7FFF)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF195DE6).withValues(alpha: 0.38),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                label: const Text('Comenzar gratis'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              icon: Icon(
                Icons.login_rounded,
                size: 18,
                color: AppTheme.textPrimary(isDark),
              ),
              label: Text(
                'Ingresar',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(isDark),
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                side: BorderSide(
                  color: AppTheme.border(isDark),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroStats extends StatelessWidget {
  final bool isDark;
  const _HeroStats({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final stats = [
      (Icons.local_shipping_rounded, '500+', 'Transportistas activos', LandingScreen.kBlue),
      (Icons.inventory_2_rounded, '2,400+', 'Cargas gestionadas', LandingScreen.kAccent),
      (Icons.local_gas_station_rounded, '180+', 'Estaciones mapeadas', const Color(0xFF22C55E)),
      (Icons.speed_rounded, 'Tiempo real', 'Actualizacion de datos', const Color(0xFF8B5CF6)),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats.map((s) {
        return Container(
          width: 160,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.card(isDark).withValues(alpha: isDark ? 0.80 : 0.90),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: s.$4.withValues(alpha: 0.20),
            ),
            boxShadow: [
              BoxShadow(
                color: s.$4.withValues(alpha: isDark ? 0.15 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: s.$4.withValues(alpha: isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(s.$1, color: s.$4, size: 20),
              ),
              const SizedBox(height: 12),
              Text(
                s.$3,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary(isDark),
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s.$2,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppTheme.textPrimary(isDark),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────
// FEATURES (bento grid)
// ─────────────────────────────────────────────

class _FeaturesSection extends StatelessWidget {
  final bool isDark;
  const _FeaturesSection({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isWide = MediaQuery.of(context).size.width >= 768;

    void goLogin() => Navigator.pushNamed(context, '/login');

    void navigateCargo() {
      if (!auth.isAuthenticated) { goLogin(); return; }
      if (auth.isShipper || auth.isCarrierCarga || auth.isDispatcher) {
        Navigator.pushNamed(context, auth.homeRoute);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Esta función es solo para usuarios de la plataforma de carga'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }

    void navigateDirectorio() {
      if (!auth.isAuthenticated) { goLogin(); return; }
      Navigator.pushNamed(context, '/carrier-directory');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Todo lo que necesitas',
          style: GoogleFonts.plusJakartaSans(
            fontSize: isWide ? 36 : 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Una plataforma. Cuatro herramientas clave.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppTheme.textSecondary(isDark),
          ),
        ),
        const SizedBox(height: 32),
        if (isWide)
          _WideBentoGrid(isDark: isDark, navigateCargo: navigateCargo, navigateDirectorio: navigateDirectorio)
        else
          _NarrowBentoGrid(isDark: isDark, navigateCargo: navigateCargo, navigateDirectorio: navigateDirectorio),
      ],
    );
  }
}

class _WideBentoGrid extends StatelessWidget {
  final bool isDark;
  final VoidCallback navigateCargo;
  final VoidCallback navigateDirectorio;
  const _WideBentoGrid({required this.isDark, required this.navigateCargo, required this.navigateDirectorio});

  @override
  Widget build(BuildContext context) {
    // 2x2 bento with visual variety per cell
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cell 1: Combustible — dark accent blue background
            Expanded(
              flex: 5,
              child: _BentoCell(
                isDark: isDark,
                icon: Icons.local_gas_station_rounded,
                title: 'Combustible',
                description: 'Localiza estaciones con los mejores precios en tu ruta y ahorra en cada viaje.',
                accentColor: LandingScreen.kBlue,
                bgColor: isDark ? const Color(0xFF0D2A6B) : const Color(0xFFEEF3FF),
                onTap: null,
                showArrow: false,
              ),
            ),
            const SizedBox(width: 14),
            // Cell 2: Mapa — orange accent background
            Expanded(
              flex: 5,
              child: _BentoCell(
                isDark: isDark,
                icon: Icons.map_rounded,
                title: 'Mapa Interactivo',
                description: 'Ve cargas activas, estaciones y transportistas en tiempo real sobre el mapa.',
                accentColor: LandingScreen.kAccent,
                bgColor: isDark ? const Color(0xFF3D1A00) : const Color(0xFFFFF4EC),
                onTap: null,
                showArrow: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cell 3: Cargas — green accent, wide
            Expanded(
              flex: 6,
              child: _BentoCell(
                isDark: isDark,
                icon: Icons.inventory_2_rounded,
                title: 'Cargas',
                description: 'Publica y acepta cargas como Shipper o Transportista. Gestion completa desde la app.',
                accentColor: const Color(0xFF22C55E),
                bgColor: isDark ? const Color(0xFF0D2B1A) : const Color(0xFFECFDF5),
                onTap: navigateCargo,
                showArrow: true,
              ),
            ),
            const SizedBox(width: 14),
            // Cell 4: Transportistas — purple accent
            Expanded(
              flex: 4,
              child: _BentoCell(
                isDark: isDark,
                icon: Icons.people_alt_rounded,
                title: 'Directorio',
                description: 'Transportistas verificados filtrados por flota y ubicacion.',
                accentColor: const Color(0xFF8B5CF6),
                bgColor: isDark ? const Color(0xFF1E0A3C) : const Color(0xFFF5F3FF),
                onTap: navigateDirectorio,
                showArrow: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NarrowBentoGrid extends StatelessWidget {
  final bool isDark;
  final VoidCallback navigateCargo;
  final VoidCallback navigateDirectorio;
  const _NarrowBentoGrid({required this.isDark, required this.navigateCargo, required this.navigateDirectorio});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _BentoCell(
          isDark: isDark,
          icon: Icons.local_gas_station_rounded,
          title: 'Combustible',
          description: 'Localiza estaciones con los mejores precios en tu ruta.',
          accentColor: LandingScreen.kBlue,
          bgColor: isDark ? const Color(0xFF0D2A6B) : const Color(0xFFEEF3FF),
          onTap: null,
          showArrow: false,
        ),
        const SizedBox(height: 12),
        _BentoCell(
          isDark: isDark,
          icon: Icons.map_rounded,
          title: 'Mapa Interactivo',
          description: 'Ve cargas activas, estaciones y transportistas en tiempo real.',
          accentColor: LandingScreen.kAccent,
          bgColor: isDark ? const Color(0xFF3D1A00) : const Color(0xFFFFF4EC),
          onTap: null,
          showArrow: false,
        ),
        const SizedBox(height: 12),
        _BentoCell(
          isDark: isDark,
          icon: Icons.inventory_2_rounded,
          title: 'Cargas',
          description: 'Publica y acepta cargas como Shipper o Transportista.',
          accentColor: const Color(0xFF22C55E),
          bgColor: isDark ? const Color(0xFF0D2B1A) : const Color(0xFFECFDF5),
          onTap: navigateCargo,
          showArrow: true,
        ),
        const SizedBox(height: 12),
        _BentoCell(
          isDark: isDark,
          icon: Icons.people_alt_rounded,
          title: 'Directorio',
          description: 'Transportistas verificados filtrados por flota y ubicacion.',
          accentColor: const Color(0xFF8B5CF6),
          bgColor: isDark ? const Color(0xFF1E0A3C) : const Color(0xFFF5F3FF),
          onTap: navigateDirectorio,
          showArrow: true,
        ),
      ],
    );
  }
}

class _BentoCell extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final Color bgColor;
  final VoidCallback? onTap;
  final bool showArrow;

  const _BentoCell({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.bgColor,
    required this.onTap,
    required this.showArrow,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const Spacer(),
              if (showArrow)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 15,
                    color: accentColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: AppTheme.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.5,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: content,
    );
  }
}

// ─────────────────────────────────────────────
// PRICING SECTION
// ─────────────────────────────────────────────

class _PricingSection extends StatelessWidget {
  final bool isDark;
  const _PricingSection({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Planes y Precios',
          style: GoogleFonts.plusJakartaSans(
            fontSize: isWide ? 36 : 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.0,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Elige el plan que mejor se adapta a tu operacion.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppTheme.textSecondary(isDark),
          ),
        ),
        const SizedBox(height: 12),
        // Transportistas
        Text(
          'Transportistas',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: LandingScreen.kBlue,
          ),
        ),
        const SizedBox(height: 16),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PlanCard(
                  isDark: isDark,
                  tag: 'BASICO',
                  price: r'$20',
                  perks: const [
                    'Cargas con 30 min de retraso',
                    'Aceptar cargas',
                    'Cargas recomendadas',
                  ],
                  ctaLabel: 'Seleccionar Basico',
                  ctaFilled: false,
                  accentColor: LandingScreen.kBlue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _PlanCard(
                  isDark: isDark,
                  tag: 'PRO',
                  price: r'$40',
                  badge: '3 meses GRATIS',
                  perks: const [
                    'Acceso instantaneo a cargas',
                    'Mapa avanzado con zonas clave',
                    'Recomendaciones por ubicacion',
                  ],
                  ctaLabel: 'Seleccionar Pro',
                  ctaFilled: true,
                  accentColor: LandingScreen.kAccent,
                  highlight: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _PlanCard(
                  isDark: isDark,
                  tag: 'DISPATCHERS',
                  price: r'$150',
                  perks: const [
                    'Todo lo del plan Pro',
                    'Gestion de multiples vehiculos',
                    'Asignacion de rutas avanzadas',
                  ],
                  ctaLabel: 'Seleccionar Dispatcher',
                  ctaFilled: false,
                  accentColor: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              _PlanCard(
                isDark: isDark,
                tag: 'BASICO',
                price: r'$20',
                perks: const [
                  'Cargas con 30 min de retraso',
                  'Aceptar cargas',
                  'Cargas recomendadas',
                ],
                ctaLabel: 'Seleccionar Basico',
                ctaFilled: false,
                accentColor: LandingScreen.kBlue,
              ),
              const SizedBox(height: 16),
              _PlanCard(
                isDark: isDark,
                tag: 'PRO',
                price: r'$40',
                badge: '3 meses GRATIS',
                perks: const [
                  'Acceso instantaneo a cargas',
                  'Mapa avanzado con zonas clave',
                  'Recomendaciones por ubicacion',
                ],
                ctaLabel: 'Seleccionar Pro',
                ctaFilled: true,
                accentColor: LandingScreen.kAccent,
                highlight: true,
              ),
              const SizedBox(height: 16),
              _PlanCard(
                isDark: isDark,
                tag: 'DISPATCHERS',
                price: r'$150',
                perks: const [
                  'Todo lo del plan Pro',
                  'Gestion de multiples vehiculos',
                  'Asignacion de rutas avanzadas',
                ],
                ctaLabel: 'Seleccionar Dispatcher',
                ctaFilled: false,
                accentColor: const Color(0xFF8B5CF6),
              ),
            ],
          ),
        const SizedBox(height: 40),
        // Clientes
        Text(
          'Clientes / MiPyMES',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: LandingScreen.kBlue,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWide ? 440 : double.infinity),
          child: _PlanCard(
            isDark: isDark,
            tag: 'PLAN UNICO',
            price: r'$50',
            badge: 'Primeros 3 meses GRATIS',
            perks: const [
              'Crear cargas ilimitadas',
              'Mapa interactivo de choferes',
              'Rating e informacion detallada de choferes',
            ],
            ctaLabel: 'Seleccionar Plan Unico',
            ctaFilled: true,
            accentColor: LandingScreen.kBlue,
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool isDark;
  final String tag;
  final String price;
  final String? badge;
  final List<String> perks;
  final String ctaLabel;
  final bool ctaFilled;
  final bool highlight;
  final Color accentColor;

  const _PlanCard({
    required this.isDark,
    required this.tag,
    required this.price,
    required this.perks,
    required this.ctaLabel,
    required this.accentColor,
    this.badge,
    this.ctaFilled = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, highlight ? -6 : 0),
      child: Container(
        decoration: BoxDecoration(
          color: highlight
              ? (isDark ? const Color(0xFF1C1A12) : const Color(0xFFFFF8F2))
              : AppTheme.card(isDark).withValues(alpha: isDark ? 0.88 : 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlight ? accentColor : AppTheme.border(isDark),
            width: highlight ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: highlight
                  ? accentColor.withValues(alpha: isDark ? 0.25 : 0.14)
                  : Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
              blurRadius: highlight ? 32 : 16,
              offset: Offset(0, highlight ? 12 : 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: isDark ? 0.16 : 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          badge!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF22C55E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: price,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -2.0,
                            color: AppTheme.textPrimary(isDark),
                          ),
                        ),
                        TextSpan(
                          text: ' /mes',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final perk in perks) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            perk,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              height: 1.45,
                              color: AppTheme.textPrimary(isDark),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ctaFilled
                        ? Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  accentColor,
                                  Color.lerp(accentColor, Colors.white, 0.25) ?? accentColor,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withValues(alpha: 0.30),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: Text(ctaLabel),
                            ),
                          )
                        : OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: BorderSide(color: accentColor, width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: Text(ctaLabel),
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

// ─────────────────────────────────────────────
// FOOTER
// ─────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final bool isDark;
  const _Footer({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;
    return Column(
      children: [
        Container(
          height: 1,
          color: AppTheme.border(isDark),
        ),
        const SizedBox(height: 32),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand column
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Logo(isDark: isDark),
                    const SizedBox(height: 12),
                    Text(
                      'Logistica inteligente para\ntransportistas modernos.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        height: 1.6,
                        color: AppTheme.textSecondary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              // Links columns
              Expanded(
                flex: 2,
                child: _FooterColumn(
                  isDark: isDark,
                  title: 'Producto',
                  links: const ['Funciones', 'Precios', 'Transportistas', 'Cargas'],
                ),
              ),
              Expanded(
                flex: 2,
                child: _FooterColumn(
                  isDark: isDark,
                  title: 'Empresa',
                  links: const ['Acerca de', 'Contacto', 'Terminos', 'Privacidad'],
                ),
              ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Logo(isDark: isDark),
              const SizedBox(height: 10),
              Text(
                'Logistica inteligente para transportistas modernos.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.6,
                  color: AppTheme.textSecondary(isDark),
                ),
              ),
            ],
          ),
        const SizedBox(height: 28),
        Container(height: 1, color: AppTheme.border(isDark)),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              '© ${DateTime.now().year} Muevete.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.textTertiary(isDark),
              ),
            ),
            const Spacer(),
            Text(
              'Hecho con precision.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppTheme.textTertiary(isDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FooterColumn extends StatelessWidget {
  final bool isDark;
  final String title;
  final List<String> links;
  const _FooterColumn({required this.isDark, required this.title, required this.links});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(isDark),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 12),
        for (final link in links) ...[
          Text(
            link,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
