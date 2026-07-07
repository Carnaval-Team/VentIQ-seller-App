/// Conversión y formato de peso según nomenclador (factor → kg).
class PesoUnidadUtil {
  PesoUnidadUtil._();

  static double? aKilogramos(double? valor, double factorAKg) {
    if (valor == null) return null;
    return valor * factorAKg;
  }

  static double? desdeKilogramos(double? kg, double factorAKg) {
    if (kg == null || factorAKg <= 0) return null;
    return kg / factorAKg;
  }

  static int decimalesSugeridos(double valor) {
    if (valor >= 1000) return 0;
    if (valor >= 100) return 0;
    if (valor >= 10) return 1;
    return 2;
  }

  static String formatear({
    required double valor,
    required String simbolo,
    int? decimales,
  }) {
    final d = decimales ?? decimalesSugeridos(valor);
    return '${valor.toStringAsFixed(d)} $simbolo';
  }
}
