import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/ventiq_home_theme.dart';

/// La tarjeta virtual "Tienda": agrupa todo lo que **no** es especial.
///
/// No es una `TarjetaExploracion` con otro color: es horizontal y ancha, y su
/// trabajo es distinto. Las especiales son puertas directas (tocar →
/// subcategorías); esta es una **puerta a una lista**, y por eso lleva la
/// cuenta de categorías a la vista y una flecha a la derecha que anticipa "aquí
/// entras y hay más".
///
/// Se pinta **después** de la grilla de especiales, a ancho completo, para que
/// se lea como el cajón donde va todo lo demás.
class TiendaCard extends StatelessWidget {
  const TiendaCard({
    super.key,
    required this.categorias,
    required this.productos,
    required this.onTap,
    this.nombre = 'Tienda',
  });

  /// Cuántas categorías agrupa.
  final int categorias;

  /// Cuántos productos hay dentro. Se usa para el subtítulo.
  final int productos;

  /// Nombre de la tienda (D2). Sale de `app_dat_tienda.denominacion`; si no se
  /// pudo leer, cae a «Tienda».
  final String nombre;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // «categ» y no «rubros»: es la palabra que usa el negocio (y el gerente)
    // para estas agrupaciones del catálogo.
    final String sub =
        productos > 0
            ? '$productos producto${productos == 1 ? '' : 's'} en $categorias categ'
            : '$categorias categ';

    return Semantics(
      button: true,
      label: '$nombre. $sub',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VentiqHomeTheme.sectionPadding,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusCard),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[Color(0xFF424A65), Color(0xFF2C3654)],
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                child: Stack(
                  children: <Widget>[
                    // Marca de agua, igual que en las tarjetas de la grilla.
                    Positioned(
                      right: -14,
                      bottom: -20,
                      child: Icon(
                        Icons.storefront_rounded,
                        size: 96,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(
                                VentiqHomeTheme.radiusTile,
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              size: 21,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          VentiqHomeTheme.radiusChip,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.22,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '$categorias CATEG',
                                        style: VentiqHomeTheme.chipTarjeta,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: VentiqHomeTheme.subtituloTarjeta,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
