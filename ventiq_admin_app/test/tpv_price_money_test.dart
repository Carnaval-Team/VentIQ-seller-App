import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/tpv_price.dart';
import 'package:ventiq_admin_app/models/tpv_price_money.dart';

void main() {
  test('el vacio no es cero y el cero se rechaza', () {
    expect(TpvPriceMoney.opcional(null), isNull);
    expect(TpvPriceMoney.opcional(''), isNull);
    expect(() => TpvPriceMoney.opcional('0'), throwsFormatException);
    expect(() => TpvPriceMoney.opcional('-1'), throwsFormatException);
    expect(TpvPriceMoney.opcional('1.25'), 1.25);
  });

  test('importar CUP no borra el USD ausente', () {
    final soloCup = TpvPriceImportData.fromExcel({
      'id_producto': '4',
      'id_tpv': '8',
      'precio_venta_cup': '10.50',
    });
    expect(soloCup.precioVentaCup, 10.50);
    expect(soloCup.heredarUsd, isTrue);
    expect(soloCup.precioVentaUsd, isNull);

    final vacio = TpvPriceImportData.fromExcel({
      'id_producto': 4,
      'id_tpv': 8,
      'precio_venta_cup': 10,
      'precio_venta_usd': '',
    });
    expect(vacio.heredarUsd, isTrue);

    expect(
      () => TpvPriceImportData.fromExcel({
        'id_producto': 4,
        'id_tpv': 8,
        'precio_venta_cup': 10,
        'precio_venta_usd': '0',
      }),
      throwsFormatException,
    );
  });

  test('la exportacion no convierte el USD ausente en cero', () {
    final row = TpvPrice(
      id: 1,
      idProducto: 4,
      idTpv: 8,
      precioVentaCup: 10,
      precioVentaUsd: null,
      fechaDesde: DateTime(2026, 11, 14),
      esActivo: true,
      createdAt: DateTime(2026, 11, 14),
      updatedAt: DateTime(2026, 11, 14),
    ).toExportRow();
    expect(row['precio_venta_cup'], 10);
    expect(row['precio_venta_usd'], isNull);
    expect(row.containsKey('precio_venta_usd'), isTrue);
  });

  test('el aviso no habilita USD sin CUP', () {
    expect(
      TpvPricePreview.texto(editando: true, usdVacio: true),
      contains('CUP sigue obligatorio'),
    );
  });
}
