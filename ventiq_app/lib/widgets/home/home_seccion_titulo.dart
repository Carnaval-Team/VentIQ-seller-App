import 'package:flutter/material.dart';

import '../../theme/ventiq_home_theme.dart';

/// Rótulo de bloque del Home, con acción opcional a la derecha.
///
/// Es deliberadamente un **rótulo** y no un titular: mayúsculas, 12.5 px, mucho
/// espaciado entre letras. Lo que titula de verdad es la tarjeta que viene
/// debajo; el rótulo solo ordena.
///
/// La acción ("Ver tienda ›") se pinta en el cian de acento y con `tapTarget`
/// reducido, porque vive pegada al borde derecho y no debe robarle ancho al
/// rótulo.
class HomeSeccionTitulo extends StatelessWidget {
  const HomeSeccionTitulo({
    super.key,
    required this.rotulo,
    this.accionEtiqueta,
    this.onAccion,
    this.icono,
  }) : assert(
          (accionEtiqueta == null) == (onAccion == null),
          'La acción necesita etiqueta y callback, o ninguno de los dos',
        );

  final String rotulo;
  final String? accionEtiqueta;
  final VoidCallback? onAccion;

  /// Icono opcional antes del rótulo (se usa en el drawer).
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final String? etiqueta = accionEtiqueta;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VentiqHomeTheme.sectionPadding,
      ),
      child: Row(
        children: <Widget>[
          if (icono != null) ...<Widget>[
            Icon(icono, size: 15, color: VentiqHomeTheme.textSecondary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              rotulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VentiqHomeTheme.rotuloBloque,
            ),
          ),
          if (etiqueta != null)
            TextButton(
              onPressed: onAccion,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(etiqueta, style: VentiqHomeTheme.accionSeccion),
            ),
        ],
      ),
    );
  }
}
