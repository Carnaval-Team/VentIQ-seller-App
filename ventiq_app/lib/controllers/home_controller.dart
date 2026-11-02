import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/home_catalogo.dart';
import '../services/home_catalog_service.dart';

/// Estado del Home.
enum HomeEstado {
  /// Todavía no se pidió nada.
  inicial,

  /// Primera carga, sin datos que enseñar aún.
  cargando,

  /// Hay catálogo (de red o de caché).
  listo,

  /// No hubo forma de cargar y no había caché.
  error,
}

/// Nivel visible dentro del drawer jerárquico.
enum HomeNivelDrawer {
  /// Lista de categorías. Es la raíz cuando se entra por "Tienda".
  categorias,

  /// Subcategorías de una categoría.
  subcategorias,

  /// Productos de una categoría o de una subcategoría. Es el nivel final.
  productos,
}

/// Un escalón de la pila del drawer.
///
/// Guarda lo necesario para repintar el nivel sin volver a pedir nada: al subir,
/// el nivel anterior ya está resuelto en memoria. Eso es lo que hace que el
/// "atrás" sea instantáneo.
@immutable
class HomePasoDrawer {
  const HomePasoDrawer({
    required this.nivel,
    required this.titulo,
    this.categoria,
    this.subcategoria,
    this.categorias = const <HomeCategoria>[],
  });

  final HomeNivelDrawer nivel;

  /// Rótulo del nivel, para el breadcrumb.
  final String titulo;

  /// Categoría de la que cuelga este nivel.
  final HomeCategoria? categoria;

  /// Subcategoría, solo en el nivel de productos abierto desde una subcategoría.
  final HomeSubcategoria? subcategoria;

  /// Categorías a pintar, solo en el nivel [HomeNivelDrawer.categorias].
  final List<HomeCategoria> categorias;

  factory HomePasoDrawer.categorias({
    required String titulo,
    required List<HomeCategoria> categorias,
  }) => HomePasoDrawer(
    nivel: HomeNivelDrawer.categorias,
    titulo: titulo,
    categorias: List<HomeCategoria>.unmodifiable(categorias),
  );

  factory HomePasoDrawer.subcategorias(HomeCategoria categoria) =>
      HomePasoDrawer(
        nivel: HomeNivelDrawer.subcategorias,
        titulo: categoria.nombre,
        categoria: categoria,
      );

  factory HomePasoDrawer.productos({
    required HomeCategoria categoria,
    HomeSubcategoria? subcategoria,
  }) => HomePasoDrawer(
    nivel: HomeNivelDrawer.productos,
    titulo: subcategoria?.nombre ?? categoria.nombre,
    categoria: categoria,
    subcategoria: subcategoria,
  );

  @override
  String toString() => 'HomePasoDrawer($nivel, "$titulo")';
}

/// Estado y reglas del Home tipo cliente.
///
/// Es un `ChangeNotifier` de la librería estándar, **sin `provider` ni ningún
/// paquete de estado**: la app entera funciona con `setState` y servicios, y
/// meter un gestor de estado para una pantalla habría sido una isla. El Home lo
/// consume con `ListenableBuilder`.
///
/// No conoce Supabase ni `SharedPreferences`: depende de
/// [HomeCatalogoGateway], que se le inyecta. Por eso toda la lógica de esta
/// clase (agrupación, orden, búsqueda, pila del drawer) se prueba con un doble.
class HomeController extends ChangeNotifier {
  HomeController({
    required HomeCatalogoGateway gateway,
    this.debounceBusqueda = const Duration(milliseconds: 250),
  }) : _gateway = gateway;

  final HomeCatalogoGateway _gateway;

  /// Espera antes de buscar. 250 ms es el punto donde el vendedor que teclea
  /// rápido no dispara una consulta por letra y el que teclea despacio no
  /// percibe retardo.
  final Duration debounceBusqueda;

  // ── Catálogo ───────────────────────────────────────────────────────────
  HomeEstado _estado = HomeEstado.inicial;
  HomeEstado get estado => _estado;

