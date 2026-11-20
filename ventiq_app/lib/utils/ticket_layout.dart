import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// Maquetación ESC/POS común del ticket térmico (Bluetooth y WiFi).
///
/// - Producto: «cantidad x nombre» alineado a la izquierda y, en otra línea,
///   el subtotal alineado a la derecha.
/// - Totales: una línea por moneda, «TOTAL MONEDA» a la izquierda y el monto a
///   la derecha.
/// - Guía de almacén: solo cantidad, nombre completo y ubicación; sin importes.
///
/// La alineación a la derecha se hace con espacios, no con `ESC a 2` ni con
/// `row()`: esos comandos dejan el área de impresión de la impresora estrecha
/// o desplazada y el texto siguiente se partía a mitad de palabra («50x Diese»
/// y la «l» debajo). Toda línea sale alineada a la izquierda, igual que la guía
/// de almacén, que imprime bien.
///
/// Los dos servicios llaman aquí para que no diverjan. Los datos salen de
/// `TicketData`.
class TicketLayout {
  const TicketLayout._();

  /// Caracteres por línea en papel de 58 mm con la fuente normal.
  static const int anchoLinea = 32;

  /// [izquierda] pegado al margen izquierdo y [derecha] al derecho, en una
  /// sola línea de [ancho] caracteres. Si no caben, queda un espacio entre
  /// ambos y la impresora continúa en la línea siguiente.
  static String justificada(
    String izquierda,
    String derecha, {
    int ancho = anchoLinea,
  }) {
    final hueco = ancho - izquierda.length - derecha.length;
    return '$izquierda${' ' * (hueco < 1 ? 1 : hueco)}$derecha';
  }

  /// Línea 1: cantidad y producto a la izquierda. Línea 2: subtotal a la
  /// derecha.
  ///
  /// La línea del producto se construye igual que en la guía de almacén
  /// ([almacenProductoBytes]): mismo estilo (izquierda, negrita) y los mismos
  /// bytes. En la impresora Bluetooth esa línea sale completa, mientras que la
  /// misma línea sin negrita se partía a los 9 caracteres.
  ///
  /// El nombre va completo: si no cabe en el ancho del papel, la impresora lo
  /// continúa en la línea siguiente.
  static List<int> productoBytes(
    Generator generator, {
    required String cantidad,
    required String nombre,
    required String subtotal,
  }) => [
    ..._lineaCantidadNombre(generator, cantidad, nombre),
    ...generator.text(
      subtotal.padLeft(anchoLinea),
      styles: const PosStyles(align: PosAlign.left),
    ),
  ];

  /// «cantidad x nombre», izquierda y negrita. Compartida por la factura, el
  /// recibo de caja y la guía de almacén.
  static List<int> _lineaCantidadNombre(
    Generator generator,
    String cantidad,
    String nombre,
  ) => generator.text(
    '${cantidad}x $nombre',
    styles: const PosStyles(align: PosAlign.left, bold: true),
  );

  /// «TOTAL MONEDA» a la izquierda y el monto a la derecha, en la misma línea.
  static List<int> totalBytes(
    Generator generator, {
    required String moneda,
    required String monto,
  }) => generator.text(
    justificada('TOTAL $moneda', monto),
    styles: const PosStyles(align: PosAlign.left, bold: true),
  );

  /// Guía de almacén: cantidad y nombre completo, y debajo la ubicación.
  static List<int> almacenProductoBytes(
    Generator generator, {
    required String cantidad,
    required String nombre,
    required String ubicacion,
  }) => [
    ..._lineaCantidadNombre(generator, cantidad, nombre),
    ...generator.text(
      '   Ubic: $ubicacion',
      styles: const PosStyles(align: PosAlign.left),
    ),
  ];
}
