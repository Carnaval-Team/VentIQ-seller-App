import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/cxc_v1.dart';
import 'package:ventiq_app/money/piloto_v1.dart';
import 'package:ventiq_app/money/venta_v1_envio.dart';

void main() {
  const clave = '00000000-0000-4000-8000-000000000099';

  test('sin cache o de otra tienda la orden no usa el cobro anterior', () {
    final sinCache = PilotoV1.recorrido(
      cache: CacheRecorrido.ausente,
      mismaTienda: true,
      version: null,
      modoActivo: false,
      tieneTasa: true,
      lineasCompletas: true,
      origen: 'mostrador',
      respuestaPerdida: false,
      claveGuardada: null,
    );
    expect(sinCache.ruta, RutaEnvio.rechazar);
    final v1SinCache = PilotoV1.recorrido(
      cache: CacheRecorrido.ausente,
      mismaTienda: true,
      version: 'producto-v1',
      modoActivo: true,
      tieneTasa: true,
      lineasCompletas: true,
      origen: 'mostrador',
      respuestaPerdida: false,
      claveGuardada: clave,
    );
    expect(v1SinCache.ruta, RutaEnvio.retener);
    final ajena = PilotoV1.recorrido(
      cache: CacheRecorrido.otraTienda,
      mismaTienda: false,
      version: 'producto-v1',
      modoActivo: true,
      tieneTasa: true,
      lineasCompletas: true,
      origen: 'mostrador',
      respuestaPerdida: false,
      claveGuardada: clave,
    );
    expect(ajena.ruta, RutaEnvio.rechazar);
  });

  test('una respuesta perdida reintenta la misma clave', () {
    expect(PilotoV1.claveReintento(guardada: clave, nueva: 'otra'), clave);
    final decision = PilotoV1.recorrido(
      cache: CacheRecorrido.fresca,
      mismaTienda: true,
      version: 'producto-v1',
      modoActivo: true,
      tieneTasa: true,
      lineasCompletas: true,
      origen: 'mostrador',
      respuestaPerdida: true,
      claveGuardada: clave,
    );
    expect(decision.ruta, RutaEnvio.productoV1);
  });

  test('el flag no se enciende sin el si, el ticket y los pendientes', () {
    expect(
      PilotoV1.puedeEncender(
        anonSinEjecutar: true,
        comandaCorregida: true,
        pendientesIdentificados: true,
        ticketFisico: false,
        autorizacionAct: true,
      ),
      isFalse,
    );
    expect(
      PilotoV1.puedeEncender(
        anonSinEjecutar: true,
        comandaCorregida: true,
        pendientesIdentificados: true,
        ticketFisico: true,
        autorizacionAct: false,
      ),
      isFalse,
    );
  });

  test('al apagar entra lo nuevo sin version y se conserva lo ya empezado', () {
    expect(
      PilotoV1.apagado(version: null, claveGuardada: null).ruta,
      RutaEnvio.legacy,
    );
    expect(
      PilotoV1.apagado(version: 'producto-v1', claveGuardada: clave).ruta,
      RutaEnvio.productoV1,
    );
    expect(
      PilotoV1.apagado(version: 'producto-v1', claveGuardada: null).ruta,
      RutaEnvio.retener,
    );
    expect(
      PilotoV1.conservaColaYEsquema(
        claveGuardada: clave,
        borraEsquema: false,
        borraCola: false,
      ),
      isTrue,
    );
    expect(
      () => CxcV1.validarLiquidacion(
        monedaDeuda: 'USD',
        monedaPago: 'USD',
        medioFijado: 1,
        medioPago: 2,
        saldo: '5.00',
        monto: '1.00',
      ),
      throwsA(isA<CxcV1Exception>()),
    );
    PilotoV1.deudaYDevolucion();
  });

  test('el verificador del piloto no enciende ni borra', () {
    final sql = File('../docs/plan-multimoneda/verificar_m01_m07_piloto.sql')
        .readAsStringSync()
        .toLowerCase();
    expect(RegExp(r'^\s*(update|delete|insert)\s', multiLine: true).hasMatch(sql), isFalse);
    expect(sql.contains('permitir_moneda_por_producto'), isTrue);
  });
}
