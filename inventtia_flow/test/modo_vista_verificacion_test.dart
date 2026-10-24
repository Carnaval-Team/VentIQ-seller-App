// Verificación INDEPENDIENTE del conmutador de vista admin ↔ cliente (F15).
//
// Qué fija este fichero
//   1. La matriz completa de `vistaDelShell` (las 8 combinaciones de
//      admin/vendedor/comoCliente), con el caso feo incluido: un **vendedor puro
//      con el interruptor encendido por error** tiene que seguir viendo su vista
//      de trabajo, no la del cliente.
//   2. `ModoVistaProvider`: estado inicial, transiciones, `alternar` y —lo que
//      más se rompe en un `ChangeNotifier`— que `notifyListeners` **solo** se
//      dispare cuando el valor cambia de verdad.
//   3. `esVistaCliente` y `puedeVerComoCliente`.
//   4. Un widget test que monta un árbol como el del shell (provider del modo +
//      `EntidadProvider` con los dos booleanos de rol) y comprueba que la
//      decisión **se repinta** al cambiar el modo, por las dos vías que usa el
//      shell real: `ListenableBuilder` y `context.watch`.
//
// Qué NO hace (y por qué)
//   No monta `HomeShell`, `PerfilScreen` ni `GestionScreen`: las tres leen
//   `AuthProvider` y/o `AuthService`, que sin `Supabase.initialize` lanzan al
//   instante (`AuthService._supabase` es un `SupabaseClient` estático sacado de
//   `Supabase.instance`). Montarlas exigiría levantar Supabase de mentira, que
//   este encargo prohíbe («no lo fuerces»). El árbol de aquí reproduce la misma
//   decisión (`vistaDelShell` sobre los dos booleanos del `EntidadProvider`) sin
//   Supabase: verifica la lógica del conmutador, no el pintado de cada pantalla.
//
// Nada de este fichero toca `lib/`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/providers/entidad_provider.dart';
import 'package:inventtia_flow/providers/modo_vista_provider.dart';
import 'package:inventtia_flow/utils/modo_vista.dart';
import 'package:provider/provider.dart';

/// `EntidadProvider` de mentira: solo fija los dos booleanos que decide el
/// shell (`isAdmin` = tengo entidades propias, `isVendedor` = trabajo en las de
/// otros). El real los saca de Supabase; aquí no hay red ni sesión.
class _EntidadProviderFalso extends EntidadProvider {
  _EntidadProviderFalso({required this.admin, required this.vendedor});

  final bool admin;
  final bool vendedor;

  @override
  bool get isAdmin => admin;

  @override
  bool get isVendedor => vendedor;

  @override
  bool get isLoading => false;
}

/// Cuántas veces se ha reconstruido cada sonda. Sirve para comprobar que un
/// `notifyListeners` de más se traduce en un repintado de más (y que uno que no
/// debe llegar, no llega).
class _Contadores {
  int porWatch = 0;
  int porListenableBuilder = 0;
}

/// Sonda que lee el modo con `ListenableBuilder`, como `HomeShell.build`.
class _SondaListenableBuilder extends StatelessWidget {
  const _SondaListenableBuilder({required this.contadores});

  final _Contadores contadores;

  @override
  Widget build(BuildContext context) {
    final entidad = context.watch<EntidadProvider>();
    return ListenableBuilder(
      listenable: context.watch<ModoVistaProvider>(),
      builder: (context, _) {
        contadores.porListenableBuilder++;
        final vista = vistaDelShell(
          esAdmin: entidad.isAdmin,
          esVendedor: entidad.isVendedor,
          comoCliente: context.read<ModoVistaProvider>().comoCliente,
        );
        return Text('lb:${vista.name}');
      },
    );
  }
}

/// Sonda que lee el modo con `context.watch`, como `PerfilScreen`.
class _SondaWatch extends StatelessWidget {
  const _SondaWatch({required this.contadores});

  final _Contadores contadores;

  @override
  Widget build(BuildContext context) {
    contadores.porWatch++;
    final entidad = context.watch<EntidadProvider>();
    final modo = context.watch<ModoVistaProvider>();
    final vista = vistaDelShell(
      esAdmin: entidad.isAdmin,
      esVendedor: entidad.isVendedor,
      comoCliente: modo.comoCliente,
    );
    return Text('watch:${vista.name}');
  }
}

