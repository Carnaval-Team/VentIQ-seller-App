import 'line_money.dart';

enum PoliticaMonedaFase { apagada, incompleta, lista }

class PoliticaMonedaException implements Exception {
  final String message;
  PoliticaMonedaException(this.message);
  @override
  String toString() => message;
}

/// Lectura de la política. El flag solo no enciende el modo.
class PoliticaMonedaEstado {
  final PoliticaMonedaFase fase;

  const PoliticaMonedaEstado._(this.fase);

  static const apagada = PoliticaMonedaEstado._(PoliticaMonedaFase.apagada);
  static const incompleta = PoliticaMonedaEstado._(PoliticaMonedaFase.incompleta);
  static const lista = PoliticaMonedaEstado._(PoliticaMonedaFase.lista);

  bool get modoActivo => fase == PoliticaMonedaFase.lista;

  /// Una política encendida pero sin evidencia bloquea la orden nueva.
  bool get bloqueaOrdenNueva => fase == PoliticaMonedaFase.incompleta;

  static PoliticaMonedaEstado interpretar({
    Map<String, dynamic>? cache,
    int? tiendaSesion,
    String? usuario,
  }) {
    if (cache == null || cache['flag'] != true) return apagada;
    if (cache['denegada'] == true) return incompleta;
    final tienda = cache['id_tienda'];
    if (tienda is! int || tiendaSesion == null || tienda != tiendaSesion) {
      return incompleta;
    }
    final revision = cache['revision'];
    final constancia = cache['constancia'];
    if (revision is! Map || constancia is! Map) return incompleta;
    if (revision['id_tienda'] != tienda || constancia['id_tienda'] != tienda) {
      return incompleta;
    }
    final sujeto = constancia['uuid_sujeto']?.toString();
    if (usuario == null || sujeto == null || sujeto != usuario) {
      return incompleta;
    }
    if (constancia['id_revision'] != revision['id']) return incompleta;
    final monedas = revision['monedas_habilitadas'];
    if (monedas is! List || monedas.isEmpty) return incompleta;
    if (monedas.any((m) => m != 'CUP' && m != 'USD')) return incompleta;
    final forzada = revision['moneda_venta_forzada'];
    if (revision['forzar_moneda_venta'] == true) {
      if (forzada != 'CUP' && forzada != 'USD') return incompleta;
      if (!monedas.contains(forzada)) return incompleta;
    }
    return lista;
  }

  /// Una respuesta de otra tienda no reemplaza la caché de la sesión.
  static bool puedeReemplazar({
    required int tiendaRespuesta,
    required int? tiendaSesion,
  }) {
    return tiendaSesion != null && tiendaRespuesta == tiendaSesion;
  }
}

class LineaMonedaPreparada {
  final String moneda;
  final String precio;
  final String tasa;
  final String manual;
  final LineMoney calculo;

  const LineaMonedaPreparada({
    required this.moneda,
    required this.precio,
    required this.tasa,
    required this.manual,
    required this.calculo,
  });
}

/// Con el modo apagado no pide moneda. Con el modo listo exige precio, tasa y permiso.
class SeleccionLineaMoneda {
  static LineaMonedaPreparada? preparar({
    required bool modoActivo,
    String? moneda,
    String? precio,
    String? tasa,
    String manual = '0',
    bool permiteDescuento = false,
  }) {
    if (!modoActivo) return null;
    if (moneda != 'CUP' && moneda != 'USD') {
      throw PoliticaMonedaException('Moneda no permitida');
    }
    if (manual != '0' && !permiteDescuento) {
      throw PoliticaMonedaException('Sin permiso para el descuento manual');
    }
    final tasaEfectiva = moneda == 'CUP' ? '1' : tasa;
    if (tasaEfectiva == null || tasaEfectiva.isEmpty) {
      throw PoliticaMonedaException('Falta la tasa de la linea');
    }
    final calculo = LineMoneyCalculator.calcular(
      moneda: moneda!,
      cantidad: '1',
      precioUnitario: precio,
      automaticoTipo: 'none',
      automaticoValor: '0',
      manualUnitario: manual,
      tasaCup: tasaEfectiva,
    );
    return LineaMonedaPreparada(
      moneda: moneda,
      precio: precio!,
      tasa: tasaEfectiva,
      manual: manual,
      calculo: calculo,
    );
  }
}

enum DecisionDuplicado { unir, separar, cancelar, pedirConfirmacion }

class DuplicadoLinea {
  static DecisionDuplicado decidir({
    required bool mismaPresentacion,
    required bool mismaMoneda,
    required bool mismoMedio,
    required bool confirmado,
    bool cancelado = false,
  }) {
    if (cancelado) return DecisionDuplicado.cancelar;
    if (!mismaPresentacion || !mismaMoneda || !mismoMedio) {
      return DecisionDuplicado.separar;
    }
    if (!confirmado) return DecisionDuplicado.pedirConfirmacion;
    return DecisionDuplicado.unir;
  }
}
