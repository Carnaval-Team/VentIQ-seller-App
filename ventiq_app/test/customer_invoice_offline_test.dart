import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/screens/orders_screen.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';
import 'preorder_totales_moneda_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'los datos de contacto de tienda sobreviven al cache de impresión',
    () async {
      final prefs = UserPreferencesService();
      await prefs.saveStorePrintInfo(
        'Tienda de prueba',
        null,
        Uint8List.fromList([1, 2]),
        address: 'Dirección de prueba',
        location: 'Localidad',
        phone: '5550000',
      );
      await prefs.saveStorePrintInfo(
        'Tienda de prueba',
        null,
        Uint8List.fromList([1, 2]),
      );
      final info = await prefs.getStorePrintInfo();
      expect(info!['address'], 'Dirección de prueba');
      expect(info['location'], 'Localidad');
      expect(info['phone'], '5550000');
      await prefs.clearStoreConfig();
      expect(await prefs.getStorePrintInfo(), isNull);
    },
  );

  for (final offline in [false, true]) {
    for (final cached in [false, true]) {
      test(
        'genera PDF sin Supabase (offline=$offline, cache=$cached)',
        () async {
          if (cached) {
            await UserPreferencesService().saveStorePrintInfo(
              'Tienda de prueba',
              null,
              null,
              address: 'Dirección de prueba',
              location: 'Localidad',
              phone: '5550000',
            );
          }
          final original = fixtures
              .orden(
                items: [
                  fixtures
                      .item(idProducto: 1, precio: 100, cantidad: 2)
                      .copyWith(
                        ingredientes: [
                          {
                            'nombre_ingrediente': 'Ingrediente guardado',
                            'cantidad_vendida': 2,
                            'unidad_medida': 'unid',
                          },
                        ],
                      ),
                ],
              )
              .copyWith(
                isOfflineOrder: offline,
                status: OrderStatus.completada,
                buyerName: 'Cliente de prueba',
                descuento: {
                  'monto_real': 200,
                  'monto_descontado': 20,
                  'tipo_descuento': 1,
                  'valor_descuento': 10,
                },
              );
          final restored = Order.fromJson(
            jsonDecode(jsonEncode(original.toJson())),
          );
          final invoice = await OrdersScreen.buildCustomerInvoicePdf(restored);
          expect(invoice.storeName, cached ? 'Tienda de prueba' : 'Inventtia');
          expect(ascii.decode(invoice.bytes.take(5).toList()), '%PDF-');
          expect(invoice.bytes.length, greaterThan(500));
          expect(
            restored.items.single.ingredientes!.single['nombre_ingrediente'],
            'Ingrediente guardado',
          );
        },
      );
    }
  }

  test(
    'genera la factura de una orden multimoneda restaurada offline',
    () async {
      final order = fixtures
          .orden(
            version: 'producto-v1',
            items: [
              fixtures.item(
                idProducto: 1,
                precio: 200,
                cantidad: 1,
                sel: fixtures.seleccion(moneda: 'CUP', precio: '200'),
              ),
              fixtures.item(
                idProducto: 2,
                precio: 3.15,
                cantidad: 1,
                sel: fixtures.seleccion(
                  moneda: 'USD',
                  precio: '3.15',
                  tasa: '400',
                ),
              ),
            ],
          )
          .copyWith(
            isOfflineOrder: true,
            clientUuid: '00000000-0000-4000-8000-000000000001',
          );
      final restored = Order.fromJson(jsonDecode(jsonEncode(order.toJson())));
      final invoice = await OrdersScreen.buildCustomerInvoicePdf(restored);
      expect(ascii.decode(invoice.bytes.take(5).toList()), '%PDF-');
      expect(invoice.bytes.length, greaterThan(500));
    },
  );

  test('web y nativo comparten el generador sin consultas remotas', () {
    final source = File('lib/screens/orders_screen.dart').readAsStringSync();
    final generation = source.substring(
      source.indexOf('  Future<void> _generateCustomerInvoice('),
      source.indexOf('  static pw.Document _buildInvoicePdf('),
    );
    expect(generation, isNot(contains('Supabase.instance')));
    expect(generation, isNot(contains('_downloadImageBytes(')));
    expect(
      RegExp(
        r'OrdersScreen.buildCustomerInvoicePdf\(',
      ).allMatches(generation).length,
      2,
    );
  });

  test('PDF y WiFi usan ReceiptOptions.thanksMessage (sin Vuelva Pronto)', () {
    final pdf = File('lib/screens/orders_screen.dart').readAsStringSync();
    final wifi = File('lib/services/wifi_printer_service.dart').readAsStringSync();
    final pdfFooter = pdf.substring(
      pdf.indexOf('static pw.Document _buildInvoicePdf('),
    );
    expect(pdfFooter, contains('ReceiptOptions('));
    expect(pdfFooter, contains('thanksMessage'));
    expect(wifi, contains('receiptOptions.thanksMessage'));
    expect(wifi, isNot(contains("'Vuelva Pronto'")));
  });
}
