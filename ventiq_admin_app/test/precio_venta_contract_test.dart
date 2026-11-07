import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/services/product_service.dart';
import 'package:ventiq_admin_app/services/tpv_price_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var fail = false;
  var emptySave = false;
  double? tpvPrice;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Object body;
        var status = 200;
        if (path.endsWith('fn_guardar_precio_venta_base')) {
          status = fail ? 403 : 200;
          body = fail
              ? {'message': 'Sin permiso', 'code': '42501'}
              : emptySave
                  ? []
                  : [{'id': 30, 'id_producto': 2, 'precio_venta_cup': 4250}];
        } else if (path.endsWith('app_dat_precio_tpv')) {
          body = tpvPrice == null ? [] : [{'precio_venta_cup': tpvPrice}];
        } else if (path.endsWith('app_v_precio_venta_base_vigente')) {
          body = [{'id': 30, 'precio_venta_cup': 4250}];
        } else {
          body = {'message': 'Consulta fuera del contrato: $path'};
          status = 400;
        }
        return http.Response(jsonEncode(body), status,
            request: request, headers: {'content-type': 'application/json'});
      }),
    );
  });

  setUp(() {
    requests.clear();
    fail = false;
    emptySave = false;
    tpvPrice = null;
  });

  tearDownAll(() => Supabase.instance.dispose());

  test('guardar usa una sola RPC sin escribir versiones desde el cliente', () async {
    expect(await ProductService.updateBasePriceVenta(
      productId: 2, newPrice: 4250, newPriceUsd: 5,
    ), isTrue);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('fn_guardar_precio_venta_base'));
    expect(jsonDecode(requests.single.body), {
      'p_id_producto': 2, 'p_precio_venta_cup': 4250, 'p_precio_venta_usd': 5,
    });
  });

  test('no elude permisos con un fallback directo a la tabla', () async {
    fail = true;
    expect(await ProductService.updateBasePriceVenta(
      productId: 2, newPrice: 4250, newPriceUsd: 5,
    ), isFalse);
    expect(requests, hasLength(1));
  });

  test('no anuncia éxito si el servidor no devuelve el precio guardado', () async {
    emptySave = true;
    expect(await ProductService.updateBasePriceVenta(
      productId: 2, newPrice: 4250, newPriceUsd: 5,
    ), isFalse);
  });

  test('precio general del TPV viene de la fuente vigente común', () async {
    expect(await TpvPriceService.resolvePrice(2, 3), 4250);
    expect(requests.last.url.path, endsWith('app_v_precio_venta_base_vigente'));
    expect(requests.any((r) => r.url.path.endsWith('app_dat_precio_venta')), isFalse);
  });

  test('mantiene la prioridad del precio específico por TPV', () async {
    tpvPrice = 4000;
    expect(await TpvPriceService.resolvePrice(2, 3), 4000);
    expect(requests, hasLength(1));
    expect(requests.single.url.queryParameters['fecha_desde'], startsWith('lte.'));
  });
}
