import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/home_catalogo.dart';
import 'elaborated_availability_service.dart';
import 'home_offline_mapper.dart';
import 'offline_database_service.dart';
import 'supabase_retry_helper.dart';
import 'user_preferences_service.dart';

/// Lo que el Home necesita del backend.
///
/// Es una interfaz y no la implementación directa para que `HomeController` se
/// pueda probar sin Supabase: los tests inyectan un doble y comprueban la
/// agrupación, el orden y la navegación del drawer sin tocar la red.
abstract class HomeCatalogoGateway {
  /// Categorías del Home, ya colapsadas por denominación en el backend.
  ///
  /// Con [forceRefresh] se salta la caché en memoria y va directo a la red.
  Future<List<HomeCategoria>> catalogo({
    required HomeContexto contexto,
    bool forceRefresh = false,
  });

  /// Subcategorías de **todas** las categorías del grupo, en una sola llamada.
  Future<List<HomeSubcategoria>> subcategorias({
    required List<int> idsCategorias,
    required HomeContexto contexto,
  });

  /// Productos de la tienda.
  ///
  /// * [idsCategorias] vacío ⇒ una sola llamada sin filtro de categoría: es el
  ///   camino de la búsqueda global, que barre todo el catálogo del TPV.
  /// * con ids ⇒ una llamada por categoría del grupo (ver [kMaxCategoriasGrupo]).
  Future<List<HomeProducto>> productos({
    required HomeContexto contexto,
    List<int> idsCategorias = const <int>[],
    String? texto,
    bool soloDisponibles = false,
  });
}

/// Tope de categorías que se consultan de golpe al abrir un grupo.
///
/// Tras el colapso, las tiendas **activas** tienen grupos de 1-2 miembros. El
/// tope existe por las tiendas muertas del nomenclador (hay una con 208
/// "Alimentos"): sin él, abrir una carpeta dispararía 208 RPC. Con el tope, esa
/// tienda enseña los productos de las 8 primeras categorías y sigue siendo
/// usable en vez de colgarse.
const int kMaxCategoriasGrupo = 8;

/// Implementación real: RPC de Supabase + caché en memoria + snapshot en disco.
///
/// Todo el camino de lectura tiene **fallback offline** para que el Home nuevo
/// se comporte como el viejo cuando no hay red:
///
///  * [catalogo] → memoria → snapshot en disco → (si falla) error actual;
///  * [subcategorias] y [productos] → red y, si el modo offline está activo o la
///    RPC falla, el cache local (`offline_data`/SQLite) vía
///    [HomeOfflineSource]. Así el drawer no se queda vacío sin conexión.
class HomeCatalogService implements HomeCatalogoGateway {
  HomeCatalogService({
    SupabaseClient? cliente,
    ElaboratedAvailabilityService? disponibilidadElaborados,
    HomeOfflineSource? offline,
  }) : _cliente = cliente,
       _disponibilidadInyectada = disponibilidadElaborados,
       _offlineInyectada = offline;

  /// Cliente inyectado. Nulo ⇒ se resuelve `Supabase.instance` de forma
  /// perezosa: así los tests pueden construir el servicio para probar el
  /// fallback offline sin inicializar Supabase.
  final SupabaseClient? _cliente;

  final ElaboratedAvailabilityService? _disponibilidadInyectada;
  final HomeOfflineSource? _offlineInyectada;

  ElaboratedAvailabilityService? _disponibilidadCache;
  HomeOfflineSource? _offlineCache;

  SupabaseClient get _supabase => _cliente ?? Supabase.instance.client;

  /// Disponibilidad real de los elaborados. Se usa para no enseñar el stock
  /// propio del plato (1, 0...) cuando lo que importa es cuántos se pueden
  /// preparar con la materia prima de su cocina.
  ElaboratedAvailabilityService get _disponibilidadElaborados =>
      _disponibilidadInyectada ??
      (_disponibilidadCache ??= ElaboratedAvailabilityService());

  /// Cache local del modo offline. Solo se construye cuando hace falta.
  HomeOfflineSource get _offline =>
      _offlineInyectada ?? (_offlineCache ??= _HomeOfflineSourceCache());

