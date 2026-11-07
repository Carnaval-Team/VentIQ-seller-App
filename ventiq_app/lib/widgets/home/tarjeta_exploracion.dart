import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/ventiq_home_theme.dart';

/// La tarjeta del Home (y del drawer): degradado o foto, chip de contexto,
/// icono, título, subtítulo y —opcionalmente— una acción en el pie.
///
/// Es la réplica de `TarjetaExploracion` de `inventtia_flow`
/// (`widgets/exploracion_rapida_grid.dart`), con una variante nueva: **modo
/// imagen de fondo**. En el catálogo del TPV (`app_dat_categoria.image`) la
/// mayoría de categorías no tiene foto, así que el degradado es el caso normal
/// y la imagen es la mejora — al revés que en el marketplace, donde casi todo
/// local tiene foto.
///
/// El widget es **tonto a propósito**: no pide datos, no navega y no conoce
/// ningún servicio. Recibe los callbacks ya resueltos, así se puede probar sin
/// Supabase y sin red, y el Home decide qué abre cada tarjeta.
class TarjetaExploracion extends StatelessWidget {
  const TarjetaExploracion({
    super.key,
    required this.chip,
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.colores,
    required this.onTap,
    this.imagenUrl,
    this.accionEtiqueta,
    this.onAccion,
    this.heroTag,
  }) : assert(colores.length >= 2, 'El degradado necesita al menos 2 colores');

  /// Etiqueta pequeña del ángulo superior izquierdo. Es contexto, no contenido:
  /// "3 PRODUCTOS", "ESPECIAL", "12 RUBROS".
  final String chip;

  final String titulo;
  final String subtitulo;
  final IconData icono;

  /// Dos colores: inicio (arriba-izquierda) y fin (abajo-derecha).
  final List<Color> colores;

  /// Toca la tarjeta entera. Abre el drawer.
  final VoidCallback onTap;

  /// Si viene, la tarjeta pinta la foto y el degradado pasa a ser el fondo de
  /// reserva mientras carga (y si falla).
  final String? imagenUrl;

  /// Acción secundaria del pie ("Ver todos").
  ///
  /// Tiene su **propio** gesto para que no se confunda con el toque de la
  /// tarjeta: tocar la tarjeta abre la carpeta y "Ver todos" va al listado.
  /// Son dos destinos distintos y el usuario pidió expresamente no mezclarlos.
  final String? accionEtiqueta;

  /// Con `null` el pie se pinta apagado y no responde: mantiene el alto de la
  /// tarjeta sin ofrecer un toque que no lleva a ningún sitio.
  final VoidCallback? onAccion;

  /// Para `Hero` desde otra pantalla (el detalle de producto lo reutiliza).
  final Object? heroTag;

  bool get _conImagen => imagenUrl != null && imagenUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final Widget tarjeta = ClipRRect(
      borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusCard),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // El degradado va SIEMPRE de fondo: con imagen queda oculto, pero
          // evita el fogonazo blanco mientras carga o si la URL falla.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colores,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // Respuesta táctil inmediata: en un TPV la gente toca rápido y
              // sin esto la tarjeta se siente muerta.
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (_conImagen) _fotoConVelo(context),
                if (!_conImagen) _marcaDeAgua(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Flexible(child: _Chip(texto: chip)),
                          const SizedBox(width: 6),
                          _TileIcono(icono: icono),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VentiqHomeTheme.tituloTarjeta,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: VentiqHomeTheme.subtituloTarjeta,
                      ),
                      if (accionEtiqueta != null) ...<Widget>[
                        const SizedBox(height: 7),
                        _AccionTarjeta(
                          etiqueta: accionEtiqueta!,
                          onTap: onAccion,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final Object? tag = heroTag;
    final Widget conHero = tag == null
        ? tarjeta
        : Hero(tag: tag, child: tarjeta);

    return Semantics(
      button: true,
      label: '$titulo. $subtitulo',
      child: conHero,
    );
  }

  /// Marca de agua: da profundidad sin competir con el texto. Es lo que separa
  /// una tarjeta "degradada" de una tarjeta barata.
  Widget _marcaDeAgua() => Positioned(
        right: -10,
        bottom: -14,
        child: Icon(
          icono,
          size: 76,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      );

  /// Foto de fondo + velo inferior.
  ///
  /// Usa `Image.network` a propósito, sin paquetes nuevos: Flutter ya cachea en
  /// memoria por `ImageCache`, y el TPV vive en una red local. Añadir
  /// `cached_network_image` (caché en disco) queda como mejora **solo si se
  /// mide** que hace falta: evitaba dos dependencias y su verificación en web y
  /// Windows justo en la fase más barata del rediseño.
  ///
  /// El velo **no es decorativo**: es lo que garantiza que el título blanco
  /// siga siendo legible sobre cualquier foto que suba el gerente, incluidas
  /// las claras. En `inventtia_flow` la `TarjetaColeccion` resuelve lo mismo
  /// con un velo de 3 paradas.
  Widget _fotoConVelo(BuildContext context) {
    // No decodificar 1080 px para una miniatura de ~170 pt: el doble de ancho
    // de la tarjeta es más que suficiente y ahorra memoria en TPV de gama baja.
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int anchoCache =
        ((MediaQuery.sizeOf(context).width / 2) * dpr).round().clamp(64, 1024);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.network(
          imagenUrl!,
          fit: BoxFit.cover,
          cacheWidth: anchoCache,
          // Reserva: deja ver el degradado de debajo, sin fogonazo blanco.
          loadingBuilder: (_, Widget child, ImageChunkEvent? progreso) =>
              progreso == null ? child : const SizedBox.shrink(),
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const <Color>[
                Color(0x00000000),
                Color(0x66000000),
                Color(0x9E000000),
              ],
              stops: const <double>[0.25, 0.62, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// Etiqueta pequeña en mayúsculas del ángulo superior izquierdo.
class _Chip extends StatelessWidget {
  const _Chip({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusChip),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: VentiqHomeTheme.chipTarjeta,
      ),
    );
  }
}

/// Tile cuadrado con el icono de la categoría.
class _TileIcono extends StatelessWidget {
  const _TileIcono({required this.icono});

  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusTile),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Icon(icono, size: 17, color: Colors.white),
    );
  }
}

/// Acción del pie de una tarjeta ("Ver todos ›").
///
/// Lleva su propio `GestureDetector` `opaque` dentro del `InkWell` de la
/// tarjeta: así el toque del pie no dispara también el de la tarjeta.
class _AccionTarjeta extends StatelessWidget {
  const _AccionTarjeta({required this.etiqueta, this.onTap});

  final String etiqueta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool activo = onTap != null;

    final Widget pastilla = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: activo ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusChip),
        border: Border.all(
          color: Colors.white.withValues(alpha: activo ? 0.24 : 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Flexible(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VentiqHomeTheme.pieTarjeta.copyWith(
                color: Colors.white.withValues(alpha: activo ? 0.95 : 0.50),
              ),
            ),
          ),
          if (activo) ...<Widget>[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 13,
                color: Colors.white),
          ],
        ],
      ),
    );

    if (!activo) return pastilla;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      behavior: HitTestBehavior.opaque,
      child: pastilla,
    );
  }
}
