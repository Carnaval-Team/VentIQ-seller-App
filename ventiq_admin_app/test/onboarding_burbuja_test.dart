// Contrato de la burbuja flotante de activación (estilo Stripe).
//
// Cada prueba de aquí corresponde a un defecto reportado al usarla:
//
//  1. Al entrar con una tienda sin terminar salía el checklist **a pantalla
//     completa**, sin dashboard. Debía ser un aviso flotante abajo a la derecha.
//  2. Cerrarlo obligaba a volver a iniciar sesión para verlo otra vez.
//  3. Faltaban los datos del paso 2 del asistente (nombre, dirección, ubicación).
//  4. «Quién cobra en tu caja» llevaba a la pantalla de TPVs, donde no se crea
//     ninguna persona.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/onboarding_tareas.dart';
import 'package:ventiq_admin_app/widgets/onboarding_burbuja.dart';

/// Tareas de una tienda retail recién creada: los datos del paso 2 vacíos y lo
/// demás por hacer.
List<TareaOnboarding> tareasNuevas({bool conDatosDeTienda = false}) {
  return construirTareas(
    tipoNegocio: 'retail',
    hechos: HechosTienda(
      tieneNombreTienda: conDatosDeTienda,
      tieneDireccion: conDatosDeTienda,
      tieneUbicacion: conDatosDeTienda,
    ),
  );
}

/// Monta la burbuja dentro de un `Scaffold` que hace de dashboard.
///
/// El tamaño se fija con `tester.view`, no con `MediaQuery`: `Positioned` se
/// ancla al lienzo real de la vista, y un `MediaQuery` distinto solo cambiaría
/// lo que lee el widget sin mover el viewport. Con `MediaQuery` el botón seguía
/// apareciendo en el borde de 800×600 y las pruebas de posición mentían.
Widget conDashboard({
  required List<TareaOnboarding> tareas,
  bool abierto = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          const Center(child: Text('DASHBOARD')),
          OnboardingBurbuja(
            tareasIniciales: tareas,
            estadoInicial: 'borrador',
            abiertoInicial: abierto,
          ),
        ],
      ),
    ),
  );
}

