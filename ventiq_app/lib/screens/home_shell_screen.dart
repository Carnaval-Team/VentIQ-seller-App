import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tutorial/tutorial_anchor.dart';
import '../tutorial/tutorial_flujos.dart';
import 'tutorial_venta_screen.dart';
import '../controllers/home_controller.dart';
import '../models/changelog.dart';
import '../models/home_catalogo.dart';
import '../models/product.dart';
import '../services/changelog_service.dart';
import '../services/home_catalog_service.dart';
import '../services/home_extras_service.dart';
import '../services/moneda_venta_service.dart';
import '../services/notification_service.dart';
import '../services/order_service.dart';
import '../services/product_detail_service.dart';
import '../services/product_service.dart';
import '../services/quick_add_service.dart';
import '../services/elaborated_availability_service.dart';
import '../services/sales_mode_service.dart';
import '../services/smart_offline_manager.dart';
import '../services/store_config_service.dart';
import '../services/user_preferences_service.dart';
import '../theme/ventiq_home_theme.dart';
import '../utils/categoria_gradiente.dart';
import '../utils/navigation_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/connection_status_widget.dart';
import '../widgets/home/categoria_drawer.dart';
import '../widgets/home/categoria_drawer_route.dart';
import '../widgets/home/home_buscador.dart';
import '../widgets/home/home_catalogo_view.dart';
import '../widgets/home/home_estado_vacio.dart';
import '../widgets/home/home_quick_chips.dart';
import '../widgets/home/home_seccion_titulo.dart';
import '../widgets/home/producto_tile.dart';
import '../widgets/home/quick_add_sheet.dart';
import '../widgets/home/riel_productos.dart';
import '../widgets/moneda_venta_chip.dart';
import '../widgets/notification_widget.dart';
import '../widgets/sales_monitor_fab.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/usd_rate_chip.dart';
import 'barcode_scanner_screen.dart';
import 'product_details_screen.dart';
import 'products_screen.dart';

/// Home tipo cliente del TPV: una sola implementación para web y APK.
///
/// Sustituye a `CategoriesScreen` (1780 líneas) y `CategoriesWebScreen` (1216),
/// que eran la misma pantalla copiada con diferencias accidentales.
///
/// Piezas del diseño, de arriba abajo:
///  1. hero degradado con saludo y acciones;
///  2. **buscador siempre visible**, flotando sobre la costura hero/lienzo;
///  3. chips rápidos;
///  4. rejilla de categorías **especiales**;
///  5. tarjeta **"Tienda"** con todo lo demás;
///  6. rieles de producto («Ofertas», «Más vendidos») al final.
///
/// Todo el estado y las reglas viven en [HomeController]; esta pantalla sólo
/// pinta y navega.
class HomeShellScreen extends StatefulWidget {
  const HomeShellScreen({super.key, this.gateway, this.contexto});

  /// Inyectable para tests. En la app se usa [HomeCatalogService].
  final HomeCatalogoGateway? gateway;

  /// Tienda y TPV. En la app se resuelven de `UserPreferencesService`; los
  /// tests lo pasan para no depender de las preferencias del dispositivo.
  final HomeContexto? contexto;

  /// Compone el saludo del Home. Público y estático para poder probarlo sin
  /// montar la pantalla (que arrastra Supabase y cuelga el runner).
  ///
  /// `Hola, {nombre}` cuando hay nombre guardado del trabajador; `Hola 👋` si
  /// la sesión es vieja y no lo tiene. Nunca devuelve un saludo vacío.
  static String saludoCon(String? nombre) {
    final String? limpio = nombre?.trim();
    return (limpio == null || limpio.isEmpty) ? 'Hola 👋' : 'Hola, $limpio';
  }

  /// ¿El Home debe enseñar los resultados de búsqueda en vez del catálogo?
  ///
  /// Depende **solo del texto**: el chip «Solo con stock» es un modificador de
  /// la búsqueda, no una búsqueda. Cuando entraba en esta condición con la
  /// consulta vacía, el Home se sustituía por «No hay productos que coincidan
  /// con “”» y se quedaba en blanco. Estático para poder probarlo.
  static bool hayBusquedaCon(String texto) => texto.trim().isNotEmpty;

