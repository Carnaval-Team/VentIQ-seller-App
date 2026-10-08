import '../models/servicio.dart';
import '../utils/horario_atencion.dart';
import '../utils/precio_reserva.dart';
import 'catalogo_service.dart';

/// Categoría real del catálogo, tomada de `flow.nom_tipo_actividad_servicio`.
///
/// No es una taxonomía inventada: es exactamente lo que el administrador asigna
/// al crear un servicio. Antes de la migración
/// `22_categorias_marketplace.sql` la tabla solo tenía `general` y
/// `transporte_omnibus`; ahora tiene la taxonomía sembrada, y esta clase la
/// representa sin cambios.
class HomeCatalogCategory {
  const HomeCatalogCategory({
    required this.id,
    required this.codigo,
    required this.nombre,
  });

  /// `null` representa la opción "Todas".
  final int? id;
  final String codigo;
  final String nombre;

  bool get esTodas => id == null;

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
      );
}

/// Tarjeta del Home construida **solo** con campos que existen en `flow`.
///
/// Los campos de marketplace (rating, reseñas, distancia, descuento, duración)
/// no se incluyen a propósito: no hay columnas que los respalden. Ver
/// `lib/config/home_features.dart` para el estado de cada uno.
class HomeCatalogItem {
  const HomeCatalogItem({
    required this.id,
    required this.title,
    required this.venue,
    required this.category,
    this.price,
    this.currency,
    this.imageUrl,
    this.estadoHorario = EstadoHorario.desconocido,
    this.horarioTexto = '',
    this.direccion,
    this.provincia,
    this.pais,
    this.permiteReservaDirecta = false,
    this.cantidadMaxCapacidad = 1,
    this.localServicio,
  });

  /// `flow.local_servicio.id`.
  final int id;

  /// Nombre del servicio.
  final String title;

  /// Nombre del local.
  final String venue;

  /// Tipo de actividad real (`nom_tipo_actividad_servicio`).
  final HomeCatalogCategory category;

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

  final String? direccion;
  final String? provincia;
  final String? pais;

  final bool permiteReservaDirecta;
  final int cantidadMaxCapacidad;

  /// Entidad original, para navegar al detalle sin volver a consultar.
  final LocalServicio? localServicio;

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
/// Fuente única: `flow.cliente_obtener_servicios(...)`. Se lee una vez y se
/// pagina en memoria para que recorrer el feed no dispare una petición por
/// tarjeta. Cuando exista el RPC paginado `cliente_home_feed` descrito en
/// `plan.md`, este es el único archivo que debe cambiar.
///
/// A diferencia de la versión anterior, **no hay catálogo de respaldo
/// inventado**: si la lectura falla, el error sube al llamador para que la
/// pantalla muestre un estado de error en lugar de negocios inexistentes.
class HomeCatalogService {
  static const int defaultPageSize = 6;

  static List<HomeCatalogItem>? _cachedCatalog;
  static List<HomeCatalogCategory>? _cachedCategories;
  static Future<List<HomeCatalogItem>>? _loadingCatalog;
  static Future<List<HomeCatalogCategory>>? _loadingCategories;

  static Future<HomeCatalogPage> fetchPage({
    required int page,
    int pageSize = defaultPageSize,
    String query = '',
    HomeCatalogCategory category = HomeCatalogCategory.todas,
    bool onlyOpen = false,
    String? provincia,
    DateTime? ahora,
  }) async {
    final catalogo = await _getCatalog();
    return paginar(
      catalogo: catalogo,
      page: page,
      pageSize: pageSize,
      query: query,
      category: category,
      onlyOpen: onlyOpen,
      provincia: provincia,
      ahora: ahora,
    );
  }

