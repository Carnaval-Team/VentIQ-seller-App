import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/compra.dart';

/// Servicio del módulo Compras.
///
/// Todas las escrituras pasan por las RPC `fn_fdi_compra_*` (SECURITY DEFINER:
/// validan rol y tienda en servidor). No hay escritura directa a tablas.
class CompraService {
  static final CompraService _instance = CompraService._internal();
  factory CompraService() => _instance;
  CompraService._internal();

  final _supabase = Supabase.instance.client;

  /// Genera una clave de idempotencia (uuid v4), mismo formato que
  /// `FondoInversionService.newIdempotencyKey()`. Debe crearse UNA vez por
  /// formulario y reutilizarse en los reintentos.
  String newIdempotencyKey() {
    final r = Random.secure();
    String h(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
  }

  Map<String, dynamic> _asMap(dynamic resp) =>
      resp is Map ? Map<String, dynamic>.from(resp) : <String, dynamic>{};

  /// Las columnas `date` viajan como `YYYY-MM-DD`; las `timestamptz`, completas.
  String? _fecha(DateTime? x) => x?.toIso8601String().split('T').first;

  // ==========================================================================
  // Lectura
  // ==========================================================================

  /// Filas de `fn_fdi_compra_listar`, ya ordenadas por número de compra desc.
  ///
  /// Los filtros de fecha se aplican sobre `fecha_factura`, así que las compras
  /// sin fecha de factura quedan fuera cuando se pasa [desde] o [hasta].
  Future<List<CompraResumen>> listar({
    required int idTienda,
    String? estado,
    int? idProveedor,
    DateTime? desde,
    DateTime? hasta,
    String? texto,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_listar',
      params: {
        'p_id_tienda': idTienda,
        'p_estado': estado,
        'p_id_proveedor': idProveedor,
        'p_desde': _fecha(desde),
        'p_hasta': _fecha(hasta),
        'p_texto': texto,
      },
    );
    return ((resp as List?) ?? [])
        .map((e) => CompraResumen.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<CompraDetalle> detalle(int idCompra) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_detalle',
      params: {'p_id_compra': idCompra},
    );
    return CompraDetalle.fromJson(_asMap(resp));
  }

  // ==========================================================================
  // Escritura
  // ==========================================================================

  /// Crea la compra. Devuelve el jsonb de la RPC: `{status, id_compra,
  /// numero_compra, estado, total_mercancia, total_ajustes, total_financiado,
  /// costo_aterrizado, moneda_total}` — o `{status:'ok', id_compra,
  /// duplicada:true}` si la [idempotencyKey] ya se usó (no trae totales).
  Future<Map<String, dynamic>> crear({
    required int idTienda,
    required int idProveedor,
    String? numeroFactura,
    DateTime? fechaFactura,
    required String monedaTotal,
    double tasaFactura = 1,
    required List<CompraLinea> lineas,
    List<CompraAjuste> ajustes = const [],
    String modoLiquidacion = 'fondo',
    String politicaPago = 'al_pagar',
    String? observacion,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_crear',
      params: {
        'p_id_tienda': idTienda,
        'p_id_proveedor': idProveedor,
        'p_numero_factura': numeroFactura,
        'p_fecha_factura': _fecha(fechaFactura),
        'p_moneda_total': monedaTotal,
        'p_tasa_factura': tasaFactura,
        'p_lineas': lineas.map((l) => l.toJson()).toList(),
        'p_ajustes': ajustes.map((a) => a.toJson()).toList(),
        'p_modo_liquidacion': modoLiquidacion,
        'p_politica_pago': politicaPago,
        'p_observacion': observacion,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  /// Edita cabecera, líneas y ajustes. Solo la acepta la RPC mientras la compra
  /// está en `creada` (reemplaza líneas y ajustes completos).
  ///
  /// Devuelve `{status, id_compra, total_mercancia, total_financiado,
  /// costo_aterrizado}`.
  Future<Map<String, dynamic>> editar({
    required int idCompra,
    String? numeroFactura,
    DateTime? fechaFactura,
    required String monedaTotal,
    double tasaFactura = 1,
    required List<CompraLinea> lineas,
    List<CompraAjuste> ajustes = const [],
    String? observacion,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_editar',
      params: {
        'p_id_compra': idCompra,
        'p_numero_factura': numeroFactura,
        'p_fecha_factura': _fecha(fechaFactura),
        'p_moneda_total': monedaTotal,
        'p_tasa_factura': tasaFactura,
        'p_lineas': lineas.map((l) => l.toJson()).toList(),
        'p_ajustes': ajustes.map((a) => a.toJson()).toList(),
        'p_observacion': observacion,
      },
    );
    return _asMap(resp);
  }

  /// Cancela una compra en `creada` y sin recepciones. Devuelve
  /// `{status, id_compra, estado}` (`duplicada:true` si ya estaba cancelada).
  Future<Map<String, dynamic>> cancelar(int idCompra, String motivo) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_cancelar',
      params: {'p_id_compra': idCompra, 'p_motivo': motivo},
    );
    return _asMap(resp);
  }
}
