import 'package:flutter/material.dart';

import '../../theme/ventiq_home_theme.dart';

/// Estado vacío del Home: no hay categorías, no hay resultados, o el catálogo
/// aún está cargando por primera vez.
///
/// Un solo widget para los tres casos porque el patrón visual es el mismo
/// (icono apagado + título + explicación + acción opcional). Tener tres
/// pantallas casi iguales fue justo lo que hizo que el Home viejo acabara con
/// mensajes distintos para el mismo problema.
class HomeEstadoVacio extends StatelessWidget {
  const HomeEstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    this.mensaje,
    this.accionEtiqueta,
    this.onAccion,
    this.compacto = false,
  }) : assert(
          (accionEtiqueta == null) == (onAccion == null),
          'La acción necesita etiqueta y callback, o ninguno de los dos',
        );

  final IconData icono;
  final String titulo;
  final String? mensaje;
  final String? accionEtiqueta;
  final VoidCallback? onAccion;

  /// Para meterlo dentro del drawer o de un bloque, en vez de a pantalla
  /// completa.
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final String? texto = mensaje;
    final String? etiqueta = accionEtiqueta;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 32,
          vertical: compacto ? 24 : 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icono,
              size: compacto ? 40 : 64,
              color: VentiqHomeTheme.textSecondary.withValues(alpha: 0.45),
            ),
            SizedBox(height: compacto ? 10 : 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compacto ? 14 : 16,
                fontWeight: FontWeight.w700,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
            if (texto != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                texto,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compacto ? 12 : 13,
                  height: 1.35,
                  color: VentiqHomeTheme.textSecondary,
                ),
              ),
            ],
            if (etiqueta != null) ...<Widget>[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAccion,
                style: FilledButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  etiqueta,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado de error del Home, con reintento.
///
/// Separado del vacío a propósito: "no hay nada" y "no pudimos cargarlo" son
/// cosas distintas y el vendedor necesita saber cuál es. En inventtia_flow esta
/// distinción existe y se ganó a pulso (distingue "falta migración" de "sin
/// conexión"); aquí el caso real del TPV es "sin conexión" contra "sin
/// categorías con productos".
class HomeEstadoError extends StatelessWidget {
  const HomeEstadoError({
    super.key,
    required this.onReintentar,
    this.titulo = 'No se pudo cargar el catálogo',
    this.mensaje =
        'Revisa la conexión y vuelve a intentarlo. Si el problema sigue, '
        'avisa al administrador.',
  });

  final VoidCallback onReintentar;
  final String titulo;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return HomeEstadoVacio(
      icono: Icons.cloud_off_rounded,
      titulo: titulo,
      mensaje: mensaje,
      accionEtiqueta: 'Reintentar',
      onAccion: onReintentar,
    );
  }
}