  /// Caché en memoria. Evita repetir la RPC al volver al Home desde otra
  /// pantalla, que es lo que pasa decenas de veces por turno.
  static final Map<String, _EntradaCatalogo> _memoria =
      <String, _EntradaCatalogo>{};

  static const Duration _ttl = Duration(minutes: 5);

  static const String _clavePrefs = 'ventiq_home_catalogo_v1';

  /// Catálogo del Home con caché: memoria → disco → red.
  ///
  /// El orden importa y es "stale-while-revalidate" en la práctica: con caché
  /// fresca no se toca la red; con caché vieja se devuelve lo que hay (para que
  /// el Home pinte de inmediato) y el refresco lo decide el controlador.
  @override
  Future<List<HomeCategoria>> catalogo({
    required HomeContexto contexto,
    bool forceRefresh = false,
  }) async {
    final String clave = _clave(contexto);

    if (!forceRefresh) {
      final _EntradaCatalogo? enMemoria = _memoria[clave];
      if (enMemoria != null && enMemoria.fresca(_ttl)) {
        return enMemoria.categorias;
      }
    }

    try {
      final List<dynamic> filas = await withNetworkRetry(
        () => _supabase.rpc(
          'get_home_catalogo_tpv',
          params: <String, dynamic>{
            'p_tienda_id': contexto.idTienda,
            'p_tpv_id': contexto.idTpv,
          },
        ),
        description: 'Cargar home',
      );

      final List<HomeCategoria> categorias =
          filas
              .whereType<Map>()
              .map(
                (Map<dynamic, dynamic> m) =>
                    HomeCategoria.fromJson(m.cast<String, dynamic>()),
              )
              .toList();

      _memoria[clave] = _EntradaCatalogo(categorias);
      // El snapshot no se espera: es una optimización, no parte del resultado.
      unawaited(_guardarSnapshot(contexto, categorias));
      return categorias;
    } catch (e) {
      debugPrint('❌ HomeCatalogService.catalogo: $e');

      // Sin red: lo último bueno que se guardó. Es lo que permite abrir el Home
      // en modo offline en lugar de enseñar un error.
      final List<HomeCategoria>? enDisco = await _leerSnapshot(contexto);
      if (enDisco != null && enDisco.isNotEmpty) {
        debugPrint('📦 Home desde snapshot en disco: ${enDisco.length}');
        _memoria[clave] = _EntradaCatalogo(enDisco);
        return enDisco;
      }
      rethrow;
    }
  }

  @override
  Future<List<HomeSubcategoria>> subcategorias({
    required List<int> idsCategorias,
    required HomeContexto contexto,
  }) async {
    if (idsCategorias.isEmpty) return const <HomeSubcategoria>[];

    // Modo offline / full-offline: la fuente es el cache local, sin red.
    if (await _debeUsarCacheLocal()) {
      final List<HomeSubcategoria> locales = await _subcategoriasDesdeCache(
        idsCategorias,
      );
      debugPrint('🔌 Subs offline (cache): ${locales.length}');
      return locales;
    }

    try {
      final List<dynamic> filas = await withNetworkRetry(
        () => _supabase.rpc(
          'get_subcategorias_by_categoria_tpv',
          params: <String, dynamic>{
            'p_id_categorias': idsCategorias,
            'p_tienda_id': contexto.idTienda,
            'p_tpv_id': contexto.idTpv,
          },
        ),
        description: 'Cargar subcategorías',
      );

      return filas
          .whereType<Map>()
          .map(
            (Map<dynamic, dynamic> m) =>
                HomeSubcategoria.fromJson(m.cast<String, dynamic>()),
          )
          .toList();
    } catch (e) {
      // Sin cache el drawer enseña su estado vacío, pero no se rompe la
      // pantalla: es preferible un nivel vacío a un Home caído en medio del
      // turno. El mensaje del log dice exactamente qué pasó.
      debugPrint('❌ HomeCatalogService.subcategorias: $e');

      final List<HomeSubcategoria> locales = await _subcategoriasDesdeCache(
        idsCategorias,
      );
      if (locales.isNotEmpty) {
        debugPrint('📦 Subcategorías desde cache offline: ${locales.length}');
      } else {
        debugPrint(
          '⚠️ Sin red y sin subcategorías en cache para $idsCategorias: '
          'el drawer mostrará el nivel vacío.',
        );
      }
      return locales;
    }
  }

