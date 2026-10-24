import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/utils/shell_navegacion.dart';
import 'package:inventtia_flow/widgets/barra_navegacion_cliente.dart';

void _sinSeleccion(int _) {}

void main() {
  setUp(ShellNavegacion.limpiar);
  tearDown(ShellNavegacion.limpiar);

  group('ShellNavegacion', () {
    test('sin shell detrás no se pinta la barra', () {
      expect(ShellNavegacion.disponible, isFalse);
      // Antes que una barra que no lleva a ningún sitio (un test, una vista
      // previa), ninguna: `bottomNavigationBar` admite null.
      expect(BarraNavegacionCliente.dePantalla(), isNull);
    });

    test('con el shell registrado la barra de pantalla existe', () {
      ShellNavegacion.registrar(_sinSeleccion);
      expect(ShellNavegacion.disponible, isTrue);
      expect(BarraNavegacionCliente.dePantalla(), isNotNull);
    });

    test('al limpiar se deja de ofrecer', () {
      ShellNavegacion.registrar(_sinSeleccion);
      ShellNavegacion.limpiar();
      expect(ShellNavegacion.disponible, isFalse);
      expect(BarraNavegacionCliente.dePantalla(), isNull);
    });
  });

  group('BarraNavegacionCliente', () {
    testWidgets('pinta las cinco pestañas del cliente', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: BarraNavegacionCliente(
              onSeleccion: _sinSeleccion,
              pendientesReservas: 0,
            ),
          ),
        ),
      );

      for (final etiqueta in <String>[
        'Inicio',
        'Servicios',
        'Mis Listas',
        'Reservas',
        'Perfil',
      ]) {
        expect(find.text(etiqueta), findsOneWidget, reason: etiqueta);
      }
    });

    testWidgets('marca la pestaña que se le pide', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: BarraNavegacionCliente(
              onSeleccion: _sinSeleccion,
              pendientesReservas: 0,
              indiceActivo: ShellNavegacion.inicio,
            ),
          ),
        ),
      );

      final barra = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(barra.selectedIndex, ShellNavegacion.inicio);
    });

    testWidgets('el badge de reservas cuenta lo que le pasan y se puede apagar', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: BarraNavegacionCliente(
              onSeleccion: _sinSeleccion,
              pendientesReservas: 3,
            ),
          ),
        ),
      );
      expect(find.text('3'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: BarraNavegacionCliente(
              onSeleccion: _sinSeleccion,
              pendientesReservas: 3,
              mostrarBadgeReservas: false,
            ),
          ),
        ),
      );
      expect(find.text('3'), findsNothing);
    });

    testWidgets('avisa al shell con el índice tocado', (tester) async {
      final tocadas = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: BarraNavegacionCliente(
              onSeleccion: tocadas.add,
              pendientesReservas: 0,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mis Listas'));
      await tester.pump();

      expect(tocadas, <int>[ShellNavegacion.misListas]);
    });

    testWidgets('sin callback cierra lo apilado y pide la pestaña', (
      tester,
    ) async {
      final pedidas = <int>[];
      ShellNavegacion.registrar(pedidas.add);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: const Center(child: Text('Vista apilada')),
                        bottomNavigationBar: BarraNavegacionCliente(
                          pendientesReservas: 0,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.text('Vista apilada'), findsOneWidget);

      await tester.tap(find.text('Servicios'));
      await tester.pumpAndSettle();

      // Vuelve al shell (la ruta apilada desaparece) y le pide la pestaña.
      expect(find.text('Vista apilada'), findsNothing);
      expect(pedidas, <int>[ShellNavegacion.servicios]);
    });
  });
}