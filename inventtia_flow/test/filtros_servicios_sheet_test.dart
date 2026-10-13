import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/widgets/filtros_servicios_sheet.dart';

/// Opciones de ejemplo, como las que arma el catálogo con datos reales.
const _opciones = OpcionesFiltros(
  precios: [
    OfertaPrecio(precio: 10, moneda: 'USD'),
    OfertaPrecio(precio: 30, moneda: 'USD'),
    OfertaPrecio(precio: 1500, moneda: 'CUP'),
  ],
  provincias: ['Artemisa', 'La Habana'],
  locales: [
    LocalOpcion(id: 7, nombre: 'Carnaval', provincia: 'La Habana'),
    LocalOpcion(id: 9, nombre: 'Transportación', provincia: 'Artemisa'),
    LocalOpcion(id: 11, nombre: 'Barbería El Vedado', provincia: 'La Habana'),
  ],
  hayValoraciones: true,
);

void main() {
  group('FiltrosServicios.coincide', () {
    test('sin filtros pasa cualquier servicio, incluso sin datos', () {
      const filtros = FiltrosServicios.vacio;
      expect(filtros.hayAlgo, isFalse);
      expect(filtros.coincide(), isTrue);
      expect(filtros.coincide(precioItem: null, ratingItem: null), isTrue);
    });

    test('la moneda descarta los servicios de otra moneda', () {
      const filtros = FiltrosServicios(moneda: 'USD');
      expect(filtros.coincide(monedaItem: 'USD'), isTrue);
      expect(filtros.coincide(monedaItem: 'CUP'), isFalse);
      // Un servicio sin precio no puede verificarse: queda fuera.
      expect(filtros.coincide(monedaItem: null), isFalse);
    });

    test('el rango de precio es inclusivo en los dos extremos', () {
      const filtros = FiltrosServicios(precioMin: 10, precioMax: 30);
      expect(filtros.coincide(precioItem: 10), isTrue);
      expect(filtros.coincide(precioItem: 30), isTrue);
      expect(filtros.coincide(precioItem: 20), isTrue);
      expect(filtros.coincide(precioItem: 9.99), isFalse);
      expect(filtros.coincide(precioItem: 30.01), isFalse);
      expect(filtros.coincide(precioItem: null), isFalse);
    });

    test('un solo extremo del rango también filtra', () {
      expect(
        const FiltrosServicios(precioMin: 100).coincide(precioItem: 50),
        isFalse,
      );
      expect(
        const FiltrosServicios(precioMax: 100).coincide(precioItem: 1000),
        isFalse,
      );
      expect(
        const FiltrosServicios(precioMax: 100).coincide(precioItem: 80),
        isTrue,
      );
    });

    test('la valoración mínima exige reseñas reales', () {
      const filtros = FiltrosServicios(ratingMinimo: 4);
      expect(filtros.coincide(ratingItem: 4), isTrue);
      expect(filtros.coincide(ratingItem: 3.9), isFalse);
      // Sin reseñas no se le supone un 0: simplemente no cumple.
      expect(filtros.coincide(ratingItem: null), isFalse);
    });

    test('el establecimiento y la provincia se comparan tal cual', () {
      const filtros = FiltrosServicios(idLocal: 7, provincia: 'La Habana');
      expect(
        filtros.coincide(idLocalItem: 7, provinciaItem: 'La Habana'),
        isTrue,
      );
      expect(
        filtros.coincide(idLocalItem: 9, provinciaItem: 'La Habana'),
        isFalse,
      );
      expect(
        filtros.coincide(idLocalItem: 7, provinciaItem: 'Artemisa'),
        isFalse,
      );
    });

    test('"abierto ahora" no da por abierto un horario desconocido', () {
      const filtros = FiltrosServicios(soloAbiertos: true);
      expect(filtros.coincide(abiertoItem: true), isTrue);
      expect(filtros.coincide(abiertoItem: false), isFalse);
      expect(filtros.coincide(abiertoItem: null), isFalse);
    });

    test('"solo favoritos" deja fuera lo que no está guardado', () {
      const filtros = FiltrosServicios(soloFavoritos: true);
      expect(filtros.coincide(esFavoritoItem: true), isTrue);
      expect(filtros.coincide(esFavoritoItem: false), isFalse);
      // Quien no sabe si el servicio es favorito no puede demostrarlo: fuera.
      expect(filtros.coincide(), isFalse);
      // Sin el filtro, el mismo servicio pasa igual.
      expect(FiltrosServicios.vacio.coincide(esFavoritoItem: false), isTrue);
    });

    test('los filtros se acumulan (todos deben cumplirse)', () {
      const filtros = FiltrosServicios(
        moneda: 'USD',
        precioMax: 20,
        provincia: 'La Habana',
        ratingMinimo: 4,
        soloAbiertos: true,
      );
      expect(
        filtros.coincide(
          monedaItem: 'USD',
          precioItem: 15,
          provinciaItem: 'La Habana',
          ratingItem: 4.6,
          abiertoItem: true,
        ),
        isTrue,
      );
      final cumple = filtros.coincide(
        monedaItem: 'USD',
        precioItem: 15,
        provinciaItem: 'La Habana',
        ratingItem: 4.6,
        abiertoItem: true,
      );
      expect(filtros.coincide(monedaItem: 'CUP', precioItem: 15), isFalse);
      expect(filtros.coincide(monedaItem: 'USD', precioItem: 25), isFalse);
      expect(
        filtros.coincide(
          monedaItem: 'USD',
          precioItem: 15,
          provinciaItem: 'Artemisa',
        ),
        isFalse,
      );
      expect(
        filtros.coincide(
          monedaItem: 'USD',
          precioItem: 15,
          provinciaItem: 'La Habana',
          ratingItem: 2,
        ),
        isFalse,
      );
      expect(
        filtros.coincide(
          monedaItem: 'USD',
          precioItem: 15,
          provinciaItem: 'La Habana',
          ratingItem: 4.6,
          abiertoItem: false,
        ),
        isFalse,
      );
      expect(cumple, isTrue);
    });

    test('activos cuenta cada decisión tomada', () {
      expect(FiltrosServicios.vacio.activos, 0);
      expect(
        const FiltrosServicios(
          precioMin: 1,
          precioMax: 2,
          moneda: 'USD',
        ).activos,
        2,
      );
      expect(
        const FiltrosServicios(
          provincia: 'La Habana',
          idLocal: 7,
          ratingMinimo: 4,
          soloAbiertos: true,
        ).activos,
        4,
      );
      // Los guardados cuentan como un filtro más: el badge del botón y el
      // contador del pie tienen que verlo, ahora que no hay chip fuera.
      const conFavoritos = FiltrosServicios(soloFavoritos: true);
      expect(conFavoritos.activos, 1);
      expect(conFavoritos.hayAlgo, isTrue);
    });
  });

  group('FiltrosServicios.copyWith', () {
    test('sin argumentos conserva todo', () {
      const original = FiltrosServicios(
        moneda: 'USD',
        precioMin: 5,
        precioMax: 50,
        provincia: 'La Habana',
        idLocal: 7,
        nombreLocal: 'Carnaval',
        ratingMinimo: 4,
        soloAbiertos: true,
      );
      final copia = original.copyWith();
      expect(copia.moneda, 'USD');
      expect(copia.precioMin, 5);
      expect(copia.precioMax, 50);
      expect(copia.provincia, 'La Habana');
      expect(copia.idLocal, 7);
      expect(copia.nombreLocal, 'Carnaval');
      expect(copia.ratingMinimo, 4);
      expect(copia.soloAbiertos, isTrue);
    });

    test('se puede volver a null explícitamente', () {
      const original = FiltrosServicios(
        moneda: 'USD',
        provincia: 'La Habana',
        idLocal: 7,
        nombreLocal: 'Carnaval',
        ratingMinimo: 4,
      );
      final limpio = original.copyWith(
        moneda: null,
        provincia: null,
        idLocal: null,
        nombreLocal: null,
        ratingMinimo: null,
      );
      expect(limpio.moneda, isNull);
      expect(limpio.provincia, isNull);
      expect(limpio.idLocal, isNull);
      expect(limpio.nombreLocal, isNull);
      expect(limpio.ratingMinimo, isNull);
      expect(limpio.hayAlgo, isFalse);
    });

    test('los booleanos se apagan explícitamente', () {
      // Los dos son `bool` (no `bool?`): hay que poder volver a `false`, que es
      // lo que hace el switch del sheet al desactivarse.
      const original = FiltrosServicios(
        soloAbiertos: true,
        soloFavoritos: true,
      );
      final apagado = original.copyWith(
        soloAbiertos: false,
        soloFavoritos: false,
      );
      expect(apagado.soloAbiertos, isFalse);
      expect(apagado.soloFavoritos, isFalse);
      expect(apagado.hayAlgo, isFalse);
    });
  });

  group('OpcionesFiltros', () {
    test('las monedas salen en el orden del catálogo de la app', () {
      expect(_opciones.monedas, ['USD', 'CUP']);
    });

    test('el rango de precio se recalcula por moneda', () {
      expect(_opciones.rangoPrecio(null)!.min, 10);
      expect(_opciones.rangoPrecio(null)!.max, 1500);
      expect(_opciones.rangoPrecio('USD')!.min, 10);
      expect(_opciones.rangoPrecio('USD')!.max, 30);
      // Una moneda sin precios no tiene rango: no se inventa.
      expect(_opciones.rangoPrecio('EUR'), isNull);
    });

    test('sin datos no hay nada que ofrecer', () {
      const vacias = OpcionesFiltros();
      expect(vacias.hayAlgo, isFalse);
      expect(vacias.monedas, isEmpty);
      expect(vacias.rangoPrecio(null), isNull);
    });

    test('los guardados cuentan como opción de filtrado', () {
      // Sin esto, un catálogo sin precios ni provincias (pero con favoritos)
      // no ofrecería el botón de filtros y la pista no tendría destino.
      const soloGuardados = OpcionesFiltros(
        hayFavoritos: true,
        totalFavoritos: 2,
      );
      expect(soloGuardados.hayAlgo, isTrue);
      expect(soloGuardados.totalFavoritos, 2);
    });
  });

  group('mostrarFiltrosServicios', () {
    /// Monta un botón que abre el sheet y guarda el resultado en [capturado].
    Future<void> abrir(
      WidgetTester tester,
      List<FiltrosServicios?> capturado, {
      FiltrosServicios actual = FiltrosServicios.vacio,
      OpcionesFiltros opciones = _opciones,
      int Function(FiltrosServicios)? contador,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    capturado.add(
                      await mostrarFiltrosServicios(
                        context,
                        actual: actual,
                        opciones: opciones,
                        contador: contador,
                      ),
                    );
                  },
                  child: const Text('abrir filtros'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir filtros'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'con varias monedas pide elegir una antes de filtrar por precio',
      (tester) async {
        final capturado = <FiltrosServicios?>[];
        await abrir(tester, capturado, contador: (_) => 3);

        // Mezclar dólares y pesos en un mismo rango no significa nada: en vez de
        // un control que engaña, se explica qué falta.
        expect(
          find.text('Elige una moneda arriba para poder comparar precios.'),
          findsOneWidget,
        );
        expect(find.byType(RangeSlider), findsNothing);

        await tester.tap(find.text('\$ USD'));
        await tester.pumpAndSettle();

        expect(find.byType(RangeSlider), findsOneWidget);
        expect(find.text('10 \$'), findsOneWidget);
        expect(find.text('30 \$'), findsOneWidget);
      },
    );

    testWidgets('con una sola moneda el rango de precio se muestra solo', (
      tester,
    ) async {
      final capturado = <FiltrosServicios?>[];
      await abrir(
        tester,
        capturado,
        opciones: const OpcionesFiltros(
          precios: [OfertaPrecio(precio: 5, moneda: 'USD')],
        ),
        contador: (_) => 1,
      );

      expect(find.text('Todos los servicios están en 5 \$.'), findsOneWidget);
      expect(find.byType(RangeSlider), findsNothing);
    });

    testWidgets('aplica la moneda y devuelve el filtro al confirmar', (
      tester,
    ) async {
      final capturado = <FiltrosServicios?>[];
      await abrir(
        tester,
        capturado,
        contador: (f) {
          const servicios = ['USD', 'USD', 'CUP'];
          if (f.moneda == null) return servicios.length;
          return servicios.where((m) => m == f.moneda).length;
        },
      );

      expect(find.text('3 servicios coinciden ahora mismo'), findsOneWidget);
      expect(find.text('Ver 3 servicios'), findsOneWidget);

      // El chip de moneda se pinta con símbolo + código.
      await tester.tap(find.text('\$ USD'));
      await tester.pumpAndSettle();

      expect(find.text('2 servicios coinciden ahora mismo'), findsOneWidget);
      expect(find.text('Ver 2 servicios'), findsOneWidget);

      await tester.tap(find.text('Ver 2 servicios'));
      await tester.pumpAndSettle();

      expect(capturado, hasLength(1));
      expect(capturado.single!.moneda, 'USD');
    });

    testWidgets('sin coincidencias el botón de aplicar se desactiva', (
      tester,
    ) async {
      final capturado = <FiltrosServicios?>[];
      await abrir(tester, capturado, contador: (_) => 0);

      expect(find.text('Sin resultados'), findsOneWidget);
      final boton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Sin resultados'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets('Limpiar deja el borrador vacío y no aplica nada al cerrar', (
      tester,
    ) async {
      final capturado = <FiltrosServicios?>[];
      await abrir(
        tester,
        capturado,
        actual: const FiltrosServicios(moneda: 'USD', provincia: 'La Habana'),
        contador: (_) => 2,
      );

      expect(find.text('2 activos'), findsOneWidget);
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();

      expect(find.text('2 activos'), findsNothing);
      expect(find.text('Ver 2 servicios'), findsOneWidget);

      await tester.tap(find.text('Ver 2 servicios'));
      await tester.pumpAndSettle();
      expect(capturado.single!.hayAlgo, isFalse);
    });

    testWidgets('cerrar sin aplicar no cambia los filtros', (tester) async {
      final capturado = <FiltrosServicios?>[];
      await abrir(
        tester,
        capturado,
        actual: const FiltrosServicios(provincia: 'La Habana'),
        contador: (_) => 1,
      );

      // Se cierra el sheet tocando la barrera: devuelve `null` = sin cambios.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(capturado, hasLength(1));
      expect(capturado.single, isNull);
    });

    testWidgets('el filtro de establecimiento aparece al buscar un local', (
      tester,
    ) async {
      final capturado = <FiltrosServicios?>[];
      await abrir(
        tester,
        capturado,
        contador: (f) => f.idLocal == null ? 3 : 1,
      );

      // La sección de establecimiento está más abajo: se desplaza el sheet.
      await tester.dragUntilVisible(
        find.text('Establecimiento'),
        find.byType(ListView).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'carnaval');
      await tester.pumpAndSettle();
      expect(find.text('Carnaval'), findsOneWidget);
      expect(find.text('Barbería El Vedado'), findsNothing);

      await tester.tap(find.text('Carnaval'));
      await tester.pumpAndSettle();
      expect(find.text('1 servicio coincide ahora mismo'), findsOneWidget);

      await tester.tap(find.text('Ver 1 servicio'));
      await tester.pumpAndSettle();
      expect(capturado.single!.idLocal, 7);
      expect(capturado.single!.nombreLocal, 'Carnaval');
    });

    testWidgets('sin favoritos no se ofrece la sección de guardados', (
      tester,
    ) async {
      final capturado = <FiltrosServicios?>[];
      await abrir(tester, capturado, contador: (_) => 3);

      // `_opciones` no marca favoritos: la sección no existe en vez de salir
      // vacía o filtrar a cero.
      expect(find.text('Guardados'), findsNothing);
      expect(find.text('Solo favoritos'), findsNothing);
    });

    testWidgets('los guardados se activan en el sheet y se aplican', (
      tester,
    ) async {
      final capturado = <FiltrosServicios?>[];
      final borradores = <FiltrosServicios>[];
      await abrir(
        tester,
        capturado,
        opciones: const OpcionesFiltros(hayFavoritos: true, totalFavoritos: 3),
        contador: (f) {
          borradores.add(f);
          return f.soloFavoritos ? 1 : 4;
        },
      );

      expect(find.text('Guardados'), findsOneWidget);
      expect(
        find.text('Los 3 servicios que guardaste con el corazón.'),
        findsOneWidget,
      );
      // La sección va arriba del todo: se ve sin desplazar el sheet.
      expect(borradores.last.soloFavoritos, isFalse);
      expect(find.text('Ver 4 servicios'), findsOneWidget);

      await tester.tap(find.text('Solo favoritos'));
      await tester.pumpAndSettle();

      // El contador ve el borrador con guardados: el número baja a 1.
      expect(borradores.last.soloFavoritos, isTrue);
      expect(find.text('Ver 1 servicio'), findsOneWidget);

      await tester.tap(find.text('Ver 1 servicio'));
      await tester.pumpAndSettle();
      expect(capturado.single!.soloFavoritos, isTrue);
    });

    testWidgets('Limpiar también apaga los guardados', (tester) async {
      final capturado = <FiltrosServicios?>[];
      await abrir(
        tester,
        capturado,
        actual: const FiltrosServicios(soloFavoritos: true),
        opciones: const OpcionesFiltros(hayFavoritos: true, totalFavoritos: 1),
        contador: (_) => 1,
      );

      expect(find.text('1 activo'), findsOneWidget);
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver 1 servicio'));
      await tester.pumpAndSettle();
      expect(capturado.single!.soloFavoritos, isFalse);
    });
  });
}
