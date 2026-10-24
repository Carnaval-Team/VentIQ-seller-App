import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/categoria_con_conteo.dart';
import '../services/exploracion_service.dart';
import '../tutorial/tutorial_anchor.dart';
import '../utils/categoria_icono.dart';
import '../utils/exploracion_navegacion.dart';
import '../widgets/exploracion_rapida_grid.dart';

/// Panel lateral de categorías del cliente, con contadores reales por rubro.
///
/// COMO SE ABRE
///   Entra desde la izquierda como un cajón (`RutaLateral`): deja ver el Home
///   detrás, atenuado por un velo, y se cierra tocando el velo, con la X o con el
///   gesto de atrás. Por dentro sigue siendo una ruta —no un `Scaffold.drawer`—
///   para que el botón atrás, el «volver al shell» del tutorial y el cambio de
///   pestaña de la barra inferior sigan funcionando sin casos especiales.
///
/// QUE SE VE
///   Los rubros en tarjetas de dos en dos, con el MISMO lenguaje visual que los
///   atajos de «Exploración rápida» (degradado, chip, icono): el chip dice
///   cuántos locales hay y el pie de la tarjeta lleva «Ver todos». Tocar la
///   tarjeta abre la carpeta del rubro con una animación de despliegue y sus
///   subcategorías entran en cascada.
///
/// LAS DOS ACCIONES NO SE MEZCLAN (pedido del usuario)
///   * Tocar la tarjeta = abrir la carpeta (subcategorías).
///   * Tocar «Ver todos» = ir al listado de establecimientos filtrado por el
///     rubro.
///   * Tocar una subcategoría = listado filtrado por esa subcategoría.
///
/// DE DONDE SALE CADA DATO
///   `flow.cliente_categorias_resumen()` (migración 57) vía
///   [ExploracionService.categorias]: contadores con la misma regla de
///   visibilidad que el feed. Los tres números de la cabecera son GLOBALES y a
///   propósito no son la suma de las tarjetas: un local con servicios en dos
///   rubros se cuenta una vez arriba.
class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  /// Clave del velo que cierra el panel al tocarlo. Pública para poder pulsarla
  /// en un test sin depender de coordenadas.
  static const Key claveVelo = Key('categorias-panel-velo');

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  ResumenCategorias? _resumen;
  bool _cargando = true;
  bool _error = false;
  bool _migracionPendiente = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Lee el nomenclador con contadores.
  ///
  /// Se distingue "falta aplicar la migración 57" de "no hay conexión": son dos
  /// problemas distintos y solo uno se arregla reintentando.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
      _migracionPendiente = false;
    });
    try {
      final resumen = await ExploracionService.categorias();
      if (!mounted) return;
      setState(() {
        _resumen = resumen;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
        _migracionPendiente = ExploracionService.esMigracionPendiente(e);
      });
      debugPrint('[flow] CategoriasScreen._cargar ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ancho de cajón: deja ver la pantalla de detrás, que es lo que lo hace leer
    // como menú lateral y no como una página más. Tope para tablets.
    final ancho = MediaQuery.sizeOf(context).width;
    final anchoPanel = math.min(372.0, ancho * 0.88);

    return Scaffold(
      // Sin fondo propio ni barra inferior: el panel flota sobre la pantalla
      // anterior y la barra del shell se ve detrás, atenuada por el velo. Un
      // cajón con su propia barra de pestañas serían dos navegaciones a la vez.
      backgroundColor: Colors.transparent,
      // `Stack` y no `Row`: el velo cubre toda la pantalla por debajo y el panel
      // se apoya a la izquierda encima. Con una `Row` el velo quedaba reducido a
      // la franja de la derecha y dependía del ancho exacto del panel para
      // recibir el toque.
      body: Stack(
        children: [
          // Velo: tocar fuera cierra, como cualquier cajón.
          Positioned.fill(
            child: GestureDetector(
              key: CategoriasScreen.claveVelo,
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.maybePop(context),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.42),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: anchoPanel,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(26),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x3D1B2540),
                    blurRadius: 28,
                    offset: Offset(8, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CategoriasCabecera(
                    resumen: _resumen,
                    onCerrar: () => Navigator.maybePop(context),
                  ),
                  Expanded(child: _contenido()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido() {
    if (_cargando) return const _CargandoCategorias();
    if (_error) {
      return _ErrorCategorias(
        migracion: _migracionPendiente,
        onReintentar: _cargar,
      );
    }
    final resumen = _resumen ?? ResumenCategorias.vacio;
    return CategoriasCuerpo(resumen: resumen);
  }
}

/// Cabecera del panel: degradado de marca, título, totales globales y cerrar.
///
/// Es pública (y no privada) para poder pintarla en un test con un
/// [ResumenCategorias] inyectado, sin Supabase. El ancla del tutorial vive aquí:
/// la cabecera se monta en todos los estados, así que el paso nunca se queda sin
/// objetivo.
class CategoriasCabecera extends StatelessWidget {
  const CategoriasCabecera({super.key, this.resumen, this.onCerrar});

  /// `null` mientras carga: se pinta igual, sin la pastilla de totales.
  final ResumenCategorias? resumen;

  final VoidCallback? onCerrar;

  @override
  Widget build(BuildContext context) {
    final resumenActual = resumen;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
      ),
      // El degradado pasa por detrás de la barra de estado: el relleno de arriba
      // la compensa para que el título no quede debajo del reloj.
      padding: EdgeInsets.fromLTRB(
        18,
        14 + MediaQuery.paddingOf(context).top,
        10,
        18,
      ),
      child: TutorialAnchor(
        id: 'categorias_lista',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Categorías',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      onCerrar ?? () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white,
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Todos los rubros',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.80),
                fontSize: 12.5,
              ),
            ),
            if (resumenActual != null && resumenActual.hayAlgo) ...[
              const SizedBox(height: 12),
              _PildoraTotales(texto: _resumenGlobal(resumenActual)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cuerpo del panel: la rejilla de rubros y, al abrir uno, sus subcategorías.
///
/// Es público a propósito: no toca Supabase, así que `test/` puede pintarlo con
/// un [ResumenCategorias] de prueba y comprobar la apertura de carpetas, los
/// contadores y los destinos sin red.
///
/// Los tres callbacks son ganchos **solo para tests**: en la app van `null` y el
/// cuerpo navega con [ExploracionNavegacion], la única fuente de verdad de las
/// rutas nuevas.
class CategoriasCuerpo extends StatefulWidget {
  const CategoriasCuerpo({
    super.key,
    required this.resumen,
    this.onVerCategoria,
    this.onVerSubcategoria,
    this.onVerTodosLosEstablecimientos,
  });

  final ResumenCategorias resumen;

  final void Function(CategoriaConConteo categoria)? onVerCategoria;

  final void Function(
    CategoriaConConteo categoria,
    SubcategoriaConConteo subcategoria,
  )?
  onVerSubcategoria;

  final VoidCallback? onVerTodosLosEstablecimientos;

  @override
  State<CategoriasCuerpo> createState() => _CategoriasCuerpoState();
}

class _CategoriasCuerpoState extends State<CategoriasCuerpo> {
  /// Rubro cuya carpeta está abierta. `null` = rejilla de rubros.
  CategoriaConConteo? _abierta;

  /// Posición del rubro abierto en el resumen, para no volver a buscarla con
  /// `indexOf` (el modelo no tiene `==`) y para que el degradado del banner sea
  /// el mismo que tenía su tarjeta.
  int _indiceAbierto = 0;

  /// Rubro que está haciendo el «boom» de apertura (se está desplegando).
  int? _boom;

  bool get _reducido => MediaQuery.disableAnimationsOf(context);

  @override
  void didUpdateWidget(CategoriasCuerpo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si el host cambia el resumen con una carpeta abierta, la carpeta se cierra:
    // seguir mostrando las subcategorías del resumen anterior sería enseñar datos
    // que ya no corresponden a lo que dice el padre.
    if (!identical(oldWidget.resumen, widget.resumen) && _abierta != null) {
      setState(() {
        _abierta = null;
        _boom = null;
      });
    }
  }

  /// Abre la carpeta del rubro.
  ///
  /// Primero la tarjeta toca el «boom» (un latido de 190 ms, se ve crecer) y
  /// después se cambia a la vista de subcategorías. Encadenarlo así es lo que
  /// hace que se lea como una carpeta que se abre: si se cambiara de golpe, el
  /// toque no tendría respuesta visual.
  Future<void> _abrirCarpeta(CategoriaConConteo conteo, int indice) async {
    if (_reducido) {
      setState(() {
        _abierta = conteo;
        _indiceAbierto = indice;
      });
      return;
    }
    setState(() => _boom = conteo.categoria.id);
    await Future<void>.delayed(const Duration(milliseconds: 190));
    if (!mounted) return;
    setState(() {
      _boom = null;
      _abierta = conteo;
      _indiceAbierto = indice;
    });
  }

  void _cerrarCarpeta() => setState(() => _abierta = null);

  void _verCategoria(CategoriaConConteo conteo) {
    final callback = widget.onVerCategoria;
    if (callback != null) {
      callback(conteo);
      return;
    }
    ExploracionNavegacion.abrirEstablecimientos(
      context,
      categoria: conteo.categoria,
    );
  }

  void _verSubcategoria(
    CategoriaConConteo conteo,
    SubcategoriaConConteo subcategoria,
  ) {
    final callback = widget.onVerSubcategoria;
    if (callback != null) {
      callback(conteo, subcategoria);
      return;
    }
    ExploracionNavegacion.abrirEstablecimientos(
      context,
      categoria: conteo.categoria,
      subcategoria: subcategoria.categoria,
    );
  }

  void _verTodos() {
    final callback = widget.onVerTodosLosEstablecimientos;
    if (callback != null) {
      callback();
      return;
    }
    ExploracionNavegacion.abrirEstablecimientos(context);
  }

  @override
  Widget build(BuildContext context) {
    // El estado vacío lo decide el cuerpo, no la pantalla: así cualquier host
    // (la pantalla o un test que pinte el cuerpo) lo recibe igual.
    if (!widget.resumen.hayAlgo) {
      return const _CatalogoVacio();
    }

    final abierta = _abierta;
    return AnimatedSwitcher(
      duration: _reducido ? Duration.zero : const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: _transicionCarpeta,
      child: abierta == null
          ? KeyedSubtree(
              key: const ValueKey<String>('rejilla-rubros'),
              child: _buildRejilla(),
            )
          : KeyedSubtree(
              key: ValueKey<String>('carpeta-${abierta.categoria.id}'),
              child: _buildCarpeta(abierta),
            ),
    );
  }

  /// La carpeta se despliega desde el centro con un rebote suave: es el «boom»
  /// pedido, sin mover el resto de la pantalla.
  Widget _transicionCarpeta(Widget child, Animation<double> animacion) {
    return FadeTransition(
      opacity: animacion,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.90, end: 1).animate(
          CurvedAnimation(parent: animacion, curve: Curves.easeOutBack),
        ),
        child: child,
      ),
    );
  }

  // ── Rejilla de rubros ───────────────────────────────────────────────────

  Widget _buildRejilla() {
    final escala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final tarjetas = <Widget>[];

    for (var i = 0; i < widget.resumen.categorias.length; i++) {
      final conteo = widget.resumen.categorias[i];
      tarjetas.add(
        _conBoom(
          TarjetaExploracion(
            chip: _chipLocales(conteo.establecimientos),
            titulo: conteo.categoria.nombre,
            subtitulo: conteo.etiquetaServicios,
            icono: iconoCategoria(conteo.categoria),
            colores: _gradiente(i),
            onTap: () => _abrirCarpeta(conteo, i),
            // Dos destinos separados: la tarjeta abre la carpeta y el pie va al
            // listado. Sin establecimientos el pie se apaga (no hay nada que ver)
            // pero se sigue pintando, así todas las tarjetas miden igual.
            accionEtiqueta: conteo.vacia ? 'Sin establecimientos' : 'Ver todos',
            onAccion: conteo.vacia ? null : () => _verCategoria(conteo),
          ),
          boom: _boom == conteo.categoria.id,
        ),
      );
    }

    if (widget.resumen.hayOtros) {
      tarjetas.add(
        TarjetaExploracion(
          chip: _chipLocales(widget.resumen.otrosEstablecimientos),
          titulo: 'Otras',
          subtitulo: widget.resumen.otrosServicios == 1
              ? '1 servicio'
              : '${widget.resumen.otrosServicios} servicios',
          icono: Icons.more_horiz_rounded,
          colores: const [AppTheme.primary, AppTheme.primaryDark],
          onTap: _verTodos,
          accionEtiqueta: 'Ver todos',
          onAccion: _verTodos,
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        14,
        14,
        14,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Row(
            children: [
              const Icon(
                Icons.touch_app_outlined,
                size: 13,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Toca un rubro para ver sus subcategorías',
                  style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.95),
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 134 * escala,
          ),
          children: tarjetas,
        ),
      ],
    );
  }

  // ── Carpeta abierta (subcategorías) ─────────────────────────────────────

  Widget _buildCarpeta(CategoriaConConteo conteo) {
    final escala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final hijas = conteo.subcategorias;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        14,
        12,
        14,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _cerrarCarpeta,
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppTheme.primary,
              tooltip: 'Volver a los rubros',
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                'Subcategorías de ${conteo.categoria.nombre}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // La carpeta abierta, como pieza grande: es el «contenedor» del que salen
        // las subcategorías y desde donde se puede ver el rubro completo.
        _BannerCarpeta(
          conteo: conteo,
          indice: _indiceAbierto,
          onVerTodos: conteo.vacia ? null : () => _verCategoria(conteo),
        ),
        const SizedBox(height: 14),
        if (hijas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Este rubro no tiene subcategorías: al abrirlo ves todos sus '
              'establecimientos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
            ),
          )
        else
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 112 * escala,
            ),
            children: [
              // En cascada: cada tarjeta entra un poco después que la anterior,
              // que es lo que da la sensación de carpeta que se abre.
              for (var i = 0; i < hijas.length; i++)
                _conCascada(
                  TarjetaExploracion(
                    chip: _chipLocales(hijas[i].establecimientos),
                    titulo: hijas[i].categoria.nombre,
                    subtitulo: hijas[i].etiquetaServicios,
                    icono: iconoCategoria(hijas[i].categoria),
                    colores: _gradiente(i),
                    onTap: () => _verSubcategoria(conteo, hijas[i]),
                  ),
                  indice: i,
                ),
            ],
          ),
      ],
    );
  }

  // ── Animaciones ────────────────────────────────────────────────────────

  /// Latido de la tarjeta que se está abriendo (crece con rebote).
  Widget _conBoom(Widget hijo, {required bool boom}) {
    if (!boom || _reducido) return hijo;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.86, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      builder: (_, valor, child) => Transform.scale(scale: valor, child: child),
      child: hijo,
    );
  }

  /// Entrada en cascada de las subcategorías, con rebote y desvanecido.
  Widget _conCascada(Widget hijo, {required int indice}) {
    if (_reducido) return hijo;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 430),
      curve: Interval(
        math.min(0.14 * indice, 0.55),
        1,
        curve: Curves.easeOutBack,
      ),
      builder: (_, valor, child) => Opacity(
        // `easeOutBack` pasa de 1 al final: la opacidad se acota, la escala no
        // (ese pequeño exceso es el rebote).
        opacity: valor.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.86 + 0.14 * valor, child: child),
      ),
      child: hijo,
    );
  }
}

