// Pruebas del controlador del editor de precios compartido.
//
// Solo se prueba el controlador (sin widgets): lo que hay que blindar es la
// **paridad con lo que ya se guardaba**, no el pintado. Todas las pruebas
// `dispose()`an el controlador al final para que la suite no arrastre
// `ChangeNotifier`s vivos ni `Timer`s pendientes.

import 'package:flutter_test/flutter_test.dart';

import 'package:inventtia_flow/models/config_precio.dart';
import 'package:inventtia_flow/widgets/precios_servicio_editor.dart';

void main() {
  group('PreciosServicioControlador', () {
    test(
      'construir() devuelve el config_precio que se guardó (USD 25 / CUP 2500)',
      () {
        final guardado = ConfigPrecio(
          monedaDefault: 'USD',
          monedas: const ['USD', 'CUP'],
          preciosBase: const {'USD': 25.0, 'CUP': 2500.0},
        );
        final ctrl = PreciosServicioControlador(configInicial: guardado);

        final out = ctrl.construir();

        expect(out, isNotNull);
        // Se compara el JSON porque es EXACTAMENTE lo que va a la base: si la
        // extracción hubiera cambiado una clave o el formato de un precio, aquí
        // se vería.
        expect(out!.toJson(), guardado.toJson());
        expect(ctrl.error, isNull);
        ctrl.dispose();
      },
    );

    test('un precio ilegible devuelve null y error con la moneda', () {
      final ctrl = PreciosServicioControlador(
        configInicial: ConfigPrecio(
          monedas: const ['USD', 'CUP'],
          preciosBase: const {'USD': 25.0, 'CUP': 2500.0},
        ),
      );

      // Antes se guardaba como 25 a medias: el parseo no puede inventar un
      // número, así que `construir()` falla en vez de escribir un precio falso.
      ctrl.editarPrecioBase('CUP', 'mil pesos');

      expect(ctrl.construir(), isNull);
      expect(ctrl.error, 'Precio base inválido para CUP');
      ctrl.dispose();
    });

    test(
      'toggleMoneda quita una moneda, no deja la lista vacía y reasigna la base',
      () {
        final ctrl = PreciosServicioControlador(
          configInicial: ConfigPrecio(
            monedaDefault: 'CUP',
            monedas: const ['USD', 'CUP'],
            preciosBase: const {'USD': 25.0, 'CUP': 2500.0},
          ),
        );

        ctrl.toggleMoneda('CUP', false);
        var out = ctrl.construir()!;
        expect(out.monedas, const ['USD']);
        // La base era CUP: el desplegable no admite un valor que ya no está.
        expect(out.monedaDefault, 'USD');
        expect(out.preciosBase, const {'USD': 25.0});

        // Quitar la última moneda no puede dejar el servicio sin precios.
        ctrl.toggleMoneda('USD', false);
        out = ctrl.construir()!;
        expect(out.monedas, const ['USD']);

        // Y volver a habilitarla no duplica.
        ctrl.toggleMoneda('USD', true);
        expect(ctrl.construir()!.monedas, const ['USD']);
        ctrl.dispose();
      },
    );

    test(
      'la regla con siClave = slug se resuelve a la clave final del campo',
      () {
        final ctrl = PreciosServicioControlador(
          configInicial: ConfigPrecio(
            monedas: const ['USD'],
            preciosBase: const {'USD': 25.0},
            reglas: [
              ReglaPrecio(
                siClave: 'tipo_habitacion',
                preciosOpcion: const {
                  'Doble': {'USD': 40.0},
                },
              ),
            ],
          ),
          // El host resuelve el slug de la etiqueta y le añade sufijo si choca con
          // otro campo: la regla debe guardar la clave final, no el slug.
          camposSelect: [
            (
              slug: 'tipo_habitacion',
              clave: 'tipo_habitacion_2',
              etiqueta: 'Tipo de habitación',
              opciones: const ['Doble', 'Simple'],
            ),
          ],
        );

        final out = ctrl.construir()!;

        expect(out.reglas, hasLength(1));
        expect(out.reglas.single.siClave, 'tipo_habitacion_2');
        expect(out.reglas.single.preciosOpcion['Doble'], const {'USD': 40.0});
        ctrl.dispose();
      },
    );

    test(
      'un precio guardado con 3 decimales se relee como 18.38, no como 18380',
      () {
        final ctrl = PreciosServicioControlador(
          configInicial: ConfigPrecio(preciosBase: const {'USD': 18.375}),
        );

        // `parseMonto` lee tres dígitos tras el punto como millares: por eso el
        // texto inicial se redondea antes de pintarlo.
        expect(ctrl.textoPrecioBase('USD'), '18.38');
        expect(ctrl.construir()!.preciosBase['USD'], 18.38);
        ctrl.dispose();
      },
    );

    test('hayCambios se enciende al editar y se apaga al guardar', () {
      final ctrl = PreciosServicioControlador(
        configInicial: ConfigPrecio(preciosBase: const {'USD': 25.0}),
      );

      expect(ctrl.hayCambios, isFalse);
      ctrl.editarPrecioBase('USD', '30');
      expect(ctrl.hayCambios, isTrue);
      ctrl.marcarComoGuardado();
      expect(ctrl.hayCambios, isFalse);
      ctrl.dispose();
    });

    test('las reglas sin campo o sin precios no llegan al config_precio', () {
      final ctrl = PreciosServicioControlador(
        configInicial: ConfigPrecio(
          monedas: const ['USD'],
          preciosBase: const {'USD': 25.0},
          reglas: [
            // Sin campo elegido: no hay a qué dato adicional aplicarla.
            ReglaPrecio(
              siClave: '',
              preciosOpcion: const {
                'Doble': {'USD': 40.0},
              },
            ),
            // Con campo, pero sin ningún precio (el 0 significa «sin precio»).
            ReglaPrecio(
              siClave: 'tipo_habitacion',
              preciosOpcion: const {
                'Doble': {'USD': 0.0},
              },
            ),
          ],
        ),
      );

      final out = ctrl.construir()!;

      expect(out.reglas, isEmpty);
      expect(out.preciosBase, const {'USD': 25.0});
      expect(ctrl.error, isNull);
      ctrl.dispose();
    });
  });
}
