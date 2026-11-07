/// Modelos del módulo Fondo de Inversión (tablas fdi_*).
library;

List<double> repartirGanancia(
  double monto,
  List<double> porcentajes, {
  bool repartirIgual = false,
}) {
  if (!monto.isFinite ||
      monto < 0 ||
      porcentajes.isEmpty ||
      porcentajes.any((p) => !p.isFinite || p <= 0 || p > 100)) {
    throw ArgumentError('Monto o participaciones inválidos');
  }
  final unidades = porcentajes.map((p) => (p * 10000).round()).toList();
  if (!repartirIgual && unidades.fold<int>(0, (s, p) => s + p) != 1000000) {
    throw ArgumentError('Las participaciones deben sumar 100%');
  }
  final centavos = (monto * 100).round();
  if ((monto - centavos / 100).abs() > 0.00000001) {
    throw ArgumentError('El monto debe tener como máximo dos decimales');
  }
  return [
    for (final porcentaje in unidades)
      (repartirIgual
              ? centavos ~/ (unidades.length * 100)
              : centavos * porcentaje ~/ 100000000)
          .toDouble(),
  ];
}

class FdiConcepto {
  final int id;
  final int idTienda;
  final String denominacion;
  final String? descripcion;
  final bool activo;

  const FdiConcepto({
    required this.id,
    required this.idTienda,
    required this.denominacion,
    this.descripcion,
    this.activo = true,
  });

  factory FdiConcepto.fromJson(Map<String, dynamic> j) => FdiConcepto(
    id: (j['id'] as num).toInt(),
    idTienda: (j['id_tienda'] as num).toInt(),
    denominacion: j['denominacion']?.toString() ?? '',
    descripcion: j['descripcion']?.toString(),
    activo: j['activo'] == true,
  );
}

class FdiCuenta {
  final int id;
  final int idConcepto;
  final int idTienda;
  final String nombre;
  final String? descripcion;
  final bool activo;

  const FdiCuenta({
    required this.id,
    required this.idConcepto,
    required this.idTienda,
    required this.nombre,
    this.descripcion,
    this.activo = true,
  });

  factory FdiCuenta.fromJson(Map<String, dynamic> j) => FdiCuenta(
    id: (j['id'] as num).toInt(),
    idConcepto: (j['id_concepto'] as num).toInt(),
    idTienda: (j['id_tienda'] as num).toInt(),
    nombre: j['nombre']?.toString() ?? '',
    descripcion: j['descripcion']?.toString(),
    activo: j['activo'] == true,
  );
}

/// Una fila del RPC fn_fdi_saldos: saldo por cuenta+medio+moneda.
class FdiSaldo {
  final int idCuenta;
  final String cuenta;
  final String concepto;
  final int? idMedioPago;
  final String medioPago;
  final String moneda;
  final double saldo;

  const FdiSaldo({
    required this.idCuenta,
    required this.cuenta,
    required this.concepto,
    this.idMedioPago,
    required this.medioPago,
    required this.moneda,
    required this.saldo,
  });

  factory FdiSaldo.fromJson(Map<String, dynamic> j) => FdiSaldo(
    idCuenta: (j['id_cuenta'] as num).toInt(),
    cuenta: j['cuenta']?.toString() ?? '',
    concepto: j['concepto']?.toString() ?? '',
    idMedioPago: (j['id_medio_pago'] as num?)?.toInt(),
    medioPago: j['medio_pago']?.toString() ?? '',
    moneda: j['moneda']?.toString() ?? '',
    saldo: (j['saldo'] as num?)?.toDouble() ?? 0,
  );
}

/// Respuesta de fn_fdi_saldos: filas + totales por moneda.
class FdiSaldosResult {
  final List<FdiSaldo> saldos;
  final Map<String, double> totalesPorMoneda;

  const FdiSaldosResult(this.saldos, this.totalesPorMoneda);

  factory FdiSaldosResult.fromJson(Map<String, dynamic> j) => FdiSaldosResult(
    ((j['saldos'] as List?) ?? [])
        .map((e) => FdiSaldo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    {
      for (final e in ((j['totales_por_moneda'] as Map?) ?? {}).entries)
        e.key.toString(): (e.value as num).toDouble(),
    },
  );
}

/// Una fila del RPC fn_fdi_ventas_por_medio_moneda (previo a liquidar).
class FdiVentaMedioMoneda {
  final int? idMedioPago;
  final String medioPago;
  final String moneda;
  final double montoVendido;
  final double montoVendidoCup;

