// VERIFICACIÓN INDEPENDIENTE (task-4) de la pestaña «Precios» y del editor
// compartido. No es un test de producto: es la evidencia adversarial del
// verificador. Las expectativas se escribieron leyendo SOLO el enunciado y el
// código original (`git show HEAD:...gestion_servicios_screen.dart`), no el
// resumen de los implementadores.
//
// Lo que se blinda aquí:
//  · `construir()` no lanza en los casos límite del punto 9 de la tarea.
//  · No se inventan precios: "1.500" es 1500 (no 1.5) y "1,50" es 1.5.
//  · Quitar la moneda base reasigna la base (el desplegable no admite un valor
//    que ya no está en la lista).
//  · Una regla sin precios / sin campo no se guarda.
//  · `aplica_precio_ida_vuelta_todos` se conserva cuando la casilla no se pinta
//    (el editor no debe tocarlo fuera de transporte en ómnibus).
//  · El controlador se `dispose()`a sin lanzar y sin `Timer`s vivos.
//  · Los anchors del tutorial solo se registran con `conAnchorsTutorial: true`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inventtia_flow/models/config_precio.dart';
import 'package:inventtia_flow/models/precio_config.dart';
import 'package:inventtia_flow/screens/admin/local_servicio_admin_screen.dart';
import 'package:inventtia_flow/tutorial/tutorial_anchor.dart';
import 'package:inventtia_flow/widgets/precios_servicio_editor.dart';

