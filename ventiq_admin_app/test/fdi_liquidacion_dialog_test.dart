import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/models/fondo_inversion.dart';
import 'package:ventiq_admin_app/services/sales_service.dart';
import 'package:ventiq_admin_app/widgets/fdi_liquidacion_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var fallo = false;
  var ordenes = 2;
  var cuentas = true;
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
    enviado = null;
  });

  Future<void> abrir(
    WidgetTester tester, {
    List<TotalesPorMonedaProducto> totales = const [],
  }) async {
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
                  totalesPorMoneda: totales,
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

  const totalesCup = [
    TotalesPorMonedaProducto(
      moneda: 'CUP',
      ingresos: 200,
      costo: 100,
      ganancia: 100,
      cantidadBase: 2,
      utilidadCompleta: true,
    ),
  ];

  testWidgets('montos en columna y secciones de destino por moneda', (
    tester,
  ) async {
    await abrir(
      tester,
      totales: const [
        TotalesPorMonedaProducto(
          moneda: 'CUP',
          ingresos: 1500,
          costo: 900,
          ganancia: 600,
          cantidadBase: 10,
          utilidadCompleta: true,
        ),
        TotalesPorMonedaProducto(
          moneda: 'USD',
          ingresos: 25,
          costo: 11,
          ganancia: 14,
          cantidadBase: 10,
          utilidadCompleta: true,
        ),
      ],
    );
    expect(find.text('Venta'), findsWidgets);
    expect(find.text('Inversión'), findsWidgets);
    expect(find.text('Ganancia'), findsWidgets);
    expect(find.text('1,500.00 CUP'), findsOneWidget);
    expect(find.text('25.00 USD'), findsOneWidget);
    expect(find.text('Destino de la inversión'), findsWidgets);
    expect(find.text('Destino de la ganancia'), findsWidgets);
    expect(find.text('A cuenta del fondo'), findsWidgets);
    expect(find.text('A liquidación directa'), findsWidgets);
    expect(find.text('A liquidación'), findsWidgets);
    expect(find.text('A fondo de inversión'), findsWidgets);
    expect(find.text('A fondo de caja'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('envía monto_inversion y ganancia con default a liquidación', (
    tester,
  ) async {
    await abrir(tester, totales: totalesCup);
    await desplazar(tester, find.byType(DropdownButtonFormField<FdiCuenta>));
    await tester.tap(find.byType(DropdownButton<FdiCuenta>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fondo · Principal').last);
    await tester.pumpAndSettle();
    await desplazar(tester, find.text('Repartir a partes iguales'));
    await tester.tap(find.text('Repartir a partes iguales'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    expect(enviado?['p_repartir_igual'], true);
    expect(enviado?['p_tasa_validacion'], isNull);
    expect(find.text('Tasa a CUP'), findsNothing);
    final detalle = enviado?['p_detalle'] as List?;
    expect(detalle, isNotNull);
    expect(detalle!.single['moneda'], 'CUP');
    expect(detalle.single['monto_ganancia_retirada'], 100.0);
    expect(detalle.single['monto_inversion'], 100.0);
    expect(find.text('Crear liquidación'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reparto mixto de inversión valida la suma', (tester) async {
    await abrir(tester, totales: totalesCup);
    // Primer TextFormField = inversión → cuenta del fondo.
    final fields = find.byType(TextFormField);
    expect(fields, findsWidgets);
    await tester.enterText(fields.at(0), '40');
    await tester.pumpAndSettle();
    expect(find.textContaining('debe ser'), findsNothing);

    await desplazar(tester, find.byType(DropdownButtonFormField<FdiCuenta>));
    await tester.tap(find.byType(DropdownButton<FdiCuenta>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fondo · Principal').last);
    await tester.pumpAndSettle();
    await desplazar(tester, find.text('Repartir a partes iguales'));
    await tester.tap(find.text('Repartir a partes iguales'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    final detalle = enviado?['p_detalle'] as List?;
    expect(detalle, isNotNull);
    expect(detalle!.single['monto_inversion'], 40.0);
    expect(detalle.single['monto_ganancia_retirada'], 100.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ganancia a fondo de inversión se deposita en la cuenta', (
    tester,
  ) async {
    await abrir(tester, totales: totalesCup);
    final fields = find.byType(TextFormField);
    // Campos: inv cuenta, inv liquidación, gan liquidación, gan fondo.
    await tester.enterText(fields.at(2), '30'); // ganancia a liquidación
    await tester.pumpAndSettle();
    // CompletarPar deja 70 en fondo de inversión → depósito = 100 inv + 70 gan.

    await desplazar(tester, find.byType(DropdownButtonFormField<FdiCuenta>));
    await tester.tap(find.byType(DropdownButton<FdiCuenta>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fondo · Principal').last);
    await tester.pumpAndSettle();
    await desplazar(tester, find.text('Repartir a partes iguales'));
    await tester.tap(find.text('Repartir a partes iguales'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
    await tester.pumpAndSettle();
    final detalle = enviado?['p_detalle'] as List?;
    expect(detalle, isNotNull);
    expect(detalle!.single['monto_ganancia_retirada'], 30.0);
    expect(detalle.single['monto_inversion'], 170.0);
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
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
