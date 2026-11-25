// Humo de UI de la pantalla de activación (fase 3 del plan
// `docs/plans/alta-tienda-progresiva-go-live.md`).
//
// Monta `OnboardingChecklistVista`, que es la parte visual y **no importa
// ningún servicio**: recibe las tareas ya calculadas por el modelo puro. Por eso
// esta prueba no inicializa Supabase ni toca la red —`ActivacionTiendaScreen`
// solo envuelve esta vista con las consultas—.
//
// Qué se comprueba, que es lo que se rompe en silencio:
//   1. A 390 px (móvil real) no hay overflow ni ninguna excepción de layout.
//   2. El contador es el neutro «X de Y pasos completados», nunca «te faltan N».
//   3. Una tarea bloqueada NO es tocable y muestra su motivo; una accionable sí
//      es tocable y navega.
//   4. Mientras carga no se pintan ceros ni una lista vacía.
//   5. En ancho (>900) el contenido se centra con ancho máximo, sin desbordar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/onboarding_tareas.dart';
import 'package:ventiq_admin_app/widgets/onboarding_checklist_vista.dart';
import 'package:ventiq_admin_app/widgets/onboarding_burbuja.dart';
import 'package:ventiq_admin_app/widgets/onboarding_tarea_tile.dart';

/// Tareas equivalentes a una tienda retail sin nada configurado: 4 obligatorias
/// pendientes, 2 opcionales pendientes.
List<TareaOnboarding> _tareasRetail() => construirTareas(
  tipoNegocio: 'retail',
  hechos: const HechosTienda(),
);

/// Tareas de un restaurante sin almacén convertible: la cocina sale bloqueada
/// con el motivo a la vista (caso real 1 almacén + 1 TPV).
List<TareaOnboarding> _tareasRestauranteConCocinaBloqueada() =>
    construirTareas(
      tipoNegocio: 'restaurante',
      hechos: const HechosTienda(modoRestaurante: true),
    );

