import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/coleccion_service.dart';
import '../services/home_catalog_service.dart';
import '../utils/coleccion_servicios.dart';
import '../utils/horario_atencion.dart';
import '../utils/precio_reserva.dart';
import '../widgets/net_image.dart';
import '../widgets/resenas.dart';
import '../widgets/tarjeta_coleccion.dart';
import 'local_servicio_detail_screen.dart';
import 'mis_tickets_screen.dart';
import 'reserva_multiple_screen.dart';

/// Vista de marketing de una **colección temática** (`flow.coleccion`).
///
/// POR QUE EXISTE
///   Antes, tocar una colección en el Home **filtraba el propio feed**: el
///   cliente veía la misma lista de tarjetas, solo que recortada, y perdía la
///   sección curada de vista. Una colección no es un filtro, es una
///   **propuesta**: "todo para la cara", "pack novia". Aquí se presenta como tal
///   (portada con el degradado de la colección, de qué va, qué establecimientos
///   participan y todo lo que trae) y desde aquí se reserva.
///
/// DE DONDE SALE CADA DATO
///   * La colección (título, subtítulo, colores, icono, vigencia y el orden
///     curado de sus servicios): `flow.coleccion` vía el feed del Home.
///   * Los servicios: `flow.cliente_home_feed(p_id_coleccion => id)`, que ya
///     aplica `flow._ls_disponible`, el orden curado, la valoración real y la
///     promoción vigente. Es la misma fuente que el Home: cero RPC nuevo.
///
/// NADA DE ESTA PANTALLA CAMBIA EL PRECIO. Los importes que se ven son el precio
/// base del catálogo, etiquetados como referencia; el definitivo lo fija el
/// servidor al confirmar cada reserva (`flow.cotizar_reserva` /
/// `flow.cliente_reservar_directo`).
class ColeccionDetailScreen extends StatefulWidget {
  const ColeccionDetailScreen({
    super.key,
    required this.coleccion,
    this.serviciosIniciales,
  });

  final Coleccion coleccion;

  /// Servicios ya resueltos, **solo para tests de widget**.
  ///
  /// El cuerpo de esta vista (agrupado por establecimiento, tarjetas, modo
  /// selección) solo se puede ejercitar sin Supabase si se le inyecta el
  /// catálogo. En la app siempre es `null` y la pantalla lo lee del feed.
  @visibleForTesting
  final List<HomeCatalogItem>? serviciosIniciales;

  @override
  State<ColeccionDetailScreen> createState() => _ColeccionDetailScreenState();
}

class _ColeccionDetailScreenState extends State<ColeccionDetailScreen> {
  List<HomeCatalogItem> _items = const [];
  bool _cargando = true;
  bool _error = false;

  /// `true` una vez que el cliente toca "Reservar": las tarjetas pasan a
  /// seleccionarse en vez de abrirse. Se sale con la X del AppBar o con
  /// "Cancelar" de la barra inferior.
  bool _modoSeleccion = false;

  /// `flow.local_servicio.id` seleccionados, en el orden en que se eligieron.
  final List<int> _seleccionados = [];

