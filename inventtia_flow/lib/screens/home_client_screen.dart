import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../config/home_features.dart';
import '../providers/auth_provider.dart';
import '../providers/favoritos_provider.dart';
import '../providers/notificacion_provider.dart';
import '../providers/reservas_provider.dart';
import '../services/campana_service.dart';
import '../services/coleccion_service.dart';
import '../services/fidelidad_service.dart';
import '../services/home_catalog_service.dart';
import '../services/resena_service.dart';
import '../utils/horario_atencion.dart';
import '../widgets/boton_favorito.dart';
import '../widgets/filtros_servicios_sheet.dart';
import '../widgets/home_hero_header.dart';
import '../widgets/net_image.dart';
import '../widgets/notificaciones_bell.dart';
import '../widgets/resenas.dart';
import '../widgets/tarjeta_resena_reciente.dart';
import 'favoritos_screen.dart';
import 'local_servicio_detail_screen.dart';

class HomeClientScreen extends StatefulWidget {
  const HomeClientScreen({
    super.key,
    this.onVerCatalogo,
    this.onPublicarNegocio,
    this.onVerEstablecimiento,
  });

  /// Abre la lista completa de servicios (pestaña Catálogo de `HomeShell`).
  ///
  /// Es `null` cuando la pantalla se monta fuera del shell; en ese caso los
  /// botones que dependen de él caen al aviso informativo de siempre.
  final VoidCallback? onVerCatalogo;

  /// Lleva al perfil, a la sección "Registrar Entidad".
  final VoidCallback? onPublicarNegocio;

  /// Abre la lista de servicios **filtrada por un establecimiento**.
  ///
  /// Tocar una tarjeta de "Establecimientos" debe enseñar todo lo que publica
  /// ese local, no el detalle de su primer servicio. Si es `null` (la pantalla
  /// se usa fuera del shell) se mantiene el comportamiento anterior.
  final void Function(int idLocal, String nombreLocal)? onVerEstablecimiento;

  @override
  State<HomeClientScreen> createState() => HomeClientScreenState();
}

