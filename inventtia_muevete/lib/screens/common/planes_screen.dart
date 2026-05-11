import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/plan_model.dart';
import '../../providers/plan_provider.dart';
import '../../providers/theme_provider.dart';

class PlanesScreen extends StatefulWidget {
  // tipoUsuario: 'shipper' | 'carrier' | 'dispatcher'
  final String tipoUsuario;
  const PlanesScreen({super.key, required this.tipoUsuario});

  @override
  State<PlanesScreen> createState() => _PlanesScreenState();
}

class _PlanesScreenState extends State<PlanesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlanProvider>().cargarPlanes(widget.tipoUsuario);
    });
  }

  String get _headerTitle {
    switch (widget.tipoUsuario) {
      case 'shipper':
        return 'Elige tu plan para publicar cargas';
      case 'carrier':
        return 'Elige tu plan para recibir cargas';
      case 'dispatcher':
        return 'Elige tu plan de gestión de flota';
      default:
        return 'Planes disponibles';
    }
  }

  String get _headerSubtitle {
    switch (widget.tipoUsuario) {
      case 'shipper':
        return 'Publica cargas, conecta con transportistas verificados y gestiona tus envíos.';
      case 'carrier':
        return 'Recibe cargas, aumenta tu visibilidad y accede a herramientas de tracking.';
      case 'dispatcher':
        return 'Gestiona tu flota, asigna cargas y maximiza la productividad de tus choferes.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final provider = context.watch<PlanProvider>();
    final planes = provider.planesParaTipo(widget.tipoUsuario);

    final bg = AppTheme.bg(isDark);
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Planes',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : provider.error != null
              ? _ErrorState(
                  message: provider.error!,
                  onRetry: () =>
                      context.read<PlanProvider>().cargarPlanes(widget.tipoUsuario),
                )
              : planes.isEmpty
                  ? _EmptyState(textSecondary: textSecondary)
                  : _PlanesContent(
                      planes: planes,
                      tipoUsuario: widget.tipoUsuario,
                      headerTitle: _headerTitle,
                      headerSubtitle: _headerSubtitle,
                      isDark: isDark,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PlanesContent extends StatelessWidget {
  final List<PlanModel> planes;
  final String tipoUsuario;
  final String headerTitle;
  final String headerSubtitle;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _PlanesContent({
    required this.planes,
    required this.tipoUsuario,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  // El plan "más popular" es el de precio medio (índice 1 si hay ≥2)
  int get _popularIndex => planes.length >= 2 ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Header
        Text(
          headerTitle,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          headerSubtitle,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        // Tarjetas de planes
        ...planes.asMap().entries.map((entry) {
          final index = entry.key;
          final plan = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _PlanCard(
              plan: plan,
              isPopular: index == _popularIndex && planes.length > 1,
              isDark: isDark,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          );
        }),
        // FAQ por tipo
        const SizedBox(height: 8),
        _FaqSection(tipoUsuario: tipoUsuario, isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final PlanModel plan;
  final bool isPopular;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _PlanCard({
    required this.plan,
    required this.isPopular,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = AppTheme.card(isDark);
    final border = isPopular
        ? AppTheme.primaryColor
        : AppTheme.border(isDark);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: isPopular ? 2 : 1),
        boxShadow: isPopular
            ? [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge "Más popular"
          if (isPopular)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Text(
                'MÁS POPULAR',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre + precio
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      plan.nombre,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (plan.esGratis)
                      Text(
                        'Gratis',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.success,
                        ),
                      )
                    else ...[
                      Text(
                        '\$${plan.precioMensual.toStringAsFixed(0)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: isPopular ? AppTheme.primaryColor : textPrimary,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '/mes',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                // Características
                ..._buildFeatures(context),
                const SizedBox(height: 20),
                // Botón
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: null, // Suscripción diferida a Fase 2
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPopular
                          ? AppTheme.primaryColor
                          : AppTheme.border(isDark),
                      foregroundColor: isPopular ? Colors.white : textPrimary,
                      disabledBackgroundColor: isPopular
                          ? AppTheme.primaryColor.withValues(alpha: 0.5)
                          : AppTheme.border(isDark),
                      disabledForegroundColor: isPopular
                          ? Colors.white70
                          : textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      plan.esGratis ? 'Plan actual' : 'Próximamente',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFeatures(BuildContext context) {
    final features = <_Feature>[];

    // Cargas/mes
    if (plan.cargasMesMax != null) {
      features.add(_Feature(
        icon: Icons.inventory_2_outlined,
        label: '${plan.cargasMesMax} cargas / mes',
      ));
    } else {
      features.add(const _Feature(
        icon: Icons.all_inclusive_rounded,
        label: 'Cargas ilimitadas',
        highlighted: true,
      ));
    }

    // Comisión escrow
    if (plan.escrowComision != null) {
      features.add(_Feature(
        icon: Icons.lock_outline_rounded,
        label: 'Escrow: ${plan.escrowComision!.toStringAsFixed(1)}% comisión',
        included: plan.escrowIncluido,
      ));
    }

    // Matching
    if (plan.matchingAuto) {
      features.add(_Feature(
        icon: Icons.auto_awesome_rounded,
        label: plan.matchingDiarioMax != null
            ? 'Matching automático (${plan.matchingDiarioMax}/día)'
            : 'Matching automático ilimitado',
        highlighted: true,
      ));
    }

    // Verificación MC/DOT
    if (plan.verificacionMc) {
      features.add(const _Feature(
        icon: Icons.verified_outlined,
        label: 'Verificación MC/DOT incluida',
        highlighted: true,
      ));
    }

    // GPS avanzado
    if (plan.gpsAvanzado) {
      features.add(const _Feature(
        icon: Icons.gps_fixed_rounded,
        label: 'GPS tracking avanzado',
      ));
    }

    // Alertas push
    if (plan.alertasPush) {
      features.add(const _Feature(
        icon: Icons.notifications_active_outlined,
        label: 'Alertas push ilimitadas',
      ));
    }

    // Ventana exclusiva
    if (plan.ventanaExclusivaHoras != null) {
      features.add(_Feature(
        icon: Icons.access_time_filled_rounded,
        label: '${plan.ventanaExclusivaHoras}h de acceso anticipado a cargas',
        highlighted: true,
      ));
    }

    // Multi-usuarios
    if (plan.multiUsuarios > 1) {
      features.add(_Feature(
        icon: Icons.group_outlined,
        label: 'Hasta ${plan.multiUsuarios} sub-usuarios',
      ));
    }

    // Dashboard
    if (plan.dashboardNivel != 'ninguno') {
      features.add(_Feature(
        icon: Icons.bar_chart_rounded,
        label: 'Dashboard ${plan.dashboardNivel}',
      ));
    }

    // Soporte
    features.add(_Feature(
      icon: Icons.support_agent_outlined,
      label: 'Soporte por ${plan.soporteNivel}'
          '${plan.soporteSlaH != null ? ' (SLA ${plan.soporteSlaH}h)' : ''}',
    ));

    return features
        .map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: f,
            ))
        .toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Feature extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool included;
  final bool highlighted;

  const _Feature({
    required this.icon,
    required this.label,
    this.included = true,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final color = !included
        ? AppTheme.textSecondary(isDark)
        : highlighted
            ? AppTheme.primaryColor
            : AppTheme.textPrimary(isDark);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          included ? icon : Icons.remove_rounded,
          size: 17,
          color: color,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13.5,
              color: color,
              fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
              decoration: !included ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FaqSection extends StatelessWidget {
  final String tipoUsuario;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _FaqSection({
    required this.tipoUsuario,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  List<Map<String, String>> get _faqs {
    switch (tipoUsuario) {
      case 'shipper':
        return [
          {
            'q': '¿Qué es el escrow?',
            'a':
                'El escrow retiene el pago hasta que el transportista confirma la entrega. El dinero se libera automáticamente o puedes objetar si hay un problema.',
          },
          {
            'q': '¿Puedo cancelar en cualquier momento?',
            'a':
                'Sí. Puedes cancelar tu suscripción en cualquier momento desde tu perfil. El plan sigue activo hasta el final del período pagado.',
          },
        ];
      case 'carrier':
        return [
          {
            'q': '¿Cómo funciona la verificación MC/DOT?',
            'a':
                'Verificamos tu número MC y DOT con la base de datos FMCSA. Una vez verificado, tu perfil muestra el badge de confianza.',
          },
          {
            'q': '¿Qué diferencia al plan Básico del Profesional?',
            'a':
                'El plan Profesional te da acceso a escrow, GPS avanzado, alertas ilimitadas y verificación MC incluida.',
          },
        ];
      case 'dispatcher':
        return [
          {
            'q': '¿Cómo invito a mis choferes?',
            'a':
                'Desde tu panel de flota puedes enviar invitaciones por email. Cada chofer recibe un link para activar su cuenta y quedar vinculado a tu dispatcher.',
          },
          {
            'q': '¿Qué es el factoraje de fletes?',
            'a':
                'El factoraje te permite adelantar el cobro de tus fletes antes de que el shipper pague, a cambio de una comisión.',
          },
        ];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_faqs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preguntas frecuentes',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ..._faqs.map(
          (faq) => _FaqItem(
            question: faq['q']!,
            answer: faq['a']!,
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
        ),
      ],
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _FaqItem({
    required this.question,
    required this.answer,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.card(widget.isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border(widget.isDark)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          onExpansionChanged: (v) => setState(() => _expanded = v),
          trailing: Icon(
            _expanded ? Icons.remove_rounded : Icons.add_rounded,
            size: 20,
            color: widget.textSecondary,
          ),
          title: Text(
            widget.question,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: widget.textPrimary,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                widget.answer,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  color: widget.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Color textSecondary;
  const _EmptyState({required this.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No hay planes disponibles por el momento.',
        style: GoogleFonts.plusJakartaSans(color: textSecondary),
      ),
    );
  }
}
