/// Tutorial guiado reutilizable sobre una pantalla cualquiera.
///
/// Recorre un paso por campo: deja el resto de la pantalla en sombra y resalta
/// el campo con un anillo, igual que un hover, mientras muestra al lado qué es
/// y para qué sirve.
///
/// Se abre sobre la misma ruta (`opaque: false`), así la pantalla sigue montada
/// debajo: el velo lo pinta este widget con un agujero, no un fondo opaco del
/// `Navigator`.
///
/// Lo usan [ComprasScreen] y el alta de tienda; cualquier pantalla nueva que
/// quiera explicarse campo por campo solo tiene que crear sus `GlobalKey` y
/// pasar la lista de [PasoGuiado].
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Un paso: qué campo se resalta y qué se explica.
class PasoGuiado {
  const PasoGuiado({
    required this.clave,
    required this.titulo,
    required this.texto,
    this.icono,
    this.alEntrar,
  });

  /// Clave del widget a resaltar. Si su `RenderBox` no está en pantalla, el
  /// paso se salta en vez de mostrar un globo huérfano.
  final GlobalKey clave;

  final String titulo;
  final String texto;
  final IconData? icono;

  /// Se ejecuta **antes** de medir el campo. Sirve para que la pantalla lleve
  /// al usuario al paso, pestaña o página donde vive el campo; el recorrido
  /// espera a que termine y luego lo busca. Sin esto, un campo de otra página
  /// del `PageView` no existiría y el paso se saltaría.
  final Future<void> Function()? alEntrar;
}

/// Lanza el tutorial. Devuelve `true` si el usuario lo completó.
///
/// Sin pasos no se abre nada: un recorrido vacío dejaría una tarjeta con
/// índices fuera de rango.
Future<bool> mostrarTutorialGuiado(
  BuildContext context, {
  required List<PasoGuiado> pasos,
}) async {
  if (pasos.isEmpty) return false;
  final completado = await Navigator.of(context).push<bool>(
    PageRouteBuilder<bool>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, __) => TutorialGuiado(pasos: pasos),
      transitionsBuilder: (_, anim, __, hijo) =>
          FadeTransition(opacity: anim, child: hijo),
    ),
  );
  return completado ?? false;
}

/// Burbuja de aviso viva sobre el overlay.
///
/// Es la **única dueña** del `OverlayEntry`: todo cierre pasa por [cerrar], y
/// [cerrar] se puede llamar cuantas veces haga falta. Esto importa porque la
/// retirada se pide desde dos sitios (el propio widget al tocar fuera o la X, y
/// la pantalla al desmontarse) y Flutter aborta con
/// «An OverlayEntry should be removed only once» si se quita dos veces.
class AvisoTutorial {
  AvisoTutorial._(this._entrada);

  final OverlayEntry _entrada;
  bool _cerrada = false;

  bool get cerrada => _cerrada;

  /// Retira la burbuja del overlay. **Idempotente**: la segunda llamada no
  /// hace nada. No toca ningún `setState`: quien lo necesite lo hace en su
  /// propio llamador.
  void cerrar() {
    if (_cerrada) return;
    _cerrada = true;
    _entrada
      ..remove()
      ..dispose();
  }
}

/// Inserta la burbuja bajo el icono [ancla] y devuelve su dueño, o `null` si el
/// ancla aún no está montada.
///
/// [alCerrar] se llama al tocar fuera, al pulsar la X y antes de arrancar el
/// tutorial: es ahí donde el llamador limpia su estado. Para retirar la burbuja
/// de forma programática, usa [AvisoTutorial.cerrar]; nunca quites la entrada
/// por fuera.
AvisoTutorial? insertarAvisoTutorial(
  BuildContext context, {
  required GlobalKey ancla,
  required Future<void> Function() alAceptar,
  required VoidCallback alCerrar,
  String titulo = '¿Tienes dudas?',
  String descripcion =
      'Ve el tutorial: te explica campo por campo qué se pone en cada sitio, '
      'resaltándolo sobre la pantalla.',
  String textoBoton = 'Ver tutorial',
}) {
  final caja = ancla.currentContext?.findRenderObject();
  if (caja is! RenderBox || !caja.hasSize) return null;
  final overlay = Overlay.of(context, rootOverlay: true);

  final origen = caja.localToGlobal(Offset.zero);
  final pantalla = MediaQuery.sizeOf(context);
  const ancho = 300.0;
  const margen = 12.0;
  final izquierda = (origen.dx + caja.size.width - ancho)
      .clamp(margen, math.max(margen, pantalla.width - ancho - margen))
      .toDouble();

  late final AvisoTutorial aviso;

  /// Un solo camino de salida: cierra la burbuja y avisa al llamador. El
  /// `cerrar()` de dentro y el del llamador son el mismo y no se repiten.
  void cerrarYNotificar() {
    aviso.cerrar();
    alCerrar();
  }

  final entrada = OverlayEntry(
    builder: (_) => _AvisoTutorialBurbuja(
      izquierda: izquierda,
      arriba: origen.dy + caja.size.height + 8,
      ancho: ancho,
      titulo: titulo,
      descripcion: descripcion,
      textoBoton: textoBoton,
      alCerrar: cerrarYNotificar,
      alAceptar: () async {
        cerrarYNotificar();
        await alAceptar();
      },
    ),
  );
  aviso = AvisoTutorial._(entrada);
  overlay.insert(entrada);
  return aviso;
}

