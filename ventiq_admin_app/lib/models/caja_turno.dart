// Modelos del tab "Turnos Tpv": turno de caja (app_dat_caja_turno),
// desglose de cobros por medio de pago y reporte de discrepancias
// extraido del texto libre de `observaciones`.

/// Una linea de discrepancia detectada en el cierre de turno.
class DiscrepanciaInventario {
  final double cantidad;
  final String producto;
  final bool esFaltante;

  const DiscrepanciaInventario({
    required this.cantidad,
    required this.producto,
    required this.esFaltante,
  });

  bool get esExceso => !esFaltante;
}

/// Cobro agrupado por medio de pago (viene del jsonb `desglose_pagos`).
class PagoMedio {
  final String medio;
  final double monto;
  final bool esEfectivo;
  final int cantidad;

  const PagoMedio({
    required this.medio,
    required this.monto,
    required this.esEfectivo,
    required this.cantidad,
  });

  factory PagoMedio.fromJson(Map<String, dynamic> json) {
    return PagoMedio(
      medio: json['medio']?.toString() ?? 'Sin medio',
      monto: (json['monto'] as num?)?.toDouble() ?? 0,
      esEfectivo: json['es_efectivo'] == true,
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Cierre de una divisa dentro del turno (viene del jsonb `desglose_monedas`).
///
/// Los importes `*Nativo` están en [moneda] y no se pueden sumar entre sí ni
/// con el equivalente: el único consolidado comparable es [importeBase], ya
/// convertido a la moneda base de la tienda.
class DesgloseMoneda {
  final String moneda;
  final int operaciones;
  final double importeNativo;
  final double importeBase;
  final double efectivoNativo;
  final double digitalNativo;

  const DesgloseMoneda({
    required this.moneda,
    required this.operaciones,
    required this.importeNativo,
    required this.importeBase,
    required this.efectivoNativo,
    required this.digitalNativo,
  });

  factory DesgloseMoneda.fromJson(Map<String, dynamic> json) {
    return DesgloseMoneda(
      moneda: json['moneda']?.toString() ?? 'Sin divisa',
      operaciones: (json['operaciones'] as num?)?.toInt() ?? 0,
      importeNativo: (json['importe_nativo'] as num?)?.toDouble() ?? 0,
      importeBase: (json['importe_base'] as num?)?.toDouble() ?? 0,
      efectivoNativo: (json['efectivo_nativo'] as num?)?.toDouble() ?? 0,
      digitalNativo: (json['digital_nativo'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'moneda': moneda,
      'operaciones': operaciones,
      'importe_nativo': importeNativo,
      'importe_base': importeBase,
      'efectivo_nativo': efectivoNativo,
      'digital_nativo': digitalNativo,
    };
  }
}

/// Desglose por divisa del cierre de un turno, tal como lo devuelve
/// `fn_resumen_turno_por_id_v2`.
///
/// Es tolerante por diseño: si la `_v2` no está desplegada o el turno es
/// anterior a la migración no llegan `desglose_monedas` ni `total_base`, la
/// lista queda vacía y la UI omite la sección sin romper el detalle.
class DesgloseTurnoMonedas {
  final List<DesgloseMoneda> monedas;

  /// Consolidado en la moneda base; null si el RPC no mandó la columna.
  final double? totalBase;

  const DesgloseTurnoMonedas({required this.monedas, this.totalBase});

  factory DesgloseTurnoMonedas.empty() =>
      const DesgloseTurnoMonedas(monedas: []);

  /// Parsea la fila cruda del RPC (`null` cuando no devolvió filas). Se usa
  /// igual desde el servicio y desde [CajaTurno.fromJson], de modo que la
  /// tolerancia es la misma venga la fila del listado o del detalle.
  factory DesgloseTurnoMonedas.fromRow(Map<String, dynamic>? row) {
    if (row == null) return DesgloseTurnoMonedas.empty();

    final crudo = row['desglose_monedas'];
    final monedas = crudo is List
        ? crudo
              .whereType<Map>()
              .map(
                (item) =>
                    DesgloseMoneda.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : const <DesgloseMoneda>[];

    // `total_base` es numeric: se reutiliza el parser del turno para aceptar
    // tanto número JSON como texto.
    return DesgloseTurnoMonedas(
      monedas: monedas,
      totalBase: CajaTurno._toDouble(row['total_base']),
    );
  }

  /// La tabla solo aporta con varias divisas: una sola repetiría el total que
  /// la sección "Ventas" ya muestra (y sin desglose la lista también está
  /// vacía, así que cubre los dos casos).
  bool get tieneVariasDivisas => monedas.length > 1;

  /// Consolidado en moneda base. Si el RPC no mandó `total_base` se usa la
  /// suma de los equivalentes, que ya están todos en moneda base (es la misma
  /// cuenta que hace `fn_desglose_monedas_turno`).
  double get totalEquivalenteBase =>
      totalBase ?? monedas.fold<double>(0, (suma, m) => suma + m.importeBase);
}

/// Reporte de discrepancias parseado desde `observaciones`.
///
/// El TPV graba el texto con este formato:
///
///   FALTANTES:
///   Faltan 24.00 unidades de PASTA TOMATE VICTORIA 400 g
///   Faltan 103766.14 unidades de ACEITE
///
///   EXCESOS:
///   Sobran 432.00 unidades de GALLETAS NUTRO FRESA
///
/// Se tolera texto libre antes/después y encabezados ausentes: la
/// clasificación real se toma del verbo (Faltan / Sobran), y el
/// encabezado solo se usa como respaldo cuando la línea no lo trae.
class ReporteDiscrepancias {
  final List<DiscrepanciaInventario> faltantes;
  final List<DiscrepanciaInventario> excesos;

  /// Líneas que no encajaron en el formato esperado (notas manuales, etc.).
  final List<String> notas;

  const ReporteDiscrepancias({
    required this.faltantes,
    required this.excesos,
    required this.notas,
  });

  factory ReporteDiscrepancias.empty() {
    return const ReporteDiscrepancias(faltantes: [], excesos: [], notas: []);
  }

  static final RegExp _lineaRegExp = RegExp(
    r'^(faltan|sobran|falta|sobra)\s+([\d.,]+)\s*(?:unidades?|uds?\.?|u\.?)?\s*(?:de\s+)?(.+)$',
    caseSensitive: false,
  );

  static final RegExp _encabezadoRegExp = RegExp(
    r'^\s*(faltantes|excesos|sobrantes)\s*:?\s*$',
    caseSensitive: false,
  );

  /// Parsea el texto de `observaciones`. Nunca lanza: cualquier línea
  /// no reconocida cae en [notas] para que el auditor igual la vea.
  factory ReporteDiscrepancias.parse(String? observaciones) {
    if (observaciones == null || observaciones.trim().isEmpty) {
      return ReporteDiscrepancias.empty();
    }

    final faltantes = <DiscrepanciaInventario>[];
    final excesos = <DiscrepanciaInventario>[];
    final notas = <String>[];

    // null = aún no se vio ningún encabezado
    bool? seccionEsFaltante;

    for (final rawLine in observaciones.split(RegExp(r'\r?\n'))) {
      final linea = rawLine.trim();
      if (linea.isEmpty) continue;

      final encabezado = _encabezadoRegExp.firstMatch(linea);
      if (encabezado != null) {
        seccionEsFaltante =
            encabezado.group(1)!.toLowerCase().startsWith('faltante');
        continue;
      }

      final match = _lineaRegExp.firstMatch(linea);
      if (match == null) {
        notas.add(linea);
        continue;
      }

      final verbo = match.group(1)!.toLowerCase();
      final esFaltante =
          verbo.startsWith('falta') ? true : (verbo.startsWith('sobra') ? false : seccionEsFaltante);

      if (esFaltante == null) {
        notas.add(linea);
        continue;
      }

      final cantidad = _parseCantidad(match.group(2)!);
      final producto = match.group(3)!.trim();
      if (producto.isEmpty) {
        notas.add(linea);
        continue;
      }

      final item = DiscrepanciaInventario(
        cantidad: cantidad,
        producto: producto,
        esFaltante: esFaltante,
      );
      if (esFaltante) {
        faltantes.add(item);
      } else {
        excesos.add(item);
      }
    }

    // Mayor impacto primero: es lo que el auditor revisa antes.
    faltantes.sort((a, b) => b.cantidad.compareTo(a.cantidad));
    excesos.sort((a, b) => b.cantidad.compareTo(a.cantidad));

    return ReporteDiscrepancias(
      faltantes: faltantes,
      excesos: excesos,
      notas: notas,
    );
  }

  /// Acepta "103766.14", "1,234.56" y "1.234,56".
  static double _parseCantidad(String raw) {
    var texto = raw.trim();
    final tienePunto = texto.contains('.');
    final tieneComa = texto.contains(',');

    if (tienePunto && tieneComa) {
      // El último separador es el decimal.
      if (texto.lastIndexOf(',') > texto.lastIndexOf('.')) {
        texto = texto.replaceAll('.', '').replaceAll(',', '.');
      } else {
        texto = texto.replaceAll(',', '');
      }
    } else if (tieneComa) {
      // Coma sola: decimal si deja 1-2 dígitos al final, si no es de miles.
      final partes = texto.split(',');
      texto =
          (partes.length == 2 && partes.last.length <= 2)
              ? texto.replaceAll(',', '.')
              : texto.replaceAll(',', '');
    }

    return double.tryParse(texto) ?? 0;
  }

  bool get tieneDiscrepancias => faltantes.isNotEmpty || excesos.isNotEmpty;
  bool get estaVacio => !tieneDiscrepancias && notas.isEmpty;
  int get totalLineas => faltantes.length + excesos.length;
  double get unidadesFaltantes =>
      faltantes.fold<double>(0, (sum, d) => sum + d.cantidad);
  double get unidadesExcedentes =>
      excesos.fold<double>(0, (sum, d) => sum + d.cantidad);
}

/// Turno de caja con todos los agregados que devuelve
/// `fn_listar_turnos_admin` (un solo viaje al servidor).
class CajaTurno {
  final int id;
  final int idTpv;
  final String tpvDenominacion;
  final int? idVendedor;
  final String? vendedorNombre;
  final String? vendedorUuid;
  final int? idTrabajador;

  final int estado;
  final String? estadoDenominacion;

  final DateTime fechaApertura;
  final DateTime? fechaCierre;
  final double duracionMinutos;
  final bool manejaInventario;

  final int? idOperacionApertura;
  final int? idOperacionCierre;

  // Conciliación de efectivo
  final double efectivoInicial;
  final double? efectivoEsperadoRegistrado;
  final double efectivoEsperadoCalculado;
  final double? efectivoReal;
  final double? diferenciaRegistrada;
  final double? diferenciaCalculada;
  final String conciliacionEstado;

  // KPIs de venta
  final double ventasTotales;
  final int operacionesVenta;
  final int ventasPagadas;
  final double ticketPromedio;
  final double productosVendidos;

  // Cobros
  final double totalPagos;
  final double totalEfectivo;
  final double totalDigital;
  final double porcentajeEfectivo;
  final List<PagoMedio> desglosePagos;

  // Desglose por divisa. Solo lo traen `fn_resumen_turno_por_id_v2` y la carga
  // bajo demanda del detalle, así que en el listado viaja vacío.
  final List<DesgloseMoneda> desgloseMonedas;

  /// Consolidado en moneda base de [desgloseMonedas]; null si no vino.
  final double? totalBase;

  // Egresos (entregas parciales de caja)
  final double totalEgresos;
  final int egresosCantidad;

  // Cierre
  final String? observaciones;
  final int obsFaltantesCant;
  final int obsExcesosCant;
  final String? cerradoPorNombre;

  /// Discrepancias ya parseadas desde [observaciones].
  final ReporteDiscrepancias reporte;

  const CajaTurno({
    required this.id,
    required this.idTpv,
    required this.tpvDenominacion,
    this.idVendedor,
    this.vendedorNombre,
    this.vendedorUuid,
    this.idTrabajador,
    required this.estado,
    this.estadoDenominacion,
    required this.fechaApertura,
    this.fechaCierre,
    required this.duracionMinutos,
    required this.manejaInventario,
    this.idOperacionApertura,
    this.idOperacionCierre,
    required this.efectivoInicial,
    this.efectivoEsperadoRegistrado,
    required this.efectivoEsperadoCalculado,
    this.efectivoReal,
    this.diferenciaRegistrada,
    this.diferenciaCalculada,
    required this.conciliacionEstado,
    required this.ventasTotales,
    required this.operacionesVenta,
    required this.ventasPagadas,
    required this.ticketPromedio,
    required this.productosVendidos,
    required this.totalPagos,
    required this.totalEfectivo,
    required this.totalDigital,
    required this.porcentajeEfectivo,
    required this.desglosePagos,
    this.desgloseMonedas = const [],
    this.totalBase,
    required this.totalEgresos,
    required this.egresosCantidad,
    this.observaciones,
    required this.obsFaltantesCant,
    required this.obsExcesosCant,
    this.cerradoPorNombre,
    required this.reporte,
  });

  /// Acepta tanto las filas de `fn_listar_turnos_admin` (columnas planas)
  /// como el fallback PostgREST con recursos embebidos (`tpv`, `vendedor`,
  /// `estado_operacion`), donde los KPIs no vienen.
  factory CajaTurno.fromJson(Map<String, dynamic> json) {
    final observaciones = json['observaciones']?.toString();
    final reporte = ReporteDiscrepancias.parse(observaciones);

    // Un solo parseo para las dos columnas nuevas; sin la `_v2` queda vacío.
    final desglose = DesgloseTurnoMonedas.fromRow(json);

    final fechaApertura = _parseDate(json['fecha_apertura']) ?? DateTime.now();
    final fechaCierre = _parseDate(json['fecha_cierre']);

    final efectivoInicial = _toDouble(json['efectivo_inicial']) ?? 0;
    final efectivoReal = _toDouble(json['efectivo_real']);
    final totalEfectivo = _toDouble(json['total_efectivo']) ?? 0;
    final totalEgresos = _toDouble(json['total_egresos']) ?? 0;
    final estado = _toInt(json['estado']) ?? 1;

    // El fallback no trae las columnas calculadas: se derivan aquí para que
    // la UI se comporte igual con RPC o sin ella.
    final esperadoCalculado =
        _toDouble(json['efectivo_esperado_calculado']) ??
        (efectivoInicial + totalEfectivo - totalEgresos);

    double? diferenciaCalculada = _toDouble(json['diferencia_calculada']);
    if (diferenciaCalculada == null && efectivoReal != null) {
      diferenciaCalculada = efectivoReal - esperadoCalculado;
    }

    return CajaTurno(
      id: _toInt(json['turno_id']) ?? _toInt(json['id']) ?? 0,
      idTpv: _toInt(json['id_tpv']) ?? 0,
      tpvDenominacion:
          json['tpv_denominacion']?.toString() ??
          _embedded(json['tpv'])?['denominacion']?.toString() ??
          'TPV sin nombre',
      idVendedor: _toInt(json['id_vendedor']),
      vendedorNombre:
          json['vendedor_nombre']?.toString() ??
          _nombreTrabajadorEmbebido(json['vendedor']),
      vendedorUuid:
          json['vendedor_uuid']?.toString() ??
          _embedded(json['vendedor'])?['uuid']?.toString(),
      idTrabajador:
          _toInt(json['id_trabajador']) ??
          _toInt(_embedded(json['vendedor'])?['id_trabajador']),
      estado: estado,
      estadoDenominacion:
          json['estado_denominacion']?.toString() ??
          _embedded(json['estado_operacion'])?['denominacion']?.toString(),
      fechaApertura: fechaApertura,
      fechaCierre: fechaCierre,
      duracionMinutos:
          _toDouble(json['duracion_minutos']) ??
          (fechaCierre ?? DateTime.now())
                  .difference(fechaApertura)
                  .inSeconds /
              60.0,
      manejaInventario: json['maneja_inventario'] == true,
      idOperacionApertura: _toInt(json['id_operacion_apertura']),
      idOperacionCierre: _toInt(json['id_operacion_cierre']),
      efectivoInicial: efectivoInicial,
      efectivoEsperadoRegistrado:
          _toDouble(json['efectivo_esperado_registrado']) ??
          _toDouble(json['efectivo_esperado']),
      efectivoEsperadoCalculado: esperadoCalculado,
      efectivoReal: efectivoReal,
      diferenciaRegistrada:
          _toDouble(json['diferencia_registrada']) ??
          _toDouble(json['diferencia']),
      diferenciaCalculada: diferenciaCalculada,
      conciliacionEstado:
          json['conciliacion_estado']?.toString() ??
          _conciliacionFallback(
            estado: estado,
            fechaCierre: fechaCierre,
            efectivoReal: efectivoReal,
            diferencia: diferenciaCalculada,
          ),
      ventasTotales: _toDouble(json['ventas_totales']) ?? 0,
      operacionesVenta: _toInt(json['operaciones_venta']) ?? 0,
      ventasPagadas: _toInt(json['ventas_pagadas']) ?? 0,
      ticketPromedio: _toDouble(json['ticket_promedio']) ?? 0,
      productosVendidos: _toDouble(json['productos_vendidos']) ?? 0,
      totalPagos: _toDouble(json['total_pagos']) ?? 0,
      totalEfectivo: totalEfectivo,
      totalDigital: _toDouble(json['total_digital']) ?? 0,
      porcentajeEfectivo: _toDouble(json['porcentaje_efectivo']) ?? 0,
      desglosePagos: _parseDesglose(json['desglose_pagos']),
      desgloseMonedas: desglose.monedas,
      totalBase: desglose.totalBase,
      totalEgresos: totalEgresos,
      egresosCantidad: _toInt(json['egresos_cantidad']) ?? 0,
      observaciones: observaciones,
      obsFaltantesCant:
          _toInt(json['obs_faltantes_cant']) ?? reporte.faltantes.length,
      obsExcesosCant:
          _toInt(json['obs_excesos_cant']) ?? reporte.excesos.length,
      cerradoPorNombre: json['cerrado_por_nombre']?.toString(),
      reporte: reporte,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'turno_id': id,
      'id_tpv': idTpv,
      'tpv_denominacion': tpvDenominacion,
      'id_vendedor': idVendedor,
      'vendedor_nombre': vendedorNombre,
      'vendedor_uuid': vendedorUuid,
      'id_trabajador': idTrabajador,
      'estado': estado,
      'estado_denominacion': estadoDenominacion,
      'fecha_apertura': fechaApertura.toIso8601String(),
      'fecha_cierre': fechaCierre?.toIso8601String(),
      'duracion_minutos': duracionMinutos,
      'maneja_inventario': manejaInventario,
      'id_operacion_apertura': idOperacionApertura,
      'id_operacion_cierre': idOperacionCierre,
      'efectivo_inicial': efectivoInicial,
      'efectivo_esperado_registrado': efectivoEsperadoRegistrado,
      'efectivo_esperado_calculado': efectivoEsperadoCalculado,
      'efectivo_real': efectivoReal,
      'diferencia_registrada': diferenciaRegistrada,
      'diferencia_calculada': diferenciaCalculada,
      'conciliacion_estado': conciliacionEstado,
      'ventas_totales': ventasTotales,
      'operaciones_venta': operacionesVenta,
      'ventas_pagadas': ventasPagadas,
      'ticket_promedio': ticketPromedio,
      'productos_vendidos': productosVendidos,
      'total_pagos': totalPagos,
      'total_efectivo': totalEfectivo,
      'total_digital': totalDigital,
      'porcentaje_efectivo': porcentajeEfectivo,
      'desglose_monedas': desgloseMonedas.map((m) => m.toJson()).toList(),
      'total_base': totalBase,
      'total_egresos': totalEgresos,
      'egresos_cantidad': egresosCantidad,
      'observaciones': observaciones,
      'obs_faltantes_cant': obsFaltantesCant,
      'obs_excesos_cant': obsExcesosCant,
      'cerrado_por_nombre': cerradoPorNombre,
    };
  }

  // ==================== Getters de presentación ====================

  bool get estaAbierto => estado == 1 || fechaCierre == null;
  bool get estaCerrado => !estaAbierto;
  bool get sinConteo => estaCerrado && efectivoReal == null;

  /// Etiqueta corta del ciclo de vida del turno.
  String get estadoLabel {
    if (estaAbierto) return 'Abierto';
    switch (estado) {
      case 2:
        return 'Cerrado';
      case 3:
      case 4:
        return 'Cancelado';
      case 5:
        return 'Anulado';
      default:
        return estadoDenominacion ?? 'Cerrado';
    }
  }

  String get vendedorDisplay {
    final nombre = vendedorNombre?.trim();
    if (nombre == null || nombre.isEmpty) {
      return idVendedor != null
          ? 'Vendedor #$idVendedor'
          : 'Vendedor no disponible';
    }
    return nombre;
  }

  String get cerradoPorDisplay {
    final nombre = cerradoPorNombre?.trim();
    if (nombre == null || nombre.isEmpty) return 'No registrado';
    return nombre;
  }

  /// Duración legible: "7h 32m", "45m" o "—" si aún no aplica.
  String get duracionDisplay {
    final minutos = duracionMinutos.round();
    if (minutos <= 0) return '0m';
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    if (horas <= 0) return '${resto}m';
    if (resto == 0) return '${horas}h';
    return '${horas}h ${resto}m';
  }

  double get diferenciaAbsoluta => (diferenciaCalculada ?? 0).abs();
  bool get esFaltanteEfectivo => (diferenciaCalculada ?? 0) < -0.005;
  bool get esSobranteEfectivo => (diferenciaCalculada ?? 0) > 0.005;
  bool get estaConciliado =>
      efectivoReal != null && diferenciaAbsoluta < 0.005;

  /// El `efectivo_esperado` grabado por el TPV suele venir en 0, lo que
  /// vuelve engañosa la columna generada `diferencia`. Este flag avisa
  /// para que la UI muestre la conciliación recalculada.
  bool get esperadoRegistradoDudoso =>
      (efectivoEsperadoRegistrado ?? 0).abs() < 0.005 &&
      efectivoEsperadoCalculado.abs() >= 0.005;

  bool get tieneDiscrepanciasInventario =>
      obsFaltantesCant > 0 || obsExcesosCant > 0;
  bool get tieneObservaciones =>
      observaciones != null && observaciones!.trim().isNotEmpty;

  /// Cuánto de lo cobrado sigue en caja tras las entregas parciales.
  bool get tieneEgresos => egresosCantidad > 0;

  /// Requiere revisión del auditor: descuadre de efectivo o de inventario.
  bool get requiereAtencion =>
      estaCerrado &&
      (sinConteo || diferenciaAbsoluta > 1.00 || tieneDiscrepanciasInventario);

  // ==================== Helpers de parseo ====================

  static Map<String, dynamic>? _embedded(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    // PostgREST puede devolver el recurso embebido como lista de 1 elemento.
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  static String? _nombreTrabajadorEmbebido(dynamic vendedor) {
    final trabajador = _embedded(_embedded(vendedor)?['trabajador']);
    if (trabajador == null) return null;
    final nombre =
        '${trabajador['nombres'] ?? ''} ${trabajador['apellidos'] ?? ''}'.trim();
    return nombre.isEmpty ? null : nombre;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  static List<PagoMedio> _parseDesglose(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => PagoMedio.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static String _conciliacionFallback({
    required int estado,
    required DateTime? fechaCierre,
    required double? efectivoReal,
    required double? diferencia,
  }) {
    if (estado == 1 || fechaCierre == null) return 'Abierto';
    if (efectivoReal == null) return 'Sin conteo';
    final d = diferencia ?? 0;
    if (d.abs() < 0.005) return 'Conciliado';
    if (d.abs() <= 1.00) return 'Casi exacto';
    return d > 0 ? 'Sobrante' : 'Faltante';
  }
}

/// Página de resultados + total global (viene en `total_registros`).
class CajaTurnoResponse {
  final List<CajaTurno> turnos;
  final int totalCount;

  const CajaTurnoResponse({required this.turnos, required this.totalCount});

  factory CajaTurnoResponse.empty() {
    return const CajaTurnoResponse(turnos: [], totalCount: 0);
  }

  bool get isEmpty => turnos.isEmpty;

  // ==================== Totales de la página ====================

  double get ventasTotales =>
      turnos.fold<double>(0, (sum, t) => sum + t.ventasTotales);
  double get efectivoCobrado =>
      turnos.fold<double>(0, (sum, t) => sum + t.totalEfectivo);
  double get digitalCobrado =>
      turnos.fold<double>(0, (sum, t) => sum + t.totalDigital);
  double get egresos => turnos.fold<double>(0, (sum, t) => sum + t.totalEgresos);
  int get turnosAbiertos => turnos.where((t) => t.estaAbierto).length;
  int get turnosConDescuadre =>
      turnos.where((t) => t.estaCerrado && t.diferenciaAbsoluta > 1.00).length;
  int get turnosConDiscrepancias =>
      turnos.where((t) => t.tieneDiscrepanciasInventario).length;
}