  Coleccion get _coleccion => widget.coleccion;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final inyectados = widget.serviciosIniciales;
    if (inyectados != null) {
      setState(() {
        _items = _ordenarSegunCuraduria(inyectados);
        _cargando = false;
        _error = false;
      });
      return;
    }
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      final feed = await HomeCatalogService.fetchFeed(
        idColeccion: _coleccion.id,
      );
      if (!mounted) return;
      setState(() {
        _items = _ordenarSegunCuraduria(feed.items);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
      });
      debugPrint('[flow] ColeccionDetailScreen._cargar ERROR: $e');
    }
  }

  /// Respeta el orden curado por el superadmin.
  ///
  /// El servidor ya ordena por `orden_coleccion`, pero la colección que llegó al
  /// Home trae la lista de `local_servicio.id` en ese mismo orden: reordenar
  /// aqui en memoria deja la pantalla correcta aunque el RPC venga de una
  /// versión anterior que no ordenaba. Los servicios que no estén en esa lista
  /// (curados después de que el Home cargara) van al final, sin desaparecer.
  List<HomeCatalogItem> _ordenarSegunCuraduria(List<HomeCatalogItem> items) {
    final curados = _coleccion.servicios;
    if (curados.isEmpty) return items;
    final posicion = {for (var i = 0; i < curados.length; i++) curados[i]: i};
    final ordenados = List<HomeCatalogItem>.of(items);
    ordenados.sort((a, b) {
      final pa = posicion[a.id];
      final pb = posicion[b.id];
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pa.compareTo(pb);
    });
    return ordenados;
  }

  // ── Selección ────────────────────────────────────────────────────────────

  List<HomeCatalogItem> get _itemsSeleccionados => [
    for (final id in _seleccionados)
      for (final item in _items)
        if (item.id == id) item,
  ];

  void _alternar(HomeCatalogItem item) {
    if (!reservableEnLote(item)) {
      final motivo = motivoNoReservableEnLote(item) ?? '';
      _avisar(
        motivo == 'Solo lista de espera'
            ? '${item.title} solo admite lista de espera. Ábrelo para anotarte.'
            : '${item.title} se reserva desde su propia ficha.',
      );
      return;
    }
    setState(() {
      if (_seleccionados.contains(item.id)) {
        _seleccionados.remove(item.id);
      } else {
        _seleccionados.add(item.id);
      }
    });
  }

  void _seleccionarTodo() {
    setState(() {
      _seleccionados
        ..clear()
        ..addAll(_items.where(reservableEnLote).map((item) => item.id));
    });
  }

  void _limpiarSeleccion() => setState(_seleccionados.clear);

  void _entrarEnModoSeleccion() {
    // Sin aviso emergente: la portada ya cambia a "ELIGE TUS SERVICIOS" y la
    // barra de abajo explica qué hacer. Un `SnackBar` flotante tapaba justo el
    // botón de continuar.
    setState(() => _modoSeleccion = true);
  }

  void _salirDeModoSeleccion() {
    setState(() {
      _modoSeleccion = false;
      _seleccionados.clear();
    });
  }

  void _abrirServicio(HomeCatalogItem item) {
    final localServicio = item.localServicio;
    if (localServicio == null) {
      _avisar('No pudimos abrir este servicio.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalServicioDetailScreen(localServicio: localServicio),
      ),
    );
  }

  Future<void> _reservarSeleccionados() async {
    final seleccionados = _itemsSeleccionados;
    if (seleccionados.isEmpty) return;

    final creadas = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReservaMultipleScreen(
          coleccion: _coleccion,
          servicios: seleccionados,
        ),
      ),
    );
    if (!mounted) return;
    if (creadas == true) {
      setState(() {
        _modoSeleccion = false;
        _seleccionados.clear();
      });
      _avisar(
        'Reservas creadas. Las encuentras en "Mis tickets".',
        actionLabel: 'Ver',
      );
    }
  }

  void _avisar(String mensaje, {String? actionLabel}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: AppTheme.accent,
                  onPressed: _verMisTickets,
                ),
        ),
      );
  }

  void _verMisTickets() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MisTicketsScreen()),
    );
  }

  // ── Pintado ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      // La barra va dentro del `body`, como en la ficha de un servicio, y no en
      // `bottomNavigationBar`: el `Scaffold` mide esa ranura con altura
      // **ilimitada**, y un `Row` con un `Column` dentro se estiraba hasta
      // ocupar la pantalla entera, dejando el cuerpo con 0 px. Lo cazó
      // `test/coleccion_widgets_test.dart` (`Size(360.0, 0.0)`).
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _cargar,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  _hero(context),
                  SliverToBoxAdapter(child: _cuerpo()),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
          if (_items.isNotEmpty || _modoSeleccion) _barraInferior(),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final colores = degradadoDeColeccion(_coleccion);
    final oscuro = colores.last;
    final ancho = MediaQuery.sizeOf(context).width;
    // Alto generoso a propósito: el contenido va anclado abajo (título,
    // subtítulo y hasta cuatro chips). Con poco alto, un título de dos líneas
    // empujaba el contenido fuera de la portada por arriba.
    final alto = (ancho * 0.66).clamp(248.0, 336.0);
    final emoji = (_coleccion.icono?.trim().isNotEmpty ?? false)
        ? _coleccion.icono!.trim()
        : iconoColeccionPorDefecto;

    final grupos = agruparPorEstablecimiento(_items);
    final rango = rangoPrecios(_items);

    return SliverAppBar(
      expandedHeight: alto,
      pinned: true,
      stretch: true,
      backgroundColor: oscuro,
      foregroundColor: Colors.white,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _BotonCristal(
          icono: _modoSeleccion
              ? Icons.close_rounded
              : Icons.arrow_back_rounded,
          etiqueta: _modoSeleccion ? 'Cancelar selección' : 'Volver',
          onTap: () {
            if (_modoSeleccion) {
              _salirDeModoSeleccion();
            } else {
              Navigator.maybePop(context);
            }
          },
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Base: el degradado curado de la colección.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colores,
                ),
              ),
            ),
            // 2. Halo: profundidad sin añadir información falsa.
            Positioned(
              top: -70,
              right: -50,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.20),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            // 3. Emoji de marca de agua, a la derecha y recortado.
            Positioned(
              right: -14,
              bottom: -30,
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: 150,
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
            // 4. Velo: el texto va sobre negro progresivo, nunca sobre el
            //    degradado a pelo (ilegible con colores claros).
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.black.withValues(alpha: 0.10),
                    Colors.black.withValues(alpha: 0.74),
                  ],
                  stops: const [0, 0.34, 1],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _EtiquetaCristal(
                    texto: _modoSeleccion
                        ? 'ELIGE TUS SERVICIOS'
                        : 'COLECCIÓN CURADA',
                    icono: _modoSeleccion
                        ? Icons.checklist_rounded
                        : Icons.auto_awesome_rounded,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _coleccion.titulo.trim().isEmpty
                        ? 'Colección'
                        : _coleccion.titulo.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.7,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  if (_coleccion.subtitulo?.trim().isNotEmpty ?? false) ...[
                    const SizedBox(height: 6),
                    Text(
                      _coleccion.subtitulo!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_cargando)
                        const _DatoCristal(
                          icono: Icons.hourglass_top_rounded,
                          texto: 'Cargando servicios…',
                        )
                      else ...[
                        _DatoCristal(
                          icono: Icons.auto_awesome_rounded,
                          texto: _items.length == 1
                              ? '1 servicio'
                              : '${_items.length} servicios',
                        ),
                        if (grupos.length > 1)
                          _DatoCristal(
                            icono: Icons.storefront_outlined,
                            texto: '${grupos.length} establecimientos',
                          ),
                        if (rango != null)
                          _DatoCristal(
                            icono: Icons.sell_outlined,
                            texto: rango.unico
                                ? 'Desde ${importeCorto(rango.minimo, rango.moneda)}'
                                : '${importeCorto(rango.minimo, rango.moneda)} – '
                                      '${importeCorto(rango.maximo, rango.moneda)}',
                          ),
                      ],
                      if (_coleccion.hasta != null)
                        _DatoCristal(
                          icono: Icons.event_outlined,
                          texto: 'Hasta ${fechaCorta(_coleccion.hasta!)}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) return const _CargandoColeccion();
    if (_error) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: _Aviso(
          icono: Icons.cloud_off_rounded,
          titulo: 'No pudimos cargar la colección',
          detalle: 'Revisa tu conexión y vuelve a intentarlo.',
          accion: TextButton.icon(
            onPressed: _cargar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: _Aviso(
          icono: Icons.hourglass_empty_rounded,
          titulo: 'Esta colección está vacía',
          detalle:
              'El equipo la está armando. Vuelve en un rato para ver los '
              'servicios que incluye.',
        ),
      );
    }

    final grupos = agruparPorEstablecimiento(_items);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_modoSeleccion) ...[
            _ComoFunciona(servicios: _items.length),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Servicios de la colección',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (_modoSeleccion && _items.length > 1)
                TextButton(
                  onPressed: _seleccionados.length == _items.length
                      ? _limpiarSeleccion
                      : _seleccionarTodo,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _seleccionados.length == _items.length
                        ? 'Limpiar'
                        : 'Elegir todo',
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _modoSeleccion
                ? 'Elige los que quieras reservar y después escoge el turno de cada uno.'
                : 'Todo lo que incluye esta colección, agrupado por establecimiento.',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          for (final grupo in grupos) ...[
            _CabeceraEstablecimiento(grupo: grupo),
            const SizedBox(height: 8),
            for (final item in grupo.servicios) ...[
              _TarjetaServicioColeccion(
                item: item,
                modoSeleccion: _modoSeleccion,
                seleccionado: _seleccionados.contains(item.id),
                onToggle: () => _alternar(item),
                onAbrir: () => _abrirServicio(item),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  // ── Barra inferior ───────────────────────────────────────────────────────

  Widget _barraInferior() {
    if (!_modoSeleccion) {
      return _BarraFija(
        child: Row(
          children: [
            Expanded(
              child: Column(
                // `min`, no `max`: la barra se mide con altura ilimitada y un
                // `Column` que reclama todo el alto se come la pantalla.
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reserva varios servicios de una vez',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Eliges el día y el turno de cada uno antes de confirmar.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary.withValues(alpha: 0.95),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _entrarEnModoSeleccion,
              icon: const Icon(Icons.event_available_rounded, size: 18),
              label: const Text('Reservar'),
            ),
          ],
        ),
      );
    }

    final resumen = resumirSeleccion(_itemsSeleccionados);
    final listo = resumen.haySeleccion;

    return _BarraFija(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                listo ? Icons.check_circle_rounded : Icons.touch_app_outlined,
                size: 17,
                color: listo ? AppTheme.success : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  listo
                      ? '${resumen.etiquetaServicios} · '
                            '${resumen.etiquetaEstablecimientos}'
                      : 'Toca los servicios que quieras reservar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: listo
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
              if (resumen.estimado != null)
                Text(
                  '${resumen.sumaCompleta ? '' : '≈ '}'
                  '${importeCorto(resumen.estimado!, resumen.moneda)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: _seleccionados.isEmpty
                    ? _salirDeModoSeleccion
                    : null,
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: listo ? _reservarSeleccionados : null,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    listo
                        ? 'Elegir turnos (${resumen.servicios})'
                        : 'Elegir turnos',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Widgets de apoyo ───────────────────────────────────────────────────────

/// Barra fija inferior: fondo blanco, sombra hacia arriba y `SafeArea`.
class _BarraFija extends StatelessWidget {
  const _BarraFija({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: child,
        ),
      ),
    );
  }
}

/// Botón redondo translúcido sobre la portada (volver / cancelar).
class _BotonCristal extends StatelessWidget {
  const _BotonCristal({
    required this.icono,
    required this.onTap,
    required this.etiqueta,
  });

  final IconData icono;
  final VoidCallback onTap;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icono, size: 20, color: Colors.white),
        tooltip: etiqueta,
      ),
    );
  }
}

/// Etiqueta superior de la portada ("COLECCIÓN CURADA").
class _EtiquetaCristal extends StatelessWidget {
  const _EtiquetaCristal({required this.texto, required this.icono});

  final String texto;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            texto,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de dato real sobre la portada.
class _DatoCristal extends StatelessWidget {
  const _DatoCristal({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.96),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Los tres pasos del flujo. No es adorno: es la razón por la que esta pantalla
/// existe (elegir varios servicios y darle a cada uno su día y su turno).
class _ComoFunciona extends StatelessWidget {
  const _ComoFunciona({required this.servicios});

  final int servicios;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D2B3A67),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.route_outlined,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Cómo reservar esta colección',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                servicios == 1 ? '1 servicio' : '$servicios servicios',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _Paso(
            numero: '1',
            titulo: 'Elige los servicios',
            detalle:
                'Marca todo lo que quieras hacerte, aunque sea de locales distintos.',
          ),
          const _Paso(
            numero: '2',
            titulo: 'Ponle día y turno a cada uno',
            detalle:
                'Uno para hoy, otro para mañana: cada servicio lleva su propia fecha y su propio turno.',
          ),
          const _Paso(
            numero: '3',
            titulo: 'Confirma tus reservas',
            detalle:
                'Se crean una por servicio y las ves todas en "Mis tickets".',
            ultimo: true,
          ),
        ],
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({
    required this.numero,
    required this.titulo,
    required this.detalle,
    this.ultimo = false,
  });

  final String numero;
  final String titulo;
  final String detalle;
  final bool ultimo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: ultimo ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Text(
              numero,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detalle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cabecera de un establecimiento dentro de la colección.
class _CabeceraEstablecimiento extends StatelessWidget {
  const _CabeceraEstablecimiento({required this.grupo});

  final GrupoEstablecimiento grupo;

  @override
  Widget build(BuildContext context) {
    final ubicacion = grupo.ubicacion?.trim();
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C3654), Color(0xFF3E4E80)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            grupo.nombre.trim().isEmpty
                ? '?'
                : grupo.nombre.trim().substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                grupo.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (ubicacion != null && ubicacion.isNotEmpty)
                Text(
                  ubicacion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        Text(
          grupo.total == 1 ? '1 servicio' : '${grupo.total} servicios',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de un servicio de la colección.
///
/// Fuera del modo selección abre la ficha del servicio (donde se ve todo el
/// detalle). Dentro, alterna la selección; si el servicio no se puede cerrar en
/// el asistente (solo cola, o transporte ómnibus) lo dice y no deja marcarlo.
class _TarjetaServicioColeccion extends StatelessWidget {
  const _TarjetaServicioColeccion({
    required this.item,
    required this.modoSeleccion,
    required this.seleccionado,
    required this.onToggle,
    required this.onAbrir,
  });

  final HomeCatalogItem item;
  final bool modoSeleccion;
  final bool seleccionado;
  final VoidCallback onToggle;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final servicio = item.localServicio?.servicio;
    final motivo = motivoNoReservableEnLote(item);
    final etiquetaCategoria = [
      if (item.category.nombre.trim().isNotEmpty) item.category.nombre.trim(),
      if (item.subcategoria?.nombre.trim().isNotEmpty ?? false)
        item.subcategoria!.nombre.trim(),
    ].join(' › ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: modoSeleccion ? onToggle : onAbrir,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: seleccionado
                ? AppTheme.primary.withValues(alpha: 0.05)
                : AppTheme.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: seleccionado ? AppTheme.primary : AppTheme.border,
              width: seleccionado ? 1.6 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D2B3A67),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Miniatura(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (etiquetaCategoria.isNotEmpty)
                      Text(
                        etiquetaCategoria,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    if (servicio?.descripcion?.trim().isNotEmpty ?? false) ...[
                      const SizedBox(height: 3),
                      Text(
                        servicio!.descripcion!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    // `Wrap` y no `Row`: valoración y precio comparten una línea
                    // de ~180 px dentro de la tarjeta. Si no caben los dos, el
                    // precio baja de línea en vez de recortarse. Con `Row` +
                    // `Spacer` la fila se desbordaba (lo cazó
                    // `test/coleccion_widgets_test.dart`).
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (item.tieneValoracion)
                          _ValoracionItem(item: item)
                        else
                          _Punto(
                            color: switch (item.estadoHorario) {
                              EstadoHorario.abierto => AppTheme.success,
                              EstadoHorario.cerrado => AppTheme.textSecondary,
                              EstadoHorario.desconocido =>
                                AppTheme.textSecondary,
                            },
                            texto: switch (item.estadoHorario) {
                              EstadoHorario.abierto => 'Abierto ahora',
                              EstadoHorario.cerrado => 'Cerrado ahora',
                              EstadoHorario.desconocido =>
                                'Horario no indicado',
                            },
                          ),
                        _PrecioItem(item: item),
                      ],
                    ),
                    if (motivo != null) ...[
                      const SizedBox(height: 7),
                      _ChipMotivo(motivo: motivo),
                    ],
                    if (!modoSeleccion) ...[
                      const SizedBox(height: 8),
                      // Una sola afordancia, no dos: fuera del modo selección
                      // toda la tarjeta abre la ficha del servicio, y es ahí
                      // donde se reserva solo ese. Dos etiquetas competían por
                      // la misma línea y la fila se desbordaba.
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          const Expanded(
                            child: Text(
                              'Ver detalle y reservar',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: AppTheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (modoSeleccion) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _MarcaSeleccion(
                    seleccionado: seleccionado,
                    bloqueado: motivo != null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Imagen del servicio con el mismo lenguaje visual que el resto del Home.
class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.item});

  final HomeCatalogItem item;

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl?.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 82,
        height: 82,
        child: url != null && url.isNotEmpty
            ? NetImage(
                url: url,
                fit: BoxFit.cover,
                errorWidget: () => const _PlaceholderServicio(),
              )
            : const _PlaceholderServicio(),
      ),
    );
  }
}

class _PlaceholderServicio extends StatelessWidget {
  const _PlaceholderServicio();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.18),
            AppTheme.accent.withValues(alpha: 0.22),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.miscellaneous_services_outlined,
          color: AppTheme.primary.withValues(alpha: 0.5),
          size: 26,
        ),
      ),
    );
  }
}

class _MarcaSeleccion extends StatelessWidget {
  const _MarcaSeleccion({required this.seleccionado, required this.bloqueado});

  final bool seleccionado;
  final bool bloqueado;

  @override
  Widget build(BuildContext context) {
    final color = bloqueado
        ? AppTheme.textSecondary
        : (seleccionado ? AppTheme.primary : AppTheme.border);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: seleccionado && !bloqueado
            ? AppTheme.primary
            : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: seleccionado ? 1.6 : 1.4),
      ),
      child: seleccionado && !bloqueado
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : bloqueado
          ? Icon(Icons.lock_outline_rounded, size: 13, color: color)
          : null,
    );
  }
}

class _ChipMotivo extends StatelessWidget {
  const _ChipMotivo({required this.motivo});

  final String motivo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 12,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 5),
          // `Flexible` + elipsis: el motivo lo escribe la app, pero la tarjeta
          // puede quedarse sin ancho (modo selección). Así se recorta en vez de
          // desbordar la fila.
          Flexible(
            child: Text(
              motivo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9A5B00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Valoración real del servicio en formato compacto: estrellas, promedio y
/// cuántas reseñas lo respaldan. Sin reseñas no se pinta (lo decide la tarjeta).
class _ValoracionItem extends StatelessWidget {
  const _ValoracionItem({required this.item});

  final HomeCatalogItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Estrellas(promedio: item.rating, size: 12),
        const SizedBox(width: 4),
        Text(
          item.rating!.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '(${item.totalResenas})',
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 5),
        Text(
          texto,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Precio base del servicio, con la promoción si la hay.
///
/// Es **de referencia**: el Home no conoce las opciones que elegirá el cliente,
/// y el importe definitivo lo fija el servidor al confirmar. El sufijo "desde"
/// aparece cuando hay promoción o cuando varias unidades cambian el importe.
class _PrecioItem extends StatelessWidget {
  const _PrecioItem({required this.item});

  final HomeCatalogItem item;

  @override
  Widget build(BuildContext context) {
    if (!item.tieneDescuento) {
      final label = precioBaseDe(item.localServicio?.servicio?.configPrecio);
      if (label == null) {
        return const Text(
          'Consultar precio',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        );
      }
      return Text(
        importeCorto(label.precio, label.moneda),
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 13.5,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          importeCorto(item.precioConPromocion!, item.currency),
          style: const TextStyle(
            color: AppTheme.error,
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          importeCorto(item.price!, item.currency),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(icono, size: 36, color: AppTheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (accion != null) ...[const SizedBox(height: 8), accion!],
        ],
      ),
    );
  }
}

/// Esqueleto de carga: mantiene la silueta de las tarjetas reales.
class _CargandoColeccion extends StatelessWidget {
  const _CargandoColeccion();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: AppTheme.border.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final ancho in [0.55, 0.9, 0.35])
                          Container(
                            width: double.infinity,
                            height: 12,
                            margin: const EdgeInsets.only(bottom: 8),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.sizeOf(context).width * ancho,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: ancho * 220,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppTheme.border.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
