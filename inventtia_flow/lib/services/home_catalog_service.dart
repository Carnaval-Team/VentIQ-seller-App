import '../models/servicio.dart';
import 'catalogo_service.dart';

/// View model ligero para las tarjetas del Home.
///
/// El catálogo real todavía no tiene campos de marketplace como rating,
/// distancia o descuento. Esos campos son opcionales y se mantienen aquí para
/// que el Home pueda renderizarse hoy sin inventar columnas en la base de datos.
class HomeCatalogItem {
  final int id;
  final String title;
  final String venue;
  final String category;
  final double price;
  final String currency;
  final double? originalPrice;
  final int discount;
  final int durationMinutes;
  final String distance;
  final double rating;
  final int reviews;
  final bool isOpen;
  final bool verified;
  final bool availableNow;
  final String? imageUrl;
  final List<String> tags;
  final LocalServicio? localServicio;

  const HomeCatalogItem({
    required this.id,
    required this.title,
    required this.venue,
    required this.category,
    required this.price,
    this.currency = 'USD',
    this.originalPrice,
    this.discount = 0,
    this.durationMinutes = 45,
    this.distance = '1.2 km',
    this.rating = 4.8,
    this.reviews = 32,
    this.isOpen = true,
    this.verified = true,
    this.availableNow = true,
    this.imageUrl,
    this.tags = const [],
    this.localServicio,
  });

  String get priceLabel {
    final amount = price == price.roundToDouble()
        ? price.toStringAsFixed(0)
        : price.toStringAsFixed(2);
    return '$amount $currency';
  }
}

class HomeCatalogPage {
  final List<HomeCatalogItem> items;
  final bool hasMore;
  final bool isMock;
  final int page;

  const HomeCatalogPage({
    required this.items,
    required this.hasMore,
    required this.isMock,
    required this.page,
  });
}

/// Adaptador de lectura para el Home.
///
/// Mientras no exista el RPC paginado del Home, realiza una única lectura del
/// RPC existente y pagina en memoria. Así navegar por el feed no dispara una
/// petición por tarjeta. Cuando se publique el RPC/Edge Function definitivo,
/// este es el único punto que deberá cambiar.
class HomeCatalogService {
  static const int defaultPageSize = 6;
  static List<HomeCatalogItem>? _cachedCatalog;
  static Future<List<HomeCatalogItem>>? _loadingCatalog;
  static bool _usingMock = false;

  static Future<HomeCatalogPage> fetchPage({
    required int page,
    int pageSize = defaultPageSize,
    String query = '',
    String category = 'Todas',
    bool onlyOpen = false,
    bool topRated = false,
    bool nearMe = false,
  }) async {
    final catalog = await _getCatalog();
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = catalog.where((item) {
      final matchesCategory = category == 'Todas' || item.category == category;
      final matchesQuery =
          normalizedQuery.isEmpty ||
          item.title.toLowerCase().contains(normalizedQuery) ||
          item.venue.toLowerCase().contains(normalizedQuery) ||
          item.category.toLowerCase().contains(normalizedQuery);
      final matchesOpen = !onlyOpen || item.isOpen;
      final matchesRating = !topRated || item.rating >= 4.7;
      // Los datos actuales no exponen coordenadas de usuario; mientras tanto,
      // `nearMe` conserva los elementos con distancia conocida o cercana.
      final matchesDistance =
          !nearMe ||
          item.distance == 'Cerca de ti' ||
          item.distance.endsWith('km');
      return matchesCategory &&
          matchesQuery &&
          matchesOpen &&
          matchesRating &&
          matchesDistance;
    }).toList();

    final safePage = page < 1 ? 1 : page;
    final start = (safePage - 1) * pageSize;
    if (start >= filtered.length) {
      return HomeCatalogPage(
        items: const [],
        hasMore: false,
        isMock: _usingMock,
        page: safePage,
      );
    }
    final end = (start + pageSize).clamp(0, filtered.length);
    return HomeCatalogPage(
      items: filtered.sublist(start, end),
      hasMore: end < filtered.length,
      isMock: _usingMock,
      page: safePage,
    );
  }

