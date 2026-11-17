import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/estudio_inversion.dart';

void main() {
  final recepcion = DateTime(2026, 5, 10);
  final venta = DateTime(2026, 6, 1);

  RecepcionInversion cerveza({DateTime? fecha, double unidades = 5000, double total = 1500}) {
    return RecepcionInversion(
      fecha: fecha ?? recepcion,
      unidadesBase: unidades,
      costoUnitarioUsd: total / unidades,
      totalUsd: total,
    );
  }

  VentaInversion cobroCup({DateTime? fecha, double unidades = 2000}) {
    return VentaInversion(
      fecha: fecha ?? venta,
      unidadesBase: unidades,
      moneda: 'CUP',
      importeNativo: unidades * 510,
      tasaUsd: 850,
    );
  }

  group('estudio de inversión', () {
    test('la cerveza recupera el 80 % con la tasa del día de la venta', () {
      final estudio = estudiarInversion(
        recepciones: [cerveza()],
        ventas: [cobroCup()],
      );

      final tramo = estudio.tramos.single;
      expect(tramo.meta, 1500);
      expect(tramo.recaudado, 1200);
      expect(tramo.cumplimiento, 0.8);
      expect(tramo.enCurso, isTrue);
      expect(estudio.resumenDelListado?.cumplimiento, 0.8);
      expect(estudio.resumenDelListado?.costoUnitarioUsd, 0.3);
    });

    test('una venta en USD no se vuelve a dividir por la tasa', () {
      final estudio = estudiarInversion(
        recepciones: [cerveza()],
        ventas: [
          VentaInversion(
            fecha: venta,
            unidadesBase: 2000,
            moneda: 'USD',
            importeNativo: 1200,
          ),
        ],
      );

      expect(estudio.tramos.single.recaudado, 1200);
      expect(estudio.tramos.single.cumplimiento, 0.8);
    });

    test('una recepción con stock todavía positivo se suma a la misma meta', () {
      final estudio = estudiarInversion(
        recepciones: [
          cerveza(),
          cerveza(fecha: DateTime(2026, 7, 1), unidades: 1000, total: 400),
        ],
        ventas: [cobroCup()],
      );

      expect(estudio.tramos, hasLength(1));
      expect(estudio.tramos.single.meta, 1900);
    });

    test('agotarse antes de la siguiente recepción abre otra inversión', () {
      final estudio = estudiarInversion(
        recepciones: [
          cerveza(),
          cerveza(fecha: DateTime(2026, 8, 1), unidades: 1000, total: 400),
        ],
        ventas: [
          cobroCup(unidades: 5000),
          cobroCup(fecha: DateTime(2026, 8, 15), unidades: 100),
        ],
      );

      expect(estudio.tramos, hasLength(2));
      expect(estudio.tramos.first.cumplimiento, closeTo(5000 * 0.6 / 1500, 0.0001));
      expect(estudio.tramos.first.recaudado, 3000);
      expect(estudio.tramos.last.recepciones.single.totalUsd, 400);
      expect(estudio.tramos.last.ventas.single.unidadesBase, 100);
      expect(estudio.existenciasDe(estudio.tramos.first), 0);
      expect(estudio.existenciasDe(estudio.tramos.last), 900);
    });

    test('una devolución después del cero no vuelve a unir los tramos', () {
      final estudio = estudiarInversion(
        recepciones: [
          cerveza(),
          cerveza(fecha: DateTime(2026, 8, 1), unidades: 1000, total: 400),
        ],
        ventas: [cobroCup(unidades: 5000)],
        ajustes: [
          AjusteStock(fecha: DateTime(2026, 7, 1), deltaUnidadesBase: 2),
        ],
      );

      expect(estudio.tramos, hasLength(2));
    });

    test('sin tasa el cumplimiento queda en null y esa venta no suma', () {
      final estudio = estudiarInversion(
        recepciones: [cerveza()],
        ventas: [
          VentaInversion(
            fecha: venta,
            unidadesBase: 2000,
            moneda: 'CUP',
            importeNativo: 2000 * 510,
          ),
        ],
      );

      expect(estudio.tramos.single.incompleto, isTrue);
      expect(estudio.tramos.single.cumplimiento, isNull);
      expect(estudio.tramos.single.recaudado, 0);
    });

    test('una recepción sin factor no entra a la meta y marca el estudio', () {
      final estudio = estudiarInversion(
        recepciones: [
          RecepcionInversion(
            fecha: recepcion,
            unidadesBase: 0,
            costoUnitarioUsd: 0.3,
            totalUsd: 1500,
            cuentaParaStock: false,
          ),
        ],
        ventas: [],
      );

      expect(estudio.datosIncompletos, isTrue);
      expect(estudio.tramos, isEmpty);
    });

    test('el costo real es por unidad: 5000 a 1 no suman 1', () {
      expect(
        metaDeRecepcion(costoReal: 1, cantidadPagada: 5000, precioUnitarioUsd: 1),
        5000,
      );
      expect(
        metaDeRecepcion(costoReal: 0, cantidadPagada: 5000, precioUnitarioUsd: 0.3),
        1500,
      );
    });

    test('el id guardado es el de la fila y la base con cantidad 24 no multiplica', () {
      const base = FilaPresentacion(
        idFila: 8,
        idCatalogo: 1,
        cantidad: 24,
        marcadaBase: true,
      );
      const caja = FilaPresentacion(
        idFila: 9,
        idCatalogo: 3,
        cantidad: 48,
        marcadaBase: false,
      );
      final tabla = tablaPresentaciones([base, caja]);

      final deLaFila = tabla.buscar(9);
      expect(deLaFila!.factorRel, 2);
      expect(aUnidadesBase(cantidad: 4, esBase: false, factor: deLaFila.factorRel), 8);

      final deLaBase = tabla.buscar(8);
      expect(deLaBase!.esBase, isTrue);
      expect(deLaBase.factorRel, 1);
      expect(aUnidadesBase(cantidad: 10, esBase: false, factor: deLaBase.factorRel), 10);

      expect(tabla.buscar(null)!.idFila, 8);
      expect(tabla.buscar(3)!.idFila, 9);
    });

    test('una caja se pasa a unidades base y el total USD no se recalcula', () {
      expect(aUnidadesBase(cantidad: 2, esBase: false, factor: 24), 48);
      expect(aUnidadesBase(cantidad: 2, esBase: true, factor: 24), 2);
      expect(aUnidadesBase(cantidad: 2, esBase: false, factor: null), isNull);
    });

    test('la tasa sale del precio de referencia de esa fecha, no del de hoy', () {
      final viejo = PrecioReferencia(
        id: 1,
        idVariante: null,
        desde: DateTime(2026, 5, 1),
        hasta: DateTime(2026, 6, 30),
        precioCup: 510,
        precioUsd: 0.6,
      );
      final hoy = PrecioReferencia(
        id: 2,
        idVariante: null,
        desde: DateTime(2026, 7, 1),
        hasta: null,
        precioCup: 900,
        precioUsd: 1,
      );

      final vigente = precioReferenciaEnFecha([hoy, viejo], DateTime(2026, 6, 1));
      expect(vigente!.id, 1);
      expect(tasaUsdDesdeReferencia(precioCup: vigente.precioCup, precioUsd: vigente.precioUsd), 850);
    });

    test('el inventario al precio actual se suma a lo recaudado', () {
      const precio = 9.41;
      const stock = 120.0;
      const recaudado = 9846.0;
      const meta = 11000.0;
      final corto = predecirInversion(
        meta: meta,
        recaudado: recaudado,
        incompleto: false,
        existenciasBase: stock,
        precioActualUsd: precio,
      );
      final valor = stock * precio;
      expect(corto.valorExistenciasUsd, closeTo(valor, 0.001));
      expect(corto.proyectadoUsd, closeTo(recaudado + valor, 0.001));
      expect(corto.gananciaUsd, closeTo(recaudado + valor - meta, 0.001));
      expect(corto.porcentajeGanancia, closeTo((recaudado + valor - meta) / meta, 0.0000001));
      expect(corto.esGanancia, isFalse);

      final conGanancia = predecirInversion(
        meta: meta,
        recaudado: recaudado,
        incompleto: false,
        existenciasBase: 200,
        precioActualUsd: precio,
      );
      expect(conGanancia.esGanancia, isTrue);
      expect(
        conGanancia.porcentajeGanancia,
        closeTo((recaudado + 200 * precio - meta) / meta, 0.0000001),
      );

      final sinPrecio = predecirInversion(
        meta: meta,
        recaudado: recaudado,
        incompleto: false,
        existenciasBase: stock,
        precioActualUsd: null,
      );
      expect(sinPrecio.sinPrecio, isTrue);
      expect(sinPrecio.porcentajeGanancia, isNull);
      expect(sinPrecio.existenciasBase, stock);

      final agotado = predecirInversion(
        meta: 1500,
        recaudado: 1800,
        incompleto: false,
        existenciasBase: 0,
        precioActualUsd: 0.6,
      );
      expect(agotado.valorExistenciasUsd, 0);
      expect(agotado.porcentajeGanancia, 0.2);
    });

    test('el precio teórico se convierte con la tasa de la tienda', () {
      expect(usdDesdeCup(cup: 8000, tasaUsdACup: 850), closeTo(8000 / 850, 0.0000001));
      expect(cupDesdeUsd(usd: 9.41, tasaUsdACup: 850), closeTo(9.41 * 850, 0.0000001));
      expect(usdDesdeCup(cup: 100, tasaUsdACup: 0), isNull);
      expect(parsearPrecioTeorico('1,5'), 1.5);
      expect(parsearPrecioTeorico(''), isNull);
    });

    test('solo el estado completado entra', () {
      expect(operacionCompletada(2), isTrue);
      expect(operacionCompletada(4), isFalse);
    });
  });
}
