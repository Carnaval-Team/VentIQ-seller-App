import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/services/inventory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var denied = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (denied) {
          return http.Response(
            jsonEncode({'message': 'Saldo insuficiente', 'code': 'P0002'}),
            400,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'status': 'success'}),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() {
    requests.clear();
    denied = false;
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<Map<String, dynamic>> guardar({bool financiar = true}) =>
      InventoryService.insertInventoryReception(
        entregadoPor: 'Prueba',
        idTienda: 9,
        montoTotal: 50,
        motivo: 1,
        observaciones: '',
        productos: [],
        recibidoPor: 'Prueba',
        uuid: '00000000-0000-4000-8000-000000000001',
        monedaFactura: 'USD',
        fuentesFondo: financiar
            ? [
                {
                  'id_cuenta': 1,
                  'id_medio_pago': 1,
                  'moneda': 'USD',
                  'monto': '30.00',
                  'tasa_a_ref': '1',
                },
                {
                  'id_cuenta': 2,
                  'id_medio_pago': 1,
                  'moneda': 'CUP',
                  'monto': '8000.00',
                  'tasa_a_ref': '0.0025',
                },
              ]
            : null,
        idempotencyKey: financiar
            ? '00000000-0000-4000-8000-000000000002'
            : null,
      );
  test('financiación usa una RPC y conserva la clave al reintentar', () async {
    await guardar();
    await guardar();
    expect(requests, hasLength(2));
    expect(
      requests.every((r) => r.url.path.endsWith('fn_fdi_registrar_recepcion')),
      isTrue,
    );
    final payload = jsonDecode(requests.first.body);
    expect(payload['p_fuentes'], hasLength(2));
    expect(payload['p_recepcion']['p_monto_total'], '50.00');
    expect(requests.first.body, requests.last.body);
  });
  test('sin financiación conserva la RPC de recepción existente', () async {
    await guardar(financiar: false);
    expect(
      requests.single.url.path,
      endsWith('fn_registrar_recepcion_con_inventario'),
    );
  });
  test('un rechazo de saldo no registra recepción por otra vía', () async {
    denied = true;
    await expectLater(guardar(), throwsException);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('fn_fdi_registrar_recepcion'));
  });
  test('contrato SQL: acceso, bloqueo, idempotencia y fallo transaccional', () {
    final sql = File(
      'lib/sql/fondo_inversion_financiar_recepcion.sql',
    ).readAsStringSync();
    expect(sql, contains('fn_user_is_gerente_or_superadmin'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('FOR UPDATE OF s'));
    expect(sql, contains('fdi_solicitud IS DISTINCT FROM v_solicitud'));
    expect(sql, contains('fn_fdi_crear_inversion'));
    expect(sql, contains('fn_fdi_vincular_recepcion'));
    expect(sql, contains("IF v_result->>'status' IS DISTINCT FROM 'success'"));
    expect(sql, isNot(contains('WHEN OTHERS')));
    expect(sql, isNot(contains('TO anon')));
  });
}
