import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/notificacion.dart';
import 'package:inventtia_flow/utils/notificacion_orden.dart';

/// F1 — Orden de notificaciones (decisión D2 del plan).
///
/// El orden se decide en una función pura para poder probar el caso incómodo:
/// varios avisos insertados por el mismo CTE comparten `created_at` (porque
/// `current_timestamp` es la hora de la transacción), y el desempate por `id`
/// es lo que hace que el orden sea determinista.
void main() {
  Notificacion notif(int id, DateTime createdAt) => Notificacion(
        id: id,
        uuidUsuario: 'usuario-1',
        tipo: 'sistema',
        titulo: 'Aviso $id',
        mensaje: 'Mensaje $id',
        leida: false,
        createdAt: createdAt,
      );

  group('ordenarPorFecha', () {
    test('ordena descendente por createdAt', () {
      final vieja = notif(1, DateTime(2025, 3, 1, 9));
      final media = notif(2, DateTime(2025, 3, 1, 12));
      final nueva = notif(3, DateTime(2025, 3, 2, 8));

      final orden = ordenarPorFecha([vieja, nueva, media]);

      expect(orden.map((n) => n.id).toList(), [3, 2, 1]);
    });

    test('con createdAt idéntico desempata por id descendente', () {
      // Mismo instante exacto: es lo que produce un CTE con varios inserts.
      final mismo = DateTime(2025, 3, 1, 10, 30);
      final a = notif(7, mismo);
      final b = notif(30, mismo);
      final c = notif(15, mismo);

      final orden = ordenarPorFecha([a, b, c]);

      expect(orden.map((n) => n.id).toList(), [30, 15, 7]);
    });

    test('mezcla fechas y empates sin perder el criterio', () {
      final mismo = DateTime(2025, 3, 1, 10);
      final orden = ordenarPorFecha([
        notif(1, DateTime(2025, 2, 28, 23)),
        notif(4, mismo),
        notif(9, mismo),
        notif(2, DateTime(2025, 3, 2, 0)),
      ]);

      expect(orden.map((n) => n.id).toList(), [2, 9, 4, 1]);
    });

    test('lista vacía devuelve lista vacía', () {
      expect(ordenarPorFecha([]), isEmpty);
    });

    test('un solo ítem se devuelve tal cual', () {
      final solo = notif(5, DateTime(2025, 3, 1));
      final orden = ordenarPorFecha([solo]);
      expect(orden, hasLength(1));
      expect(orden.single.id, 5);
    });

    test('no muta la lista de entrada', () {
      final entrada = [
        notif(1, DateTime(2025, 3, 1, 9)),
        notif(2, DateTime(2025, 3, 2, 9)),
      ];
      final orden = ordenarPorFecha(entrada);

      expect(identical(entrada, orden), isFalse);
      expect(entrada.map((n) => n.id).toList(), [1, 2]);
      expect(orden.map((n) => n.id).toList(), [2, 1]);
    });
  });

  group('etiquetaDiaNotificacion', () {
    final ahora = DateTime(2025, 3, 10, 15, 30);

    test('el mismo día es Hoy', () {
      expect(etiquetaDiaNotificacion(DateTime(2025, 3, 10, 0, 5), ahora: ahora),
          'Hoy');
      expect(etiquetaDiaNotificacion(DateTime(2025, 3, 10, 15, 29), ahora: ahora),
          'Hoy');
    });

    test('el día anterior es Ayer aunque hayan pasado pocas horas', () {
      // 23:50 de ayer frente a las 15:30 de hoy: menos de 24 h, pero es "Ayer".
      expect(etiquetaDiaNotificacion(DateTime(2025, 3, 9, 23, 50), ahora: ahora),
          'Ayer');
      expect(etiquetaDiaNotificacion(DateTime(2025, 3, 9, 0, 1), ahora: ahora),
          'Ayer');
    });

    test('más atrás usa dd/MM/yyyy', () {
      expect(etiquetaDiaNotificacion(DateTime(2025, 3, 8, 23, 59), ahora: ahora),
          '08/03/2025');
      expect(etiquetaDiaNotificacion(DateTime(2024, 12, 31), ahora: ahora),
          '31/12/2024');
    });

    test('el cambio de mes no confunde Hoy/Ayer', () {
      final primeroDeMes = DateTime(2025, 3, 1, 9);
      expect(etiquetaDiaNotificacion(DateTime(2025, 2, 28, 9),
          ahora: primeroDeMes), 'Ayer');
      expect(etiquetaDiaNotificacion(DateTime(2025, 2, 27, 9),
          ahora: primeroDeMes), '27/02/2025');
    });
  });
}