  /// Cuánto de la ganancia retirar en este medio/moneda (editable en UI).
  double montoGananciaRetirada;

  FdiVentaMedioMoneda({
    this.idMedioPago,
    required this.medioPago,
    required this.moneda,
    required this.montoVendido,
    required this.montoVendidoCup,
    this.montoGananciaRetirada = 0,
  });

  double get montoInversion => montoVendido - montoGananciaRetirada;

  factory FdiVentaMedioMoneda.fromJson(Map<String, dynamic> j) =>
      FdiVentaMedioMoneda(
        idMedioPago: (j['id_medio_pago'] as num?)?.toInt(),
        medioPago: j['medio_pago']?.toString() ?? '',
        moneda: j['moneda']?.toString() ?? '',
        montoVendido: (j['monto_vendido'] as num?)?.toDouble() ?? 0,
        montoVendidoCup: (j['monto_vendido_cup'] as num?)?.toDouble() ?? 0,
      );
}

/// Respuesta completa de fn_fdi_ventas_por_medio_moneda.
class FdiVentasPeriodo {
  final int ordenesElegibles;
  final int ordenesExcluidas;
  final double ventaTotalCup;
  final double costoTotalCup;
  final double gananciaCup;
  final List<FdiVentaMedioMoneda> medios;

  const FdiVentasPeriodo({
    required this.ordenesElegibles,
    required this.ordenesExcluidas,
    required this.ventaTotalCup,
    required this.costoTotalCup,
    required this.gananciaCup,
    required this.medios,
  });

  factory FdiVentasPeriodo.fromJson(Map<String, dynamic> j) => FdiVentasPeriodo(
    ordenesElegibles: (j['ordenes_elegibles'] as num?)?.toInt() ?? 0,
    ordenesExcluidas: (j['ordenes_excluidas'] as num?)?.toInt() ?? 0,
    ventaTotalCup: (j['venta_total_cup'] as num?)?.toDouble() ?? 0,
    costoTotalCup: (j['costo_total_cup'] as num?)?.toDouble() ?? 0,
    gananciaCup: (j['ganancia_cup'] as num?)?.toDouble() ?? 0,
    medios: ((j['medios'] as List?) ?? [])
        .map(
          (e) =>
              FdiVentaMedioMoneda.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );
}

class FdiSeleccionGanancia {
  final origenes = <FdiVentaMedioMoneda>{};

  void inicializar(FdiVentasPeriodo ventas) {
    origenes.clear();
    for (final medio in ventas.medios) {
      medio.montoGananciaRetirada = 0;
    }
    if (ventas.medios.length == 1) {
      final medio = ventas.medios.single;
      origenes.add(medio);
      if (medio.moneda == 'CUP') {
        medio.montoGananciaRetirada = double.parse(
          ventas.gananciaCup.clamp(0.0, medio.montoVendido).toStringAsFixed(2),
        );
      }
    }
  }

  void seleccionar(
    FdiVentaMedioMoneda medio,
    bool selected, {
    required double pendienteCup,
    double? tasaCup,
  }) {
    if (!selected) {
      origenes.remove(medio);
      medio.montoGananciaRetirada = 0;
      return;
    }
    if (!origenes.add(medio)) return;
    final tasa = medio.moneda == 'CUP' ? 1.0 : tasaCup;
    if (tasa == null || !tasa.isFinite || tasa <= 0) return;
    medio.montoGananciaRetirada = double.parse(
      (pendienteCup.clamp(0.0, double.infinity) / tasa)
          .clamp(0.0, medio.montoVendido)
          .toStringAsFixed(2),
    );
  }

  List<Map<String, dynamic>> get detalle => [
    for (final medio in origenes)
      if (medio.montoGananciaRetirada > 0)
        {
          'id_medio_pago': medio.idMedioPago,
          'moneda': medio.moneda,
          'monto_ganancia_retirada': medio.montoGananciaRetirada,
        },
  ];
}

class FdiMovimiento {
  final int id;
  final int idCuenta;
  final String cuenta;
  final String concepto;
  final int? idMedioPago;
  final String medioPago;
  final String moneda;
  final double monto;
  final double saldoAnterior;
  final double saldoNuevo;
  final String tipo;
  final int? idLiquidacion;
  final int? idTransferencia;
  final int? idInversion;
  final String? observacion;
  final DateTime? createdAt;

