import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/services/product_search_service.dart';
import 'package:ventiq_admin_app/services/product_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var sinZona = false;
  var sinAlmacenes = false;
  var sinPermiso = false;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'id_tienda': 9});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Object body;
        var status = 200;
        if (path.endsWith('app_dat_almacen')) {
          body = sinAlmacenes
              ? []
              : [
                  {'id': 10, 'denominacion': 'Principal'},
                  {'id': 20, 'denominacion': 'Sucursal'},
                ];
        } else if (path.endsWith('app_dat_producto_presentacion')) {
          body = {'id': 100};
        } else if (path.endsWith('app_dat_layout_almacen')) {
          body = [
            {'id': 11, 'id_almacen': 10},
            {'id': 12, 'id_almacen': 10},
            if (!sinZona) {'id': 21, 'id_almacen': 20},
          ];
        } else if (path.endsWith('app_dat_producto_ingredientes')) {
          status = sinPermiso ? 403 : 201;
          body = sinPermiso ? {'message': 'Sin permiso', 'code': '42501'} : [];
        } else if (path.endsWith('app_dat_inventario_productos')) {
          status = sinPermiso ? 403 : 201;
          body = sinPermiso ? {'message': 'Sin permiso', 'code': '42501'} : [];
        } else if (path.endsWith(
          'get_productos_completos_by_tienda_optimized_provider',
        )) {
          body = {
            'productos': [
              {'id': 1, 'denominacion': 'Producto A', 'es_servicio': true},
              {'id': 2, 'denominacion': 'Producto B', 'es_servicio': false},
              {'id': 3, 'denominacion': 'Producto C', 'es_servicio': null},
              {'id': 4, 'denominacion': 'Producto D', 'es_servicio': true},
              {'id': 5, 'denominacion': 'Producto E', 'es_servicio': false},
            ],
          };
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
    requests.clear();
    sinZona = false;
    sinAlmacenes = false;
    sinPermiso = false;
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> crear({bool esServicio = true, bool esElaborado = false}) =>
      ProductService.crearInventarioInicialProducto(
        productId: 7,
        idTienda: 9,
        sku: 'RECETA-7',
        esServicio: esServicio,
        esElaborado: esElaborado,
      );

  test('el elaborado se habilita sin consultar stock de ingredientes', () async {
    await crear(esServicio: false, esElaborado: true);
    final insert = requests.singleWhere((r) => r.method == 'POST');
    final filas = jsonDecode(insert.body) as List;
    expect(filas.map((f) => f['id_ubicacion']), [11, 21]);
    expect(filas.every((f) => f['cantidad_final'] == 1), isTrue);
    expect(requests.any((r) => r.url.path.contains('ingrediente')), isFalse);
  });

  test('producto físico no recibe inventario artificial al crearse', () async {
    await crear(esServicio: false);
    expect(requests, isEmpty);
  });

  test('servicio elaborado no duplica el registro por almacén', () async {
    await crear(esElaborado: true);
    final insert = requests.singleWhere((r) => r.method == 'POST');
    expect(jsonDecode(insert.body), hasLength(2));
  });

  test(
    'inserta cantidad 1 por almacén en su presentación base, no por zona',
    () async {
      await crear();
      final insert = requests.singleWhere((r) => r.method == 'POST');
      final filas = jsonDecode(insert.body) as List;
      expect(filas, hasLength(2));
      expect(filas.map((f) => f['id_ubicacion']), [11, 21]);
      for (final fila in filas) {
        expect(fila['id_producto'], 7);
        expect(fila['id_presentacion'], 100);
        expect(fila['cantidad_final'], 1);
      }
      final consulta = requests.firstWhere(
        (r) => r.url.path.endsWith('app_dat_almacen'),
      );
      expect(consulta.url.queryParameters['id_tienda'], 'eq.9');
    },
  );

  test('no inserta parcialmente si un almacén no tiene zona', () async {
    sinZona = true;
    await expectLater(crear(), throwsStateError);
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
  });

  test('reporta tienda sin almacenes', () async {
    sinAlmacenes = true;
    await expectLater(crear(), throwsStateError);
  });

  test('propaga permisos sin intentar escrituras alternativas', () async {
    sinPermiso = true;
    await expectLater(crear(), throwsA(isA<PostgrestException>()));
    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  for (final texto in <String?>[null, 'Producto']) {
    test(
      'recepción filtra servicios antes de paginar (búsqueda=$texto)',
      () async {
        final primera = await ProductSearchService.searchProducts(
          searchType: ProductSearchType.reception,
          searchQuery: texto,
          pageSize: 2,
        );
        final segunda = await ProductSearchService.searchProducts(
          searchType: ProductSearchType.reception,
          searchQuery: texto,
          pageSize: 2,
          page: 2,
        );
        expect(primera.products.map((p) => p['id']), [2, 3]);
        expect(primera.totalCount, 3);
        expect(primera.hasNextPage, isTrue);
        expect(segunda.products.map((p) => p['id']), [5]);
        expect(segunda.hasNextPage, isFalse);
      },
    );
  }

  test('guarda la receta del servicio en una sola escritura', () async {
    final ok = await ProductService.insertProductIngredients(
      productId: 7,
      esServicio: true,
      ingredientes: [
        {'id_producto': 2, 'cantidad': 1, 'unidad_medida': 'und'},
        {'id_producto': 3, 'cantidad': 2, 'unidad_medida': 'und'},
      ],
    );
    expect(ok, isTrue);
    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body), hasLength(2));
  });

  test('la receta del elaborado se guarda completa antes de habilitarlo', () async {
    final ok = await ProductService.insertProductIngredients(
      productId: 7,
      esServicio: false,
      guardarAtomico: true,
      ingredientes: [
        {'id_producto': 2, 'cantidad': 1},
        {'id_producto': 3, 'cantidad': 2},
      ],
    );
    expect(ok, isTrue);
    expect(requests, hasLength(1));
    expect(jsonDecode(requests.single.body), hasLength(2));
  });

  test('receta rechazada del elaborado impide reportar éxito', () async {
    sinPermiso = true;
    final ok = await ProductService.insertProductIngredients(
      productId: 7,
      esServicio: false,
      guardarAtomico: true,
      ingredientes: [{'id_producto': 2, 'cantidad': 1}],
    );
    expect(ok, isFalse);
    expect(requests, hasLength(1));
  });

  test('receta rechazada no se reporta como guardada parcialmente', () async {
    sinPermiso = true;
    final ok = await ProductService.insertProductIngredients(
      productId: 7,
      esServicio: true,
      ingredientes: [
        {'id_producto': 2, 'cantidad': 1},
      ],
    );
    expect(ok, isFalse);
    expect(requests, hasLength(1));
  });

  test('búsqueda general conserva servicios', () async {
    final resultado = await ProductSearchService.searchProducts();
    expect(resultado.totalCount, 5);
  });
}
