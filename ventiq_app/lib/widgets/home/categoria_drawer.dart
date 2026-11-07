import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../controllers/home_controller.dart';
import '../../models/home_catalogo.dart';
import '../../theme/ventiq_home_theme.dart';
import '../../utils/categoria_gradiente.dart';
import '../../utils/categoria_icono.dart';
import 'producto_tile.dart';
import 'tarjeta_exploracion.dart';
import 'ventiq_skeleton.dart';

/// Drawer jerárquico de categorías, **a pantalla completa**.
///
/// Sustituye al "tocar categoría → listado de productos" del Home viejo. Lo que
/// resuelve, que era el encargo:
///
///  * tocar una categoría **especial** sin subcategorías va directo a sus
///    productos; con subcategorías, abre su nivel de subcategorías;
///  * tocar **"Tienda"** abre el nivel de categorías no especiales;
///  * dentro, bajar y subir de nivel sin salir: el nivel anterior ya está
///    resuelto en la pila, así que volver es instantáneo;
///  * **cinco** formas de salir o retroceder, y ninguna obliga a la «X»;
///  * tocar una subcategoría enseña sus productos **sin pasar por el listado**,
///    y el listado completo sigue a un toque si se quiere.
///
/// La navegación por niveles vive en [HomeController]; aquí solo se pinta y se
/// traducen gestos a llamadas.
class CategoriaDrawer extends StatefulWidget {
  const CategoriaDrawer({
    super.key,
    required this.controller,
    required this.onAbrirProducto,
    required this.onAbrirCarrito,
    required this.carrito,
    this.onAgregarProducto,
    this.mostrarSku = false,
    this.atenuarImagenes = false,
  });

  final HomeController controller;

  /// Toca un producto: abre su detalle.
  final void Function(HomeProducto producto) onAbrirProducto;

  /// «Ir al carrito» del pie.
  final VoidCallback onAbrirCarrito;

  /// Cuántas líneas lleva el carrito, para el pie. Es un listenable porque el
  /// drawer es una ruta aparte y no se reconstruye con el `setState` del Home.
  final ValueListenable<int> carrito;

  /// "＋": suma una unidad sin salir del drawer. `null` = sin venta rápida.
  final void Function(HomeProducto producto)? onAgregarProducto;

  final bool mostrarSku;
  final bool atenuarImagenes;

  @override
  State<CategoriaDrawer> createState() => _CategoriaDrawerState();
}

class _CategoriaDrawerState extends State<CategoriaDrawer> {
  /// Desplazamiento vertical acumulado en la cabecera.
  double _arrastreVertical = 0;

  /// Umbral de arrastre hacia abajo para cerrar, en píxeles o por velocidad.
  static const double _umbralCierre = 120;
  static const double _velocidadCierre = 700;

  /// Ancho de la franja del borde izquierdo que acepta el gesto de "atrás".
  static const double _franjaBorde = 28;

  /// Distancia horizontal para que el gesto del borde cuente.
  static const double _umbralBorde = 64;