  @override
  State<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends State<HomeShellScreen>
    with WidgetsBindingObserver {
  late final HomeController _home = HomeController(
    gateway: widget.gateway ?? HomeCatalogService(),
  );

  final UserPreferencesService _prefs = UserPreferencesService();

  // Estos tres servicios se crean **de forma perezosa** y no como campos
  // inicializados: sus constructores tocan `Supabase.instance`, así que
  // crearlos al montar el State reventaría en cualquier test (y en cualquier
  // arranque donde Supabase aún no esté listo). Creándolos al primer uso, el
  // Home pinta aunque la red todavía no esté configurada.
  ProductService? _productos;
  ProductService get _productService => _productos ??= ProductService();

  QuickAddService? _quickAdd;
  QuickAddService get _quickAddService => _quickAdd ??= QuickAddService();

  ElaboratedAvailabilityService? _elaborados;
  ElaboratedAvailabilityService get _elaboradosService =>
      _elaborados ??= ElaboratedAvailabilityService();

  /// Disponibilidad real de los elaborados en los resultados de búsqueda.
  /// (En el drawer la enriquece `HomeCatalogService` al cargar productos.)
  Map<int, double> _disponibilidadElaborados = <int, double>{};

  OrderService? _ordenes;
  OrderService get _orderService => _ordenes ??= OrderService();

  /// Líneas que lleva el carrito. Es un [ValueNotifier] porque el pie del
  /// drawer vive en otra ruta y no se reconstruye con el `setState` del Home.
  final ValueNotifier<int> _carrito = ValueNotifier<int>(0);

  NotificationService? _notificaciones;
  SmartOfflineManager? _offline;

  /// Rieles del Home (Fase 7). Perezoso por la misma razón que los demás
  /// servicios: su constructor toca `Supabase.instance`.
  HomeExtrasService? _extras;
  HomeExtrasService get _extrasService => _extras ??= HomeExtrasService();

  List<HomeRielProducto> _masVendidos = const <HomeRielProducto>[];
  List<HomeRielProducto> _ofertas = const <HomeRielProducto>[];

  /// Nombre de la tienda (D2) desde `app_dat_tienda.denominacion`.
  String _nombreTienda = 'Tienda';

  /// Ficha completa para abrir un producto de riel con su stock real.
  ProductDetailService? _detalle;
  ProductDetailService get _detalleService =>
      _detalle ??= ProductDetailService();

  final TextEditingController _buscador = TextEditingController();
  final FocusNode _focoBuscador = FocusNode();

  /// Para abrir el `endDrawer` desde la pleca lateral (el icono del AppBar ya
  /// no existe en este Home).
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  StreamSubscription<SmartOfflineEvent>? _subOffline;
  Timer? _debounceBusqueda;

  bool _soloConStock = false;
  bool _mostrarSku = false;
  bool _ahorroDeDatos = false;
  bool _modoFluido = false;

  /// Nombre del trabajador logueado, para el saludo del hero.
  ///
  /// Antes el Home saludaba con un `'Hola 👋'` fijo aunque el nombre ya estaba
  /// guardado en `SharedPreferences` desde el login: se leía `nombres` solo
  /// para resolver la tienda y se descartaba.
  String? _nombreTrabajador;

  List<Product> _resultados = const <Product>[];
  bool _buscandoProductos = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _home.addListener(_alCambiarHome);
    _arrancar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _home.removeListener(_alCambiarHome);
    _home.dispose();
    _subOffline?.cancel();
    _debounceBusqueda?.cancel();
    _buscador.dispose();
    _focoBuscador.dispose();
    _carrito.dispose();
    try {
      _notificaciones?.dispose();
    } catch (e) {
      debugPrint('⚠️ No se pudo cerrar el servicio de notificaciones: $e');
    }
    super.dispose();
  }

  /// Repinta cuando el controlador cambia. Es el equivalente a `setState` sin
  /// tener que envolver todo el árbol en un `ListenableBuilder`.
  void _alCambiarHome() {
    if (mounted) setState(() {});
  }

  Future<void> _arrancar() async {
    await _redirigirSiSoloInventario();
    await _cargarPerfil();
    await _cargarAjustes();
    // La moneda de venta se resuelve ANTES del catálogo: los precios del Home se
    // pintan con `MonedaVentaService.formatearPrecio` en el primer `build()`, y
    // si se cargara después el vendedor vería un parpadeo en CUP y luego el
    // cambio de divisa.
    await _cargarMonedaVenta();
    await _cargarCatalogo();
    _escucharModoOffline();
    unawaited(_iniciarNotificaciones());
    // El tutorial manda: si arranca, no encadenamos el changelog encima.
    final bool tutorial = await _quizasTutorial();
    if (!tutorial) unawaited(_mostrarNovedadesSiAplican());
  }

  /// Carga la **moneda de venta** de este teléfono y deja el formateador listo.
  ///
  /// Una sola llamada resuelve: divisas aceptadas por la tienda, sus tasas,
  /// la moneda guardada (con caída segura a CUP si ya no sirve) y el estado en
  /// memoria que leen las pantallas dentro de `build()`.
  ///
  /// Si falla la red o el catálogo, el servicio se queda en CUP, que es
  /// exactamente el comportamiento anterior a esta funcionalidad: nunca se
  /// bloquea el arranque del Home por esto.
  Future<void> _cargarMonedaVenta() async {
    try {
      await MonedaVentaService.cargarDesdeTienda();
    } catch (e) {
      debugPrint('⚠️ No se pudo cargar la moneda de venta: $e');
    }
    if (mounted) setState(() {});
  }

  /// Lanza el tutorial de venta la primera vez (normal o restaurante según la
  /// configuración del negocio). Devuelve 	rue si quedó visible.
  Future<bool> _quizasTutorial() async {
    final bool restaurante =
        StoreConfigService.modoRestauranteSync ||
        StoreConfigService.cocinaActivaSync;
    return TutorialAutoStart.intentar(context, restaurante: restaurante);
  }

  /// Muestra el changelog una vez por versión (antes solo salía en la primera
  /// instalación, así que los clientes nunca veían las novedades nuevas).
  Future<void> _mostrarNovedadesSiAplican() async {
    try {
      final Changelog? novedades =
          await ChangelogService().getLatestChangelog();
      if (novedades == null) return;

      final bool corresponde = await _prefs.isFirstTimeOpening(
        novedades.version,
      );
      if (!corresponde || !mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ChangelogDialog(changelog: novedades),
      );
      await _prefs.saveAppVersion(novedades.version);
    } catch (e) {
      // Nunca debe impedir que el Home arranque.
      debugPrint('⚠️ No se pudo mostrar el changelog: $e');
    }
  }

