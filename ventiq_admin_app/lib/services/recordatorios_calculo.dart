/// Cálculos puros de los recordatorios de compras sin completar (Fase 9).
///
/// Este archivo NO importa Flutter ni Supabase a propósito: es la parte que se
/// prueba con Dart puro en `test/recordatorios_contract_test.dart`. Todo lo que
/// tiene estado (SharedPreferences, RPC y notificación local) vive en
/// `recordatorios_service.dart`.
///
/// Reglas del módulo:
///  · El umbral se cuenta en días de antigüedad de la compra y una compra
///    «supera el umbral» solo si lleva MÁS días que el umbral (estricto).
///  · El pendiente se agrupa por moneda. Nunca se suman monedas distintas: no
///    existe un «pendiente total» multimoneda.
library;

/// Umbral por defecto: avisar a los 15 días sin recepción completa.
const int umbralDiasPorDefecto = 15;

/// Rango admitido para el umbral (días).
const int umbralDiasMinimo = 1;
const int umbralDiasMaximo = 365;

/// Etiqueta para una compra cuyo `moneda` viene nula o vacía (moneda
/// desconocida, no una moneda más).
const String monedaDesconocida = 'SIN MONEDA';

/// Título de la notificación local de pendientes.
const String tituloNotificacionPendientes = 'Compras sin completar';

/// Normaliza un valor leído de `SharedPreferences` (o de cualquier origen).
///
/// Devuelve [umbralDiasPorDefecto] si el valor no es un entero utilizable o
/// está fuera del rango admitido: un dato corrupto no debe dejar la app sin
/// recordatorios ni con un umbral absurdo.
int normalizarUmbral(Object? valor) {
  final dias = _entero(valor);
  if (dias == null || dias < umbralDiasMinimo || dias > umbralDiasMaximo) {
    return umbralDiasPorDefecto;
  }
  return dias;
}

/// Ajusta un valor al rango admitido. Se usa al guardar el umbral desde el
/// diálogo, para que la UI nunca pueda escribir un valor inválido.
int acotarUmbral(num valor) {
  final dias = valor.round();
  if (dias < umbralDiasMinimo) return umbralDiasMinimo;
  if (dias > umbralDiasMaximo) return umbralDiasMaximo;
  return dias;
}

/// Una compra abierta tal como llega del panel (`fn_fdi_pendientes_panel`).
class CompraPendiente {
  const CompraPendiente({
    required this.idCompra,
    required this.numeroCompra,
    required this.proveedor,
    required this.moneda,
    required this.diasAntiguedad,
    required this.montoTotal,
    required this.montoPendiente,
    required this.recibidoPct,
  });

  final int? idCompra;
  final String numeroCompra;
  final String? proveedor;
  final String moneda;
  final int diasAntiguedad;

  /// Importe de la compra en su moneda (nunca se suma con otras monedas).
  final double montoTotal;

  /// Lo que falta por recibir valorizado, en la moneda de la compra.
  final double montoPendiente;

  final double recibidoPct;

  /// `true` cuando la compra lleva más días que el umbral sin recepción
  /// completa.
  bool superaUmbral(int umbralDias) => diasAntiguedad > umbralDias;

  @override
  String toString() =>
      'CompraPendiente($numeroCompra, ${diasAntiguedad}d, $moneda $montoPendiente)';
}

/// Pendiente agregado de UNA moneda. Es la única forma de totalizar el
/// pendiente: nunca se cruzan monedas.
class PendientePorMoneda {
  const PendientePorMoneda({
    required this.moneda,
    required this.compras,
    required this.montoTotal,
    required this.montoPendiente,
  });

  final String moneda;
  final int compras;
  final double montoTotal;
  final double montoPendiente;

  @override
  String toString() =>
      'PendientePorMoneda($moneda, $compras compras, pendiente $montoPendiente)';
}

/// Resumen listo para pintar la tarjeta del inicio y para decidir el aviso.
class ResumenPendientes {
  const ResumenPendientes({
    required this.umbralDias,
    required this.compras,
    required this.porMoneda,
  });

  /// Resumen vacío (sin compras abiertas).
  factory ResumenPendientes.vacio({int umbralDias = umbralDiasPorDefecto}) {
    return ResumenPendientes(
      umbralDias: normalizarUmbral(umbralDias),
      compras: const <CompraPendiente>[],
      porMoneda: const <PendientePorMoneda>[],
    );
  }

