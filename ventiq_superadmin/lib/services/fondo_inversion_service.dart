import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio del Fondo de Inversión para superadmin.
/// El superadmin gestiona la estructura (conceptos/cuentas) de cada tienda
/// y consulta paneles de solo lectura (saldos, inversiones en revisión).
class FondoInversionService {
  static final _client = Supabase.instance.client;

  // ==========================================================================
  // Conceptos
  // ==========================================================================

  static Future<List<Map<String, dynamic>>> listConceptos(
    int idTienda,
  ) async {
    final rows = await _client
        .from('fdi_dat_concepto')
        .select()
        .eq('id_tienda', idTienda)
        .order('denominacion');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> crearConcepto({
    required int idTienda,
    required String denominacion,
    String? descripcion,
  }) async {
    final row = await _client
        .from('fdi_dat_concepto')
        .insert({
          'id_tienda': idTienda,
          'denominacion': denominacion,
          'descripcion': descripcion,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  static Future<void> actualizarConcepto(
    int id, {
    String? denominacion,
    String? descripcion,
    bool? activo,
  }) async {
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (denominacion != null) data['denominacion'] = denominacion;
    if (descripcion != null) data['descripcion'] = descripcion;
    if (activo != null) data['activo'] = activo;
    await _client.from('fdi_dat_concepto').update(data).eq('id', id);
  }

  static Future<void> eliminarConcepto(int id) async {
    await _client.from('fdi_dat_concepto').delete().eq('id', id);
  }

  // ==========================================================================
  // Cuentas
  // ==========================================================================

  static Future<List<Map<String, dynamic>>> listCuentas(int idTienda) async {
    final rows = await _client
        .from('fdi_dat_cuenta')
        .select()
        .eq('id_tienda', idTienda)
        .order('nombre');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> crearCuenta({
    required int idTienda,
    required int idConcepto,
    required String nombre,
    String? descripcion,
  }) async {
    final row = await _client
        .from('fdi_dat_cuenta')
        .insert({
          'id_concepto': idConcepto,
          'id_tienda': idTienda,
          'nombre': nombre,
          'descripcion': descripcion,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(row);
  }

  static Future<void> actualizarCuenta(
    int id, {
    String? nombre,
    String? descripcion,
    bool? activo,
    int? idConcepto,
  }) async {
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (nombre != null) data['nombre'] = nombre;
    if (descripcion != null) data['descripcion'] = descripcion;
    if (activo != null) data['activo'] = activo;
    if (idConcepto != null) data['id_concepto'] = idConcepto;
    await _client.from('fdi_dat_cuenta').update(data).eq('id', id);
  }

  static Future<void> eliminarCuenta(int id) async {
    await _client.from('fdi_dat_cuenta').delete().eq('id', id);
  }

  // ==========================================================================
  // Paneles de solo lectura
  // ==========================================================================

  /// Saldos actuales de la tienda (RPC fn_fdi_saldos).
  static Future<Map<String, dynamic>> saldos(int idTienda) async {
    final resp = await _client.rpc(
      'fn_fdi_saldos',
      params: {'p_id_tienda': idTienda},
    );
    return resp is Map ? Map<String, dynamic>.from(resp) : <String, dynamic>{};
  }

  /// Inversiones de la tienda; [soloRevision] filtra las que están en
  /// revisión efectiva o vencidas por días sin completarse.
  static Future<List<Map<String, dynamic>>> inversiones(
    int idTienda, {
    bool soloRevision = false,
  }) async {
    final resp = await _client.rpc(
      'fn_fdi_inversiones',
      params: {
        'p_id_tienda': idTienda,
        'p_estado': null,
        'p_solo_revision': soloRevision,
      },
    );
    return ((resp as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Movimientos del libro contable del fondo (RPC fn_fdi_movimientos).
  static Future<List<Map<String, dynamic>>> movimientos(
    int idTienda, {
    int limite = 200,
  }) async {
    final resp = await _client.rpc(
      'fn_fdi_movimientos',
      params: {
        'p_id_tienda': idTienda,
        'p_desde': null,
        'p_hasta': null,
        'p_id_concepto': null,
        'p_id_cuenta': null,
        'p_id_medio_pago': null,
        'p_moneda': null,
        'p_tipo': null,
        'p_limite': limite,
      },
    );
    return ((resp as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
