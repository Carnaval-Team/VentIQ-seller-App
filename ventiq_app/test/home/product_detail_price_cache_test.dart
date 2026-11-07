import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/services/product_detail_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var price = 4250.0;
  var requests = 0;
  Completer<void>? gate;
  Completer<void>? started;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests++;
        final capturedPrice = price;
        final currentGate = gate;
        gate = null;
        started?.complete();
        started = null;
        if (currentGate != null) await currentGate.future;
        return http.Response(jsonEncode({
          'producto': {
            'id': 2,
            'denominacion': 'Agua Pura',
            'precio_actual': capturedPrice,
            'categoria': {'id': 1, 'denominacion': 'Bebidas'},
            'presentaciones': [],
          },
          'inventario': [],
        }), 200, request: request, headers: {'content-type': 'application/json'});
      }),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'id_tienda': 4,
      'user_id': 'usuario-a',
      'offline_mode_enabled': false,
    });
    ProductDetailService().limpiarCacheDetalle();
    requests = 0;
    price = 4250;
    gate = null;
    started = null;
  });

  tearDownAll(() => Supabase.instance.dispose());

  test('invalidar el producto permite leer el precio recién guardado', () async {
    final service = ProductDetailService();
    expect((await service.getProductDetail(2)).precio, 4250);
    price = 5100;
    expect((await service.getProductDetail(2)).precio, 4250);
    expect(requests, 1);
    service.invalidarDetalle(2);
    expect((await service.getProductDetail(2)).precio, 5100);
    expect(requests, 2);
  });

  test('cambiar de tienda no reutiliza un detalle de otra tienda', () async {
    final service = ProductDetailService();
    await service.getProductDetail(2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('id_tienda', 5);
    price = 600;
    expect((await service.getProductDetail(2)).precio, 600);
    expect(requests, 2);
  });

  test('cambiar de usuario no reutiliza el precio de la sesión anterior', () async {
    final service = ProductDetailService();
    await service.getProductDetail(2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', 'usuario-b');
    price = 700;
    expect((await service.getProductDetail(2)).precio, 700);
    expect(requests, 2);
  });

  test('offline sin datos no presenta el detalle online como sincronizado', () async {
    final service = ProductDetailService();
    await service.getProductDetail(2);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offline_mode_enabled', true);
    await expectLater(service.getProductDetail(2), throwsException);
    expect(requests, 1);
  });

  test('una lectura en curso no repuebla la caché tras una sincronización', () async {
    final service = ProductDetailService();
    final waiting = Completer<void>();
    gate = waiting;
    final ready = Completer<void>();
    started = ready;
    final previous = service.getProductDetail(2);
    await ready.future;
    service.limpiarCacheDetalle();
    price = 800;
    waiting.complete();
    expect((await previous).precio, 4250);
    expect((await service.getProductDetail(2)).precio, 800);
    expect(requests, 2);
  });

  test('un precio cero no se sustituye por el precio anterior', () async {
    price = 0;
    expect((await ProductDetailService().getProductDetail(2)).precio, 0);
  });
}