  HomeCatalogo _catalogo = const HomeCatalogo();
  HomeCatalogo get catalogo => _catalogo;

  String? _mensajeError;
  String? get mensajeError => _mensajeError;

  HomeContexto? _contexto;
  HomeContexto? get contexto => _contexto;

  /// Tarjetas destacadas del Home, en orden.
  List<HomeCategoria> get especiales => _catalogo.especiales;

  /// Contenido de la tarjeta "Tienda". Vacío ⇒ la tarjeta no se pinta.
  List<HomeCategoria> get categoriasTienda => _catalogo.tienda;

  bool get mostrarTarjetaTienda => _catalogo.mostrarTarjetaTienda;

  /// Número de rubros que agrupa "Tienda", para el chip de la tarjeta.
  int get rubrosEnTienda => _catalogo.tienda.length;

  int get productosEnTienda => _catalogo.tienda.fold<int>(
    0,
    (int suma, HomeCategoria c) => suma + c.totalProductos,
  );

  final List<HomeCategoria> _todasLasCategorias = <HomeCategoria>[];

  /// Todo el catálogo sin repartir. Lo necesita "Ver todos" y el conteo del
  /// chip de la tarjeta de Tienda.
  List<HomeCategoria> get todasLasCategorias =>
      List<HomeCategoria>.unmodifiable(_todasLasCategorias);

  // ── Búsqueda ───────────────────────────────────────────────────────────
  String _query = '';
  String get query => _query;

  bool _buscando = false;
  bool get buscando => _buscando;

  List<HomeProducto> _resultados = const <HomeProducto>[];
  List<HomeProducto> get resultados => _resultados;

  bool get hayBusquedaActiva => _query.trim().isNotEmpty;

  Timer? _temporizador;
  int _tokenBusqueda = 0;

  // ── Drawer ─────────────────────────────────────────────────────────────
  final List<HomePasoDrawer> _pila = <HomePasoDrawer>[];

  /// Pila de niveles del drawer. La raíz es `[0]`; el nivel visible es `last`.
  List<HomePasoDrawer> get pila => List<HomePasoDrawer>.unmodifiable(_pila);

  HomePasoDrawer? get pasoActual => _pila.isEmpty ? null : _pila.last;

  bool get drawerAbierto => _pila.isNotEmpty;

  /// Se puede volver atrás sin cerrar (hay más de un nivel).
  bool get puedeVolverAtras => _pila.length > 1;

  /// Se puede cerrar sin haber abierto nada.
  bool get puedeCerrar => _pila.isNotEmpty;

  List<HomeSubcategoria> _subcategorias = const <HomeSubcategoria>[];
  List<HomeSubcategoria> get subcategorias => _subcategorias;

  List<HomeProducto> _productosNivel = const <HomeProducto>[];
  List<HomeProducto> get productosNivel => _productosNivel;

  bool _cargandoNivel = false;
  bool get cargandoNivel => _cargandoNivel;

  String? _errorNivel;
  String? get errorNivel => _errorNivel;

  /// Migajas del breadcrumb: `['Tienda', 'Bebidas', 'Colas']`.
  List<String> get migajas =>
      _pila.map((HomePasoDrawer p) => p.titulo).toList(growable: false);

  bool _desechado = false;

  @override
  void dispose() {
    _desechado = true;
    _temporizador?.cancel();
    super.dispose();
  }

  void _avisar() {
    if (!_desechado) notifyListeners();
  }

  // ── Carga ──────────────────────────────────────────────────────────────

