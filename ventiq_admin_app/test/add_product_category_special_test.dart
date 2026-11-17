import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/services/product_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'id_tienda': 9});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final body = request.url.path.endsWith('app_dat_categoria')
            ? {'id': 101}
            : [];
        return http.Response(
          jsonEncode(body),
          201,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(requests.clear);
  tearDownAll(() => Supabase.instance.dispose());

  for (final especial in [false, true]) {
    test(
      'guarda especial=$especial solo en la relación con la tienda',
      () async {
        final result = await ProductService.createCategoria(
          denominacion: 'Categoría de prueba',
          descripcion: 'Prueba',
          especial: especial,
        );
        expect(result['id'], 101);
        final category = requests.singleWhere(
          (r) => r.url.path.endsWith('app_dat_categoria'),
        );
        expect(jsonDecode(category.body), isNot(contains('especial')));
        final relation = requests.singleWhere(
          (r) => r.url.path.endsWith('app_dat_categoria_tienda'),
        );
        expect(jsonDecode(relation.body), {
          'id_categoria': 101,
          'id_tienda': 9,
          'especial': especial,
        });
      },
    );
  }

  test('sin opción explícita la categoría no es especial', () async {
    await ProductService.createCategoria(
      denominacion: 'Normal',
      descripcion: 'Prueba',
    );
    final relation = requests.singleWhere(
      (r) => r.url.path.endsWith('app_dat_categoria_tienda'),
    );
    expect(jsonDecode(relation.body)['especial'], isFalse);
  });

  test(
    'el diálogo combinado pregunta y envía la opción de categoría especial',
    () {
      final source = File(
        'lib/screens/add_product_screen.dart',
      ).readAsStringSync();
      final dialog = source.substring(
        source.indexOf('  void _showCreateCategoryDialog()'),
        source.indexOf('  void _showCreateSubcategoryDialog()'),
      );
      expect(dialog, contains("Text('Categoría especial')"));
      expect(dialog, contains('SwitchListTile('));
      expect(dialog, contains('especial: categoriaEspecial'));
      final subcategory = source.substring(
        source.indexOf('  void _showCreateSubcategoryDialog()'),
      );
      expect(subcategory, isNot(contains('especial: categoriaEspecial')));
    },
  );
}
