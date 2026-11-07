import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/models/fondo_inversion.dart';
import 'package:ventiq_admin_app/widgets/fdi_liquidacion_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var fallo = false;
  var ordenes = 2;
  var cuentas = true;
  var usd = false;
  Map<String, dynamic>? enviado;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'id_tienda': 4});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object body;
        if (path.endsWith('fn_fdi_ventas_por_medio_moneda')) {
          if (fallo) {
            return http.Response(
              jsonEncode({'message': 'Sin conexión'}),
              500,
              request: request,
            );
          }
          body = {
            'ordenes_elegibles': ordenes,
            'ordenes_excluidas': 1,
            'venta_total_cup': 200,
            'costo_total_cup': 100,
            'ganancia_cup': 100,
            'medios': [
              {
                'id_medio_pago': 1,
                'medio_pago': 'Efectivo',
                'moneda': 'CUP',
                'monto_vendido': 200,
                'monto_vendido_cup': 200,
              },
              if (usd)
                {
                  'id_medio_pago': 4,
                  'medio_pago': 'Transferencia',
                  'moneda': 'USD',
                  'monto_vendido': 2,
                  'monto_vendido_cup': 200,
                },
            ],
          };
        } else if (path.endsWith('fdi_dat_concepto')) {
          body = [
            {'id': 1, 'id_tienda': 4, 'denominacion': 'Fondo', 'activo': true},
          ];
        } else if (path.endsWith('fdi_dat_cuenta')) {
          body = cuentas
              ? [
                  {
                    'id': 1,
                    'id_concepto': 1,
                    'id_tienda': 4,
                    'nombre': 'Principal',
                    'activo': true,
                  },
                ]
              : [];
        } else if (path.endsWith('fdi_dat_inversor')) {
          body = [
            for (var i = 1; i <= 3; i++)
              {
                'id': i,
                'nombre': 'Inversor $i',
                'porcentaje': 30,
                'activo': true,
              },
          ];
        } else if (path.endsWith('fn_fdi_crear_liquidacion')) {
          enviado = jsonDecode(request.body) as Map<String, dynamic>;
          body = {'status': 'ok'};
        } else {
          throw StateError('Petición no esperada: $path');
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  setUp(() {
    fallo = false;
    ordenes = 2;
    cuentas = true;
    usd = false;
    enviado = null;
  });

  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => FdiLiquidacionDialog(
                  desde: DateTime(2026, 11, 1),
                  hasta: DateTime(2026, 11, 7),
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> desplazar(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('jerarquiza el resumen y conserva el envío del reparto entero', (
    tester,
  ) async {
    await abrir(tester);
    expect(find.text('Ganancia del período'), findsOneWidget);
    expect(find.text('100.00 CUP'), findsOneWidget);
    expect(find.text('Venta'), findsNothing);
    await tester.tap(find.text('Resumen de ventas'));
    await tester.pumpAndSettle();
    expect(find.text('Venta'), findsOneWidget);
    expect(find.text('Costo'), findsOneWidget);
    await tester.tap(find.text('Resumen de ventas'));
    await tester.pumpAndSettle();
    await desplazar(tester, find.byType(DropdownButtonFormField<FdiCuenta>));
    await tester.tap(find.byType(DropdownButton<FdiCuenta>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fondo · Principal').last);
    await tester.pumpAndSettle();
    await desplazar(tester, find.text('Repartir a partes iguales'));
    await tester.tap(find.text('Repartir a partes iguales'));
    await tester.pumpAndSettle();
    await desplazar(tester, find.text('Para inversores'));
    expect(find.text('33 CUP'), findsNWidgets(3));
    expect(find.text('99 CUP'), findsOneWidget);
    expect(find.text('101.00 CUP'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(enviado?['p_repartir_igual'], true);
    expect(enviado?['p_id_cuenta_destino'], 1);
    expect(enviado?['p_detalle'], [
      {'id_medio_pago': 1, 'moneda': 'CUP', 'monto_ganancia_retirada': 100.0},
    ]);
    expect(find.text('Crear liquidación'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('se adapta a móvil y mantiene visible la tasa necesaria', (
    tester,
  ) async {
    usd = true;
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await abrir(tester);
    await desplazar(tester, find.text('Transferencia · USD'));
    await tester.tap(find.text('Transferencia · USD'));
    await tester.pumpAndSettle();
    await desplazar(tester, find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), '100');
    await tester.pumpAndSettle();
    expect(find.text('Tasa a CUP'), findsOneWidget);
    await desplazar(tester, find.text('Validación del importe'));
    await tester.tap(find.text('Validación del importe'));
    await tester.pumpAndSettle();
    expect(find.text('Equivalente seleccionado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('permite reintentar la carga y explica la falta de cuenta', (
    tester,
  ) async {
    fallo = true;
    await abrir(tester);
    expect(
      find.text('No se pudieron cargar los datos de la liquidación.'),
      findsOneWidget,
    );
    fallo = false;
    cuentas = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    await desplazar(
      tester,
      find.text(
        'Crea una cuenta activa en Fondo de Inversión → Config para continuar.',
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('informa cuando no quedan órdenes por liquidar', (tester) async {
    ordenes = 0;
    await abrir(tester);
    expect(
      find.text('No hay ventas pendientes de liquidar en este período.'),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<FdiCuenta>), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
