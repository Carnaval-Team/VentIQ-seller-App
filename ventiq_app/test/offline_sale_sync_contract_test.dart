import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/auto_sync_service.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var scenario = 'success';
  const orderId = 'offline-sale-test';
  const uuid = '00000000-0000-4000-8000-000000000021';
  const paymentUuid = '00000000-0000-4000-8000-000000000022';
  const userId = '00000000-0000-4000-8000-000000000023';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET' &&
            request.url.path.contains('app_dat_pago_venta')) {
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        final fn = request.url.path.split('/').last;
        var status = 200;
        Object response = {'status': 'error', 'message': 'Ruta no prevista'};
        if (scenario == 'denied_schema_cache') {
          status = 403;
          response = {
            'code': '42501',
            'message': 'schema cache: acceso denegado a $fn',
          };
        } else if (scenario == 'timeout') {
          throw TimeoutException('Respuesta perdida');
        } else if (scenario == 'nested_missing') {
          status = 400;
          response = {
            'code': '42883',
            'message': 'function public.helper_interno() does not exist',
          };
        } else if (scenario == 'all_missing' ||
            (scenario == 'fallback_v3' &&
                fn == 'fn_registrar_venta_offline_v4')) {
          status = 404;
          response = {
            'code': 'PGRST202',
            'message':
                'Could not find the function public.$fn() in the schema cache',
          };
        } else if (scenario == 'estado_sin_clave') {
          if (fn == 'fn_registrar_venta_offline_v4') {
            response = {
              'status': 'success',
              'id_operacion': 71,
              'idempotent': false,
            };
          } else if (fn == 'fn_registrar_cambio_estado_offline' ||
              fn == 'fn_registrar_cambio_estado_operacion') {
            status = 404;
            response = {
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.$fn() in the schema cache',
            };
          }
        } else if (scenario == 'pago_sin_clave') {
          if (fn == 'fn_registrar_venta_offline_v4') {
            response = {
              'status': 'success',
              'id_operacion': 71,
              'idempotent': false,
            };
          } else {
            status = 404;
            response = {
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.$fn() in the schema cache',
            };
          }
        } else if (scenario == 'idempotent_mismatch' &&
            fn == 'fn_registrar_venta_offline_v4') {
          response = {
            'status': 'success',
            'id_operacion': 71,
            'idempotent': true,
          };
        } else if (fn == 'fn_registrar_venta_offline_v4' ||
            fn == 'fn_registrar_venta_offline_v3') {
          response = {
            'status': 'success',
            if (scenario != 'invalid_id') 'id_operacion': 71,
            'idempotent': false,
          };
        }
        return http.Response(
          jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  setUp(() async {
    scenario = 'success';
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
      'user_email': 'test@example.com',
      'access_token': token,
      'is_logged_in': true,
      'id_tpv': 9,
    });
    await UserPreferencesService().savePendingOrder({
      'id': orderId,
      'client_uuid': uuid,
      'client_uuid_pago': paymentUuid,
      'estado': 'pendiente',
      'items': [
        {'id_producto': 7, 'cantidad': 1, 'precio_unitario': 0, 'subtotal': 0},
      ],
      'desglose_pagos': <Object>[],
    });
    requests.clear();
  });

  tearDownAll(() => Supabase.instance.dispose());

  for (final outcome in [
    'denied_schema_cache',
    'timeout',
    'nested_missing',
    'all_missing',
    'invalid_id',
    'success',
    'fallback_v3',
  ]) {
    test('$outcome conserva cola y UUID sin alta no idempotente', () async {
      scenario = outcome;
      final success = outcome == 'success' || outcome == 'fallback_v3';
      final result = await AutoSyncService().syncSinglePendingOrder(orderId);
      expect(result, success);
      expect(requests, isNotEmpty);
      expect(
        requests.any((r) => r.url.path.endsWith('/fn_registrar_venta')),
        isFalse,
      );
      if (outcome != 'all_missing' && outcome != 'fallback_v3') {
        expect(requests, hasLength(1));
      }
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body)['p_client_uuid'], uuid);
      }
      final saved = (await UserPreferencesService().getPendingOrders()).single;
      expect(saved['client_uuid'], uuid);
      expect(saved['client_uuid_pago'], paymentUuid);
      expect(saved['items'], hasLength(1));
      expect(saved['synced'] == true, success);
      expect(saved['id_operacion'], success ? 71 : isNull);
      if (!success) expect(saved['last_sync_error'], isNotEmpty);
      if (outcome == 'fallback_v3') {
        expect(requests.map((r) => r.url.path.split('/').last), [
          'fn_registrar_venta_offline_v4',
          'fn_registrar_venta_offline_v3',
        ]);
      }
    });
  }

  test('replay con desglose distinto no reescribe pagos', () async {
    scenario = 'idempotent_mismatch';
    await UserPreferencesService().clearPendingOrders();
    await UserPreferencesService().savePendingOrder({
      'id': orderId,
      'client_uuid': uuid,
      'client_uuid_pago': paymentUuid,
      'estado': 'pendiente',
      'items': [
        {
          'id_producto': 7,
          'cantidad': 1,
          'precio_unitario': 10,
          'subtotal': 10,
        },
      ],
      'desglose_pagos': [
        {'id_medio_pago': 1, 'monto': 10, 'moneda': 'CUP', 'tipo_pago': 1},
      ],
    });
    requests.clear();

    final result = await AutoSyncService().syncSinglePendingOrder(orderId);

    expect(result, isFalse);
    expect(
      requests.any((r) => r.url.path.endsWith('fn_registrar_venta_offline_v4')),
      isTrue,
    );
    expect(
      requests.any((r) => r.url.path.contains('fn_registrar_pago')),
      isFalse,
    );
    expect(
      requests.any((r) => r.url.path.endsWith('/fn_registrar_venta')),
      isFalse,
    );
    final saved = (await UserPreferencesService().getPendingOrders()).single;
    expect(saved['client_uuid'], uuid);
    expect(saved['client_uuid_pago'], paymentUuid);
    expect(saved['synced'] == true, isFalse);
    expect(saved['last_sync_error'], isNotEmpty);
  });

  test('cobro sin RPC idempotente no usa fn_registrar_pago_venta', () async {
    scenario = 'pago_sin_clave';
    await UserPreferencesService().clearPendingOrders();
    await UserPreferencesService().savePendingOrder({
      'id': orderId,
      'client_uuid': uuid,
      'client_uuid_pago': paymentUuid,
      'estado': 'pendiente',
      'items': [
        {
          'id_producto': 7,
          'cantidad': 1,
          'precio_unitario': 10,
          'subtotal': 10,
        },
      ],
      'desglose_pagos': [
        {'id_medio_pago': 1, 'monto': 10, 'moneda': 'CUP', 'tipo_pago': 1},
      ],
    });
    requests.clear();

    final result = await AutoSyncService().syncSinglePendingOrder(orderId);

    expect(result, isFalse);
    expect(
      requests.any((r) => r.url.path.endsWith('/fn_registrar_pago_venta')),
      isFalse,
    );
    expect(
      requests.any((r) => r.url.path.endsWith('fn_registrar_pago_venta_v3')),
      isTrue,
    );
    final saved = (await UserPreferencesService().getPendingOrders()).single;
    expect(saved['client_uuid'], uuid);
    expect(saved['client_uuid_pago'], paymentUuid);
    expect(saved['synced'] == true, isFalse);
    expect(saved['last_sync_error'], isNotEmpty);
  });

  test('cambio de estado sin RPC idempotente no usa la función original', () async {
    scenario = 'estado_sin_clave';
    await UserPreferencesService().clearPendingOrders();
    await UserPreferencesService().savePendingOrder({
      'id': orderId,
      'client_uuid': uuid,
      'client_uuid_pago': paymentUuid,
      'estado': 'completada',
      'items': [
        {'id_producto': 7, 'cantidad': 1, 'precio_unitario': 0, 'subtotal': 0},
      ],
      'desglose_pagos': <Object>[],
    });
    requests.clear();

    final result = await AutoSyncService().syncSinglePendingOrder(orderId);

    expect(result, isFalse);
    expect(
      requests.any(
        (r) => r.url.path.endsWith('fn_registrar_cambio_estado_offline'),
      ),
      isTrue,
    );
    expect(
      requests.any(
        (r) => r.url.path.endsWith('/fn_registrar_cambio_estado_operacion'),
      ),
      isFalse,
    );
    final saved = (await UserPreferencesService().getPendingOrders()).single;
    expect(saved['client_uuid'], uuid);
    expect(saved['client_uuid_estado_2'], isNotEmpty);
    expect(saved['synced'] == true, isFalse);
    expect(saved['last_sync_error'], isNotEmpty);
  });

  test('cola de estado usa la RPC con clave', () async {
    scenario = 'estado_sin_clave';
    await UserPreferencesService().savePendingOperation({
      'type': 'order_status_change',
      'order_id': 'ORD-88',
      'id_operacion': 88,
      'new_status': 'completada',
    });
    requests.clear();

    final synced = await AutoSyncService().syncPendingOrderStatusChanges();

    expect(synced, 0);
    expect(
      requests.map((r) => r.url.path.split('/').last),
      ['fn_registrar_cambio_estado_offline'],
    );
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['p_id_operacion'], 88);
    expect(body['p_nuevo_estado'], 2);
    expect(body['p_client_uuid'], isNotEmpty);
    final left = await UserPreferencesService().getPendingOperations();
    expect(left, hasLength(1));
    expect(left.single['client_uuid_estado_2'], body['p_client_uuid']);
  });
}
