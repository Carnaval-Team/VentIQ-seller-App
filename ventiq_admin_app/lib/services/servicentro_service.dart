import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_preferences_service.dart';

/// Acceso a las RPC de modo servicentro **por TPV**.
class ServicentroService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _userPrefs = UserPreferencesService();

  static Future<int> _requireStoreId() async {
    final storeId = await _userPrefs.getIdTienda();
    if (storeId == null) {
      throw ServicentroException(
        'No se pudo determinar la tienda actual. Vuelve a iniciar sesión.',
        codigo: 'NO_STORE',
      );
    }
    return storeId;
  }

  static Map<String, dynamic> _unwrap(dynamic response, String operacion) {
    if (response is! Map) {
      throw ServicentroException('Respuesta inesperada al $operacion');
    }
    final mapa = Map<String, dynamic>.from(response);
    if (mapa['status'] == 'error') {
      throw ServicentroException(
        mapa['message']?.toString() ?? 'Error al $operacion',
        codigo: mapa['error_code']?.toString(),
        datos: mapa,
      );
    }
    return mapa;
  }

  static Future<ServicentroConfig> getConfig(int idTpv) async {
    final response = await _supabase.rpc(
      'fn_get_servicentro_config',
      params: {'p_id_tpv': idTpv},
    );
    final mapa = _unwrap(response, 'obtener config servicentro');
    return ServicentroConfig.fromJson(mapa);
  }

  static Future<ServicentroConfigFlags> setModo({
    required int idTpv,
    required bool activo,
    int? columnas,
  }) async {
    final response = await _supabase.rpc(
      'fn_set_modo_servicentro',
      params: {
        'p_id_tpv': idTpv,
        'p_activo': activo,
        if (columnas != null) 'p_servicentro_columnas': columnas,
      },
    );
    final mapa = _unwrap(response, 'actualizar modo servicentro');
    return ServicentroConfigFlags(
      modoServicentro: mapa['modo_servicentro'] == true,
      columnas: (mapa['servicentro_columnas'] as num?)?.toInt() ?? 2,
    );
  }

  static Future<void> setColumnas(int idTpv, int columnas) async {
    final config = await getConfig(idTpv);
    await setModo(
      idTpv: idTpv,
      activo: config.modoServicentro,
      columnas: columnas,
    );
  }

  static Future<void> upsertProducto({
    required int idTpv,
    required int idProducto,
    int? orden,
    String? color,
  }) async {
    final response = await _supabase.rpc(
      'fn_upsert_servicentro_producto',
      params: {
        'p_id_tpv': idTpv,
        'p_id_producto': idProducto,
        if (orden != null) 'p_orden': orden,
        if (color != null) 'p_color': color,
      },
    );
    _unwrap(response, 'guardar combustible');
  }

  static Future<void> eliminarProducto({
    required int idTpv,
    required int idProducto,
  }) async {
    final response = await _supabase.rpc(
      'fn_eliminar_servicentro_producto',
      params: {
        'p_id_tpv': idTpv,
        'p_id_producto': idProducto,
      },
    );
    _unwrap(response, 'quitar combustible');
  }

  static Future<void> reordenar({
    required int idTpv,
    required List<int> idsProducto,
  }) async {
    final response = await _supabase.rpc(
      'fn_reordenar_servicentro_productos',
      params: {
        'p_id_tpv': idTpv,
        'p_ids_producto': idsProducto,
      },
    );
    _unwrap(response, 'reordenar combustibles');
  }

  /// Productos combustible de la tienda aún no en la lista de este TPV.
  static Future<List<Map<String, dynamic>>> buscarCombustiblesDisponibles({
    required Set<int> idsYaEnLista,
    String query = '',
  }) async {
    final idTienda = await _requireStoreId();
    final response = await _supabase
        .from('app_dat_producto')
        .select('id, denominacion, sku, um, imagen, es_combustible')
        .eq('id_tienda', idTienda)
        .eq('es_combustible', true)
        .isFilter('deleted_at', null)
        .order('denominacion');

    final rows = (response as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((p) {
          final id = (p['id'] as num?)?.toInt();
          if (id == null || idsYaEnLista.contains(id)) return false;
          if (query.trim().isEmpty) return true;
          final qLower = query.trim().toLowerCase();
          final nombre = (p['denominacion'] ?? '').toString().toLowerCase();
          final sku = (p['sku'] ?? '').toString().toLowerCase();
          return nombre.contains(qLower) || sku.contains(qLower);
        })
        .toList();
    return rows;
  }

  static const List<String> colorPresets = [
    '#64748B',
    '#EF4444',
    '#F97316',
    '#EAB308',
    '#92400E',
    '#22C55E',
    '#14B8A6',
    '#3B82F6',
    '#8B5CF6',
    '#EC4899',
    '#000000',
  ];

  static ColorParseResult parseHexColor(String hex) {
    final cleaned = hex.trim();
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(cleaned)) {
      return const ColorParseResult(valid: false);
    }
    final value = int.parse(cleaned.substring(1), radix: 16);
    return ColorParseResult(valid: true, argb: 0xFF000000 | value);
  }
}

class ColorParseResult {
  final bool valid;
  final int? argb;
  const ColorParseResult({required this.valid, this.argb});
}

class ServicentroConfigFlags {
  final bool modoServicentro;
  final int columnas;

  const ServicentroConfigFlags({
    required this.modoServicentro,
    required this.columnas,
  });
}

class ServicentroConfig {
  final int idTpv;
  final int idTienda;
  final String? tpvDenominacion;
  final bool modoServicentro;
  final int columnas;
  final List<ServicentroProductoItem> productos;

  const ServicentroConfig({
    required this.idTpv,
    required this.idTienda,
    this.tpvDenominacion,
    required this.modoServicentro,
    required this.columnas,
    required this.productos,
  });

  factory ServicentroConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['productos'];
    final list = <ServicentroProductoItem>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(
            ServicentroProductoItem.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return ServicentroConfig(
      idTpv: (json['id_tpv'] as num?)?.toInt() ?? 0,
      idTienda: (json['id_tienda'] as num?)?.toInt() ?? 0,
      tpvDenominacion: json['tpv_denominacion']?.toString(),
      modoServicentro: json['modo_servicentro'] == true,
      columnas: (json['servicentro_columnas'] as num?)?.toInt() ?? 2,
      productos: list,
    );
  }
}

class ServicentroProductoItem {
  final int id;
  final int idProducto;
  final int orden;
  final String color;
  final String denominacion;
  final String? sku;
  final String? um;
  final String? imagen;
  final double precioVenta;

  const ServicentroProductoItem({
    required this.id,
    required this.idProducto,
    required this.orden,
    required this.color,
    required this.denominacion,
    this.sku,
    this.um,
    this.imagen,
    this.precioVenta = 0,
  });

  factory ServicentroProductoItem.fromJson(Map<String, dynamic> json) {
    return ServicentroProductoItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idProducto: (json['id_producto'] as num?)?.toInt() ?? 0,
      orden: (json['orden'] as num?)?.toInt() ?? 0,
      color: (json['color'] ?? '#64748B').toString(),
      denominacion: (json['denominacion'] ?? '').toString(),
      sku: json['sku']?.toString(),
      um: json['um']?.toString(),
      imagen: json['imagen']?.toString(),
      precioVenta: (json['precio_venta'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ServicentroException implements Exception {
  final String message;
  final String? codigo;
  final Map<String, dynamic>? datos;

  ServicentroException(this.message, {this.codigo, this.datos});

  @override
  String toString() => message;
}