PreciosServicioControlador _ctrl(
  ConfigPrecio? config, {
  List<CampoSelectPrecio> campos = const [],
  bool proponer = false,
}) {
  final c = PreciosServicioControlador(
    configInicial: config,
    camposSelect: campos,
    proponerMonedaOrigen: proponer,
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('verificación · orden de pestañas', () {
    test('enum: precios va inmediatamente a la izquierda de promociones', () {
      // El índice del enum ES el índice de la pestaña (`initialIndex` y
      // `TabBarView` usan el orden de `values`), así que este assert cubre el
      // contrato que el tutorial y el detalle del local asumen.
      expect(PestanaLocalServicio.values, const [
        PestanaLocalServicio.calendario,
        PestanaLocalServicio.configuracion,
        PestanaLocalServicio.precios,
        PestanaLocalServicio.promociones,
      ]);
      expect(PestanaLocalServicio.calendario.index, 0);
      expect(PestanaLocalServicio.configuracion.index, 1,
          reason: 'tutorial_navegacion y el detalle abren «Configuración»');
      expect(PestanaLocalServicio.precios.index, 2);
      expect(PestanaLocalServicio.promociones.index, 3);
      expect(
        PestanaLocalServicio.precios.index + 1,
        PestanaLocalServicio.promociones.index,
      );
    });
  });

  group('verificación · construir() casos límite', () {
    test('solo USD y sin precios: mapa vacío, sin reglas y sin excepción', () {
      final c = _ctrl(null);

      final out = c.construir();

      expect(out, isNotNull);
      expect(out!.monedas, const ['USD']);
      expect(out.monedaDefault, 'USD');
      expect(out.preciosBase, isEmpty);
      expect(out.reglas, isEmpty);
      expect(c.error, isNull);
      // `ConfigPrecio.toJson` omite `precios_base` cuando está vacío: es lo que
      // se va a la base. No debe aparecer la clave con un mapa vacío.
      expect(out.toJson().containsKey('precios_base'), isFalse);
      expect(out.toJson()['monedas'], const ['USD']);
    });

    test('regla cuyo campo ya no existe en camposSelect: no lanza', () {
      final c = _ctrl(
        ConfigPrecio(
          monedas: const ['USD'],
          preciosBase: const {'USD': 25},
          reglas: [
            ReglaPrecio(
              siClave: 'tipo_habitacion',
              preciosOpcion: const {
                'Doble': {'USD': 40.0},
              },
            ),
          ],
        ),
        // El dato adicional se borró: la regla queda huérfana.
        campos: const [],
      );

      final out = c.construir();

      expect(out, isNotNull);
      expect(out!.reglas, hasLength(1));
      // Fallback al propio `siClave`, que es lo que hacía el formulario.
      expect(out.reglas.single.siClave, 'tipo_habitacion');
      expect(out.reglas.single.preciosOpcion['Doble'], const {'USD': 40.0});
      expect(c.error, isNull);
    });

    test('"1.500" en CUP se guarda como 1500 y "1,50" como 1.5', () {
      final c = _ctrl(
        ConfigPrecio(monedaDefault: 'CUP', monedas: const ['CUP']),
      );

      // Con un solo separador y 3 dígitos detrás, separa millares (es-CU).
      c.editarPrecioBase('CUP', '1.500');
      expect(c.construir()!.preciosBase['CUP'], 1500);

      // Coma decimal de dos dígitos: es un decimal normal.
      c.editarPrecioBase('CUP', '1,50');
      expect(c.construir()!.preciosBase['CUP'], 1.5);

      // `parseMonto` también entiende en-US: coma de millares + punto decimal.
      c.editarPrecioBase('CUP', '1,500.75');
      expect(c.construir()!.preciosBase['CUP'], 1500.75);
    });

    test('quitar la moneda que es base reasigna la base a otra habilitada', () {
      final c = _ctrl(
        ConfigPrecio(
          monedaDefault: 'CUP',
          monedas: const ['USD', 'CUP', 'MLC'],
          preciosBase: const {'USD': 25, 'CUP': 2500, 'MLC': 25},
        ),
      );

      c.toggleMoneda('CUP', false);

      final out = c.construir()!;
      expect(out.monedas, const ['USD', 'MLC']);
      expect(out.monedaDefault, 'USD');
      // El precio de la moneda quitada no se guarda.
      expect(out.preciosBase, const {'USD': 25.0, 'MLC': 25.0});
    });

    test('una regla sin precios no se guarda', () {
      final c = _ctrl(
        ConfigPrecio(
          monedas: const ['USD'],
          preciosBase: const {'USD': 25},
          reglas: [
            ReglaPrecio(
              siClave: 'talla',
              // El 0 significa «sin precio» en toda la app.
              preciosOpcion: const {
                'M': {'USD': 0.0},
              },
            ),
          ],
        ),
        campos: const [
          (slug: 'talla', clave: 'talla', etiqueta: 'Talla', opciones: ['S', 'M']),
        ],
      );

      final out = c.construir()!;
      expect(out.reglas, isEmpty);
      expect(out.preciosBase, const {'USD': 25.0});
    });

    test(
      'conserva aplica_precio_ida_vuelta_todos con la casilla oculta',
      () {
        // El servicio no es transporte en ómnibus: el editor NO pinta la casilla.
        // Al guardar precios, el valor ya guardado no puede cambiar.
        final c = _ctrl(
          ConfigPrecio(
            monedas: const ['USD'],
            preciosBase: const {'USD': 25},
            aplicaPrecioIdaVueltaTodos: true,
          ),
        );

        final out = c.construir()!;
        expect(out.aplicaPrecioIdaVueltaTodos, isTrue);
        expect(out.toJson()['aplica_precio_ida_vuelta_todos'], isTrue);
      },
    );

    test('una moneda_default que no está habilitada cae a la primera', () {
      // Caso real: CUP se deshabilitó en otro dispositivo y quedó como default.
      final c = _ctrl(
        ConfigPrecio(
          monedaDefault: 'CUP',
          monedas: const ['USD', 'EUR'],
          preciosBase: const {'USD': 10},
        ),
      );

      final out = c.construir()!;
      expect(out.monedaDefault, 'USD');
      expect(out.monedas, const ['USD', 'EUR']);
    });

    test('un precio ilegible devuelve null y no guarda nada', () {
      final c = _ctrl(ConfigPrecio(monedas: const ['USD']));
      c.editarPrecioBase('USD', 'mil');

      expect(c.construir(), isNull);
      expect(c.error, 'Precio base inválido para USD');
    });
  });

  group('verificación · riesgo conocido: regla huérfana al resincronizar', () {
    // CARACTERIZACIÓN (no es un contrato): si el campo de una regla desaparece
    // de `camposSelect`, la resincronización borra los precios de sus opciones y
    // la regla deja de guardarse. Es el comportamiento que ya tenía el
    // formulario, pero la pestaña «Precios» lo dispara con solo ABRIRLA (el tile
    // de la regla llama a `syncCampo` en su `initState`). Si se corrige, este
    // test debe cambiar: está aquí para que el fallo sea visible.
    test('actualizarCamposSelect sin el campo tira los precios de la regla', () {
      final c = _ctrl(
        ConfigPrecio(
          monedas: const ['USD'],
          preciosBase: const {'USD': 25},
          reglas: [
            ReglaPrecio(
              siClave: 'talla',
              preciosOpcion: const {
                'M': {'USD': 40.0},
              },
            ),
          ],
        ),
        campos: const [
          (slug: 'talla', clave: 'talla', etiqueta: 'Talla', opciones: ['M']),
        ],
      );

      // Sigue el campo: la regla conserva sus precios.
      c.actualizarCamposSelect(const [
        (slug: 'talla', clave: 'talla', etiqueta: 'Talla', opciones: ['M']),
      ]);
      expect(c.construir()!.reglas, hasLength(1));

      // Desaparece el campo (se borró/cambió de tipo): la regla se vacía.
      c.actualizarCamposSelect(const []);
      expect(c.construir()!.reglas, isEmpty);
    });
  });

  group('verificación · ciclo de vida', () {
    test('dispose() cancela el debounce y deja el controlador inerte', () async {
      final c = PreciosServicioControlador(
        configInicial: ConfigPrecio(
          monedas: const ['USD', 'CUP'],
          preciosBase: const {'USD': 25},
        ),
      );
      // Configuración de la entidad con cálculo automático: editar programa un
      // Timer de 700 ms que intentaría ir a la red.
      c.actualizarConfigEntidad(const PrecioConfig(autoActivo: true));
      c.editarPrecioBase('USD', '30');

      c.dispose();

      // Ningún mutador puede lanzar ni notificar sobre un ChangeNotifier muerto.
      expect(() {
        c.editarPrecioBase('USD', '31');
        c.toggleMoneda('CUP', false);
        c.cambiarMonedaDefault('CUP');
        c.agregarRegla();
        c.quitarRegla(0);
        c.marcarEditado();
        c.marcarComoGuardado();
        c.actualizarCamposSelect(const []);
        c.actualizarConfigEntidad(const PrecioConfig());
        c.editarIdaVuelta(true);
      }, returnsNormally);

      // Si el Timer no se hubiera cancelado en `dispose()`, a los 700 ms
      // intentaría tocar el controlador ya dispuesto (y en la app, la red).
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
  });

  group('verificación · editor (widget)', () {
    Future<void> montar(
      WidgetTester tester,
      PreciosServicioControlador c, {
      bool anchors = false,
      bool transporte = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PreciosServicioEditor(
                controlador: c,
                conAnchorsTutorial: anchors,
                esTransporteOmnibus: transporte,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('conAnchorsTutorial: true registra los 3 anchors una sola vez', (
      tester,
    ) async {
      final c = PreciosServicioControlador();
      addTearDown(c.dispose);

      await montar(tester, c, anchors: true);

      final ids = tester
          .widgetList<TutorialAnchor>(find.byType(TutorialAnchor))
          .map((a) => a.id)
          .toList();
      expect(ids, hasLength(3));
      expect(ids, containsAll(<String>[
        'admin_precio',
        'admin_precio_auto',
        'admin_reglas_precio',
      ]));
      expect(ids.toSet(), hasLength(3), reason: 'ningún id duplicado');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sin conAnchorsTutorial no registra ningún anchor', (
      tester,
    ) async {
      final c = PreciosServicioControlador();
      addTearDown(c.dispose);

      // Es lo que hace la pestaña «Precios»: si registrara anchors, pisaría al
      // tutorial del formulario (mismos ids en dos pantallas vivas).
      await montar(tester, c);

      expect(find.byType(TutorialAnchor), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('quitar la moneda base no rompe el desplegable ni la base', (
      tester,
    ) async {
      final c = _ctrl(
        ConfigPrecio(
          monedaDefault: 'CUP',
          monedas: const ['USD', 'CUP'],
          preciosBase: const {'USD': 25, 'CUP': 2500},
        ),
      );

      await montar(tester, c);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilterChip, 'CUP — Peso cubano'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // El DropdownButtonFormField no puede quedarse con un valor que ya no
      // está entre sus items (asserción de Flutter).
      expect(tester.takeException(), isNull);
      expect(c.construir()!.monedaDefault, 'USD');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'abrir el editor con una regla huérfana borra sus precios (riesgo)',
      (tester) async {
        final c = _ctrl(
          ConfigPrecio(
            monedas: const ['USD'],
            preciosBase: const {'USD': 25},
            reglas: [
              ReglaPrecio(
                siClave: 'campo_borrado',
                preciosOpcion: const {
                  'M': {'USD': 40.0},
                },
              ),
            ],
          ),
          // El host no encuentra el campo: es el caso de la pestaña Precios con
          // un dato adicional borrado o convertido a texto.
          campos: const [],
        );

        // Antes de pintarse, la regla tiene su precio cargado en memoria.
        await montar(tester, c);
        await tester.pump();

        // El tile de la regla llama a `syncCampo` en `initState` con opciones
        // vacías: se lleva por delante los precios y la regla ya no se guarda.
        // Un guardado de SOLO precios (pestaña) la elimina sin avisar.
        expect(c.construir()!.reglas, isEmpty);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('la casilla de ida y vuelta solo se pinta en transporte', (
      tester,
    ) async {
      final c = _ctrl(
        ConfigPrecio(
          monedas: const ['USD'],
          preciosBase: const {'USD': 25},
          aplicaPrecioIdaVueltaTodos: true,
        ),
      );

      await montar(tester, c, transporte: false);
      expect(find.byType(CheckboxListTile), findsNothing);
      // Aunque no se vea, el valor guardado se conserva al construir.
      expect(c.construir()!.aplicaPrecioIdaVueltaTodos, isTrue);

      await montar(tester, c, transporte: true);
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });
  });
}