  @override
  Future<List<HomeProducto>> productos({
    required HomeContexto contexto,
    List<int> idsCategorias = const <int>[],
    String? texto,
    bool soloDisponibles = false,
  }) async {
    final String? busqueda =
        (texto == null || texto.trim().isEmpty) ? null : texto.trim();

    // Modo offline / full-offline: el cache local manda. No se enriquece con la
    // disponibilidad de elaborados porque eso también es una RPC.
    if (await _debeUsarCacheLocal()) {
      final List<HomeProducto> locales = await _productosDesdeCache(
        idsCategorias: idsCategorias,
        texto: busqueda,
        soloDisponibles: soloDisponibles,
      );
      debugPrint('🔌 Productos offline (cache): ${locales.length}');
      return locales;
    }

    // Sin ids: una sola llamada con categoría nula, que en la RPC significa
    // "todo el catálogo vendible del TPV". Es el camino de la búsqueda global.
    final List<int?> categorias =
        idsCategorias.isEmpty
            ? const <int?>[null]
            : idsCategorias.take(kMaxCategoriasGrupo).toList();

    if (idsCategorias.length > kMaxCategoriasGrupo) {
      debugPrint(
        '⚠️ Grupo de ${idsCategorias.length} categorías recortado a '
        '$kMaxCategoriasGrupo para no disparar ${idsCategorias.length} RPC',
      );
    }

    try {
      final List<List<HomeProducto>> partes = await Future.wait(
        categorias.map((int? idCategoria) async {
          final List<dynamic> filas = await withNetworkRetry(
            () => _supabase.rpc(
              'get_productos_by_categoria_tpv_search_meta_v3',
              params: <String, dynamic>{
                'id_categoria_param': idCategoria,
                'id_tienda_param': contexto.idTienda,
                'id_tpv_param': contexto.idTpv,
                'text_search': busqueda,
                'solo_disponibles_param': soloDisponibles,
              },
            ),
            description: 'Cargar productos',
          );

          return filas
              .whereType<Map>()
              .map(
                (Map<dynamic, dynamic> m) =>
                    HomeProducto.fromJson(m.cast<String, dynamic>()),
              )
              .toList();
        }),
      );

      return _conDisponibilidadElaborados(_unirPorId(partes), contexto);
    } catch (e) {
      // Falla la red (o el modo offline se activó a media petición): se
      // devuelve lo que haya en el cache local, que es lo que permite seguir
      // vendiendo. Sin cache, lista vacía y log claro; nunca una excepción que
      // tumbe el drawer.
      debugPrint('❌ HomeCatalogService.productos: $e');

      final List<HomeProducto> locales = await _productosDesdeCache(
        idsCategorias: idsCategorias,
        texto: busqueda,
        soloDisponibles: soloDisponibles,
      );
      if (locales.isNotEmpty) {
        debugPrint('📦 Productos desde cache offline: ${locales.length}');
      } else {
        debugPrint(
          '⚠️ Sin red y sin productos en cache para categorías $idsCategorias: '
          'el drawer mostrará el nivel vacío.',
        );
      }
      return locales;
    }
  }

  /// `true` si toca leer del cache local. Tolerante: si no se puede saber
  /// (preferencias corruptas), se intenta la red como siempre.
  Future<bool> _debeUsarCacheLocal() async {
    try {
      return await _offline.debeUsarDatosLocales();
    } catch (e) {
      debugPrint('⚠️ Home offline: no se pudo leer el modo offline: $e');
      return false;
    }
  }

  Future<List<HomeSubcategoria>> _subcategoriasDesdeCache(
    List<int> idsCategorias,
  ) async {
    try {
      final Map<int, List<Map<String, dynamic>>> cache = await _offline
          .productosPorCategoria(idsCategorias: idsCategorias);
      return subcategoriasOfflineDesdeCache(
        cache,
        idsCategorias: idsCategorias,
      );
    } catch (e) {
      debugPrint(
        '⚠️ Home offline: no se pudieron leer las subcategorías del cache: $e',
      );
      return const <HomeSubcategoria>[];
    }
  }

