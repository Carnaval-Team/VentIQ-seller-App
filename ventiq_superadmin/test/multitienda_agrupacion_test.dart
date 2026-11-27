import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_superadmin/services/inventtia_reparto_service.dart';

CobroLicencia cobro(
  int suscripcionId,
  int tiendaId,
  String tienda, {
  double planUsd = 10,
  double recibidoCup = 5000,
}) {
  return CobroLicencia(
    suscripcionId: suscripcionId,
    tiendaId: tiendaId,
    tienda: tienda,
    plan: 'basica',
    planUsd: planUsd,
    cupTeorico: planUsd * 500,
    recibidoUsd: planUsd,
    recibidoCup: recibidoCup,
    transaccion: '',
    agenteId: null,
    agenteNombre: null,
    periodo: DateTime(2026, 11),
  );
}

void main() {
  test('la secundaria se agrupa en la principal sin sumar lo recibido', () {
    final principal = cobro(1, 100, 'Principal');
    final secundaria = cobro(2, 200, 'Secundaria A', recibidoCup: 3000);
    final otra = cobro(3, 300, 'Independiente');

    final grupos = InventtiaRepartoService.agruparCobros(
      [secundaria, principal, otra],
      {200: 100},
      {100: 'Principal', 200: 'Secundaria A'},
    );

    expect(grupos.length, 2);
    expect(grupos.map((c) => c.tienda), containsAll(['Principal', 'Independiente']));
    expect(principal.secundarias, ['Secundaria A']);
    // El grupo cobra solo por la licencia de la principal.
    expect(principal.recibidoCup, 5000);
    expect(principal.recibidoUsd, 10);
  });

  test('secundaria sin cobro de la principal queda visible y marcada', () {
    final secundaria = cobro(2, 200, 'Secundaria A');

    final grupos = InventtiaRepartoService.agruparCobros(
      [secundaria],
      {200: 100},
      {100: 'Principal'},
    );

    expect(grupos.length, 1);
    expect(grupos.single.secundariaDe, 'Principal');
    expect(grupos.single.secundarias, isEmpty);
  });

  test('sin grupos definidos no cambia nada', () {
    final a = cobro(1, 100, 'A');
    final b = cobro(2, 200, 'B');

    final grupos = InventtiaRepartoService.agruparCobros([a, b], {}, {});

    expect(grupos.length, 2);
    expect(a.secundarias, isEmpty);
    expect(b.secundariaDe, isNull);
  });
}