  /// Carga el catálogo del Home.
  ///
  /// El contexto (tienda y TPV) se pasa desde fuera a propósito: así esta clase
  /// no depende de `UserPreferencesService` y se puede probar sin él.
  Future<void> cargar(
    HomeContexto contexto, {
    bool forceRefresh = false,
  }) async {
    if (_contexto != contexto) {
      // Cambió de tienda o de TPV: lo de antes no vale.
      _pila.clear();
      _contexto = contexto;
    }

    if (_estado == HomeEstado.inicial || _todasLasCategorias.isEmpty) {
      _estado = HomeEstado.cargando;
      _avisar();
    }

    try {
      final List<HomeCategoria> crudas = await _gateway.catalogo(
        contexto: contexto,
        forceRefresh: forceRefresh,
      );

      _todasLasCategorias
        ..clear()
        ..addAll(crudas);
      _catalogo = HomeCatalogo.agrupar(crudas);
      _mensajeError = null;
      _estado = HomeEstado.listo;
    } catch (e) {
      debugPrint('❌ HomeController.cargar: $e');
      _mensajeError = 'No se pudo cargar el catálogo.';
      // Si ya había algo en pantalla (caché), no se tira: es mejor un Home algo
      // viejo que un Home vacío en medio de un turno.
      _estado =
          _todasLasCategorias.isEmpty ? HomeEstado.error : HomeEstado.listo;
    }
    _avisar();
  }

  /// Recarga saltándose la caché. Es el pull-to-refresh.
  Future<void> refrescar() async {
    final HomeContexto? c = _contexto;
    if (c == null) return;
    await cargar(c, forceRefresh: true);
  }

  // ── Búsqueda ───────────────────────────────────────────────────────────

  /// Busca con retardo. Cada pulsación reinicia el temporizador, así que solo
  /// se consulta cuando el vendedor para de teclear.
  void buscar(String texto) {
    _query = texto;
    _temporizador?.cancel();

    if (texto.trim().isEmpty) {
      _resultados = const <HomeProducto>[];
      _buscando = false;
      _avisar();
      return;
    }

    _buscando = true;
    _avisar();

    _temporizador = Timer(debounceBusqueda, () => _ejecutarBusqueda(texto));
  }

  /// Ejecuta la búsqueda ya mismo, sin esperar el debounce (tecla Enter).
  Future<void> buscarAhora(String texto) {
    _temporizador?.cancel();
    _query = texto;
    return _ejecutarBusqueda(texto);
  }

  Future<void> _ejecutarBusqueda(String texto) async {
    final HomeContexto? c = _contexto;
    final String consulta = texto.trim();
    if (c == null || consulta.isEmpty) return;

    // Cada búsqueda lleva un token: si el vendedor sigue tecleando, la
    // respuesta vieja llega tarde y NO debe pisar a la nueva.
    final int token = ++_tokenBusqueda;
    _buscando = true;
    _avisar();

    try {
      final List<HomeProducto> encontrados = await _gateway.productos(
        contexto: c,
        texto: consulta,
      );
      if (token != _tokenBusqueda) return;

      // Copia antes de ordenar: el gateway puede devolver una lista cacheada e
      // inmutable, y `sort` sobre ella reventaría en producción.
      _resultados = List<HomeProducto>.of(encontrados)..sort(
        (HomeProducto a, HomeProducto b) =>
            a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );
    } catch (e) {
      if (token != _tokenBusqueda) return;
      debugPrint('❌ HomeController.buscar: $e');
      _resultados = const <HomeProducto>[];
    } finally {
      if (token == _tokenBusqueda) {
        _buscando = false;
        _avisar();
      }
    }
  }

  /// Limpia la búsqueda y vuelve al lienzo de categorías.
  void limpiarBusqueda() {
    _temporizador?.cancel();
    _tokenBusqueda++;
    _query = '';
    _resultados = const <HomeProducto>[];
    _buscando = false;
    _avisar();
  }

  // ── Drawer: entrada desde el Home ──────────────────────────────────────

  /// Toca la tarjeta "Tienda": abre el nivel de categorías no especiales.
  void abrirTienda() {
    if (_catalogo.tienda.isEmpty) return;
    _pila
      ..clear()
      ..add(
        HomePasoDrawer.categorias(
          titulo: kNombreTienda,
          categorias: _catalogo.tienda,
        ),
      );
    _limpiarNivel();
    _avisar();
  }

