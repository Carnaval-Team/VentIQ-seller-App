import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  // Brand accent — kept as orange highlight from the design reference
  static const Color kAccent = Color(0xFFFE6B00);

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

    // Wait for tipoUsuario to resolve (may still be loading)
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
          // Layer 2: tint + gradient to keep cards & text legible
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          AppTheme.darkBg.withValues(alpha: 0.35),
                          AppTheme.darkBg.withValues(alpha: 0.60),
                          AppTheme.darkBg.withValues(alpha: 0.80),
                        ]
                      : [
                          AppTheme.lightBg.withValues(alpha: 0.25),
                          AppTheme.lightBg.withValues(alpha: 0.50),
                          AppTheme.lightBg.withValues(alpha: 0.75),
                        ],
                  stops: const [0.0, 0.55, 1.0],
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
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 48,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Hero(isDark: isDark),
                            const SizedBox(height: 48),
                            _BentoGrid(isDark: isDark),
                            const SizedBox(height: 48),
                            _SectionTitle(
                              title: 'Planes Transportistas',
                              isDark: isDark,
                            ),
                            const SizedBox(height: 24),
                            _DriverPlans(isDark: isDark),
                            const SizedBox(height: 48),
                            _SectionTitle(
                              title: 'Plan Clientes / MiPyMES',
                              isDark: isDark,
                            ),
                            const SizedBox(height: 24),
                            _ClientPlan(isDark: isDark),
                            const SizedBox(height: 48),
                            _Footer(isDark: isDark),
                          ],
                        ),
                      ),
                    ),
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

// ---------- Top bar ----------

