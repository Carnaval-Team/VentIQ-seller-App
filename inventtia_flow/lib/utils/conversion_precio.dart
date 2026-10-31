/// Conversión de precios entre monedas con la tasa del día («el toque»).
///
/// **100 % puro**: no importa Flutter ni Supabase, sólo el modelo [TasasDia].
/// Todo lo que decide *cuánto* vale un precio vive aquí para poder probarlo sin
/// red ni widgets.
///
/// Regla de oro: **nunca se inventa un factor**. Si la moneda de destino no
/// tiene tasa, la conversión es `null` (no `0`, no `1`): quien llama decide qué
/// hacer, y en la UI significa "no se toca ese precio".
library;

import '../models/tasa_cambio.dart';

/// Redondeo y formateo de precios escritos en un `TextField`.
///
/// Existe por un fallo real de `parseMonto`: si el controlador recibe
/// `18.375` (tres decimales), al releerlo se interpreta como **18375** (tres
/// dígitos detrás del punto = separador de millares). Por eso un precio
/// calculado NUNCA se escribe con `v.toString()`: se redondea a los decimales
/// configurados y se formatea con `toStringAsFixed`, que deja como mucho esos
/// decimales.
class Redondeo {
  Redondeo._();

  /// Máximo de decimales que admite el precio (CUP y divisas van de 0 a 2).
  static const int maxDecimales = 2;

  /// Redondea [valor] a [decimales] posiciones (redondeo al más cercano).
  static double aDecimales(double valor, int decimales) {
    if (!valor.isFinite) return valor;
    final d = decimales.clamp(0, 8).toInt();
    if (d == 0) return valor.roundToDouble();
    var factor = 1.0;
    for (var i = 0; i < d; i++) {
      factor *= 10;
    }
    return (valor * factor).roundToDouble() / factor;
  }

  /// Quita los ceros sobrantes de un decimal ya formateado (`18.50` → `18.5`,
  /// `18.00` → `18`) sin tocar los que están a la izquierda del punto.
  static String quitarCeros(String texto) {
    if (!texto.contains('.')) return texto;
    var s = texto;
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    if (s.isEmpty || s == '-') return '0';
    return s;
  }

  /// Texto seguro para el `TextEditingController` de un precio.
  ///
  /// Redondea primero y formatea con `toStringAsFixed(decimales)`; así el valor
  /// que el admin vuelve a leer (y `parseMonto` interpreta) es el mismo que se
  /// calculó.
  static String texto(double valor, int decimales) {
    final d = decimales.clamp(0, 8).toInt();
    return quitarCeros(aDecimales(valor, d).toStringAsFixed(d));
  }
}

/// Redondea un precio a [decimales] posiciones (usa la regla bancaria del
/// más cercano: 18.375 → 18.38 con 2 decimales).
double redondearPrecio(double valor, int decimales) =>
    Redondeo.aDecimales(valor, decimales);

/// Factor de conversión `origen → destino` (1 unidad de origen = N de destino),
/// o `null` si la tasa no lo trae.
///
/// Lee la matriz `conversiones` que ya calcula la base de datos, que **incluye
/// el cruce por CUP** (MLC→EUR = MLC→CUP / EUR→CUP) y la identidad
/// `X → X = 1`. Si falta la clave, devuelve `null` en vez de suponer 1.
double? factorDesde(TasasDia? tasas, String origen, String destino) {
  if (tasas == null) return null;
  return tasas.factor(origen, destino);
}

/// Convierte [valor] de [origen] a [destino] y lo redondea a [decimales].
///
/// `null` si no hay tasa (o si el resultado no es un número usable). Nunca
/// devuelve `0` por falta de datos.
double? convertirPrecio({
  required double valor,
  required String origen,
  required String destino,
  TasasDia? tasas,
  required int decimales,
}) {
  if (!valor.isFinite) return null;
  final factor = factorDesde(tasas, origen, destino);
  if (factor == null || !factor.isFinite) return null;
  final convertido = valor * factor;
  if (!convertido.isFinite) return null;
  return redondearPrecio(convertido, decimales);
}

/// Convierte un precio de [origen] a todas las [monedas] pedidas.
///
/// Devuelve **todas** las claves de [monedas]: las que no se pueden calcular
/// valen `null` (nunca `0` ni el mismo valor del origen). El redondeo de cada
/// moneda lo decide [decimalesDe] (CUP usa un número de decimales y las divisas
/// otro, según la configuración de la entidad).
Map<String, double?> convertirVarios({
  required Map<String, double> precios,
  required String origen,
  required List<String> monedas,
  TasasDia? tasas,
  required int Function(String moneda) decimalesDe,
}) {
  final buscada = origen.trim().toUpperCase();
  double? valor;
  for (final e in precios.entries) {
    if (e.key.trim().toUpperCase() == buscada) {
      valor = e.value;
      break;
    }
  }
  if (valor == null) {
    return {for (final m in monedas) m: null};
  }
  final base = valor;
  final out = <String, double?>{};
  for (final m in monedas) {
    final destino = m.trim().toUpperCase();
    out[m] = convertirPrecio(
      valor: base,
      origen: buscada,
      destino: destino,
      tasas: tasas,
      decimales: decimalesDe(destino),
    );
  }
  return out;
}

/// Alias del plan (`§5.1`) de [convertirVarios]; se mantiene para que el
/// contrato documentado y el código no se separen.
Map<String, double?> preciosConvertidos({
  required Map<String, double> precios,
  required String origen,
  required List<String> monedas,
  TasasDia? tasas,
  required int Function(String moneda) decimalesDe,
}) => convertirVarios(
  precios: precios,
  origen: origen,
  monedas: monedas,
  tasas: tasas,
  decimalesDe: decimalesDe,
);