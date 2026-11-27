/// Aritmética pura de los costos de compra y recepción.
///
/// Vive fuera de las pantallas para poder probarla sin Flutter: el reparto por
/// cantidad de un costo adicional y el costo unitario que verá el usuario.
class ComprasCostosCalculo {
  const ComprasCostosCalculo._();

  /// Ajustes por unidad cuando el reparto es por cantidad.
  static double ajustesPorUnidad({
    required double ajustesTotal,
    required double cantidadTotal,
  }) {
    if (!ajustesTotal.isFinite || !cantidadTotal.isFinite) return 0;
    if (ajustesTotal <= 0 || cantidadTotal <= 0) return 0;
    return ajustesTotal / cantidadTotal;
  }

  /// Costo unitario después de sumar los ajustes repartidos por cantidad.
  static double costoUnitarioAterrizado({
    required double costoUnitario,
    required double ajustesTotal,
    required double cantidadTotal,
  }) {
    return costoUnitario +
        ajustesPorUnidad(
          ajustesTotal: ajustesTotal,
          cantidadTotal: cantidadTotal,
        );
  }

  /// Reparte [monto] entre las líneas en proporción a [cantidades].
  ///
  /// Redondea a centavos por línea y manda el residuo a la línea de mayor
  /// cantidad (empate: la primera). Así Σ cuotas = monto y no se pierde ni un
  /// centavo. Devuelve una lista de la misma longitud que [cantidades].
  static List<double> repartirPorCantidad({
    required List<double> cantidades,
    required double monto,
  }) {
    final cuotas = List<double>.filled(cantidades.length, 0);
    if (cantidades.isEmpty || !monto.isFinite || monto <= 0) return cuotas;

    var total = 0.0;
    for (final c in cantidades) {
      if (c.isFinite && c > 0) total += c;
    }
    if (total <= 0) return cuotas;

    var asignado = 0.0;
    var maxIdx = 0;
    var maxCantidad = -1.0;
    for (var i = 0; i < cantidades.length; i++) {
      final c = (cantidades[i].isFinite && cantidades[i] > 0)
          ? cantidades[i]
          : 0.0;
      if (c > maxCantidad) {
        maxCantidad = c;
        maxIdx = i;
      }
      final cuota = ((monto * c / total) * 100).round() / 100;
      cuotas[i] = cuota;
      asignado += cuota;
    }

    final residuo = ((monto - asignado) * 100).round() / 100;
    if (residuo != 0) {
      cuotas[maxIdx] = ((cuotas[maxIdx] + residuo) * 100).round() / 100;
    }
    return cuotas;
  }
}
