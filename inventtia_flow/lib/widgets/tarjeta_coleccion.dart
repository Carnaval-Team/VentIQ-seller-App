import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/coleccion_service.dart';

/// Degradado de una colección a partir de los colores que fijó el superadmin.
///
/// Si un color no es un `#RRGGBB` (o `#AARRGGBB`) válido se cae al degradado de
/// marca en vez de romper el pintado: el campo lo escribe una persona en un
/// formulario del panel.
List<Color> degradadoDeColeccion(Coleccion coleccion) {
  final inicio = colorHexColeccion(coleccion.colorInicio);
  final fin = colorHexColeccion(coleccion.colorFin);
  if (inicio == null && fin == null) {
    return const [Color(0xFF2C3654), Color(0xFF1FA8B8)];
  }
  return [inicio ?? fin!, fin ?? inicio!];
}

/// `#RRGGBB` / `#AARRGGBB` → [Color]. `null` si no se puede interpretar.
Color? colorHexColeccion(String? valor) {
  final v = valor?.trim().replaceFirst('#', '');
  if (v == null) return null;
  if (v.length == 6) {
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }
  if (v.length == 8) {
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(n);
  }
  return null;
}

/// Icono de repuesto cuando el superadmin no escribió un emoji en la colección.
const String iconoColeccionPorDefecto = '✨';

/// Tarjeta de una colección temática para el Home.
///
/// Reemplaza la rejilla de dos columnas por una pieza **editorial**: una sola
/// fila que se desliza, con el degradado de la colección, un halo, el emoji
/// como marca de agua y el dato que de verdad decide el toque (cuántos
/// servicios trae). El toque ya no filtra el feed: abre la vista de la
/// colección (`ColeccionDetailScreen`), que es donde se reserva.
///
/// [animacion] llega del Home (un único `AnimationController` compartido por
/// todas las tarjetas) y sólo mueve un brillo diagonal de baja opacidad: sin
/// ella la tarjeta se pinta igual, así que se puede usar en un test sin
/// controlador.
class TarjetaColeccion extends StatefulWidget {
  const TarjetaColeccion({
    super.key,
    required this.coleccion,
    required this.onTap,
    this.ancho = 236,
    this.alto = 158,
    this.expandida = false,
    this.animacion,
  });

  final Coleccion coleccion;
  final VoidCallback onTap;

  /// Ancho de la tarjeta en el riel. Se ignora con [expandida].
  final double ancho;

  final double alto;

  /// Una sola colección: ocupa todo el ancho y gana el subtítulo.
  final bool expandida;

  final Animation<double>? animacion;

  @override
  State<TarjetaColeccion> createState() => _TarjetaColeccionState();
}

class _TarjetaColeccionState extends State<TarjetaColeccion> {
  bool _presionada = false;

