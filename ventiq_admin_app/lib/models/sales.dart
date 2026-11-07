/// Una divisa del reporte `fn_reporte_ventas_por_moneda`.
///
/// `importeNativo` es la suma **exacta** de lo cobrado en esa divisa, pero no es
/// dinero homogéneo: 14 USD no se pueden sumar con 45.000 CUP. `importeBase` es
/// el equivalente contable en CUP e `importeConsolidado` el importe de la fila ya
/// expresado en `monedaConsolidacion` (la divisa que la tienda fuerza para
/// vender, o CUP). El modelo expone los tres por separado para que la UI no
/// tenga que decidir cuál es cuál: **lo que se totaliza es
/// `importeConsolidado`**.
///
/// Vive aquí, con los demás modelos: antes estaba en `sales_service.dart` y eso
/// obligaba a este fichero a importar el servicio (ciclo) solo para reutilizarlo.
class VentasPorMoneda {
  final String moneda;
  final int operaciones;
  final double importeNativo;
  final double importeBase;
  final double efectivoNativo;
  final double digitalNativo;

  /// `importeBase / importeNativo` ponderado por importe. Vale `0` cuando la RPC
  /// no pudo calcularla (divisa sin importe); la UI lo muestra como «—».
  final double tasaPromedio;

  /// Divisa en la que la tienda consolida, tal como la manda cada fila del
  /// reporte (`fn_moneda_consolidacion`). `''` cuando la columna todavía no
  /// existe en el backend, para poder distinguir «no vino» de «vino vacía».
  final String monedaConsolidacion;

  /// El importe de **esta fila** ya expresado en [monedaConsolidacion]: exacto si
  /// la fila es de esa misma divisa, convertido con la tasa del día si no. Es la
  /// única columna que se puede sumar verticalmente en una app multimoneda.
  /// `0` cuando la columna todavía no existe en el backend.
  final double importeConsolidado;

  VentasPorMoneda({
    required this.moneda,
    required this.operaciones,
    required this.importeNativo,
    required this.importeBase,
    required this.efectivoNativo,
    required this.digitalNativo,
    required this.tasaPromedio,
    this.monedaConsolidacion = '',
    this.importeConsolidado = 0,
  });

  factory VentasPorMoneda.fromJson(Map<String, dynamic> json) {
    // Las columnas `numeric` de Postgres llegan como int, double o texto según
    // como las serialice PostgREST: se acepta cualquiera en vez de asumir un
    // subtipo concreto de `num` y romper el parseo entero.
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse('${value ?? ''}') ?? 0.0;
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('${value ?? ''}') ?? 0;
    }

    return VentasPorMoneda(
      moneda: (json['moneda'] ?? '').toString().trim().toUpperCase(),
      operaciones: asInt(json['operaciones']),
      importeNativo: asDouble(json['importe_nativo']),
      importeBase: asDouble(json['importe_base']),
      efectivoNativo: asDouble(json['efectivo_nativo']),
      digitalNativo: asDouble(json['digital_nativo']),
      tasaPromedio: asDouble(json['tasa_promedio']),
      // Las dos columnas de consolidación van al final del contrato del reporte:
      // contra un backend que todavía no las tenga llegan ausentes y la fila se
      // queda en «sin consolidar» en vez de romper el parseo.
      monedaConsolidacion: (json['moneda_consolidacion'] ?? '')
          .toString()
          .trim()
          .toUpperCase(),
      importeConsolidado: asDouble(json['importe_consolidado']),
    );
  }
}

class Sale {
  final String id;
  final String orderId;
  final String customerId;
  final String customerName;
  final String tpvId;
  final String tpvName;
  final String sellerId;
  final String sellerName;
  final DateTime saleDate;
  final String paymentMethod;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String status; // completada, cancelada, devuelta
  final List<SaleItem> items;

  Sale({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.tpvId,
    required this.tpvName,
    required this.sellerId,
    required this.sellerName,
    required this.saleDate,
    required this.paymentMethod,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.status,
    this.items = const [],
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] ?? '',
      orderId: json['orderId'] ?? '',
      customerId: json['customerId'] ?? '',
      customerName: json['customerName'] ?? '',
      tpvId: json['tpvId'] ?? '',
      tpvName: json['tpvName'] ?? '',
      sellerId: json['sellerId'] ?? '',
      sellerName: json['sellerName'] ?? '',
      saleDate: DateTime.parse(json['saleDate'] ?? DateTime.now().toIso8601String()),
      paymentMethod: json['paymentMethod'] ?? '',
      subtotal: (json['subtotal'] ?? 0.0).toDouble(),
      discount: (json['discount'] ?? 0.0).toDouble(),
      tax: (json['tax'] ?? 0.0).toDouble(),
      total: (json['total'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'completada',
      items: (json['items'] as List<dynamic>?)
          ?.map((i) => SaleItem.fromJson(i))
          .toList() ?? [],
    );
  }
}

class SaleItem {
  final String id;
  final String saleId;
  final String productId;
  final String variantId;
  final String productName;
  final String variantName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] ?? '',
      saleId: json['saleId'] ?? '',
      productId: json['productId'] ?? '',
      variantId: json['variantId'] ?? '',
      productName: json['productName'] ?? '',
      variantName: json['variantName'] ?? '',
      quantity: json['quantity'] ?? 0,
      unitPrice: (json['unitPrice'] ?? 0.0).toDouble(),
      totalPrice: (json['totalPrice'] ?? 0.0).toDouble(),
    );
  }
}