  /// Nombre del vendedor para el saludo. Aislado y tolerante: si el perfil no
  /// está (sesión vieja, offline sin datos), el Home pinta «Hola 👋» y sigue.
  Future<void> _cargarPerfil() async {
    try {
      final Map<String, dynamic?> perfil = await _prefs.getWorkerProfile();
      final String? nombres = (perfil['nombres'] as String?)?.trim();
      if (!mounted || nombres == null || nombres.isEmpty) return;
      setState(() => _nombreTrabajador = nombres);
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el nombre del trabajador: $e');
    }
  }

  /// Saludo del hero: el nombre del trabajador manda; sin él, saludo a secas.
  String get _saludo => HomeShellScreen.saludoCon(_nombreTrabajador);

  /// Aislado y protegido: si las notificaciones no arrancan (permiso denegado,
  /// plataforma sin soporte, test), el Home tiene que seguir funcionando.
  Future<void> _iniciarNotificaciones() async {
    try {
      final NotificationService servicio =
          _notificaciones ??= NotificationService();
      await servicio.initialize();
    } catch (e) {
      debugPrint('⚠️ Notificaciones no inicializadas en el Home: $e');
    }
  }

  Future<void> _cargarAjustes() async {
    try {
      final bool ahorro = await _prefs.isLimitDataUsageEnabled();
      final bool fluido = await _prefs.isFluidModeEnabled();
      final bool sku = await _prefs.isShowSkuEnabled();
      if (!mounted) return;
      setState(() {
        _ahorroDeDatos = ahorro;
        _modoFluido = fluido;
        _mostrarSku = sku;
      });
    } catch (e) {
      debugPrint('⚠️ No se pudieron leer los ajustes del Home: $e');
    }
  }

  /// Una sesión de solo inventario no vende: va al panel de administración.
  Future<void> _redirigirSiSoloInventario() async {
    try {
      final bool solo = await _prefs.isInventoryOnlySession();
      if (solo && mounted) {
        Navigator.of(context).pushReplacementNamed('/admin-home');
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo comprobar la sesión de inventario: $e');
    }
  }

  Future<void> _cargarCatalogo({bool forceRefresh = false}) async {
    try {
      final HomeContexto? inyectado = widget.contexto;
      if (inyectado != null) {
        await _home.cargar(inyectado, forceRefresh: forceRefresh);
        return;
      }

      final Map<String, dynamic> perfil = await _prefs.getWorkerProfile();
      final int? idTienda = perfil['idTienda'] as int?;
      final int? idTpv = await _prefs.getIdTpv();

      if (idTienda == null || idTpv == null) {
        debugPrint('⚠️ Home sin tienda/TPV en preferencias');
        return;
      }

      await _home.cargar(
        HomeContexto(idTienda: idTienda, idTpv: idTpv),
        forceRefresh: forceRefresh,
      );

      // Rieles y nombre de la tienda: no son críticos, van después y en
      // paralelo para no retrasar el primer frame del catálogo.
      unawaited(_cargarExtras(idTpv: idTpv, idTienda: idTienda));
    } catch (e) {
      debugPrint('❌ No se pudo resolver el contexto del Home: $e');
    }
  }

  /// Carga «más vendidos», «ofertas» y el nombre de la tienda.
  ///
  /// Tolerante: si las RPC nuevas no están aplicadas todavía (o no hay red),
  /// los rieles quedan vacíos y el Home funciona exactamente igual.
  Future<void> _cargarExtras({
    required int idTpv,
    required int idTienda,
  }) async {
    try {
      // 1) Pintar primero la última copia local: en offline (o con red lenta)
      //    el riel aparece al instante en vez de esperar al timeout.
      final List<HomeRielProducto> cacheTop = await _extrasService
          .masVendidosDesdeCache(idTpv);
      final List<HomeRielProducto> cacheOfertas = await _extrasService
          .ofertasDesdeCache(idTpv);
      final String nombreTienda = await _leerNombreTienda(idTienda);
      if (!mounted) return;
      setState(() {
        if (cacheTop.isNotEmpty) _masVendidos = cacheTop;
        if (cacheOfertas.isNotEmpty) _ofertas = cacheOfertas;
        _nombreTienda = nombreTienda;
      });

      // 2) En modo offline no se llama a la red: la caché es la verdad.
      if (await _prefs.shouldUseLocalData()) return;

      // 3) Online: refrescar y volver a guardar la copia local.
      final List<dynamic> resultados =
          await Future.wait<dynamic>(<Future<dynamic>>[
            _extrasService.masVendidos(idTpv: idTpv),
            _extrasService.ofertas(idTpv: idTpv),
          ]);
      if (!mounted) return;
      setState(() {
        _masVendidos = resultados[0] as List<HomeRielProducto>;
        _ofertas = resultados[1] as List<HomeRielProducto>;
      });
    } catch (e) {
      debugPrint('⚠️ No se pudieron cargar los rieles del Home: $e');
    }
  }

  /// Nombre de la tienda para la tarjeta «Tienda» (D2). La tabla de
  /// configuración no guarda nombre; el nombre real está en `app_dat_tienda`.
  Future<String> _leerNombreTienda(int idTienda) async {
    try {
      final dynamic fila =
          await Supabase.instance.client
              .from('app_dat_tienda')
              .select('denominacion')
              .eq('id', idTienda)
              .maybeSingle();
      final String? nombre =
          (fila is Map ? fila['denominacion'] : null)?.toString().trim();
      return (nombre == null || nombre.isEmpty) ? 'Tienda' : nombre;
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el nombre de la tienda: $e');
      return 'Tienda';
    }
  }

  /// Rieles que se pintan en el Home. Ofertas primero (es lo accionable) y
  /// después «más vendidos».
  List<Widget> _rielesDelHome() {
    final List<Widget> rieles = <Widget>[];
    if (_ofertas.isNotEmpty) {
      rieles.add(
        RielProductos(
          titulo: 'Ofertas',
          icono: Icons.local_offer_rounded,
          productos: _ofertas,
          esOferta: true,
          onTap: (HomeRielProducto p) {
            unawaited(_abrirProductoRiel(p));
          },
        ),
      );
    }
    if (_masVendidos.isNotEmpty) {
      if (rieles.isNotEmpty) rieles.add(const SizedBox(height: 18));
      rieles.add(
        RielProductos(
          titulo: 'Más vendidos',
          icono: Icons.trending_up_rounded,
          productos: _masVendidos,
          onTap: (HomeRielProducto p) {
            unawaited(_abrirProductoRiel(p));
          },
        ),
      );
    }
    return rieles;
  }

  /// Abre el detalle de un producto de riel cargando su ficha completa.
  ///
  /// El riel solo trae id/nombre/precio: construir un `Product` a medias
  /// dispararía la guarda de «sin stock». Si la ficha falla, avisa sin romper
  /// el Home.
  Future<void> _abrirProductoRiel(HomeRielProducto p) async {
    try {
      final Product completo = await _detalleService.getProductDetail(p.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder:
              (_) => ProductDetailsScreen(
                product: completo,
                categoryColor: VentiqHomeTheme.primary,
              ),
        ),
      );
      if (mounted) {
        unawaited(_cargarExtrasForzado());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir «${p.nombre}»: $e')),
      );
    }
  }

