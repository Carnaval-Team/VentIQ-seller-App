/// Cálculos, normalización y formato de los reportes del módulo Compras
/// (fase 8: dinero, conciliación, aging y descuadres).
///
/// **Dart puro**: no importa Flutter ni Supabase y no toca la red. Así
/// `test/reportes_contract_test.dart` puede validar los helpers y las sumas
/// contra payloads `jsonDecode` reales sin montar widgets.
///
/// Regla del módulo que manda sobre todo lo demás: **nunca se suman monedas
/// distintas**. Cada total es un mapa `moneda -> importe`; la UI los pinta
/// separados con su moneda al lado.
library;

import 'dart:math' as math;

import 'package:intl/intl.dart';

final NumberFormat _fmtCifra = NumberFormat('#,##0.00');
final NumberFormat _fmtPorcentaje = NumberFormat('#,##0.0');

/// Umbral de céntimos del módulo (`08_reportes.sql` usa 0.009).
const double umbralDescuadre = 0.009;

/// Resultado de una RPC del reporte: datos **o** error, nunca ambos.
///
/// La pantalla carga cada bloque por separado para que un fallo (p. ej. la
/// ausencia de `fn_fdi_conciliacion_ultima`) no tumbe las demás tarjetas.
class BloqueReporte {
  final Map<String, dynamic>? datos;
  final String? error;

  const BloqueReporte({this.datos, this.error});

  const BloqueReporte.vacio() : datos = null, error = null;

  bool get conDatos => datos != null;
  bool get conError => error != null;
}

/// Redondeo a 2 decimales, igual que `round(x, 2)` de PostgreSQL.
double redondear2(double valor) =>
    valor.isFinite ? (valor * 100).round() / 100 : 0;

// ===========================================================================
// Normalización de jsonb
// ===========================================================================

/// Importe de una RPC. Llega como número o como texto (`"484599.00"`).
double numero(dynamic valor) {
  if (valor == null) return 0;
  if (valor is num) return valor.toDouble();
  final texto = valor.toString().trim();
  if (texto.isEmpty) return 0;
  return double.tryParse(texto) ?? 0;
}

/// Igual que [numero] pero conservando la ausencia de dato.
///
/// `pct_desvio` puede ser `null` en el contrato y eso **no** es un 0: un 0 se
/// pinta «0,0 %» y un null se pinta «—».
double? numeroONulo(dynamic valor) {
  if (valor == null) return null;
  if (valor is num) return valor.toDouble();
  final texto = valor.toString().trim();
  if (texto.isEmpty) return null;
  return double.tryParse(texto);
}

bool booleano(dynamic valor) =>
    valor == true || valor == 'true' || valor == 't' || valor == 1;

String? textoONulo(dynamic valor) {
  if (valor == null) return null;
  final texto = valor.toString().trim();
  return texto.isEmpty ? null : texto;
}

/// Texto de una celda; lo que no viene se muestra como «—», nunca inventado.
String textoOGuion(dynamic valor, {String guion = '—'}) =>
    textoONulo(valor) ?? guion;

String monedaDe(Map<String, dynamic> fila, {String guion = '—'}) =>
    textoONulo(fila['moneda']) ?? guion;

