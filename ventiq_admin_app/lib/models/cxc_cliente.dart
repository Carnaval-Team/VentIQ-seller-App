/// Cliente con saldo pendiente en Cuentas por Cobrar (resultado de
/// fn_cxc_listar_clientes).
class CxcCliente {
  final int idCliente;
  final String nombreCompleto;
  final String? telefono;
  final String codigoCliente;
  final bool bloqueadoCxc;
  final double saldoPendiente;
  final int ordenesPendientes;
  final DateTime? fechaMasAntigua;

  CxcCliente({
    required this.idCliente,
    required this.nombreCompleto,
    this.telefono,
    required this.codigoCliente,
    required this.bloqueadoCxc,
    required this.saldoPendiente,
    required this.ordenesPendientes,
    this.fechaMasAntigua,
  });

  factory CxcCliente.fromJson(Map<String, dynamic> json) {
    return CxcCliente(
      idCliente: (json['id_cliente'] as num).toInt(),
      nombreCompleto: json['nombre_completo']?.toString() ?? 'Sin nombre',
      telefono: json['telefono']?.toString(),
      codigoCliente: json['codigo_cliente']?.toString() ?? '',
      bloqueadoCxc: json['bloqueado_cxc'] == true,
      saldoPendiente: (json['saldo_pendiente'] as num?)?.toDouble() ?? 0.0,
      ordenesPendientes: (json['ordenes_pendientes'] as num?)?.toInt() ?? 0,
      fechaMasAntigua: json['fecha_mas_antigua'] != null
          ? DateTime.tryParse(json['fecha_mas_antigua'].toString())
          : null,
    );
  }

  /// Días desde la venta pendiente más antigua de este cliente.
  int? get diasAntiguedad {
    if (fechaMasAntigua == null) return null;
    return DateTime.now().difference(fechaMasAntigua!).inDays;
  }
}

/// Una venta a crédito (pendiente o ya pagada) dentro del historial de un
/// cliente (resultado de fn_cxc_historial_cliente).
class CxcVenta {
  final int idOperacion;
  final DateTime fecha;
  final String? denominacion;
  final double importeTotal;
  final double abonado;
  final double saldo;
  final bool esPagada;

  CxcVenta({
    required this.idOperacion,
    required this.fecha,
    this.denominacion,
    required this.importeTotal,
    required this.abonado,
    required this.saldo,
    required this.esPagada,
  });

  factory CxcVenta.fromJson(Map<String, dynamic> json) {
    return CxcVenta(
      idOperacion: (json['id_operacion'] as num).toInt(),
      fecha: DateTime.tryParse(json['fecha']?.toString() ?? '') ??
          DateTime.now(),
      denominacion: json['denominacion']?.toString(),
      importeTotal: (json['importe_total'] as num?)?.toDouble() ?? 0.0,
      abonado: (json['abonado'] as num?)?.toDouble() ?? 0.0,
      saldo: (json['saldo'] as num?)?.toDouble() ?? 0.0,
      esPagada: json['es_pagada'] == true,
    );
  }
}
