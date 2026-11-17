import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/services/vendedor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var scenario = 'ok';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final fn = request.url.path.split('/').last;
        if (scenario == 'missing' && fn == 'fn_m01_personal_reasignar_vendedor') {
          return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.fn_m01_personal_reasignar_vendedor',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (scenario == 'denied') {
          return http.Response(
            jsonEncode({'code': '42501', 'message': 'Sin permiso'}),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode([
              {'id': 7},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode(scenario != 'false'),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  setUp(() {
    requests.clear();
    scenario = 'ok';
  });

  tearDownAll(() => Supabase.instance.dispose());

  for (final assign in [true, false]) {
    Future<bool> save() => assign
        ? VendedorService.asignarVendedorATpv(vendedorId: 7, tpvId: 9)
        : VendedorService.desasignarVendedorDeTpv(7);

    test('asignacion=$assign usa la RPC y no el UPDATE', () async {
      expect(await save(), isTrue);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(
        requests.single.url.path,
        endsWith('/fn_m01_personal_reasignar_vendedor'),
      );
      expect(jsonDecode(requests.single.body), {
        'p_id_vendedor': 7,
        'p_id_tpv': assign ? 9 : null,
      });
    });

    test('asignacion=$assign denegada no cae al UPDATE', () async {
      scenario = 'denied';
      expect(await save(), isFalse);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
    });

    test('asignacion=$assign sin la RPC conserva el UPDATE de id_tpv', () async {
      scenario = 'missing';
      expect(await save(), isTrue);
      expect(requests, hasLength(2));
      expect(requests.last.method, 'PATCH');
      expect(requests.last.url.path, endsWith('/app_dat_vendedor'));
      expect(requests.last.url.queryParameters['id'], 'eq.7');
      expect(jsonDecode(requests.last.body), {'id_tpv': assign ? 9 : null});
    });
  }

  test('una respuesta false de la RPC no abre el UPDATE', () async {
    scenario = 'false';
    expect(
      await VendedorService.asignarVendedorATpv(vendedorId: 7, tpvId: 9),
      isFalse,
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
  });
}
