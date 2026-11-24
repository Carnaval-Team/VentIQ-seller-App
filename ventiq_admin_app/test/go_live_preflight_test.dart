// Contrato del Go Live (fase 4 del alta progresiva).
//
// Lo que se rompe en silencio aquí es la regla de negocio: **cuatro esenciales
// bloquean, el resto no**. Si alguien la invierte, el cliente vuelve a ver el
// producto como roto y abandona, que es justo lo que este trabajo evita.
//
// El veredicto final lo da el servidor (`fn_m01_activar_tienda`); estas pruebas
// cubren el preflight que lo explica y el cableado del botón.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/onboarding_tareas.dart';
import 'package:ventiq_admin_app/screens/go_live_sheet.dart';

/// Tareas de una tienda retail con los cuatro esenciales resueltos salvo los
/// que se pidan pendientes.
List<TareaOnboarding> tareasRetail({
  Set<String> pendientes = const {},
  bool conAvisos = false,
}) {
  final hechos = HechosTienda(
    tieneAlmacen: !pendientes.contains('almacen'),
    tieneZona: !pendientes.contains('zona'),
    tieneTpv: !pendientes.contains('tpv'),
    tieneProducto: !pendientes.contains('producto'),
    tieneVendedorAsignado: !pendientes.contains('cobro'),
    tienePersonal: conAvisos || !pendientes.contains('personal'),
  );
  return construirTareas(tipoNegocio: 'retail', hechos: hechos);
}

void main() {
  group('preflight: los 4 esenciales bloquean', () {
    for (final clave in ['almacen', 'tpv', 'producto', 'cobro']) {
      testWidgets('sin $clave no se puede activar', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: GoLiveSheet(
                  tareas: tareasRetail(pendientes: {clave}),
                  activar: () async => {'success': true},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // El botón de activar está deshabilitado.
        final boton = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Activar tienda'),
        );
        expect(
          boton.onPressed,
          isNull,
          reason: 'sin $clave el Go Live no puede permitir activar',
        );
        // Y se explica qué falta, con el motivo visible.
        expect(find.textContaining('imprescindible'), findsWidgets);
      });
    }

    testWidgets('una tarea obligatoria omitida tampoco deja activar', (
      tester,
    ) async {
      final tareas = tareasRetail(pendientes: {'almacen'});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoLiveSheet(tareas: tareas, activar: () async => {'success': true}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(puedeActivar(tareas), isFalse);
      final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Activar tienda'),
      );
      expect(boton.onPressed, isNull);
    });
  });

  group('preflight: lo no esencial solo avisa', () {
    testWidgets('con los 4 esenciales se activa aunque falten zonas', (
      tester,
    ) async {
      final tareas = tareasRetail(pendientes: {'zona'});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoLiveSheet(tareas: tareas, activar: () async => {'success': true}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(puedeActivar(tareas), isTrue);
      final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Activar tienda'),
      );
      expect(
        boton.onPressed,
        isNotNull,
        reason: 'una zona pendiente no puede impedir vender',
      );
      // Se avisa, no se bloquea.
      expect(find.textContaining('dejar para después'), findsWidgets);
    });

    testWidgets('activar con advertencias cierra el diálogo con true', (
      tester,
    ) async {
      var llamadas = 0;
      bool? resultado;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    resultado = await showDialog<bool>(
                      context: context,
                      builder: (_) => GoLiveSheet(
                        tareas: tareasRetail(pendientes: {'zona'}),
                        activar: () async {
                          llamadas++;
                          return {'success': true};
                        },
                      ),
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activar tienda'));
      await tester.pumpAndSettle();

      expect(llamadas, 1, reason: 'llama al backend una sola vez');
      expect(resultado, isTrue, reason: 'el diálogo devuelve que activó');
      expect(find.text('Activar tienda'), findsNothing);
    });
  });

  group('preflight: el servidor manda', () {
    testWidgets('si el servidor falla, el diálogo no se cierra y avisa', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoLiveSheet(
              tareas: tareasRetail(),
              activar: () async => {
                'success': false,
                'mensaje': 'falta un vendedor asignado a la caja',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Activar tienda'));
      await tester.pumpAndSettle();

      // El veredicto del servidor no se pisa con el preflight del cliente.
      expect(
        find.textContaining('falta un vendedor'),
        findsOneWidget,
        reason: 'el error del servidor debe verse, no tragarse',
      );
      expect(find.text('Activar tienda'), findsOneWidget);
    });

    testWidgets('el resumen usa los conteos del servidor, no los del cliente', (
      tester,
    ) async {
      // Regresión real: `fn_m01_activar_tienda` devuelve `resumen` como objeto
      // ANIDADO en la raíz (`{success, resumen: {almacenes: 1, ...}}`), no bajo
      // `data` ni plano. Leerlo mal dejaba la tabla entera en «Sin configurar»
      // después de una activación correcta.
      //
      // Se prueba por el camino que mantiene el diálogo abierto: una activación
      // fallida también trae `resumen`, y ahí sí se puede leer la tabla.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoLiveSheet(
              tareas: tareasRetail(),
              // El cliente cree que hay 0; el servidor dice 3. Manda el servidor.
              resumenInicial: const {'almacenes': 0},
              activar: () async => {
                'success': false,
                'mensaje': 'no se pudo activar',
                'resumen': {
                  'almacenes': 3,
                  'tpvs': 2,
                  'productos': 17,
                  'vendedores': 4,
                  'trabajadores': 6,
                  'tipo_negocio': 'retail',
                },
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Activar tienda'));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget, reason: 'almacenes del servidor');
      expect(find.text('17'), findsOneWidget, reason: 'productos del servidor');
      expect(
        find.text('Sin configurar'),
        findsNothing,
        reason: 'con conteos del servidor la tabla no puede quedar vacía',
      );
    });

    testWidgets('sin respuesta del servidor no inventa ceros', (tester) async {
      // Antes de activar solo hay lo que trajo la pantalla. Si no trajo nada, la
      // tabla se deriva del estado de las tareas: una tarea completada dice
      // «Configurado», y una pendiente dice «Sin configurar». Nunca un «0»,
      // porque un cero es una afirmación y aquí no se ha contado nada.
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoLiveSheet(
              // Almacén hecho, el resto pendiente: mezcla de los dos estados.
              tareas: tareasRetail(pendientes: {'tpv', 'producto', 'cobro'}),
              resumenInicial: const {},
              activar: () async => {'success': true},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Configurado'),
        findsWidgets,
        reason: 'lo que ya está hecho se muestra como configurado',
      );
      expect(
        find.text('Sin configurar'),
        findsWidgets,
        reason: 'lo pendiente se muestra como sin configurar',
      );
      expect(find.text('0'), findsNothing);
    });
  });
}
