import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/sales.dart';

CashDelivery _entrega({
  required int id,
  required int idTurno,
  required String fecha,
  double monto = 1,
}) {
  return CashDelivery(
    id: id,
    montoEntrega: monto,
    motivoEntrega: 'motivo',
    nombreRecibe: 'recibe',
    nombreAutoriza: 'autoriza',
    fechaEntrega: DateTime.parse(fecha),
    estado: 1,
    idTurno: idTurno,
    creadoPor: '',
  );
}

SalesVendorReport _reporte(Map<String, dynamic> json) {
  return SalesVendorReport.fromJson({
    'uuid_usuario': '748b2bc7-dadb-4c76-b327-251c047657fe',
    'nombres': 'TURNO',
    'apellidos': 'CAPIRO 1',
    'nombre_completo': 'TURNO CAPIRO 1',
    ...json,
  });
}

void main() {
  final entregas = [
    _entrega(
      id: 2424,
      idTurno: 3533,
      fecha: '2026-11-17T16:08:02.818337-05:00',
      monto: 81520,
    ),
    _entrega(
      id: 2396,
      idTurno: 3504,
      fecha: '2026-11-14T14:49:57.855312-05:00',
      monto: 409425,
    ),
    _entrega(
      id: 2410,
      idTurno: 3524,
      fecha: '2026-11-17T10:00:00-05:00',
      monto: 100,
    ),
  ];

  test('un turno no se queda con egresos de otro turno del mismo día ni de uno anterior', () {
    final del3533 = filtrarEntregasPorTurno(entregas, 3533);
    expect(del3533.map((e) => e.id), [2424]);
    expect(del3533.single.idTurno, 3533);

    final del3524 = filtrarEntregasPorTurno(entregas, 3524);
    expect(del3524.map((e) => e.id), [2410]);
  });

  test('los egresos se agrupan por divisa y sin divisa cuentan como base', () {
    final lista = [
      _entrega(id: 1, idTurno: 21, fecha: '2026-11-20T14:06:47-05:00', monto: 750),
      _entrega(id: 2, idTurno: 21, fecha: '2026-11-20T14:07:00-05:00', monto: 5),
      CashDelivery.fromJson({
        'id': 3,
        'monto_entrega': 2,
        'id_turno': 21,
        'moneda': 'usd',
        'fecha_entrega': '2026-11-20T14:08:00-05:00',
      }),
    ];
    final porMoneda = egresosPorMoneda(lista, monedaBase: 'CUP');
    expect(porMoneda['CUP'], 755);
    expect(porMoneda['USD'], 2);
  });

  test('cada egreso se resta del efectivo de su propia divisa', () {
    final filas = [
      VentasPorMoneda(
        moneda: 'CUP',
        operaciones: 3,
        importeNativo: 15200,
        importeBase: 15200,
        efectivoNativo: 15200,
        digitalNativo: 0,
        tasaPromedio: 1,
        monedaConsolidacion: '',
        importeConsolidado: 0,
      ),
      VentasPorMoneda(
        moneda: 'USD',
        operaciones: 3,
        importeNativo: 23.1,
        importeBase: 0,
        efectivoNativo: 23.1,
        digitalNativo: 0,
        tasaPromedio: 0,
        monedaConsolidacion: '',
        importeConsolidado: 0,
      ),
    ];
    final lineas = efectivoCobradoPorDivisa(
      filas,
      egresos: 0,
      monedaBase: 'CUP',
      egresosPorMoneda: const {'CUP': 750},
    );
    expect(lineas.firstWhere((l) => l.moneda == 'CUP').importe, 14450);
    expect(lineas.firstWhere((l) => l.moneda == 'USD').importe, 23.1);
  });

  test('sin turno se conserva el período completo', () {
    expect(filtrarEntregasPorTurno(entregas, null), entregas);
  });

  test('el reporte por turno usa apertura y cierre, no la primera y última venta', () {
    final turno = _reporte({
      'id_turno': 3533,
      'id_tpv': 249,
      'estado_turno': 2,
      'fecha_apertura': '2026-11-17T16:07:17.550868-05:00',
      'fecha_cierre': '2026-11-17T16:16:02.002434-05:00',
      'primera_venta': '2026-11-17T07:57:27.272564-05:00',
      'ultima_venta': '2026-11-17T15:16:06.188390-05:00',
    });

    expect(turno.esPorTurno, isTrue);
    expect(turno.idTurno, 3533);
    expect(turno.periodoInicio, turno.fechaApertura);
    expect(turno.periodoFin, turno.fechaCierre);
    expect(turno.periodoInicio.isBefore(turno.primeraVenta), isFalse);
  });

  test('sin id_turno el período cae en las ventas y no se puede separar el turno', () {
    final vendedor = _reporte({
      'primera_venta': '2026-11-17T07:57:27.272564-05:00',
      'ultima_venta': '2026-11-17T15:16:06.188390-05:00',
    });

    expect(vendedor.esPorTurno, isFalse);
    expect(vendedor.idTurno, isNull);
    expect(vendedor.periodoInicio, vendedor.primeraVenta);
    expect(vendedor.periodoFin, vendedor.ultimaVenta);
  });

  test('el instante para la RPC lleva la hora local y su desplazamiento', () {
    final value = DateTime.utc(2026, 11, 17, 21, 7, 17, 550, 868);
    final texto = instanteEntregaParaRpc(value);
    final local = value.toLocal();

    expect(texto.endsWith('Z'), isFalse);
    expect(
      texto.startsWith(
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}T'
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}',
      ),
      isTrue,
    );

    final offset = local.timeZoneOffset;
    final signo = offset.isNegative ? '-' : '+';
    final horas = offset.inHours.abs().toString().padLeft(2, '0');
    final minutos = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    expect(texto.endsWith('$signo$horas:$minutos'), isTrue);
  });
}