  /// Toca una tarjeta especial.
  ///
  /// Sin subcategorías va directo a los productos (es el caso de "Combustibles"
  /// en un servicentro: un toque y ya se está vendiendo). Con subcategorías abre
  /// el nivel de subcategorías.
  Future<void> abrirEspecial(HomeCategoria categoria) async {
    _pila.clear();
    await _entrarEnCategoria(categoria, desdeLista: false);
  }

  /// Toca una categoría dentro de la lista de categorías del drawer.
  Future<void> abrirCategoria(HomeCategoria categoria) =>
      _entrarEnCategoria(categoria, desdeLista: true);

  /// Toca la cabecera de una categoría abierta ("Ver todos"): sus productos.
  Future<void> abrirProductosDeCategoria(HomeCategoria categoria) async {
    _pila.add(HomePasoDrawer.productos(categoria: categoria));
    await _cargarProductosDelNivel();
  }

  /// Toca una subcategoría: sus productos, en el mismo drawer.
  Future<void> abrirSubcategoria(HomeSubcategoria subcategoria) async {
    final HomeCategoria? categoria = pasoActual?.categoria;
    if (categoria == null) return;

    _pila.add(
      HomePasoDrawer.productos(
        categoria: categoria,
        subcategoria: subcategoria,
      ),
    );
    await _cargarProductosDelNivel();
  }

  Future<void> _entrarEnCategoria(
    HomeCategoria categoria, {
    required bool desdeLista,
  }) async {
    if (categoria.tieneSubcategorias) {
      _pila.add(HomePasoDrawer.subcategorias(categoria));
      await _cargarSubcategoriasDelNivel();
    } else {
      _pila.add(HomePasoDrawer.productos(categoria: categoria));
      await _cargarProductosDelNivel();
    }
  }

  /// Sube un nivel.
  ///
  /// Devuelve `true` si el drawer sigue abierto y `false` si se cerró: es lo que
  /// necesita el `PopScope` de la pantalla para decidir si consume el "atrás"
  /// del sistema o deja que cierre la ruta.
  bool volverNivel() {
    if (_pila.isEmpty) return false;

    if (_pila.length == 1) {
      cerrarDrawer();
      return false;
    }

    _pila.removeLast();
    final HomePasoDrawer actual = _pila.last;

    // Los datos del nivel al que se vuelve ya estaban resueltos: si es la lista
    // de categorías, no hay nada que pedir; si no, se conserva lo cargado y solo
    // se limpia el nivel de productos.
    if (actual.nivel == HomeNivelDrawer.categorias) {
      _limpiarNivel();
    } else if (actual.nivel == HomeNivelDrawer.subcategorias) {
      _productosNivel = const <HomeProducto>[];
      _errorNivel = null;
    } else {
      _subcategorias = const <HomeSubcategoria>[];
      _errorNivel = null;
    }

    _avisar();
    return true;
  }

  void cerrarDrawer() {
    _pila.clear();
    _limpiarNivel();
    _avisar();
  }

  /// Vuelve al **primer** nivel del drawer sin cerrarlo.
  ///
  /// Es lo que hacen «Seguir añadiendo» (tras agregar al carrito) y el pie del
  /// nivel de productos: deja al vendedor en la lista de categorías (o en las
  /// subcategorías de la especial abierta) para seguir vendiendo.
  ///
  /// Ojo: **no** se puede limpiar el nivel a ciegas. Si la raíz del drawer es el
  /// nivel de subcategorías (caso de una especial con hijas), limpiar
  /// `_subcategorias` dejaba el nivel vacío y pintaba el mensaje «esta categoría
  /// no tiene subcategorías» aunque sí las tuviera. Solo se limpia lo que ya no
  /// sirve en el nivel de destino.
  void volverARaiz() {
    if (_pila.length <= 1) return;

    _pila.removeRange(1, _pila.length);
    final HomePasoDrawer actual = _pila.last;

    switch (actual.nivel) {
      case HomeNivelDrawer.categorias:
        _limpiarNivel();
      case HomeNivelDrawer.subcategorias:
        // La lista de subcategorías ya estaba cargada: se conserva. Si faltara
        // (p. ej. se volvió antes de que terminara la carga), se vuelve a pedir.
        _productosNivel = const <HomeProducto>[];
        _errorNivel = null;
        _cargandoNivel = false;
        if (_subcategorias.isEmpty) {
          unawaited(_cargarSubcategoriasDelNivel());
          return;
        }
      case HomeNivelDrawer.productos:
        // Raíz de una especial sin hijas: los productos siguen siendo válidos.
        _errorNivel = null;
        _cargandoNivel = false;
    }

    _avisar();
  }