class TPV {
  final String id;
  final String name;
  final String code;
  final String storeId;
  final String storeName;
  final String location;
  final bool isActive;
  final String status; // activo, inactivo, mantenimiento
  final DateTime lastActivity;
  final String? assignedUserId;
  final String? assignedUserName;

  TPV({
    required this.id,
    required this.name,
    required this.code,
    required this.storeId,
    required this.storeName,
    required this.location,
    this.isActive = true,
    required this.status,
    required this.lastActivity,
    this.assignedUserId,
    this.assignedUserName,
  });

  factory TPV.fromJson(Map<String, dynamic> json) {
    return TPV(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      storeId: json['storeId'] ?? '',
      storeName: json['storeName'] ?? '',
      location: json['location'] ?? '',
      isActive: json['isActive'] ?? true,
      status: json['status'] ?? 'activo',
      lastActivity: DateTime.parse(json['lastActivity'] ?? DateTime.now().toIso8601String()),
      assignedUserId: json['assignedUserId'],
      assignedUserName: json['assignedUserName'],
    );
  }
}

class CashDelivery {
  final int id;
  final double montoEntrega;
  final String motivoEntrega;
  final String nombreRecibe;
  final String nombreAutoriza;
  final DateTime fechaEntrega;
  final int estado;
  final int idTurno;
  final String creadoPor;

  CashDelivery({
    required this.id,
    required this.montoEntrega,
    required this.motivoEntrega,
    required this.nombreRecibe,
    required this.nombreAutoriza,
    required this.fechaEntrega,
    required this.estado,
    required this.idTurno,
    required this.creadoPor,
  });

  factory CashDelivery.fromJson(Map<String, dynamic> json) {
    return CashDelivery(
      id: json['id'] ?? 0,
      montoEntrega: (json['monto_entrega'] ?? 0.0).toDouble(),
      motivoEntrega: json['motivo_entrega'] ?? '',
      nombreRecibe: json['nombre_recibe'] ?? '',
      nombreAutoriza: json['nombre_autoriza'] ?? '',
      fechaEntrega: DateTime.parse(json['fecha_entrega'] ?? DateTime.now().toIso8601String()),
      estado: json['estado'] ?? 1,
      idTurno: json['id_turno'] ?? 0,
      creadoPor: json['creado_por'] ?? '',
    );
  }
}

class SalesVendorReport {
  final String uuidUsuario;
  final String nombres;
  final String apellidos;
  final String nombreCompleto;
  final int totalVentas;
  final double totalProductosVendidos;
  final double totalDineroEfectivo;
  final double totalDineroTransferencia;
  final double totalDineroGeneral;
  final double totalImporteVentas;
  final int productosDiferentesVendidos;
  final DateTime primeraVenta;
  final DateTime ultimaVenta;
  final double totalEgresos;

  /// Presente cuando el reporte viene de `fn_reporte_ventas_por_turno`.
  final int? idTurno;
  final int? idTpv;
  final String? tpvNombre;
  final int? estadoTurno;
  final DateTime? fechaApertura;
  final DateTime? fechaCierre;

  /// Desglose por divisa de la v2 del reporte (`desglose_monedas`). Vacío
  /// cuando el backend todavía no expone la v2, para que el tab TPVs muestre el
  /// mismo informe que hoy en vez de romperse.
  final List<VentasPorMoneda> desgloseMonedas;

  /// Consolidado en moneda base calculado por la v2 (`total_base`). `null`
  /// cuando la columna no vino, que es la señal de «no hay desglose».
  final double? totalBase;

  SalesVendorReport({
    required this.uuidUsuario,
    required this.nombres,
    required this.apellidos,
    required this.nombreCompleto,
    required this.totalVentas,
    required this.totalProductosVendidos,
    required this.totalDineroEfectivo,
    required this.totalDineroTransferencia,
    required this.totalDineroGeneral,
    required this.totalImporteVentas,
    required this.productosDiferentesVendidos,
    required this.primeraVenta,
    required this.ultimaVenta,
    this.totalEgresos = 0.0,
    this.idTurno,
    this.idTpv,
    this.tpvNombre,
    this.estadoTurno,
    this.fechaApertura,
    this.fechaCierre,
    this.desgloseMonedas = const [],
    this.totalBase,
  });

