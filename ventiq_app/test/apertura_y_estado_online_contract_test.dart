import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'rpc_m01_mock_helper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/services/order_service.dart';
import 'package:ventiq_app/services/turno_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var scenario = 'apertura_ok';
  const clave = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'user_id': '11111111-1111-4111-8111-111111111111',
    });
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final m01 = m01NoDesplegada(request);
        if (m01 != null) return m01;
        requests.add(request);
        final fn = request.url.path.split('/').last;
        if (scenario == 'apertura_denied' &&
            fn == 'fn_apertura_turno_offline_monedas') {
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
        if (scenario == 'apertura_missing' &&
            fn == 'fn_apertura_turno_offline_monedas') {
          return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.fn_apertura_turno_offline_monedas in the schema cache',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (fn == 'registrar_apertura_turno_monedas') {
          return http.Response(
            jsonEncode(44),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (scenario == 'estado_denied' &&
            fn == 'fn_registrar_cambio_estado_offline') {
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
        if (scenario == 'estado_missing' &&
            fn == 'fn_registrar_cambio_estado_offline') {
          return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message':
                  'Could not find the function public.fn_registrar_cambio_estado_offline in the schema cache',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (fn == 'fn_apertura_turno_offline_monedas') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'id_turno': 15,
              'idempotent': false,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode({'status': 'success'}),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  setUp(() {
    requests.clear();
    scenario = 'apertura_ok';
  });

  tearDownAll(() => Supabase.instance.dispose());

  Future<Map<String, dynamic>> abrir() => TurnoService.registrarAperturaTurno(
    efectivoInicialPorDivisa: const {'CUP': 1000, 'USD': 20},
    idTpv: 4,
    idVendedor: 8,
    usuario: '11111111-1111-4111-8111-111111111111',
    manejaInventario: false,
    clientUuid: clave,
  );

  List<String> rpcs() =>
      requests.map((r) => r.url.path.split('/').last).toList();

  test('la apertura online usa la RPC con clave', () async {
    final result = await abrir();
    expect(result['success'], isTrue);
    expect(result['operacion_id'], 15);
    expect(result['client_uuid'], clave);
    expect(rpcs(), ['fn_apertura_turno_offline_monedas']);
    final body = jsonDecode(requests.single.body);
    expect(body['p_client_uuid'], clave);
    expect(body['p_efectivo_inicial_por_moneda']['USD'], 20);
  });

  test('una denegacion de la apertura no abre la funcion sin clave', () async {
    scenario = 'apertura_denied';
    final result = await abrir();
    expect(result['success'], isFalse);
    expect(result['errorKind'], TurnoErrorKind.business);
    expect(result['client_uuid'], clave);
    expect(rpcs(), ['fn_apertura_turno_offline_monedas']);
  });

  test('si la RPC con clave no existe la apertura usa la de monedas', () async {
    scenario = 'apertura_missing';
    final result = await abrir();
    expect(result['success'], isTrue);
    expect(result['operacion_id'], 44);
    expect(rpcs(), [
      'fn_apertura_turno_offline_monedas',
      'registrar_apertura_turno_monedas',
    ]);
  });

  test('el estado online reutiliza la clave y no llama la funcion sin clave', () async {
    scenario = 'estado_ok';
    final primero = await OrderService().updateOrderStatusInSupabase(
      30,
      OrderStatus.completada,
    );
    final segundo = await OrderService().updateOrderStatusInSupabase(
      30,
      OrderStatus.completada,
    );
    expect(primero['success'], isTrue);
    expect(segundo['success'], isTrue);
    expect(primero['client_uuid'], segundo['client_uuid']);
    expect(rpcs(), [
      'fn_registrar_cambio_estado_offline',
      'fn_registrar_cambio_estado_offline',
    ]);
    expect(jsonDecode(requests.first.body)['p_client_uuid'], primero['client_uuid']);
    expect(jsonDecode(requests.last.body)['p_nuevo_estado'], 2);
  });

  test('una denegacion del estado no abre la funcion sin clave', () async {
    scenario = 'estado_denied';
    final result = await OrderService().updateOrderStatusInSupabase(
      31,
      OrderStatus.cancelada,
    );
    expect(result['success'], isFalse);
    expect(rpcs(), ['fn_registrar_cambio_estado_offline']);
  });

  test('si la RPC de estado con clave no existe se usa la anterior', () async {
    scenario = 'estado_missing';
    final result = await OrderService().updateOrderStatusInSupabase(
      32,
      OrderStatus.completada,
    );
    expect(result['success'], isTrue);
    expect(rpcs(), [
      'fn_registrar_cambio_estado_offline',
      'fn_registrar_cambio_estado_operacion',
    ]);
  });
}
