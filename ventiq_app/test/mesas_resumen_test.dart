import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/mesa.dart';

Mesa mesa(int id, int abiertas, {bool activa = true}) => Mesa(
  id: id,
  idTienda: 4,
  numero: 'Mesa $id',
  capacidad: 4,
  activa: activa,
  ordenesAbiertas: abiertas,
  comensalesActivos: abiertas,
);

void main() {
  test('el resumen coincide con las tarjetas de la tienda 4', () {
    final resumen = MesasResumen.fromMesas([
      mesa(1, 1),
      mesa(3, 0),
      mesa(2, 0),
    ]);
    expect(resumen.total, 3);
    expect(resumen.ocupadas, 1);
    expect(resumen.libres, 2);
    expect(resumen.ordenesPendientesTotal, 1);
    expect(resumen.mesaTopComensales?.id, 1);
    expect(resumen.mesaTopComensales?.comensales, 1);
  });

  test('suma todas las cuentas abiertas y selecciona la mesa más activa', () {
    final resumen = MesasResumen.fromMesas([
      mesa(1, 2),
      mesa(2, 4),
      mesa(3, 0),
    ]);
    expect(resumen.total, 3);
    expect(resumen.ocupadas, 2);
    expect(resumen.libres, 1);
    expect(resumen.ordenesPendientesTotal, 6);
    expect(resumen.mesaTopComensales?.id, 2);
    expect(resumen.mesaTopComensales?.comensales, 4);
  });

  test('excluye mesas inactivas y sus cuentas del resumen', () {
    final resumen = MesasResumen.fromMesas([
      mesa(1, 1),
      mesa(2, 8, activa: false),
    ]);
    expect(resumen.total, 1);
    expect(resumen.ocupadas, 1);
    expect(resumen.libres, 0);
    expect(resumen.ordenesPendientesTotal, 1);
    expect(resumen.mesaTopComensales?.id, 1);
  });

  test('sin cuentas abiertas no muestra una mesa más activa', () {
    final resumen = MesasResumen.fromMesas([mesa(1, 0), mesa(2, 0)]);
    expect(resumen.ocupadas, 0);
    expect(resumen.libres, 2);
    expect(resumen.ordenesPendientesTotal, 0);
    expect(resumen.mesaTopComensales, isNull);
  });

  test('una lista vacía produce un resumen vacío', () {
    final resumen = MesasResumen.fromMesas([]);
    expect(resumen.total, 0);
    expect(resumen.ocupadas, 0);
    expect(resumen.libres, 0);
    expect(resumen.ordenesPendientesTotal, 0);
    expect(resumen.mesaTopComensales, isNull);
  });

  test('una recarga recalcula las métricas sin conservar cuentas antiguas', () {
    final primera = MesasResumen.fromMesas([mesa(1, 3), mesa(2, 0)]);
    final segunda = MesasResumen.fromMesas([mesa(1, 0), mesa(2, 1)]);
    expect(primera.ordenesPendientesTotal, 3);
    expect(segunda.ordenesPendientesTotal, 1);
    expect(segunda.mesaTopComensales?.id, 2);
    expect(segunda.total, segunda.ocupadas + segunda.libres);
  });
}
