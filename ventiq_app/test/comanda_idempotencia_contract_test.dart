import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'rpc_m01_mock_helper.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/comanda_service.dart';
import 'package:ventiq_app/services/mesa_cuenta_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var scenario = 'estado_denied';

  Map<String, dynamic> pedidoOk() => {
    'status': 'success',
    'id_item': 4,
    'id_cuenta': 9,
    'origen': 'barra',
    'stock_movido': true,
    'message': 'Agregado',
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final m01 = m01NoDesplegada(request);
        if (m01 != null) return m01;
        requests.add(request);
        final fn = request.url.path.split('/').last;
        if (scenario == 'estado_network' &&
            fn == 'fn_cambiar_estado_comanda_item_offline') {
          throw http.ClientException('SocketException: connection failed');
        }
        if (scenario == 'estado_denied' &&
            fn == 'fn_cambiar_estado_comanda_item_offline') {
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
        if (scenario == 'pedir_denied' && fn == 'fn_pedir_item_cuenta_v2') {
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
        if ((scenario == 'estado_missing' &&
                fn == 'fn_cambiar_estado_comanda_item_offline') ||
            (scenario == 'pedir_missing' && fn == 'fn_pedir_item_cuenta_v2')) {
          return http.Response(
            jsonEncode({
              'code': 'PGRST202',
              'message': 'Could not find the function public.$fn in the schema cache',
            }),
            404,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (scenario == 'ticket' &&
            fn == 'fn_cambiar_estado_comanda_item_offline') {
          final id = jsonDecode(request.body)['p_id_item'];
          if (id == 2) {
            return http.Response(
              jsonEncode({
                'status': 'error',
                'error_code': 'TRANSICION_INVALIDA',
                'message': 'El plato ya fue entregado',
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
        }
        if (fn == 'fn_cambiar_estado_comanda_item' ||
            fn == 'fn_cambiar_estado_comanda_item_offline') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'message': 'Estado actualizado',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode(pedidoOk()),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  setUp(() async {
    requests.clear();
    scenario = 'estado_denied';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cocina_offline_queue_v1');
  });

  tearDownAll(() => Supabase.instance.dispose());

  test('una denegacion del estado con clave no usa la funcion sin clave', () async {
    scenario = 'estado_denied';
    await expectLater(
      ComandaService().cambiarEstadoItem(idItem: 7, nuevoEstado: 2),
      throwsA(anything),
    );
    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      endsWith('/fn_cambiar_estado_comanda_item_offline'),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cocina_offline_queue_v1'), isNull);
  });

  test('si la RPC con clave no existe el estado no usa la funcion anterior', () async {
    scenario = 'estado_missing';
    await expectLater(
      ComandaService().cambiarEstadoItem(idItem: 7, nuevoEstado: 2),
      throwsA(anything),
    );
    expect(requests, hasLength(1));
    expect(
      requests.single.url.path,
      endsWith('/fn_cambiar_estado_comanda_item_offline'),
    );
  });

  test('un corte de red conserva la misma clave en la cola de cocina', () async {
    scenario = 'estado_network';
    final msg = await ComandaService().cambiarEstadoItem(
      idItem: 7,
      nuevoEstado: 3,
    );
    expect(msg, contains('Sin conexión'));
    expect(requests, hasLength(1));
    final sent = jsonDecode(requests.single.body)['p_client_uuid'];
    final prefs = await SharedPreferences.getInstance();
    final cola = jsonDecode(prefs.getString('cocina_offline_queue_v1')!) as List;
    expect(cola, hasLength(1));
    expect(cola.single['client_uuid'], sent);
    expect(cola.single['params']['p_client_uuid'], sent);
    expect(cola.single['params']['p_nuevo_estado'], 3);
  });

  test('el ticket completo marca cada plato con clave y salta el entregado', () async {
    scenario = 'ticket';
    final msg = await ComandaService().cambiarEstadoComanda(
      idComanda: 4,
      nuevoEstado: 3,
      idsItems: const [1, 2],
    );
    expect(msg, 'Comanda actualizada (1 sin cambiar)');
    expect(
      requests.map((r) => r.url.path.split('/').last),
      [
        'fn_cambiar_estado_comanda_item_offline',
        'fn_cambiar_estado_comanda_item_offline',
      ],
    );
    final uuids = requests
        .map((r) => jsonDecode(r.body)['p_client_uuid'] as String)
        .toList();
    requests.clear();
    await ComandaService().cambiarEstadoComanda(
      idComanda: 4,
      nuevoEstado: 3,
      idsItems: const [1, 2],
    );
    final repetidos = requests
        .map((r) => jsonDecode(r.body)['p_client_uuid'] as String)
        .toList();
    expect(repetidos, uuids);
  });

  test('el pedido con v2 no llama la RPC que usa la version anterior', () async {
    scenario = 'pedir_ok';
    final res = await MesaCuentaService().pedirItem(
      idCuenta: 9,
      idProducto: 3,
      cantidad: 1,
      precioUnitario: 10,
    );
    expect(res.idItem, 4);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/fn_pedir_item_cuenta_v2'));
  });

  test('si v2 no existe el pedido no usa la funcion anterior', () async {
    scenario = 'pedir_missing';
    await expectLater(
      MesaCuentaService().pedirItem(
        idCuenta: 9,
        idProducto: 3,
        cantidad: 1,
        precioUnitario: 10,
      ),
      throwsA(anything),
    );
    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/fn_pedir_item_cuenta_v2'));
  });

  test('una denegacion de v2 no abre la RPC anterior', () async {
    scenario = 'pedir_denied';
    await expectLater(
      MesaCuentaService().pedirItem(
        idCuenta: 9,
        idProducto: 3,
        cantidad: 1,
        precioUnitario: 10,
      ),
      throwsA(anything),
    );
    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/fn_pedir_item_cuenta_v2'));
  });
}