  const FdiMovimiento({
    required this.id,
    required this.idCuenta,
    required this.cuenta,
    required this.concepto,
    this.idMedioPago,
    required this.medioPago,
    required this.moneda,
    required this.monto,
    required this.saldoAnterior,
    required this.saldoNuevo,
    required this.tipo,
    this.idLiquidacion,
    this.idTransferencia,
    this.idInversion,
    this.observacion,
    this.createdAt,
  });

  factory FdiMovimiento.fromJson(Map<String, dynamic> j) => FdiMovimiento(
    id: (j['id'] as num).toInt(),
    idCuenta: (j['id_cuenta'] as num).toInt(),
    cuenta: j['cuenta']?.toString() ?? '',
    concepto: j['concepto']?.toString() ?? '',
    idMedioPago: (j['id_medio_pago'] as num?)?.toInt(),
    medioPago: j['medio_pago']?.toString() ?? '',
    moneda: j['moneda']?.toString() ?? '',
    monto: (j['monto'] as num?)?.toDouble() ?? 0,
    saldoAnterior: (j['saldo_anterior'] as num?)?.toDouble() ?? 0,
    saldoNuevo: (j['saldo_nuevo'] as num?)?.toDouble() ?? 0,
    tipo: j['tipo']?.toString() ?? '',
    idLiquidacion: (j['id_liquidacion'] as num?)?.toInt(),
    idTransferencia: (j['id_transferencia'] as num?)?.toInt(),
    idInversion: (j['id_inversion'] as num?)?.toInt(),
    observacion: j['observacion']?.toString(),
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
  );
}

class FdiLiquidacion {
  final int id;
  final DateTime fechaDesde;
  final DateTime fechaHasta;
  final String modoFiltro;
  final double ventaTotal;
  final double costoTotal;
  final double gananciaReporte;
  final double? tasaValidacion;
  final double? gananciaRetiradaEquivalente;
  final double? diferenciaGanancia;
  final bool confirmadaConDiferencia;
  final String cuentaDestino;
  final String conceptoDestino;
  final int cantidadOrdenes;
  final String? observacion;
  final DateTime? createdAt;
  final List<Map<String, dynamic>> detalle;

  const FdiLiquidacion({
    required this.id,
    required this.fechaDesde,
    required this.fechaHasta,
    required this.modoFiltro,
    required this.ventaTotal,
    required this.costoTotal,
    required this.gananciaReporte,
    this.tasaValidacion,
    this.gananciaRetiradaEquivalente,
    this.diferenciaGanancia,
    this.confirmadaConDiferencia = false,
    required this.cuentaDestino,
    required this.conceptoDestino,
    required this.cantidadOrdenes,
    this.observacion,
    this.createdAt,
    this.detalle = const [],
  });

