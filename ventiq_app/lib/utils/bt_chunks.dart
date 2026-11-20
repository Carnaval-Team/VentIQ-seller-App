/// Trocea un trabajo ESC/POS para enviarlo por Bluetooth sin partir líneas de
/// texto.
///
/// Las impresoras térmicas imprimen lo que tienen en el buffer cuando la
/// transmisión se pausa. Si el trozo termina a mitad de una línea («50x Di»),
/// sale esa mitad y el resto («esel») en otra línea. El corte caía donde
/// terminaba el trozo de 256 bytes, por eso variaba entre tickets y en la
/// guía de almacén casi nunca se veía.
///
/// Cada trozo termina en un salto de línea (0x0A) si hay uno dentro de
/// [maximo] bytes. Sin salto (datos de imagen, una línea muy larga) corta en
/// [maximo], como antes.
List<List<int>> trocearEnLineas(List<int> bytes, {int maximo = 256}) {
  assert(maximo > 0);
  final trozos = <List<int>>[];
  var inicio = 0;
  while (inicio < bytes.length) {
    var fin = inicio + maximo;
    if (fin >= bytes.length) {
      fin = bytes.length;
    } else {
      for (var i = fin - 1; i >= inicio; i--) {
        if (bytes[i] == 0x0A) {
          fin = i + 1;
          break;
        }
      }
    }
    trozos.add(bytes.sublist(inicio, fin));
    inicio = fin;
  }
  return trozos;
}
