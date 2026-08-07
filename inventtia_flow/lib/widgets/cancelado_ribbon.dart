import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Envuelve una tarjeta y le dibuja encima una cinta diagonal de esquina a
/// esquina con el texto "CANCELADO". Fondo al 20% de opacidad y letras en rojo.
///
/// Uso:
///   CanceladoRibbon(child: miCard)
class CanceladoRibbon extends StatelessWidget {
  final Widget child;

  /// Texto de la cinta (por defecto "CANCELADO").
  final String texto;

  const CanceladoRibbon({
    super.key,
    required this.child,
    this.texto = 'CANCELADO',
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(opacity: 0.7, child: child),
        // La cinta se recorta al mismo radio de la tarjeta para no desbordar.
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                painter: _RibbonPainter(texto: texto),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final String texto;
  _RibbonPainter({required this.texto});

  @override
  void paint(Canvas canvas, Size size) {
    // Banda diagonal de esquina inferior-izquierda a superior-derecha.
    // Ancho = 3× el original (26 → 78).
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final angle = -math.atan2(size.height, size.width);
    const bandHeight = 78.0;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: diag,
      height: bandHeight,
    );

    // Fondo rojo al 20% de opacidad.
    final bandPaint = Paint()
      ..color = AppTheme.error.withValues(alpha: 0.20);
    canvas.drawRect(rect, bandPaint);

    // Texto centrado en rojo.
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: const TextStyle(
          color: AppTheme.error,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter oldDelegate) =>
      oldDelegate.texto != texto;
}
