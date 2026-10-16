/// Normaliza un monto escrito a mano (admin) a `double`.
///
/// La app convive con las dos convenciones de separadores:
///
///  - **es-CU / es-ES**: punto para los millares y coma para los decimales
///    (`1.500` → 1500, `1.500,50` → 1500.5).
///  - **en-US**: coma para los millares y punto para los decimales
///    (`1,500.75` → 1500.75, `18.5` → 18.5).
///
/// Reglas:
///  1. Se descartan espacios, símbolos de moneda y cualquier otro carácter.
///  2. Si aparecen **ambos** separadores, el de más a la derecha es el decimal
///     y el otro son millares.
///  3. Si aparece **uno solo** (una vez), es decimal… salvo que tenga
///     exactamente 3 dígitos detrás y haya parte entera delante: entonces son
///     millares (`1.500` → 1500, `.500` → 0.5).
///  4. Si el mismo separador aparece **varias** veces, solo puede ser millares
///     (`1.500.000` → 1500000).
///  5. Si no queda ningún número, devuelve `null` (nunca `0`): quien decide qué
///     hacer con un valor ilegible es la pantalla, no este parser.
library;

double? parseMonto(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  // Quitar espacios (incluidos los no separables) y símbolos de moneda.
  s = s.replaceAll(RegExp(r'[^0-9.,\-]'), '');
  final negativo = s.startsWith('-');
  s = s.replaceAll('-', '');
  if (s.isEmpty || !RegExp(r'[0-9]').hasMatch(s)) return null;

  final nPuntos = '.'.allMatches(s).length;
  final nComas = ','.allMatches(s).length;
  final ultimoPunto = s.lastIndexOf('.');
  final ultimaComa = s.lastIndexOf(',');

  String entero;
  String decimales;

  if (nPuntos > 0 && nComas > 0) {
    // Ambos: el de más a la derecha es el decimal; el otro, millares.
    final posDecimal = ultimoPunto > ultimaComa ? ultimoPunto : ultimaComa;
    final separadorDecimal = s[posDecimal];
    final separadorMillar = separadorDecimal == '.' ? ',' : '.';
    entero = s.substring(0, posDecimal).replaceAll(separadorMillar, '');
    decimales = s.substring(posDecimal + 1).replaceAll(separadorMillar, '');
  } else if (nPuntos + nComas > 1) {
    // Repetido: solo puede ser separador de millares.
    final separador = nPuntos > 0 ? '.' : ',';
    entero = s.replaceAll(separador, '');
    decimales = '';
  } else if (nPuntos + nComas == 1) {
    final pos = nPuntos == 1 ? ultimoPunto : ultimaComa;
    final cabeza = s.substring(0, pos);
    final cola = s.substring(pos + 1);
    if (cola.length == 3 && cabeza.isNotEmpty) {
      entero = '$cabeza$cola';
      decimales = '';
    } else {
      entero = cabeza;
      decimales = cola;
    }
  } else {
    entero = s;
    decimales = '';
  }

  if (entero.isEmpty) entero = '0';
  final texto = decimales.isEmpty ? entero : '$entero.$decimales';
  final valor = double.tryParse(texto);
  if (valor == null) return null;
  return negativo ? -valor : valor;
}