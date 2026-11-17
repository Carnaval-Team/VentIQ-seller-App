/// Envelope común de lectura para los reportes multimoneda del admin
/// (SPEC-product-currency-report-contracts §7, tarea R01).
///
/// Todo consumidor de reportes pasa por aquí en vez de leer el JSON crudo:
/// un campo requerido ausente o malformado es un error de contrato visible
/// ([ReporteContratoException]), nunca un cero silencioso. Los importes
/// viajan como cadenas decimales exactas (MC-003); la conversión a `double`
/// es decisión de presentación de cada consumidor, no de este adaptador.
library;

/// Error de contrato de un reporte: falta un campo requerido, llega un tipo
/// inesperado o un importe no es un decimal finito bien formado. La UI debe
/// mostrar "no disponible"/error, no degradar el dato a cero.
class ReporteContratoException implements Exception {
  final String campo;
  final String motivo;
  const ReporteContratoException(this.campo, this.motivo);

  @override
  String toString() => 'ReporteContratoException($campo): $motivo';
}

/// Magnitud financiera que un reporte declara para sus importes (§3). No es
/// lo mismo venta neta que cobrado ni saldo: cada consumidor valida la que
/// espera y no reetiqueta la que recibe.
enum MagnitudReporte {
  ventaNeta('venta_neta'),
  ventaBruta('venta_bruta'),
  cobrado('cobrado'),
  saldo('saldo'),
  costeRealizado('coste_realizado'),
  utilidad('utilidad'),
  gastos('gastos_operativos'),
  operaciones('operaciones'),

  /// El reporte no tiene una sola magnitud: cada campo declara la suya
  /// (venta neta en las líneas, cobrado en los pagos). No se reetiqueta
  /// como una de las otras.
  mixtaDeclarada('mixta_declarada_por_campo'),
  desconocida('desconocida');

  final String codigo;
  const MagnitudReporte(this.codigo);

  static MagnitudReporte parse(dynamic valor) {
    final codigo = valor?.toString().trim() ?? '';
    for (final m in values) {
      if (m.codigo == codigo && m != desconocida) return m;
    }
    return desconocida;
  }
}

/// Completitud del dataset según §6/§7. `incompleto` exige `motivos`; un
/// estado que no sea `completo` prohíbe presentar el total como total global.
enum CompletitudReporte {
  completo('completo'),
  incompleto('incompleto'),
  noDisponible('no_disponible'),
  noAutorizado('no_autorizado');

  final String codigo;
  const CompletitudReporte(this.codigo);

  static CompletitudReporte parse(dynamic valor) {
    final codigo = valor?.toString().trim() ?? '';
    for (final c in values) {
      if (c.codigo == codigo) return c;
    }
    throw ReporteContratoException(
      'completitud',
      'valor inesperado: ${valor ?? 'null'}',
    );
  }
}

/// Base temporal declarada por el reporte (§5): qué significa el intervalo
/// [desde, hasta) que recortó los datos.
enum BaseTemporal {
  comercial('comercial'),
  cobrosPeriodo('cobros_periodo'),
  cohorteVentas('cohorte_ventas'),
  saldoCorte('saldo_corte'),
  turno('turno');

  final String codigo;
  const BaseTemporal(this.codigo);

  static BaseTemporal parse(dynamic valor) {
    final codigo = valor?.toString().trim() ?? '';
    for (final b in values) {
      if (b.codigo == codigo) return b;
    }
    throw ReporteContratoException(
      'base_temporal',
      'valor inesperado: ${valor ?? 'null'}',
    );
  }
}

/// Importe exacto con su moneda. `valor` es una cadena decimal canónica
/// (`-?\d+(\.\d+)?`); nunca se parsea a double aquí porque la autoridad
/// monetaria no pasa por binario. `moneda` es el código ISO-4217 de tres
/// letras en el que está expresado el importe.
class MontoReporte {
  final String valor;
  final String moneda;

  MontoReporte({required this.valor, required this.moneda});

  static final _decimal = RegExp(r'^-?\d+(\.\d+)?$');

  /// Construye desde un valor que puede llegar como `int`, `double` finito o
  /// `String` decimal (PostgREST serializa `numeric` de las tres formas).
  /// Malformado/no finito/ausente = error de contrato, no 0.
  factory MontoReporte.parse(dynamic valor, {required String moneda}) {
    return MontoReporte(valor: decimalExacto(valor, 'importe'), moneda: moneda);
  }

  /// Decimal exacto como cadena canónica. Acepta `num` finito y `String`
  /// decimal; cualquier otra cosa lanza [ReporteContratoException].
  static String decimalExacto(dynamic valor, String campo) {
    if (valor is int) return valor.toString();
    if (valor is double) {
      if (valor.isFinite) return valor.toString();
      throw ReporteContratoException(campo, 'valor no finito: $valor');
    }
    if (valor is String) {
      final limpio = valor.trim();
      if (_decimal.hasMatch(limpio)) return limpio;
      throw ReporteContratoException(campo, 'decimal malformado: $valor');
    }
    throw ReporteContratoException(
      campo,
      'tipo inesperado (${valor.runtimeType}): $valor',
    );
  }

  /// Suma solo si [otro] está en la misma moneda; mezclar monedas es un
  /// error de contrato (§4-2), no una conversión silenciosa.
  MontoReporte operator +(MontoReporte otro) {
    if (otro.moneda != moneda) {
      throw ReporteContratoException(
        'importe',
        'no se puede sumar $moneda con ${otro.moneda}',
      );
    }
    final total =
        (BigInt.parse(_escala(valor)) + BigInt.parse(_escala(otro.valor)));
    return MontoReporte(valor: _desescalar(total), moneda: moneda);
  }

