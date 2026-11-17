import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/product_detail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var sinIngredientes = false;
  var fallo = false;
  var stock = 3.0;
  final receta = [
    {
      'id_ingrediente': 2,
      'cantidad_necesaria': 2,
      'app_dat_producto': {'id': 2, 'denominacion': 'Material'},
    },
  ];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        Object body;
        var status = 200;
        final path = request.url.path;
        if (path.endsWith('app_dat_producto_ingredientes')) {
          status = fallo ? 503 : 200;
          body =
              fallo
                  ? {'message': 'No disponible'}
                  : sinIngredientes
                  ? []
                  : receta;
        } else if (path.endsWith('app_dat_producto_presentacion')) {
          body = [
            {
              'id': 22,
              'id_producto': 2,
              'cantidad': 1,
              'es_base': true,
              'presentacion': {'id': 1, 'denominacion': 'Unidad'},
            },
          ];
        } else if (path.endsWith('fn_stock_producto_almacen_detalle')) {
          final params = jsonDecode(request.body) as Map;
          body = [
            {
              'id_presentacion': 22,
              'cantidad_final': params['p_id_almacen'] == 10 ? stock : 999,
            },
          ];
        } else {
          status = 400;
          body = {'message': 'Consulta inesperada: $path'};
        }
        return http.Response(
          jsonEncode(body),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    requests.clear();
    sinIngredientes = false;
    fallo = false;
    stock = 3;
  });
  tearDownAll(() => Supabase.instance.dispose());

  test('mide ingredientes solo en el almacén del vendedor', () async {
    final ingredientes = await ProductDetailService().getProductIngredients(
      7,
      idAlmacen: 10,
      exigirAlmacen: true,
    );
    expect(ingredientes.single['cantidad_disponible'], 3);
    expect(ingredientes.single['id_almacen'], 10);
    final rpc = requests.singleWhere(
      (r) => r.url.path.endsWith('fn_stock_producto_almacen_detalle'),
    );
    expect(jsonDecode(rpc.body)['p_id_almacen'], 10);
  });

  test('stock cero local no usa existencias de otros almacenes', () async {
    stock = 0;
    final ingredientes = await ProductDetailService().getProductIngredients(
      7,
      idAlmacen: 10,
      exigirAlmacen: true,
    );
    expect(ingredientes.single['cantidad_disponible'], 0);
  });

  test('servicio sin ingredientes devuelve receta vacía', () async {
    sinIngredientes = true;
    expect(
      await ProductDetailService().getProductIngredients(
        7,
        idAlmacen: 10,
        exigirAlmacen: true,
      ),
      isEmpty,
    );
  });

  test(
    'error de receta no se interpreta como servicio sin ingredientes',
    () async {
      fallo = true;
      await expectLater(
        ProductDetailService().getProductIngredients(
          7,
          idAlmacen: 10,
          exigirAlmacen: true,
        ),
        throwsA(isA<PostgrestException>()),
      );
    },
  );

  test('sin almacén no consulta stock global', () async {
    await expectLater(
      ProductDetailService().getProductIngredients(7, exigirAlmacen: true),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });

  test('offline con cache vacío bloquea sin consultar red', () async {
    SharedPreferences.setMockInitialValues({'offline_mode_enabled': true});
    await expectLater(
      ProductDetailService().getProductIngredients(
        7,
        idAlmacen: 10,
        exigirAlmacen: true,
      ),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });
}
