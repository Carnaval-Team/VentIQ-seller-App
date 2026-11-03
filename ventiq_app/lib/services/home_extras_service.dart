import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Producto de un riel del Home (más vendidos / ofertas).
///
/// Modelo plano: lo que la tarjeta necesita pintar. Se construye desde las RPC
/// `fn_top_productos_tpv` y `fn_ofertas_tpv` (ver migración
/// `20261103130000_fn_top_productos_y_ofertas_tpv.sql`).
@immutable
class HomeRielProducto {
  const HomeRielProducto({
    required this.id,
    required this.nombre,
    this.imagen,
    this.precio,
    this.precioOferta,
    this.unidadesVendidas,
    this.porcentajeDescuento,
    this.categoria,
  });

  final int id;
  final String nombre;
  final String? imagen;
  final double? precio;
  final double? precioOferta;

  /// Solo en «más vendidos».
  final double? unidadesVendidas;

  /// Solo en «ofertas».
  final double? porcentajeDescuento;

  final String? categoria;

  bool get tieneOferta => precioOferta != null && precio != null;

  static double? _num(dynamic v) => v is num ? v.toDouble() : null;

  factory HomeRielProducto.fromJson(Map<String, dynamic> json) {
    return HomeRielProducto(
      id: (json['id_producto'] as num?)?.toInt() ?? 0,
      nombre:
          (json['denominacion'] ?? json['nombre'] ?? 'Sin nombre').toString(),
      imagen: json['imagen']?.toString(),
      precio: _num(json['precio_venta']),
      precioOferta: _num(json['precio_descuento']),
      unidadesVendidas: _num(json['unidades_vendidas']),
      porcentajeDescuento: _num(json['porcentaje']),
      categoria: json['categoria_nombre']?.toString(),
    );
  }

  /// Para la caché local de los rieles (offline).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id_producto': id,
    'denominacion': nombre,
    'imagen': imagen,
    'precio_venta': precio,
    'precio_descuento': precioOferta,
    'unidades_vendidas': unidadesVendidas,
    'porcentaje': porcentajeDescuento,
    'categoria_nombre': categoria,
  };
}

/// Datos extra del Home: rieles de «más vendidos» y «ofertas».
///
/// Tolerante a fallos: si la RPC no está aplicada todavía (o no hay red) los
/// rieles se quedan vacíos y el Home funciona igual. El Home viejo no los
/// tenía y no son críticos.
class HomeExtrasService {
  /// El cliente se resuelve al primer RPC (no al construir la clase) para que
  /// las pruebas de caché puedan instanciar el servicio sin Supabase.
  HomeExtrasService({SupabaseClient? client}) : _client = client;

  SupabaseClient? _client;

  SupabaseClient get _cliente => _client ??= Supabase.instance.client;

  static const int maxProductos = 12;

  /// Más vendidos de la caja en los últimos [dias] días.
  ///
  /// Si la RPC falla (sin red, sin aplicar o sin permiso) devuelve la última
  /// copia guardada en el dispositivo, para que el riel siga existiendo offline.
  Future<List<HomeRielProducto>> masVendidos({
    required int idTpv,
    int dias = 30,
    int limite = maxProductos,
  }) async {
    return _llamarRpcConCache(
      'fn_top_productos_tpv',
      'home_rail_top_$idTpv',
      <String, dynamic>{'p_id_tpv': idTpv, 'p_dias': dias, 'p_limit': limite},
    );
  }

  /// Productos con descuento vigente vendibles en la caja.
  Future<List<HomeRielProducto>> ofertas({
    required int idTpv,
    int limite = maxProductos,
  }) async {
    return _llamarRpcConCache(
      'fn_ofertas_tpv',
      'home_rail_ofertas_$idTpv',
      <String, dynamic>{'p_id_tpv': idTpv, 'p_limit': limite},
    );
  }

  /// Última copia local de «más vendidos» (para pintar el riel al instante,
  /// también en modo offline).
  Future<List<HomeRielProducto>> masVendidosDesdeCache(int idTpv) =>
      _leerCache('home_rail_top_$idTpv');

  /// Última copia local de «ofertas».
  Future<List<HomeRielProducto>> ofertasDesdeCache(int idTpv) =>
      _leerCache('home_rail_ofertas_$idTpv');

  Future<List<HomeRielProducto>> _llamarRpcConCache(
    String rpc,
    String cacheKey,
    Map<String, dynamic> params,
  ) async {
    try {
      final dynamic respuesta = await _cliente.rpc(rpc, params: params);
      final List<HomeRielProducto> riel = mapearRespuesta(respuesta);
      await _guardarCache(cacheKey, riel);
      return riel;
    } catch (e) {
      // RPC sin aplicar, sin red o sin permiso: se usa la copia local.
      debugPrint('ℹ️ HomeExtrasService.$rpc sin red, usando caché: $e');
      return _leerCache(cacheKey);
    }
  }

  Future<List<HomeRielProducto>> _leerCache(String clave) =>
      leerCacheRiel(clave);

  Future<void> _guardarCache(String clave, List<HomeRielProducto> riel) =>
      guardarCacheRiel(clave, riel);

  /// Lee un riel de la caché local. Público para poder probarlo sin Supabase.
  static Future<List<HomeRielProducto>> leerCacheRiel(String clave) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? crudo = prefs.getString(clave);
      if (crudo == null || crudo.isEmpty) return const <HomeRielProducto>[];
      final dynamic json = jsonDecode(crudo);
      return mapearRespuesta(json);
    } catch (e) {
      debugPrint('ℹ️ HomeExtrasService: caché ilegible ($clave): $e');
      return const <HomeRielProducto>[];
    }
  }

  /// Guarda un riel en la caché local. Público para poder probarlo.
  static Future<void> guardarCacheRiel(
    String clave,
    List<HomeRielProducto> riel,
  ) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        clave,
        jsonEncode(riel.map((HomeRielProducto p) => p.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('ℹ️ HomeExtrasService: no se pudo guardar la caché: $e');
    }
  }

  /// Puro y público para poder testear el mapeo sin Supabase.
  static List<HomeRielProducto> mapearRespuesta(dynamic respuesta) {
    if (respuesta is! List) return const <HomeRielProducto>[];
    final List<HomeRielProducto> salida = <HomeRielProducto>[];
    for (final dynamic fila in respuesta) {
      if (fila is! Map) continue;
      final HomeRielProducto p = HomeRielProducto.fromJson(
        Map<String, dynamic>.from(fila),
      );
      if (p.id > 0 && p.nombre.trim().isNotEmpty) salida.add(p);
    }
    return salida;
  }
}
