// Contrato del alta de tienda: lo que se rompe en silencio.
//
// Cubre tres cosas que no fallan con una excepción pero sí rompen la promesa
// al usuario:
//   1. Que el creador quede como Dueño: el SQL tiene que escribir en
//      `app_dat_dueno` y enlazar el trabajador.
//   2. Que el paso 1 y el login no revienten a 390 px (móvil real).
//   3. Que el tutorial se abra con la burbuja y recorra los pasos.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/screens/login_screen.dart';
import 'package:ventiq_admin_app/screens/store_registration_screen.dart';
import 'package:ventiq_admin_app/widgets/tutorial_guiado.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Las dos pantallas construyen servicios que leen `Supabase.instance` en el
  // constructor. Sin inicializar, el widget revienta antes de pintar nada y la
  // prueba de layout no mediría la UI.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
    );
  });

  group('SQL: el creador queda como Dueño', () {
    late String sql;

    setUpAll(() {
      // El script vive en la raíz del monorepo, un nivel por encima de la app.
      final fichero = File(
        '../sql_updates/fn_m01_crear_estructura_tienda_dueno.sql',
      );
      expect(
        fichero.existsSync(),
        isTrue,
        reason: 'falta sql_updates/fn_m01_crear_estructura_tienda_dueno.sql',
      );
      sql = fichero.readAsStringSync();
    });

    test('escribe en app_dat_dueno y en app_dat_gerente', () {
      expect(sql, contains('INSERT INTO public.app_dat_dueno'));
      expect(sql, contains('INSERT INTO public.app_dat_gerente'));
    });

    test('es idempotente: no duplica la fila del Dueño', () {
      expect(
        sql,
        contains(
          'WHERE NOT EXISTS (\n            SELECT 1 FROM public.app_dat_dueno',
        ),
      );
    });

    test('enlaza el trabajador del creador y le pone el uuid', () {
      // Sin el UPDATE, el trabajador se queda con uuid nulo (la RPC original
      // no lo escribe) y el Dueño no aparece en Personal.
      expect(sql, contains('UPDATE public.app_dat_trabajadores'));
      expect(sql, contains('SET uuid = v_uuid'));
    });

    test('un fallo al registrar el Dueño no tumba la tienda ya creada', () {
      expect(sql, contains("v_resultado->>'success'"));
      expect(sql, contains('dueno_registrado'));
      expect(sql, contains('WHEN OTHERS THEN'));
    });

    test('el creador es auth.uid(), no un uuid del cliente', () {
      expect(sql, contains('v_uuid uuid := auth.uid()'));
      expect(sql, contains('USING ERRCODE = \'42501\''));
    });

    test('sigue siendo SECURITY DEFINER para poder escribir con RLS', () {
      // `crear_estructura_tienda` es INVOKER: desde ahí el INSERT en
      // app_dat_dueno lo bloquearía la política. El wrapper es el que escribe.
      expect(sql, contains('SECURITY DEFINER'));
    });
  });

  group('UI a 390 px', () {
    /// Fija un móvil real. Sin esto el lienzo de test es 800x600 y los
    /// overflows de móvil no aparecen.
    void movil(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('el login no desborda y muestra sus acciones', (tester) async {
      movil(tester);
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Inventtia Gestión'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('Crear mi tienda'), findsOneWidget);

      // Desmontaje limpio: el auto-login deja un `Future` pendiente.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('el paso 1 del alta no desborda', (tester) async {
      movil(tester);
      await tester.pumpWidget(
        const MaterialApp(home: StoreRegistrationScreen()),
      );
      await tester.pump();

      // La pantalla pide países por red al montarse. En test eso falla y deja
      // un SnackBar animándose; lo que interesa aquí es que el layout del paso
      // 1 no desborde.
      expect(tester.takeException(), isNull);
      expect(find.text('Crea la cuenta del administrador'), findsOneWidget);
      expect(find.text('Nombre completo'), findsOneWidget);
      expect(find.text('Crear tienda asistida (IA)'), findsOneWidget);

      // Desmontaje limpio: sin esto la animación del SnackBar sigue viva cuando
      // el árbol se destruye y Flutter lo reporta como error del test.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('Tutorial: las claves de los pasos existen de verdad', () {
    // Regresión real: `_claveMapa` estaba declarada y usada en un paso, pero no
    // anclada a ningún widget. Ese paso se saltaba en silencio y el usuario
    // nunca veía la explicación del mapa.
    test('cada GlobalKey del recorrido está anclada a un widget', () {
      final fuente = File(
        'lib/screens/store_registration_screen.dart',
      ).readAsStringSync();

      // Claves que el recorrido usa como objetivo de un paso.
      final enPasos = RegExp(
        r'clave:\s*(_clave\w+),',
      ).allMatches(fuente).map((m) => m.group(1)!).toSet();

      expect(
        enPasos,
        isNotEmpty,
        reason: 'no se encontró ningún paso en _pasosTutorial',
      );

      for (final clave in enPasos) {
        // El widget la recibe como `key:` (KeyedSubtree) o `clave:` (campo).
        final anclada =
            fuente.contains('key: $clave,') ||
            fuente.contains('key: $clave)') ||
            // El campo la recibe como parámetro y la aplica a la Column.
            RegExp('clave:\\s*$clave,').allMatches(fuente).length > 1;
        expect(
          anclada,
          isTrue,
          reason:
              '$clave se usa en un paso del tutorial pero no está anclada a '
              'ningún widget: ese paso se saltaría sin explicar nada.',
        );
      }
    });
  });

  group('burbuja y recorrido del tutorial', () {
    testWidgets('la burbuja explica y arranca el recorrido', (tester) async {
      final ancla = GlobalKey();
      var aceptado = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                actions: [
                  IconButton(
                    key: ancla,
                    icon: const Icon(Icons.school_outlined),
                    onPressed: () {},
                  ),
                ],
              ),
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final aviso = insertarAvisoTutorial(
        tester.element(find.byType(Scaffold)),
        ancla: ancla,
        alAceptar: () async => aceptado++,
        alCerrar: () {},
      );
      await tester.pumpAndSettle();

      expect(aviso, isNotNull);
      expect(find.text('¿Tienes dudas?'), findsOneWidget);
      expect(find.textContaining('Ve el tutorial'), findsOneWidget);

      await tester.tap(find.text('Ver tutorial'));
      await tester.pumpAndSettle();
      expect(aceptado, 1);
    });

    testWidgets('un paso con `alEntrar` cambia de página antes de medir', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: _HarnessDosPaginas()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      // El paso no se saltó: la pantalla cambió de página y se mostró la
      // tarjeta de ese campo. Sin `alEntrar` el RenderBox no existiría y el
      // recorrido habría saltado al paso siguiente (o terminado).
      expect(find.text('Vive en otra página.'), findsOneWidget);
    });

    testWidgets('cerrar la burbuja dos veces no lanza', (tester) async {
      final ancla = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  key: ancla,
                  icon: const Icon(Icons.school_outlined),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final aviso = insertarAvisoTutorial(
        tester.element(find.byType(Scaffold)),
        ancla: ancla,
        alAceptar: () async {},
        alCerrar: () {},
      );
      expect(aviso, isNotNull);
      aviso!
        ..cerrar()
        ..cerrar();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// Pantalla mínima con dos «páginas»: el campo del paso solo se monta cuando
/// `alEntrar` cambia el estado. Reproduce lo que hace el asistente real con su
/// `PageView`, y por eso el paso se mide bien en vez de saltarse.
class _HarnessDosPaginas extends StatefulWidget {
  const _HarnessDosPaginas();

  @override
  State<_HarnessDosPaginas> createState() => _HarnessDosPaginasState();
}

class _HarnessDosPaginasState extends State<_HarnessDosPaginas> {
  final _clavePagina2 = GlobalKey();
  int _pagina = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text('página $_pagina'),
          if (_pagina == 2)
            SizedBox(
              key: _clavePagina2,
              height: 60,
              child: const TextField(
                decoration: InputDecoration(labelText: 'Campo lejano'),
              ),
            ),
          ElevatedButton(
            onPressed: () => mostrarTutorialGuiado(
              context,
              pasos: [
                PasoGuiado(
                  clave: _clavePagina2,
                  titulo: 'Campo lejano',
                  texto: 'Vive en otra página.',
                  alEntrar: () async {
                    if (!mounted) return;
                    setState(() => _pagina = 2);
                    // Un frame para que el campo esté montado y medible.
                    await Future<void>.delayed(
                      const Duration(milliseconds: 80),
                    );
                  },
                ),
              ],
            ),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }
}
