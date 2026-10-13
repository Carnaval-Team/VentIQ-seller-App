import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/dashboard_entidad.dart';

/// El dashboard del admin (punto 1 del plan) se alimenta de una sola RPC.
///
/// Estas pruebas fijan el contrato del parseo: **nunca lanza**. Si la RPC cambia
/// de forma, o si una entidad nueva no tiene datos, la pantalla de Gestión debe
/// seguir pintando ceros y no romperse.
void main() {
  group('ConteoActivo', () {
    test('calcula los inactivos y la proporción', () {
      const c = ConteoActivo(total: 10, activos: 4);
      expect(c.inactivos, 6);
      expect(c.proporcionActiva, closeTo(0.4, 1e-9));
    });

    test('sin datos no divide por cero', () {
      expect(ConteoActivo.vacio.inactivos, 0);
      expect(ConteoActivo.vacio.proporcionActiva, 0);
    });

    test('activos nunca supera a total', () {
      final c = ConteoActivo.fromJson({'total': 3, 'activos': 99});
      expect(c.total, 3);
      expect(c.activos, 3);
      expect(c.inactivos, 0);
    });

    test('total negativo se normaliza a 0', () {
      final c = ConteoActivo.fromJson({'total': -5, 'activos': 2});
      expect(c.total, 0);
      expect(c.activos, 0);
    });

    test('acepta números como texto', () {
      final c = ConteoActivo.fromJson({'total': '7', 'activos': '7'});
      expect(c.total, 7);
      expect(c.activos, 7);
    });

    test('un valor nulo o basura da ceros', () {
      expect(ConteoActivo.fromJson(null).total, 0);
      expect(ConteoActivo.fromJson('loquesea').total, 0);
      expect(ConteoActivo.fromJson(const {}).activos, 0);
    });
  });

  group('ReservasResumen', () {
    test('lee los cuatro contadores', () {
      final r = ReservasResumen.fromJson({
        'total': 12,
        'reservado': 5,
        'completado': 6,
        'cancelado': 1,
      });
      expect(r.total, 12);
      expect(r.reservado, 5);
      expect(r.completado, 6);
      expect(r.cancelado, 1);
    });

    test('sin payload devuelve el cero compartido', () {
      expect(ReservasResumen.fromJson(null).total, 0);
      expect(ReservasResumen.fromJson(42).total, 0);
    });
  });

  group('ReservasDia', () {
    test('recorta la fecha a año-mes-día', () {
      final d = ReservasDia.fromJson({
        'fecha': '2025-03-09T00:00:00',
        'total': 4,
        'reservadas': 3,
        'completadas': 1,
        'canceladas': 0,
      });
      expect(d, isNotNull);
      expect(d!.fecha, DateTime(2025, 3, 9));
      expect(d.total, 4);
      expect(d.reservadas, 3);
    });

    test('descarta una fecha ilegible en vez de lanzar', () {
      expect(ReservasDia.fromJson({'fecha': 'ayer', 'total': 3}), isNull);
      expect(ReservasDia.fromJson({'fecha': 20250309}), isNull);
      expect(ReservasDia.fromJson(null), isNull);
    });
  });

  group('TopServicio', () {
    test('usa "Servicio" cuando el nombre viene vacío', () {
      final top = TopServicio.fromJson({
        'id_local_servicio': 9,
        'servicio': '   ',
        'local': 'Local Centro',
        'total': 5,
      });
      expect(top!.servicio, 'Servicio');
      expect(top.idLocalServicio, 9);
      expect(top.local, 'Local Centro');
      expect(top.total, 5);
    });

    test('descarta entradas que no son mapa', () {
      expect(TopServicio.fromJson('nada'), isNull);
    });
  });

  group('DashboardEntidad', () {
    final jsonCompleto = {
      'ok': true,
      'dias': 30,
      'locales': {'total': 2, 'activos': 1},
      'servicios': {'total': 5, 'activos': 5},
      'local_servicios': {'total': 7, 'activos': 3},
      'reservas': {
        'total': 10,
        'reservado': 2,
        'completado': 7,
        'cancelado': 1,
      },
      'reservas_por_dia': [
        {'fecha': '2025-03-01', 'total': 0},
        {'fecha': '2025-03-02', 'total': 6, 'reservadas': 6},
        {'fecha': '2025-03-03', 'total': 4},
      ],
      'top_servicios': [
        {'id_local_servicio': 1, 'servicio': 'Corte', 'total': 6},
      ],
    };

    test('parsea la respuesta completa', () {
      final d = DashboardEntidad.fromJson(jsonCompleto);
      expect(d.dias, 30);
      expect(d.locales.total, 2);
      expect(d.locales.inactivos, 1);
      expect(d.localServicios.activos, 3);
      expect(d.reservas.completado, 7);
      expect(d.porDia, hasLength(3));
      expect(d.topServicios.single.servicio, 'Corte');
    });

    test('maximoDiario es el pico y nunca 0', () {
      expect(DashboardEntidad.fromJson(jsonCompleto).maximoDiario, 6);
      expect(DashboardEntidad.vacio.maximoDiario, 1);
    });

    test('totalSerie suma los días', () {
      expect(DashboardEntidad.fromJson(jsonCompleto).totalSerie, 10);
      expect(DashboardEntidad.vacio.totalSerie, 0);
    });

    test('un payload vacío da el dashboard vacío sin lanzar', () {
      final d = DashboardEntidad.fromJson(const {});
      expect(d.dias, 30);
      expect(d.locales.total, 0);
      expect(d.reservas.total, 0);
      expect(d.porDia, isEmpty);
      expect(d.topServicios, isEmpty);
    });

    test('descarta los días inválidos y conserva los buenos', () {
      final d = DashboardEntidad.fromJson({
        'reservas_por_dia': [
          {'fecha': 'no-es-fecha'},
          {'fecha': '2025-01-02', 'total': 3},
          'basura',
        ],
      });
      expect(d.porDia, hasLength(1));
      expect(d.porDia.single.total, 3);
    });

    test('dias <= 0 cae al valor por defecto', () {
      expect(DashboardEntidad.fromJson({'dias': 0}).dias, 30);
      expect(DashboardEntidad.fromJson({'dias': -3}).dias, 30);
    });
  });
}
