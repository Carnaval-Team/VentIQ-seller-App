import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fondo_inversion.dart';

/// Servicio del módulo Fondo de Inversión.
/// Todas las escrituras pasan por RPCs SECURITY DEFINER (validan rol en
/// servidor); las lecturas estructurales van a las tablas con RLS.
class FondoInversionService {
  static final FondoInversionService _instance =
      FondoInversionService._internal();
  factory FondoInversionService() => _instance;
  FondoInversionService._internal();

  final _supabase = Supabase.instance.client;

  /// Genera una clave de idempotencia (uuid v4). Debe crearse UNA vez por
  /// diálogo/operación y reutilizarse en reintentos.
  String newIdempotencyKey() {
    final r = Random.secure();
    String h(int n) =>
        List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
  }

  Map<String, dynamic> _asMap(dynamic resp) =>
      resp is Map ? Map<String, dynamic>.from(resp) : <String, dynamic>{};

  // ==========================================================================
  // Estructura: conceptos y cuentas
  // ==========================================================================

  Future<List<FdiConcepto>> listConceptos(
    int idTienda, {
    bool soloActivos = false,
  }) async {
    var q = _supabase
        .from('fdi_dat_concepto')
        .select()
        .eq('id_tienda', idTienda);
    if (soloActivos) q = q.eq('activo', true);
    final rows = await q.order('denominacion');
    return (rows as List)
        .map((e) => FdiConcepto.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<FdiCuenta>> listCuentas(
    int idTienda, {
    int? idConcepto,
    bool soloActivas = false,
  }) async {
    var q = _supabase.from('fdi_dat_cuenta').select().eq('id_tienda', idTienda);
    if (idConcepto != null) q = q.eq('id_concepto', idConcepto);
    if (soloActivas) q = q.eq('activo', true);
    final rows = await q.order('nombre');
    return (rows as List)
        .map((e) => FdiCuenta.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<FdiConcepto> crearConcepto(
    int idTienda, {
    required String denominacion,
    String? descripcion,
  }) async {
    final row = await _supabase
        .from('fdi_dat_concepto')
        .insert({
          'id_tienda': idTienda,
          'denominacion': denominacion,
          'descripcion': descripcion,
        })
        .select()
        .single();
    return FdiConcepto.fromJson(Map<String, dynamic>.from(row));
  }

  Future<FdiCuenta> crearCuenta(
    int idTienda, {
    required int idConcepto,
    required String nombre,
    String? descripcion,
  }) async {
    final row = await _supabase
        .from('fdi_dat_cuenta')
        .insert({
          'id_concepto': idConcepto,
          'id_tienda': idTienda,
          'nombre': nombre,
          'descripcion': descripcion,
        })
        .select()
        .single();
    return FdiCuenta.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> actualizarConcepto(
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
    await _supabase.from('fdi_dat_concepto').update(data).eq('id', id);
  }

  Future<void> actualizarCuenta(
    int id, {
    String? nombre,
    String? descripcion,
    bool? activo,
  }) async {
    final data = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (nombre != null) data['nombre'] = nombre;
    if (descripcion != null) data['descripcion'] = descripcion;
    if (activo != null) data['activo'] = activo;
    await _supabase.from('fdi_dat_cuenta').update(data).eq('id', id);
  }

  /// Borrado solo permitido si la cuenta no tiene saldos ni movimientos;
  /// la FK lo bloquea en base de datos de todas formas.
  Future<bool> cuentaTieneMovimientos(int idCuenta) async {
    final rows = await _supabase
        .from('fdi_dat_movimiento')
        .select('id')
        .eq('id_cuenta', idCuenta)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<void> eliminarCuenta(int id) async {
    await _supabase.from('fdi_dat_cuenta').delete().eq('id', id);
  }

  /// Eliminar concepto — solo si no tiene cuentas (la FK bloquea de todas
  /// formas, la UI lo valida antes).
  Future<void> eliminarConcepto(int id) async {
    await _supabase.from('fdi_dat_concepto').delete().eq('id', id);
  }

  // ==========================================================================
  // Config
  // ==========================================================================

  Future<List<Map<String, dynamic>>> listInversores(int idTienda) async {
    final rows = await _supabase
        .from('fdi_dat_inversor')
        .select()
        .eq('id_tienda', idTienda)
        .order('id');
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> guardarInversor(
    int idTienda, {
    int? id,
    required String nombre,
    required double porcentaje,
    required bool activo,
  }) async {
    await _supabase.rpc(
      'fn_fdi_guardar_inversor',
      params: {
        'p_id_tienda': idTienda,
        'p_id': id,
        'p_nombre': nombre,
        'p_porcentaje': porcentaje,
        'p_activo': activo,
      },
    );
  }

  Future<List<Map<String, dynamic>>> historialInversores(
    int idTienda, {
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final rows = await _supabase.rpc(
      'fn_fdi_historial_inversores',
      params: {
        'p_id_tienda': idTienda,
        'p_desde': desde?.toIso8601String().split('T').first,
        'p_hasta': hasta?.toIso8601String().split('T').first,
      },
    );
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> pagarInversor(int idReparto, String referencia) async {
    await _supabase.rpc(
      'fn_fdi_pagar_inversor',
      params: {'p_id_reparto': idReparto, 'p_referencia': referencia},
    );
  }

  Future<int> getDiasAlertaRevision(int idTienda) async {
    final row = await _supabase
        .from('fdi_dat_config')
        .select('dias_alerta_revision')
        .eq('id_tienda', idTienda)
        .maybeSingle();
    return (row?['dias_alerta_revision'] as num?)?.toInt() ?? 15;
  }

  Future<void> setDiasAlertaRevision(int idTienda, int dias) async {
    await _supabase.from('fdi_dat_config').upsert({
      'id_tienda': idTienda,
      'dias_alerta_revision': dias,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ==========================================================================
  // Liquidación
  // ==========================================================================

  Future<FdiVentasPeriodo> ventasPorMedioMoneda({
    required int idTienda,
    required DateTime? desde,
    required DateTime? hasta,
    required String modo,
  }) async {
    String? d(DateTime? x) => x?.toIso8601String().split('T').first;
    final resp = await _supabase.rpc(
      'fn_fdi_ventas_por_medio_moneda',
      params: {
        'p_id_tienda': idTienda,
        'p_desde': d(desde),
        'p_hasta': d(hasta),
        'p_modo': modo,
      },
    );
    return FdiVentasPeriodo.fromJson(_asMap(resp));
  }

  /// [detalle]: [{id_medio_pago, moneda, monto_ganancia_retirada}]
  Future<Map<String, dynamic>> crearLiquidacion({
    required int idTienda,
    required DateTime desde,
    required DateTime hasta,
    required String modo,
    required int idCuentaDestino,
    required List<Map<String, dynamic>> detalle,
    double? tasaValidacion,
    bool confirmarDiferencia = false,
    String? observacion,
    String? idempotencyKey,
    bool repartirIgual = false,
  }) async {
    String d(DateTime x) => x.toIso8601String().split('T').first;
    final resp = await _supabase.rpc(
      'fn_fdi_crear_liquidacion',
      params: {
        'p_id_tienda': idTienda,
        'p_desde': d(desde),
        'p_hasta': d(hasta),
        'p_modo': modo,
        'p_id_cuenta_destino': idCuentaDestino,
        'p_detalle': detalle,
        'p_tasa_validacion': tasaValidacion,
        'p_confirmar_diferencia': confirmarDiferencia,
        'p_observacion': observacion,
        'p_idempotency_key': idempotencyKey,
        'p_repartir_igual': repartirIgual,
      },
    );
    return _asMap(resp);
  }

  Future<List<FdiLiquidacion>> listLiquidaciones(
    int idTienda, {
    DateTime? desde,
    DateTime? hasta,
  }) async {
    String? d(DateTime? x) => x?.toIso8601String().split('T').first;
    final resp = await _supabase.rpc(
      'fn_fdi_liquidaciones',
      params: {
        'p_id_tienda': idTienda,
        'p_desde': d(desde),
        'p_hasta': d(hasta),
      },
    );
    return ((resp as List?) ?? [])
        .map(
          (e) => FdiLiquidacion.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<Map<String, dynamic>> ajusteCorreccionLiquidacion({
    required int idTienda,
    required int idLiquidacion,
    required int idMedioPago,
    required String moneda,
    required double monto,
    required String motivo,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_ajuste_correccion_liquidacion',
      params: {
        'p_id_tienda': idTienda,
        'p_id_liquidacion': idLiquidacion,
        'p_id_medio_pago': idMedioPago,
        'p_moneda': moneda,
        'p_monto': monto,
        'p_motivo': motivo,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  // ==========================================================================
  // Saldos y movimientos
  // ==========================================================================

  Future<FdiSaldosResult> saldos(int idTienda) async {
    final resp = await _supabase.rpc(
      'fn_fdi_saldos',
      params: {'p_id_tienda': idTienda},
    );
    return FdiSaldosResult.fromJson(_asMap(resp));
  }

  Future<List<FdiMovimiento>> movimientos(
    int idTienda, {
    DateTime? desde,
    DateTime? hasta,
    int? idConcepto,
    int? idCuenta,
    int? idMedioPago,
    String? moneda,
    String? tipo,
    int limite = 500,
  }) async {
    String? d(DateTime? x) => x?.toIso8601String().split('T').first;
    final resp = await _supabase.rpc(
      'fn_fdi_movimientos',
      params: {
        'p_id_tienda': idTienda,
        'p_desde': d(desde),
        'p_hasta': d(hasta),
        'p_id_concepto': idConcepto,
        'p_id_cuenta': idCuenta,
        'p_id_medio_pago': idMedioPago,
        'p_moneda': moneda,
        'p_tipo': tipo,
        'p_limite': limite,
      },
    );
    return ((resp as List?) ?? [])
        .map((e) => FdiMovimiento.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ==========================================================================
  // Transferencias
  // ==========================================================================

  Future<Map<String, dynamic>> transferir({
    required int idTienda,
    required int idCuentaOrigen,
    required int idMedioPagoOrigen,
    required String monedaOrigen,
    required int idCuentaDestino,
    required int idMedioPagoDestino,
    required String monedaDestino,
    required double montoDestino,
    double tasa = 1,
    double porcentajeCosto = 0,
    int? idTransferenciaCorregida,
    String? observacion,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_transferir',
      params: {
        'p_id_tienda': idTienda,
        'p_id_cuenta_origen': idCuentaOrigen,
        'p_id_medio_pago_origen': idMedioPagoOrigen,
        'p_moneda_origen': monedaOrigen,
        'p_id_cuenta_destino': idCuentaDestino,
        'p_id_medio_pago_destino': idMedioPagoDestino,
        'p_moneda_destino': monedaDestino,
        'p_monto_destino': montoDestino,
        'p_tasa': tasa,
        'p_porcentaje_costo': porcentajeCosto,
        'p_id_transferencia_corregida': idTransferenciaCorregida,
        'p_observacion': observacion,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  Future<List<FdiTransferencia>> listTransferencias(int idTienda) async {
    final rows = await _supabase
        .from('fdi_dat_transferencia')
        .select()
        .eq('id_tienda', idTienda)
        .order('created_at', ascending: false);
    return (rows as List)
        .map(
          (e) => FdiTransferencia.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  // ==========================================================================
  // Ingreso manual y ajuste
  // ==========================================================================

  Future<Map<String, dynamic>> ingresoManual({
    required int idTienda,
    required int idCuenta,
    required int idMedioPago,
    required String moneda,
    required double monto,
    DateTime? fecha,
    String? motivo,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_ingreso_manual',
      params: {
        'p_id_tienda': idTienda,
        'p_id_cuenta': idCuenta,
        'p_id_medio_pago': idMedioPago,
        'p_moneda': moneda,
        'p_monto': monto,
        'p_fecha': fecha?.toIso8601String().split('T').first,
        'p_motivo': motivo,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  Future<Map<String, dynamic>> ajuste({
    required int idTienda,
    required int idCuenta,
    required int idMedioPago,
    required String moneda,
    required double monto,
    required String motivo,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_ajuste',
      params: {
        'p_id_tienda': idTienda,
        'p_id_cuenta': idCuenta,
        'p_id_medio_pago': idMedioPago,
        'p_moneda': moneda,
        'p_monto': monto,
        'p_motivo': motivo,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  /// Descuenta saldo del fondo hacia un destino que no es inversión.
  Future<Map<String, dynamic>> gasto({
    required int idTienda,
    required int idCuenta,
    required int idMedioPago,
    required String moneda,
    required double monto,
    required String destino,
    String? motivo,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_gasto',
      params: {
        'p_id_tienda': idTienda,
        'p_id_cuenta': idCuenta,
        'p_id_medio_pago': idMedioPago,
        'p_moneda': moneda,
        'p_monto': monto,
        'p_destino': destino,
        'p_motivo': motivo,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  // ==========================================================================
  // Inversiones
  // ==========================================================================

  /// [fuentes]: [{id_cuenta, id_medio_pago, moneda, monto, tasa_a_ref}]
  Future<Map<String, dynamic>> crearInversion({
    required int idTienda,
    required String identificador,
    String? detalles,
    String? descripcion,
    required String monedaReferencia,
    required List<Map<String, dynamic>> fuentes,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_crear_inversion',
      params: {
        'p_id_tienda': idTienda,
        'p_identificador': identificador,
        'p_detalles': detalles,
        'p_descripcion': descripcion,
        'p_moneda_referencia': monedaReferencia,
        'p_fuentes': fuentes,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  Future<Map<String, dynamic>> cambiarEstadoInversion({
    required int idInversion,
    required String estado,
    String? motivo,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_cambiar_estado_inversion',
      params: {
        'p_id_inversion': idInversion,
        'p_estado': estado,
        'p_motivo': motivo,
      },
    );
    return _asMap(resp);
  }

  Future<Map<String, dynamic>> resolverRevision({
    required int idInversion,
    required String nota,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_resolver_revision',
      params: {'p_id_inversion': idInversion, 'p_nota': nota},
    );
    return _asMap(resp);
  }

  Future<List<FdiInversion>> listInversiones(
    int idTienda, {
    String? estado,
    bool soloRevision = false,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_inversiones',
      params: {
        'p_id_tienda': idTienda,
        'p_estado': estado,
        'p_solo_revision': soloRevision,
      },
    );
    return ((resp as List?) ?? [])
        .map((e) => FdiInversion.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> detalleInversion(int idInversion) async {
    final resp = await _supabase.rpc(
      'fn_fdi_detalle_inversion',
      params: {'p_id_inversion': idInversion},
    );
    return _asMap(resp);
  }

  /// Vincula una recepción ya registrada a una inversión.
  /// Devuelve status `requires_confirmation`/`exceso_recepcion` si supera el
  /// total esperado — reintentar con [confirmarExceso] = true tras confirmar
  /// en UI.
  Future<Map<String, dynamic>> vincularRecepcion({
    required int idOperacion,
    required int idInversion,
    required double monto,
    required String moneda,
    double tasaARef = 1,
    bool confirmarExceso = false,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_vincular_recepcion',
      params: {
        'p_id_operacion': idOperacion,
        'p_id_inversion': idInversion,
        'p_monto': monto,
        'p_moneda': moneda,
        'p_tasa_a_ref': tasaARef,
        'p_confirmar_exceso': confirmarExceso,
      },
    );
    return _asMap(resp);
  }

  // ==========================================================================
  // Catálogos de apoyo
  // ==========================================================================

  /// Medios de pago globales (app_nom_medio_pago).
  Future<List<Map<String, dynamic>>> listMediosPago() async {
    final rows = await _supabase
        .from('app_nom_medio_pago')
        .select('id, denominacion, es_efectivo, es_digital')
        .eq('es_activo', true)
        .order('id');
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Monedas activas de la nomenclatura global.
  Future<List<String>> listMonedas() async {
    final rows = await _supabase
        .from('monedas')
        .select('codigo')
        .eq('activo', true)
        .order('codigo');
    return (rows as List)
        .map((e) => (e['codigo']?.toString() ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toList();
  }
}