class _TopBar extends StatelessWidget {
  final bool isDark;
  const _TopBar({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(isDark).withValues(alpha: 0.70),
        border: Border(
          bottom: BorderSide(color: AppTheme.border(isDark), width: 1),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              child: Row(
                children: [
                  _Logo(isDark: isDark),
                  const Spacer(),
                  if (isWide) ...[
                    _NavLink(label: 'Precios', isDark: isDark, onTap: () {}),
                    const SizedBox(width: 8),
                    _NavLink(label: 'Acerca de', isDark: isDark, onTap: () {}),
                    const SizedBox(width: 8),
                    _NavLink(label: 'Contactos', isDark: isDark, onTap: () {}),
                    const SizedBox(width: 16),
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
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/images/logo.png',
            height: 36,
            width: 36,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.local_shipping,
              color: AppTheme.textPrimary(isDark),
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 8),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Muev',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: AppTheme.textPrimary(isDark),
                ),
              ),
              TextSpan(
                text: 'ete',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: AppTheme.primaryColor,
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
  const _NavLink({
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: GoogleFonts.inter(
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
          OutlinedButton(
            onPressed: () => Navigator.pushNamed(context, '/register'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textPrimary(isDark),
              side: BorderSide(
                color: AppTheme.textPrimary(isDark),
                width: 2,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Registrar'),
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton(
          onPressed: () => Navigator.pushNamed(context, '/login'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Iniciar'),
        ),
      ],
    );
  }
}

class _UserAvatarMenu extends StatelessWidget {
  final bool isDark;
  const _UserAvatarMenu({required this.isDark});

  String _initials(String? name, String? email) {
    final source = (name?.trim().isNotEmpty ?? false)
        ? name!.trim()
        : (email ?? '?');
    final parts =
        source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppTheme.surface(isDark),
      elevation: 8,
      onSelected: (value) async {
        if (value == 'viajes') {
          Navigator.pushNamedAndRemoveUntil(
              context, auth.homeRoute, (_) => false);
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
                  color: LandingScreen.kAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.route_rounded,
                  size: 18,
                  color: LandingScreen.kAccent,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Ir a mi panel',
                style: GoogleFonts.inter(
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
                child: const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: AppTheme.error,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Cerrar sesión',
                style: GoogleFonts.inter(
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
          border: Border.all(
            color: LandingScreen.kAccent,
            width: 2,
          ),
        ),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: AppTheme.primaryColor,
          child: Text(
            _initials(name, email),
            style: GoogleFonts.inter(
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

// ---------- Hero ----------

class _Hero extends StatelessWidget {
  final bool isDark;
  const _Hero({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Logística Inteligente y Eficiente',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: isWide ? 48 : 34,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -1.0,
            color: AppTheme.textPrimary(isDark),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            'Conectando transportistas con cargas en tiempo real. Optimiza tus rutas, encuentra combustible y gestiona tu flota con Muevete.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.5,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- Bento grid ----------

class _BentoGrid extends StatelessWidget {
  final bool isDark;
  const _BentoGrid({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isWide = MediaQuery.of(context).size.width >= 768;

    void goLogin() => Navigator.pushNamed(context, '/login');

    void navigateCargo() {
      if (!auth.isAuthenticated) { goLogin(); return; }
      if (auth.isShipper || auth.isCarrierCarga) {
        Navigator.pushNamed(context, auth.homeRoute);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Esta función es solo para Shippers y Transportistas de carga'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }

    void navigateDirectorio() {
      if (!auth.isAuthenticated) { goLogin(); return; }
      Navigator.pushNamed(context, '/carrier-directory');
    }

    final items = [
      (
        const _FeatureCardData(
          icon: Icons.local_gas_station_rounded,
          title: 'Combustible',
          description:
              'Sitios donde repostar combustible con los mejores precios en tu ruta.',
        ),
        null as VoidCallback?,
      ),
      (
        const _FeatureCardData(
          icon: Icons.map_rounded,
          title: 'Mapa',
          description:
              'Ver combustibles, cargas y transportistas en tiempo real.',
        ),
        null as VoidCallback?,
      ),
      (
        const _FeatureCardData(
          icon: Icons.inventory_2_rounded,
          title: 'Cargas',
          description:
              'Gestiona tus cargas como Shipper o revisa las cargas activas como Transportista.',
          tappable: true,
        ),
        navigateCargo,
      ),
      (
        const _FeatureCardData(
          icon: Icons.people_alt_rounded,
          title: 'Transportistas',
          description:
              'Directorio de transportistas verificados. Filtra por flota, ubicación y características.',
          tappable: true,
        ),
        navigateDirectorio,
      ),
    ];

    if (isWide) {
      return Wrap(
        spacing: 24,
        runSpacing: 24,
        children: [
          for (final item in items)
            SizedBox(
              width: (MediaQuery.of(context).size.width > 1120
                      ? 1120.0
                      : MediaQuery.of(context).size.width - 48) /
                  2 -
                  12,
              child: _FeatureCard(
                  data: item.$1, isDark: isDark, onTap: item.$2),
            ),
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _FeatureCard(
              data: items[i].$1, isDark: isDark, onTap: items[i].$2),
          if (i != items.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _FeatureCardData {
  final IconData icon;
  final String title;
  final String description;
  final bool tappable;
  const _FeatureCardData({
    required this.icon,
    required this.title,
    required this.description,
    this.tappable = false,
  });
}

class _FeatureCard extends StatelessWidget {
  final _FeatureCardData data;
  final bool isDark;
  final VoidCallback? onTap;
  const _FeatureCard(
      {required this.data, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark).withValues(alpha: isDark ? 0.88 : 0.94),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: data.tappable && onTap != null
              ? AppTheme.primaryColor.withValues(alpha: 0.35)
              : AppTheme.border(isDark),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.35)
                : const Color(0x140A1D37),
            blurRadius: 18,
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
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor
                      .withValues(alpha: isDark ? 0.18 : 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  data.icon,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
              ),
              const Spacer(),
              if (data.tappable && onTap != null)
                Icon(Icons.arrow_forward_rounded,
                    size: 18, color: AppTheme.primaryColor),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            data.title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.description,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.45,
              color: AppTheme.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: card,
    );
  }
}

// ---------- Section title ----------

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.primaryColor.withValues(alpha: 0.2),
            width: 2,
          ),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppTheme.textPrimary(isDark),
        ),
      ),
    );
  }
}

// ---------- Driver plans ----------

class _DriverPlans extends StatelessWidget {
  final bool isDark;
  const _DriverPlans({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 768;

    final plans = <Widget>[
      _PlanCard(
        isDark: isDark,
        tag: 'BÁSICO',
        tagBg: AppTheme.primaryColor.withValues(alpha: 0.15),
        tagFg: AppTheme.primaryColor,
        price: r'$20',
        perks: const [
          'Cargas con 30 min retraso',
          'Aceptar cargas',
          'Cargas recomendadas',
        ],
        ctaLabel: 'Seleccionar Básico',
        ctaFilled: false,
      ),
      _PlanCard(
        isDark: isDark,
        tag: 'PRO',
        tagBg: LandingScreen.kAccent,
        tagFg: Colors.white,
        price: r'$40',
        badge: '¡3 meses GRATIS!',
        perks: const [
          'Acceso instantáneo a cargas',
          'Mapa avanzado (zonas importantes)',
          'Recomendaciones por ubicación',
        ],
        ctaLabel: 'Seleccionar Pro',
        ctaFilled: true,
        highlight: true,
      ),
      _PlanCard(
        isDark: isDark,
        tag: 'DISPATCHERS',
        tagBg: isDark ? Colors.white12 : const Color(0xFF213145),
        tagFg: Colors.white,
        price: r'$150',
        perks: const [
          'Todo lo de Pro',
          'Gestión de múltiples vehículos',
          'Asignación de rutas avanzadas',
        ],
        ctaLabel: 'Seleccionar Dispatcher',
        ctaFilled: false,
      ),
    ];

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < plans.length; i++) ...[
            Expanded(child: plans[i]),
            if (i != plans.length - 1) const SizedBox(width: 24),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < plans.length; i++) ...[
          plans[i],
          if (i != plans.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _ClientPlan extends StatelessWidget {
  final bool isDark;
  const _ClientPlan({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: _PlanCard(
        isDark: isDark,
        tag: 'PLAN ÚNICO',
        tagBg: AppTheme.primaryColor,
        tagFg: Colors.white,
        price: r'$50',
        badge: '¡Primeros 3 meses GRATIS!',
        perks: const [
          'Crear cargas ilimitadas',
          'Mapa interactivo de choferes',
          'Ver rating e información detallada de choferes',
        ],
        ctaLabel: 'Seleccionar Plan Único',
        ctaFilled: true,
        ctaColor: AppTheme.primaryColor,
        checkColor: AppTheme.primaryColor,
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool isDark;
  final String tag;
  final Color tagBg;
  final Color tagFg;
  final String price;
  final String? badge;
  final List<String> perks;
  final String ctaLabel;
  final bool ctaFilled;
  final bool highlight;
  final Color? ctaColor;
  final Color? checkColor;

  const _PlanCard({
    required this.isDark,
    required this.tag,
    required this.tagBg,
    required this.tagFg,
    required this.price,
    required this.perks,
    required this.ctaLabel,
    this.badge,
    this.ctaFilled = false,
    this.highlight = false,
    this.ctaColor,
    this.checkColor,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedCtaColor = ctaColor ??
        (highlight ? LandingScreen.kAccent : AppTheme.primaryColor);
    final resolvedCheckColor = checkColor ??
        (highlight ? LandingScreen.kAccent : AppTheme.success);

    return Transform.translate(
      offset: Offset(0, highlight ? -8 : 0),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.card(isDark)
                  .withValues(alpha: isDark ? 0.88 : 0.94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: highlight
                    ? LandingScreen.kAccent
                    : AppTheme.border(isDark),
                width: highlight ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(
                          alpha: highlight ? 0.5 : 0.35,
                        )
                      : (highlight
                          ? const Color(0x260A1D37)
                          : const Color(0x140A1D37)),
                  blurRadius: highlight ? 28 : 18,
                  offset: Offset(0, highlight ? 10 : 6),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: price,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.0,
                              color: AppTheme.textPrimary(isDark),
                            ),
                          ),
                          TextSpan(
                            text: '/mes',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: AppTheme.textSecondary(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: highlight
                              ? LandingScreen.kAccent
                              : AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge!,
                          style: GoogleFonts.workSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                for (final perk in perks) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 20,
                        color: resolvedCheckColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          perk,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            height: 1.4,
                            color: AppTheme.textPrimary(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ctaFilled
                      ? ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: resolvedCtaColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(ctaLabel),
                        )
                      : OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary(isDark),
                            side: BorderSide(
                              color: AppTheme.textPrimary(isDark),
                              width: 2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(ctaLabel),
                        ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: tagBg,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: Text(
                tag,
                style: GoogleFonts.workSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: tagFg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Footer ----------

class _Footer extends StatelessWidget {
  final bool isDark;
  const _Footer({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Text(
          '© ${DateTime.now().year} Muevete. Logística en movimiento.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppTheme.textTertiary(isDark),
          ),
        ),
      ),
    );
  }
}
