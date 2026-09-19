import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/services/servicentro_service.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';
import 'package:ventiq_app/utils/price_utils.dart';

void main() {
  test('servicentro preserves the exact amount entered by the seller', () {
    final unitPrice = ServicentroService.unitPriceForEnteredAmount(
      liters: 3.333,
      amount: 500,
    );

    expect(unitPrice * 3.333, closeTo(500, 0.000001));
  });

  test('mixed payments are summed using their CUP equivalents', () {
    final payments = <Map<String, dynamic>>[
      {'monto': 420, 'moneda': 'CUP'},
      {'monto': 2, 'moneda': 'USD', 'tasa_usd': 420},
    ];

    expect(PriceUtils.paymentTotalCup(payments), 1260);
    expect(PriceUtils.paymentTotalUsd(payments), 2);
  });

  test('offline mode has no invented USD rate when cache is empty', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await UserPreferencesService().getCambioCupUsd(), 0);
  });

  test('uses USD as primary currency only when every payment is USD', () {
    final usdOnly = <Map<String, dynamic>>[
      {'monto': 1, 'moneda': 'USD', 'tasa_usd': 420},
      {'monto': 2, 'moneda': 'USD', 'tasa_usd': 420},
    ];
    final mixed = <Map<String, dynamic>>[
      {'monto': 1, 'moneda': 'USD', 'tasa_usd': 420},
      {'monto': 100, 'moneda': 'CUP'},
    ];

    expect(PriceUtils.paymentDisplayCurrency(usdOnly), 'USD');
    expect(PriceUtils.formatCupAmountForPayments(840, usdOnly), '2.00 USD');
    expect(
      PriceUtils.formatCupAmountForPayments(5000, [
        {'monto': '9.090909', 'moneda': 'USD', 'tasa_usd': '550.0'},
      ]),
      '9.09 USD',
    );
    expect(PriceUtils.paymentDisplayCurrency(mixed), 'CUP');
    expect(PriceUtils.formatCupAmountForPayments(520, mixed), '520.00 CUP');
  });

  test('formats each payment in its own currency', () {
    expect(
      PriceUtils.formatPaymentAmount({
        'monto': 2.5,
        'moneda': 'USD',
        'tasa_usd': 420,
      }),
      '2.50 USD',
    );
    expect(
      PriceUtils.formatPaymentAmount({'monto': 500, 'moneda': 'CUP'}),
      '500.00 CUP',
    );
  });
}
