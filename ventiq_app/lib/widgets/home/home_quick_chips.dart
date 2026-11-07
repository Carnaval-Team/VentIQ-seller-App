import 'package:flutter/material.dart';

import '../../theme/ventiq_home_theme.dart';

/// Chip de filtro rápido del Home ("Solo con stock", "Promociones", la tasa
/// del día).
///
/// Port de `_QuickChip` de `inventtia_flow` con su misma gramática visual: pill
/// de radio 16, fondo `surface` con borde cuando está apagado y tinte del
/// primario con borde marcado cuando está encendido. El estado seleccionado se
/// tiene que leer de un vistazo y a 28 px de alto.
class HomeQuickChip extends StatelessWidget {
  const HomeQuickChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icono,
    this.selected = false,
    this.live = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icono;

  /// Filtro puesto.
  final bool selected;

  /// Dato vivo (se refresca solo). Pinta un punto verde en vez de selección.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final Color fondo = selected
        ? VentiqHomeTheme.primary.withValues(alpha: 0.10)
        : live
            ? VentiqHomeTheme.success.withValues(alpha: 0.08)
            : VentiqHomeTheme.surface;

    final Color borde = selected
        ? VentiqHomeTheme.primary.withValues(alpha: 0.35)
        : VentiqHomeTheme.border;

    final Color texto = selected
        ? VentiqHomeTheme.primary
        : VentiqHomeTheme.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borde),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (live) ...<Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: VentiqHomeTheme.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else if (icono != null) ...<Widget>[
                  Icon(icono, size: 13, color: texto),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: texto,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Riel horizontal de chips rápidos, con el alto justo para que no se coma el
/// scroll del Home.
class HomeQuickChips extends StatelessWidget {
  const HomeQuickChips({super.key, required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: VentiqHomeTheme.sectionPadding,
        ),
        children: chips,
      ),
    );
  }
}
