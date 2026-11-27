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

  /// Líneas de la compra con lo ya recibido y lo que falta
  /// (`fn_fdi_compra_recepcion_pendiente`).
  ///
  /// Devuelve todas las líneas, también las completas: la pantalla de recepción
  /// filtra por [LineaPendiente.tienePendiente]. Es la fuente de verdad, así que
  /// se relee antes de cada recepción y no se cachea.
  Future<List<LineaPendiente>> pendiente(int idCompra) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_recepcion_pendiente',
      params: {'p_id_compra': idCompra},
    );
    return ((_asMap(resp)['lineas'] as List?) ?? [])
        .map((e) => LineaPendiente.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
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

  // ==========================================================================
  // Liquidación: reserva y pago con el fondo
  // ==========================================================================

  /// Cuentas y medios con saldo para financiar compras de la tienda
  /// (`fn_fdi_disponible`). Devuelve el array jsonb ya tipado.
  ///
  /// `disponible` descuenta lo reservado por otras compras vivas; por eso hay
  /// que releerlo antes de cada reserva y no cachearlo.
  Future<List<DisponibleFondo>> disponible(int idTienda) async {
    final resp = await _supabase.rpc(
      'fn_fdi_disponible',
      params: {'p_id_tienda': idTienda},
    );
    return ((resp as List?) ?? [])
        .map(
          (e) => DisponibleFondo.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// Reserva el total en las [fuentes] indicadas y deja la compra en
  /// `reservada`. Devuelve `{status, id_compra, estado, cubierto,
  /// total_financiado}`.
  ///
  /// Cada fuente va en la moneda nativa de su cuenta; [FuenteReserva.tasaATotal]
  /// la convierte a la moneda del total. La suma de equivalentes redondeados
  /// debe cubrir exacto o la RPC rechaza. Reutiliza la misma [idempotencyKey]
  /// en los reintentos del mismo formulario (`newIdempotencyKey()`).
  Future<Map<String, dynamic>> reservar({
    required int idCompra,
    required List<FuenteReserva> fuentes,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_reservar',
      params: {
        'p_id_compra': idCompra,
        'p_fuentes': fuentes.map((f) => f.toJson()).toList(),
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  /// Último costo unitario con el que se compró ese producto en la tienda.
  /// Sirve para precargar la línea en el alta y no teclear de cero.
  Future<double?> ultimoCostoCompra({
    required int idTienda,
    required int idProducto,
  }) async {
    final rows = await _supabase
        .from('fdi_dat_compra_linea')
        .select('costo_unitario')
        .eq('id_tienda', idTienda)
        .eq('id_producto', idProducto)
        .order('id', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return (rows.first['costo_unitario'] as num?)?.toDouble();
  }

  /// Paga al proveedor la compra reservada y la deja en `pagada`. Devuelve
  /// `{status, id_compra, estado, pagado}` o `{status:'ok', duplicada:true}`.
  ///
  /// [tasaPago] solo hace falta cuando el pago y el total no están en la misma
  /// moneda; si se omite la RPC usa su valor por defecto.
  Future<Map<String, dynamic>> pagar(int idCompra, {double? tasaPago}) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_pagar',
      params: {'p_id_compra': idCompra, 'p_tasa_pago': tasaPago},
    );
    return _asMap(resp);
  }

  /// Libera las reservas de la compra sin pagarla. Devuelve `{status,
  /// id_compra, liberadas, estado}`.
  Future<Map<String, dynamic>> liberar(int idCompra, String motivo) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_liberar',
      params: {'p_id_compra': idCompra, 'p_motivo': motivo},
    );
    return _asMap(resp);
  }

  /// Anula la compra y devuelve al fondo lo reservado o pagado. Devuelve
  /// `{status, id_compra, estado, devuelto}` o
  /// `{status:'ok', duplicada:true, devuelto:0}`.
  Future<Map<String, dynamic>> anular(int idCompra, String motivo) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_anular',
      params: {'p_id_compra': idCompra, 'p_motivo': motivo},
    );
    return _asMap(resp);
  }

  // ==========================================================================
  // Recepción contra compra (fase 5b)
  // ==========================================================================

  /// Enlaza a su compra una recepción **ya registrada**
  /// (`fn_fdi_compra_vincular_recepcion`) y mueve el estado de la compra a
  /// `entrega_parcial` o `completada`.
  ///
  /// La RPC no crea la recepción: [idOperacion] tiene que existir, así que se
  /// llama después de `insertInventoryReception`. [lineas] va tal cual en
  /// `p_lineas`: `[{id_compra_linea, cantidad_recibida}]`.
  ///
  /// Si [confirmarExceso] es false y alguna línea supera el pendiente, la RPC
  /// lanza el error de exceso y no vincula nada; hay que reintentar el vínculo
  /// (no la recepción) con true.
  ///
  /// [pctImportadora] va en porcentaje 0..100 — la RPC guarda
  /// `round(base * pct / 100, 2) - reembolso` como cargo de importadora.
  /// [origenPago]: `fondo | wallet_importadora | wallet_proveedor | externo`.
  ///
  /// Devuelve `{status, id_compra, id_operacion, estado, pendiente_total,
  /// id_compra_recepcion, cargo_importadora}`.
  Future<Map<String, dynamic>> vincularRecepcion({
    required int idOperacion,
    required int idCompra,
    required List<Map<String, dynamic>> lineas,
    bool confirmarExceso = false,
    double pctImportadora = 0,
    double baseImportadora = 0,
    double reembolsoImportadora = 0,
    String origenPago = 'wallet_importadora',
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_vincular_recepcion',
      params: {
        'p_id_operacion': idOperacion,
        'p_id_compra': idCompra,
        'p_lineas': lineas,
        'p_confirmar_exceso': confirmarExceso,
        'p_pct_importadora': pctImportadora,
        'p_base_importadora': baseImportadora,
        'p_reembolso_importadora': reembolsoImportadora,
        'p_origen_pago': origenPago,
      },
    );
    return _asMap(resp);
  }

  /// Resumen del costo aterrizado de la compra
  /// (`fn_fdi_compra_costo_resumen`): valor de factura vinculado, cargo de
  /// importadora, % declarado vs efectivo con su desvío, y qué parte de los
  /// ajustes globales se aplica según lo recibido.
  ///
  /// Es de solo lectura: el aterrizaje se persiste al vincular/repartir y el
  /// promedio lo capitaliza `fn_actualizar_precio_promedio_recepcion_v2`.
  Future<Map<String, dynamic>> costoResumen(int idCompra) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_costo_resumen',
      params: {'p_id_compra': idCompra},
    );
    return _asMap(resp);
  }

  /// Reparte el cargo de importadora del vínculo entre sus líneas
  /// (`fn_fdi_compra_repartir_aterrizaje`). Idempotente: reemplaza las filas
  /// del tipo Importadora del vínculo, no las de otra compra.
  ///
  /// Devuelve `{status: ok|sin_cargo|omitido, capitaliza, suma_monto_usd,
  /// filas_insertadas, filas_retiradas, tasa_usd_aplicada, ...}`.
  Future<Map<String, dynamic>> repartirAterrizaje(
    int idCompraRecepcion, {
    double? tasaUsd,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_repartir_aterrizaje',
      params: {
        'p_id_compra_recepcion': idCompraRecepcion,
        if (tasaUsd != null) 'p_tasa_usd': tasaUsd,
      },
    );
    return _asMap(resp);
  }

  /// Agrega un costo que llega **después de pagar** la compra
  /// (`fn_fdi_compra_ajuste_agregar`). Nace en `por_financiar`: no mueve
  /// `total_financiado`; se cubre con [financiarAjuste].
  ///
  /// [base]: `global` | `porcentaje` | `unidad`. [valor] es el importe (global),
  /// el % (porcentaje) o el importe por unidad (unidad). Solo origen `fondo`.
  Future<Map<String, dynamic>> agregarAjuste({
    required int idCompra,
    required int idTipoCosto,
    required String base,
    required double valor,
    String reparto = 'valor',
    bool afectaInventario = true,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_ajuste_agregar',
      params: {
        'p_id_compra': idCompra,
        'p_id_tipo_costo': idTipoCosto,
        'p_base': base,
        'p_valor': valor,
        'p_reparto': reparto,
        'p_afecta_inventario': afectaInventario,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  /// Financia un ajuste `por_financiar`: reserva y pago propios desde las
  /// fuentes dadas (misma forma que `fn_fdi_compra_reservar`), reparte el
  /// costo sobre lo recibido y actualiza la valoración. Requiere la compra
  /// **completada**.
  Future<Map<String, dynamic>> financiarAjuste({
    required int idAjuste,
    required List<Map<String, dynamic>> fuentes,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_ajuste_financiar',
      params: {
        'p_id_ajuste': idAjuste,
        'p_fuentes': fuentes,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  // ==========================================================================
  // Aportes de inversores (fase 7)
  // ==========================================================================
  //
  // Solo aplican a compras con `modo_liquidacion = 'inversores'`: los aportes
  // cubren el total y `fn_fdi_compra_pagar` no debita el fondo. El pago sigue
  // siendo [pagar]: la RPC tiene una rama propia para ese modo.

  /// Desglose de aportes de la compra, tal cual lo arma el servidor
  /// (`fn_fdi_compra_aportes`): `{id_compra, modo_liquidacion, estado, moneda,
  /// total, aportado, devuelto, faltante, pct, puede_registrar, puede_pagar,
  /// motivo_bloqueo, aportes[]}`.
  ///
  /// `motivo_bloqueo` es `null` cuando se puede pagar; si no, trae el texto
  /// real del bloqueo («Faltan 500.00 USD», «La compra ya está pagada», ...).
  /// Es de solo lectura y se relee antes de cada operación: no se cachea.
  Future<Map<String, dynamic>> aportesCompra(int idCompra) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_aportes',
      params: {'p_id_compra': idCompra},
    );
    return _asMap(resp);
  }

  /// Registra el aporte de un inversor (`fn_fdi_compra_aporte_registrar`).
  ///
  /// [monto] va en [moneda] y [tasaATotal] la lleva a la moneda del total de la
  /// compra; si [moneda] ya es la de la compra la RPC fuerza la tasa a 1. La
  /// RPC rechaza que el equivalente supere el faltante.
  ///
  /// [naturaleza]: `anticipo | pasivo | capital`; [tasaInteres] solo tiene
  /// sentido con `pasivo`.
  ///
  /// Devuelve `{status, id, id_compra, id_inversor, inversor, moneda, monto,
  /// tasa_a_total, monto_eq_total, aportado, faltante, total}` o
  /// `{status:'ok', duplicada:true, id, id_compra, monto_eq_total, estado}`
  /// cuando la [idempotencyKey] ya se usó.
  ///
  /// [idempotencyKey] se genera **una vez por formulario** (ver
  /// [newIdempotencyKey]) y se reutiliza en los reintentos: si el diálogo la
  /// volviera a crear, un reintento tras un timeout duplicaría el aporte.
  Future<Map<String, dynamic>> registrarAporte({
    required int idCompra,
    required int idInversor,
    required String moneda,
    required double monto,
    double tasaATotal = 1,
    String naturaleza = 'anticipo',
    double? tasaInteres,
    String? comprobante,
    String? observacion,
    String? idempotencyKey,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_aporte_registrar',
      params: {
        'p_id_compra': idCompra,
        'p_id_inversor': idInversor,
        'p_moneda': moneda,
        'p_monto': monto,
        'p_tasa_a_total': tasaATotal,
        'p_naturaleza': naturaleza,
        'p_tasa_interes': tasaInteres,
        'p_comprobante': comprobante,
        'p_observacion': observacion,
        'p_idempotency_key': idempotencyKey,
      },
    );
    return _asMap(resp);
  }

  /// Marca un aporte como devuelto (`fn_fdi_compra_aporte_devolver`). El monto
  /// vuelve a contar como faltante; **el dinero no regresa al fondo**, porque
  /// nunca salió de él.
  ///
  /// [motivo] es obligatorio. Devuelve `{status, id, id_compra, id_inversor,
  /// devuelto_monto, aportado, devuelto, faltante, estado_compra,
  /// estado_cambiado}` o `{status:'ok', duplicada:true, id}` si el aporte ya
  /// estaba devuelto.
  Future<Map<String, dynamic>> devolverAporte({
    required int idAporte,
    required String motivo,
  }) async {
    final resp = await _supabase.rpc(
      'fn_fdi_compra_aporte_devolver',
      params: {'p_id_aporte': idAporte, 'p_motivo': motivo},
    );
    return _asMap(resp);
  }
}