  /// Construye el resumen a partir del JSON del panel.
  ///
  /// Es tolerante a JSON incompleto o mal formado: nunca lanza, ignora las
  /// filas que no son objetos y usa valores por defecto para las claves que
  /// falten.
  factory ResumenPendientes.desdePanel(
    Map<String, dynamic>? panel, {
    int umbralDias = umbralDiasPorDefecto,
  }) {
    final umbral = normalizarUmbral(umbralDias);
    if (panel == null || panel.isEmpty) {
      return ResumenPendientes.vacio(umbralDias: umbral);
    }

    final compras = <CompraPendiente>[];
    final crudas = panel['compras'];
    if (crudas is List) {
      for (final fila in crudas) {
        if (fila is! Map) continue;
        final dias = _entero(fila['dias_antiguedad']) ?? 0;
        compras.add(
          CompraPendiente(
            idCompra: _entero(fila['id_compra']),
            numeroCompra: _texto(fila['numero_compra']),
            proveedor: _textoOpcional(fila['proveedor']),
            moneda: _moneda(fila['moneda']),
            diasAntiguedad: dias < 0 ? 0 : dias,
            montoTotal: _decimal(fila['monto_total']),
            montoPendiente: _decimal(fila['monto_pendiente']),
            recibidoPct: _porcentaje(fila['recibido_pct']),
          ),
        );
      }
    }

    return ResumenPendientes(
      umbralDias: umbral,
      compras: compras,
      porMoneda: _porMoneda(panel['totales_por_moneda'], compras),
    );
  }

  final int umbralDias;
  final List<CompraPendiente> compras;

  /// Un elemento por moneda presente en el panel (sin total multimodal).
  final List<PendientePorMoneda> porMoneda;

  /// Compras abiertas (con o sin recepción parcial).
  int get totalCompras => compras.length;

  bool get vacio => compras.isEmpty;

  /// Compras que llevan MÁS días que [umbralDias] sin recibirse completas.
  int get comprasSobreUmbral =>
      compras.where((compra) => compra.superaUmbral(umbralDias)).length;

  /// Hay algo que avisar (alguna compra supera el umbral). Sin compras, o con
  /// compras recientes, no se avisa.
  bool get hayAviso => comprasSobreUmbral > 0;

  List<CompraPendiente> get comprasQueSuperanUmbral => compras
      .where((compra) => compra.superaUmbral(umbralDias))
      .toList(growable: false);

  /// Días de la compra abierta más antigua (`null` si no hay compras).
  int? get diasMasAntigua {
    if (compras.isEmpty) return null;
    var maximo = compras.first.diasAntiguedad;
    for (final compra in compras) {
      if (compra.diasAntiguedad > maximo) maximo = compra.diasAntiguedad;
    }
    return maximo;
  }

  /// La compra abierta más antigua (`null` si no hay compras).
  CompraPendiente? get masAntigua {
    if (compras.isEmpty) return null;
    var masVieja = compras.first;
    for (final compra in compras) {
      if (compra.diasAntiguedad > masVieja.diasAntiguedad) masVieja = compra;
    }
    return masVieja;
  }

  bool get hayPendientePorMoneda => porMoneda.isNotEmpty;

  /// Cuerpo de la notificación local, en español y sin sumar monedas.
  String get mensajeNotificacion {
    final n = comprasSobreUmbral;
    if (n == 1) {
      return '1 compra lleva más de $umbralDias días sin recibirse completa';
    }
    return '$n compras llevan más de $umbralDias días sin recibirse completas';
  }
}

// ---------------------------------------------------------------------------
// Helpers de parseo (tolerantes: nunca lanzan)
// ---------------------------------------------------------------------------

int? _entero(Object? valor) {
  if (valor == null) return null;
  if (valor is int) return valor;
  if (valor is double) return valor.isFinite ? valor.round() : null;
  if (valor is num) return valor.isFinite ? valor.round() : null;
  final texto = valor.toString().trim();
  if (texto.isEmpty) return null;
  final numero = double.tryParse(texto.replaceAll(',', ''));
  if (numero == null || !numero.isFinite) return null;
  return numero.round();
}

