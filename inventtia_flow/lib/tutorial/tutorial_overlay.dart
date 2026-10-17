import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'tutorial_controller.dart';
import 'tutorial_paso.dart';
import 'tutorial_registry.dart';

/// Monta la capa del tutorial por encima de todo lo demás.
///
/// Se instala desde `MaterialApp.builder`, así que queda **por encima del
/// Navigator** y también de las hojas modales (`showModalBottomSheet`), que es
/// justo lo que necesita un tutorial que cruza pantallas.
///
/// Cuando no hay tutorial activo devuelve un `SizedBox` sin hijo: no intercepta
/// ningún toque.
class TutorialOverlayHost extends StatelessWidget {
  final Widget? child;

  const TutorialOverlayHost({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (child != null) child!,
        const _TutorialLayer(),
      ],
    );
  }
}

class _TutorialLayer extends StatefulWidget {
  const _TutorialLayer();

  @override
  State<_TutorialLayer> createState() => _TutorialLayerState();
}

class _TutorialLayerState extends State<_TutorialLayer>
    with SingleTickerProviderStateMixin {
  final TutorialController _controller = TutorialController.instance;

  Rect? _ultimoHueco;

  /// Latido de vigilancia: corre **solo** mientras hay tutorial activo y sirve
  /// para dos cosas que ningún evento del árbol avisa por sí solo:
  ///
  ///  * reposicionar hueco y burbuja si el elemento resaltado se mueve (scroll,
  ///    teclado, rotación);
  ///  * detectar que el elemento del paso actual ya no está a la vista (el
  ///    usuario cambió de pestaña, navegó o se apiló una hoja modal) y que el
  ///    del paso siguiente aparece un frame después. Al no haber alta ni baja
  ///    de ancla en un cambio de pestaña, sin este latido el recorrido se
  ///    quedaría clavado en la pantalla anterior.
  ///
  /// La decisión de avanzar la toma siempre `TutorialController.evaluarAvance`,
  /// que solo avanza desde un paso que el usuario llegó a ver: el latido
  /// observa, no decide.
  late final AnimationController _latido = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  )..addListener(_revisar);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_alCambiar);
    TutorialRegistry.instance.version.addListener(_alCambiar);
    // Sin `setState`: esto corre dentro de la fase de build y marcar el widget
    // como sucio ahí es un error.
    if (_controller.activo && !_latido.isAnimating) _latido.repeat();
  }

  @override
  void dispose() {
    _controller.removeListener(_alCambiar);
    TutorialRegistry.instance.version.removeListener(_alCambiar);
    _latido.dispose();
    super.dispose();
  }

  void _alCambiar() {
    // Seguro sin diferir: las altas y bajas del registro se hacen siempre en
    // post-frame (ver `TutorialAnchor`), nunca dentro de la fase de build.
    if (!mounted) return;
    if (_controller.activo) {
      if (!_latido.isAnimating) _latido.repeat();
    } else if (_latido.isAnimating) {
      _latido.stop();
    }
    setState(() {});
  }

  void _revisar() {
    if (!_controller.activo) return;

    // Se reevalúa en cada frame: `evaluarAvance` anota el paso actual en cuanto
    // está a la vista (condición para poder avanzar solo desde un paso visto) y
    // salta al siguiente en cuanto el actual desaparece y el nuevo aparece (que
    // puede ser un frame más tarde).
    _controller.evaluarAvance();

    final paso = _controller.pasoActual;
    if (paso == null) return;
    final nuevo = TutorialRegistry.instance.rectDe(paso.id);
    if (mounted && nuevo != _ultimoHueco) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final paso = _controller.pasoActual;
    if (paso == null) {
      if (_ultimoHueco != null) _ultimoHueco = null;
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = TutorialRegistry.instance.rectDe(paso.id);
        _ultimoHueco = rect;

        final sinMovimiento = MediaQuery.of(context).disableAnimations;
        final duracion =
            sinMovimiento ? Duration.zero : const Duration(milliseconds: 200);

        final hueco = rect?.inflate(_paddingHueco);

        return Stack(
          children: [
            // Oscurecido en 4 bloques: el hueco no se cubre, así el widget
            // resaltado recibe de verdad el toque del usuario.
            ..._bloquesOscuros(size, hueco, duracion),

            if (hueco != null)
              AnimatedPositioned(
                duration: duracion,
                curve: Curves.easeOutCubic,
                left: hueco.left,
                top: hueco.top,
                width: hueco.width,
                height: hueco.height,
                child: IgnorePointer(
                  child: _AnilloPulsante(detenerAnimacion: sinMovimiento),
                ),
              ),

            CustomSingleChildLayout(
              delegate: _DelegadoBurbuja(hueco: hueco),
              child: TweenAnimationBuilder<double>(
                key: ValueKey<String>('${paso.id}-${_controller.indice}'),
                tween: Tween<double>(begin: 0, end: 1),
                duration: duracion,
                curve: Curves.easeOutCubic,
                builder: (_, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - t)),
                    child: child,
                  ),
                ),
                child: _Burbuja(
                  paso: paso,
                  indice: _controller.indice,
                  total: _controller.total,
                  anclaVisible: hueco != null,
                  navegando: _controller.navegando,
                  burbujaArriba: _vaArriba(hueco, size),
                  onSiguiente: _controller.siguiente,
                  onAtras: _controller.indice > 0 ? _controller.anterior : null,
                  onSaltar: _controller.omitir,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _vaArriba(Rect? hueco, Size size) {
    if (hueco == null) return false;
    return hueco.center.dy > size.height / 2;
  }

  List<Widget> _bloquesOscuros(Size size, Rect? hueco, Duration duracion) {
    // El oscurecido absorbe el toque (`opaque`) pero NO lo usa para avanzar: el
    // recorrido del admin es un formulario largo y adelantaría pasos sin querer
    // al tocar cualquier zona atenuada. Para avanzar están "Siguiente" y el
    // propio avance automático.
    Widget bloque(Rect r) => Positioned(
          left: r.left,
          top: r.top,
          width: math.max(0, r.width),
          height: math.max(0, r.height),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Color(0xB3000000)),
          ),
        );

    if (hueco == null) {
      return [bloque(Offset.zero & size)];
    }

    final h = size.height;
    final w = size.width;
    final top = _limitar(hueco.top, 0, h);
    final bottom = _limitar(hueco.bottom, 0, h);
    final left = _limitar(hueco.left, 0, w);
    final right = _limitar(hueco.right, 0, w);

    return [
      bloque(Rect.fromLTRB(0, 0, w, top)),
      bloque(Rect.fromLTRB(0, bottom, w, h)),
      bloque(Rect.fromLTRB(0, top, left, bottom)),
      bloque(Rect.fromLTRB(right, top, w, bottom)),
    ];
  }
}

double _limitar(double v, double min, double max) =>
    v < min ? min : (v > max ? max : v);

/// Margen alrededor del elemento resaltado: deja respirar el anillo y evita
/// que el bloque oscuro se coma el borde táctil del widget.
const double _paddingHueco = 8;

class _AnilloPulsante extends StatefulWidget {
  final bool detenerAnimacion;

  const _AnilloPulsante({required this.detenerAnimacion});

  @override
  State<_AnilloPulsante> createState() => _AnilloPulsanteState();
}

class _AnilloPulsanteState extends State<_AnilloPulsante>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.detenerAnimacion) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulso = widget.detenerAnimacion
        ? const AlwaysStoppedAnimation<double>(0.6)
        : CurvedAnimation(parent: _c, curve: Curves.easeInOut);

    return AnimatedBuilder(
      animation: pulso,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.85),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.18 + 0.22 * pulso.value),
              blurRadius: 16 + 12 * pulso.value,
              spreadRadius: 1 + 2 * pulso.value,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.10),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

