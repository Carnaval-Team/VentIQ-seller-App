import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/price_utils.dart';

void main() {
  test('agrupa la parte entera con espacios finos no separables', () {
    expect(PriceUtils.formatAmount(30000, decimals: 0), '30\u202F000');
    expect(
      PriceUtils.formatAmount(3000000, decimals: 0),
      '3\u202F000\u202F000',
    );
    expect(PriceUtils.formatAmount(999, decimals: 0), '999');
    expect(PriceUtils.formatAmount(0), '0.00');
  });

  test('conserva signo, decimales y redondeo', () {
    expect(PriceUtils.formatAmount(30000.5), '30\u202F000.50');
    expect(PriceUtils.formatAmount(-3000000.75), '-3\u202F000\u202F000.75');
    expect(PriceUtils.formatAmount(999.999), '1\u202F000.00');
    expect(PriceUtils.formatAmount(12345.678, decimals: 3), '12\u202F345.678');
  });

  test('los formatos compartidos de pagos y descuentos usan agrupación', () {
    expect(PriceUtils.formatDiscountPrice(30000.1), '30\u202F000.00');
    expect(
      PriceUtils.formatPaymentAmount({'monto': 30000.5, 'moneda': 'CUP'}),
      '30\u202F000.50 CUP',
    );
    expect(
      PriceUtils.formatCupAmountForPayments(3000000, []),
      '3\u202F000\u202F000.00 CUP',
    );
    expect(
      PriceUtils.formatCupAmountForPayments(3000000, [
        {'moneda': 'USD', 'tasa_usd': 100},
      ]),
      '30\u202F000.00 USD',
    );
  });

  test('los tickets usan un separador compatible con impresoras térmicas', () {
    expect(PriceUtils.formatTicketMoney(30000, []), '\$30 000 CUP');
  });

  test('no agrupa cantidades ni modifica valores numéricos', () {
    expect(PriceUtils.formatQuantity(30000), '30000');
    expect(PriceUtils.paymentAmount({'monto': 30000.5}), 30000.5);
    expect(
      PriceUtils.paymentTotalCup([
        {'monto': 30000.5},
      ]),
      30000.5,
    );
  });
}
