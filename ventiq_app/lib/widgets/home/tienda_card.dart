import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/ventiq_home_theme.dart';
import 'tarjeta_exploracion.dart';

/// La tarjeta virtual "Tienda": agrupa todo lo que **no** es especial.
///
/// No es una `TarjetaExploracion` con otro color: es horizontal y ancha, y su
/// trabajo es distinto. Las especiales son puertas directas (tocar →
/// subcategorías); esta es una **puerta a una lista**, y por eso lleva la
/// cuenta de categorías a la vista y una flecha a la derecha que anticipa "aquí
/// entras y hay más".
///
/// Tiene **dos disposiciones** y las dos pintan el mismo contenido —[nombre],
/// [_chip] y [_subtitulo] salen de un único sitio—: lo único que cambia es
/// dónde se coloca la tarjeta.
///
/// La foto del local es opcional ([imagenTienda]) y en las dos disposiciones
/// ocupa el **lado derecho**, fundida hacia la izquierda sobre el degradado:
/// el texto vive a la izquierda y ahí no se toca el contraste.
///
///  * [TiendaCard], la de siempre: a ancho completo y **debajo** de la rejilla,
///    para que se lea como el cajón donde va todo lo demás. Es la que toca
///    cuando la rejilla de especiales tiene un número par de tarjetas.
///  * [TiendaCard.celda], del tamaño y el lenguaje de una tarjeta de categoría
///    y **dentro** de la rejilla: rellena el hueco que deja una fila impar de
///    especiales, justo al lado de la última. Ahí una banda ancha no cabe sin
///    romper la rejilla; una celda sí, porque es una vecina más que cierra la
///    fila.
class TiendaCard extends StatelessWidget {
  const TiendaCard({
    super.key,
    required this.categorias,
    required this.productos,
    required this.onTap,
    this.nombre = 'Tienda',
    this.imagenTienda,
  }) : _enCelda = false;

  /// La variante de **celda**, para el hueco que deja una fila impar de
  /// especiales.
  ///
  /// Delega en [TarjetaExploracion] —la tarjeta de las categorías de al lado—
  /// en vez de reimplementar el marco: así comparte radio, chip, tipografías,
  /// marca de agua y degradado corporativo con sus vecinas, y no puede ni
  /// parecer de otra familia ni desincronizarse de ellas.
  const TiendaCard.celda({
    super.key,
    required this.categorias,
    required this.productos,
    required this.onTap,
    this.nombre = 'Tienda',
    this.imagenTienda,
  }) : _enCelda = true;

  /// Cuántas categorías agrupa.
  final int categorias;

  /// Cuántos productos hay dentro. Se usa para el subtítulo.
  final int productos;

  /// Nombre de la tienda (D2). Sale de `app_dat_tienda.denominacion`; si no se
  /// pudo leer, cae a «Tienda».
  final String nombre;

  /// Foto del local, si la tienda tiene una (URL pública cacheada en
  /// `UserPreferencesService`). Es opcional y **best-effort**: `null` es el
  /// caso normal de una tienda sin logo y deja la tarjeta como siempre.
  ///
  /// La pintan las dos disposiciones a la derecha, con el mismo criterio: la
  /// foto se ve en el tramo derecho y se desvanece hacia la izquierda, donde
  /// están el chip, el nombre y los contadores.
  final String? imagenTienda;

  final VoidCallback onTap;

  /// La disposición que se pidió al constructor. Es privada a propósito: desde
  /// fuera se elige la variante, no un flag suelto que se pueda olvidar.
  final bool _enCelda;

  /// El par *navy* de la paleta corporativa ([VentiqHomeTheme.cardGradients]).
  ///
  /// Las dos disposiciones lo leen del tema y no de literales propios: si la
  /// paleta se ajusta, «Tienda» se mueve con las categorías en vez de quedarse
  /// con un azul huérfano.
  static const int _indiceDegradado = 3;

  static List<Color> get _degradado =>
      VentiqHomeTheme.cardGradients[_indiceDegradado];

  /// Una URL vacía o en blanco no es imagen: se trata igual que `null` para no
  /// dejar un hueco pintado ni cargar una petición inútil.
  bool get _conImagen =>
      imagenTienda != null && imagenTienda!.trim().isNotEmpty;

  /// El chip del recuento de categorías. El texto es el mismo en las dos
  /// disposiciones: si cambia la palabra «CATEG», cambia en ambas a la vez.
  String get _chip => '$categorias CATEG';