/// Coloca la burbuja junto al hueco sin salirse de la pantalla.
///
/// Se usa `CustomSingleChildLayout` porque necesita la altura real de la
/// burbuja (el texto puede ocupar 1 o 4 líneas) para decidir si cabe arriba.
class _DelegadoBurbuja extends SingleChildLayoutDelegate {
  final Rect? hueco;

  const _DelegadoBurbuja({required this.hueco});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(constraints.maxWidth - 24, 380),
        minWidth: math.min(constraints.maxWidth - 24, 380) * 0.6,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final h = hueco;
    if (h == null) {
      return Offset(
        math.max(12, (size.width - childSize.width) / 2),
        math.max(12, (size.height - childSize.height) / 2),
      );
    }

    const gap = 16.0;
    final cabeArriba = h.top - childSize.height - gap >= 8;
    final cabeAbajo = h.bottom + childSize.height + gap <= size.height - 8;
    final preferirArriba = h.center.dy > size.height / 2;

    double top;
    if (cabeArriba && (preferirArriba || !cabeAbajo)) {
      top = h.top - childSize.height - gap;
    } else if (cabeAbajo) {
      top = h.bottom + gap;
    } else {
      top = h.top - childSize.height - gap;
    }
    top = _limitar(top, 8, math.max(8, size.height - childSize.height - 8));

    final left = _limitar(
      h.center.dx - childSize.width / 2,
      12,
      math.max(12, size.width - childSize.width - 12),
    );

    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _DelegadoBurbuja oldDelegate) =>
      oldDelegate.hueco != hueco;
}

class _Burbuja extends StatelessWidget {
  final TutorialPaso paso;
  final int indice;
  final int total;
  final bool anclaVisible;

  /// El controlador acaba de pedir una navegación y el elemento del paso
  /// todavía no está montado: no se le pide nada al usuario en ese hueco.
  final bool navegando;
  final bool burbujaArriba;
  final VoidCallback onSiguiente;
  final VoidCallback? onAtras;
  final VoidCallback onSaltar;

