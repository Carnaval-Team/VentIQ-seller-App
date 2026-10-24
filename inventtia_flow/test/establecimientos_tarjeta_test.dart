import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/establecimiento_resumen.dart';
import 'package:inventtia_flow/screens/establecimientos_screen.dart';
import 'package:inventtia_flow/utils/exploracion_resumen.dart';
import 'package:inventtia_flow/widgets/filtros_servicios_sheet.dart';

/// Lunes 8 de enero de 2024, 10:00 — dentro de «Lun - Dom, 8:30 - 16:00».
final DateTime _lunes = DateTime(2024, 1, 8, 10);

EstablecimientoResumen _local({
  required String nombre,
  int id = 1,
  int servicios = 1,
  bool directa = false,
  String? horario = 'Lun - Dom, 8:30 - 16:00',
  double? precio,
  String? moneda,
}) {
  return EstablecimientoResumen(
    idLocal: id,
    nombre: nombre,
    provincia: 'Villa Clara Province',
    totalServicios: servicios,
    tieneReservaDirecta: directa,
    horarioTexto: horario,
    precioDesde: precio,
    monedaDesde: moneda,
  );
}

Widget _montar(List<EstablecimientoResumen> locales, {double escalaTexto = 1.0}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 900),
        textScaler: TextScaler.linear(escalaTexto),
      ),
      child: Scaffold(
        body: CuerpoEstablecimientos(
          establecimientos: locales,
          filtros: FiltrosServicios.vacio,
          orden: OrdenEstablecimientos.mejorValorados,
          ahora: _lunes,
        ),
      ),
    ),
  );
}

/// Alto real de la tarjeta que contiene [nombre].
double _altoDe(WidgetTester tester, String nombre) {
  final tarjeta = find.ancestor(
    of: find.text(nombre),
    matching: find.byType(InkWell),
  );
  return tester.getSize(tarjeta.first).height;
}

void main() {
  testWidgets('todas las tarjetas miden lo mismo aunque tengan chips distintos', (
    tester,
  ) async {
    await tester.pumpWidget(
      _montar([
        // Tres chips: abierto, servicios y reserva directa.
        _local(
          id: 1,
          nombre: 'Con tres chips',
          servicios: 4,
          directa: true,
        ),
        // Un solo chip.
        _local(
          id: 2,
          nombre: 'Con un chip',
          servicios: 1,
          horario: 'Cerrado',
        ),
        // Sin chips: horario ilegible y sin servicios.
        _local(id: 3, nombre: 'Sin chips', servicios: 0, horario: 'sd'),
      ]),
    );

    final conTres = _altoDe(tester, 'Con tres chips');
    final conUno = _altoDe(tester, 'Con un chip');
    final sinNinguno = _altoDe(tester, 'Sin chips');

    expect(conTres, conUno);
    expect(conTres, sinNinguno);
  });

  testWidgets('los chips van en una fila, no apilados', (tester) async {
    await tester.pumpWidget(
      _montar([
        _local(id: 1, nombre: 'Con chips', servicios: 4, directa: true),
      ]),
    );

    // Sin `Wrap`: era lo que hacía saltar los chips a una segunda línea.
    expect(find.byType(Wrap), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    final fila = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(fila.scrollDirection, Axis.horizontal);
  });

  testWidgets('los tres chips se pintan en la misma fila', (tester) async {
    await tester.pumpWidget(
      _montar([
        _local(id: 1, nombre: 'Con chips', servicios: 4, directa: true),
      ]),
    );

    final abierto = tester.getRect(find.text('Abierto ahora'));
    final servicios = tester.getRect(find.text('4 servicios'));
    final directa = tester.getRect(find.text('Reserva directa'));

    // Misma «y» (una sola fila) y en orden creciente de izquierda a derecha.
    expect(abierto.center.dy, servicios.center.dy);
    expect(servicios.center.dy, directa.center.dy);
    expect(abierto.left, lessThan(servicios.left));
    expect(servicios.left, lessThan(directa.left));
  });

  testWidgets('el precio va en dos líneas y el importe no se puede recortar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _montar([
        _local(id: 1, nombre: 'Con precio', servicios: 2, precio: 2500, moneda: 'CUP'),
      ]),
    );

    // «Desde» y el importe son dos textos: en una sola línea, «Desde 2500 CUP» no
    // cabía en la columna y salía cortado.
    expect(find.text('Desde'), findsOneWidget);
    expect(find.text('2500 CUP'), findsOneWidget);

    final desde = tester.getRect(find.text('Desde'));
    final importe = tester.getRect(find.text('2500 CUP'));
    expect(desde.bottom, lessThanOrEqualTo(importe.top));

    // Y el importe se reduce si hace falta (`FittedBox`) en vez de recortarse: un
    // `Text` con `ellipsis` volvería a dejar el precio «picado».
    final texto = tester.widget<Text>(find.text('2500 CUP'));
    expect(texto.maxLines, 1);
    expect(texto.overflow, isNot(TextOverflow.ellipsis));
    expect(
      find.ancestor(
        of: find.text('2500 CUP'),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no desborda en un teléfono de 320 pt', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _montar([
        _local(
          id: 1,
          nombre: 'Un establecimiento con el nombre bastante largo',
          servicios: 12,
          directa: true,
        ),
      ]),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda con el texto al 130 %', (tester) async {
    await tester.pumpWidget(
      _montar([
        _local(id: 1, nombre: 'Con texto grande', servicios: 3, directa: true),
      ], escalaTexto: 1.3),
    );

    expect(tester.takeException(), isNull);
  });
}