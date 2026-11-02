import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/home_catalogo.dart';
import 'elaborated_availability_service.dart';
import 'supabase_retry_helper.dart';

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
class HomeCatalogService implements HomeCatalogoGateway {
  HomeCatalogService({
    SupabaseClient? cliente,
    ElaboratedAvailabilityService? disponibilidadElaborados,
  }) : _supabase = cliente ?? Supabase.instance.client,
       _disponibilidadElaborados =
           disponibilidadElaborados ?? ElaboratedAvailabilityService();

  final SupabaseClient _supabase;

  /// Disponibilidad real de los elaborados. Se usa para no enseñar el stock
  /// propio del plato (1, 0...) cuando lo que importa es cuántos se pueden
  /// preparar con la materia prima de su cocina.
  final ElaboratedAvailabilityService _disponibilidadElaborados;

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