  @override
  Widget build(BuildContext context) {
    final coleccion = widget.coleccion;
    final colores = degradadoDeColeccion(coleccion);
    final emoji = (coleccion.icono?.trim().isNotEmpty ?? false)
        ? coleccion.icono!.trim()
        : iconoColeccionPorDefecto;

    final radio = widget.expandida ? 24.0 : 22.0;

    final tarjeta = AnimatedScale(
      scale: _presionada ? 0.978 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radio),
          boxShadow: const [
            BoxShadow(
              color: Color(0x242B3A67),
              blurRadius: 18,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radio),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Base: el degradado curado.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colores,
                  ),
                ),
              ),
              // 2. Halo superior derecho: da profundidad sin añadir ruido.
              Positioned(
                top: -54,
                right: -40,
                child: Container(
                  width: 168,
                  height: 168,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              // 3. Emoji de marca de agua: firma visual de la colección.
              Positioned(
                right: widget.expandida ? 6 : -6,
                bottom: widget.expandida ? -26 : -18,
                child: Text(
                  emoji,
                  style: TextStyle(
                    fontSize: widget.expandida ? 116 : 96,
                    color: Colors.white.withValues(alpha: 0.18),
                    height: 1,
                  ),
                ),
              ),
              // 4. Velo inferior: garantiza contraste del texto sobre cualquier
              //    combinación de colores que elija el superadmin.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.12),
                      Colors.black.withValues(alpha: 0.62),
                    ],
                    stops: const [0.32, 0.6, 1],
                  ),
                ),
              ),
              // 5. Brillo diagonal en bucle: micro-movimiento, no decoración.
              if (widget.animacion != null)
                _Sheen(animacion: widget.animacion!, radio: radio),
              Positioned(
                left: 13,
                top: 12,
                child: _SelloColeccion(compacto: !widget.expandida),
              ),
              Positioned(
                left: 14,
                right: 13,
                bottom: 13,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coleccion.titulo.trim().isEmpty
                          ? 'Colección'
                          : coleccion.titulo.trim(),
                      maxLines: widget.expandida ? 2 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: widget.expandida ? 23 : 18,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        shadows: const [
                          Shadow(
                            color: Color(0x73000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    if (widget.expandida &&
                        (coleccion.subtitulo?.trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 4),
                      Text(
                        coleccion.subtitulo!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        _Pastilla(
                          icono: Icons.auto_awesome_rounded,
                          texto: coleccion.totalServicios > 0
                              ? coleccion.etiquetaServicios
                              : coleccion.subtituloORecuento,
                        ),
                        const Spacer(),
                        const _FlechaCirculo(),
                      ],
                    ),
                  ],
                ),
              ),
              // 6. Filo interior: remata el borde sin engordar la tarjeta.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radio),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final interactiva = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _presionada = true),
      onTapUp: (_) => setState(() => _presionada = false),
      onTapCancel: () => setState(() => _presionada = false),
      child: tarjeta,
    );

    return Semantics(
      button: true,
      label:
          'Colección ${coleccion.titulo}. '
          '${coleccion.etiquetaServicios}. Abrir la colección.',
      child: SizedBox(
        width: widget.expandida ? double.infinity : widget.ancho,
        height: widget.expandida ? math.max(widget.alto, 176) : widget.alto,
        child: interactiva,
      ),
    );
  }
}

/// Barrido de luz muy tenue. Va por debajo del contenido y por encima del velo,
/// así que nunca reduce el contraste del texto.
class _Sheen extends StatelessWidget {
  const _Sheen({required this.animacion, required this.radio});

  final Animation<double> animacion;
  final double radio;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animacion,
      builder: (context, _) {
        // Solo el 45 % central del ciclo barre la tarjeta: dejar el brillo fuera
        // de pantalla el resto del tiempo evita que se lea como un parpadeo.
        final t = (animacion.value * 2 - 1).clamp(0.0, 1.0);
        return IgnorePointer(
          child: Transform.translate(
            offset: Offset(-140 + t * 420, 0),
            child: Transform.rotate(
              angle: -0.32,
              child: Container(
                width: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Etiqueta "COLECCIÓN" en cristal, arriba a la izquierda.
class _SelloColeccion extends StatelessWidget {
  const _SelloColeccion({required this.compacto});

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 8 : 9,
        vertical: compacto ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: const Text(
        'COLECCIÓN',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Pastilla con el dato duro de la tarjeta: cuántos servicios trae.
class _Pastilla extends StatelessWidget {
  const _Pastilla({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 11, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Círculo con la flecha: dice "esto abre algo" sin escribirlo.
class _FlechaCirculo extends StatelessWidget {
  const _FlechaCirculo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: const Icon(
        Icons.arrow_forward_rounded,
        size: 15,
        color: Colors.white,
      ),
    );
  }
}

/// Espacio reservado cuando la sección de colecciones no tiene nada real que
/// enseñar. Existe para que el Home no tenga que repetir el `SizedBox`.
const Widget sinColecciones = SizedBox.shrink();

/// Ayuda de color para degradados derivados (p. ej. fondos suaves a partir del
/// color de la colección) sin salir del esquema de la app.
Color colorSuaveDe(Color base, {double alpha = 0.12}) =>
    Color.alphaBlend(base.withValues(alpha: alpha), AppTheme.cardBg);