/// Árbol mínimo con lo que el shell pone de verdad alrededor de las pantallas:
/// el `ModoVistaProvider` (con `.value`, igual que `HomeShell`) y un
/// `EntidadProvider` con el rol ya resuelto.
class _Arnes extends StatelessWidget {
  const _Arnes({
    required this.entidad,
    required this.modo,
    required this.contadores,
  });

  final EntidadProvider entidad;
  final ModoVistaProvider modo;
  final _Contadores contadores;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EntidadProvider>.value(value: entidad),
        ChangeNotifierProvider<ModoVistaProvider>.value(value: modo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              _SondaListenableBuilder(contadores: contadores),
              _SondaWatch(contadores: contadores),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      context.read<ModoVistaProvider>().verComoCliente(),
                  child: const Text('entrar'),
                ),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      context.read<ModoVistaProvider>().verComoAdmin(),
                  child: const Text('salir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // 1. `vistaDelShell`: la matriz completa
  // ─────────────────────────────────────────────────────────────────────
  group('vistaDelShell · matriz completa', () {
    /// Las 8 combinaciones posibles, con lo que se espera de cada una.
    ///
    /// `comoCliente` solo lo puede encender un admin; las filas donde va
    /// encendido sin ser admin (y sin ser nada) están aquí a propósito: son el
    /// caso «interruptor fantasma» que no puede dejar a nadie sin su vista.
    const matriz = <({bool admin, bool vendedor, bool comoCliente, VistaShell esperado})>[
      // Cliente puro (ni admin ni vendedor).
      (admin: false, vendedor: false, comoCliente: false, esperado: VistaShell.cliente),
      (admin: false, vendedor: false, comoCliente: true, esperado: VistaShell.cliente),
      // Admin.
      (admin: true, vendedor: false, comoCliente: false, esperado: VistaShell.admin),
      (admin: true, vendedor: false, comoCliente: true, esperado: VistaShell.cliente),
      // Admin que además vende.
      (admin: true, vendedor: true, comoCliente: false, esperado: VistaShell.vendedorAdmin),
      (admin: true, vendedor: true, comoCliente: true, esperado: VistaShell.cliente),
      // Vendedor puro.
      (admin: false, vendedor: true, comoCliente: false, esperado: VistaShell.vendedor),
      // El caso feo: el interruptor encendido por error en un vendedor puro
      // NO puede degradarlo a la vista de cliente (perdería sus Reservas y su
      // Gestión de vendedor).
      (admin: false, vendedor: true, comoCliente: true, esperado: VistaShell.vendedor),
    ];

    for (final caso in matriz) {
      test(
        'admin=${caso.admin} vendedor=${caso.vendedor} comoCliente=${caso.comoCliente} '
        '→ ${caso.esperado.name}',
        () {
          expect(
            vistaDelShell(
              esAdmin: caso.admin,
              esVendedor: caso.vendedor,
              comoCliente: caso.comoCliente,
            ),
            equals(caso.esperado),
          );
        },
      );
    }

    test('los 8 casos están cubiertos y son distintos entre sí', () {
      final combinaciones = matriz
          .map((c) => '${c.admin}-${c.vendedor}-${c.comoCliente}')
          .toSet();
      expect(combinaciones, hasLength(8));
    });

    test('el interruptor solo cambia la vista de quien administra', () {
      for (final admin in [true, false]) {
        for (final vendedor in [true, false]) {
          final sinInterruptor = vistaDelShell(
            esAdmin: admin,
            esVendedor: vendedor,
            comoCliente: false,
          );
          final conInterruptor = vistaDelShell(
            esAdmin: admin,
            esVendedor: vendedor,
            comoCliente: true,
          );
          if (admin) {
            expect(
              conInterruptor,
              equals(VistaShell.cliente),
              reason: 'un admin con el interruptor encendido ve la app de cliente',
            );
          } else {
            expect(
              conInterruptor,
              equals(sinInterruptor),
              reason: 'sin admin el interruptor se ignora',
            );
          }
        }
      }
    });

    test('un admin nunca se queda sin panel: o admin o vendedorAdmin', () {
      for (final vendedor in [true, false]) {
        expect(
          vistaDelShell(esAdmin: true, esVendedor: vendedor, comoCliente: false),
          equals(vendedor ? VistaShell.vendedorAdmin : VistaShell.admin),
        );
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 3. `esVistaCliente` y `puedeVerComoCliente`
  // ─────────────────────────────────────────────────────────────────────
  group('esVistaCliente', () {
    test('solo la vista del cliente pinta la barra de 5 pestañas', () {
      expect(esVistaCliente(VistaShell.cliente), isTrue);
      expect(esVistaCliente(VistaShell.admin), isFalse);
      expect(esVistaCliente(VistaShell.vendedor), isFalse);
      expect(esVistaCliente(VistaShell.vendedorAdmin), isFalse);
    });

    test('coincide con vistaDelShell en las 8 combinaciones', () {
      for (final admin in [true, false]) {
        for (final vendedor in [true, false]) {
          for (final comoCliente in [true, false]) {
            final vista = vistaDelShell(
              esAdmin: admin,
              esVendedor: vendedor,
              comoCliente: comoCliente,
            );
            expect(
              esVistaCliente(vista),
              equals(vista == VistaShell.cliente),
              reason: 'admin=$admin vendedor=$vendedor comoCliente=$comoCliente',
            );
          }
        }
      }
    });
  });

  group('puedeVerComoCliente', () {
    test('solo quien administra una entidad', () {
      expect(puedeVerComoCliente(esAdmin: true), isTrue);
      expect(puedeVerComoCliente(esAdmin: false), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 2. `ModoVistaProvider`
  // ─────────────────────────────────────────────────────────────────────
  group('ModoVistaProvider', () {
    test('arranca apagado (siempre se entra como administrador)', () {
      expect(ModoVistaProvider().comoCliente, isFalse);
    });

    test('verComoCliente enciende una vez y notifica una vez', () {
      final modo = ModoVistaProvider();
      var avisos = 0;
      modo.addListener(() => avisos++);

      modo.verComoCliente();
      expect(modo.comoCliente, isTrue);
      expect(avisos, equals(1));

      // Repetir no cambia nada: no debe notificar (evita repintados de más).
      modo.verComoCliente();
      expect(modo.comoCliente, isTrue);
      expect(avisos, equals(1));
    });

    test('verComoAdmin apaga una vez y notifica una vez', () {
      final modo = ModoVistaProvider()..verComoCliente();
      var avisos = 0;
      modo.addListener(() => avisos++);

      modo.verComoAdmin();
      expect(modo.comoCliente, isFalse);
      expect(avisos, equals(1));

      modo.verComoAdmin();
      expect(modo.comoCliente, isFalse);
      expect(avisos, equals(1));
    });

    test('verComoAdmin con el modo ya apagado no hace nada', () {
      final modo = ModoVistaProvider();
      var avisos = 0;
      modo.addListener(() => avisos++);

      modo.verComoAdmin();
      expect(modo.comoCliente, isFalse);
      expect(avisos, isZero);
    });

    test('alternar cambia y notifica en cada llamada', () {
      final modo = ModoVistaProvider();
      var avisos = 0;
      modo.addListener(() => avisos++);

      modo.alternar();
      expect(modo.comoCliente, isTrue);
      expect(avisos, equals(1));

      modo.alternar();
      expect(modo.comoCliente, isFalse);
      expect(avisos, equals(2));

      modo.alternar();
      expect(modo.comoCliente, isTrue);
      expect(avisos, equals(3));
    });

    test('alternar y las dos puertas dejan el mismo estado final', () {
      final porPuertas = ModoVistaProvider()
        ..verComoCliente()
        ..verComoAdmin()
        ..verComoCliente();
      final porAlternar = ModoVistaProvider()..alternar();

      expect(porPuertas.comoCliente, isTrue);
      expect(porAlternar.comoCliente, porPuertas.comoCliente);
    });

    test('el ida y vuelta avisa exactamente 3 veces', () {
      final modo = ModoVistaProvider();
      var avisos = 0;
      modo.addListener(() => avisos++);

      modo.verComoCliente(); // 1 (false→true)
      modo.verComoCliente(); // sin aviso
      modo.verComoAdmin(); // 2 (true→false)
      modo.verComoCliente(); // 3 (false→true)

      expect(avisos, equals(3));
      expect(modo.comoCliente, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // 4. Widget test: el modo repinta la decisión (sin Supabase)
  // ─────────────────────────────────────────────────────────────────────
  group('repintado del conmutador', () {
    Future<(ModoVistaProvider, _Contadores)> montar(
      WidgetTester tester, {
      required bool admin,
      required bool vendedor,
    }) async {
      final modo = ModoVistaProvider();
      final contadores = _Contadores();
      await tester.pumpWidget(
        _Arnes(
          entidad: _EntidadProviderFalso(admin: admin, vendedor: vendedor),
          modo: modo,
          contadores: contadores,
        ),
      );
      return (modo, contadores);
    }

    testWidgets('un admin pasa de admin a cliente y vuelve, por las dos vías', (
      tester,
    ) async {
      final (modo, contadores) = await montar(tester, admin: true, vendedor: false);

      // Arranque: las dos sondas coinciden con el rol.
      expect(find.text('lb:admin'), findsOneWidget);
      expect(find.text('watch:admin'), findsOneWidget);
      expect(contadores.porListenableBuilder, equals(1));
      expect(contadores.porWatch, equals(1));

      // «Ver la app como cliente» desde Gestión/Perfil.
      await tester.tap(find.text('entrar'));
      await tester.pump();
      expect(modo.comoCliente, isTrue);
      expect(find.text('lb:cliente'), findsOneWidget);
      expect(find.text('watch:cliente'), findsOneWidget);
      expect(contadores.porListenableBuilder, equals(2));
      expect(contadores.porWatch, equals(2));

      // Repetir no repinta: el provider no notifica si no cambia.
      await tester.tap(find.text('entrar'));
      await tester.pump();
      expect(contadores.porListenableBuilder, equals(2));
      expect(contadores.porWatch, equals(2));

      // Vuelta al panel.
      await tester.tap(find.text('salir'));
      await tester.pump();
      expect(modo.comoCliente, isFalse);
      expect(find.text('lb:admin'), findsOneWidget);
      expect(find.text('watch:admin'), findsOneWidget);
      expect(contadores.porListenableBuilder, equals(3));
      expect(contadores.porWatch, equals(3));
    });

    testWidgets('admin+vendedor: cliente mientras dura, vendedorAdmin al volver', (
      tester,
    ) async {
      final (modo, _) = await montar(tester, admin: true, vendedor: true);

      expect(find.text('watch:vendedorAdmin'), findsOneWidget);

      await tester.tap(find.text('entrar'));
      await tester.pump();
      expect(modo.comoCliente, isTrue);
      expect(find.text('watch:cliente'), findsOneWidget);
      expect(esVistaCliente(VistaShell.cliente), isTrue);

      await tester.tap(find.text('salir'));
      await tester.pump();
      expect(find.text('watch:vendedorAdmin'), findsOneWidget);
    });

    testWidgets(
      'vendedor puro con el interruptor encendido por error sigue en vendedor',
      (tester) async {
        final (modo, contadores) = await montar(tester, admin: false, vendedor: true);

        expect(find.text('watch:vendedor'), findsOneWidget);
        expect(find.text('lb:vendedor'), findsOneWidget);

        // El provider SÍ se enciende (no sabe de roles: eso lo decide el shell),
        // pero la vista que se elige no cambia → no se le quitan sus pantallas.
        await tester.tap(find.text('entrar'));
        await tester.pump();
        expect(modo.comoCliente, isTrue);
        expect(find.text('watch:vendedor'), findsOneWidget);
        expect(find.text('lb:vendedor'), findsOneWidget);
        expect(contadores.porWatch, equals(2)); // repintó…
        expect(find.text('watch:cliente'), findsNothing); // …pero a lo mismo
      },
    );

    testWidgets('cliente puro: el interruptor no le cambia nada', (tester) async {
      final (modo, _) = await montar(tester, admin: false, vendedor: false);

      expect(find.text('watch:cliente'), findsOneWidget);

      await tester.tap(find.text('entrar'));
      await tester.pump();
      expect(modo.comoCliente, isTrue);
      expect(find.text('watch:cliente'), findsOneWidget);
    });
  });
}
