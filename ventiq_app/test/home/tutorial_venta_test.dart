// Tutorial de venta: los guiones dependen del modo del negocio.
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/screens/tutorial_venta_screen.dart';

void main() {
  test('el flujo normal explica Home, producto, carrito, orden y cobro', () {
    final List<PasoTutorialVenta> pasos = TutorialVentaScreen.pasosPara(
      restaurante: false,
    );
    expect(pasos.length, greaterThanOrEqualTo(4));
    expect(pasos.first.ruta, '/');
    expect(pasos.any((PasoTutorialVenta p) => p.ruta == '/preorder'), isTrue);
    expect(pasos.any((PasoTutorialVenta p) => p.ruta == '/orders'), isTrue);
    // Cada paso tiene título y descripción para el cliente.
    for (final PasoTutorialVenta p in pasos) {
      expect(p.titulo.trim(), isNotEmpty);
      expect(p.descripcion.trim(), isNotEmpty);
    }
  });

  test('restaurante/cocina usa el flujo de mesas y KDS', () {
    final List<PasoTutorialVenta> pasos = TutorialVentaScreen.pasosPara(
      restaurante: true,
    );
    expect(pasos.length, greaterThanOrEqualTo(4));
    expect(pasos.first.ruta, '/mesas');
    expect(pasos.any((PasoTutorialVenta p) => p.ruta == '/kds'), isTrue);
    for (final PasoTutorialVenta p in pasos) {
      expect(p.titulo.trim(), isNotEmpty);
      expect(p.descripcion.trim(), isNotEmpty);
    }
  });

  test('los dos recorridos son distintos', () {
    expect(
      TutorialVentaScreen.pasosNormal.first.titulo,
      isNot(TutorialVentaScreen.pasosRestaurante.first.titulo),
    );
  });
}