  void _limpiarNivel() {
    _subcategorias = const <HomeSubcategoria>[];
    _productosNivel = const <HomeProducto>[];
    _errorNivel = null;
    _cargandoNivel = false;
  }

  Future<void> _cargarSubcategoriasDelNivel() async {
    final HomeContexto? c = _contexto;
    final HomeCategoria? categoria = pasoActual?.categoria;
    if (c == null || categoria == null) return;

    _cargandoNivel = true;
    _errorNivel = null;
    _subcategorias = const <HomeSubcategoria>[];
    _avisar();

    try {
      final List<HomeSubcategoria> crudas = await _gateway.subcategorias(
        idsCategorias: categoria.idsConsulta,
        contexto: c,
      );
      // Colapso por nombre: un grupo de 208 "Alimentos" trae 208 subcategorías
      // homónimas y el drawer no puede enseñar 208 entradas iguales.
      _subcategorias = HomeSubcategoria.agruparPorNombre(crudas);
    } catch (e) {
      debugPrint('❌ HomeController.subcategorias: $e');
      _errorNivel = 'No se pudieron cargar las subcategorías.';
    } finally {
      _cargandoNivel = false;
      _avisar();
    }
  }

  Future<void> _cargarProductosDelNivel() async {
    final HomeContexto? c = _contexto;
    final HomePasoDrawer? paso = pasoActual;
    final HomeCategoria? categoria = paso?.categoria;
    if (c == null || paso == null || categoria == null) return;

    _cargandoNivel = true;
    _errorNivel = null;
    _productosNivel = const <HomeProducto>[];
    _avisar();

    try {
      final List<HomeProducto> todos = await _gateway.productos(
        contexto: c,
        idsCategorias: categoria.idsConsulta,
      );

      final HomeSubcategoria? sub = paso.subcategoria;
      _productosNivel =
          sub == null
              ? todos
              // El filtro por subcategoría se hace aquí, en el cliente, porque se
              // reutiliza la RPC por categoría en vez de crear una RPC nueva. Hay
              // que mirar TODOS los ids del grupo de la subcategoría: un grupo
              // colapsado tiene subcategorías homónimas con ids distintos.
              : todos
                  .where(
                    (HomeProducto p) =>
                        p.idSubcategoria != null &&
                        sub.idsConsulta.contains(p.idSubcategoria),
                  )
                  .toList();

      _productosNivel = _ordenarProductos(_productosNivel);
    } catch (e) {
      debugPrint('❌ HomeController.productos: $e');
      _errorNivel = 'No se pudieron cargar los productos.';
    } finally {
      _cargandoNivel = false;
      _avisar();
    }
  }

  static List<HomeProducto> _ordenarProductos(List<HomeProducto> lista) {
    final List<HomeProducto> copia = List<HomeProducto>.of(lista);
    // Con stock primero: en un TPV lo que se puede vender ya debe estar arriba.
    copia.sort((HomeProducto a, HomeProducto b) {
      if (a.disponible != b.disponible) return a.disponible ? -1 : 1;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });
    return copia;
  }

  /// Reintenta el nivel actual del drawer tras un error.
  Future<void> reintentarNivel() async {
    final HomePasoDrawer? paso = pasoActual;
    if (paso == null) return;

    switch (paso.nivel) {
      case HomeNivelDrawer.categorias:
        _limpiarNivel();
        _avisar();
      case HomeNivelDrawer.subcategorias:
        await _cargarSubcategoriasDelNivel();
      case HomeNivelDrawer.productos:
        await _cargarProductosDelNivel();
    }
  }
}