  static Future<void> clearCache() async {
    _cachedCatalog = null;
    _loadingCatalog = null;
    _usingMock = false;
  }

  static Future<List<HomeCatalogItem>> _getCatalog() {
    final cached = _cachedCatalog;
    if (cached != null) return Future.value(cached);
    return _loadingCatalog ??= _loadCatalog();
  }

  static Future<List<HomeCatalogItem>> _loadCatalog() async {
    try {
      final services = await CatalogoService.getLocalServicios();
      final mapped = services.map(_fromLocalServicio).toList();
      if (mapped.isNotEmpty) {
        _cachedCatalog = mapped;
        _usingMock = false;
        return mapped;
      }
    } catch (_) {
      // La vista debe seguir siendo navegable durante el primer despliegue,
      // cuando el RPC o sus permisos aún no estén disponibles.
    }

    _usingMock = true;
    _cachedCatalog = _mockCatalog;
    return _cachedCatalog!;
  }

  static HomeCatalogItem _fromLocalServicio(LocalServicio item) {
    final servicio = item.servicio;
    final local = item.local;
    final config = servicio?.configPrecio;
    final defaultCurrency = config?.monedaDefault ?? 'USD';
    final basePrice =
        config?.preciosBase[defaultCurrency] ??
        (config?.preciosBase.values.isNotEmpty == true
            ? config!.preciosBase.values.first
            : 0);
    final category = _categoryFor(servicio?.nombre, servicio?.tipoActividad);
    final isOpen = _isOpen(local?.horarioAtencion);
    return HomeCatalogItem(
      id: item.id,
      title: servicio?.nombre ?? 'Servicio disponible',
      venue: local?.nombre ?? 'Establecimiento cercano',
      category: category,
      price: basePrice,
      currency: defaultCurrency,
      durationMinutes: _durationFor(category),
      distance: 'Cerca de ti',
      rating: 4.7,
      reviews: 24,
      isOpen: isOpen,
      verified: true,
      availableNow: item.permiteReservaDirecta || isOpen,
      imageUrl: servicio?.foto ?? local?.foto,
      tags: [if (item.permiteReservaDirecta) 'Reserva directa', 'Pago online'],
      localServicio: item,
    );
  }

  static bool _isOpen(String? schedule) {
    if (schedule == null || schedule.trim().isEmpty) return true;
    final value = schedule.toLowerCase();
    return !value.contains('cerrado');
  }

  static int _durationFor(String category) => switch (category) {
    'Transporte' => 60,
    'Salud' => 45,
    'Hogar' => 90,
    _ => 45,
  };

  static String _categoryFor(String? name, String? activity) {
    final value = '${name ?? ''} ${activity ?? ''}'.toLowerCase();
    if (value.contains('uñ') ||
        value.contains('manicur') ||
        value.contains('pedicur')) {
      return 'Uñas';
    }
    if (value.contains('ceja') || value.contains('pestañ')) {
      return 'Cejas & Pestañas';
    }
    if (value.contains('transport') ||
        value.contains('ómnibus') ||
        value.contains('taxi')) {
      return 'Transporte';
    }
    if (value.contains('salud') ||
        value.contains('méd') ||
        value.contains('doctor')) {
      return 'Salud';
    }
    if (value.contains('hogar') ||
        value.contains('repar') ||
        value.contains('plomer')) {
      return 'Hogar';
    }
    if (value.contains('mascot') || value.contains('veter')) return 'Mascotas';
    return 'Belleza';
  }

