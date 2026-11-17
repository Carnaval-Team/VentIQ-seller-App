import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/exact_money.dart';

void main() {
  test('3 x 100 menos 10 por unidad son 270', () {
    final neto = ExactMoney.parse('100') - ExactMoney.parse('10');
    expect(neto.times(3).toString(), '270');
  });

  test('3 x 1.05 con 10 por ciento queda en 2.84', () {
    final neto =
        ExactMoney.parse('1.05').percentOff(10).times(3).roundHalfUp(2);
    expect(neto.toString(), '2.84');
  });

  test('rechaza un importe no finito', () {
    expect(() => ExactMoney.parse('NaN'), throwsFormatException);
    expect(() => ExactMoney.parse(''), throwsFormatException);
  });
}