  factory FdiLiquidacion.fromJson(Map<String, dynamic> j) => FdiLiquidacion(
    id: (j['id'] as num).toInt(),
    fechaDesde:
        DateTime.tryParse(j['fecha_desde']?.toString() ?? '') ?? DateTime.now(),
    fechaHasta:
        DateTime.tryParse(j['fecha_hasta']?.toString() ?? '') ?? DateTime.now(),
    modoFiltro: j['modo_filtro']?.toString() ?? '',
    ventaTotal: (j['venta_total'] as num?)?.toDouble() ?? 0,
    costoTotal: (j['costo_total'] as num?)?.toDouble() ?? 0,
    gananciaReporte: (j['ganancia_reporte'] as num?)?.toDouble() ?? 0,
    tasaValidacion: (j['tasa_validacion'] as num?)?.toDouble(),
    gananciaRetiradaEquivalente: (j['ganancia_retirada_equivalente'] as num?)
        ?.toDouble(),
    diferenciaGanancia: (j['diferencia_ganancia'] as num?)?.toDouble(),
    confirmadaConDiferencia: j['confirmada_con_diferencia'] == true,
    cuentaDestino: j['cuenta_destino']?.toString() ?? '',
    conceptoDestino: j['concepto_destino']?.toString() ?? '',
    cantidadOrdenes: (j['cantidad_ordenes'] as num?)?.toInt() ?? 0,
    observacion: j['observacion']?.toString(),
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
    detalle: ((j['detalle'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
  );
}

class FdiTransferencia {
  final int id;
  final int idCuentaOrigen;
  final int? idMedioPagoOrigen;
  final String monedaOrigen;
  final int idCuentaDestino;
  final int? idMedioPagoDestino;
  final String monedaDestino;
  final double montoDestino;
  final double tasa;
  final double montoBaseOrigen;
  final double porcentajeCosto;
  final double montoComision;
  final double montoTotalOrigen;
  final int? idTransferenciaCorregida;
  final String? observacion;
  final DateTime? createdAt;

  const FdiTransferencia({
    required this.id,
    required this.idCuentaOrigen,
    this.idMedioPagoOrigen,
    required this.monedaOrigen,
    required this.idCuentaDestino,
    this.idMedioPagoDestino,
    required this.monedaDestino,
    required this.montoDestino,
    required this.tasa,
    required this.montoBaseOrigen,
    required this.porcentajeCosto,
    required this.montoComision,
    required this.montoTotalOrigen,
    this.idTransferenciaCorregida,
    this.observacion,
    this.createdAt,
  });

  factory FdiTransferencia.fromJson(Map<String, dynamic> j) => FdiTransferencia(
    id: (j['id'] as num).toInt(),
    idCuentaOrigen: (j['id_cuenta_origen'] as num).toInt(),
    idMedioPagoOrigen: (j['id_medio_pago_origen'] as num?)?.toInt(),
    monedaOrigen: j['moneda_origen']?.toString() ?? '',
    idCuentaDestino: (j['id_cuenta_destino'] as num).toInt(),
    idMedioPagoDestino: (j['id_medio_pago_destino'] as num?)?.toInt(),
    monedaDestino: j['moneda_destino']?.toString() ?? '',
    montoDestino: (j['monto_destino'] as num?)?.toDouble() ?? 0,
    tasa: (j['tasa'] as num?)?.toDouble() ?? 1,
    montoBaseOrigen: (j['monto_base_origen'] as num?)?.toDouble() ?? 0,
    porcentajeCosto: (j['porcentaje_costo'] as num?)?.toDouble() ?? 0,
    montoComision: (j['monto_comision'] as num?)?.toDouble() ?? 0,
    montoTotalOrigen: (j['monto_total_origen'] as num?)?.toDouble() ?? 0,
    idTransferenciaCorregida: (j['id_transferencia_corregida'] as num?)
        ?.toInt(),
    observacion: j['observacion']?.toString(),
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
  );
}

class FdiInversion {
  final int id;
  final int idTienda;
  final String identificador;
  final String? detalles;
  final String? descripcion;
  final String monedaReferencia;
  final double montoTotalRef;
  final double montoRecibidoRef;
  final String estado;
  final bool estadoManual;
  final bool requiereRevision;
  final bool enRevision;
  final String? motivoRevision;
  final double? montoFaltanteRef;
  final String? revisionNota;
  final DateTime? createdAt;

  const FdiInversion({
    required this.id,
    required this.idTienda,
    required this.identificador,
    this.detalles,
    this.descripcion,
    required this.monedaReferencia,
    required this.montoTotalRef,
    required this.montoRecibidoRef,
    required this.estado,
    this.estadoManual = false,
    this.requiereRevision = false,
    this.enRevision = false,
    this.motivoRevision,
    this.montoFaltanteRef,
    this.revisionNota,
    this.createdAt,
  });

  factory FdiInversion.fromJson(Map<String, dynamic> j) => FdiInversion(
    id: (j['id'] as num).toInt(),
    idTienda: (j['id_tienda'] as num).toInt(),
    identificador: j['identificador']?.toString() ?? '',
    detalles: j['detalles']?.toString(),
    descripcion: j['descripcion']?.toString(),
    monedaReferencia: j['moneda_referencia']?.toString() ?? '',
    montoTotalRef: (j['monto_total_ref'] as num?)?.toDouble() ?? 0,
    montoRecibidoRef: (j['monto_recibido_ref'] as num?)?.toDouble() ?? 0,
    estado: j['estado']?.toString() ?? 'pendiente',
    estadoManual: j['estado_manual'] == true,
    requiereRevision: j['requiere_revision'] == true,
    enRevision: j['en_revision'] == true || j['requiere_revision'] == true,
    motivoRevision: (j['motivo_revision_efectivo'] ?? j['motivo_revision'])
        ?.toString(),
    montoFaltanteRef: (j['monto_faltante_ref'] as num?)?.toDouble(),
    revisionNota: j['revision_nota']?.toString(),
    createdAt: j['created_at'] != null
        ? DateTime.tryParse(j['created_at'].toString())
        : null,
  );
}
