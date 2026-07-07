import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Encabezado de marca para las pantallas de acceso (login / registro).
///
/// Da jerarquía al título: una línea "eyebrow" discreta, el wordmark
/// "GoReserva" pintado con el degradado de marca (azul → cyan) vía [ShaderMask]
/// para que combine con los gradientes de la app, y un subtítulo secundario.
class BrandTitle extends StatelessWidget {
  /// Línea superior corta y espaciada, p. ej. "BIENVENIDO A".
  final String eyebrow;

  /// Frase de apoyo bajo el wordmark, p. ej. "Inicia sesión para continuar".
  final String subtitle;

  const BrandTitle({
    super.key,
    required this.eyebrow,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          eyebrow.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: AppTheme.textSecondary.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 6),
        // Wordmark con degradado de marca. El ShaderMask tiñe el texto (que se
        // pinta en blanco) con el gradiente diagonal primary → accent.
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primary, AppTheme.accent],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: const Text(
            'GoReserva',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.05,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            color: AppTheme.textSecondary,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
