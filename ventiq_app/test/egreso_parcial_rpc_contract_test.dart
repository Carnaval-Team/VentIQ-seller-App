import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/turno_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var scenario = 'missing';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final fn = request.url.path.split('/').last;
        if (scenario == 'denied' && fn == 'registrar_egreso_parcial_v3') {
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
        if (fn == 'registrar_egreso_parcial_v3') {
          return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.registrar_egreso_parcial_v3() in the schema cache',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'egreso_id': 3}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  setUp(() {
    requests.clear();
    scenario = 'missing';
  });

  tearDownAll(() => Supabase.instance.dispose());

  Future<Map<String, dynamic>> save() => TurnoService.registrarEgresoParcial(
    idTurno: 8,
    montoEntrega: 10,
    motivoEntrega: 'caja',
    nombreAutoriza: 'Ana',
    nombreRecibe: 'Luis',
    moneda: 'USD',
  );

  test('una denegacion con schema cache no usa la variante sin divisa', () async {
    scenario = 'denied';
    final result = await save();
    expect(result['success'], isFalse);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/registrar_egreso_parcial_v3'));
  });

  test('si la variante con divisa no existe se usa la anterior', () async {
    final result = await save();
    expect(result['success'], isTrue);
    expect(
      requests.map((r) => r.url.path.split('/').last),
      ['registrar_egreso_parcial_v3', 'registrar_egreso_parcial_v2'],
    );
    expect(jsonDecode(requests.last.body).containsKey('p_moneda'), isFalse);
  });
}
