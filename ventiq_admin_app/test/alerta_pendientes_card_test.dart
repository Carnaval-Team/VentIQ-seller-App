// Prueba de widget de la tarjeta de recordatorio de compras (Fase 9).
//
// No toca red ni notificaciones: inyecta un doble de `RecordatoriosService`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/recordatorios_calculo.dart';
import 'package:ventiq_admin_app/services/recordatorios_service.dart';
import 'package:ventiq_admin_app/widgets/alerta_pendientes_card.dart';

class _ServicioFalso extends RecordatoriosService {
  _ServicioFalso({this.resumenFalso, this.umbral = umbralDiasPorDefecto});

  final ResumenPendientes? resumenFalso;
  int umbral;
  int? umbralGuardado;
  int notificaciones = 0;

  @override
  Future<int> umbralDias() async => umbral;

  @override
  Future<void> guardarUmbral(int dias) async {
    umbralGuardado = dias;
    umbral = dias;
  }

  @override
  Future<ResumenPendientes?> resumen({required int idTienda}) async =>
      resumenFalso;

  @override
  Future<void> notificarSiCorresponde({
    required ResumenPendientes? resumen,
    DateTime? ahora,
  }) async {
    notificaciones++;
  }
}

Map<String, dynamic> _panel({
  List<Map<String, dynamic>> compras = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> totales = const <Map<String, dynamic>>[],
}) {
  return <String, dynamic>{
    'id_tienda': 5,
    'orden': 'antiguedad',
    'compras': compras,
    'totales_por_moneda': totales,
  };
}

Map<String, dynamic> _compra({
  required int id,
  required int dias,
  String moneda = 'USD',
  double pendiente = 0,
}) {
  return <String, dynamic>{
    'id_compra': id,
    'numero_compra': 'C-$id',
    'moneda': moneda,
    'dias_antiguedad': dias,
    'monto_total': pendiente,
    'monto_pendiente': pendiente,
    'recibido_pct': 0.5,
  };
}

Widget _montar(Widget hijo, {double ancho = 800}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(width: ancho, child: hijo),
      ),
    ),
  );
}

void main() {
  testWidgets('sin compras muestra el estado vacío y el enlace del umbral',
      (tester) async {
    final servicio = _ServicioFalso(
      resumenFalso: ResumenPendientes.desdePanel(_panel()),
    );

    await tester.pumpWidget(
      _montar(
        AlertaPendientesCard(
          idTienda: 5,
          servicio: servicio,
          notificar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AlertaPendientesCard.claveTarjeta), findsOneWidget);
    expect(find.text('Compras sin completar'), findsOneWidget);
    expect(find.text('No hay compras pendientes de recibir'), findsOneWidget);
    expect(find.text('Ajustar umbral'), findsOneWidget);
  });

  testWidgets('con compras pinta cifras, antigüedad y pendiente por moneda',
      (tester) async {
    final servicio = _ServicioFalso(
      resumenFalso: ResumenPendientes.desdePanel(
        _panel(
          compras: [
            _compra(id: 1, dias: 40, moneda: 'USD', pendiente: 1234.5),
            _compra(id: 2, dias: 20, moneda: 'CUP', pendiente: 2500),
          ],
          totales: [
            {
              'moneda': 'USD',
              'compras': 1,
              'monto_total': 1234.5,
              'monto_pendiente': 1234.5,
            },
            {
              'moneda': 'CUP',
              'compras': 1,
              'monto_total': 2500,
              'monto_pendiente': 2500,
            },
          ],
        ),
        umbralDias: 15,
      ),
    );

    await tester.pumpWidget(
      _montar(
        AlertaPendientesCard(
          idTienda: 5,
          servicio: servicio,
          notificar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 compras sin completar'), findsOneWidget);
    expect(find.text('La más antigua hace 40 días'), findsOneWidget);
    // Chip de antigüedad (supera el umbral) y conteo de las que lo superan.
    expect(find.text('40 días'), findsOneWidget);
    expect(find.text('2 superan el umbral de 15 días'), findsOneWidget);
    // Un bloque por moneda, sin sumarlas.
    expect(find.text('Pendiente en USD'), findsOneWidget);
    expect(find.text('Pendiente en CUP'), findsOneWidget);
    expect(find.text('1,234.50'), findsOneWidget);
    expect(find.text('2,500.00'), findsOneWidget);

    // La ruta de pendientes no existe todavía: botón deshabilitado + nota.
    final boton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Ver pendientes'),
    );
    expect(boton.onPressed, isNull);
    expect(
      find.text(
        'La pantalla de pendientes todavía no está disponible en esta versión.',
      ),
      findsOneWidget,
    );
    expect(servicio.notificaciones, 0);
  });

  testWidgets('el diálogo guarda el umbral validado', (tester) async {
    final servicio = _ServicioFalso(
      resumenFalso: ResumenPendientes.desdePanel(
        _panel(compras: [_compra(id: 1, dias: 40, pendiente: 10)]),
        umbralDias: 15,
      ),
    );

    await tester.pumpWidget(
      _montar(
        AlertaPendientesCard(
          idTienda: 5,
          servicio: servicio,
          notificar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajustar umbral'));
    await tester.pumpAndSettle();
    expect(find.text('Ajustar umbral de aviso'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '30');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(servicio.umbralGuardado, 30);
    expect(find.text('Ajustar umbral de aviso'), findsNothing);
  });

  testWidgets('el diálogo rechaza un umbral fuera de rango', (tester) async {
    final servicio = _ServicioFalso(
      resumenFalso: ResumenPendientes.desdePanel(
        _panel(compras: [_compra(id: 1, dias: 40, pendiente: 10)]),
      ),
    );

    await tester.pumpWidget(
      _montar(
        AlertaPendientesCard(
          idTienda: 5,
          servicio: servicio,
          notificar: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajustar umbral'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(servicio.umbralGuardado, isNull);
    expect(find.text('Debe estar entre 1 y 365'), findsOneWidget);
  });

  testWidgets('en pantalla estrecha no desborda', (tester) async {
    final servicio = _ServicioFalso(
      resumenFalso: ResumenPendientes.desdePanel(
        _panel(
          compras: [
            _compra(id: 1, dias: 40, moneda: 'USD', pendiente: 1234567.89),
            _compra(id: 2, dias: 20, moneda: 'CUP', pendiente: 2500),
          ],
          totales: [
            {
              'moneda': 'USD',
              'compras': 1,
              'monto_total': 1234567.89,
              'monto_pendiente': 1234567.89,
            },
            {
              'moneda': 'CUP',
              'compras': 1,
              'monto_total': 2500,
              'monto_pendiente': 2500,
            },
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      _montar(
        AlertaPendientesCard(
          idTienda: 5,
          servicio: servicio,
          notificar: false,
        ),
        ancho: 360,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2 compras sin completar'), findsOneWidget);
  });
}