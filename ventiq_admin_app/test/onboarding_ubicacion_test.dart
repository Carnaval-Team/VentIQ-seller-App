// Contrato de dónde vive la burbuja de activación.
//
// El fallo real que motiva este archivo: la burbuja se montó solo en
// `dashboard_screen.dart` (la de móvil). En web, `/dashboard` resuelve a
// `DashboardWebScreen` (`PlatformAwareDashboardScreen` en `main.dart:346`), así
// que el Dueño de una tienda en borrador no veía el aviso por ningún sitio.
//
// Es el tipo de error que no rompe nada y no lo caza ningún test de unidad: hay
// que comprobar que **las dos** pantallas que pueden hacer de dashboard montan
// el widget, y que el menú no manda a la pantalla completa.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('la burbuja está en todos los dashboards', () {
    /// Pantallas que `/dashboard` puede resolver. Si aparece una tercera en
    /// `PlatformAwareDashboardScreen`, tiene que entrar aquí y montar la
    /// burbuja, o el aviso desaparecerá solo en esa plataforma.
    const dashboards = [
      'lib/screens/dashboard_screen.dart',
      'lib/screens/dashboard_web_screen.dart',
    ];

    for (final ruta in dashboards) {
      test('$ruta monta OnboardingBurbuja', () {
        final fuente = File(ruta).readAsStringSync();
        expect(
          fuente,
          contains('OnboardingBurbuja()'),
          reason:
              'sin la burbuja, una tienda en borrador no tiene checklist en '
              'esta plataforma y el cliente no sabe qué le falta',
        );
        expect(
          fuente,
          contains("import '../widgets/onboarding_burbuja.dart';"),
          reason: 'falta el import que hace posible el widget',
        );
      });

      test('$ruta ya no pinta la tarjeta duplicada', () {
        final fuente = File(ruta).readAsStringSync();
        expect(
          fuente,
          isNot(contains('OnboardingDashboardCard')),
          reason:
              'la tarjeta de arriba se duplicaba con la burbuja: el aviso '
              'tiene un solo sitio',
        );
      });
    }

    test('PlatformAwareDashboardScreen solo conoce esas dos', () {
      final main = File('lib/main.dart').readAsStringSync();
      // Si alguien añade un tercer dashboard, este test le obliga a pasar por
      // aquí y decidir si necesita burbuja.
      final destinos = RegExp(
        r'return const (Dashboard\w*Screen)\(\);',
      ).allMatches(main).map((m) => m.group(1)!).toSet();
      expect(
        destinos,
        {'DashboardWebScreen', 'DashboardScreen'},
        reason:
            'apareció otro dashboard: revisa si también necesita '
            'OnboardingBurbuja y actualiza `dashboards` en este test',
      );
    });
  });

  group('el menú no manda a pantalla completa', () {
    test('el drawer ya no navega a /activacion', () {
      final drawer = File('lib/widgets/admin_drawer.dart').readAsStringSync();
      expect(
        drawer,
        isNot(contains("pushNamed(context, '/activacion')")),
        reason:
            'la entrada «Pon en marcha tu tienda» abría la pantalla completa; '
            'debe volver al dashboard, donde vive la burbuja',
      );
    });

    test('la entrada del drawer sigue existiendo', () {
      // Quitarla dejaría a quien descartó el checklist sin vía de recuperación.
      final drawer = File('lib/widgets/admin_drawer.dart').readAsStringSync();
      expect(drawer, contains('Pon en marcha tu tienda'));
    });
  });

  group('no se apilan dos Scaffold', () {
    // El «duplicado» que se veía: `OnboardingChecklistVista` ya trae su
    // `Scaffold` con AppBar, y `ActivacionTiendaScreen` la envolvía en otro. Dos
    // barras superpuestas.
    test('ActivacionTiendaScreen devuelve la vista directamente', () {
      final fuente = File(
        'lib/screens/activacion_tienda_screen.dart',
      ).readAsStringSync();
      expect(
        fuente,
        isNot(contains('return Scaffold(')),
        reason:
            'OnboardingChecklistVista ya construye su Scaffold: envolverla en '
            'otro apila dos AppBar',
      );
      expect(fuente, contains('return OnboardingChecklistVista('));
    });
  });
}