  Future<void> _cargarExtrasForzado() async {
    final int? idTpv = await _prefs.getIdTpv();
    final Map<String, dynamic> perfil = await _prefs.getWorkerProfile();
    final int? idTienda = perfil['idTienda'] as int?;
    if (idTpv == null || idTienda == null) return;
    await _cargarExtras(idTpv: idTpv, idTienda: idTienda);
  }

  /// Cuando el modo offline se activa o desactiva, el catálogo cambia de origen
  /// (red o caché) y hay que refrescarlo. Es el mismo motivo por el que el Home
  /// viejo tenía este listener.
  void _escucharModoOffline() {
    try {
      _subOffline = (_offline ??= SmartOfflineManager()).eventStream.listen((
        SmartOfflineEvent evento,
      ) {
        switch (evento.type) {
          case SmartOfflineEventType.offlineModeAutoActivated:
          case SmartOfflineEventType.offlineModeManuallyEnabled:
          case SmartOfflineEventType.offlineModeActive:
          case SmartOfflineEventType.offlineModeAutoDeactivated:
          case SmartOfflineEventType.offlineModeManuallyDisabled:
            _cargarCatalogo(forceRefresh: true);
          case SmartOfflineEventType.connectionRestoredWhileOffline:
            break;
          default:
            break;
        }
      });
    } catch (e) {
      debugPrint('⚠️ No se pudo escuchar el modo offline: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de segundo plano, la tasa y el catálogo pueden estar viejos.
    if (state == AppLifecycleState.resumed) {
      _cargarCatalogo(forceRefresh: true);
    }
  }

  // ── Búsqueda ───────────────────────────────────────────────────────────

  void _onBuscar(String texto) {
    setState(() => _buscandoProductos = texto.trim().isNotEmpty);
    _debounceBusqueda?.cancel();

    if (texto.trim().isEmpty) {
      setState(() {
        _resultados = const <Product>[];
        _buscandoProductos = false;
      });
      return;
    }

    _debounceBusqueda = Timer(
      const Duration(milliseconds: 250),
      () => _ejecutarBusqueda(texto),
    );
  }

  Future<void> _ejecutarBusqueda(String texto) async {
    final String consulta = texto.trim();
    if (consulta.isEmpty) return;

    try {
      final List<Product> encontrados = await _productService.searchProducts(
        query: consulta,
        soloDisponibles: _soloConStock,
      );
      if (!mounted || _buscador.text.trim() != consulta) return;
      setState(() {
        _resultados = encontrados;
        _buscandoProductos = false;
      });
      // Los elaborados no se venden por stock propio: su disponibilidad es la
      // materia prima de la cocina. Se resuelve en segundo plano para no
      // retrasar los resultados.
      unawaited(_enriquecerDisponibilidadElaborados());
    } catch (e) {
      debugPrint('❌ Búsqueda global falló: $e');
      if (!mounted) return;
      setState(() {
        _resultados = const <Product>[];
        _buscandoProductos = false;
      });
    }
  }

  void _limpiarBusqueda() {
    _debounceBusqueda?.cancel();
    _buscador.clear();
    // Al limpiar (también desde «Seguir comprando» del alta rápida) se cierra el
    // teclado para volver a ver el lienzo de categorías completo.
    _focoBuscador.unfocus();
    setState(() {
      _resultados = const <Product>[];
      _buscandoProductos = false;
      _disponibilidadElaborados = <int, double>{};
    });
  }

  /// Calcula y guarda la disponibilidad real de los elaborados que hay en los
  /// resultados de búsqueda. Solo importa a los elaborados: el resto sigue con
  /// su stock normal.
  Future<void> _enriquecerDisponibilidadElaborados() async {
    final int? idTpv = _home.contexto?.idTpv;
    final List<int> ids =
        _resultados
            .where((Product p) => p.esElaborado && !p.esServicio)
            .map((Product p) => p.id)
            .toSet()
            .toList();
    if (idTpv == null || ids.isEmpty || !mounted) return;

    try {
      final Map<int, double> disp = await _elaboradosService.disponibles(
        idsProductos: ids,
        idTpv: idTpv,
      );
      if (!mounted) return;
      setState(() => _disponibilidadElaborados = disp);
    } catch (e) {
      debugPrint('⚠️ No se pudo calcular la disponibilidad de elaborados: $e');
    }
  }

  // ── Navegación ─────────────────────────────────────────────────────────

  Color _colorDe(HomeCategoria categoria) =>
      gradienteCategoria(categoria.id).first;

  /// Tocar una tarjeta del Home.
  ///
  /// Si es especial, entra directo (sus subcategorías o sus productos). Si es
  /// la tarjeta "Tienda", abre el nivel de categorías. En los dos casos se abre
  /// el drawer **a pantalla completa**, que es el requisito.
  Future<void> _abrirDesdeHome(HomeCategoria categoria) async {
    // En flujo mesa el catálogo se navega **dentro** de la mesa (la cuenta
    // activa se ve allí), no desde el Home. Abrir el drawer aquí dejaría al
    // vendedor añadiendo a una cuenta que no tiene delante. El Home viejo ya
    // desviaba a `/mesas` desde la barra inferior por el mismo motivo
    // (`SalesModeService`); se hace igual al tocar una tarjeta.
    if (SalesModeService.flujoMesaActivo) {
      Navigator.pushNamedAndRemoveUntil(context, '/mesas', (_) => false);
      return;
    }

    if (categoria.esTiendaVirtual) {
      _home.abrirTienda();
    } else {
      await _home.abrirEspecial(categoria);
    }
    if (!mounted) return;
    await _mostrarDrawer();
  }

  Future<void> _abrirTienda() => _abrirDesdeHome(
    HomeCategoria.tienda(
      totalProductos: _home.productosEnTienda,
      totalSubcategorias: 0,
    ),
  );

  Future<void> _mostrarDrawer() {
    _actualizarCarrito();
    return abrirCategoriaDrawer<void>(
      context,
      builder:
          (BuildContext context) => CategoriaDrawer(
            controller: _home,
            mostrarSku: _mostrarSku,
            atenuarImagenes: _ahorroDeDatos,
            carrito: _carrito,
            onAbrirCarrito: _abrirCarrito,
            onAgregarProducto: _abrirCantidadRapida,
            onAbrirProducto: _abrirProducto,
          ),
    ).then((_) {
      // Al cerrarse, la pila se limpia para que la próxima apertura empiece en
      // la raíz y no donde se quedó.
      if (mounted) {
        _home.cerrarDrawer();
        _actualizarCarrito();
      }
    });
  }

  /// "Ver todos" desde el Home: listado completo, sin pasar por el drawer.
  void _abrirListadoCompleto(
    HomeCategoria categoria,
    HomeSubcategoria? subcategoria,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => ProductsScreen(
              categoryId: categoria.id,
              categoryName: categoria.nombre,
              categoryColor: _colorDe(categoria),
              subcategoriaNombre: subcategoria?.nombre,
            ),
      ),
    );
  }

