import 'exact_money.dart';
import 'venta_v1_envio.dart';

class CxcV1Exception implements Exception {
  final String code;
  CxcV1Exception(this.code);
  @override
  String toString() => code;
}

class SaldoMoneda {
  final String moneda;
  final String saldo;
  const SaldoMoneda(this.moneda, this.saldo);
}

/// La deuda nueva se lee y se cobra por moneda. No se suma con otra.
class CxcV1 {
  static List<SaldoMoneda> saldos(List<Map<String, dynamic>> obligaciones) {
    final lineas = <LineaCobro>[];
    for (final fila in obligaciones) {
      if (fila['version_monetaria'] != 'producto-v1') continue;
      final moneda = fila['moneda']?.toString();
      final saldo = fila['saldo_nativo']?.toString();
      if (moneda != 'CUP' && moneda != 'USD') {
        throw CxcV1Exception('UNSUPPORTED_CURRENCY');
      }
      if (saldo == null) throw CxcV1Exception('SALDO_AUSENTE');
      lineas.add(LineaCobro(
        idLinea: '${lineas.length}',
        moneda: moneda!,
        medio: null,
        pendiente: false,
        neto: saldo,
        cup: saldo,
        tasaDisponible: true,
      ));
    }
    return [
      for (final grupo in CheckoutV1.agrupar(lineas))
        SaldoMoneda(grupo.moneda, grupo.neto),
    ];
  }

  static void validarLiquidacion({
    required String monedaDeuda,
    required String monedaPago,
    required int? medioFijado,
    required int medioPago,
    required String saldo,
    required String monto,
  }) {
    if (monedaPago != monedaDeuda) {
      throw CxcV1Exception('MONEDA_DISTINTA');
    }
    if (medioFijado != null && medioFijado != medioPago) {
      throw CxcV1Exception('MEDIO_DISTINTO');
    }
    if (ExactMoney.parse(monto) > ExactMoney.parse(saldo)) {
      throw CxcV1Exception('EXCEDE_SALDO');
    }
  }
}

class AjusteV1 {
  static void validarDevolucion({
    required String? version,
    required String monedaOriginal,
    required String monedaDevolucion,
  }) {
    if (version != 'producto-v1') {
      throw CxcV1Exception('CONTRACT_VERSION_UNSUPPORTED');
    }
    if (monedaDevolucion != monedaOriginal) {
      throw CxcV1Exception('MONEDA_DISTINTA');
    }
  }
}
