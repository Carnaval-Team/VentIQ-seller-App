import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/services/turno_service.dart';

void main() {
  group('TurnoService.resolveTurnoIdForEgresos', () {
    test('prioriza id numérico del turno en display', () {
      expect(
        TurnoService.resolveTurnoIdForEgresos({'id': 3599, 'estado': 2}),
        3599,
      );
    });

    test('acepta server_id_turno cuando no hay id abierto', () {
      expect(
        TurnoService.resolveTurnoIdForEgresos({
          'server_id_turno': 3599,
          'status': 'synced',
        }),
        3599,
      );
    });

    test('parsea ids string de cache offline', () {
      expect(
        TurnoService.resolveTurnoIdForEgresos({'id_turno': '3599'}),
        3599,
      );
    });

    test('null sin mapa o sin id usable', () {
      expect(TurnoService.resolveTurnoIdForEgresos(null), isNull);
      expect(TurnoService.resolveTurnoIdForEgresos({'estado': 2}), isNull);
      expect(
        TurnoService.resolveTurnoIdForEgresos({'id': 'no-int'}),
        isNull,
      );
    });
  });
}
