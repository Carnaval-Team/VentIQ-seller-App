import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/establecimiento_resumen.dart';
import 'package:inventtia_flow/screens/establecimientos_screen.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/utils/exploracion_resumen.dart';
import 'package:inventtia_flow/widgets/filtros_servicios_sheet.dart';
import 'package:inventtia_flow/widgets/resenas.dart';

/// Tests del **pintado** del listado de establecimientos.
///
/// La carga (Supabase) vive en el `State` de `EstablecimientosScreen`; aquí se
/// monta el cuerpo con datos inyectados, así que no se toca la red. El reloj se
/// pasa fijo: un «abierto ahora» depende de la hora.
///
/// Lunes 8 de enero de 2024, 10:00 — dentro de «Lun - Dom, 8:30 - 16:00».
final DateTime _lunes10 = DateTime(2024, 1, 8, 10);

const String _horarioManana = 'Lun - Dom, 8:30 - 16:00';
const String _horarioNoche = 'Lun - Dom, 18:00 - 22:00';

EstablecimientoResumen _local({
  int id = 1,
  String nombre = 'Local',
  String? provincia = 'Villa Clara Province',
  String? foto,
  String? horario,
  double? rating,
  int resenas = 0,
  int servicios = 1,
  double? precio,
  String? moneda,
  bool reservaDirecta = false,
}) {
  return EstablecimientoResumen(
    idLocal: id,
    nombre: nombre,
    provincia: provincia,
    foto: foto,
    horarioTexto: horario,
    rating: rating,
    totalResenas: resenas,
    totalServicios: servicios,
    precioDesde: precio,
    monedaDesde: moneda,
    tieneReservaDirecta: reservaDirecta,
  );
}

Future<void> _montar(WidgetTester tester, Widget cuerpo) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: cuerpo)));
  await tester.pump();
}

double _y(WidgetTester tester, String texto) =>
    tester.getTopLeft(find.text(texto)).dy;

void main() {
  testWidgets('los sin reseñas van al final con «Mejor valorados» y sin '
      'estrellas', (tester) async {
    final sinResenas = _local(id: 1, nombre: 'Alfa', servicios: 9);
    final bueno = _local(id: 2, nombre: 'Zeta', rating: 4.9, resenas: 30);
    final regular = _local(id: 3, nombre: 'Beta', rating: 3.1, resenas: 5);

    await _montar(
      tester,
      CuerpoEstablecimientos(
        establecimientos: [sinResenas, regular, bueno],
        filtros: FiltrosServicios.vacio,
        orden: OrdenEstablecimientos.mejorValorados,
        ahora: _lunes10,
      ),
    );

    // Primero los valorados (4.9 antes que 3.1) y el sin reseñas al final.
    expect(_y(tester, 'Zeta'), lessThan(_y(tester, 'Beta')));
    expect(_y(tester, 'Beta'), lessThan(_y(tester, 'Alfa')));

    // Solo los dos locales con reseñas pintan estrellas: al de Alfa no se le
    // supone una valoración.
    expect(find.byType(Estrellas), findsNWidgets(2));
    expect(find.text('4.9 (30 reseñas)'), findsOneWidget);
    expect(find.text('3.1 (5 reseñas)'), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing);
    expect(find.textContaining('Sin valoraciones'), findsNothing);
  });

  testWidgets('el filtro «abierto ahora» oculta los cerrados', (tester) async {
    final abierto = _local(
      id: 1,
      nombre: 'Local Abierto',
      horario: _horarioManana,
    );
    final cerrado = _local(
      id: 2,
      nombre: 'Local Cerrado',
      horario: _horarioNoche,
    );
    final sinHorario = _local(id: 3, nombre: 'Local Sin Horario');

    await _montar(
      tester,
      CuerpoEstablecimientos(
        establecimientos: [abierto, cerrado, sinHorario],
        filtros: const FiltrosServicios(soloAbiertos: true),
        orden: OrdenEstablecimientos.nombre,
        ahora: _lunes10,
      ),
    );

    expect(find.text('Local Abierto'), findsOneWidget);
    expect(find.text('Local Cerrado'), findsNothing);
    // Un horario ilegible no se cuenta como abierto.
    expect(find.text('Local Sin Horario'), findsNothing);
    expect(find.text('Abierto ahora'), findsOneWidget);
    expect(find.text('Cerrado'), findsNothing);
  });

  testWidgets('el chip de servicios dice el número correcto', (tester) async {
    await _montar(
      tester,
      CuerpoEstablecimientos(
        establecimientos: [
          _local(id: 1, nombre: 'Local Uno', servicios: 3, reservaDirecta: true),
          _local(id: 2, nombre: 'Local Dos', servicios: 1),
        ],
        filtros: FiltrosServicios.vacio,
        orden: OrdenEstablecimientos.nombre,
        ahora: _lunes10,
      ),
    );

    expect(find.text('3 servicios'), findsOneWidget);
    expect(find.text('1 servicio'), findsOneWidget);
    expect(find.text('Reserva directa'), findsOneWidget);
  });

  testWidgets('estado vacío: nombra el filtro activo y ofrece quitarlo', (
    tester,
  ) async {
    var pedido = false;

    await _montar(
      tester,
      CuerpoEstablecimientos(
        establecimientos: const <EstablecimientoResumen>[],
        filtros: FiltrosServicios.vacio,
        orden: OrdenEstablecimientos.mejorValorados,
        categoria: const HomeCatalogCategory(
          id: 6,
          codigo: 'belleza',
          nombre: 'Belleza',
        ),
        ahora: _lunes10,
        onQuitarFiltros: () => pedido = true,
      ),
    );

    expect(find.textContaining('Belleza'), findsOneWidget);

    final boton = find.text('Ver todos los establecimientos');
    expect(boton, findsOneWidget);
    await tester.tap(boton);
    await tester.pump();
    expect(pedido, isTrue);
  });

  testWidgets('sin reseñas ni precio la tarjeta no inventa ese dato', (
    tester,
  ) async {
    await _montar(
      tester,
      CuerpoEstablecimientos(
        establecimientos: [_local(id: 1, nombre: 'Local Pelado')],
        filtros: FiltrosServicios.vacio,
        orden: OrdenEstablecimientos.nombre,
        ahora: _lunes10,
      ),
    );

    expect(find.text('Local Pelado'), findsOneWidget);
    expect(find.byType(Estrellas), findsNothing);
    expect(find.textContaining('Desde'), findsNothing);
    expect(find.text('Villa Clara Province'), findsOneWidget);
  });
}