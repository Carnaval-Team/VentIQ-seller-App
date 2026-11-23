/// Contrato de lectura de los aportes de inversores de una compra
/// (`fn_fdi_compra_aportes`, fase 7 del módulo Compras).
///
/// Las claves JSON son las de la RPC (snake_case); las propiedades Dart van en
/// camelCase. El archivo no importa nada a propósito: el parseo se prueba sin
/// red ni Flutter (`test/compra_aportes_contract_test.dart`).
library;

/// Redondeo a dos decimales, el mismo que aplica `round(x, 2)` en PostgreSQL
/// para los importes de dinero de este módulo.
double _redondear2(double valor) =>
    valor.isFinite ? (valor * 100).round() / 100 : 0;

double _numero(Object? valor) => (valor as num?)?.toDouble() ?? 0;

double? _numeroOpcional(Object? valor) => (valor as num?)?.toDouble();

String? _textoOpcional(Object? valor) {
  final texto = valor?.toString().trim() ?? '';
  return texto.isEmpty ? null : texto;
}

DateTime? _fecha(Object? valor) =>
    valor == null ? null : DateTime.tryParse(valor.toString());

/// Estados posibles de un aporte (columna `estado`).
const String aporteEstadoAportado = 'aportado';
const String aporteEstadoDevuelto = 'devuelto';

/// Etiquetas de `naturaleza`, en el mismo vocabulario de la RPC.
const Map<String, String> _etiquetasNaturaleza = {
  'anticipo': 'Anticipo',
  'pasivo': 'Pasivo',
  'capital': 'Capital',
};

/// Un aporte de un inversor a la compra.
class AporteInversor {
  final int id;
  final int idInversor;

  /// Nombre del inversor tal como lo devuelve la RPC (`i.nombre`).
  final String inversor;

  /// Porcentaje declarado del inversor en la tienda. **No** es la parte de
  /// este aporte sobre la compra: eso lo calcula la UI con [parteDelTotal].
  final double porcentajeInversor;

  /// `anticipo` | `pasivo` | `capital`.
  final String naturaleza;

  /// Moneda en la que el inversor entregó el dinero.
  final String moneda;

  /// Importe en [moneda].
  final double monto;

  /// Moneda de la compra por una unidad de [moneda].
  final double tasaATotal;

  /// Importe ya convertido a la moneda de la compra (`monto * tasa_a_total`).
  final double montoEqTotal;

  /// Solo tiene sentido con naturaleza `pasivo`.
  final double? tasaInteres;

  /// Interés estimado que calcula el servidor (`monto_eq_total * tasa`).
  final double interesEstimado;

  final String? comprobante;
  final String? observacion;

  /// `aportado` | `devuelto`.
  final String estado;

  final DateTime? devueltoAt;
  final String? motivoDevolucion;
  final DateTime? createdAt;

  const AporteInversor({
    required this.id,
    required this.idInversor,
    required this.inversor,
    this.porcentajeInversor = 0,
    this.naturaleza = 'anticipo',
    this.moneda = '',
    this.monto = 0,
    this.tasaATotal = 1,
    this.montoEqTotal = 0,
    this.tasaInteres,
    this.interesEstimado = 0,
    this.comprobante,
    this.observacion,
    this.estado = aporteEstadoAportado,
    this.devueltoAt,
    this.motivoDevolucion,
    this.createdAt,
  });

  bool get esDevuelto => estado == aporteEstadoDevuelto;

  String get estadoLegible => esDevuelto ? 'Devuelto' : 'Aportado';

  String get naturalezaLegible =>
      _etiquetasNaturaleza[naturaleza] ?? naturaleza;

  /// Parte de este aporte sobre el total de la compra, en porcentaje 0..100.
  ///
  /// Es el `%` real que pinta la barra segmentada y la columna
  /// «% participación»: nunca el `porcentaje_inversor` del inversor.
  double parteDelTotal(double total) {
    if (!total.isFinite || total <= 0) return 0;
    return _redondear2(montoEqTotal / total * 100);
  }

  factory AporteInversor.fromJson(Map<String, dynamic> j) => AporteInversor(
    id: (j['id'] as num?)?.toInt() ?? 0,
    idInversor: (j['id_inversor'] as num?)?.toInt() ?? 0,
    inversor: j['inversor']?.toString() ?? '',
    porcentajeInversor: _numero(j['porcentaje_inversor']),
    naturaleza: j['naturaleza']?.toString() ?? 'anticipo',
    moneda: j['moneda']?.toString() ?? '',
    monto: _numero(j['monto']),
    tasaATotal: j['tasa_a_total'] == null ? 1 : _numero(j['tasa_a_total']),
    montoEqTotal: _numero(j['monto_eq_total']),
    tasaInteres: _numeroOpcional(j['tasa_interes']),
    interesEstimado: _numero(j['interes_estimado']),
    comprobante: _textoOpcional(j['comprobante']),
    observacion: _textoOpcional(j['observacion']),
    estado: j['estado']?.toString() ?? aporteEstadoAportado,
    devueltoAt: _fecha(j['devuelto_at']),
    motivoDevolucion: _textoOpcional(j['motivo_devolucion']),
    createdAt: _fecha(j['created_at']),
  );
}

