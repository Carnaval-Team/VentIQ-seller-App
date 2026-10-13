import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Pista flotante que señala el botón de filtros ("búsqueda avanzada").
///
/// Se coloca con `CompositedTransformFollower` **fuera** de este widget, para
/// que la flecha caiga justo debajo del botón real aunque cambie el alto de la
/// cabecera (safe area, fuente del sistema, textos a dos líneas...). Aquí vive
/// solo el contenido, que es lo que se puede probar sin montar la pantalla.
class PistaBusquedaAvanzada extends StatelessWidget {
  const PistaBusquedaAvanzada({
    super.key,
    required this.onTap,
    required this.onCerrar,
  });

  /// Tocar el cuerpo: abre el sheet de filtros.
  final VoidCallback onTap;

  /// Cerrar la pista (no vuelve a salir).
  final VoidCallback onCerrar;

  /// Marca de la flecha, para poder comprobarla en los tests.
  static const Key claveFlecha = Key('pista-filtros-flecha');

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Flecha hacia el botón: mismo blanco que la tarjeta para que se lean
          // como una sola pieza.
          const Padding(
            padding: EdgeInsets.only(right: 15),
            child: CustomPaint(
              key: claveFlecha,
              size: Size(20, 10),
              painter: _FlechaArriba(),
            ),
          ),
          Material(
            color: Colors.white,
            elevation: 6,
            shadowColor: AppTheme.primaryDark.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¿No encuentras lo que buscas?',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Haz una búsqueda avanzada aquí: precio, '
                            'valoración, establecimiento y más.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.3,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Cerrar: 44×44 de área táctil (no solo el icono de 17), que es lo
                    // que pide el estándar de Material para un toque cómodo.
                    GestureDetector(
                      onTap: onCerrar,
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.close_rounded,
                          size: 17,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Triángulo blanco apuntando hacia arriba, para unir la pista con el botón.
class _FlechaArriba extends CustomPainter {
  const _FlechaArriba();

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint()..color = Colors.white;
    final camino = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(camino, pincel);
  }

  @override
  bool shouldRepaint(covariant _FlechaArriba oldDelegate) => false;
}