/// Pieza grande de la carpeta abierta: el rubro con sus contadores y el atajo al
/// listado completo.
class _BannerCarpeta extends StatelessWidget {
  const _BannerCarpeta({
    required this.conteo,
    required this.indice,
    required this.onVerTodos,
  });

  final CategoriaConConteo conteo;
  final int indice;
  final VoidCallback? onVerTodos;

  @override
  Widget build(BuildContext context) {
    final colores = _gradiente(indice < 0 ? 0 : indice);
    final activo = onVerTodos != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colores,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26202A45),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: _ChipTexto(texto: _chipLocales(conteo.establecimientos))),
              const SizedBox(width: 6),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Icon(
                  iconoCategoria(conteo.categoria),
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            conteo.categoria.nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            conteo.vacia
                ? 'Todavía sin establecimientos'
                : '${conteo.etiquetaServicios} en ${conteo.etiquetaEstablecimientos.toLowerCase()}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onVerTodos,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: activo ? 1 : 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `Flexible`: el panel es estrecho (88 % del ancho, tope 372) y
                  // el texto tiene que recortar antes que desbordar la fila.
                  Flexible(
                    child: Text(
                      'Ver todos los establecimientos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: activo
                            ? AppTheme.primaryDark
                            : Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (activo) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: AppTheme.primaryDark,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta pequeña en mayúsculas (mismo aspecto que el chip de las tarjetas).
class _ChipTexto extends StatelessWidget {
  const _ChipTexto({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

// ── Estados ────────────────────────────────────────────────────────────────

class _CargandoCategorias extends StatelessWidget {
  const _CargandoCategorias();

  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(strokeWidth: 2.4),
    ),
  );
}

class _ErrorCategorias extends StatelessWidget {
  const _ErrorCategorias({required this.migracion, required this.onReintentar});

  /// `true` = el fallo es que falta la migración 57, no la conexión.
  final bool migracion;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              migracion ? Icons.build_circle_outlined : Icons.cloud_off_rounded,
              size: 42,
              color: AppTheme.primary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 10),
            Text(
              migracion
                  ? 'Todavía falta un paso en la base de datos'
                  : 'No pudimos leer las categorías',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              migracion
                  ? ExploracionService.mensajeMigracionPendiente
                  : 'Revisa tu conexión y vuelve a intentarlo.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogoVacio extends StatelessWidget {
  const _CatalogoVacio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.category_outlined,
              size: 44,
              color: AppTheme.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'El catálogo todavía no tiene categorías publicadas',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Apoyo ──────────────────────────────────────────────────────────────────

/// Los cuatro degradados de «Exploración rápida», en ciclo.
///
/// Que las tarjetas de aquí usen los MISMOS cuatro degradados que los atajos del
/// Home es lo que hace que las dos vistas se lean como la misma familia.
const List<List<Color>> _degradados = <List<Color>>[
  [AppTheme.exploracionIndigo, AppTheme.exploracionIndigoDark],
  [AppTheme.exploracionTeal, AppTheme.exploracionTealDark],
  [AppTheme.exploracionNavy, AppTheme.exploracionNavyDark],
  [AppTheme.exploracionCoral, AppTheme.exploracionCoralDark],
];

List<Color> _gradiente(int indice) {
  if (indice < 0) return _degradados.first;
  return _degradados[indice % _degradados.length];
}

/// «3 LOCALES» / «1 LOCAL» / «SIN LOCALES»: el dato que el usuario pidió ver en
/// la tarjeta, en el mismo formato de chip que los atajos del Home.
String _chipLocales(int establecimientos) {
  if (establecimientos <= 0) return 'SIN LOCALES';
  return establecimientos == 1 ? '1 LOCAL' : '$establecimientos LOCALES';
}

/// «6 categorías · 8 establecimientos · 11 servicios».
///
/// Los tres números son los GLOBALES del resumen, no la suma de las tarjetas: un
/// local con servicios en dos rubros se cuenta una vez aquí y una vez en cada
/// tarjeta, y sumarlas lo contaría dos veces.
String _resumenGlobal(ResumenCategorias resumen) {
  final categorias = resumen.categoriasActivas == 1
      ? '1 categoría'
      : '${resumen.categoriasActivas} categorías';
  final establecimientos = resumen.totalEstablecimientos == 1
      ? '1 establecimiento'
      : '${resumen.totalEstablecimientos} establecimientos';
  final servicios = resumen.totalServicios == 1
      ? '1 servicio'
      : '${resumen.totalServicios} servicios';
  return '$categorias · $establecimientos · $servicios';
}

/// Los tres totales globales, en una pastilla legible sobre el degradado.
class _PildoraTotales extends StatelessWidget {
  const _PildoraTotales({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
