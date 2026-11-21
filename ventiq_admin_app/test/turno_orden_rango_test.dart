import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/sales.dart';

void main() {
  final inicio = DateTime(2026, 11, 19, 8);
  final fin = DateTime(2026, 11, 19, 20);

  bool pertenece(
    int id,
    DateTime fecha, {
    RangoOperacionesTurno? rango,
    bool abierto = false,
  }) => ordenPerteneceATurno(
    idOperacion: id,
    fechaOperacion: fecha,
    inicio: inicio,
    fin: fin,
    turnoAbierto: abierto,
    rango: rango,
  );

  test('venta offline subida al día siguiente sigue en su turno', () {
    const rango = RangoOperacionesTurno(apertura: 100, cierre: 200);
    final subida = DateTime(2026, 11, 20, 9);
    expect(pertenece(150, subida, rango: rango), isTrue);
  });

  test('operación fuera del rango de ids no pertenece aunque la fecha encaje', () {
    const rango = RangoOperacionesTurno(apertura: 100, cierre: 200);
    final enVentana = DateTime(2026, 11, 19, 12);
    expect(pertenece(99, enVentana, rango: rango), isFalse);
    expect(pertenece(100, enVentana, rango: rango), isFalse);
    expect(pertenece(200, enVentana, rango: rango), isFalse);
    expect(pertenece(201, enVentana, rango: rango), isFalse);
  });

  test('turno abierto: todo lo posterior a la apertura', () {
    const rango = RangoOperacionesTurno(apertura: 100);
    expect(pertenece(5000, DateTime(2026, 11, 21), rango: rango, abierto: true),
        isTrue);
  });

  test('sin rango fiable cae a la ventana de fechas', () {
    const sinCierre = RangoOperacionesTurno(apertura: 100);
    final dentro = DateTime(2026, 11, 19, 12);
    final fuera = DateTime(2026, 11, 20, 9);
    expect(pertenece(150, dentro, rango: sinCierre), isTrue);
    expect(pertenece(150, fuera, rango: sinCierre), isFalse);
    expect(pertenece(150, dentro), isTrue);
    expect(pertenece(150, fuera), isFalse);
  });
}
