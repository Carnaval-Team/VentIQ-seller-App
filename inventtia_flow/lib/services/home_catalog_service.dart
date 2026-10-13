import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/servicio.dart';
import '../utils/horario_atencion.dart';
import '../utils/precio_reserva.dart';
import 'campana_service.dart';
import 'coleccion_service.dart';
import 'promocion_service.dart';

/// Categoría real del catálogo, tomada de `flow.nom_tipo_actividad_servicio`.
///
/// No es una taxonomía inventada: es exactamente lo que el administrador asigna
/// al crear un servicio. Desde la migración
/// `47_categorias_reales_subcategorias.sql` la tabla tiene dos niveles, así que
/// cada categoría raíz trae sus [subcategorias] anidadas: el Home pinta el riel
/// y, al tocar una categoría, los chips de debajo sin otra petición.
class HomeCatalogCategory {
  const HomeCatalogCategory({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.subcategorias = const <HomeCatalogCategory>[],
  });

  /// `null` representa la opción "Todas".
  final int? id;
  final String codigo;
  final String nombre;

  /// Subcategorías activas de esta categoría. Vacío en una subcategoría y en
  /// "Todas".
  final List<HomeCatalogCategory> subcategorias;

  bool get esTodas => id == null;

  bool get tieneSubcategorias => subcategorias.isNotEmpty;

  static const HomeCatalogCategory todas = HomeCatalogCategory(
    id: null,
    codigo: '',
    nombre: 'Todas',
  );