  /// Abre el detalle de un producto tocado en el drawer.
  ///
  /// El drawer trabaja con `HomeProducto` (ligero: lo justo para pintar la
  /// fila), pero el detalle necesita el `Product` completo —variantes,
  /// presentaciones, banderas de inventario— que esa vista no trae. Se resuelve
  /// con `ProductService`, que ya tiene caché de 5 minutos y es el mismo camino
  /// que usaba el listado de siempre: la segunda vez es instantáneo.
  ///
  /// El detalle se apila **encima** del drawer, así que volver atrás devuelve al
  /// vendedor al nivel donde estaba, no al Home.
  Future<void> _abrirProducto(HomeProducto ligero) async {
    final int? idCategoria = ligero.idCategoria;
    if (idCategoria == null) return;

    try {
      final Map<String, List<Product>> porSubcategoria = await _productService
          .getProductsByCategory(idCategoria);

      Product? completo;
      for (final List<Product> lista in porSubcategoria.values) {
        for (final Product p in lista) {
          if (p.id == ligero.id) {
            completo = p;
            break;
          }
        }
        if (completo != null) break;
      }

      if (!mounted) return;

      if (completo == null) {
        _avisar('No se pudo abrir «${ligero.nombre}». Actualiza el catálogo.');
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder:
              (_) => ProductDetailsScreen(
                product: completo!,
                categoryColor: VentiqHomeTheme.primary,
              ),
        ),
      );
    } catch (e) {
      debugPrint('❌ No se pudo abrir el detalle: $e');
      if (mounted) _avisar('No se pudo abrir el producto.');
    }
  }

  // ── Venta rápida desde el drawer ───────────────────────────────────────

  /// Refresca el contador que enseña el pie del drawer.
  void _actualizarCarrito() {
    try {
      _carrito.value = _orderService.currentOrderItemCount;
    } catch (e) {
      debugPrint('⚠️ No se pudo leer el carrito: $e');
    }
  }

  /// Toca el «+» de una fila del drawer.
  Future<void> _abrirCantidadRapida(HomeProducto ligero) {
    return _abrirHojaCantidad(
      idProducto: ligero.id,
      nombre: ligero.nombre,
      stock: ligero.stock,
      esServicio: ligero.esServicio,
      esElaborado: ligero.esElaborado,
      idTpv: _home.contexto?.idTpv,
      etiquetaSeguir: 'Continuar añadiendo',
      alSeguir: () => _home.volverARaiz(),
    );
  }

  /// Toca el «+» de un resultado de la **búsqueda global** del Home.
  ///
  /// Misma hoja y mismas reglas que en el drawer; lo único distinto es que
  /// «Seguir comprando» limpia el filtro y devuelve al lienzo de categorías.
  Future<void> _abrirCantidadRapidaBusqueda(Product producto) {
    return _abrirHojaCantidad(
      idProducto: producto.id,
      nombre: producto.denominacion,
      stock: producto.cantidadReal.toDouble(),
      esServicio: producto.esServicio,
      esElaborado: producto.esElaborado,
      idTpv: _home.contexto?.idTpv,
      etiquetaSeguir: 'Seguir comprando',
      alSeguir: _limpiarBusqueda,
    );
  }

  /// Abre la hoja de cantidad y resuelve el resultado (agregar o detalle).
  Future<void> _abrirHojaCantidad({
    required int idProducto,
    required String nombre,
    required double stock,
    required bool esServicio,
    required bool esElaborado,
    required int? idTpv,
    required String etiquetaSeguir,
    required VoidCallback alSeguir,
  }) async {
    final QuickAddSalida? salida = await showModalBottomSheet<QuickAddSalida>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => QuickAddSheet(
            nombreProducto: nombre,
            evaluar:
                () => _quickAddService.evaluar(
                  idProducto,
                  fallbackStock: stock,
                  esServicio: esServicio,
                  esElaborado: esElaborado,
                  idTpv: idTpv,
                ),
            agregar: _quickAddService.agregar,
          ),
    );

    if (!mounted || salida == null) return;

    switch (salida.tipo) {
      case QuickAddSalidaTipo.requiereDetalle:
        final Product? producto = salida.producto;
        if (producto != null) await _abrirDetalleProducto(producto);
      case QuickAddSalidaTipo.agregado:
        _actualizarCarrito();
        final Product? producto = salida.producto;
        if (producto != null) {
          await _dialogoPostAgregado(
            producto,
            salida.cantidad,
            etiquetaSeguir: etiquetaSeguir,
            alSeguir: alSeguir,
          );
        }
    }
  }

  Future<void> _abrirDetalleProducto(Product producto) {
    return Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => ProductDetailsScreen(
              product: producto,
              categoryColor: VentiqHomeTheme.primary,
            ),
      ),
    );
  }

  /// Diálogo tras añadir: «Ir al carrito» o la acción de seguir comprando.
  ///
  /// En el drawer, seguir comprando vuelve a la raíz del drawer; en la búsqueda,
  /// limpia el filtro y devuelve al lienzo de categorías.
  Future<void> _dialogoPostAgregado(
    Product producto,
    double cantidad, {
    required String etiquetaSeguir,
    required VoidCallback alSeguir,
  }) async {
    final String cantidadTexto =
        cantidad == cantidad.roundToDouble()
            ? cantidad.toStringAsFixed(0)
            : cantidad.toStringAsFixed(2);
    final int enCarrito = _carrito.value;

    final bool? irAlCarrito = await showDialog<bool>(
      context: context,
      builder:
          (BuildContext ctx) => AlertDialog(
            title: const Text('Añadido al carrito'),
            content: Text(
              '${producto.denominacion} × $cantidadTexto\n\n'
              'Llevas $enCarrito ${enCarrito == 1 ? 'producto' : 'productos'} '
              'en el carrito.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(etiquetaSeguir),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ir al carrito'),
              ),
            ],
          ),
    );

    if (!mounted) return;

    if (irAlCarrito == true) {
      await _abrirCarrito();
    } else {
      // Drawer: vuelve a categorías. Búsqueda: limpia el filtro.
      alSeguir();
    }
  }

  Future<void> _abrirCarrito() async {
    // Si hay una ruta encima del Home (el drawer o un diálogo), se cierra antes
    // de abrir el carrito; si no, el "atrás" del carrito volvería al drawer.
    final ModalRoute<dynamic>? ruta = ModalRoute.of(context);
    if (ruta != null && !ruta.isCurrent) {
      Navigator.of(context).pop();
      if (!mounted) return;
    }
    await NavigationHelper.goCarrito(context);
  }

  /// Abre el detalle desde los resultados de búsqueda: aquí el [Product] ya
  /// viene completo —variantes incluidas—, así que no hay que resolverlo
  /// contra el listado como en el drawer.
  Future<void> _abrirProductoCompleto(Product producto) {
    return Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder:
            (_) => ProductDetailsScreen(
              product: producto,
              categoryColor: VentiqHomeTheme.primary,
            ),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0:
        // Home. En modo restaurante el "home" del vendedor son las mesas.
        if (SalesModeService.flujoMesaActivo) {
          Navigator.pushNamedAndRemoveUntil(context, '/mesas', (_) => false);
        } else if (_home.hayBusquedaActiva || _buscador.text.isNotEmpty) {
          _limpiarBusqueda();
        } else {
          _cargarCatalogo(forceRefresh: true);
        }
      case 1:
        NavigationHelper.goCarrito(context);
      case 2:
        Navigator.pushNamed(context, '/orders');
      case 3:
        Navigator.pushNamed(context, '/settings').then((_) {
          if (mounted) _cargarAjustes();
        });
    }
  }

  void _abrirEscaner() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const BarcodeScannerScreen()),
    );
  }

  // ── Construcción ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: VentiqHomeTheme.surface,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final bool mostrarFlotantes = c.maxWidth >= 300 && c.maxHeight >= 400;
          return Stack(
            children: <Widget>[
              RefreshIndicator(
                color: VentiqHomeTheme.primary,
                onRefresh: () => _cargarCatalogo(forceRefresh: true),
                child: HomeCatalogoView(
                  saludo: _saludo,
                  subtitulo: '¿Qué vas a vender?',
                  estado: _home.estado,
                  catalogo: _home.catalogo,
                  // El estado online/offline va en su propio hueco (abajo a la
                  // derecha), no pegado al saludo: así el nombre queda limpio a
                  // la izquierda y la derecha se lee en dos pisos.
                  estadoConexion: const ConnectionStatusWidget(compact: true),
                  acciones: <Widget>[
                    // Moneda de venta: se oculta sola si la tienda solo tiene
                    // una divisa con tasa, así que las tiendas de siempre no
                    // ven ningún control nuevo. Al cambiarla hay que repintar
                    // el Home porque todos sus precios se reformatean.
                    MonedaVentaChip(
                      onChanged: (_) {
                        if (mounted) setState(() {});
                      },
                    ),
                    IconButton(
                      tooltip: 'Escanear código de barras',
                      onPressed: _abrirEscaner,
                      icon: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const NotificationWidget(),
                  ],
                  buscador: TutorialAnchor(
                    id: 'home_buscar',
                    child: HomeBuscador(
                      controller: _buscador,
                      focusNode: _focoBuscador,
                      onChanged: _onBuscar,
                      onLimpiar: _limpiarBusqueda,
                    ),
                  ),
                  chips: TutorialAnchor(
                    id: 'home_chips',
                    child: _chipsRapidos(),
                  ),
                  rieles: _rielesDelHome(),
                  nombreTienda: _nombreTienda,
                  contenidoAlternativo:
                      _hayBusqueda ? _resultadosBusqueda() : null,
                  onTapCategoria: _abrirDesdeHome,
                  onTapTienda: _abrirTienda,
                  onAbrirListado:
                      (HomeCategoria c) => _abrirListadoCompleto(c, null),
                  onRefrescar: () => _cargarCatalogo(forceRefresh: true),
                ),
              ),
              if (mostrarFlotantes) ...<Widget>[
                const Positioned(bottom: 16, left: 16, child: UsdRateChip()),
                const Positioned(bottom: 80, left: 16, child: SyncStatusChip()),
                // Pleca lateral centrada: abre el menú (endDrawer) sin gastar
                // sitio en el AppBar. Sustituye al icono de menú retirado.
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TutorialAnchor(
                      id: 'home_pleca',
                      child: _PlecaMenu(
                        onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      endDrawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0,
        onTap: _onBottomNavTap,
      ),
      floatingActionButton:
          MediaQuery.sizeOf(context).width < 300
              ? null
              : const SalesMonitorFAB(),
    );
  }

  /// Hay una búsqueda de producto activa **con texto**.
  ///
  /// El chip «Solo con stock» NO entra aquí: es un filtro de la búsqueda, no
  /// una búsqueda. Antes encendía el lienzo alternativo con la consulta vacía y
  /// el Home desaparecía diciendo «No hay productos que coincidan con “”»,
  /// dejando la pantalla en blanco al tocar el chip.
  bool get _hayBusqueda => HomeShellScreen.hayBusquedaCon(_buscador.text);

  Widget _chipsRapidos() {
    return HomeQuickChips(
      chips: <Widget>[
        HomeQuickChip(
          label: 'Solo con stock',
          icono: Icons.inventory_2_outlined,
          selected: _soloConStock,
          onTap: () {
            setState(() => _soloConStock = !_soloConStock);
            if (_buscador.text.trim().isNotEmpty) {
              _ejecutarBusqueda(_buscador.text);
            } else if (_soloConStock) {
              // El filtro es de la búsqueda, no del lienzo: sin texto no hay
              // nada que filtrar. Mejor decirlo que dejar la pantalla igual y
              // que parezca que el chip no hace nada.
              _avisar(
                '«Solo con stock» se aplica a los resultados de la búsqueda.',
              );
            }
          },
        ),
        if (_ahorroDeDatos)
          HomeQuickChip(
            label: 'Ahorro de datos',
            icono: Icons.data_saver_on,
            live: true,
            onTap:
                () => _avisar(
                  'Modo ahorro de datos activo: las imágenes no se cargan.',
                ),
          ),
        if (_modoFluido)
          HomeQuickChip(
            label: 'Modo fluido',
            icono: Icons.bolt_rounded,
            live: true,
            onTap:
                () => _avisar(
                  'El modo fluido se retirará: el nuevo Home ya es el camino rápido.',
                ),
          ),
        HomeQuickChip(
          label: 'Tutorial',
          icono: Icons.school_rounded,
          onTap: _abrirTutorial,
        ),
        HomeQuickChip(
          label: _mostrarSku ? 'SKU visible' : 'SKU oculto',
          icono: Icons.tag_rounded,
          onTap: () => _avisar('El SKU se cambia en Configuración.'),
        ),
      ],
    );
  }

  /// Relanza el tutorial guiado (overlay con foco) del modo actual.
  void _abrirTutorial() {
    final bool restaurante =
        StoreConfigService.modoRestauranteSync ||
        StoreConfigService.cocinaActivaSync;
    final String uuid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uuid.isEmpty) {
      // Sin sesión no hay tutorial que recordar: se abre el recorrido simple.
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TutorialVentaScreen(modoRestaurante: restaurante),
        ),
      );
      return;
    }
    TutorialAutoStart.reiniciarIntento();
    TutorialFlujos.iniciarVenta(
      context,
      restaurante: restaurante,
      uuidUsuario: uuid,
    );
  }

  void _avisar(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), duration: const Duration(seconds: 2)),
    );
  }

  // ── Resultados de búsqueda ─────────────────────────────────────────────

  Widget _resultadosBusqueda() {
    if (_buscandoProductos) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_resultados.isEmpty) {
      return HomeEstadoVacio(
        icono: Icons.search_off_rounded,
        titulo: 'Sin resultados',
        mensaje:
            'No hay productos que coincidan con «${_buscador.text.trim()}».',
        compacto: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HomeSeccionTitulo(
          rotulo:
              '${_resultados.length} RESULTADO'
              '${_resultados.length == 1 ? '' : 'S'}',
        ),
        const SizedBox(height: 8),
        for (final Product p in _resultados) _filaBusqueda(p),
      ],
    );
  }

  Widget _filaBusqueda(Product p) {
    HomeProducto fila = HomeProducto.desdeProducto(p);

    // Elaborado: el stock propio (1, 0...) no es lo que se puede vender; se
    // sustituye por la disponibilidad calculada sobre la materia prima.
    final double? elaborable = _disponibilidadElaborados[p.id];
    if (elaborable != null) {
      fila = fila.copyWith(stock: elaborable, tieneStock: elaborable > 0);
    }
    final bool disponible =
        elaborable != null ? elaborable > 0 : p.disponibleParaVenta;

    return ProductoTile(
      producto: fila,
      heroTag: 'prod-${p.id}',
      mostrarSku: _mostrarSku,
      atenuarImagenes: _ahorroDeDatos,
      // En la búsqueda no hay contexto de categoría alrededor: se pinta
      // bajo el nombre (con SKU si el ajuste está activo).
      subtitulo:
          _mostrarSku && (p.sku ?? '').isNotEmpty
              ? '${p.categoria} · ${p.sku}'
              : p.categoria,
      onTap: () => _abrirProductoCompleto(p),
      // El «+» es el mismo alta rápida del drawer. Se oculta para servicios
      // (siempre pasan por el detalle) y para lo no vendible.
      onAgregar:
          (p.esServicio || !disponible)
              ? null
              : () => _abrirCantidadRapidaBusqueda(p),
    );
  }
}