/// Array jsonb tipado; un `null` o una forma inesperada dan lista vacía.
List<Map<String, dynamic>> listaDeMapas(dynamic valor) {
  if (valor is! List) return const [];
  return valor
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

// ===========================================================================
// Formato
// ===========================================================================

String cifra(num valor) => _fmtCifra.format(valor);

/// Porcentaje con un decimal: `3,4 %`, `0,0 %`. `pct_desvio` ya viene en
/// porcentaje, no en razón.
String cifraPorcentaje(num valor) => _fmtPorcentaje.format(valor);

/// Cifra con signo explícito; el `0,00` no lleva ni `+` ni `-`.
String cifraConSigno(num valor) {
  if (valor > 0) return '+${cifra(valor)}';
  if (valor < 0) return '-${cifra(valor.abs())}';
  return cifra(valor);
}

/// `23 nov` — sin depender del locale de `intl` (que no se inicializa en
/// toda la app), los meses van en una tabla fija en español.
const List<String> _mesesCortos = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String fechaCorta(DateTime fecha) {
  final mes = _mesesCortos[(fecha.month - 1).clamp(0, 11)];
  return '${fecha.day} $mes';
}

String _dosCifras(int n) => n.toString().padLeft(2, '0');

String fechaNumerica(DateTime? fecha, {String guion = '—'}) {
  if (fecha == null) return guion;
  return '${_dosCifras(fecha.day)}/${_dosCifras(fecha.month)}/${fecha.year}';
}

String fechaHora(DateTime? fecha, {String guion = '—'}) {
  if (fecha == null) return guion;
  return '${fechaNumerica(fecha)} '
      '${_dosCifras(fecha.hour)}:${_dosCifras(fecha.minute)}';
}

/// Las fechas de las RPC viajan como `date` (`YYYY-MM-DD`) o `timestamptz`.
/// Los timestamps se pasan a hora local: la pantalla muestra la hora del
/// usuario, no la de UTC.
DateTime? fechaDe(dynamic valor) {
  final texto = textoONulo(valor);
  if (texto == null) return null;
  return DateTime.tryParse(texto)?.toLocal();
}

/// «25 oct – 23 nov 2026» o «—» cuando el servidor no devolvió la ventana.
String rangoTexto(DateTime? desde, DateTime? hasta, {String guion = '—'}) {
  if (desde == null || hasta == null) return guion;
  if (desde.year == hasta.year) {
    return '${fechaCorta(desde)} – ${fechaCorta(hasta)} ${hasta.year}';
  }
  return '${fechaCorta(desde)} ${desde.year} – ${fechaCorta(hasta)} ${hasta.year}';
}

/// «0,00 CUP · 0,00 USD». Vacío si no hay nada que sumar.
String totalesPorMoneda(Map<String, double> totales, {String guion = '—'}) {
  if (totales.isEmpty) return guion;
  final monedas = totales.keys.toList()..sort();
  return monedas
      .map((moneda) {
        final valor = cifra(totales[moneda] ?? 0);
        return moneda.trim().isEmpty ? valor : '$valor $moneda';
      })
      .join(' · ');
}

// ===========================================================================
// Conciliación (R1, `fn_fdi_conciliacion`)
// ===========================================================================

/// Σ abs(dif vs movimientos) + abs(dif vs último saldo) de una clave.
///
/// Sin redondear: el umbral del módulo (0.009) decide la alarma y redondear
/// antes convertiría 0.008 en 0.01, marcando descuadre por un artefacto.
double descuadreFilaConciliacion(Map<String, dynamic> fila) {
  final vsMov = numero(fila['dif_saldo_vs_mov']).abs();
  final vsUltimo = numero(fila['dif_saldo_vs_ultimo']).abs();
  return vsMov + vsUltimo;
}

/// Una clave cuadra cuando sus dos diferencias están dentro del umbral.
///
/// No se confía solo en el flag `ok` del servidor: se recalcula, y el flag se
/// usa como salvaguarda (si el servidor marca descuadre, se respeta).
bool filaConciliacionOk(Map<String, dynamic> fila) {
  if (descuadreFilaConciliacion(fila) > umbralDescuadre) return false;
  final ok = fila['ok'];
  if (ok == null) return true;
  return booleano(ok);
}

/// Diferencia total de la conciliación, **por moneda**:
/// Σ (abs(dif_saldo_vs_mov) + abs(dif_saldo_vs_ultimo)).
///
/// Es el número que va en la banda de la tarjeta. No existe un total único
/// multimoneda.
Map<String, double> diferenciaTotalConciliacion(
  Iterable<Map<String, dynamic>> filas,
) {
  final totales = <String, double>{};
  for (final fila in filas) {
    final moneda = monedaDe(fila, guion: '');
    totales[moneda] = (totales[moneda] ?? 0) + descuadreFilaConciliacion(fila);
  }
  return {for (final e in totales.entries) e.key: redondear2(e.value)};
}

/// Descuadres que la pantalla debe mostrar.
///
/// `claves` y `descuadres` son escalares en el contrato. Si el conteo del
/// servidor y las filas no cuadran (p. ej. una fila con diferencias pero
/// `descuadres = 0`), manda el mayor: la alarma nunca puede mentir a la baja.
int descuadresEfectivos({
  required dynamic descuadres,
  required Iterable<Map<String, dynamic>> filas,
}) {
  final reportado = numero(descuadres).round();
  final calculado = filas.where((f) => !filaConciliacionOk(f)).length;
  return math.max(reportado, calculado);
}

// ===========================================================================
// Aging y descuadres declarados (`fn_fdi_reporte_aging`)
// ===========================================================================

/// Σ abs(diferencia_financiado) + abs(diferencia_pagos) de una compra.
double descuadreFilaAging(Map<String, dynamic> fila) {
  final financiado = numero(fila['diferencia_financiado']).abs();
  final pagos = numero(fila['diferencia_pagos']).abs();
  return redondear2(financiado + pagos);
}

/// Descuadre declarado por moneda de la compra. Alimenta la franja de
/// pendientes; tampoco aquí se suman monedas distintas.
Map<String, double> descuadreAging(Iterable<Map<String, dynamic>> filas) {
  final totales = <String, double>{};
  for (final fila in filas) {
    final moneda = monedaDe(fila, guion: '');
    totales[moneda] = (totales[moneda] ?? 0) + descuadreFilaAging(fila);
  }
  return {for (final e in totales.entries) e.key: redondear2(e.value)};
}

// ===========================================================================
// Movimientos (`fn_fdi_reporte_movimientos`)
// ===========================================================================

/// Subtotal de una moneda dentro de un día (o del rango entero).
class SubtotalMoneda {
  final int n;
  final double entradas;
  final double salidas;
  final double neto;

  const SubtotalMoneda({
    this.n = 0,
    this.entradas = 0,
    this.salidas = 0,
    this.neto = 0,
  });

  SubtotalMoneda sumar(Map<String, dynamic> fila) => SubtotalMoneda(
    n: n + numero(fila['n']).round(),
    entradas: redondear2(entradas + numero(fila['entradas'])),
    salidas: redondear2(salidas + numero(fila['salidas'])),
    neto: redondear2(neto + numero(fila['neto'])),
  );
}

/// Totales por moneda de un conjunto de filas `por_dia_usuario`.
Map<String, SubtotalMoneda> subtotalesMoneda(
  Iterable<Map<String, dynamic>> filas,
) {
  final totales = <String, SubtotalMoneda>{};
  for (final fila in filas) {
    final moneda = monedaDe(fila, guion: '');
    totales[moneda] = (totales[moneda] ?? const SubtotalMoneda()).sumar(fila);
  }
  return totales;
}

/// Agrupa por día (clave `dia`) conservando el orden de llegada del servidor
/// dentro de cada día. El resultado se devuelve con los días más recientes
/// primero, como el mockup.
Map<DateTime, List<Map<String, dynamic>>> agruparMovimientosPorDia(
  Iterable<Map<String, dynamic>> filas,
) {
  final porDia = <DateTime, List<Map<String, dynamic>>>{};
  for (final fila in filas) {
    final dia = fechaDe(fila['dia']);
    if (dia == null) continue;
    final clave = DateTime(dia.year, dia.month, dia.day);
    porDia.putIfAbsent(clave, () => []).add(fila);
  }
  final ordenados = porDia.keys.toList()..sort((a, b) => b.compareTo(a));
  return {for (final dia in ordenados) dia: porDia[dia]!};
}

DateTime _soloDia(DateTime fecha) =>
    DateTime(fecha.year, fecha.month, fecha.day);

/// «Hoy · 23 nov 2026», «Ayer · 22 nov 2026» o «21 nov 2026».
String etiquetaDia(DateTime dia, {DateTime? hoy}) {
  final referencia = _soloDia(hoy ?? DateTime.now());
  final objetivo = _soloDia(dia);
  final prefijo = objetivo == referencia
      ? 'Hoy'
      : objetivo == referencia.subtract(const Duration(days: 1))
      ? 'Ayer'
      : null;
  final fecha = '${fechaCorta(objetivo)} ${objetivo.year}';
  return prefijo == null ? fecha : '$prefijo · $fecha';
}