class HomeClientScreenState extends State<HomeClientScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _sponsoredController = PageController(viewportFraction: 0.86);
  final _searchFocusNode = FocusNode();

  Timer? _searchDebounce;
  late final AnimationController _shineController;

  List<HomeCatalogItem> _items = const [];

  /// Muestra completa que devolvió el servidor, ya filtrada por él.
  ///
  /// Se guarda entera para poder pasar de página sin red: el servidor todavía no
  /// trocea (`has_more` llega `false`), así que paginar en memoria sigue siendo
  /// lo correcto y "cargar más" no cuesta una petición.
  List<HomeCatalogItem> _feedItems = const [];

  /// Ranking semanal real (`cliente_ranking_semanal`). Vacío = no se pinta.
  List<HomeCatalogItem> _rankingSemanal = const [];

  List<HomeCatalogCategory> _categories = const [HomeCatalogCategory.todas];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  int _total = 0;
  int _sponsoredPage = 0;
  String _query = '';
  HomeCatalogCategory _category = HomeCatalogCategory.todas;
  String? _provincia;

  /// Filtros del sheet (precio, moneda, provincia, valoración, establecimiento
  /// y "abierto ahora"), aplicados en memoria sobre el catálogo ya cargado.
  FiltrosServicios _filtros = FiltrosServicios.vacio;

  /// Ordena por valoración real (`flow.resena`). Al desactivarlo se vuelve al
  /// orden del catálogo.
  bool _topRated = false;

  /// Últimas reseñas con comentario, para el bloque del Home. Vacío si la
  /// migración `26_resenas.sql` no está aplicada.
  List<Resena> _resenasRecientes = const [];

  /// Campañas patrocinadas vigentes (`flow.campana`), curadas por el superadmin.
  /// Vacío si la migración `28_patrocinados.sql` no está aplicada: en ese caso
  /// la sección no se pinta, en vez de mostrar tarjetas inventadas.
  List<CampanaPatrocinada> _campanas = const [];

  /// Colecciones temáticas vigentes (`flow.coleccion`), curadas por el
  /// superadmin. Vacío si la migración `30_colecciones.sql` no está aplicada: en
  /// ese caso la sección no se pinta.
  List<Coleccion> _colecciones = const [];

  /// Colección seleccionada. `null` = sin filtro. Cuando hay una, el feed se
  /// limita a sus servicios (filtrado en memoria, como la categoría).
  Coleccion? _coleccionActiva;

  /// Programa de fidelidad del usuario: saldo, regla vigente, beneficio de
  /// bienvenida pendiente y últimos movimientos (`flow.cliente_mi_fidelidad`).
  ///
  /// `null` si la migración `31_fidelidad.sql` no está aplicada o no hay sesión.
  /// En ese caso el banner no se pinta, en vez de anunciar un "20 % de descuento"
  /// inventado como hacía antes.
  MiFidelidad? _fidelidad;

  /// Mensaje del último fallo de lectura. `null` cuando el catálogo cargó.
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    // El catálogo y las secciones curadas por el superadmin (categorías,
    // colecciones, patrocinados) llegan juntos en una sola petición desde
    // `_loadPage`. Solo quedan aparte las dos secciones que son del usuario y se
    // refrescan por su cuenta.
    _loadPage(reset: true);
    _cargarRankingSemanal();
    _cargarResenasRecientes();
    _cargarFidelidad();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _sponsoredController.dispose();
    _searchDebounce?.cancel();
    _shineController.dispose();
    super.dispose();
  }

  Future<void> reload() => _refresh();

  Future<void> _refresh() async {
    await HomeCatalogService.clearCache();
    if (!mounted) return;
    await _loadPage(reset: true);
    await _cargarRankingSemanal();
    await _cargarResenasRecientes();
    await _cargarFidelidad();
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_isLoadingMore && !reset) return;
    if (!reset && !_hasMore) return;
    if (reset) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _page = 1;
        _items = const [];
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      HomeFeed? feed;
      if (reset) {
        // UNA petición: el catálogo ya filtrado por el servidor (búsqueda,
        // categoría, provincia, colección y orden) más las categorías, las
        // colecciones, los patrocinados y los contadores del usuario.
        feed = await HomeCatalogService.fetchFeed(
          query: _query,
          category: _category,
          provincia: _provincia,
          idColeccion: _coleccionActiva?.id,
          topRated: _topRated,
        );
        if (!mounted) return;
        _feedItems = feed.items;
      }

      // En el cliente solo queda el filtro de horario (a propósito: ver
      // `HomeCatalogService.paginar`) y el troceado en páginas. Los filtros del
      // sheet se aplican aquí, en memoria, sobre el catálogo que el servidor ya
      // acotó por búsqueda, categoría, provincia y colección.
      final catalogo = _filtros.hayAlgo
          ? _feedItems.where(_pasaFiltros).toList()
          : _feedItems;

      final page = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: reset ? 1 : _page + 1,
        onlyOpen: _filtros.soloAbiertos,
      );

      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _page = page.page;
        _hasMore = page.hasMore;
        _total = page.total;
        _error = null;
        _isLoading = false;
        _isLoadingMore = false;
      });

      // Las secciones van después de pintar el catálogo: no retrasan la primera
      // tarjeta, y `_aplicarColecciones` puede pedir una recarga si la colección
      // activa desapareció.
      if (feed != null) {
        _aplicarCategorias(feed.categorias);
        _aplicarColecciones(feed.colecciones);
        _aplicarCampanas(feed.patrocinados);
        _sembrarContadores(feed.contadores);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = false;
        _error = 'No pudimos leer el catálogo. Revisa tu conexión.';
      });
      debugPrint('[flow] HomeClientScreen._loadPage ERROR: $e');
    }
  }

  /// Aplica en memoria los filtros del sheet sobre el catálogo cargado.
  ///
  /// "Abierto ahora" se recalcula con el reloj actual (igual que hace
  /// `paginar`) para que un feed cargado hace horas no decida con datos viejos.
  /// Admite unos [filtros] distintos de los aplicados para que el sheet pueda
  /// previsualizar su borrador sin tocar el estado real.
  bool _pasaFiltros(HomeCatalogItem item, [FiltrosServicios? filtros]) {
    final f = filtros ?? _filtros;
    final abierto = f.soloAbiertos
        ? HorarioAtencion.parseConDetalle(
                item.horarioTexto,
                item.horarioDetalle,
              ).evaluar(DateTime.now()) ==
              EstadoHorario.abierto
        : null;

    return f.coincide(
      precioItem: item.price,
      monedaItem: item.currency,
      provinciaItem: item.provincia,
      ratingItem: item.totalResenas > 0 ? item.rating : null,
      idLocalItem: item.localServicio?.idLocal ?? item.localServicio?.local?.id,
      abiertoItem: abierto,
    );
  }

  /// Opciones reales del sheet de filtros, deducidas del catálogo cargado.
  OpcionesFiltros _opcionesFiltros() {
    final precios = <OfertaPrecio>[];
    final provincias = <String>{};
    final locales = <int, LocalOpcion>{};
    var hayValoraciones = false;

    for (final item in _feedItems) {
      if (item.price != null && (item.currency ?? '').isNotEmpty) {
        precios.add(OfertaPrecio(precio: item.price!, moneda: item.currency!));
      }

      final provincia = item.provincia?.trim();
      if ((provincia ?? '').isNotEmpty) provincias.add(provincia!);

      final localServicio = item.localServicio;
      final idLocal = localServicio?.idLocal ?? localServicio?.local?.id;
      if (idLocal != null && item.venue.trim().isNotEmpty) {
        locales.putIfAbsent(
          idLocal,
          () => LocalOpcion(
            id: idLocal,
            nombre: item.venue.trim(),
            provincia: (provincia ?? '').isEmpty ? null : provincia,
          ),
        );
      }

      if (item.totalResenas > 0) hayValoraciones = true;
    }

    final listaProvincias = provincias.toList()..sort();
    final listaLocales = locales.values.toList()
      ..sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

    return OpcionesFiltros(
      precios: precios,
      provincias: listaProvincias,
      locales: listaLocales,
      hayValoraciones: hayValoraciones,
    );
  }

  /// Abre el sheet de filtros y recarga el feed con lo elegido.
  Future<void> _abrirFiltros() async {
    final elegidos = await mostrarFiltrosServicios(
      context,
      actual: _filtros,
      opciones: _opcionesFiltros(),
      // Sin catálogo cargado todavía no hay nada que contar: es mejor dejar el
      // botón en "Aplicar filtros" que desactivarlo con un 0 engañoso.
      contador: _feedItems.isEmpty
          ? null
          : (borrador) =>
                _feedItems.where((item) => _pasaFiltros(item, borrador)).length,
    );

    if (elegidos == null || !mounted) return;
    setState(() => _filtros = elegidos);
    // Sin petición nueva: el servidor ya trajo el catálogo completo y los
    // filtros se aplican en memoria.
    _loadPage(reset: true);

    if (elegidos.hayAlgo) {
      _showToast('Filtros aplicados a tu exploración.');
    }
  }

  /// Tocar un establecimiento abre la lista de servicios **de ese local**.
  ///
  /// Antes abría el detalle del primer servicio que hubiera devuelto el feed,
  /// que no es lo que el cliente pidió al tocar el local.
  void _abrirEstablecimiento(HomeCatalogItem item) {
    final idLocal =
        item.localServicio?.idLocal ?? item.localServicio?.local?.id;
    final callback = widget.onVerEstablecimiento;
    if (callback != null && idLocal != null) {
      callback(idLocal, item.venue);
      return;
    }
    // Fuera del shell (o sin id resoluble) se conserva el comportamiento previo.
    _openItem(item);
  }

  /// Deja los contadores del feed como snapshot inicial de los badges.
  ///
  /// Es solo para el arranque en frío: cada provider ignora la semilla si ya
  /// tiene su propio dato, así que el badge no aparece vacío durante el primer
  /// segundo y **nunca** puede contradecir a su lista.
  void _sembrarContadores(HomeContadores contadores) {
    if (!mounted) return;
    context.read<NotificacionProvider>().sembrarNoLeidas(
      contadores.notificaciones,
    );
    context.read<ReservasProvider>().sembrarPendientes(contadores.reservas);
  }

  /// Aplica el nomenclador que vino dentro del feed.
  ///
  /// "Todas" no se comprueba como las demás: no es una categoría real (su `id`
  /// es `null`), así que nunca "desaparece" y no puede provocar un ciclo. Si la
  /// categoría seleccionada sí desapareció (el superadmin la apagó), se quita el
  /// filtro **y se relee**, porque ahora es el servidor quien filtra: la muestra
  /// guardada correspondería a la categoría anterior.
  void _aplicarCategorias(List<HomeCatalogCategory> categorias) {
    if (!mounted) return;
    final activa = _category;
    final desaparecio =
        !activa.esTodas && !categorias.any((c) => c.id == activa.id);

    setState(() {
      _categories = categorias;
      if (desaparecio) _category = HomeCatalogCategory.todas;
    });

    if (desaparecio) _loadPage(reset: true);
  }

  /// Ranking semanal real: lugares reservados en la semana en curso.
  ///
  /// Si la migración 36 no está aplicada, o no hay reservas esta semana, deja la
  /// lista vacía y el bloque no se pinta. Antes esta sección mostraba
  /// `_items.take(3)` con posiciones 1-2-3 que no significaban nada.
  Future<void> _cargarRankingSemanal() async {
    if (!HomeFeatures.rankingSemanal) return;
    try {
      final ranking = await HomeCatalogService.fetchRankingSemanal();
      if (!mounted) return;
      setState(() => _rankingSemanal = ranking);
    } catch (e) {
      debugPrint('[flow] HomeClientScreen._cargarRankingSemanal ERROR: $e');
    }
  }

  /// Últimas reseñas con comentario. Si el RPC no existe todavía, deja la lista
  /// vacía y el bloque no se pinta.
  Future<void> _cargarResenasRecientes() async {
    if (!HomeFeatures.resenas) return;
    try {
      final resenas = await ResenaService.recientes(limit: 6);
      if (!mounted) return;
      setState(() => _resenasRecientes = resenas);
    } catch (_) {
      if (!mounted) return;
      setState(() => _resenasRecientes = const []);
    }
  }

  /// Aplica las campañas patrocinadas que vinieron dentro del feed.
  ///
  /// El servidor ya las devuelve vigentes y ordenadas por prioridad, así que
  /// aquí solo queda recolocar el carrusel si el superadmin quitó campañas y la
  /// página actual quedó fuera de rango.
  void _aplicarCampanas(List<CampanaPatrocinada> campanas) {
    if (!mounted || !HomeFeatures.patrocinados) return;
    final fueraDeRango = _sponsoredPage >= campanas.length;
    setState(() {
      _campanas = campanas;
      if (fueraDeRango) _sponsoredPage = 0;
    });
    // El `PageController` es persistente: si el superadmin quitó campañas y la
    // página actual quedó fuera de rango, hay que devolverlo al inicio o el
    // carrusel arranca en una posición que ya no existe.
    if (fueraDeRango && campanas.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_sponsoredController.hasClients) return;
        _sponsoredController.jumpToPage(0);
      });
    }
  }

  /// Aplica las colecciones temáticas que vinieron dentro del feed.
  ///
  /// Si la colección seleccionada desapareció (el superadmin la apagó o le quitó
  /// todos los servicios), se quita el filtro **y se relee** para no dejar el
  /// feed vacío sin explicación.
  void _aplicarColecciones(List<Coleccion> colecciones) {
    if (!mounted || !HomeFeatures.colecciones) return;

    final activa = _coleccionActiva;
    final sigueExistiendo =
        activa != null && colecciones.any((c) => c.id == activa.id);

    setState(() {
      _colecciones = colecciones;
      if (!sigueExistiendo) _coleccionActiva = null;
    });

    if (activa != null && !sigueExistiendo) {
      // El filtro ya no aplica: releer para que el feed vuelva a estar completo.
      _loadPage(reset: true);
    }
  }

  /// Saldo y movimientos de puntos, y el beneficio de bienvenida pendiente.
  ///
  /// Silencioso a propósito: si la migración no está aplicada el servicio
  /// devuelve `null` y el banner simplemente no aparece. Un fallo de la fidelidad
  /// nunca debe romper el Home ni impedir reservar.
  Future<void> _cargarFidelidad() async {
    if (!HomeFeatures.fidelidad) return;
    final fidelidad = await FidelidadService.miFidelidad();
    if (!mounted) return;
    setState(() => _fidelidad = fidelidad);
  }

  /// Filtra el feed por una colección. Tocar la que ya está activa la quita.
  void _selectColeccion(Coleccion coleccion) {
    if (_coleccionActiva?.id == coleccion.id) {
      _limpiarColeccion();
      return;
    }
    setState(() => _coleccionActiva = coleccion);
    _loadPage(reset: true);
    _showToast('Mostrando ${coleccion.titulo}.');
  }

  void _limpiarColeccion() {
    if (_coleccionActiva == null) return;
    setState(() => _coleccionActiva = null);
    _loadPage(reset: true);
  }

  /// Degradado de la tarjeta a partir de los colores que fijó el superadmin.
  ///
  /// Si un color no es un `#RRGGBB` válido se cae al degradado por defecto en
  /// vez de romper el pintado: el campo lo escribe una persona en un formulario.
  List<Color> _degradadoDe(Coleccion coleccion) {
    final inicio = _colorHex(coleccion.colorInicio);
    final fin = _colorHex(coleccion.colorFin);
    if (inicio == null && fin == null) {
      return const [Color(0xFF2C3654), Color(0xFF1FA8B8)];
    }
    return [inicio ?? fin!, fin ?? inicio!];
  }

  static Color? _colorHex(String? valor) {
    final v = valor?.trim().replaceFirst('#', '');
    if (v == null || v.length != 6) return null;
    final n = int.tryParse(v, radix: 16);
    if (n == null) return null;
    return Color(0xFF000000 | n);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || _isLoadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 520) {
      _loadPage();
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() => _query = value);
      _loadPage(reset: true);
    });
  }

  void _selectCategory(HomeCatalogCategory category) {
    if (_category.id == category.id) return;
    setState(() => _category = category);
    _loadPage(reset: true);
  }

  void _selectProvincia(String? provincia) {
    if (_provincia == provincia) return;
    setState(() => _provincia = provincia);
    _loadPage(reset: true);
  }

  /// Alterna el favorito desde el Home.
  ///
  /// El estado y el aviso los gestiona `alternarFavorito` (widgets/boton_favorito),
  /// para que Home, catálogo y detalle se comporten igual. La tarjeta recibe
  /// `saved` ya resuelto porque se repinta con el resto de la lista.
  Future<void> _toggleFavorito(HomeCatalogItem item) async {
    await alternarFavorito(
      context,
      idLocalServicio: item.id,
      titulo: item.title,
    );
  }

  void _openItem(HomeCatalogItem item) {
    final localServicio = item.localServicio;
    if (localServicio == null) {
      // No debería ocurrir: las tarjetas siempre salen de `local_servicio`.
      _showToast('No pudimos abrir este servicio.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalServicioDetailScreen(localServicio: localServicio),
      ),
    );
  }

  void _showToast(String message, {String? actionLabel}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: AppTheme.accent,
                  onPressed: () {
                    if (actionLabel == 'Reintentar') {
                      _refresh();
                    } else if (actionLabel == 'Ver favoritos') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FavoritosScreen(),
                        ),
                      );
                    }
                  },
                ),
        ),
      );
  }

  /// Provincias disponibles, deducidas de `flow.app_dat_locales.provincia`
  /// de los locales que ya están en el catálogo cargado.
  List<String> get _provinciasDisponibles {
    final valores = <String>{};
    for (final item in _items) {
      final provincia = item.provincia;
      if (provincia != null && provincia.trim().isNotEmpty) {
        valores.add(provincia.trim());
      }
    }
    final lista = valores.toList()..sort();
    return lista;
  }

  String get _etiquetaUbicacion => _provincia ?? 'Todas las provincias';

  Future<void> _showLocationPicker() async {
    final provincias = _provinciasDisponibles;
    if (provincias.isEmpty) {
      _showToast('Todavía no hay locales con provincia configurada.');
      return;
    }
    // `null` = sin filtro de ubicación; se usa '' porque showModalBottomSheet
    // devuelve null también al cerrar sin elegir.
    final seleccion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Elige tu ubicación', style: _SectionTitleStyle()),
              const SizedBox(height: 6),
              const Text(
                'Filtramos por la provincia que el local tiene registrada.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              _OpcionUbicacion(
                titulo: 'Todas las provincias',
                icono: Icons.public_rounded,
                seleccionada: _provincia == null,
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
              ...provincias.map(
                (provincia) => _OpcionUbicacion(
                  titulo: provincia,
                  icono: Icons.location_on_outlined,
                  seleccionada: _provincia == provincia,
                  onTap: () => Navigator.pop(sheetContext, provincia),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (seleccion == null || !mounted) return;
    _selectProvincia(seleccion.isEmpty ? null : seleccion);
    _showToast('Ubicación actualizada.');
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().perfil;
    final firstName = profile?.nombre.trim().isNotEmpty == true
        ? profile!.nombre.trim().split(' ').first
        : 'María';

    // `watch` para que los corazones se repinten al alternar un favorito.
    final favoritos = context.watch<FavoritosProvider>();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: HomeHeroHeader(
                topBar: _buildTopBar(firstName),
                searchCard: _buildSearchHero(),
              ),
            ),
            SliverToBoxAdapter(child: _buildCategories()),
            // Secciones apagadas: su respaldo no existe todavía ni en la base
            // de datos ni en la administración. `lib/config/home_features.dart`
            // documenta qué falta para encender cada una.
            if (HomeFeatures.colecciones)
              SliverToBoxAdapter(child: _buildCollections()),
            if (HomeFeatures.patrocinados)
              SliverToBoxAdapter(child: _buildSponsoredCarousel()),
            if (HomeFeatures.ofertasRelampago)
              SliverToBoxAdapter(child: _buildFlashOffers()),
            SliverToBoxAdapter(child: _buildRecommended(favoritos)),
            SliverToBoxAdapter(child: _buildPopularPlaces()),
            if (HomeFeatures.rankingSemanal)
              SliverToBoxAdapter(child: _buildWeeklyPopular()),
            if (HomeFeatures.resenas)
              SliverToBoxAdapter(child: _buildResenasRecientes()),
            if (HomeFeatures.fidelidad)
              SliverToBoxAdapter(child: _buildLoyaltyBanner()),
            SliverToBoxAdapter(child: _buildHowItWorks()),
            SliverToBoxAdapter(child: _buildFeedHeader()),
            if (_isLoading && _items.isEmpty)
              const SliverToBoxAdapter(child: _LoadingBlock()),
            if (!_isLoading && _items.isEmpty)
              SliverToBoxAdapter(child: _buildNoResults()),
            if (_items.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate((_, index) {
                  final item = _items[index];
                  return _FeedServiceCard(
                    item: item,
                    saved: favoritos.estaGuardado(item.id),
                    onTap: () => _openItem(item),
                    onSave: () => _toggleFavorito(item),
                  );
                }, childCount: _items.length),
              ),
            if (_isLoadingMore)
              const SliverToBoxAdapter(child: _LoadingMoreBlock()),
            SliverToBoxAdapter(child: _buildFooter()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(String firstName) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C3654), Color(0xFF3E4E80)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXPLORA',
                          style: TextStyle(
                            color: AppTheme.accent.withValues(alpha: 0.95),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        // El nombre lo escribe la persona: puede ser largo. Con
                        // `FittedBox` el texto se reduce solo lo necesario para
                        // caber en una línea, en vez de partirse en dos y empujar
                        // el resto de la cabecera hacia abajo.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Hola, $firstName 👋',
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Encuentra tu próximo servicio sin filas.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const NotificacionesBell(color: Colors.white),
                  const SizedBox(width: 8),
                  _StatusAvatar(
                    initial: firstName.substring(0, 1).toUpperCase(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _showLocationPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _etiquetaUbicacion,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHero() {
    // La cabecera pinta el fondo índigo detrás de los primeros 26 px de la
    // tarjeta. Todo el buscador queda dentro del área del mismo sliver.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2B3A67),
              blurRadius: 22,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar servicio, local o categoría…',
                  hintStyle: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.primary,
                    size: 21,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (HomeFeatures.busquedaPorVoz)
                        IconButton(
                          tooltip: 'Buscar por voz',
                          onPressed: () => _showToast(
                            'La búsqueda por voz estará disponible pronto.',
                          ),
                          icon: const Icon(
                            Icons.mic_none_rounded,
                            color: AppTheme.textSecondary,
                            size: 20,
                          ),
                        ),
                      if (HomeFeatures.busquedaPorVoz)
                        Container(width: 1, height: 20, color: AppTheme.border),
                      IconButton(
                        tooltip: 'Filtros avanzados',
                        onPressed: _abrirFiltros,
                        // Mismo lenguaje que el buscador del catálogo: con
                        // filtros puestos, el botón lo dice.
                        icon: _filtros.activos > 0
                            ? Badge.count(
                                count: _filtros.activos,
                                backgroundColor: AppTheme.accent,
                                child: const Icon(
                                  Icons.tune_rounded,
                                  color: AppTheme.primary,
                                  size: 20,
                                ),
                              )
                            : const Icon(
                                Icons.tune_rounded,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 9),
            SizedBox(
              height: 28,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  // "Cerca de mí" y "Mejor valorados" solo aparecen cuando hay
                  // coordenadas y reseñas. Ver `lib/config/home_features.dart`.
                  if (HomeFeatures.distancia)
                    _QuickChip(
                      label: 'Cerca de mí',
                      icon: Icons.location_on_outlined,
                      selected: false,
                      onTap: () => _showToast(
                        'Necesitamos coordenadas de los locales para calcular '
                        'distancias.',
                      ),
                    ),
                  _QuickChip(
                    label: 'Abierto ahora',
                    live: true,
                    selected: _filtros.soloAbiertos,
                    onTap: () {
                      setState(
                        () => _filtros = _filtros.copyWith(
                          soloAbiertos: !_filtros.soloAbiertos,
                        ),
                      );
                      _loadPage(reset: true);
                    },
                  ),
                  if (HomeFeatures.mejorValorados)
                    _QuickChip(
                      label: 'Mejor valorados',
                      icon: Icons.star_rounded,
                      selected: _topRated,
                      onTap: () {
                        setState(() => _topRated = !_topRated);
                        _loadPage(reset: true);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Categorías principales', trailing: 'Desliza →'),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final category = _categories[index];
                final selected = category.id == _category.id;
                return GestureDetector(
                  onTap: () => _selectCategory(category),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: selected ? AppTheme.primary : AppTheme.border,
                      ),
                      boxShadow: selected
                          ? const []
                          : const [
                              BoxShadow(
                                color: Color(0x0D2B3A67),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _iconoCategoria(category),
                          color: selected ? AppTheme.accent : AppTheme.primary,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          category.nombre,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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

  /// Colecciones temáticas reales (`flow.coleccion`), curadas por el superadmin.
  ///
  /// Antes eran cuatro tarjetas inventadas ("Pack Novia", "Self-care Sunday",
  /// "Ruta & Transporte", "Ofertas del día") con recuentos, emojis y colores que
  /// no respaldaba ninguna tabla, y el toque no abría la colección: llevaba a la
  /// categoría "más cercana" y avisaba con un toast. Ahora, si el superadmin no
  /// ha curado ninguna, la sección **no se pinta**.
  Widget _buildCollections() {
    if (!HomeFeatures.colecciones || _colecciones.isEmpty) {
      return const SizedBox.shrink();
    }
    final colecciones = _colecciones;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sin "Explorar": no hay una pantalla de colecciones a la que ir; la
          // tarjeta filtra el propio feed.
          _sectionHeading('Colecciones destacadas'),
          const SizedBox(height: 4),
          const Text(
            'Experiencias curadas para ti',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 11),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: colecciones.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 112,
            ),
            itemBuilder: (_, index) {
              final coleccion = colecciones[index];
              final icono = coleccion.icono?.trim() ?? '';
              return _CollectionCard(
                collection: _Collection(
                  coleccion.titulo,
                  coleccion.subtituloORecuento,
                  icono.isNotEmpty ? icono : '✨',
                  _degradadoDe(coleccion),
                ),
                seleccionada: _coleccionActiva?.id == coleccion.id,
                onTap: () => _selectColeccion(coleccion),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Carrusel de espacio patrocinado: SOLO campañas reales de `flow.campana`.
  ///
  /// Antes pintaba tres tarjetas inventadas ("Luna Studio", "Casa Aura",
  /// "Moverte") con la etiqueta "Verificado", que nadie podía configurar ni
  /// respaldaba dato alguno. Ahora las crea el superadmin desde
  /// `ventiq_superadmin` y, si no hay ninguna campaña vigente, **la sección no
  /// se pinta**.
  Widget _buildSponsoredCarousel() {
    if (!HomeFeatures.patrocinados || _campanas.isEmpty) {
      return const SizedBox.shrink();
    }
    final campanas = _campanas;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sin "Ver todo": no existe una pantalla de patrocinados a la que ir.
          _sectionHeading('Espacio patrocinado'),
          const SizedBox(height: 10),
          SizedBox(
            height: 166,
            child: PageView.builder(
              controller: _sponsoredController,
              itemCount: campanas.length,
              onPageChanged: (index) => setState(() => _sponsoredPage = index),
              itemBuilder: (_, index) {
                final campana = campanas[index];
                return Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 16 : 5,
                    right: index == campanas.length - 1 ? 16 : 5,
                  ),
                  child: _SponsoredCard(
                    sponsored: _Sponsored.deCampana(campana),
                    onTap: () => _abrirCampana(campana),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              campanas.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: index == _sponsoredPage ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: index == _sponsoredPage
                      ? AppTheme.primary
                      : AppTheme.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre el servicio destacado por una campaña.
  ///
  /// La campaña puede apuntar a un servicio que no esté en la página cargada,
  /// así que se busca en el catálogo completo (ya cacheado) en vez de solo en
  /// `_items`. Una campaña de entidad no tiene servicio que abrir: en ese caso
  /// se indica al cliente en vez de no hacer nada.
  Future<void> _abrirCampana(CampanaPatrocinada campana) async {
    final idLocalServicio = campana.idLocalServicio;
    if (idLocalServicio == null) {
      _showToast(
        campana.entidad == null
            ? 'Esta campaña no tiene un servicio asociado.'
            : 'Explora los servicios de ${campana.entidad}.',
      );
      return;
    }

    HomeCatalogItem? item;
    for (final candidato in _items) {
      if (candidato.id == idLocalServicio) {
        item = candidato;
        break;
      }
    }
    item ??= await HomeCatalogService.itemPorId(idLocalServicio);
    if (!mounted) return;
    if (item == null) {
      _showToast('Ese servicio ya no está disponible.');
      return;
    }
    _openItem(item);
  }

  /// Sección de ofertas: SOLO servicios con promoción vigente real.
  ///
  /// Antes comparaba `item.discount > 0` sobre un campo inventado y, si no había
  /// ofertas, pintaba dos tarjetas de negocios que no existen ("Alma Spa",
  /// "Luna Studio") con "-20 %" y "3 cupos" falsos. Ahora se apoya en
  /// `flow.promocion` y, si no hay ninguna promo, **la sección no se pinta**.
  ///
  /// No hay contador de cuenta regresiva: un "termina en 4:12:39" fijo no
  /// significa nada. La vigencia real se muestra en el detalle ("Vigente hasta
  /// dd/mm"), que sale de `promocion.hasta`.
  Widget _buildFlashOffers() {
    final ofertas = _items.where((i) => i.tieneDescuento).toList();
    if (ofertas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Ofertas vigentes'),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Servicios con descuento activo',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 186,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: ofertas.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) => _FlashOfferCard(
                item: ofertas[index],
                onTap: () => _openItem(ofertas[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommended(FavoritosProvider favoritos) {
    final recomendaciones = _items.take(6).toList();
    // Sin servicios no se deja un cargador girando para siempre: o se está
    // cargando de verdad, o la sección desaparece (el estado vacío lo explica
    // el bloque principal de la pantalla).
    if (recomendaciones.isEmpty && !_isLoading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            'Servicios disponibles',
            trailing: 'Ver todo',
            // "Ver todo" abre la lista completa del catálogo.
            onTrailingTap: widget.onVerCatalogo,
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Todo el catálogo publicado por los locales',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 224,
            child: recomendaciones.isEmpty
                ? const _HorizontalLoading()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: recomendaciones.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, index) {
                      final item = recomendaciones[index];
                      return _RecommendedCard(
                        item: item,
                        saved: favoritos.estaGuardado(item.id),
                        onTap: () => _openItem(item),
                        onSave: () => _toggleFavorito(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularPlaces() {
    final locales = <String, HomeCatalogItem>{};
    for (final item in _items) {
      locales.putIfAbsent(item.venue, () => item);
    }
    final values = locales.values.take(4).toList();
    // Igual que en "Servicios disponibles": sin locales no se gira en vano.
    if (values.isEmpty && !_isLoading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Establecimientos', trailing: 'Ver todos'),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Locales con servicios publicados',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            // Alto suficiente para imagen, nombre, ubicación, estado, chips y
            // botón: antes 270 px dejaban "Ver servicios" fuera de la tarjeta
            // en los locales con más datos.
            height: 330,
            child: values.isEmpty
                ? const _HorizontalLoading()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: values.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, index) => _PopularPlaceCard(
                      item: values[index],
                      // La tarjeta y su botón "Ver servicios" abren la lista de
                      // servicios del local, no su primer servicio.
                      onTap: () => _abrirEstablecimiento(values[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyPopular() {
    // Sin reservas esta semana el bloque no existe: no se rellena con el orden
    // del catálogo, que no significaría nada.
    if (_rankingSemanal.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(
            'Servicios populares de la semana',
            trailing: 'Ranking',
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Lugares reservados esta semana (lunes a hoy)',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: _cardDecoration(),
              child: Column(
                children: List.generate(
                  _rankingSemanal.length,
                  (index) => _WeeklyServiceRow(
                    rank: index + 1,
                    item: _rankingSemanal[index],
                    onTap: () => _openItem(_rankingSemanal[index]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Reseñas recientes reales de `flow.resena`.
  ///
  /// Sustituye a la antigua "Reseña del día", que traía texto, autor y 5
  /// estrellas fijos ("Llegué, reservé y me atendieron a la hora exacta" —
  /// Ana R. · Luna Studio), un negocio que ni existe en la base.
  ///
  /// Se alimenta de `resenas_recientes`, que solo devuelve reseñas **con
  /// comentario**: una fila de "5 estrellas" sin texto no aporta nada aquí. Si
  /// no hay ninguna, el bloque no se pinta.
  Widget _buildResenasRecientes() {
    if (_resenasRecientes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Lo que dicen los clientes'),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Reseñas de servicios ya atendidos',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 178,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _resenasRecientes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 11),
              itemBuilder: (_, index) => TarjetaResenaReciente(
                resena: _resenasRecientes[index],
                onTap: () {
                  final id = _resenasRecientes[index].idLocalServicio;
                  if (id == null) return;
                  // El detalle necesita el LocalServicio completo: se toma del
                  // feed si está cargado, y si no se avisa en vez de fallar.
                  final item = _items.where((i) => i.id == id).firstOrNull;
                  if (item == null) {
                    _showToast('Desliza para encontrar ese servicio.');
                    return;
                  }
                  _openItem(item);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoyaltyBanner() {
    final f = _fidelidad;

    // Sin migración 31, sin sesión o sin regla configurada no hay nada honesto
    // que contar: la sección no se pinta. Antes este banner anunciaba un "20 %
    // de descuento" que no existía en ninguna tabla.
    if (f == null || !f.hayAlgoQueMostrar) return const SizedBox.shrink();

    // El beneficio solo se anuncia si ya está encendida la migración que lo
    // aplica al precio; si no, estaríamos prometiendo un descuento que no se
    // cobra. `beneficio` es local y nullable, así que el `!= null` sí promueve.
    final beneficio = HomeFeatures.beneficioBienvenida ? f.beneficio : null;
    final mostrarBeneficio = beneficio != null;

    final titulo = beneficio != null
        ? beneficio.titulo.toUpperCase()
        : 'TU FIDELIDAD';

    // Puntos reales del libro de movimientos, o el descuento del beneficio.
    final destacado = beneficio != null ? beneficio.etiqueta : f.etiquetaPuntos;

    final detalleBeneficio = beneficio?.descripcion?.trim();
    final detalle = beneficio != null
        ? ((detalleBeneficio != null && detalleBeneficio.isNotEmpty)
              ? detalleBeneficio
              : 'Se aplica en tu próxima reserva.')
        : f.regla!.explicacion;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Container(
          height: 142,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C3654), Color(0xFF1FA8B8)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -24,
                top: -28,
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 150,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              AnimatedBuilder(
                animation: _shineController,
                builder: (_, __) => Positioned(
                  left: -80 + (_shineController.value * 420),
                  top: -30,
                  bottom: -30,
                  width: 62,
                  child: Transform.rotate(
                    angle: -0.25,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 10,
                              letterSpacing: 1.3,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            destacado,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detalle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 32,
                            child: FilledButton(
                              onPressed: mostrarBeneficio
                                  ? () => _showToast(
                                      'Se aplica solo en tu próxima reserva.',
                                    )
                                  : _mostrarMovimientos,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              child: Text(
                                mostrarBeneficio
                                    ? 'Cómo funciona'
                                    : 'Mis movimientos',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '✦',
                      style: TextStyle(fontSize: 44, color: Colors.white),
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

  /// Libro de puntos del cliente: de dónde vino cada punto y cuándo caduca.
  ///
  /// Es la parte de **auditoría** del programa y responde a "¿por qué tengo estos
  /// puntos?". El saldo del banner es literalmente la suma de esta lista, así que
  /// no pueden discrepar.
  void _mostrarMovimientos() {
    final f = _fidelidad;
    if (f == null) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final movs = f.movimientos;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.etiquetaPuntos,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (f.regla != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      f.regla!.explicacion,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (f.regla?.etiquetaVigencia != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      f.regla!.etiquetaVigencia!,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const Divider(height: 24),
                if (movs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Todavía no tienes movimientos. Aquí aparecerán los puntos '
                      'que ganes al completar tus reservas.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: movs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final m = movs[i];
                        final suma = m.puntos >= 0;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            suma
                                ? Icons.add_circle_outline
                                : Icons.remove_circle_outline,
                            color: suma ? AppTheme.primary : Colors.black38,
                          ),
                          title: Text(
                            (m.motivo?.trim().isNotEmpty ?? false)
                                ? m.motivo!.trim()
                                : m.etiquetaTipo,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            m.vencido
                                ? '${m.etiquetaTipo} · caducados'
                                : m.etiquetaTipo,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            m.etiquetaPuntos,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: suma ? AppTheme.primary : Colors.black38,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHowItWorks() {
    const steps = [
      _HowStep(
        '1',
        'Elige',
        'Descubre un servicio cerca de ti.',
        Icons.search_rounded,
      ),
      _HowStep(
        '2',
        'Reserva',
        'Selecciona el horario que prefieras.',
        Icons.event_available_outlined,
      ),
      _HowStep(
        '3',
        'Llega sin filas',
        'Te atendemos cuando corresponde.',
        Icons.directions_walk_outlined,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading('Cómo funciona', trailing: null),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: steps
                .map((step) => Expanded(child: _HowStepCard(step: step)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedHeader() {
    final activa = _coleccionActiva;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // Con una colección activa el título cambia: "Más servicios
                  // para ti" describiría mal una lista curada y filtrada.
                  activa == null ? 'Más servicios para ti' : activa.titulo,
                  style: const _SectionTitleStyle(),
                ),
              ),
              if (_items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _total == 1 ? '1 servicio' : '$_total servicios',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (activa != null) ...[
            const SizedBox(height: 8),
            _buildColeccionActivaChip(activa),
          ],
        ],
      ),
    );
  }

  /// Aviso de que el feed está limitado a una colección, con botón para quitar
  /// el filtro. Sin esto el cliente vería menos servicios de los normales sin
  /// saber por qué.
  Widget _buildColeccionActivaChip(Coleccion coleccion) {
    final icono = coleccion.icono?.trim() ?? '';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icono.isNotEmpty) ...[
                Text(icono, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
              ],
              Text(
                'Colección · ${coleccion.titulo}',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _limpiarColeccion,
          child: const Text(
            'Quitar filtro',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoResults() {
    final hayError = _error != null;

    // Cuando hay una categoría (o una búsqueda) activa se dice **qué** no tiene
    // servicios: "No encontramos resultados" a secas deja al usuario pensando
    // que la app se quedó cargando.
    final categoria = _category.esTodas ? null : _category.nombre;
    final conFiltros = _filtros.hayAlgo;
    final titulo = hayError
        ? 'No pudimos cargar el catálogo'
        : conFiltros
        ? 'Ningún servicio con estos filtros'
        : categoria != null
        ? 'Sin servicios en «$categoria»'
        : 'No encontramos resultados';

    final detalle = hayError
        ? (_error ?? '')
        : conFiltros
        ? 'Ninguno de los servicios publicados cumple lo que pediste. '
              'Quita algún filtro para ampliar la búsqueda.'
        : categoria != null
        ? 'Todavía no hay servicios publicados en esta categoría. '
              'Prueba con otra o quita los filtros.'
        : 'Prueba otra categoría o cambia la búsqueda.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: _cardDecoration(),
        child: Column(
          children: [
            Icon(
              hayError
                  ? Icons.cloud_off_rounded
                  : conFiltros
                  ? Icons.filter_alt_off_rounded
                  : categoria != null
                  ? Icons.category_outlined
                  : Icons.search_off_rounded,
              size: 42,
              color: AppTheme.primary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 10),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 5),
            Text(
              detalle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            if (hayError)
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
              )
            else
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _category = HomeCatalogCategory.todas;
                    _provincia = null;
                    _filtros = FiltrosServicios.vacio;
                  });
                  _loadPage(reset: true);
                },
                child: const Text('Limpiar filtros'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 112),
      child: Column(
        children: [
          const Divider(color: AppTheme.border),
          const SizedBox(height: 13),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '¿Tienes un negocio?',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
              TextButton.icon(
                // Publicar un negocio se hace desde el perfil: el botón lleva
                // directo a "Registrar Entidad".
                onPressed:
                    widget.onPublicarNegocio ??
                    () => _showToast('Te ayudaremos a publicar tu negocio.'),
                icon: const Icon(Icons.storefront_outlined, size: 16),
                label: const Text('Publica tu negocio'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Explora con confianza · Reserva cuando quieras',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeading(
    String title, {
    String? trailing,
    VoidCallback? onTrailingTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const _SectionTitleStyle())),
          if (trailing != null)
            TextButton(
              // Sin destino real, el botón sigue avisando ("Desliza…") en vez de
              // fingir una navegación que no existe.
              onPressed:
                  onTrailingTap ??
                  () => _showToast('Desliza para ver más opciones.'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                trailing,
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: AppTheme.border),
    boxShadow: const [
      BoxShadow(color: Color(0x0D2B3A67), blurRadius: 12, offset: Offset(0, 5)),
    ],
  );
}

class _StatusAvatar extends StatelessWidget {
  final String initial;
  const _StatusAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accent,
          ),
          child: CircleAvatar(
            backgroundColor: const Color(0xFFBFD7E9),
            child: Text(
              initial,
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppTheme.success,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF3E4E80), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final bool live;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    this.icon,
    this.selected = false,
    this.live = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = live ? AppTheme.success : AppTheme.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.10)
                : (live
                      ? AppTheme.success.withValues(alpha: 0.08)
                      : AppTheme.surface),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.35)
                  : (live
                        ? AppTheme.success.withValues(alpha: 0.22)
                        : AppTheme.border),
            ),
          ),
          child: Row(
            children: [
              if (live)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: const BoxDecoration(
                    color: AppTheme.success,
                    shape: BoxShape.circle,
                  ),
                ),
              if (icon != null)
                Icon(
                  icon,
                  size: 13,
                  color: selected ? AppTheme.primary : foreground,
                ),
              if (icon != null) const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.primary : foreground,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final _Collection collection;
  final VoidCallback onTap;

  /// Marca la colección que está filtrando el feed ahora mismo.
  final bool seleccionada;

  const _CollectionCard({
    required this.collection,
    required this.onTap,
    this.seleccionada = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: collection.colors,
          ),
          borderRadius: BorderRadius.circular(18),
          border: seleccionada
              ? Border.all(color: Colors.white, width: 2.5)
              : null,
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2B3A67),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 10,
              top: 6,
              child: Text(
                collection.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.44),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 7,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    collection.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SponsoredCard extends StatelessWidget {
  final _Sponsored sponsored;
  final VoidCallback onTap;
  const _SponsoredCard({required this.sponsored, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: sponsored.colors,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A2B3A67),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 18,
              top: 14,
              child: Icon(
                sponsored.icon,
                color: Colors.white.withValues(alpha: 0.25),
                size: 86,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 14, 17, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.17),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PATROCINADO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Antes decía "Verificado" sin que nada lo respaldara.
                      // Ahora se muestra el local real de la campaña.
                      if (sponsored.venue != null) ...[
                        const Icon(
                          Icons.place_outlined,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            sponsored.venue!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  Text(
                    sponsored.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sponsored.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Ver local  →',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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
}

/// Fecha corta `dd/mm/aaaa` para la vigencia de una promoción.
String _fechaCorta(DateTime d) {
  final dia = d.day.toString().padLeft(2, '0');
  final mes = d.month.toString().padLeft(2, '0');
  return '$dia/$mes/${d.year}';
}

/// Tarjeta de una oferta: descuento real de `flow.promocion`.
class _FlashOfferCard extends StatelessWidget {
  final HomeCatalogItem item;
  final VoidCallback onTap;

  const _FlashOfferCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 194,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D2B3A67),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Descuento real de `flow.promocion`, no un "-20 %" fijo.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    item.promocion!.etiquetaDescuento,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const Spacer(),
                if (item.promocion!.hasta != null)
                  Text(
                    'hasta ${_fechaCorta(item.promocion!.hasta!)}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              item.venue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            _PrecioConPromocion(
              item: item,
              textoAlternativo: 'Consultar precio',
              fontSize: 15,
            ),
            const SizedBox(height: 8),
            // Los cupos solo se muestran si la promo realmente los limita.
            if (item.promocion!.cuposRestantes != null)
              Text(
                item.promocion!.cuposRestantes == 1
                    ? 'Queda 1 cupo'
                    : 'Quedan ${item.promocion!.cuposRestantes} cupos',
                style: const TextStyle(
                  color: AppTheme.error,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              _EstadoHorarioChip(item: item),
          ],
        ),
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final HomeCatalogItem item;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onSave;
  const _RecommendedCard({
    required this.item,
    required this.onTap,
    required this.onSave,
    this.saved = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 188,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D2B3A67),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  _MediaPreview(item: item, radius: 13),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: BotonFavorito(
                      idLocalServicio: item.id,
                      titulo: item.title,
                      saved: saved,
                      size: 30,
                    ),
                  ),
                  Positioned(
                    top: 7,
                    left: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.category.nombre.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.venue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 10.5,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                _ValoracionChip(item: item),
                const Spacer(),
                _PrecioConPromocion(item: item),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PopularPlaceCard extends StatelessWidget {
  final HomeCatalogItem item;
  final VoidCallback onTap;

  const _PopularPlaceCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial = item.venue.trim().isEmpty ? '?' : item.venue.trim()[0];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 285,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D2B3A67),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 126,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _MediaPreview(item: item, radius: 0),
                  Positioned(
                    left: 12,
                    bottom: -20,
                    child: Container(
                      width: 48,
                      height: 48,
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CircleAvatar(
                        backgroundColor: const Color(0xFFDDE8F0),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 11,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _iconoCategoria(item.category),
                            color: AppTheme.accent,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 90),
                            child: Text(
                              item.category.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // `Expanded` acota la altura del bloque de datos: solo con altura
            // definida el `Spacer` puede anclar los chips y el botón al pie.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 24, 13, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.venue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.ubicacion ??
                          item.direccion ??
                          'Ubicación no indicada',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _EstadoHorarioChip(item: item),
                    // El botón queda anclado al pie de la tarjeta: con muchos o
                    // pocos chips, "Ver servicios" aparece siempre a la misma
                    // altura y nunca se sale del recorte.
                    const Spacer(),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: item.tags
                          .take(3)
                          .map(
                            (tag) => ConstrainedBox(
                              // Tres chips de 80 px caben en una sola línea de la
                              // tarjeta, así un tag largo no empuja el botón fuera.
                              constraints: const BoxConstraints(maxWidth: 80),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: FilledButton(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        child: const Text(
                          'Ver servicios',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyServiceRow extends StatelessWidget {
  final int rank;
  final HomeCatalogItem item;
  final VoidCallback onTap;

  const _WeeklyServiceRow({
    required this.rank,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rank == 1 ? const Color(0xFFFFF2D6) : AppTheme.surface,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank == 1 ? AppTheme.warning : AppTheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 56,
              height: 46,
              child: _MediaPreview(item: item, radius: 9),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    // El número que ordena el ranking es el que se pinta: así la
                    // posición 1-2-3 queda explicada por un dato real.
                    item.lugaresSemanaLabel != null
                        ? '${item.lugaresSemanaLabel} · ${item.venue}'
                        : (item.ubicacion ?? item.category.nombre),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _EstadoHorarioChip(item: item),
                ],
              ),
            ),
            _PrecioConPromocion(item: item),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textSecondary,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedServiceCard extends StatelessWidget {
  final HomeCatalogItem item;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onSave;

  const _FeedServiceCard({
    required this.item,
    required this.onTap,
    required this.onSave,
    this.saved = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 78,
                height: 78,
                child: _MediaPreview(item: item, radius: 12),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        BotonFavorito(
                          idLocalServicio: item.id,
                          titulo: item.title,
                          saved: saved,
                          size: 26,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.venue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.ubicacion ??
                          item.direccion ??
                          'Ubicación no indicada',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (item.tieneValoracion)
                          _ValoracionChip(item: item)
                        else
                          _EstadoHorarioChip(item: item),
                        const Spacer(),
                        _PrecioConPromocion(
                          item: item,
                          textoAlternativo: 'Consultar precio',
                        ),
                      ],
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
}

/// Precio de la tarjeta, con descuento si hay promoción vigente.
///
/// Cuando hay promo muestra el precio rebajado y el de lista tachado. El
/// descuento es **de referencia**: se calcula sobre el precio base porque el
/// Home no conoce las opciones que elegirá el cliente. El importe definitivo lo
/// fija el servidor al confirmar, y la hoja de reserva lo muestra cotizado.
class _PrecioConPromocion extends StatelessWidget {
  final HomeCatalogItem item;
  final String textoAlternativo;
  final double fontSize;

  const _PrecioConPromocion({
    required this.item,
    this.textoAlternativo = 'Consultar',
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (!item.tieneDescuento) {
      return Text(
        item.priceLabel ?? textoAlternativo,
        style: TextStyle(
          color: AppTheme.primary,
          fontSize: fontSize,
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
          '${item.precioConPromocion!.toStringAsFixed(0)} ${item.currency ?? ''}'
              .trim(),
          style: TextStyle(
            color: AppTheme.error,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          item.priceLabel!,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: fontSize * 0.82,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }
}

/// Valoración real del servicio: promedio + número de reseñas.
///
/// Solo se pinta cuando hay reseñas ([HomeCatalogItem.tieneValoracion]). Un
/// servicio sin valoraciones no muestra "0.0" ni estrellas rellenas: mostraría
/// una opinión que nadie dio. Antes el Home pintaba 4.8 con 142 reseñas
/// inventadas en todas las tarjetas.
class _ValoracionChip extends StatelessWidget {
  final HomeCatalogItem item;
  const _ValoracionChip({required this.item});

  @override
  Widget build(BuildContext context) {
    if (!item.tieneValoracion) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Estrellas(promedio: item.rating, size: 13),
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

/// Estado de apertura real del local, o "Horario no disponible" cuando el
/// texto de `horario_atencion` no se puede interpretar.
class _EstadoHorarioChip extends StatelessWidget {
  final HomeCatalogItem item;
  const _EstadoHorarioChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final (color, icono, etiqueta) = switch (item.estadoHorario) {
      EstadoHorario.abierto => (
        AppTheme.success,
        Icons.circle,
        'Abierto ahora',
      ),
      EstadoHorario.cerrado => (
        AppTheme.textSecondary,
        Icons.circle_outlined,
        'Cerrado ahora',
      ),
      EstadoHorario.desconocido => (
        AppTheme.textSecondary,
        Icons.schedule_outlined,
        'Horario no disponible',
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, color: color, size: 9),
        const SizedBox(width: 4),
        Text(
          etiqueta,
          style: TextStyle(
            color: color,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MediaPreview extends StatelessWidget {
  final HomeCatalogItem item;
  final double radius;
  const _MediaPreview({required this.item, required this.radius});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientFor(item.category),
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(
          _emojiFor(item.category),
          style: const TextStyle(fontSize: 31),
        ),
      ),
    );
    if (item.imageUrl == null || item.imageUrl!.trim().isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: NetImage(
        url: item.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: () => fallback,
      ),
    );
  }

  static List<Color> _gradientFor(HomeCatalogCategory category) {
    if (category.codigo == 'transporte_omnibus') {
      return const [Color(0xFF385582), Color(0xFF7BA6D3)];
    }
    // Degradado estable derivado del propio identificador: el mismo tipo de
    // actividad pinta siempre igual, sin tabla de colores que mantener.
    final semilla = category.codigo.isEmpty
        ? category.nombre.length
        : category.codigo.codeUnits.fold<int>(0, (a, b) => a + b);
    const paletas = <List<Color>>[
      [Color(0xFF70537C), Color(0xFFC69CC4)],
      [Color(0xFF2D7573), Color(0xFF71BCB4)],
      [Color(0xFF8A7355), Color(0xFFCBB58B)],
      [Color(0xFF395B91), Color(0xFF6D9DD1)],
      [Color(0xFF8C5B72), Color(0xFFC98CA4)],
    ];
    return paletas[semilla % paletas.length];
  }

  static String _emojiFor(HomeCatalogCategory category) =>
      switch (category.codigo) {
        'general' => '▦',
        'belleza' => '✦',
        'unas' => '💅',
        'cejas_pestanas' => '✨',
        'peluqueria' => '💇',
        'estetica_spa' => '🧖',
        'salud' => '🩺',
        'hogar' => '⌂',
        'mascotas' => '🐾',
        'gastronomia' => '🍽',
        'eventos' => '🎉',
        'tecnologia' => '📱',
        'transporte_omnibus' => '🚌',
        'transporte_privado' => '🚕',
        _ => '✦',
      };
}

class _HowStepCard extends StatelessWidget {
  final _HowStep step;
  const _HowStepCard({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, color: AppTheme.primary, size: 21),
          ),
          const SizedBox(height: 8),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            step.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Column(
          children: [
            SizedBox(
              height: 15,
              width: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 10),
            Text(
              'Cargando servicios…',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingMoreBlock extends StatelessWidget {
  const _LoadingMoreBlock();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(18),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _HorizontalLoading extends StatelessWidget {
  const _HorizontalLoading();
  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class _SectionTitleStyle extends TextStyle {
  const _SectionTitleStyle()
    : super(
        color: AppTheme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      );
}

/// Icono para un tipo de actividad.
///
/// Se conocen los códigos sembrados por `22_categorias_marketplace.sql`; un
/// código nuevo creado desde el panel admin cae al icono genérico sin romper
/// nada.
IconData _iconoCategoria(HomeCatalogCategory category) =>
    switch (category.codigo) {
      'general' => Icons.grid_view_rounded,
      'belleza' => Icons.auto_awesome_rounded,
      'unas' => Icons.back_hand_rounded,
      'cejas_pestanas' => Icons.remove_red_eye_outlined,
      'peluqueria' => Icons.content_cut_rounded,
      'estetica_spa' => Icons.spa_outlined,
      'salud' => Icons.medical_services_outlined,
      'hogar' => Icons.home_repair_service_outlined,
      'mascotas' => Icons.pets_outlined,
      'gastronomia' => Icons.restaurant_outlined,
      'eventos' => Icons.celebration_outlined,
      'tecnologia' => Icons.devices_other_outlined,
      'transporte_omnibus' => Icons.directions_bus_filled_outlined,
      'transporte_privado' => Icons.local_taxi_outlined,
      _ => Icons.category_outlined,
    };

/// Opción del selector de provincia.
class _OpcionUbicacion extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final bool seleccionada;
  final VoidCallback onTap;

  const _OpcionUbicacion({
    required this.titulo,
    required this.icono,
    required this.seleccionada,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icono, color: AppTheme.primary),
      title: Text(titulo),
      trailing: seleccionada
          ? const Icon(Icons.check_circle, color: AppTheme.accent)
          : null,
      onTap: onTap,
    );
  }
}

class _Collection {
  final String title;
  final String subtitle;
  final String emoji;
  final List<Color> colors;
  const _Collection(this.title, this.subtitle, this.emoji, this.colors);
}

class _Sponsored {
  final String name;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;

  /// Local donde está el servicio destacado. Se pinta en la esquina.
  final String? venue;

  const _Sponsored(
    this.name,
    this.subtitle,
    this.icon,
    this.colors, {
    this.venue,
  });

  /// Construye la tarjeta desde una campaña real de `flow.campana`.
  factory _Sponsored.deCampana(CampanaPatrocinada c) {
    return _Sponsored(
      c.titulo,
      c.subtituloONombre,
      _iconoDeCampana(c.icono),
      _coloresDeCampana(c),
      venue: c.local,
    );
  }

  /// Los iconos son una clave corta guardada por el superadmin. Se traduce aquí
  /// para que la base no dependa de `IconData`.
  static IconData _iconoDeCampana(String? nombre) => switch (nombre) {
    'spa' => Icons.spa_outlined,
    'storefront' => Icons.storefront_outlined,
    'star' => Icons.star_rounded,
    'local_offer' => Icons.local_offer_outlined,
    'directions_bus' => Icons.directions_bus_filled_outlined,
    'restaurant' => Icons.restaurant_outlined,
    'pets' => Icons.pets_outlined,
    'health' => Icons.medical_services_outlined,
    _ => Icons.campaign_outlined,
  };

  /// Degradado de la campaña. Si no define colores (o son inválidos) se usa el
  /// color de marca, en vez de caer a un color de relleno arbitrario.
  static List<Color> _coloresDeCampana(CampanaPatrocinada c) {
    final inicio = _parseHex(c.colorInicio) ?? AppTheme.primary;
    final fin = _parseHex(c.colorFin) ?? _aclarar(inicio);
    return [inicio, fin];
  }

  static Color? _parseHex(String? hex) {
    if (hex == null || hex.trim().isEmpty) return null;
    var v = hex.trim().replaceFirst('#', '');
    if (v.length == 6) v = 'FF$v';
    if (v.length != 8) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(n);
  }

  static Color _aclarar(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0)).toColor();
  }
}

class _HowStep {
  final String number;
  final String title;
  final String description;
  final IconData icon;
  const _HowStep(this.number, this.title, this.description, this.icon);
}