  /// Escala ambos decimales a 6 dígitos fijos para sumar en enteros.
  static String _escala(String decimal) {
    final negativo = decimal.startsWith('-');
    final limpio = negativo ? decimal.substring(1) : decimal;
    final partes = limpio.split('.');
    final entero = partes[0];
    final fraccion = (partes.length > 1 ? partes[1] : '').padRight(6, '0');
    final cortada = fraccion.length > 6 ? fraccion.substring(0, 6) : fraccion;
    return '${negativo ? '-' : ''}$entero$cortada';
  }

  static String _desescalar(BigInt escalado) {
    final negativo = escalado.isNegative;
    final digitos = escalado.abs().toString().padLeft(7, '0');
    final entero = digitos.substring(0, digitos.length - 6);
    var fraccion = digitos.substring(digitos.length - 6);
    fraccion = fraccion.replaceFirst(RegExp(r'0+$'), '');
    final texto = fraccion.isEmpty ? entero : '$entero.$fraccion';
    return '${negativo ? '-' : ''}$texto';
  }
}

/// Cabecera del contrato de lectura: identidad, semántica y completitud que
/// todo reporte compatible debe declarar (§7). El payload de filas/montos
/// queda en [datos] para que cada consumidor lo valide contra su magnitud.
class ReporteEnvelope {
  /// Versión del contrato del reporte (no confundir con la versión monetaria
  /// de cada registro, que va por línea/registro en el payload).
  final String versionReporte;

  /// Versiones monetarias incluidas en el dataset (p.ej. `producto-v1`).
  /// Un registro con versión desconocida no se interpreta como legacy.
  final List<String> versionesMonetarias;

  /// Magnitud que los importes del reporte representan.
  final MagnitudReporte magnitud;

  /// Completitud del dataset; si no es [CompletitudReporte.completo] el
  /// consumidor no presenta el agregado como total global verdadero.
  final CompletitudReporte completitud;

  /// Qué significa la ventana temporal aplicada (§5).
  final BaseTemporal baseTemporal;

  /// Motivos de incompletitud/indisponibilidad cuando aplica.
  final List<String> motivos;

  /// Conteos de registros comparables y no atribuibles, si el reporte los
  /// declara (null = el reporte no informa cobertura).
  final int? registrosComparables;
  final int? registrosNoAtribuibles;

  /// Payload del reporte ya validado estructuralmente por el envelope.
  final Map<String, dynamic> datos;

  const ReporteEnvelope({
    required this.versionReporte,
    required this.versionesMonetarias,
    required this.magnitud,
    required this.completitud,
    required this.baseTemporal,
    this.motivos = const [],
    this.registrosComparables,
    this.registrosNoAtribuibles,
    this.datos = const {},
  });

  /// Parseo estricto del envelope. Cualquier clave requerida ausente o
  /// malformada lanza [ReporteContratoException]; el resto del JSON se
  /// conserva en [datos] para el consumidor.
  factory ReporteEnvelope.parse(Map<String, dynamic> json) {
    final versionReporte = json['version_reporte']?.toString().trim() ?? '';
    if (versionReporte.isEmpty) {
      throw const ReporteContratoException(
        'version_reporte',
        'requerido y no puede ser vacío',
      );
    }

    final crudoVersiones = json['versiones_monetarias'];
    if (crudoVersiones is! List) {
      throw const ReporteContratoException(
        'versiones_monetarias',
        'requerido: lista de versiones incluidas en el dataset',
      );
    }
    final versiones =
        crudoVersiones
            .map((v) => v?.toString().trim() ?? '')
            .where((v) => v.isNotEmpty)
            .toList(growable: false);

    final magnitud = MagnitudReporte.parse(json['magnitud']);
    if (magnitud == MagnitudReporte.desconocida) {
      throw ReporteContratoException(
        'magnitud',
        'valor inesperado: ${json['magnitud'] ?? 'null'}',
      );
    }

    final baseTemporal = BaseTemporal.parse(json['base_temporal']);

    // La spec deja `completitud` como código. Las RPC _v2 lo anidan
    // (`{estado, motivos}`) junto con conteos propios del reporte. Se
    // aceptan las dos formas; los motivos del objeto ganan sobre los de
    // la raíz.
    final crudoCompletitud = json['completitud'];
    final CompletitudReporte completitud;
    final List<String> motivos;
    if (crudoCompletitud is Map) {
      completitud = CompletitudReporte.parse(crudoCompletitud['estado']);
      motivos = _textos(crudoCompletitud['motivos']);
    } else {
      completitud = CompletitudReporte.parse(crudoCompletitud);
      motivos = _textos(json['motivos']);
    }
    if (completitud == CompletitudReporte.incompleto && motivos.isEmpty) {
      throw const ReporteContratoException(
        'motivos',
        'dataset incompleto sin motivos declarados',
      );
    }

    return ReporteEnvelope(
      versionReporte: versionReporte,
      versionesMonetarias: versiones,
      magnitud: magnitud,
      completitud: completitud,
      baseTemporal: baseTemporal,
      motivos: motivos,
      registrosComparables: _enteroOpcional(json['registros_comparables']),
      registrosNoAtribuibles: _enteroOpcional(json['registros_no_atribuibles']),
      datos: json,
    );
  }

  static List<String> _textos(dynamic crudo) {
    if (crudo is! List) return const [];
    return crudo
        .map((m) => m?.toString() ?? '')
        .where((m) => m.isNotEmpty)
        .toList(growable: false);
  }

  static int? _enteroOpcional(dynamic valor) {
    if (valor == null) return null;
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor.toString());
  }

  /// `true` si el agregado puede presentarse como total global del corte.
  bool get esTotalConfiable => completitud == CompletitudReporte.completo;
}
