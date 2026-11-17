import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/order_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var scenario = 'missing';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'user_id': '11111111-1111-4111-8111-111111111111',
    });
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final fn = request.url.path.split('/').last;
        if (scenario == 'denied' && fn.endsWith('_v2')) {
          return http.Response(
            jsonEncode({
              'code': '42501',
              'message': 'schema cache: acceso denegado',
            }),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (scenario == 'missing' && fn.endsWith('_v2')) {
          return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.$fn in the schema cache',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode({
            'status': 'success',
            'total_orden': 10,
            'importe_nuevo': 4,
            'id_extraccion': 3,
            'importe': 4,
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  setUp(() {
    requests.clear();
  });

  List<String> rpcNames() => [
    for (final request in requests)
      if (request.url.path.contains('/rpc/')) request.url.path.split('/').last,
  ];

  test('cambiar cantidad no usa la funcion sin conversion', () async {
    scenario = 'missing';
    final result = await OrderService().updatePendingOrderItemQuantity(
      idExtraccion: 8,
      nuevaCantidad: 2,
    );
    expect(result['success'], isFalse);
    expect(rpcNames(), ['fn_actualizar_cantidad_producto_orden_v2']);

    requests.clear();
    scenario = 'denied';
    final denied = await OrderService().updatePendingOrderItemQuantity(
      idExtraccion: 8,
      nuevaCantidad: 2,
    );
    expect(denied['success'], isFalse);
    expect(rpcNames(), ['fn_actualizar_cantidad_producto_orden_v2']);
  });

  test('quitar un producto no usa la funcion sin conversion', () async {
    scenario = 'missing';
    final result = await OrderService().removePendingOrderItem(
      idExtraccion: 8,
    );
    expect(result['success'], isFalse);
    expect(rpcNames(), ['fn_eliminar_producto_orden_v2']);

    requests.clear();
    scenario = 'denied';
    final denied = await OrderService().removePendingOrderItem(
      idExtraccion: 8,
    );
    expect(denied['success'], isFalse);
    expect(rpcNames(), ['fn_eliminar_producto_orden_v2']);
  });

  test('agregar un producto no usa la funcion sin conversion', () async {
    scenario = 'missing';
    final result = await OrderService().addProductToPendingOrder(
      operationId: 4,
      producto: const {'id_producto': 1, 'cantidad': 1},
    );
    expect(result['success'], isFalse);
    expect(rpcNames(), ['fn_agregar_producto_orden_pendiente_v2']);

    requests.clear();
    scenario = 'ok';
    final ok = await OrderService().addProductToPendingOrder(
      operationId: 4,
      producto: const {'id_producto': 1, 'cantidad': 1},
    );
    expect(ok['success'], isTrue);
    expect(rpcNames(), ['fn_agregar_producto_orden_pendiente_v2']);
  });
}
