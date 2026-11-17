import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/money/product_currency_order.dart';
import 'package:ventiq_app/services/order_service.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const userId = '00000000-0000-4000-8000-000000000099';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });

  setUp(() async {
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': userId, 'exp': DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000})}.test-signature';
    await Supabase.instance.client.auth.setInitialSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'user': {
          'id': userId,
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    SharedPreferences.setMockInitialValues({
      'user_id': userId,
      'id_tienda': 4,
      'is_logged_in': true,
    });
    await UserPreferencesService().savePoliticaMoneda({
      'flag': true,
      'id_tienda': 4,
      'denegada': false,
      'revision': {
        'id': 9,
        'id_tienda': 4,
        'forzar_moneda_venta': false,
        'moneda_venta_forzada': null,
        'monedas_habilitadas': ['CUP', 'USD'],
      },
      'constancia': {
        'id_tienda': 4,
        'id_revision': 9,
        'uuid_sujeto': userId,
      },
    });
  });

  tearDownAll(() => Supabase.instance.dispose());

  test('la preorden versionada se guarda y se relee sin perder el carrito', () async {
    final service = OrderService();
    final seleccion = ProductCurrencySeleccion(
      idLineaCliente: '00000000-0000-4000-8000-0000000000aa',
      idProducto: '101',
      cantidad: '1',
      monedaVenta: 'USD',
      tipoCobro: 'medio_pago',
      idMedioPago: 1,
      precioUnitarioNativo: '1.05',
      descuentoManualUnitario: '0',
      snapshotPrecio: const {'tipo': 'general', 'valor_publicado': '1'},
      snapshotTasa: const {
        'valor_publicado': '400',
        'evidencia_publicacion': 'fixture-only',
      },
      ajustesAutomaticos: const [],
    );

    await service.addItemToCurrentOrder(
      producto: Product.fromJson({
        'id': 101,
        'denominacion': 'Cafe',
        'precio': 100,
        'precio_venta_usd': 1.05,
      }),
      cantidad: 1,
      ubicacionAlmacen: 'test',
      seleccion: seleccion,
    );

    final order = service.currentOrder;
    expect(order, isNotNull);
    expect(order!.versionMonetaria, ProductCurrencySeleccion.version);
    // Sin client_uuid la preorden persistida era ilegible para su propio
    // contrato y el carrito se vaciaba al abrir la pantalla de preorden.
    expect(order.clientUuid, isNotNull);
    expect(order.clientUuid, isNotEmpty);

    final restored = Order.fromJson(order.toJson());
    expect(restored.versionMonetaria, ProductCurrencySeleccion.version);
    expect(restored.items, hasLength(1));
    expect(restored.items.single.seleccion?.monedaVenta, 'USD');
  });

  test('una preorden versionada sin client_uuid se rechaza y se limpia', () async {
    await UserPreferencesService().savePersistentPreorder({
      'id': 'vieja',
      'fechaCreacion': '2026-01-01T00:00:00Z',
      'items': <dynamic>[],
      'total': 0,
      'status': 0,
      'version_monetaria': ProductCurrencySeleccion.version,
    });

    await OrderService().loadPersistentPreorder();

    expect(OrderService().currentOrder, isNull);
    expect(await UserPreferencesService().hasPersistentPreorder(), isFalse);
  });
}
