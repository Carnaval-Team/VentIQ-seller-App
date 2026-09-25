import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_superadmin/services/supplier_payment_service.dart';

void main() {
  group('supplierBasePrice', () {
    test('removes the 12 percent increase from the extraction price', () {
      expect(supplierBasePrice(112), closeTo(100, 0.000001));
    });

    test('keeps product totals based on the original unit price', () {
      final unitPrice = supplierBasePrice(56);

      expect(unitPrice, closeTo(50, 0.000001));
      expect(unitPrice * 3, closeTo(150, 0.000001));
    });
  });
}