  /// El subtítulo con el recuento de productos.
  ///
  /// «categ» y no «rubros»: es la palabra que usa el negocio (y el gerente)
  /// para estas agrupaciones del catálogo.
  String get _subtitulo {
    if (productos <= 0) return '$categorias categ';
    return '$productos producto${productos == 1 ? '' : 's'} en $categorias categ';
  }

  @override
  Widget build(BuildContext context) {
    if (_enCelda) {
      // Sin margen lateral propio: la rejilla ya aplica el `sectionPadding` de
      // la sección, y un segundo margen dejaría la celda más estrecha que sus
      // vecinas.
      return TarjetaExploracion(
        chip: _chip,
        titulo: nombre,
        subtitulo: _subtitulo,
        icono: Icons.storefront_rounded,
        colores: _degradado,
        // La celda no reimplementa nada: [TarjetaExploracion] ya sabe pintar
        // la foto con su velo. Si es `null`, se queda el icono de siempre.
        imagenUrl: imagenTienda,
        onTap: onTap,
      );
    }

    return Semantics(
      button: true,
      label: '$nombre. $_subtitulo',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VentiqHomeTheme.sectionPadding,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusCard),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // De izquierda a derecha: la tarjeta es ancha, así que el
              // degradado acompaña su recorrido y no su alto. La celda, que es
              // cuadrada, usa el diagonal de las tarjetas de categoría.
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: _degradado,
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
                    // La foto va DEBAJO del contenido y encajada con `Positioned.fill`: el
                    // alto de la tarjeta lo marca el texto, y así la imagen se
                    // estira a ese alto ya resuelto en vez de pelear por él.
                    if (_conImagen)
                      Positioned.fill(child: _fotoDerecha(context)),
                    // Marca de agua, igual que en las tarjetas de la grilla.
                    // Con foto sobra: ocupa el mismo rincón y competiría con
                    // ella.
                    if (!_conImagen)
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
                                        _chip,
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
                                  _subtitulo,
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
                              // Sobre foto el aro blanco se perdería en una
                              // imagen clara: ahí el fondo pasa a negro suave,
                              // como el mando de un carrusel. Sin foto, el
                              // blanco traslúcido de siempre.
                              color: _conImagen
                                  ? Colors.black.withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.16),
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

  /// La foto del local en el tramo **derecho**, fundida hacia la izquierda.
  ///
  /// Es el mismo lenguaje que la celda —la foto no se recorta contra un borde,
  /// se desvanece— pero sobre el degradado horizontal de la tarjeta ancha. El
  /// fundido se hace con `ShaderMask` y no con un velo de color a propósito:
  /// un velo tendría que repetir el navy de [_degradado] y se desincronizaría
  /// en cuanto la paleta cambie; con máscara, lo que asoma por debajo es
  /// literalmente el fondo de la tarjeta, sea cual sea.
  Widget _fotoDerecha(BuildContext context) {
    // Mismo criterio de caché que [TarjetaExploracion]: no decodificar más de
    // lo que se puede ver. Aquí la foto ocupa el tramo derecho de una tarjeta
    // que va a lo ancho de la pantalla.
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int anchoCache =
        (MediaQuery.sizeOf(context).width * 0.46 * dpr).round().clamp(96, 1200);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            // Solo el tramo derecho: el izquierdo se queda entero para el
            // chip, el nombre y los contadores, que es lo que hay que leer.
            widthFactor: 0.46,
            heightFactor: 1,
            child: ShaderMask(
              shaderCallback: (Rect limites) => const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color(0x00FFFFFF),
                  Color(0xCCFFFFFF),
                  Color(0xFFFFFFFF),
                ],
                stops: <double>[0.0, 0.55, 1.0],
              ).createShader(limites),
              blendMode: BlendMode.dstIn,
              child: Image.network(
                imagenTienda!,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                cacheWidth: anchoCache,
                // Mientras llega se deja ver el degradado; si aparece de golpe
                // el cambio de brillo se nota menos que un hueco blanco.
                loadingBuilder:
                    (_, Widget child, ImageChunkEvent? progreso) =>
                        progreso == null ? child : const SizedBox.shrink(),
                // Best-effort: una URL caída no puede romper el Home. Sin
                // foto la tarjeta se queda tal cual.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        // Velo tenue, solo en el tramo de la foto: da asiento a la imagen sin
        // llegar a la mitad izquierda, donde vive el texto.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[
                const Color(0x00000000),
                Colors.black.withValues(alpha: 0.16),
              ],
              stops: const <double>[0.58, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}