  bool get esPorTurno => idTurno != null;

  /// Ventana del turno (o primera/última venta si no hay turno).
  DateTime get periodoInicio => fechaApertura ?? primeraVenta;
  DateTime get periodoFin => fechaCierre ?? ultimaVenta;

  bool get turnoAbierto => estadoTurno == 1;

  factory SalesVendorReport.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    final primera =
        parseDt(json['primera_venta']) ??
        parseDt(json['fecha_apertura']) ??
        DateTime.now();
    final ultima =
        parseDt(json['ultima_venta']) ??
        parseDt(json['fecha_cierre']) ??
        parseDt(json['fecha_apertura']) ??
        DateTime.now();

    // La v2 añade `desglose_monedas` (jsonb) y `total_base` (numeric) al final
    // del mismo contrato. Contra un backend donde aún no está desplegada esas
    // claves no llegan: se tolera su ausencia en vez de rechazar la fila.
    List<VentasPorMoneda> parseDesglose(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((row) => VentasPorMoneda.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    }

    // `total_base` es numeric: PostgREST lo puede serializar como int, double o
    // texto, así que no se asume un subtipo concreto de `num`.
    double? parseTotalBase(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return SalesVendorReport(
      uuidUsuario: json['uuid_usuario']?.toString() ?? '',
      nombres: json['nombres'] ?? '',
      apellidos: json['apellidos'] ?? '',
      nombreCompleto: json['nombre_completo'] ?? '',
      totalVentas: (json['total_ventas'] as num?)?.toInt() ?? 0,
      totalProductosVendidos:
          (json['total_productos_vendidos'] ?? 0.0).toDouble(),
      totalDineroEfectivo: (json['total_dinero_efectivo'] ?? 0.0).toDouble(),
      totalDineroTransferencia:
          (json['total_dinero_transferencia'] ?? 0.0).toDouble(),
      totalDineroGeneral: (json['total_dinero_general'] ?? 0.0).toDouble(),
      totalImporteVentas: (json['total_importe_ventas'] ?? 0.0).toDouble(),
      productosDiferentesVendidos:
          (json['productos_diferentes_vendidos'] as num?)?.toInt() ?? 0,
      primeraVenta: primera,
      ultimaVenta: ultima,
      totalEgresos: (json['total_egresos'] ?? 0.0).toDouble(),
      idTurno: (json['id_turno'] as num?)?.toInt(),
      idTpv: (json['id_tpv'] as num?)?.toInt(),
      tpvNombre: json['tpv_nombre']?.toString(),
      estadoTurno: (json['estado_turno'] as num?)?.toInt(),
      fechaApertura: parseDt(json['fecha_apertura']),
      fechaCierre: parseDt(json['fecha_cierre']),
      desgloseMonedas: parseDesglose(json['desglose_monedas']),
      totalBase: parseTotalBase(json['total_base']),
    );
  }

  SalesVendorReport copyWith({double? totalEgresos}) {
    return SalesVendorReport(
      uuidUsuario: uuidUsuario,
      nombres: nombres,
      apellidos: apellidos,
      nombreCompleto: nombreCompleto,
      totalVentas: totalVentas,
      totalProductosVendidos: totalProductosVendidos,
      totalDineroEfectivo: totalDineroEfectivo,
      totalDineroTransferencia: totalDineroTransferencia,
      totalDineroGeneral: totalDineroGeneral,
      totalImporteVentas: totalImporteVentas,
      productosDiferentesVendidos: productosDiferentesVendidos,
      primeraVenta: primeraVenta,
      ultimaVenta: ultimaVenta,
      totalEgresos: totalEgresos ?? this.totalEgresos,
      idTurno: idTurno,
      idTpv: idTpv,
      tpvNombre: tpvNombre,
      estadoTurno: estadoTurno,
      fechaApertura: fechaApertura,
      fechaCierre: fechaCierre,
      desgloseMonedas: desgloseMonedas,
      totalBase: totalBase,
    );
  }

  bool get isActiveToday {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    if (turnoAbierto) return true;
    return ultimaVenta.isAfter(todayStart);
  }

  String get status {
    if (turnoAbierto || isActiveToday) {
      return 'activo';
    } else if (ultimaVenta.isAfter(
      DateTime.now().subtract(const Duration(days: 7)),
    )) {
      return 'reciente';
    } else {
      return 'inactivo';
    }
  }
}
