import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pendientes.dart';

/// Lectura de la fase 9 de Compras: panel de pendientes, detalle por línea,
/// histórico de recepciones y vista de facturas.
///
/// Las cuatro funciones viven en `lib/sql/compra/09_pendientes.sql` y son
/// **solo lectura** (`STABLE SECURITY DEFINER`). Aquí no se escribe nada: no
/// hay `insert`, `update` ni llamadas a RPC de escritura.
class PendientesService {
  static final PendientesService _instance = PendientesService._internal();
  factory PendientesService() => _instance;
  PendientesService._internal();

  /// Se resuelve en cada llamada (no en el constructor) para que la pantalla
  /// pueda montarse con datos ya cargados —humo de widget— sin inicializar
  /// Supabase.
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Las columnas `date` viajan como `YYYY-MM-DD`; el servidor filtra por
  /// `fecha_factura` (facturas) y por `created_at::date` (recepciones).
  String _fecha(DateTime fecha) =>
      fecha.toIso8601String().split('T').first;

  Map<String, dynamic> _asMap(dynamic resp) =>
      resp is Map ? Map<String, dynamic>.from(resp) : <String, dynamic>{};

  /// Panel de compras abiertas con lo pedido, lo recibido y lo que falta.
  ///
  /// [orden] es el único filtro de orden: `antiguedad` (más viejas primero) o
  /// `monto` (más pendiente primero). Se manda al servidor en cada cambio; la
  /// pantalla **no** reordena en cliente, porque el orden forma parte del
  /// contrato (y de los totales por moneda que devuelve).
  Future<PendientesPanel> panel({
    required int idTienda,
    PendientesOrden orden = PendientesOrden.antiguedad,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_pendientes_panel',
      params: {'p_id_tienda': idTienda, 'p_orden': orden.codigo},
    );
    return PendientesPanel.fromJson(_asMap(resp));
  }

  /// Desglose por producto y línea de una compra. Sirve también para compras
  /// cerradas: el servidor no filtra por estado en el detalle.
  Future<PendienteDetalle> detalle({
    required int idTienda,
    required int idCompra,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_pendientes_detalle',
      params: {'p_id_tienda': idTienda, 'p_id_compra': idCompra},
    );
    return PendienteDetalle.fromJson(_asMap(resp));
  }

  /// Histórico de recepciones (una fila por vínculo
  /// `fdi_dat_compra_recepcion`).
  ///
  /// Las fechas son opcionales: se omiten del mapa cuando no existen y la RPC
  /// usa su `DEFAULT NULL`. El filtro va sobre la fecha del vínculo.
  Future<HistorialRecepciones> recepciones({
    required int idTienda,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_recepciones_historial',
      params: {
        'p_id_tienda': idTienda,
        if (desde != null) 'p_desde': _fecha(desde),
        if (hasta != null) 'p_hasta': _fecha(hasta),
      },
    );
    return HistorialRecepciones.fromJson(_asMap(resp));
  }

  /// Vista documental de facturas con su estado de recepción, incluidas las
  /// compras cerradas. El filtro de fechas va sobre `fecha_factura`.
  Future<FacturasVista> facturas({
    required int idTienda,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_facturas',
      params: {
        'p_id_tienda': idTienda,
        if (desde != null) 'p_desde': _fecha(desde),
        if (hasta != null) 'p_hasta': _fecha(hasta),
      },
    );
    return FacturasVista.fromJson(_asMap(resp));
  }
}