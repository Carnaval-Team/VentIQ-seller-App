import 'package:flutter_test/flutter_test.dart';

import 'package:ventiq_app/services/elaborated_availability_service.dart';

void main() {
  group('disponibilidad de elaborados', () {
    test(
      'lee los disponibles numéricos y descarta errores/ilimitados',
      () async {
        final ElaboratedAvailabilityService
        servicio = ElaboratedAvailabilityService(
          offline: () async => false,
          cargar: (int id, int idTpv) async {
            if (id == 10800) {
              return <String, dynamic>{
                'status': 'success',
                'disponible': 41000,
              };
            }
            if (id == 10813) {
              return <String, dynamic>{'status': 'success', 'disponible': '26'};
            }
            if (id == 999) {
              return <String, dynamic>{'status': 'error', 'disponible': 0};
            }
            if (id == 500) {
              return <String, dynamic>{'status': 'success', 'ilimitado': true};
            }
            return null;
          },
        );

        final Map<int, double> disp = await servicio.disponibles(
          // Repetido a propósito: se deduplica.
          idsProductos: <int>[10800, 10813, 999, 500, 10800],
          idTpv: 224,
        );

        expect(disp, <int, double>{10800: 41000, 10813: 26});
      },
    );

    test('offline no consulta al servidor', () async {
      int llamadas = 0;
      final ElaboratedAvailabilityService servicio =
          ElaboratedAvailabilityService(
            offline: () async => true,
            cargar: (int id, int idTpv) async {
              llamadas++;
              return <String, dynamic>{'status': 'success', 'disponible': 5};
            },
          );

      final Map<int, double> disp = await servicio.disponibles(
        idsProductos: <int>[1, 2],
        idTpv: 224,
      );

      expect(disp, isEmpty);
      expect(llamadas, 0);
    });

    test('un fallo de un producto no tumba a los demás', () async {
      final ElaboratedAvailabilityService servicio =
          ElaboratedAvailabilityService(
            offline: () async => false,
            cargar: (int id, int idTpv) async {
              if (id == 2) throw Exception('sin red');
              return <String, dynamic>{'status': 'success', 'disponible': 3};
            },
          );

      final Map<int, double> disp = await servicio.disponibles(
        idsProductos: <int>[1, 2, 3],
        idTpv: 224,
      );

      expect(disp, <int, double>{1: 3, 3: 3});
    });

    test('un disponible negativo se recorta a 0', () async {
      final ElaboratedAvailabilityService servicio =
          ElaboratedAvailabilityService(
            offline: () async => false,
            cargar:
                (int id, int idTpv) async => <String, dynamic>{
                  'status': 'success',
                  'disponible': -2,
                },
          );

      expect(await servicio.disponible(idProducto: 1, idTpv: 224), 0);
    });
  });
}
