/// Resolución del precio propio de un turno (`{moneda: precio}`).
///
/// Es una función pura (no depende de `BuildContext`) y vive aquí para que la
/// ficha del cliente, la del admin y el preview de reservas del admin usen
/// **exactamente la misma** regla que el servidor: si divergen, el precio que
/// se muestra deja de coincidir con el que se cobra.
///
/// Respaldo idéntico al de `flow.calcular_precio_turno` (migración 51):
/// moneda elegida → moneda por defecto del servicio → `null`.
///
/// `null` significa "este turno no trae precio propio": entonces la base la pone
/// el `precios_base` del servicio. Nunca se inventa un importe (nada de
/// `precios.values.first`, que cobraría la moneda equivocada).
double? precioBaseTurno({
  required Map<String, double>? precios,
  String? moneda,
  required String monedaDefault,
}) {
  if (precios == null || precios.isEmpty) return null;
  return precios[moneda ?? monedaDefault] ?? precios[monedaDefault];
}