  static final List<HomeCatalogItem> _mockCatalog = [
    const HomeCatalogItem(
      id: 9001,
      title: 'Diseño de uñas gel',
      venue: 'Luna Studio',
      category: 'Uñas',
      price: 18,
      originalPrice: 24,
      discount: 25,
      durationMinutes: 60,
      distance: '0.8 km',
      rating: 4.9,
      reviews: 128,
      tags: ['Sin filas garantizado', 'Pago online'],
    ),
    const HomeCatalogItem(
      id: 9002,
      title: 'Corte + brushing',
      venue: 'Casa Aura',
      category: 'Belleza',
      price: 22,
      durationMinutes: 45,
      distance: '1.1 km',
      rating: 4.8,
      reviews: 96,
      tags: ['Wi-Fi', 'Reserva directa'],
    ),
    const HomeCatalogItem(
      id: 9003,
      title: 'Perfilado de cejas',
      venue: 'Marfil Beauty',
      category: 'Cejas & Pestañas',
      price: 12,
      originalPrice: 15,
      discount: 20,
      durationMinutes: 30,
      distance: '1.4 km',
      rating: 4.7,
      reviews: 74,
      tags: ['Abierto ahora'],
    ),
    const HomeCatalogItem(
      id: 9004,
      title: 'Ruta centro · ida y vuelta',
      venue: 'Moverte',
      category: 'Transporte',
      price: 9,
      currency: 'USD',
      durationMinutes: 60,
      distance: '2.0 km',
      rating: 4.6,
      reviews: 51,
      tags: ['Pago online', 'Reserva directa'],
    ),
    const HomeCatalogItem(
      id: 9005,
      title: 'Masaje relajante',
      venue: 'Alma Spa',
      category: 'Belleza',
      price: 30,
      originalPrice: 38,
      discount: 20,
      durationMinutes: 60,
      distance: '2.3 km',
      rating: 4.9,
      reviews: 142,
      tags: ['Wi-Fi', 'Sin filas garantizado'],
    ),
    const HomeCatalogItem(
      id: 9006,
      title: 'Consulta general',
      venue: 'Centro Vida',
      category: 'Salud',
      price: 25,
      durationMinutes: 30,
      distance: '2.7 km',
      rating: 4.8,
      reviews: 63,
      tags: ['Abierto ahora', 'Reserva directa'],
    ),
    const HomeCatalogItem(
      id: 9007,
      title: 'Limpieza profunda',
      venue: 'Hogar Listo',
      category: 'Hogar',
      price: 35,
      durationMinutes: 90,
      distance: '3.0 km',
      rating: 4.6,
      reviews: 44,
      tags: ['Pago online'],
    ),
    const HomeCatalogItem(
      id: 9008,
      title: 'Baño y cuidado',
      venue: 'Patitas Club',
      category: 'Mascotas',
      price: 16,
      durationMinutes: 45,
      distance: '3.4 km',
      rating: 4.8,
      reviews: 37,
      tags: ['Sin filas garantizado'],
    ),
    const HomeCatalogItem(
      id: 9009,
      title: 'Lifting de pestañas',
      venue: 'Luna Studio',
      category: 'Cejas & Pestañas',
      price: 20,
      originalPrice: 26,
      discount: 23,
      durationMinutes: 50,
      distance: '0.8 km',
      rating: 4.9,
      reviews: 88,
      tags: ['Reserva directa'],
    ),
    const HomeCatalogItem(
      id: 9010,
      title: 'Coloración express',
      venue: 'Casa Aura',
      category: 'Belleza',
      price: 40,
      durationMinutes: 90,
      distance: '1.1 km',
      rating: 4.7,
      reviews: 35,
      tags: ['Wi-Fi'],
    ),
    const HomeCatalogItem(
      id: 9011,
      title: 'Pedicure spa',
      venue: 'Marfil Beauty',
      category: 'Uñas',
      price: 19,
      durationMinutes: 50,
      distance: '1.4 km',
      rating: 4.8,
      reviews: 67,
      tags: ['Abierto ahora'],
    ),
    const HomeCatalogItem(
      id: 9012,
      title: 'Traslado aeropuerto',
      venue: 'Moverte',
      category: 'Transporte',
      price: 28,
      durationMinutes: 75,
      distance: '2.0 km',
      rating: 4.7,
      reviews: 29,
      tags: ['Reserva directa', 'Pago online'],
    ),
  ];
}