void _tamano(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _vista({
  required List<TareaOnboarding> tareas,
  String? tipoNegocio = 'retail',
  bool cargando = false,
  String? error,
  bool descartado = false,
  ValueChanged<TareaOnboarding>? onAbrirTarea,
  ValueChanged<String>? onElegirTipo,
  VoidCallback? onReintentar,
  VoidCallback? onDescartar,
  VoidCallback? onRecuperar,
}) {
  return MaterialApp(
    home: OnboardingChecklistVista(
      tareas: tareas,
      tipoNegocio: tipoNegocio,
      cargando: cargando,
      error: error,
      descartado: descartado,
      onAbrirTarea: onAbrirTarea,
      onElegirTipoNegocio: onElegirTipo,
      onReintentar: onReintentar,
      onDescartar: onDescartar,
      onRecuperar: onRecuperar,
    ),
  );
}

void main() {
  group('móvil 390x844', () {
    testWidgets('no desborda y muestra el contador neutro', (tester) async {
      _tamano(tester, const Size(390, 844));
      await tester.pumpWidget(_vista(tareas: _tareasRetail()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Pon tu tienda en marcha'), findsWidgets);
      // Contador neutro: cuenta lo hecho, no lo que falta. El total sale del
      // modelo (`progreso`), no se escribe a mano.
      final esperado = textoProgreso(_tareasRetail());
      expect(esperado, startsWith('0 de '));
      expect(find.text(esperado), findsOneWidget);
      expect(find.textContaining('te faltan'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      // Las 4 obligatorias del plan están en pantalla.
      for (final clave in ['almacen', 'tpv', 'producto', 'cobro']) {
        expect(
          find.byKey(OnboardingTareaTile.claveTarea(clave)),
          findsOneWidget,
          reason: 'falta la tarea $clave',
        );
      }
    });

    testWidgets('una tarea bloqueada no es tocable; una accionable sí', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      final abiertas = <String>[];
      final tareas = _tareasRestauranteConCocinaBloqueada();

      await tester.pumpWidget(
        _vista(
          tareas: tareas,
          tipoNegocio: 'restaurante',
          onAbrirTarea: (t) => abiertas.add(t.clave),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      // La cocina está bloqueada: sin enlace y con el motivo visible.
      final cocina = tareas.firstWhere((t) => t.clave == 'cocina');
      expect(cocina.bloqueada, isTrue, reason: 'la cocina debería bloquearse');
      expect(
        find.byKey(OnboardingTareaTile.claveTarea('cocina')),
        findsOneWidget,
      );
      expect(find.textContaining('ALMACEN_ES_DE_TPV'), findsOneWidget);

      // Tocarla no navega.
      await tester.tap(
        find.byKey(OnboardingTareaTile.claveTarea('cocina')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(abiertas, isEmpty, reason: 'una bloqueada no debe navegar');

      // La de almacén sí es accionable. Hay que llevarla a la vista primero:
      // con las tareas de datos de la tienda (nombre, dirección, ubicación)
      // delante, en 390 px queda fuera del viewport.
      final almacen = tareas.firstWhere((t) => t.clave == 'almacen');
      expect(almacen.accionable, isTrue);
      await tester.scrollUntilVisible(
        find.byKey(OnboardingTareaTile.claveTarea('almacen')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(OnboardingTareaTile.claveTarea('almacen')));
      await tester.pump();
      expect(abiertas, contains('almacen'));

      // Y la informativa de mesas tampoco navega (ruta nula por diseño).
      final mesas = tareas.firstWhere((t) => t.clave == 'mesas_restaurante');
      expect(mesas.ruta, isNull);
      await tester.tap(
        find.byKey(OnboardingTareaTile.claveTarea('mesas_restaurante')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(abiertas, isNot(contains('mesas_restaurante')));
    });

    testWidgets('el contador sube cuando hay tareas completadas', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      final tareas = construirTareas(
        tipoNegocio: 'retail',
        hechos: const HechosTienda(
          tieneAlmacen: true,
          tieneTpv: true,
        ),
      );

      await tester.pumpWidget(_vista(tareas: tareas));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final avance = progreso(tareas);
      expect(avance.completadas, 2);
      expect(find.text(textoProgreso(tareas)), findsOneWidget);
      // Las completadas llevan check, no color de alarma.
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    });

    testWidgets('con el tipo sin elegir salen las 4 opciones con su frase', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      final elegidos = <String>[];

      await tester.pumpWidget(
        _vista(
          tareas: _tareasRetail(),
          tipoNegocio: null,
          onElegirTipo: elegidos.add,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('¿Qué tipo de negocio tienes?'), findsOneWidget);
      for (final tipo in tiposNegocioConocidos) {
        expect(
          find.byKey(ValueKey<String>('onboarding_tipo_$tipo')),
          findsOneWidget,
          reason: 'falta la opción $tipo',
        );
      }
      expect(find.text('Restaurante o cafetería'), findsOneWidget);
      expect(find.text('Servicentro'), findsOneWidget);
      expect(find.text('Solo catálogo'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding_tipo_servicentro')),
      );
      await tester.pump();
      expect(elegidos, contains('servicentro'));
    });

    testWidgets('con el tipo elegido se muestra como texto y se puede cambiar', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      final elegidos = <String>[];
      await tester.pumpWidget(
        _vista(tareas: _tareasRetail(), onElegirTipo: elegidos.add),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Tienda o bodega'), findsOneWidget);
      expect(find.text('¿Qué tipo de negocio tienes?'), findsNothing);

      await tester.tap(find.byKey(const Key('onboarding_cambiar_tipo')));
      await tester.pump();
      expect(find.text('¿Qué tipo de negocio tienes?'), findsOneWidget);
      // Cambiar de tipo llama al callback del servicio con el nuevo valor.
      await tester.tap(
        find.byKey(const ValueKey<String>('onboarding_tipo_restaurante')),
      );
      await tester.pump();
      expect(elegidos, contains('restaurante'));
    });
  });

  group('estados de carga y error', () {
    testWidgets('cargando: spinner y ninguna cifra', (tester) async {
      _tamano(tester, const Size(390, 844));
      await tester.pumpWidget(
        _vista(tareas: const [], cargando: true),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Ni contador ni lista mientras carga: el antipatrón documentado.
      expect(find.textContaining('pasos completados'), findsNothing);
      expect(find.text('Lo que falta'), findsNothing);
      expect(find.textContaining('0 de 0'), findsNothing);
    });

    testWidgets('error: mensaje con reintento, sin lista ni ceros', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));
      var reintentos = 0;

      await tester.pumpWidget(
        _vista(
          tareas: const [],
          error: 'Se cayó la conexión.',
          onReintentar: () => reintentos++,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('No se pudo cargar el checklist'), findsOneWidget);
      expect(find.text('Se cayó la conexión.'), findsOneWidget);
      expect(find.text('Lo que falta'), findsNothing);
      expect(find.textContaining('pasos completados'), findsNothing);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(reintentos, 1);
    });

    testWidgets('descartado: banner con la opción de recuperar', (tester) async {
      _tamano(tester, const Size(390, 844));
      var recuperados = 0;

      await tester.pumpWidget(
        _vista(
          tareas: _tareasRetail(),
          descartado: true,
          onRecuperar: () => recuperados++,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('checklist descartado'), findsOneWidget);
      // Descartar no borra las tareas.
      expect(find.byKey(OnboardingTareaTile.claveTarea('almacen')), findsOneWidget);

      await tester.tap(find.text('Recuperar'));
      await tester.pump();
      expect(recuperados, 1);
    });

    testWidgets('la X de la cabecera descarta', (tester) async {
      _tamano(tester, const Size(390, 844));
      var descartado = 0;

      await tester.pumpWidget(
        _vista(tareas: _tareasRetail(), onDescartar: () => descartado++),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('onboarding_descartar')));
      await tester.pump();
      expect(descartado, 1);
    });
  });

  // La tarjeta del dashboard se sustituyó por la burbuja flotante
  // (`onboarding_burbuja.dart`); sus pruebas viven en `onboarding_burbuja_test.dart`
  // y `onboarding_ubicacion_test.dart`. Aquí se dejaba una prueba de la tarjeta
  // que ya no existe.

  group('pantalla ancha', () {
    testWidgets('a 1280 el contenido se centra con ancho máximo', (
      tester,
    ) async {
      _tamano(tester, const Size(1280, 900));
      await tester.pumpWidget(_vista(tareas: _tareasRetail()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text(textoProgreso(_tareasRetail())), findsOneWidget);

      // El bloque de contenido no pasa del ancho máximo declarado.
      final ancho = tester.getSize(
        find.byKey(OnboardingTareaTile.claveTarea('almacen')),
      );
      expect(ancho.width, lessThanOrEqualTo(activacionAnchoMaximo));
      // Y queda centrado: sobran márgenes a los dos lados.
      final origen = tester.getTopLeft(
        find.byKey(OnboardingTareaTile.claveTarea('almacen')),
      );
      expect(origen.dx, greaterThan(100));
    });

    testWidgets('todos los tipos de negocio caben sin desbordar a 390', (
      tester,
    ) async {
      for (final tipo in tiposNegocioConocidos) {
        _tamano(tester, const Size(390, 844));
        await tester.pumpWidget(
          _vista(
            tareas: construirTareas(
              tipoNegocio: tipo,
              hechos: const HechosTienda(),
            ),
            tipoNegocio: tipo,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'desborda en $tipo');
      }
    });
  });
}
