import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'rpc_m01_mock_helper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/turno_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var scenario = 'ok';
  const clave = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'user_id': '11111111-1111-4111-8111-111111111111',
      'id_tpv': 4,
    });
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final m01 = m01NoDesplegada(request);
        if (m01 != null) return m01;
        requests.add(request);
        final path = request.url.path;
        if (!path.contains('/rpc/')) {
          return http.Response(
            jsonEncode({
              'creado_por': '11111111-1111-4111-8111-111111111111',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        final fn = path.split('/').last;
        if (scenario == 'network' && fn == 'fn_cerrar_turno_offline_monedas') {
          throw http.ClientException('SocketException: connection failed');
        }
        if (scenario == 'denied' && fn == 'fn_cerrar_turno_offline_monedas') {
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
        if (scenario == 'missing' && fn == 'fn_cerrar_turno_offline_monedas') {
          return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.fn_cerrar_turno_offline_monedas in the schema cache',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (fn == 'fn_cerrar_turno_tpv_monedas') {
          return http.Response(
            jsonEncode(true),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode({'status': 'success', 'idempotent': false}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  setUp(() => requests.clear());

  tearDownAll(() => Supabase.instance.dispose());

  Future<TurnoOperationResult> cerrar() => TurnoService.cerrarTurnoDetailed(
    efectivoRealPorDivisa: const {'CUP': 100, 'USD': 5},
    productos: const [],
    clientUuid: clave,
  );

  List<String> rpcs() => requests
      .map((r) => r.url.path)
      .where((p) => p.contains('/rpc/'))
      .map((p) => p.split('/').last)
      .toList();

  test('el cierre online usa la RPC con clave', () async {
    scenario = 'ok';
    final result = await cerrar();
    expect(result.success, isTrue);
    expect(result.clientUuid, clave);
    expect(rpcs(), ['fn_cerrar_turno_offline_monedas']);
    final body = jsonDecode(
      requests.lastWhere((r) => r.url.path.contains('/rpc/')).body,
    );
    expect(body['p_client_uuid'], clave);
    expect(body['p_efectivo_real_por_moneda']['USD'], 5);
  });

  test('una denegacion no abre el cierre sin clave', () async {
    scenario = 'denied';
    final result = await cerrar();
    expect(result.success, isFalse);
    expect(result.isNetworkError, isFalse);
    expect(rpcs(), ['fn_cerrar_turno_offline_monedas']);
  });

  test('si la RPC con clave no existe se usa la de monedas sin clave', () async {
    scenario = 'missing';
    final result = await cerrar();
    expect(result.success, isTrue);
    expect(rpcs(), [
      'fn_cerrar_turno_offline_monedas',
      'fn_cerrar_turno_tpv_monedas',
    ]);
  });

  test('un corte de red devuelve la misma clave', () async {
    scenario = 'network';
    final result = await cerrar();
    expect(result.isNetworkError, isTrue);
    expect(result.clientUuid, clave);
    expect(rpcs(), ['fn_cerrar_turno_offline_monedas']);
  });
}
