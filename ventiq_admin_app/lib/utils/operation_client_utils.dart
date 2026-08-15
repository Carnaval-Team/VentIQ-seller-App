/// Resolución del cliente de una operación de inventario/venta.
///
/// La venta por acuerdo y la venta desde orden registran la venta con
/// `p_id_cliente: null`, así que `detalles_especificos.nombre_cliente` llega
/// vacío y la UI mostraba "N/A". El nombre sí queda escrito en las
/// observaciones, en dos formatos:
///   `Cliente: <nombre>. Total: $186300.00. <obs libre>`  (venta por acuerdo)
///   `Cliente: <nombre>\nProductos:\n1 x Pan`              (venta desde orden)
library;

/// Corta el nombre en el primer delimitador real: `. Total:`, punto final,
/// salto de línea o fin de texto. El cuantificador perezoso evita comerse
/// la parte de "Total" y tolera nombres con punto ("Dr. Ramon").
final RegExp _clienteObsRegex = RegExp(
  r'Cliente:\s*([^\n\r]*?)\s*(?:\.\s*Total\s*:|\.\s*$|[\n\r]|$)',
  caseSensitive: false,
);

/// Nombre del cliente embebido en las observaciones, o `null` si no hay.
String? extractClienteFromObservaciones(dynamic observaciones) {
  final obs = observaciones?.toString() ?? '';
  if (obs.isEmpty) return null;
  final nombre = _clienteObsRegex.firstMatch(obs)?.group(1)?.trim();
  if (nombre == null || nombre.isEmpty) return null;
  return nombre;
}

/// `detalles.detalles_especificos` de la operación, tolerante al tipo del mapa.
Map<String, dynamic>? extractDetallesEspecificos(
  Map<String, dynamic> operation,
) {
  final detalles = operation['detalles'];
  if (detalles is Map) {
    final esp = detalles['detalles_especificos'];
    if (esp is Map<String, dynamic>) return esp;
    if (esp is Map) return Map<String, dynamic>.from(esp);
  }
  return null;
}

/// Cliente de la operación: el registrado en la venta y, si no hay
/// (venta por acuerdo), el que quedó escrito en las observaciones.
String? resolveOperationClienteNombre(Map<String, dynamic> operation) {
  final registrado = extractDetallesEspecificos(
    operation,
  )?['nombre_cliente']?.toString().trim();
  if (registrado != null && registrado.isNotEmpty) return registrado;
  return extractClienteFromObservaciones(operation['observaciones']);
}