class _AvisoTutorialBurbuja extends StatefulWidget {
  const _AvisoTutorialBurbuja({
    required this.izquierda,
    required this.arriba,
    required this.ancho,
    required this.titulo,
    required this.descripcion,
    required this.textoBoton,
    required this.alCerrar,
    required this.alAceptar,
  });

  final double izquierda;
  final double arriba;
  final double ancho;
  final String titulo;
  final String descripcion;
  final String textoBoton;
  final VoidCallback alCerrar;
  final Future<void> Function() alAceptar;

  @override
  State<_AvisoTutorialBurbuja> createState() => _AvisoTutorialBurbujaState();
}

class _AvisoTutorialBurbujaState extends State<_AvisoTutorialBurbuja> {
  bool _aceptando = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tocar fuera cierra la burbuja sin arrancar nada.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.alCerrar,
          ),
        ),
        Positioned(
          left: widget.izquierda,
          top: widget.arriba,
          width: widget.ancho,
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F1F2937),
                    blurRadius: 20,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Icon(
                            Icons.school_outlined,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.titulo,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          color: AppColors.textSecondary,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          tooltip: 'Cerrar',
                          onPressed: widget.alCerrar,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.descripcion,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _aceptando
                            ? null
                            : () async {
                                setState(() => _aceptando = true);
                                await widget.alAceptar();
                              },
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(widget.textoBoton),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Recorrido con velo, anillo de resalte y tarjeta explicativa.
class TutorialGuiado extends StatefulWidget {
  const TutorialGuiado({super.key, required this.pasos});

  final List<PasoGuiado> pasos;

  @override
  State<TutorialGuiado> createState() => _TutorialGuiadoState();
}

class _TutorialGuiadoState extends State<TutorialGuiado>
    with SingleTickerProviderStateMixin {
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  int _indice = 0;

  /// Rectángulo del objetivo en coordenadas de pantalla. `null` = aún no se
  /// conoce (primer frame) o el widget no está montado.
  Rect? _objetivo;

  /// Rectángulo anterior, para interpolar el agujero al cambiar de paso.
  Rect? _objetivoPrevio;

  PasoGuiado get _paso => widget.pasos[_indice];
  bool get _esPrimero => _indice == 0;
  bool get _esUltimo => _indice >= widget.pasos.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _irAPaso(0));
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  Future<void> _irAPaso(int indice) async {
    if (indice < 0 || indice >= widget.pasos.length) return;
    setState(() {
      _objetivoPrevio = _objetivo;
      _indice = indice;
    });

    // El paso puede vivir en otra página del PageView: la pantalla lo lleva a
    // la vista antes de medirlo.
    final alEntrar = widget.pasos[indice].alEntrar;
    if (alEntrar != null) {
      await alEntrar();
      if (!mounted) return;
      // La pantalla ya cambió de página o de estado: hace falta un frame para
      // que el campo esté montado antes de buscar su RenderBox.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    final ctx = widget.pasos[indice].clave.currentContext;
    if (ctx == null) {
      // El campo no está montado (otra rama del layout). Se salta.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_esUltimo) {
          _terminar();
        } else {
          _irAPaso(_indice + 1);
        }
      });
      return;
    }

    // Llevar el campo a la vista antes de medirlo.
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.35,
    );
    if (!mounted) return;

    _medir();
    _control
      ..reset()
      ..forward();
  }

  void _medir() {
    final ctx = _paso.clave.currentContext;
    if (ctx == null) {
      if (_objetivo != null) setState(() => _objetivo = null);
      return;
    }
    final caja = ctx.findRenderObject();
    if (caja is! RenderBox || !caja.hasSize) {
      if (_objetivo != null) setState(() => _objetivo = null);
      return;
    }
    final origen = caja.localToGlobal(Offset.zero);
    final rect = origen & caja.size;
    if (rect != _objetivo) setState(() => _objetivo = rect);
  }

  void _siguiente() {
    if (_esUltimo) {
      _terminar();
    } else {
      _irAPaso(_indice + 1);
    }
  }

  void _anterior() {
    if (!_esPrimero) _irAPaso(_indice - 1);
  }

  void _terminar() => Navigator.of(context).pop(true);

  void _salir() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    // Sin pasos no hay nada que resaltar: se cierra en vez de reventar por
    // índice fuera de rango (el widget también se puede montar a mano).
    if (widget.pasos.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _terminar();
      });
      return const SizedBox.shrink();
    }

    final pantalla = MediaQuery.sizeOf(context);
    final destino = _objetivo;
    final desde = _objetivoPrevio;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _salir();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Velo con agujero. No bloquea: debajo se ve la pantalla.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _control,
                  builder: (_, __) {
                    final t = Curves.easeOutCubic.transform(_control.value);
                    Rect? actual;
                    if (destino != null) {
                      actual = desde == null
                          ? destino
                          : Rect.lerp(desde, destino, t);
                    }
                    return CustomPaint(
                      painter: _VeloTutorial(objetivo: actual),
                    );
                  },
                ),
              ),
            ),
            if (destino == null)
              // Sin objetivo medible: solo la tarjeta, centrada arriba.
              Positioned(left: 16, right: 16, top: 96, child: _tarjeta())
            else
              _tarjetaSobreObjetivo(pantalla, destino),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaSobreObjetivo(Size pantalla, Rect objetivo) {
    const margen = 16.0;
    const anchoMaximo = 420.0;
    final ancho = math.min(anchoMaximo, pantalla.width - margen * 2);

    // Altura estimada de la tarjeta: se decide arriba o abajo con ese número.
    const altoEstimado = 210.0;
    final espacioAbajo = pantalla.height - objetivo.bottom - margen;
    final espacioArriba = objetivo.top - margen;
    final abajo = espacioAbajo >= altoEstimado || espacioAbajo >= espacioArriba;

    final izquierda = (objetivo.center.dx - ancho / 2)
        .clamp(margen, math.max(margen, pantalla.width - ancho - margen))
        .toDouble();

    return Positioned(
      left: izquierda,
      width: ancho,
      top: abajo ? objetivo.bottom + 12 : null,
      bottom: abajo ? null : pantalla.height - objetivo.top + 12,
      child: _tarjeta(),
    );
  }

  Widget _tarjeta() {
    final total = widget.pasos.length;
    final progreso = (_indice + 1) / total;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x331F2937),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _paso.icono ?? Icons.touch_app,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _paso.titulo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_indice + 1} / $total',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.textSecondary,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Salir del tutorial',
                  onPressed: _salir,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _paso.texto,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 3,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                TextButton(
                  onPressed: _esPrimero ? null : _anterior,
                  child: const Text('Atrás'),
                ),
                const Spacer(),
                TextButton(onPressed: _salir, child: const Text('Salir')),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _siguiente,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_esUltimo ? 'Terminar' : 'Siguiente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Velo oscuro con un agujero redondeado y un anillo de resalte.
class _VeloTutorial extends CustomPainter {
  const _VeloTutorial({required this.objetivo});

  final Rect? objetivo;

  @override
  void paint(Canvas canvas, Size size) {
    final velo = Path()..addRect(Offset.zero & size);

    final recorte = objetivo;
    if (recorte != null) {
      final inflado = recorte.inflate(6);
      final agujero = Path()
        ..addRRect(RRect.fromRectAndRadius(inflado, const Radius.circular(10)));
      final conAgujero = Path.combine(PathOperation.difference, velo, agujero);
      canvas.drawPath(conAgujero, Paint()..color = const Color(0xB3000000));
      canvas.drawRRect(
        RRect.fromRectAndRadius(inflado, const Radius.circular(10)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.primary,
      );
    } else {
      canvas.drawPath(velo, Paint()..color = const Color(0xB3000000));
    }
  }

  @override
  bool shouldRepaint(_VeloTutorial viejo) => viejo.objetivo != objetivo;
}
