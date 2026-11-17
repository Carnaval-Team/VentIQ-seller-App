import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/politica_moneda.dart';

void main() {
  Map<String, dynamic> lista() {
    return {
      'flag': true,
      'id_tienda': 4,
      'denegada': false,
      'revision': {
        'id': 9,
        'id_tienda': 4,
        'forzar_moneda_venta': false,
        'moneda_venta_forzada': null,
        'monedas_habilitadas': ['CUP', 'USD'],
      },
      'constancia': {
        'id_tienda': 4,
        'id_revision': 9,
        'uuid_sujeto': 'usuario-1',
      },
    };
  }

  test('el flag apagado o ausente no enciende el modo', () {
    expect(PoliticaMonedaEstado.interpretar(cache: null).modoActivo, isFalse);
    expect(
      PoliticaMonedaEstado.interpretar(
        cache: {'flag': false, 'id_tienda': 4},
        tiendaSesion: 4,
        usuario: 'usuario-1',
      ).fase,
      PoliticaMonedaFase.apagada,
    );
  });

  test('el flag encendido sin evidencia bloquea y no pasa a legacy', () {
    final estado = PoliticaMonedaEstado.interpretar(
      cache: {'flag': true, 'id_tienda': 4},
      tiendaSesion: 4,
      usuario: 'usuario-1',
    );
    expect(estado.modoActivo, isFalse);
    expect(estado.bloqueaOrdenNueva, isTrue);
  });

  test('una constancia de otra tienda o usuario no sirve', () {
    final ajena = Map<String, dynamic>.from(lista());
    expect(
      PoliticaMonedaEstado.interpretar(
        cache: ajena,
        tiendaSesion: 5,
        usuario: 'usuario-1',
      ).bloqueaOrdenNueva,
      isTrue,
    );
    expect(
      PoliticaMonedaEstado.interpretar(
        cache: lista(),
        tiendaSesion: 4,
        usuario: 'otro',
      ).bloqueaOrdenNueva,
      isTrue,
    );
  });

  test('una respuesta de otra tienda no reemplaza la sesion', () {
    expect(
      PoliticaMonedaEstado.puedeReemplazar(
        tiendaRespuesta: 5,
        tiendaSesion: 4,
      ),
      isFalse,
    );
    final completa = PoliticaMonedaEstado.interpretar(
      cache: lista(),
      tiendaSesion: 4,
      usuario: 'usuario-1',
    );
    expect(completa.modoActivo, isTrue);
  });

  test('con el modo apagado no se pide moneda y el descuento exige permiso', () {
    expect(
      SeleccionLineaMoneda.preparar(modoActivo: false, moneda: null),
      isNull,
    );
    expect(
      () => SeleccionLineaMoneda.preparar(
        modoActivo: true,
        moneda: 'EUR',
        precio: '1',
        tasa: '1',
      ),
      throwsA(isA<PoliticaMonedaException>()),
    );
    expect(
      () => SeleccionLineaMoneda.preparar(
        modoActivo: true,
        moneda: 'USD',
        precio: '1.05',
        tasa: '400',
        manual: '0.1',
      ),
      throwsA(isA<PoliticaMonedaException>()),
    );
    final linea = SeleccionLineaMoneda.preparar(
      modoActivo: true,
      moneda: 'USD',
      precio: '1.05',
      tasa: '400',
      manual: '0',
      permiteDescuento: true,
    );
    expect(linea!.calculo.neto.toFixed(2), '1.05');
  });

  test('unir exige la misma presentacion, moneda y medio, y una confirmacion', () {
    expect(
      DuplicadoLinea.decidir(
        mismaPresentacion: false,
        mismaMoneda: true,
        mismoMedio: true,
        confirmado: true,
      ),
      DecisionDuplicado.separar,
    );
    expect(
      DuplicadoLinea.decidir(
        mismaPresentacion: true,
        mismaMoneda: false,
        mismoMedio: true,
        confirmado: true,
      ),
      DecisionDuplicado.separar,
    );
    expect(
      DuplicadoLinea.decidir(
        mismaPresentacion: true,
        mismaMoneda: true,
        mismoMedio: true,
        confirmado: false,
      ),
      DecisionDuplicado.pedirConfirmacion,
    );
    expect(
      DuplicadoLinea.decidir(
        mismaPresentacion: true,
        mismaMoneda: true,
        mismoMedio: true,
        confirmado: true,
        cancelado: true,
      ),
      DecisionDuplicado.cancelar,
    );
  });
}