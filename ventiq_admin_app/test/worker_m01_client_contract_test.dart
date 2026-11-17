import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/services/worker_service.dart';

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
        final missing = scenario == 'missing' && fn.startsWith('fn_m01_');
        if (missing) {
          return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message': 'Could not find the function public.$fn',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (scenario == 'denied' && fn.startsWith('fn_m01_')) {
          return http.Response(
            jsonEncode({'code': '42501', 'message': 'acceso denegado'}),
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (request.method == 'PATCH') {
          return http.Response(
            jsonEncode([
              {'id': 4},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (fn == 'fn_m01_personal_vincular_usuario_trabajador') {
          return http.Response(
            'true',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode({'success': true}),
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

  test('la edicion nueva no manda uuid y vincula aparte', () async {
    expect(
      await WorkerService.editWorker(
        workerId: 4,
        storeId: 2,
        nombres: 'Ana',
        apellidos: 'Paz',
        usuarioUuid: '00000000-0000-4000-8000-000000000004',
      ),
      isTrue,
    );
    expect(requests.map((r) => r.url.path.split('/').last), [
      'fn_m01_editar_trabajador_basico',
      'fn_m01_personal_vincular_usuario_trabajador',
    ]);
    expect(jsonDecode(requests.first.body)['p_uuid'], isNull);
    expect(jsonDecode(requests.last.body), {
      'p_id_trabajador': 4,
      'p_uuid': '00000000-0000-4000-8000-000000000004',
    });
  });

  test('sin la RPC nueva la edicion conserva el uuid en la funcion anterior', () async {
    scenario = 'missing';
    expect(
      await WorkerService.editWorker(
        workerId: 4,
        storeId: 2,
        nombres: 'Ana',
        apellidos: 'Paz',
        usuarioUuid: '00000000-0000-4000-8000-000000000004',
      ),
      isTrue,
    );
    expect(requests.map((r) => r.url.path.split('/').last), [
      'fn_m01_editar_trabajador_basico',
      'fn_editar_trabajador_basico',
    ]);
    expect(
      jsonDecode(requests.last.body)['p_uuid'],
      '00000000-0000-4000-8000-000000000004',
    );
  });

  test('una denegacion de edicion no usa la funcion anterior', () async {
    scenario = 'denied';
    await expectLater(
      WorkerService.editWorker(
        workerId: 4,
        storeId: 2,
        nombres: 'Ana',
        apellidos: 'Paz',
      ),
      throwsA(anything),
    );
    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      endsWith('/fn_m01_editar_trabajador_basico'),
    );
  });

  test('vincular sin RPC cae al UPDATE y una denegacion no', () async {
    scenario = 'missing';
    expect(
      await WorkerService.updateWorkerUUID(
        workerId: 4,
        storeId: 2,
        uuid: '00000000-0000-4000-8000-000000000004',
      ),
      isTrue,
    );
    expect(requests.last.method, 'PATCH');
    expect(jsonDecode(requests.last.body), {
      'uuid': '00000000-0000-4000-8000-000000000004',
    });

    requests.clear();
    scenario = 'denied';
    await expectLater(
      WorkerService.updateWorkerUUID(
        workerId: 4,
        storeId: 2,
        uuid: '00000000-0000-4000-8000-000000000004',
      ),
      throwsA(anything),
    );
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
  });
}