double _decimal(Object? valor) {
  if (valor == null) return 0;
  if (valor is int) return valor.toDouble();
  if (valor is double) return valor.isFinite ? valor : 0;
  if (valor is num) return valor.isFinite ? valor.toDouble() : 0;
  final texto = valor.toString().trim();
  if (texto.isEmpty) return 0;
  final numero = double.tryParse(texto.replaceAll(',', ''));
  if (numero == null || !numero.isFinite) return 0;
  return numero;
}

/// `recibido_pct` viene en [0, 1]; se acota para que un dato raro no rompa la
/// barra de progreso de la UI.
double _porcentaje(Object? valor) {
  final bruto = _decimal(valor);
  if (bruto <= 0) return 0;
  if (bruto >= 1) return 1;
  return bruto;
}

String _texto(Object? valor) {
  if (valor == null) return '';
  return valor.toString().trim();
}

String? _textoOpcional(Object? valor) {
  final texto = _texto(valor);
  return texto.isEmpty ? null : texto;
}

String _moneda(Object? valor) {
  final texto = _texto(valor);
  return texto.isEmpty ? monedaDesconocida : texto;
}

/// Agrupa el pendiente por moneda.
///
/// Se prefiere `totales_por_moneda` (el agregado que ya calcula la RPC). Si
/// viene ausente, vacío o inservible, se agrega desde las compras: en ambos
/// caminos cada moneda conserva su propio importe y nunca se cruzan.
List<PendientePorMoneda> _porMoneda(
  Object? totalesCrudos,
  List<CompraPendiente> compras,
) {
  final resultado = <PendientePorMoneda>[];
  if (totalesCrudos is List) {
    for (final fila in totalesCrudos) {
      if (fila is! Map) continue;
      final moneda = _moneda(fila['moneda']);
      final cantidad = _entero(fila['compras']) ?? 0;
      final total = _decimal(fila['monto_total']);
      final pendiente = _decimal(fila['monto_pendiente']);
      if (cantidad <= 0 && total == 0 && pendiente == 0) continue;
      resultado.add(
        PendientePorMoneda(
          moneda: moneda,
          compras: cantidad < 0 ? 0 : cantidad,
          montoTotal: total,
          montoPendiente: pendiente,
        ),
      );
    }
  }
  if (resultado.isNotEmpty) {
    resultado.sort(_compararMonedas);
    return List<PendientePorMoneda>.unmodifiable(resultado);
  }

  // Respaldo: agregar desde las compras, moneda a moneda.
  final acumulado = <String, List<double>>{}; // [compras, total, pendiente]
  for (final compra in compras) {
    final fila = acumulado.putIfAbsent(compra.moneda, () => <double>[0, 0, 0]);
    fila[0] += 1;
    fila[1] += compra.montoTotal;
    fila[2] += compra.montoPendiente;
  }
  final monedas = acumulado.keys.toList()..sort(_compararNombresMoneda);
  for (final moneda in monedas) {
    final fila = acumulado[moneda]!;
    resultado.add(
      PendientePorMoneda(
        moneda: moneda,
        compras: fila[0].round(),
        montoTotal: fila[1],
        montoPendiente: fila[2],
      ),
    );
  }
  return List<PendientePorMoneda>.unmodifiable(resultado);
}

int _compararMonedas(PendientePorMoneda a, PendientePorMoneda b) =>
    _compararNombresMoneda(a.moneda, b.moneda);

/// La moneda desconocida va al final; el resto, alfabético.
int _compararNombresMoneda(String a, String b) {
  final aDesconocida = a == monedaDesconocida;
  final bDesconocida = b == monedaDesconocida;
  if (aDesconocida != bDesconocida) return aDesconocida ? 1 : -1;
  return a.compareTo(b);
}

// ---------------------------------------------------------------------------
// Presentación (texto puro, sin Flutter, para poder probarlo)
// ---------------------------------------------------------------------------

/// Formatea un importe con separador de miles y dos decimales: 1234.5 →
/// `1,234.50`. No añade símbolo de moneda: cada importe se muestra junto a su
/// moneda, nunca suelto.
String formatearMonto(double valor) {
  final negativo = valor < 0;
  final absoluto = valor.abs();
  final partes = absoluto.toStringAsFixed(2).split('.');
  final entero = partes[0];
  final buffer = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) buffer.write(',');
    buffer.write(entero[i]);
  }
  return '${negativo ? '-' : ''}$buffer.${partes.length > 1 ? partes[1] : '00'}';
}

/// `1 día` / `N días`.
String textoDias(int dias) => dias == 1 ? '1 día' : '$dias días';