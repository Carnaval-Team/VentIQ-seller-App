/// Resultado del arqueo de UNA moneda: contado frente a lo que debe haber.
///
/// El cierre reporta el efectivo por moneda, así que la verificación también es
/// por moneda: lo que sobra en una no compensa lo que falta en otra, y ningún
/// importe se convierte a una moneda común.
enum EstadoArqueo { sinEsperado, cuadra, falta, sobra }

class ArqueoMoneda {
  final String moneda;
  final double contado;

  /// Lo que debe haber en caja de esta moneda; `null` si no se conoce.
  final double? esperado;

  const ArqueoMoneda({
    required this.moneda,
    required this.contado,
    this.esperado,
  });

  /// Medio centavo: por debajo no hay diferencia real (redondeo de importes).
  static const tolerancia = 0.005;

  /// Contado − esperado, en la moneda nativa. `null` sin esperado.
  double? get diferencia => esperado == null ? null : contado - esperado!;

  EstadoArqueo get estado {
    final d = diferencia;
    if (d == null) return EstadoArqueo.sinEsperado;
    if (d.abs() < tolerancia) return EstadoArqueo.cuadra;
    return d < 0 ? EstadoArqueo.falta : EstadoArqueo.sobra;
  }

  /// Un renglón por moneda, en el orden dado, sin mezclar importes.
  static List<ArqueoMoneda> lista({
    required List<String> monedas,
    required Map<String, double> contado,
    Map<String, double> esperado = const {},
  }) => [
    for (final moneda in monedas)
      ArqueoMoneda(
        moneda: moneda,
        contado: contado[moneda] ?? 0,
        esperado: esperado[moneda],
      ),
  ];
}
