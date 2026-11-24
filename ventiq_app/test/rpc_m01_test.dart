import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/rpc_m01.dart';

String _src(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RpcM01.call (MockClient)', () {
    final requests = <http.Request>[];
    // función -> (status, code, message); sin entrada responde 200.
    final errores = <String, (int, String, String)>{};

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-key',
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          final fn = request.url.path.split('/').last;
          final err = errores[fn];
          if (err != null) {
            return http.Response(
              jsonEncode({'code': err.$2, 'message': err.$3}),
              err.$1,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            jsonEncode({'status': 'success', 'via': fn}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
    });

    setUp(() {
      requests.clear();
      errores.clear();
    });

    tearDownAll(() => Supabase.instance.dispose());

    List<String> rpcs() =>
        requests.map((r) => r.url.path.split('/').last).toList();

    test('usa _m01 y no toca el nombre antiguo si existe', () async {
      final resp = await RpcM01.call('fn_x', params: {'p_a': 1});
      expect(rpcs(), ['fn_x_m01']);
      expect((resp as Map)['via'], 'fn_x_m01');
      expect(jsonDecode(requests.single.body)['p_a'], 1);
    });

    test('PGRST202 en _m01 cae al nombre antiguo', () async {
      errores['fn_x_m01'] = (
        404,
        'PGRST202',
        'Could not find the function public.fn_x_m01 in the schema cache',
      );
      final resp = await RpcM01.call('fn_x', params: {'p_a': 1});
      expect(rpcs(), ['fn_x_m01', 'fn_x']);
      expect((resp as Map)['via'], 'fn_x');
    });

    test('42501 en _m01 no cae al nombre antiguo', () async {
      errores['fn_x_m01'] = (403, '42501', 'permission denied for function');
      await expectLater(
        RpcM01.call('fn_x', params: const {}),
        throwsA(isA<PostgrestException>()),
      );
      expect(rpcs(), ['fn_x_m01']);
    });

    test('42501 con texto schema cache tampoco cae', () async {
      errores['fn_x_m01'] = (403, '42501', 'schema cache: acceso denegado');
      await expectLater(
        RpcM01.call('fn_x', params: const {}),
        throwsA(isA<PostgrestException>()),
      );
      expect(rpcs(), ['fn_x_m01']);
    });

    test('error de negocio en _m01 se relanza sin caer', () async {
      errores['fn_x_m01'] = (400, 'P0001', 'saldo insuficiente');
      await expectLater(
        RpcM01.call('fn_x', params: const {}),
        throwsA(isA<PostgrestException>()),
      );
      expect(rpcs(), ['fn_x_m01']);
    });

    test('si faltan ambos se propaga el error del nombre antiguo', () async {
      errores['fn_x_m01'] = (404, 'PGRST202', 'Could not find fn_x_m01');
      errores['fn_x'] = (404, 'PGRST202', 'Could not find fn_x');
      await expectLater(
        RpcM01.call('fn_x', params: const {}),
        throwsA(
          isA<PostgrestException>().having(
            (e) => e.message,
            'message',
            contains('fn_x'),
          ),
        ),
      );
      expect(rpcs(), ['fn_x_m01', 'fn_x']);
    });
  });

  group('RpcM01 helpers', () {
    test('m01Name agrega el sufijo _m01', () {
      expect(
        RpcM01.m01Name('fn_listar_ordenes'),
        'fn_listar_ordenes_m01',
      );
    });

    test('isUnavailable es true con PGRST202 / función no encontrada', () {
      expect(
        RpcM01.isUnavailable(
          Exception('PostgrestException(code: PGRST202, message: x)'),
          'fn_listar_ordenes_m01',
        ),
        isTrue,
      );
      expect(
        RpcM01.isUnavailable(
          Exception('Could not find the function public.fn_x_m01 in the'),
          'fn_x_m01',
        ),
        isTrue,
      );
      expect(
        RpcM01.isUnavailable(
          Exception('function public.fn_x_m01(uuid) does not exist'),
          'fn_x_m01',
        ),
        isTrue,
      );
    });

    test('isUnavailable es false con 42501 aunque diga schema cache', () {
      expect(
        RpcM01.isUnavailable(
          Exception('PostgrestException(code: 42501, message: denied)'),
          'fn_x_m01',
        ),
        isFalse,
      );
      expect(
        RpcM01.isUnavailable(
          Exception('permission denied for function fn_x_m01 (schema cache)'),
          'fn_x_m01',
        ),
        isFalse,
      );
      expect(
        RpcM01.isUnavailable(Exception('42501 PGRST202'), 'fn_x_m01'),
        isFalse,
      );
    });

    test('isUnavailable es false con errores ajenos', () {
      expect(
        RpcM01.isUnavailable(Exception('SocketException'), 'fn_x_m01'),
        isFalse,
      );
      expect(
        RpcM01.isUnavailable(
          Exception('function other_fn does not exist'),
          'fn_x_m01',
        ),
        isFalse,
      );
    });
  });

  group('Contrato de cableado _m01 en el cliente', () {
    test('turno/auto sync llaman las RPC de turno vía RpcM01 (base sin _m01)',
        () {
      final turno = _src('lib/services/turno_service.dart');
      final sync = _src('lib/services/auto_sync_service.dart');

      for (final src in [turno, sync]) {
        expect(src, contains("import 'rpc_m01.dart'"));
      }
      expect(
        turno,
        contains(
          "RpcM01.call(\n          'fn_apertura_turno_offline_monedas'",
        ),
      );
      expect(
        turno,
        contains("RpcM01.call(\n          'fn_cerrar_turno_offline_monedas'"),
      );
      // El respaldo conserva la cadena existente tras el _m01 + nombre antiguo.
      expect(turno, contains("'registrar_apertura_turno_monedas'"));
      expect(turno, contains("'fn_cerrar_turno_tpv_monedas'"));

      expect(
        sync,
        contains('await RpcM01.call(monedasRpc, params: monedasParams)'),
      );
      expect(sync, contains("monedasRpc: 'fn_apertura_turno_offline_monedas'"));
      expect(sync, contains("monedasRpc: 'fn_cerrar_turno_offline_monedas'"));
      expect(sync, contains('respaldoRpc: efectivoInicialUsd == null'));
    });

    test('auto sync cablea venta v4, pago, estado, egreso y alinear', () {
      final sync = _src('lib/services/auto_sync_service.dart');
      for (final fn in const [
        'fn_registrar_venta_offline_v4',
        'fn_registrar_pago_venta_offline',
        'fn_registrar_cambio_estado_offline',
        'fn_alinear_apertura_turno_offline',
      ]) {
        expect(
          RegExp("RpcM01\\.call\\(\\s*'$fn'").hasMatch(sync),
          isTrue,
          reason: '$fn debe pasar por RpcM01.call',
        );
      }
      expect(sync, contains('await RpcM01.call(\n        fn,'));
      expect(
        sync,
        contains("RpcM01.call('fn_registrar_egreso_offline', params: params)"),
      );
      expect(
        RegExp(r"RpcM01\.call\(\s*efectivoFinalUsd == null").hasMatch(sync),
        isTrue,
      );
    });

    test('order_service, egreso y comanda usan RpcM01', () {
      final order = _src('lib/services/order_service.dart');
      final egreso = _src('lib/screens/egreso_screen.dart');
      final comanda = _src('lib/services/comanda_service.dart');
      final cocina = _src('lib/services/cocina_offline_queue.dart');

      expect(
        RegExp("RpcM01\\.call\\(\\s*'fn_listar_ordenes'")
            .allMatches(order)
            .length,
        2,
      );
      expect(
        RegExp("RpcM01\\.call\\(\\s*'fn_registrar_cambio_estado_offline'")
            .hasMatch(order),
        isTrue,
      );
      expect(
        RegExp("RpcM01\\.call\\(\\s*'fn_registrar_egreso_offline_v2'")
            .hasMatch(egreso),
        isTrue,
      );
      expect(
        RegExp("RpcM01\\.call\\(\\s*'fn_registrar_egreso_offline'")
            .hasMatch(egreso),
        isTrue,
      );
      expect(
        RegExp("RpcM01\\.call\\(\\s*'fn_cambiar_estado_comanda_item_offline'")
            .hasMatch(comanda),
        isTrue,
      );
      expect(cocina, contains('RpcM01.call(rpc, params: rpcParams)'));
    });

    test('RpcM01 prueba <base>_m01 antes del nombre antiguo', () {
      final helper = _src('lib/services/rpc_m01.dart');
      final iM01 = helper.indexOf('rpc(m01, params: params)');
      final iBase = helper.indexOf('rpc(baseName, params: params)');
      expect(iM01, greaterThan(0));
      expect(iBase, greaterThan(iM01));
      expect(helper, contains('if (!isUnavailable(e, m01)) rethrow;'));
    });

    test('el helper del admin es idéntico al del TPV', () {
      expect(
        _src('../ventiq_admin_app/lib/services/rpc_m01.dart'),
        _src('lib/services/rpc_m01.dart'),
      );
    });

    test('admin recepción usa RpcM01 para precio promedio v2', () {
      final inv = _src('../ventiq_admin_app/lib/services/inventory_service.dart');
      expect(
        RegExp("RpcM01\\.call\\(\\s*'fn_actualizar_precio_promedio_recepcion_v2'")
            .hasMatch(inv),
        isTrue,
      );
    });
  });
}