  const _Burbuja({
    required this.paso,
    required this.indice,
    required this.total,
    required this.anclaVisible,
    required this.navegando,
    required this.burbujaArriba,
    required this.onSiguiente,
    required this.onAtras,
    required this.onSaltar,
  });

  bool get _esUltimo => indice >= total - 1;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!burbujaArriba) const _Flecha(apuntandoArriba: true),
          Material(
            color: Colors.white,
            elevation: 6,
            shadowColor: AppTheme.primaryDark.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                          Icons.lightbulb_outline_rounded,
                          size: 19,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                paso.titulo,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: -0.2,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  if (paso.opcional) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Text(
                                        'OPCIONAL',
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    'PASO ${indice + 1} DE $total',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.4,
                                      color:
                                          AppTheme.primary.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 19,
                          // Sin `tooltip`: esta capa vive por encima del
                          // `Navigator`, así que no hay `Overlay` donde anclar
                          // el globo del tooltip (lanzaría una aserción).
                          onPressed: onSaltar,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    paso.mensaje,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  // Mientras se está navegando, el hueco vacío no es un error:
                  // no se le pide nada al usuario (evita el parpadeo de "haz lo
                  // que dice este paso" durante la transición).
                  if (!anclaVisible && !navegando) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          paso.opcional
                              ? Icons.info_outline_rounded
                              : Icons.touch_app_outlined,
                          size: 15,
                          color: AppTheme.warning.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            // Los pasos opcionales son extras que viven en otra
                            // pantalla: se explican igual, pero no se le pide al
                            // usuario que vaya a buscarlos.
                            paso.opcional
                                ? 'Extra opcional: puedes configurarlo cuando '
                                    'quieras. Toca «Siguiente» para continuar.'
                                : 'Haz lo que dice este paso para continuar.',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  // El progreso va en su propia línea: junto a los botones, con
                  // recorridos largos (17 pasos el del admin) desbordaría.
                  // Hasta 8 pasos, puntos; a partir de ahí, barra fina.
                  if (total <= 8)
                    Row(
                      children: List<Widget>.generate(
                        total,
                        (i) => Container(
                          width: i == indice ? 16 : 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: i == indice
                                ? AppTheme.primary
                                : AppTheme.primary.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: _BarraProgreso(indice: indice, total: total),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onAtras != null)
                        _BotonSecundario(
                          etiqueta: 'Atrás',
                          onPressed: onAtras!,
                        ),
                      _BotonSecundario(
                        etiqueta: 'Saltar',
                        onPressed: onSaltar,
                      ),
                      const SizedBox(width: 6),
                      // `Flexible` + `FittedBox`: con textos de acción largos
                      // ("Crear la reserva") la etiqueta se encoge en vez de
                      // desbordar la fila.
                      Flexible(
                        // Brillo de marca del botón principal: mismo lenguaje que
                        // los CTA de la app (sombra del color primario, sin
                        // `elevation` de Material).
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: onSiguiente,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(0, 38),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(11),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                paso.accion ??
                                    (_esUltimo ? 'Entendido' : 'Siguiente'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (burbujaArriba) const _Flecha(apuntandoArriba: false),
        ],
      ),
    );
  }
}

/// Botón de texto secundario de la burbuja ("Atrás", "Saltar").
class _BotonSecundario extends StatelessWidget {
  final String etiqueta;
  final VoidCallback onPressed;

  const _BotonSecundario({required this.etiqueta, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: AppTheme.textSecondary,
      ),
      child: Text(etiqueta),
    );
  }
}

/// Progreso compacto para recorridos largos (el del admin tiene 17 pasos): con
/// tantos pasos los puntos no caben en la fila de botones.
class _BarraProgreso extends StatelessWidget {
  final int indice;
  final int total;

  const _BarraProgreso({required this.indice, required this.total});

  @override
  Widget build(BuildContext context) {
    final avance = total <= 0 ? 0.0 : (indice + 1) / total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: avance,
        minHeight: 6,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.18),
        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
      ),
    );
  }
}

/// Triángulo que une la burbuja con el elemento resaltado (mismo recurso visual
/// que la pista del botón de filtros).
class _Flecha extends StatelessWidget {
  final bool apuntandoArriba;

  const _Flecha({required this.apuntandoArriba});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 9,
      child: Center(
        child: CustomPaint(
          size: const Size(18, 9),
          painter: _PincelFlecha(apuntandoArriba: apuntandoArriba),
        ),
      ),
    );
  }
}

class _PincelFlecha extends CustomPainter {
  final bool apuntandoArriba;

  const _PincelFlecha({required this.apuntandoArriba});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path();
    if (apuntandoArriba) {
      path
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PincelFlecha oldDelegate) =>
      oldDelegate.apuntandoArriba != apuntandoArriba;
}