  factory HomeCatalogCategory.fromJson(Map<String, dynamic> json) =>
      HomeCatalogCategory(
        id: (json['id'] as num).toInt(),
        codigo: json['codigo'] as String? ?? '',
        nombre: json['nombre'] as String? ?? 'General',
        subcategorias: ((json['subcategorias'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (e) => HomeCatalogCategory.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .where((c) => c.nombre.trim().isNotEmpty)
            .toList(growable: false),
      );
}

/// Tarjeta del Home construida **solo** con campos que existen en `flow`.
///
/// El rating y el número de reseñas **sí** son reales desde el Paso 4: salen de
/// `flow.resena` vía `resenas_por_servicio`. Un servicio sin reseñas deja ambos
/// en `null` (`totalResenas == 0`), y la tarjeta no debe pintar estrellas ni un
/// "0.0": no se le supone una valoración.
///
/// Los campos que siguen sin existir son distancia, descuento y duración. Ver
/// `lib/config/home_features.dart` para el estado de cada uno.
class HomeCatalogItem {
  const HomeCatalogItem({
    required this.id,
    required this.title,
    required this.venue,
    required this.category,
    this.subcategoria,
    this.price,
    this.currency,
    this.imageUrl,
    this.estadoHorario = EstadoHorario.desconocido,
    this.horarioTexto = '',
    this.horarioDetalle,
    this.direccion,
    this.provincia,
    this.pais,
    this.permiteReservaDirecta = false,
    this.cantidadMaxCapacidad = 1,
    this.rating,
    this.totalResenas = 0,
    this.promocion,
    this.localServicio,
    this.lugaresSemana,
  });

  /// `flow.local_servicio.id`.
  final int id;

  /// Nombre del servicio.
  final String title;

  /// Nombre del local.
  final String venue;

  /// Tipo de actividad real (`nom_tipo_actividad_servicio`). Desde la migración
  /// 47 es la **categoría** (el padre), no la hoja a la que apunta el servicio.
  final HomeCatalogCategory category;

  /// Subcategoría real del servicio, o `null` si quedó en la categoría sin
  /// subcategoría. Lo resuelve el servidor en el feed.
  final HomeCatalogCategory? subcategoria;

  /// Precio base de la moneda por defecto. `null` cuando el servicio no tiene
  /// precio configurado (`config_precio = '{}'`), caso frecuente en producción.
  final double? price;

  /// Moneda de [price].
  final String? currency;

  final String? imageUrl;

  /// Estado deducido de `app_dat_locales.horario_atencion`.
  final EstadoHorario estadoHorario;

  /// Texto original del horario, para mostrarlo tal cual.
  final String horarioTexto;

  /// Horario estructurado (`app_dat_locales.horario_detalle`), si el admin usó
  /// el constructor de días + horas. Manda sobre [horarioTexto] al interpretar.
  final Map<String, dynamic>? horarioDetalle;

  final String? direccion;
  final String? provincia;
  final String? pais;

  final bool permiteReservaDirecta;
  final int cantidadMaxCapacidad;

  /// Promedio real de `flow.resena`, o `null` si el servicio no tiene ninguna.
  final double? rating;

  /// Cuántas reseñas respaldan [rating].
  final int totalResenas;

  /// Promoción vigente que aplica a este servicio, si hay alguna.
  ///
  /// Es **de referencia** para el badge del Home: se calcula sobre el precio
  /// base, porque aquí no se conocen las opciones que elegirá el cliente (que
  /// pueden cambiar el precio por reglas). El importe que se cobra lo fija el
  /// servidor al confirmar, con la misma lógica compartida.
  final Promocion? promocion;

  /// Entidad original, para navegar al detalle sin volver a consultar.
  final LocalServicio? localServicio;

  /// Lugares reservados en la semana en curso, **solo** en el ranking semanal.
  ///
  /// `null` en el feed normal. Es el numero que ordena
  /// `cliente_ranking_semanal`, asi que pintarlo es lo que explica la posicion:
  /// sin el, las posiciones 1-2-3 serian decorativas.
  final int? lugaresSemana;

  /// `"11 lugares reservados"`, o `null` si el item no viene del ranking.
  String? get lugaresSemanaLabel {
    final n = lugaresSemana;
    if (n == null) return null;
    return n == 1 ? '1 lugar reservado' : '$n lugares reservados';
  }

  /// Precio con la promoción aplicada, o el de lista si no hay promo.
  double? get precioConPromocion {
    final lista = price;
    if (lista == null) return null;
    final p = promocion;
    if (p == null) return null;
    final d = p.esPorcentaje
        ? lista * p.valor / 100
        : (p.valor > lista ? lista : p.valor);
    final total = lista - d;
    return total < 0 ? 0 : total;
  }

  /// `true` cuando hay promo y rebaja de verdad el precio base.
  bool get tieneDescuento {
    final con = precioConPromocion;
    return promocion != null && price != null && con != null && con < price!;
  }

  /// `true` cuando hay valoración real que mostrar.
  bool get tieneValoracion => totalResenas > 0 && (rating ?? 0) > 0;

  /// `true` cuando se puede afirmar si el local está abierto.
  bool get horarioConocido => estadoHorario != EstadoHorario.desconocido;

  bool get abiertoAhora => estadoHorario == EstadoHorario.abierto;

  /// `"18 USD"`, o `null` cuando no hay precio configurado.
  String? get priceLabel {
    final valor = price;
    if (valor == null) return null;
    final monto = valor == valor.roundToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(2);
    return '$monto ${currency ?? 'USD'}';
  }

  /// Ubicación legible sin duplicados: `"Villa Clara Province, Cuba"`.
  String? get ubicacion {
    final partes = <String>[
      if (provincia != null && provincia!.trim().isNotEmpty) provincia!.trim(),
      if (pais != null && pais!.trim().isNotEmpty) pais!.trim(),
    ];
    return partes.isEmpty ? null : partes.join(', ');
  }

  /// Etiquetas derivadas de datos reales (no decorativas).
  List<String> get tags => <String>[
    if (permiteReservaDirecta) 'Reserva directa',
    if (cantidadMaxCapacidad > 1) 'Hasta $cantidadMaxCapacidad por reserva',
  ];
}

class HomeCatalogPage {
  const HomeCatalogPage({
    required this.items,
    required this.hasMore,
    required this.page,
    required this.total,
  });

  final List<HomeCatalogItem> items;
  final bool hasMore;
  final int page;

  /// Total de coincidencias antes de paginar.
  final int total;
}

/// Adaptador de lectura del Home.
///
/// Fuente única: `flow.cliente_home_feed(...)` (migración 35), que devuelve el
/// catálogo ya filtrado junto con las categorías, las colecciones, los
/// patrocinados y los contadores del usuario. Se lee una vez y se pagina en
/// memoria para que recorrer el feed no dispare una petición por tarjeta.
///
/// A diferencia de la versión anterior, **no hay catálogo de respaldo
/// inventado**: si la lectura falla, el error sube al llamador para que la
/// pantalla muestre un estado de error en lugar de negocios inexistentes.
/// Contadores que el shell del Home pinta junto al catálogo.
///
/// Es un **snapshot** que llega con el feed: ahorra las lecturas de arranque en
/// frío (una sola petición ya deja los badges puestos). Una vez que los
/// providers con tiempo real tienen dato (`NotificacionProvider`,
/// `ReservasProvider`), ellos mandan, para no tener dos fuentes del mismo número
/// discutiendo.
class HomeContadores {
  const HomeContadores({this.notificaciones = 0, this.reservas = 0});

  /// Notificaciones sin leer del usuario.
  final int notificaciones;

  /// Reservas en estado `Reservado`: las propias y las hechas para terceros.
  final int reservas;

  static const HomeContadores vacio = HomeContadores();

  factory HomeContadores.fromJson(Map<String, dynamic>? json) {
    if (json == null) return vacio;
    return HomeContadores(
      notificaciones: (json['notificaciones'] as num?)?.toInt() ?? 0,
      reservas: (json['reservas'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Todo lo que el Home necesita para pintarse, en **una** petición
/// (`flow.cliente_home_feed`).
///
/// Antes el Home encadenaba ~6 lecturas y podía quedar a medio actualizar
/// (catálogo nuevo con colecciones viejas, o al revés). Ahora llega un solo
/// objeto: o está todo lo nuevo, o nada.
///
/// No incluye las reseñas recientes ni la fidelidad: son secciones
/// independientes del usuario y se refrescan por su cuenta.
class HomeFeed {
  const HomeFeed({
    required this.items,
    required this.total,
    this.hasMore = false,
    this.nextCursor,
    this.categorias = const <HomeCatalogCategory>[HomeCatalogCategory.todas],
    this.colecciones = const <Coleccion>[],
    this.patrocinados = const <CampanaPatrocinada>[],
    this.contadores = HomeContadores.vacio,
  });

  /// Ítems que cumplen los filtros, **ya ordenados por el servidor**.
  final List<HomeCatalogItem> items;

  /// Total de coincidencias.
  final int total;

  /// Contrato de paginación. Hoy el servidor devuelve el catálogo completo (7
  /// filas), así que siempre llega `false`/`null`: se deja listo para no tener
  /// que cambiar la forma de la respuesta cuando el catálogo crezca.
  final bool hasMore;
  final int? nextCursor;

  /// Nomenclador para el riel, con "Todas" primero.
  final List<HomeCatalogCategory> categorias;

  /// Colecciones temáticas vigentes, curadas por el superadmin.
  final List<Coleccion> colecciones;

  /// Campañas patrocinadas vigentes.
  final List<CampanaPatrocinada> patrocinados;

  /// Snapshot de los contadores del usuario.
  final HomeContadores contadores;
}

class HomeCatalogService {
  static const int defaultPageSize = 6;

  static const String _schema = 'flow';

  static List<HomeCatalogItem>? _cachedCatalog;
  static Future<List<HomeCatalogItem>>? _loadingCatalog;

  /// Una sola petición que trae el catálogo ya filtrado y las secciones curadas.
  ///
  /// Los filtros los aplica el servidor (`cliente_home_feed`), que además
  /// resuelve el nombre de la categoría (`ta.nombre`) para el riel y respeta el
  /// orden curado de la colección. Por eso aquí no hay que cruzar ni ordenar
  /// nada: se pinta lo que llega.
  ///
  /// El único filtro que NO viaja es "Solo abiertos": el horario se interpreta
  /// con [HorarioAtencion] en [paginar], a propósito.
  static Future<HomeFeed> fetchFeed({
    String query = '',
    HomeCatalogCategory category = HomeCatalogCategory.todas,
    HomeCatalogCategory? subcategoria,
    String? provincia,
    int? idColeccion,
    bool topRated = false,
  }) async {
    final res = await Supabase.instance.client
        .schema(_schema)
        .rpc(
          'cliente_home_feed',
          params: <String, dynamic>{
            'p_query': query.trim().isEmpty ? null : query.trim(),
            'p_id_categoria': category.esTodas ? null : category.id,
            'p_provincia': (provincia == null || provincia.trim().isEmpty)
                ? null
                : provincia.trim(),
            'p_id_coleccion': idColeccion,
            'p_mejor_valorados': topRated,
            // Solo se envía cuando hay subcategoría elegida. Así el Home sigue
            // funcionando contra la firma vieja del RPC (migración 48 sin
            // aplicar) para todo lo que no dependa de subcategorías.
            if (subcategoria != null && subcategoria.id != null)
              'p_id_subcategoria': subcategoria.id,
          },
        );

    final json = res is Map
        ? Map<String, dynamic>.from(res)
        : const <String, dynamic>{};
    final crudos = (json['items'] as List?) ?? const <dynamic>[];

    return HomeFeed(
      items: itemsDesdeFeed(crudos),
      total: (json['total'] as num?)?.toInt() ?? crudos.length,
      hasMore: json['has_more'] as bool? ?? false,
      nextCursor: (json['next_cursor'] as num?)?.toInt(),
      categorias: categoriasDesdeFeed(json),
      colecciones: _coleccionesDesdeFeed(json),
      patrocinados: _patrocinadosDesdeFeed(json),
      contadores: HomeContadores.fromJson(
        json['contadores'] is Map
            ? Map<String, dynamic>.from(json['contadores'] as Map)
            : null,
      ),
    );
  }

  /// Ranking semanal: los servicios con más lugares reservados esta semana.
  ///
  /// Va aparte del feed a propósito: es otra consulta (agrega `flow.agenda` en
  /// una ventana) y solo se pide cuando `HomeFeatures.rankingSemanal` está
  /// encendido.
  ///
  /// Reusa [_desdeItemFeed] porque el servidor devuelve la misma forma de item
  /// que el feed más `lugares_semana`, así que aquí no hay nada que adaptar. Si
  /// la migración 36 no está aplicada, el error sube y el bloque no se pinta.
  static Future<List<HomeCatalogItem>> fetchRankingSemanal({
    int limite = 5,
  }) async {
    final res = await Supabase.instance.client
        .schema(_schema)
        .rpc(
          'cliente_ranking_semanal',
          params: <String, dynamic>{'p_limite': limite},
        );
    if (res is! List) return const <HomeCatalogItem>[];
    return itemsDesdeFeed(res);
  }

  /// Convierte la lista cruda del RPC en items, **filtrando** los que no están
  /// publicados.
  ///
  /// Es `static` y público a propósito: es el único sitio donde se interpreta el
  /// contrato del RPC (categoría/subcategoría, `activo`, `tipo_actividad`), y se
  /// cubre con tests sin tocar Supabase.
  ///
  /// Red de seguridad del punto 3/4: el servidor ya filtra con
  /// `flow._ls_disponible` (local, servicio y local-servicio activos), pero el
  /// feed puede llegar cacheado o con las columnas `activo` ausentes si la
  /// migración 40 aún no se aplicó. [LocalServicio.activoEfectivo] decide con los
  /// tres valores y, si faltan, asume publicado: nunca oculta de más.
  static List<HomeCatalogItem> itemsDesdeFeed(List<dynamic> crudos) {
    final items = <HomeCatalogItem>[];
    for (final crudo in crudos) {
      if (crudo is! Map) continue;
      final json = Map<String, dynamic>.from(crudo);
      final ls = LocalServicio.fromJson(json);
      if (!ls.activoEfectivo) continue;
      items.add(_desdeItemFeed(json, item: ls));
    }
    return List.unmodifiable(items);
  }

  /// Riel de categorías a partir de `metadata.categorias`.
  ///
  /// El servidor devuelve las raíces activas (cada una con sus subcategorías
  /// anidadas) y en el orden curado por `orden`. "Todas" lo añade el cliente
  /// porque no es una categoría real, es la ausencia de filtro.
  ///
  /// Público por el mismo motivo que [itemsDesdeFeed]: es contrato, no detalle.
  static List<HomeCatalogCategory> categoriasDesdeFeed(
    Map<String, dynamic> json,
  ) {
    final meta = json['metadata'];
    final crudas = meta is Map ? (meta['categorias'] as List?) : null;
    final categorias = (crudas ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => HomeCatalogCategory.fromJson(Map<String, dynamic>.from(e)))
        .where((c) => c.nombre.trim().isNotEmpty)
        .toList();
    return <HomeCatalogCategory>[HomeCatalogCategory.todas, ...categorias];
  }

  static List<Coleccion> _coleccionesDesdeFeed(Map<String, dynamic> json) {
    final crudas = json['colecciones'];
    if (crudas is! List) return const <Coleccion>[];
    return crudas
        .whereType<Map>()
        .map((e) => Coleccion.fromJson(Map<String, dynamic>.from(e)))
        // Red de seguridad: el RPC ya excluye las vacías.
        .where((c) => c.tieneServicios)
        .toList();
  }

  static List<CampanaPatrocinada> _patrocinadosDesdeFeed(
    Map<String, dynamic> json,
  ) {
    final crudos = json['patrocinados'];
    if (crudos is! List) return const <CampanaPatrocinada>[];
    return crudos
        .whereType<Map>()
        .map((e) => CampanaPatrocinada.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Troceado en páginas y filtro de horario, en memoria y sin red.
  ///
  /// La búsqueda, la categoría, la provincia, la colección y el orden los aplica
  /// el servidor en [fetchFeed], que es la única implementación de esas reglas.
  /// Aquí queda **solo** lo que no puede ir en SQL sin duplicarse:
  ///
  /// - `onlyOpen`: se interpreta el texto libre de `horario_atencion` con
  ///   [HorarioAtencion]. Portarlo a SQL sería una segunda implementación de la
  ///   misma regla, y si diverge el feed diría "abierto" donde el detalle dice
  ///   "Horario no disponible".
  /// - el troceado en páginas.
  ///
  /// Está separado de [fetchFeed] para poder probarlo con un catálogo
  /// construido a mano, sin tocar Supabase.
  static HomeCatalogPage paginar({
    required List<HomeCatalogItem> catalogo,
    required int page,
    int pageSize = defaultPageSize,
    bool onlyOpen = false,
    DateTime? ahora,
  }) {
    final momento = ahora ?? DateTime.now();

    final filtrados = onlyOpen
        ? catalogo.where((item) {
            // Solo se afirma "abierto ahora" cuando el horario es interpretable.
            // Se prefiere el detalle estructurado (punto 10): con él, un local
            // que abre "Lun, Mié, Vie" se filtra por esos tres días y no por
            // lunes-viernes.
            final horario = HorarioAtencion.parseConDetalle(
              item.horarioTexto,
              item.horarioDetalle,
            );
            return horario.evaluar(momento) == EstadoHorario.abierto;
          }).toList()
        : catalogo;

    final paginaSegura = page < 1 ? 1 : page;
    final inicio = (paginaSegura - 1) * pageSize;
    if (inicio >= filtrados.length) {
      return HomeCatalogPage(
        items: const <HomeCatalogItem>[],
        hasMore: false,
        page: paginaSegura,
        total: filtrados.length,
      );
    }
    final fin = (inicio + pageSize).clamp(0, filtrados.length);
    return HomeCatalogPage(
      items: filtrados.sublist(inicio, fin),
      hasMore: fin < filtrados.length,
      page: paginaSegura,
      total: filtrados.length,
    );
  }

  /// Ítem del catálogo **completo** por `id_local_servicio`.
  ///
  /// El Home solo tiene cargada una página, pero una campaña patrocinada puede
  /// destacar un servicio que esté en otra. Se busca sobre el catálogo ya
  /// cacheado, así que no supone una petición extra.
  static Future<HomeCatalogItem?> itemPorId(int idLocalServicio) async {
    try {
      final todos = await _getCatalog();
      for (final item in todos) {
        if (item.id == idLocalServicio) return item;
      }
    } catch (_) {
      // Sin catálogo no se puede abrir la campaña; el llamador avisa.
    }
    return null;
  }

  static Future<void> clearCache() async {
    _cachedCatalog = null;
    _loadingCatalog = null;
  }

  static Future<List<HomeCatalogItem>> _getCatalog() {
    final cacheado = _cachedCatalog;
    if (cacheado != null) return Future.value(cacheado);
    return _loadingCatalog ??= _loadCatalog();
  }

  /// Catálogo completo, para [itemPorId].
  ///
  /// Una campaña patrocinada puede destacar un servicio que no esté en la página
  /// visible, así que hace falta el catálogo entero. Se pide al mismo feed sin
  /// filtros: no hay una segunda forma de leer el catálogo.
  static Future<List<HomeCatalogItem>> _loadCatalog() async {
    try {
      final feed = await fetchFeed();
      _cachedCatalog = feed.items;
      return feed.items;
    } catch (_) {
      // Permite reintentar: sin esto un fallo de red dejaría el Future
      // compartido cacheado con el error para siempre.
      _loadingCatalog = null;
      rethrow;
    }
  }

  /// Convierte un ítem de `cliente_home_feed` en el modelo del Home.
  ///
  /// El servidor devuelve cada ítem con la misma forma anidada que
  /// `cliente_obtener_servicios` (`servicio` / `local` / `entidad`), así que se
  /// reusa [LocalServicio.fromJson] y la navegación al detalle sigue igual.
  /// `rating` y `promocion` ya vienen resueltos por el servidor: no hay nada que
  /// cruzar en el cliente.
  static HomeCatalogItem _desdeItemFeed(
    Map<String, dynamic> json, {
    LocalServicio? item,
  }) {
    item ??= LocalServicio.fromJson(json);
    final servicio = item.servicio;
    final local = item.local;
    final precio = precioBaseDe(servicio?.configPrecio);
    final horario = HorarioAtencion.parseConDetalle(
      local?.horarioAtencion,
      local?.horarioDetalle,
    );
    final promocion = json['promocion'];

    // [47] La hoja a la que apunta el servicio y su padre. El servidor emite la
    // categoría ya resuelta (`categoria_*`), pero el `id` y el `codigo` de la
    // categoría hay que tomarlos del padre cuando la hoja es una subcategoría:
    // si no, el riel compararía el id de la hoja con el de la categoría y no
    // marcaría nada como seleccionado.
    final idHoja = servicio?.idTipoActividad;
    final idPadre = servicio?.idPadreTipoActividad;
    final codigoCategoria = _primeraNoVacia(
      json['categoria_codigo'] as String?,
      servicio?.tipoActividad,
    );

    final subcategoria = _subcategoriaDeItem(json, servicio, idHoja, idPadre);

    return HomeCatalogItem(
      id: item.id,
      title: servicio?.nombre ?? 'Servicio sin nombre',
      venue: local?.nombre ?? 'Local sin nombre',
      category: HomeCatalogCategory(
        id: idPadre ?? idHoja,
        codigo: codigoCategoria ?? '',
        nombre: _nombreCategoriaDeItem(json, servicio),
      ),
      subcategoria: subcategoria,
      price: precio?.precio,
      currency: precio?.moneda,
      imageUrl: _primeraNoVacia(servicio?.foto, local?.foto),
      estadoHorario: horario.evaluar(DateTime.now()),
      horarioTexto: local?.horarioAtencion?.trim() ?? '',
      horarioDetalle: local?.horarioDetalle,
      direccion: _primeraNoVacia(local?.direccion, null),
      provincia: _primeraNoVacia(local?.provincia, null),
      pais: _primeraNoVacia(local?.pais, null),
      permiteReservaDirecta: item.permiteReservaDirecta,
      cantidadMaxCapacidad: item.cantidadMaxCapacidad,
      // Sin reseñas el servidor manda `rating` nulo: la tarjeta no pinta
      // estrellas, en vez de inventar un promedio.
      rating: (json['rating'] as num?)?.toDouble(),
      totalResenas: (json['total_resenas'] as num?)?.toInt() ?? 0,
      promocion: promocion is Map
          ? Promocion.fromJson(Map<String, dynamic>.from(promocion))
          : null,
      localServicio: item,
      // Solo lo manda `cliente_ranking_semanal`; el feed no lo trae.
      lugaresSemana: (json['lugares_semana'] as num?)?.toInt(),
    );
  }

  /// Subcategoría del ítem, o `null` si el servicio quedó en la categoría.
  ///
  /// El id de la subcategoría es el de la HOJA (`servicio.id_tipo_actividad`),
  /// que el feed ya manda: no hace falta un campo extra en el RPC.
  static HomeCatalogCategory? _subcategoriaDeItem(
    Map<String, dynamic> json,
    Servicio? servicio,
    int? idHoja,
    int? idPadre,
  ) {
    if (idPadre == null || idHoja == null) return null;
    final nombre = (json['subcategoria_nombre'] as String?)?.trim();
    if (nombre == null || nombre.isEmpty) return null;
    return HomeCatalogCategory(
      id: idHoja,
      codigo: (json['subcategoria_codigo'] as String?)?.trim() ?? '',
      nombre: nombre,
    );
  }

  /// Nombre de la categoría tal como lo decidió el servidor.
  ///
  /// `categoria_nombre` llega vacío cuando la categoría está apagada (el RPC lo
  /// anula a propósito), y entonces se cae al código legible y, en último caso,
  /// a "General". Es la misma regla que había antes, cuando el cliente solo
  /// conocía el nomenclador activo.
  static String _nombreCategoriaDeItem(
    Map<String, dynamic> json,
    Servicio? servicio,
  ) {
    final nombre = (json['categoria_nombre'] as String?)?.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;
    final codigo = (json['categoria_codigo'] as String?)?.trim();
    if (codigo != null && codigo.isNotEmpty) {
      return codigo.replaceAll('_', ' ');
    }
    final delServicio = servicio?.tipoActividad;
    if (delServicio != null && delServicio.trim().isNotEmpty) {
      return delServicio.replaceAll('_', ' ');
    }
    return 'General';
  }

  static String? _primeraNoVacia(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty) return a.trim();
    if (b != null && b.trim().isNotEmpty) return b.trim();
    return null;
  }
}