/// Respuesta completa de `fn_fdi_compra_aportes`.
class AportesResumen {
  final int idCompra;

  /// `fondo` | `inversores`.
  final String modoLiquidacion;

  /// Estado de la compra (`creada`, `pagada`, ...).
  final String estado;

  /// Moneda del total de la compra; todos los importes de [aportes] ya vienen
  /// convertidos a ella (`monto_eq_total`).
  final String moneda;

  /// Total a cubrir (`total_financiado` de la compra).
  final double total;

  /// Suma de los aportes vigentes (`estado = 'aportado'`).
  final double aportado;

  /// Suma de los aportes ya devueltos. No se resta de [aportado].
  final double devuelto;

  /// `total - aportado`, nunca negativo.
  final double faltante;

  /// Porcentaje cubierto por los aportes vigentes (0..100, dos decimales).
  final double pct;

  /// Si todavía se puede registrar otro aporte: compra en `creada`, con total a
  /// financiar y con faltante. Es una puerta distinta de [puedePagar].
  final bool puedeRegistrar;

  /// Si la compra se puede pagar con los aportes de sus inversores.
  final bool puedePagar;

  /// Motivo real del bloqueo que manda el servidor; `null` = se puede pagar.
  final String? motivoBloqueo;

  final List<AporteInversor> aportes;

  const AportesResumen({
    required this.idCompra,
    this.modoLiquidacion = 'inversores',
    this.estado = 'creada',
    this.moneda = '',
    this.total = 0,
    this.aportado = 0,
    this.devuelto = 0,
    this.faltante = 0,
    this.pct = 0,
    this.puedeRegistrar = false,
    this.puedePagar = false,
    this.motivoBloqueo,
    this.aportes = const [],
  });

  /// Aportes que hoy cubren la compra (todo lo que no está devuelto).
  List<AporteInversor> get aportesVigentes =>
      aportes.where((a) => !a.esDevuelto).toList();

  /// Aportes ya devueltos: siguen en el desglose, atenuados.
  List<AporteInversor> get aportesDevueltos =>
      aportes.where((a) => a.esDevuelto).toList();

  /// Σ `monto_eq_total` de los aportes vigentes.
  double get sumaVigente {
    var suma = 0.0;
    for (final a in aportesVigentes) {
      suma += a.montoEqTotal;
    }
    return _redondear2(suma);
  }

  /// Σ `monto_eq_total` de los aportes devueltos.
  double get sumaDevuelta {
    var suma = 0.0;
    for (final a in aportesDevueltos) {
      suma += a.montoEqTotal;
    }
    return _redondear2(suma);
  }

  /// Inversores distintos con aporte vigente.
  int get inversoresComprometidos =>
      aportesVigentes.map((a) => a.idInversor).toSet().length;

  /// Si la compra ya está cubierta al 100 %.
  bool get cubierto => faltante <= 0;

  /// Lo que queda por asignar, en porcentaje (0..100).
  double get pctPendiente {
    final pendiente = _redondear2(100 - pct);
    if (pendiente < 0) return 0;
    return pendiente > 100 ? 100 : pendiente;
  }

  /// Cobertura incompleta **después** de pagar: pasa cuando se devuelve un
  /// aporte de una compra ya pagada. No es un bloqueo nuevo, es un aviso.
  bool get avisoPostPago =>
      estado == 'pagada' && faltante > 0 && motivoBloqueo != null;

  /// Parte del total que aporta un inversor concreto, sumando sus aportes
  /// vigentes. Es lo que pinta cada segmento de la barra.
  double parteDeInversor(int idInversor) {
    var suma = 0.0;
    for (final a in aportesVigentes) {
      if (a.idInversor == idInversor) suma += a.montoEqTotal;
    }
    if (!total.isFinite || total <= 0) return 0;
    return _redondear2(suma / total * 100);
  }

  /// Importe vigente de un inversor, en la moneda de la compra.
  double importeDeInversor(int idInversor) {
    var suma = 0.0;
    for (final a in aportesVigentes) {
      if (a.idInversor == idInversor) suma += a.montoEqTotal;
    }
    return _redondear2(suma);
  }

  factory AportesResumen.fromJson(Map<String, dynamic> j) => AportesResumen(
    idCompra: (j['id_compra'] as num?)?.toInt() ?? 0,
    modoLiquidacion: j['modo_liquidacion']?.toString() ?? 'inversores',
    estado: j['estado']?.toString() ?? 'creada',
    moneda: j['moneda']?.toString() ?? '',
    total: _numero(j['total']),
    aportado: _numero(j['aportado']),
    devuelto: _numero(j['devuelto']),
    faltante: _numero(j['faltante']),
    pct: _numero(j['pct']),
    puedeRegistrar: j['puede_registrar'] == true,
    puedePagar: j['puede_pagar'] == true,
    motivoBloqueo: _textoOpcional(j['motivo_bloqueo']),
    aportes: ((j['aportes'] as List?) ?? const [])
        .map(
          (e) => AporteInversor.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
  );
}