/// Fija la ventana de la prueba. Devuelve el tamaño para las comprobaciones.
void fijarVentana(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('punto 1: es un aviso flotante, no una pantalla', () {
    testWidgets('el dashboard sigue visible debajo del panel', (tester) async {
      await tester.pumpWidget(conDashboard(tareas: tareasNuevas()));
      await tester.pump();

      // El dashboard no se sustituye: se sigue leyendo.
      expect(find.text('DASHBOARD'), findsOneWidget);

      // Y hay un botón flotante que resume lo que falta.
      expect(find.byKey(OnboardingBurbuja.claveBoton), findsOneWidget);
      expect(find.textContaining('por completar'), findsOneWidget);
    });

    testWidgets('el botón está abajo a la derecha', (tester) async {
      const tamano = Size(1200, 900);
      fijarVentana(tester, tamano);
      await tester.pumpWidget(conDashboard(tareas: tareasNuevas()));
      await tester.pump();

      final boton = tester.getRect(find.byKey(OnboardingBurbuja.claveBoton));
      // A menos de 120 px del borde derecho y del inferior.
      expect(boton.right, greaterThan(tamano.width - 120));
      expect(boton.bottom, greaterThan(tamano.height - 120));
      // Y pegado a la esquina, no en el centro.
      expect(boton.left, greaterThan(tamano.width / 2));
    });

    testWidgets('no arranca abierto: es un aviso, no un modal', (tester) async {
      await tester.pumpWidget(conDashboard(tareas: tareasNuevas()));
      await tester.pump();

      expect(find.byKey(OnboardingBurbuja.clavePanel), findsNothing);
    });

    testWidgets('al tocarlo se despliega el panel encima', (tester) async {
      await tester.pumpWidget(conDashboard(tareas: tareasNuevas()));
      await tester.pump();

      await tester.tap(find.byKey(OnboardingBurbuja.claveBoton));
      await tester.pumpAndSettle();

      expect(find.byKey(OnboardingBurbuja.clavePanel), findsOneWidget);
      // El dashboard sigue detrás: el panel no lo reemplaza.
      expect(find.text('DASHBOARD'), findsOneWidget);
    });
  });

  group('punto 2: cerrar no borra nada ni exige volver a entrar', () {
    testWidgets('cerrar el panel lo aparta pero deja el botón', (tester) async {
      fijarVentana(tester, const Size(1200, 900));
      await tester.pumpWidget(
        conDashboard(tareas: tareasNuevas(), abierto: true),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(OnboardingBurbuja.clavePanel), findsOneWidget);

      await tester.tap(find.byKey(OnboardingBurbuja.claveCerrarPanel));
      await tester.pumpAndSettle();

      expect(find.byKey(OnboardingBurbuja.clavePanel), findsNothing);
      // Lo importante: el acceso sigue ahí sin reiniciar sesión.
      expect(find.byKey(OnboardingBurbuja.claveBoton), findsOneWidget);
    });

    testWidgets('se vuelve a abrir sin perder nada', (tester) async {
      fijarVentana(tester, const Size(1200, 900));
      await tester.pumpWidget(
        conDashboard(tareas: tareasNuevas(), abierto: true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(OnboardingBurbuja.claveCerrarPanel));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OnboardingBurbuja.claveBoton));
      await tester.pumpAndSettle();

      expect(find.byKey(OnboardingBurbuja.clavePanel), findsOneWidget);
      expect(find.textContaining('de'), findsWidgets);
    });

    testWidgets('una tienda ya activa no pinta ni botón ni panel', (
      tester,
    ) async {
      fijarVentana(tester, const Size(1200, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Center(child: Text('DASHBOARD')),
                OnboardingBurbuja(
                  tareasIniciales: tareasNuevas(conDatosDeTienda: true),
                  estadoInicial: 'activa',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(OnboardingBurbuja.claveBoton), findsNothing);
    });
  });

  group('punto 3: los datos del paso 2 aparecen en el checklist', () {
    test('una tienda nueva tiene pendientes nombre, dirección y ubicación', () {
      final tareas = tareasNuevas();
      final claves = tareas.map((t) => t.clave).toList();

      expect(claves, contains('nombre_tienda'));
      expect(claves, contains('direccion'));
      expect(claves, contains('ubicacion'));

      for (final clave in ['nombre_tienda', 'direccion', 'ubicacion']) {
        final tarea = tareas.firstWhere((t) => t.clave == clave);
        expect(
          tarea.estado,
          EstadoTarea.pendiente,
          reason: '$clave debería estar pendiente en una tienda recién creada',
        );
        expect(
          tarea.enPanel,
          isTrue,
          reason: '$clave se pide en el panel, sin salir a otra pantalla',
        );
      }
    });

    test('con los datos puestos, las tres quedan completadas', () {
      final tareas = tareasNuevas(conDatosDeTienda: true);
      for (final clave in ['nombre_tienda', 'direccion', 'ubicacion']) {
        expect(
          tareas.firstWhere((t) => t.clave == clave).estado,
          EstadoTarea.completada,
        );
      }
    });

    test('no bloquean el Go Live: se puede vender sin dirección', () {
      final tareas = tareasNuevas();
      final conDatos = tareasNuevas(conDatosDeTienda: true);
      // Sin datos de tienda pero con todo lo esencial…
      final esenciales = tareas
          .map(
            (t) => t.clave == 'nombre_tienda' ||
                    t.clave == 'direccion' ||
                    t.clave == 'ubicacion'
                ? TareaOnboarding(
                    clave: t.clave,
                    titulo: t.titulo,
                    beneficio: t.beneficio,
                    obligatoria: t.obligatoria,
                    estado: EstadoTarea.completada,
                    enPanel: t.enPanel,
                    campoPanel: t.campoPanel,
                  )
                : t,
          )
          .toList();
      expect(tareas, isNotEmpty);
      expect(conDatos, isNotEmpty);
      // Ninguna de las tres es obligatoria.
      for (final t in esenciales) {
        if (['nombre_tienda', 'direccion', 'ubicacion'].contains(t.clave)) {
          expect(t.obligatoria, isFalse);
        }
      }
    });
  });

  group('punto 4: quién cobra se resuelve creando un trabajador', () {
    test('la tarea de cobro se pide en el panel, no navegando a TPVs', () {
      final tareas = tareasNuevas();
      final cobro = tareas.firstWhere((t) => t.clave == 'cobro');

      expect(
        cobro.ruta,
        isNull,
        reason: 'mandarla a /tpv-management era el error: allí no se crea gente',
      );
      expect(cobro.enPanel, isTrue);
      expect(cobro.campoPanel, 'cobro');
      // Sigue siendo obligatoria: sin quién cobre no hay venta.
      expect(cobro.obligatoria, isTrue);
    });

    test('el beneficio nombra el rol Dependiente y el usuario de acceso', () {
      final cobro = tareasNuevas().firstWhere((t) => t.clave == 'cobro');
      expect(cobro.beneficio, contains('Dependiente'));
      expect(cobro.beneficio.toLowerCase(), contains('usuario'));
    });
  });

  group('reglas que no deben romperse', () {
    test('tachar lo hecho: una completada no es accionable', () {
      final tareas = tareasNuevas(conDatosDeTienda: true);
      final nombre = tareas.firstWhere((t) => t.clave == 'nombre_tienda');
      expect(nombre.estado, EstadoTarea.completada);
      expect(
        nombre.accionable,
        isFalse,
        reason: 'lo ya hecho no debe ofrecer acción',
      );
    });

    test('una tarea en el panel no puede además navegar', () {
      expect(
        () => TareaOnboarding(
          clave: 'x',
          titulo: 'x',
          beneficio: 'x',
          obligatoria: false,
          estado: EstadoTarea.pendiente,
          ruta: '/algo',
          enPanel: true,
          campoPanel: 'nombre',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('una tarea en el panel tiene que decir qué campo la resuelve', () {
      expect(
        () => TareaOnboarding(
          clave: 'x',
          titulo: 'x',
          beneficio: 'x',
          obligatoria: false,
          estado: EstadoTarea.pendiente,
          enPanel: true,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('el catálogo tampoco se libra de los datos de tienda', () {
      final tareas = construirTareas(
        tipoNegocio: 'catalogo',
        hechos: const HechosTienda(),
      );
      final claves = tareas.map((t) => t.clave);
      expect(claves, contains('nombre_tienda'));
      expect(claves, contains('direccion'));
    });
  });
}
