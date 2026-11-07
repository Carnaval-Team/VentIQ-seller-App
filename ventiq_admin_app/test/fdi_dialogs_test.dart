import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/fondo_inversion.dart';
import 'package:ventiq_admin_app/widgets/fdi_inversor_dialog.dart';
import 'package:ventiq_admin_app/widgets/fdi_liquidacion_detalle_dialog.dart';

Future<void> abrir(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancelar con el campo enfocado permite cerrar y reabrir', (
    tester,
  ) async {
    await abrir(tester, const FdiInversorDialog());
    await tester.enterText(find.byType(TextFormField).first, 'Ana');
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Nuevo inversor'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo inversor'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('conserva el texto al cambiar el estado activo y valida', (
    tester,
  ) async {
    await abrir(tester, const FdiInversorDialog());
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Indique el nombre'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Ana');
    await tester.enterText(find.byType(TextFormField).last, '33,3333');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('33,3333'), findsOneWidget);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo inversor'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  final liquidacion = FdiLiquidacion(
    id: 7,
    fechaDesde: DateTime(2026, 11, 1),
    fechaHasta: DateTime(2026, 11, 7),
    modoFiltro: 'todas',
    ventaTotal: 20,
    costoTotal: 10,
    gananciaReporte: 10,
    cuentaDestino: 'Caja',
    conceptoDestino: 'Fondo',
    cantidadOrdenes: 2,
    detalle: const [
      {
        'id_medio_pago': 1,
        'moneda': 'CUP',
        'monto_vendido': 20,
        'monto_inversion': 10,
        'monto_ganancia_retirada': 10,
      },
    ],
  );

  testWidgets('muestra un resumen simple y el reparto entero por inversor', (
    tester,
  ) async {
    await abrir(
      tester,
      FdiLiquidacionDetalleDialog(
        liquidacion: liquidacion,
        cargarRepartos: () async => [
          for (final nombre in ['Ana', 'Luis', 'Eva'])
            {
              'nombre_snapshot': nombre,
              'porcentaje_snapshot': 33.3333,
              'monto': 3,
              'moneda': 'CUP',
              'id_medio_pago': 1,
              'pagado_at': nombre == 'Ana' ? '2026-11-07' : null,
              'referencia_pago': 'REC-1',
            },
        ],
      ),
    );
    expect(find.text('Liquidación #7'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Eva'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('3 CUP'), findsNWidgets(3));
    expect(find.text('Ganancia repartida'), findsOneWidget);
    expect(find.text('9 CUP'), findsOneWidget);
    expect(find.text('Período'), findsOneWidget);
    expect(find.text('Destino'), findsOneWidget);
    expect(find.text('Creada'), findsOneWidget);
    expect(find.text('Venta'), findsOneWidget);
    expect(find.text('Costo'), findsOneWidget);
    expect(find.text('Detalle por medio y moneda'), findsNothing);
    expect(find.text('Filtro'), findsNothing);
    expect(find.textContaining('REC-1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('agrupa medios por inversor sin mezclar monedas en móvil', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await abrir(
      tester,
      FdiLiquidacionDetalleDialog(
        liquidacion: liquidacion,
        cargarRepartos: () async => [
          {
            'id_inversor': 1,
            'nombre_snapshot': 'Ana',
            'moneda': 'CUP',
            'monto': 3,
          },
          {
            'id_inversor': 1,
            'nombre_snapshot': 'Ana',
            'moneda': 'CUP',
            'monto': 4,
          },
          {
            'id_inversor': 1,
            'nombre_snapshot': 'Ana',
            'moneda': 'USD',
            'monto': 1,
          },
          {
            'id_inversor': 2,
            'nombre_snapshot': 'Ana',
            'moneda': 'CUP',
            'monto': 2,
          },
        ],
      ),
    );
    await tester.scrollUntilVisible(
      find.text('2 CUP'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('7 CUP'), findsOneWidget);
    expect(find.text('9 CUP'), findsOneWidget);
    expect(find.text('1 USD'), findsNWidgets(2));
    expect(find.text('Ana'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('permite reintentar si falla el historial', (tester) async {
    var intentos = 0;
    await abrir(
      tester,
      FdiLiquidacionDetalleDialog(
        liquidacion: liquidacion,
        cargarRepartos: () async {
          if (intentos++ == 0) throw Exception('Sin conexión');
          return [];
        },
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Reintentar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Esta liquidación no tiene repartos registrados.'),
      findsOneWidget,
    );
    expect(intentos, 2);
    expect(tester.takeException(), isNull);
  });
}