  Future<List<HomeProducto>> _productosDesdeCache({
    required List<int> idsCategorias,
    String? texto,
    bool soloDisponibles = false,
  }) async {
    try {
      final Map<int, List<Map<String, dynamic>>> cache = await _offline
          .productosPorCategoria(idsCategorias: idsCategorias);
      return productosOfflineDesdeCache(
        cache,
        idsCategorias: idsCategorias,
        texto: texto,
        soloDisponibles: soloDisponibles,
      );
    } catch (e) {
      debugPrint('⚠️ Home offline: no se pudieron leer los productos: $e');
      return const <HomeProducto>[];
    }
  }

  /// Cambia el stock propio de los elaborados por su disponibilidad real
  /// (materia prima de la cocina) antes de devolverlos al drawer.
  ///
  /// Es tolerante a fallos: si `fn_disponibilidad_plato` no responde (offline,
  /// error puntual), se devuelven los productos tal cual.
  Future<List<HomeProducto>> _conDisponibilidadElaborados(
    List<HomeProducto> productos,
    HomeContexto contexto,
  ) async {
    final Set<int> ids =
        productos
            .where((HomeProducto p) => p.esElaborado && !p.esServicio)
            .map((HomeProducto p) => p.id)
            .toSet();
    if (ids.isEmpty) return productos;

    try {
      final Map<int, double> disp = await _disponibilidadElaborados.disponibles(
        idsProductos: ids,
        idTpv: contexto.idTpv,
      );
      if (disp.isEmpty) return productos;

      return productos.map((HomeProducto p) {
        final double? elaborable = disp[p.id];
        if (elaborable == null) return p;
        return p.copyWith(stock: elaborable, tieneStock: elaborable > 0);
      }).toList();
    } catch (e) {
      debugPrint(
        '⚠️ No se pudo enriquecer la disponibilidad de elaborados: $e',
      );
      return productos;
    }
  }

  /// Une los resultados del fan-out. Un producto puede estar en dos categorías
  /// del mismo grupo colapsado, y no debe aparecer dos veces en el drawer.
  static List<HomeProducto> _unirPorId(List<List<HomeProducto>> partes) {
    final Map<int, HomeProducto> porId = <int, HomeProducto>{};
    for (final List<HomeProducto> parte in partes) {
      for (final HomeProducto p in parte) {
        porId.putIfAbsent(p.id, () => p);
      }
    }
    return porId.values.toList();
  }

  /// Tira la caché en memoria. Se llama al cambiar de TPV o tras una venta que
  /// pueda haber movido stock.
  void invalidar() => _memoria.clear();

  static String _clave(HomeContexto c) => '${c.idTienda}:${c.idTpv}';

  static String _claveSnapshot(HomeContexto c) =>
      '${_clavePrefs}_${c.idTienda}_${c.idTpv}';

  Future<void> _guardarSnapshot(
    HomeContexto contexto,
    List<HomeCategoria> categorias,
  ) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _claveSnapshot(contexto),
        jsonEncode(<String, dynamic>{
          'guardado_en': DateTime.now().toIso8601String(),
          'categorias':
              categorias.map((HomeCategoria c) => c.toJson()).toList(),
        }),
      );
    } catch (e) {
      // El snapshot es una optimización: si falla, el Home funciona igual.
      debugPrint('⚠️ No se pudo guardar el snapshot del Home: $e');
    }
  }

  Future<List<HomeCategoria>?> _leerSnapshot(HomeContexto contexto) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? crudo = prefs.getString(_claveSnapshot(contexto));
      if (crudo == null) return null;

      final Map<String, dynamic> json =
          (jsonDecode(crudo) as Map).cast<String, dynamic>();
      final List<dynamic> filas =
          (json['categorias'] as List?) ?? const <dynamic>[];

      return filas
          .whereType<Map>()
          .map(
            (Map<dynamic, dynamic> m) =>
                HomeCategoria.fromJson(m.cast<String, dynamic>()),
          )
          .toList();
    } catch (e) {
      debugPrint('⚠️ Snapshot del Home ilegible: $e');
      return null;
    }
  }
}

