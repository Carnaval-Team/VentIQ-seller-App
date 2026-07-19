import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Envuelve una tarjeta y le dibuja encima una cinta diagonal roja de esquina a
/// esquina con el texto "CANCELADO". La tarjeta queda ligeramente atenuada para
/// comunicar el estado sin perder legibilidad.
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
    final diag = math.sqrt(size.width * size.width + size.height * size.height);
    final angle = -math.atan2(size.height, size.width);
    final bandHeight = 26.0;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: diag,
      height: bandHeight,
    );

    // Franja roja semitransparente con degradado sutil.
    final bandPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.error.withValues(alpha: 0.92),
          const Color(0xFFB71C1C).withValues(alpha: 0.92),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bandPaint);

    // Líneas finas de borde para dar acabado.
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(-diag / 2, -bandHeight / 2), Offset(diag / 2, -bandHeight / 2),
        borderPaint);
    canvas.drawLine(
        Offset(-diag / 2, bandHeight / 2), Offset(diag / 2, bandHeight / 2),
        borderPaint);

    // Texto centrado sobre la franja.
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
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