  HomeController get _c => widget.controller;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Con más de un nivel, el "atrás" del sistema sube un nivel en vez de
      // cerrar. Es la diferencia con un Scaffold.drawer, que se lo tragaría.
      canPop: !_c.puedeVolverAtras,
      onPopInvokedWithResult: (bool hizoPop, Object? _) {
        if (hizoPop) return;
        setState(() => _c.volverNivel());
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          // Ocupa toda la pantalla: sin márgenes laterales y con el alto del
          // viewport. Los 28 px de radio superior son lo único que lo delata
          // como hoja.
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height,
          ),
          decoration: const BoxDecoration(
            color: VentiqHomeTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: ListenableBuilder(
              listenable: _c,
              builder: (BuildContext context, _) {
                return Column(
                  children: <Widget>[
                    _cabecera(context),
                    Expanded(
                      child: Stack(
                        children: <Widget>[
                          AnimatedSwitcher(
                            duration:
                                VentiqHomeTheme.reduceMotion(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: _transicionDeNivel,
                            child: KeyedSubtree(
                              key: ValueKey<String>(
                                '${_c.pasoActual?.nivel}-${_c.pila.length}',
                              ),
                              child: _nivelActual(context),
                            ),
                          ),
                          // Franja del borde izquierdo: sube un nivel.
                          if (_c.puedeVolverAtras)
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: _franjaBorde,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onHorizontalDragUpdate: (DragUpdateDetails d) {
                                  _gestoBorde += d.delta.dx;
                                },
                                onHorizontalDragEnd: (_) {
                                  if (_gestoBorde >= _umbralBorde) {
                                    setState(() => _c.volverNivel());
                                  }
                                  _gestoBorde = 0;
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  double _gestoBorde = 0;

  /// La transición va en la dirección del movimiento: al bajar de nivel entra
  /// desde la derecha; al subir, desde la izquierda. Sin eso, "atrás" y
  /// "adelante" se sienten iguales.
  Widget _transicionDeNivel(Widget hijo, Animation<double> animacion) {
    final bool avanzando = _c.pila.length > _nivelAnterior;
    _nivelAnterior = _c.pila.length;

    if (VentiqHomeTheme.reduceMotion(context)) return hijo;

    final double desde = avanzando ? 0.06 : -0.06;
    return FadeTransition(
      opacity: animacion,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(desde, 0),
          end: Offset.zero,
        ).animate(animacion),
        child: hijo,
      ),
    );
  }

  int _nivelAnterior = 1;

  // ── Cabecera ───────────────────────────────────────────────────────────

  Widget _cabecera(BuildContext context) {
    return GestureDetector(
      // Arrastrar la cabecera hacia abajo cierra. Solo la cabecera: el cuerpo
      // es scrolleable y robárselo sería peor que no tener el gesto.
      onVerticalDragUpdate: (DragUpdateDetails d) {
        setState(() => _arrastreVertical += d.delta.dy);
      },
      onVerticalDragEnd: (DragEndDetails d) {
        final double velocidad = d.primaryVelocity ?? 0;
        if (_arrastreVertical > _umbralCierre || velocidad > _velocidadCierre) {
          _cerrar();
        } else {
          setState(() => _arrastreVertical = 0);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        // Sigue al dedo un poco, para que el gesto se sienta vivo.
        transform: Matrix4.translationValues(0, _arrastreVertical * 0.35, 0),
        child: Column(
          children: <Widget>[
            // Grabber: la señal de "esto se arrastra".
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 8, 8),
              child: Row(
                children: <Widget>[
                  if (_c.puedeVolverAtras)
                    IconButton(
                      tooltip: 'Volver a ${_tituloAnterior()}',
                      onPressed: () => setState(() => _c.volverNivel()),
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: VentiqHomeTheme.primary,
                      visualDensity: VisualDensity.compact,
                    )
                  else
                    const SizedBox(width: 10),
                  Expanded(child: _breadcrumb()),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: _cerrar,
                    icon: const Icon(Icons.close_rounded),
                    color: VentiqHomeTheme.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Migajas tocables: `Tienda › Bebidas › Gaseosas`.
  ///
  /// Es la tercera forma de volver: saltar directamente a un nivel anterior sin
  /// ir uno a uno. Tocar una migaja intermedia sube hasta ahí.
  Widget _breadcrumb() {
    final List<String> migajas = _c.migajas;
    if (migajas.isEmpty) return const SizedBox.shrink();

    final List<Widget> piezas = <Widget>[];
    for (int i = 0; i < migajas.length; i++) {
      final bool esActual = i == migajas.length - 1;
      piezas.add(
        Flexible(
          child: GestureDetector(
            onTap:
                esActual
                    ? null
                    : () => setState(() {
                      while (_c.pila.length > i + 1) {
                        _c.volverNivel();
                      }
                    }),
            child: Text(
              migajas[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: esActual ? FontWeight.w800 : FontWeight.w600,
                color:
                    esActual
                        ? VentiqHomeTheme.textPrimary
                        : VentiqHomeTheme.textSecondary,
              ),
            ),
          ),
        ),
      );
      if (!esActual) {
        piezas.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
        );
      }
    }

    return Row(children: piezas);
  }

  String _tituloAnterior() {
    final List<HomePasoDrawer> pila = _c.pila;
    if (pila.length < 2) return kNombreTienda;
    return pila[pila.length - 2].titulo;
  }

  void _cerrar() {
    // `pop` directo, **no** `maybePop`: con más de un nivel el `PopScope`
    // bloquea el "atrás" para subir un nivel, y `maybePop` se lo consultaría al
    // PopScope. La «X» y el arrastre sí deben cerrar, así que se salta ese
    // diálogo. El botón atrás del sistema sigue pasando por el PopScope.
    Navigator.of(context).pop();
  }

  // ── Niveles ────────────────────────────────────────────────────────────

  Widget _nivelActual(BuildContext context) {
    final HomePasoDrawer? paso = _c.pasoActual;
    if (paso == null) return const SizedBox.shrink();

    switch (paso.nivel) {
      case HomeNivelDrawer.categorias:
        return _grillaCategorias(context, paso.categorias);
      case HomeNivelDrawer.subcategorias:
        return _nivelSubcategorias(context, paso);
      case HomeNivelDrawer.productos:
        return _nivelProductos(context, paso);
    }
  }

  Widget _grillaCategorias(
    BuildContext context,
    List<HomeCategoria> categorias,
  ) {
    if (categorias.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No hay nada en «$kNombreTienda».',
            textAlign: TextAlign.center,
            style: TextStyle(color: VentiqHomeTheme.textSecondary),
          ),
        ),
      );
    }

    final double alto = VentiqHomeTheme.cardExtent(
      context,
      base: VentiqHomeTheme.cardExtentDrawer,
    );

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columnas(context),
        mainAxisSpacing: VentiqHomeTheme.gridSpacing,
        crossAxisSpacing: VentiqHomeTheme.gridSpacing,
        mainAxisExtent: alto,
      ),
      itemCount: categorias.length,
      itemBuilder: (BuildContext context, int i) {
        final HomeCategoria c = categorias[i];
        // El latido de 190 ms es la respuesta visual al toque. Sin él, el
        // cambio de nivel se siente como un salto sin causa.
        return _TarjetaConBoom(
          onTap:
              () => setState(() {
                _c.abrirCategoria(c);
              }),
          hijo:
              (VoidCallback onTap) => TarjetaExploracion(
                chip:
                    '${c.totalProductos} PRODUCTO'
                    '${c.totalProductos == 1 ? '' : 'S'}',
                titulo: c.nombre,
                subtitulo:
                    c.tieneSubcategorias
                        ? '${c.totalSubcategorias} subcategoría'
                            '${c.totalSubcategorias == 1 ? '' : 's'}'
                        : 'Ver productos',
                icono: iconoCategoria(c.nombre),
                colores: gradienteCategoria(c.id),
                imagenUrl: c.imagen,
                onTap: onTap,
              ),
        );
      },
    );
  }

  Widget _nivelSubcategorias(BuildContext context, HomePasoDrawer paso) {
    if (_c.cargandoNivel) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: VentiqSkeletonRejilla(cantidad: 4, columnas: 2),
      );
    }

    if (_c.errorNivel != null) {
      return _errorNivel();
    }

    final HomeCategoria? categoria = paso.categoria;
    if (categoria == null) return const SizedBox.shrink();

    final List<HomeSubcategoria> subs = _c.subcategorias;
    final double alto = VentiqHomeTheme.cardExtent(context, base: 112);

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _bannerCategoria(categoria)),
        if (subs.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Text(
                'Esta categoría no tiene subcategorías: al abrirla ves todos '
                'sus productos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: VentiqHomeTheme.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            // Las subcategorías entran en cascada: es la señal de que se ha
            // bajado un nivel, no de que la pantalla se ha recargado.
            sliver: _CascadaRejilla(
              cantidad: subs.length,
              columnas: _columnas(context),
              alto: alto,
              itemBuilder: (BuildContext context, int i) {
                final HomeSubcategoria s = subs[i];
                return TarjetaExploracion(
                  chip:
                      '${s.totalProductos} PRODUCTO'
                      '${s.totalProductos == 1 ? '' : 'S'}',
                  titulo: s.nombre,
                  subtitulo: 'Ver productos',
                  icono: Icons.label_outline_rounded,
                  colores: gradienteCategoria(s.id + 3),
                  onTap:
                      () => setState(() {
                        _c.abrirSubcategoria(s);
                      }),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Banner grande de la categoría abierta, con el atajo al listado completo.
  Widget _bannerCategoria(HomeCategoria categoria) {
    final List<Color> colores = gradienteCategoria(categoria.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusCard),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colores,
            ),
          ),
          child: Stack(
            children: <Widget>[
              Positioned(
                right: -10,
                bottom: -16,
                child: Icon(
                  iconoCategoria(categoria.nombre),
                  size: 84,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      categoria.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${categoria.totalProductos} producto'
                      '${categoria.totalProductos == 1 ? '' : 's'}'
                      ' · ${categoria.totalSubcategorias} subcategoría'
                      '${categoria.totalSubcategorias == 1 ? '' : 's'}',
                      style: VentiqHomeTheme.subtituloTarjeta,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nivelProductos(BuildContext context, HomePasoDrawer paso) {
    if (_c.cargandoNivel) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: 6,
        itemBuilder:
            (_, __) => const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: VentiqSkeleton(height: 64, radius: 16),
            ),
      );
    }

    if (_c.errorNivel != null) {
      return _errorNivel();
    }

    final HomeCategoria? categoria = paso.categoria;
    if (categoria == null) return const SizedBox.shrink();

    final List<HomeProducto> productos = _c.productosNivel;

    if (productos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.inbox_rounded,
                size: 44,
                color: VentiqHomeTheme.textSecondary.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 12),
              Text(
                'No hay productos en «${paso.titulo}».',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: VentiqHomeTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8),
            itemCount: productos.length,
            itemBuilder: (BuildContext context, int i) {
              final HomeProducto p = productos[i];
              return ProductoTile(
                producto: p,
                heroTag: 'prod-${p.id}',
                mostrarSku: widget.mostrarSku,
                atenuarImagenes: widget.atenuarImagenes,
                onTap: () => widget.onAbrirProducto(p),
                onAgregar:
                    (widget.onAgregarProducto == null || !p.disponible)
                        ? null
                        : () => widget.onAgregarProducto!(p),
              );
            },
          ),
        ),
        // Pie fijo: las dos salidas útiles al vender. «Seguir añadiendo» sube a la
        // lista de categorías sin cerrar el drawer; «Carrito» lleva al carrito
        // con lo que se lleva acumulado. Ya no hay salto a `ProductsScreen`.
        _pieCarrito(),
      ],
    );
  }

  Widget _pieCarrito() {
    // «Seguir añadiendo» solo tiene sentido si hay un nivel al que subir. En la
    // raíz (p. ej. una especial sin subcategorías) se deja solo el carrito.
    final bool puedeSubir = _c.pila.length > 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: VentiqHomeTheme.card,
        border: Border(top: BorderSide(color: VentiqHomeTheme.border)),
      ),
      child: Row(
        children: <Widget>[
          if (puedeSubir) ...<Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _c.volverARaiz()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VentiqHomeTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: VentiqHomeTheme.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text(
                  'Seguir añadiendo',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: widget.carrito,
              builder: (BuildContext context, int items, _) {
                return FilledButton.icon(
                  onPressed: widget.onAbrirCarrito,
                  style: FilledButton.styleFrom(
                    backgroundColor: VentiqHomeTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.shopping_cart_rounded, size: 18),
                  label: Text(
                    items > 0 ? 'Carrito ($items)' : 'Carrito',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorNivel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_rounded,
              size: 42,
              color: VentiqHomeTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _c.errorNivel!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  () => setState(() {
                    _c.reintentarNivel();
                  }),
              style: FilledButton.styleFrom(
                backgroundColor: VentiqHomeTheme.primary,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  /// En el drawer caben menos columnas que en el Home: el panel es alto pero
  /// estrecho, y una tarjeta de 100 pt no deja leer el nombre.
  int _columnas(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 700 ? 3 : 2;
}

/// Envoltorio que hace "latir" la tarjeta antes de entrar en la carpeta.
///
/// Es el gesto del home de `inventtia_flow`: al tocar, la tarjeta late
/// (0.86 → 1 en 240 ms) y **190 ms después** cambia el nivel. Ese medio segundo
/// es lo que separa "se ha abierto algo" de "la pantalla ha parpadeado".
///
/// El cambio de nivel corta la animación a propósito: la tarjeta empuja y
/// desaparece, no se queda encogida esperando.
class _TarjetaConBoom extends StatefulWidget {
  const _TarjetaConBoom({required this.hijo, required this.onTap});

  /// El hijo recibe el callback de toque ya resuelto. Así la tarjeta no se
  /// duplica ni hace falta envolverla con otro detector de gestos.
  final Widget Function(VoidCallback onTap) hijo;

  /// Qué hacer tras el latido: cambiar de nivel.
  final VoidCallback onTap;

  @override
  State<_TarjetaConBoom> createState() => _TarjetaConBoomState();
}

class _TarjetaConBoomState extends State<_TarjetaConBoom>
    with SingleTickerProviderStateMixin {
  static const Duration _latido = Duration(milliseconds: 240);
  static const Duration _antesDeEntrar = Duration(milliseconds: 190);

  // `value: 1` = en reposo la tarjeta está a escala 1. El latido arranca en
  // 0.86 y vuelve; si se dejara en 0 la tarjeta nacería encogida.
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: _latido,
    value: 1,
  );

  late final Animation<double> _escala = Tween<double>(
    begin: 0.86,
    end: 1,
  ).animate(CurvedAnimation(parent: _control, curve: Curves.easeOutBack));

  /// Evita dos entradas si el vendedor toca dos veces en el medio segundo de
  /// espera (en un TPV se toca rápido y con dedos grandes).
  bool _entrando = false;

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  Future<void> _tocar() async {
    if (_entrando) return;
    _entrando = true;

    // Con movimiento reducido no hay latido: se entra de una.
    if (VentiqHomeTheme.reduceMotion(context)) {
      widget.onTap();
      return;
    }

    unawaited(_control.forward(from: 0));
    await Future<void>.delayed(_antesDeEntrar);
    if (!mounted) return;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _escala, child: widget.hijo(_tocar));
  }
}

/// Rejilla de subcategorías que aparece en cascada (`Interval(0.14 * i, 1)`).
///
/// Se hace con un solo `AnimationController` y un `Interval` por índice: N
/// animaciones vivas para N tarjetas sería justo lo que hay que evitar en un
/// TPV de gama baja (§10 del plan).
class _CascadaRejilla extends StatefulWidget {
  const _CascadaRejilla({
    required this.cantidad,
    required this.columnas,
    required this.alto,
    required this.itemBuilder,
  });

  final int cantidad;
  final int columnas;
  final double alto;
  final Widget Function(BuildContext context, int indice) itemBuilder;

  @override
  State<_CascadaRejilla> createState() => _CascadaRejillaState();
}

class _CascadaRejillaState extends State<_CascadaRejilla>
    with SingleTickerProviderStateMixin {
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 430),
  );

  @override
  void initState() {
    super.initState();
    _control.forward();
  }

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduce = VentiqHomeTheme.reduceMotion(context);

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columnas,
        mainAxisSpacing: VentiqHomeTheme.gridSpacing,
        crossAxisSpacing: VentiqHomeTheme.gridSpacing,
        mainAxisExtent: widget.alto,
      ),
      delegate: SliverChildBuilderDelegate((BuildContext context, int i) {
        final Widget hijo = widget.itemBuilder(context, i);
        if (reduce) return hijo;

        // Las dos primeras ya están dentro; a partir de ahí se escalona y el
        // retardo se corta al 55 % para que la última no llegue tarde.
        final double inicio = math.min(0.14 * i, 0.55);

        // Dos curvas distintas a propósito: `easeOutBack` se pasa de 1 y una
        // opacidad > 1 revienta en debug. El fundido usa una curva acotada.
        final Animation<double> aparecer = CurvedAnimation(
          parent: _control,
          curve: Interval(inicio, 1, curve: Curves.easeOut),
        );
        final Animation<double> crecer = CurvedAnimation(
          parent: _control,
          curve: Interval(inicio, 1, curve: Curves.easeOutBack),
        );

        return FadeTransition(
          opacity: aparecer,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(crecer),
            child: hijo,
          ),
        );
      }, childCount: widget.cantidad),
    );
  }
}