class _EntradaCatalogo {
  _EntradaCatalogo(this.categorias) : cuando = DateTime.now();

  final List<HomeCategoria> categorias;
  final DateTime cuando;

  bool fresca(Duration ttl) => DateTime.now().difference(cuando) < ttl;
}

/// Fuente real del fallback offline: el cache local que comparten el Home viejo
/// y el resto de la app (`offline_data` sobre SQLite o `SharedPreferences`).
///
/// El mapeo no vive aquí: se delega en `home_offline_mapper.dart` para poder
/// probarlo sin base de datos. Esta clase solo se ocupa de **leer** el cache,
/// con las mismas prioridades que `ProductService._getProductsByCategoryLocal`:
///
///  1. lectura dirigida por categoría (usa el índice de `offline_products`);
///  2. mapa completo agrupado (búsqueda global o cache con claves raras);
///  3. blob `offline_data` legacy por si la plataforma solo tiene prefs (web).
class _HomeOfflineSourceCache implements HomeOfflineSource {
  _HomeOfflineSourceCache({
    UserPreferencesService? preferencias,
    OfflineDatabaseService? baseDatos,
  }) : _prefs = preferencias ?? UserPreferencesService(),
       _db = baseDatos ?? OfflineDatabaseService();

  final UserPreferencesService _prefs;
  final OfflineDatabaseService _db;

  @override
  Future<bool> debeUsarDatosLocales() => _prefs.shouldUseLocalData();

  @override
  Future<Map<int, List<Map<String, dynamic>>>> productosPorCategoria({
    List<int> idsCategorias = const <int>[],
  }) async {
    final Map<int, List<Map<String, dynamic>>> salida =
        <int, List<Map<String, dynamic>>>{};

    if (idsCategorias.isNotEmpty) {
      for (final int id in idsCategorias) {
        try {
          final List<Map<String, dynamic>> filas = await _db
              .getProductsByCategory(id.toString());
          if (filas.isNotEmpty) salida[id] = filas;
        } catch (e) {
          debugPrint('⚠️ Home offline: no se pudo leer la categoría $id: $e');
        }
      }
      if (salida.isNotEmpty) return salida;
    }

    try {
      final Map<String, List<Map<String, dynamic>>> agrupado =
          await _db.getProductsGroupedByCategory();
      final Map<int, List<Map<String, dynamic>>> normalizado =
          _normalizarClaves(agrupado, idsCategorias: idsCategorias);
      if (normalizado.isNotEmpty) return normalizado;
    } catch (e) {
      debugPrint('⚠️ Home offline: no se pudo leer el mapa de productos: $e');
    }

    // Último recurso: solo queda el blob clásico de prefs (web/legacy).
    try {
      final Map<String, dynamic>? datos = await _prefs.getOfflineData();
      final Object? productos = datos?['products'];
      if (productos is Map) {
        final Map<String, List<Map<String, dynamic>>> agrupado =
            <String, List<Map<String, dynamic>>>{};
        for (final MapEntry<dynamic, dynamic> entry in productos.entries) {
          final Object? lista = entry.value;
          if (lista is! List) continue;
          agrupado[entry.key.toString()] =
              lista
                  .whereType<Map>()
                  .map(
                    (Map<dynamic, dynamic> m) => Map<String, dynamic>.from(m),
                  )
                  .toList();
        }
        return _normalizarClaves(agrupado, idsCategorias: idsCategorias);
      }
    } catch (e) {
      debugPrint('⚠️ Home offline: offline_data ilegible: $e');
    }

    return salida;
  }

  Map<int, List<Map<String, dynamic>>> _normalizarClaves(
    Map<String, List<Map<String, dynamic>>> agrupado, {
    required List<int> idsCategorias,
  }) {
    final Set<int> pedidas = idsCategorias.toSet();
    final Map<int, List<Map<String, dynamic>>> salida =
        <int, List<Map<String, dynamic>>>{};

    for (final MapEntry<String, List<Map<String, dynamic>>> entry
        in agrupado.entries) {
      final int? id = int.tryParse(entry.key);
      if (id == null) continue;
      if (pedidas.isNotEmpty && !pedidas.contains(id)) continue;
      salida[id] = entry.value;
    }
    return salida;
  }
}
