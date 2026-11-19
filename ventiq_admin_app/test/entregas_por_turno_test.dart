import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/sales.dart';

CashDelivery _entrega({
  required int id,
  required int idTurno,
  required String fecha,
}) {
  return CashDelivery(
    id: id,
    montoEntrega: 1,
    motivoEntrega: 'motivo',
    nombreRecibe: 'recibe',
    nombreAutoriza: 'autoriza',
    fechaEntrega: DateTime.parse(fecha),
    estado: 1,
    idTurno: idTurno,
    creadoPor: '',
  );
}

void main() {
  final entregas = [
    _entrega(
      id: 2424,
      idTurno: 3533,
      fecha: '2026-11-17T16:08:02.818337-05:00',
    ),
    _entrega(
      id: 2396,
      idTurno: 3504,
      fecha: '2026-11-14T14:49:57.855312-05:00',
    ),
    _entrega(
      id: 2410,
      idTurno: 3524,
      fecha: '2026-11-17T10:00:00-05:00',
    ),
  ];

  test('cada turno conserva solo sus egresos', () {
    expect(
      filtrarEntregasPorTurno(entregas, 3533).map((e) => e.id),
      [2424],
    );
    expect(
      filtrarEntregasPorTurno(entregas, 3524).map((e) => e.id),
      [2410],
    );
  });

  test('el reporte lee el id de turno que después piden los egresos', () {
    final turno = SalesVendorReport.fromJson({
      'uuid_usuario': '748b2bc7-dadb-4c76-b327-251c047657fe',
      'nombres': 'TURNO',
      'apellidos': 'CAPIRO 1',
      'nombre_completo': 'TURNO CAPIRO 1',
      'id_turno': 3533,
      'estado_turno': 2,
      'fecha_apertura': '2026-11-17T16:07:17.550868-05:00',
      'fecha_cierre': '2026-11-17T16:16:02.002434-05:00',
      'primera_venta': '2026-11-17T07:57:27.272564-05:00',
      'ultima_venta': '2026-11-17T15:16:06.188390-05:00',
    });

    expect(turno.idTurno, 3533);
    expect(turno.periodoInicio, turno.fechaApertura);
    expect(turno.periodoFin, turno.fechaCierre);
  });
}