  /// Filtrado y paginado en memoria, sin acceso a red.
  ///
  /// Está separado de [fetchPage] para poder probarlo con un catálogo
  /// construido a mano. Cuando exista el RPC paginado `cliente_home_feed`,
  /// esta función desaparece y el servidor aplica los mismos filtros.
  static HomeCatalogPage paginar({
    required List<HomeCatalogItem> catalogo,
    required int page,
    int pageSize = defaultPageSize,
    String query = '',
    HomeCatalogCategory category = HomeCatalogCategory.todas,
    bool onlyOpen = false,
    String? provincia,
    DateTime? ahora,
  }) {
    final momento = ahora ?? DateTime.now();
    final normalizada = _sinAcentos(query.trim().toLowerCase());
    final provinciaBuscada = provincia?.trim().toLowerCase();

    final filtrados = catalogo.where((item) {
      if (!category.esTodas && item.category.id != category.id) return false;

      if (provinciaBuscada != null && provinciaBuscada.isNotEmpty) {
        final delItem = item.provincia?.trim().toLowerCase();
        if (delItem != provinciaBuscada) return false;
      }

      if (normalizada.isNotEmpty) {
        final heno = _sinAcentos(
          '${item.title} ${item.venue} ${item.category.nombre}'.toLowerCase(),
        );
        if (!heno.contains(normalizada)) return false;
      }

      if (onlyOpen) {
        // Solo se afirma "abierto ahora" cuando el horario es interpretable.
        final horario = HorarioAtencion.parse(item.horarioTexto);
        if (horario.evaluar(momento) != EstadoHorario.abierto) return false;
      }

      return true;
    }).toList();

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

  /// Categorías reales para el riel del Home.
  static Future<List<HomeCatalogCategory>> getCategorias() {
    final cacheadas = _cachedCategories;
    if (cacheadas != null) return Future.value(cacheadas);
    return _loadingCategories ??= _loadCategorias();
  }

  static Future<void> clearCache() async {
    _cachedCatalog = null;
    _cachedCategories = null;
    _loadingCatalog = null;
    _loadingCategories = null;
  }

  static Future<List<HomeCatalogItem>> _getCatalog() {
    final cacheado = _cachedCatalog;
    if (cacheado != null) return Future.value(cacheado);
    return _loadingCatalog ??= _loadCatalog();
  }

  static Future<List<HomeCatalogCategory>> _loadCategorias() async {
    try {
      final filas = await CatalogoService.getTiposActividadServicio();
      final categorias = filas
          .map(HomeCatalogCategory.fromJson)
          .where((c) => c.nombre.trim().isNotEmpty)
          .toList();

      // Orden del riel: alfabético, con "General" al final porque es el cajón
      // de sastre (el valor por defecto de `id_tipo_actividad`), no una
      // categoría que el cliente busque. "Todas" va siempre primero.
      categorias.sort((a, b) {
        final aGeneral = a.codigo == 'general';
        final bGeneral = b.codigo == 'general';
        if (aGeneral != bGeneral) return aGeneral ? 1 : -1;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });

      _cachedCategories = <HomeCatalogCategory>[
        HomeCatalogCategory.todas,
        ...categorias,
      ];
    } catch (_) {
      // Sin nomenclador el riel queda en "Todas": es preferible a inventar
      // categorías que ningún servicio puede tener.
      _cachedCategories = const <HomeCatalogCategory>[
        HomeCatalogCategory.todas,
      ];
    }
    return _cachedCategories!;
  }

  static Future<List<HomeCatalogItem>> _loadCatalog() async {
    try {
      final categorias = await getCategorias();
      final nombrePorId = <int, String>{
        for (final c in categorias)
          if (c.id != null) c.id!: c.nombre,
      };
      final servicios = await CatalogoService.getLocalServicios();
      final mapeados = servicios
          .map((item) => _desdeLocalServicio(item, nombrePorId))
          .toList();
      _cachedCatalog = mapeados;
      return mapeados;
    } catch (_) {
      // Permite reintentar: sin esto un fallo de red dejaría el Future
      // compartido cacheado con el error para siempre.
      _loadingCatalog = null;
      rethrow;
    }
  }

  static HomeCatalogItem _desdeLocalServicio(
    LocalServicio item,
    Map<int, String> nombrePorTipo,
  ) {
    final servicio = item.servicio;
    final local = item.local;
    final precio = precioBaseDe(servicio?.configPrecio);
    final horario = HorarioAtencion.parse(local?.horarioAtencion);
    return HomeCatalogItem(
      id: item.id,
      title: servicio?.nombre ?? 'Servicio sin nombre',
      venue: local?.nombre ?? 'Local sin nombre',
      category: HomeCatalogCategory(
        id: servicio?.idTipoActividad,
        codigo: servicio?.tipoActividad ?? '',
        nombre: _nombreCategoria(servicio, nombrePorTipo),
      ),
      price: precio?.precio,
      currency: precio?.moneda,
      imageUrl: _primeraNoVacia(servicio?.foto, local?.foto),
      estadoHorario: horario.evaluar(DateTime.now()),
      horarioTexto: local?.horarioAtencion?.trim() ?? '',
      direccion: _primeraNoVacia(local?.direccion, null),
      provincia: _primeraNoVacia(local?.provincia, null),
      pais: _primeraNoVacia(local?.pais, null),
      permiteReservaDirecta: item.permiteReservaDirecta,
      cantidadMaxCapacidad: item.cantidadMaxCapacidad,
      localServicio: item,
    );
  }

  static String _nombreCategoria(
    Servicio? servicio,
    Map<int, String> nombrePorTipo,
  ) {
    final id = servicio?.idTipoActividad;
    if (id != null) {
      final nombre = nombrePorTipo[id];
      if (nombre != null && nombre.trim().isNotEmpty) return nombre;
    }
    final codigo = servicio?.tipoActividad;
    if (codigo != null && codigo.trim().isNotEmpty) {
      return codigo.replaceAll('_', ' ');
    }
    return 'General';
  }

  static String? _primeraNoVacia(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty) return a.trim();
    if (b != null && b.trim().isNotEmpty) return b.trim();
    return null;
  }

  static String _sinAcentos(String valor) => valor
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}