/// Pleca lateral que abre el menú (`endDrawer`) del Home.
///
/// Vive anclada al borde derecho y centrada verticalmente: no ocupa espacio del
/// contenido, no tapa el hero ni la barra inferior y ofrece un punto de toque
/// grande (48 px de ancho efectivo) que se hunde al pulsarlo. Entra deslizándose
/// desde la derecha una sola vez, sin animación en bucle para no distraer.
class _PlecaMenu extends StatefulWidget {
  const _PlecaMenu({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_PlecaMenu> createState() => _PlecaMenuState();
}

class _PlecaMenuState extends State<_PlecaMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrada = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<Offset> _deslizar = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entrada, curve: Curves.easeOutCubic));

  bool _pulsada = false;

  @override
  void initState() {
    super.initState();
    _entrada.forward();
  }

  @override
  void dispose() {
    _entrada.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _deslizar,
      child: Tooltip(
        message: 'Abrir menú',
        child: Semantics(
          button: true,
          label: 'Abrir menú',
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pulsada = true),
            onTapUp: (_) => setState(() => _pulsada = false),
            onTapCancel: () => setState(() => _pulsada = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _pulsada ? 0.94 : 1.0,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 44,
                alignment: Alignment.centerRight,
                child: Container(
                  width: 30,
                  height: 98,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        VentiqHomeTheme.primaryLight,
                        VentiqHomeTheme.primary,
                      ],
                    ),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: VentiqHomeTheme.primary.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(-2, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(
                        Icons.menu_open_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                      const SizedBox(height: 6),
                      RotatedBox(
                        quarterTurns: 3,
                        child: Text(
                          'MENÚ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
