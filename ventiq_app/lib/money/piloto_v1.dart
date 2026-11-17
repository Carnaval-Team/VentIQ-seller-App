import 'cxc_v1.dart';
import 'mesa_v1.dart';
import 'venta_v1_envio.dart';

enum CacheRecorrido { ausente, otraTienda, fresca }

/// Recorrido, activación y apagado. Ninguno enciende el flag.
class PilotoV1 {
  static DecisionEnvio recorrido({
    required CacheRecorrido cache,
    required bool mismaTienda,
    required String? version,
    required bool modoActivo,
    required bool tieneTasa,
    required bool lineasCompletas,
    required String origen,
    required bool respuestaPerdida,
    required String? claveGuardada,
  }) {
    if (!mismaTienda || cache == CacheRecorrido.otraTienda) {
      return const DecisionEnvio(
        RutaEnvio.rechazar,
        'La tienda de la sesion no es la de la orden.',
      );
    }
    if (cache == CacheRecorrido.ausente) {
      if (version == 'producto-v1') {
        return const DecisionEnvio(
          RutaEnvio.retener,
          'Sin cache la orden nueva se conserva y no pasa al cobro anterior.',
        );
      }
      return const DecisionEnvio(
        RutaEnvio.rechazar,
        'Sin cache no se sabe si la moneda esta apagada. No se envia.',
      );
    }
    if (respuestaPerdida && claveGuardada != null) {
      return const DecisionEnvio(
        RutaEnvio.productoV1,
        'La respuesta no volvio. Se reintenta con la misma clave.',
      );
    }
    return EnvioV1.decidir(
      version: version,
      modoActivo: modoActivo,
      bloqueaOrdenNueva: false,
      tieneTasa: tieneTasa,
      lineasCompletas: lineasCompletas,
      origen: origen,
    );
  }

  static String claveReintento({String? guardada, required String nueva}) {
    if (guardada != null && guardada.isNotEmpty) return guardada;
    return nueva;
  }

  static bool puedeEncender({
    required bool anonSinEjecutar,
    required bool comandaCorregida,
    required bool pendientesIdentificados,
    required bool ticketFisico,
    required bool autorizacionAct,
  }) {
    return anonSinEjecutar &&
        comandaCorregida &&
        pendientesIdentificados &&
        ticketFisico &&
        autorizacionAct;
  }

  static DecisionEnvio apagado({
    required String? version,
    required String? claveGuardada,
  }) {
    if (version == 'producto-v1') {
      if (claveGuardada == null || claveGuardada.isEmpty) {
        return const DecisionEnvio(
          RutaEnvio.retener,
          'La orden nueva ya empezada no tiene clave. No se convierte ni se borra.',
        );
      }
      return const DecisionEnvio(
        RutaEnvio.productoV1,
        'Con el flag apagado la orden ya empezada se reintenta con su clave.',
      );
    }
    if (version == null) {
      return const DecisionEnvio(
        RutaEnvio.legacy,
        'Con el flag apagado una venta nueva sin version entra por el cobro anterior.',
      );
    }
    return const DecisionEnvio(
      RutaEnvio.rechazar,
      'La version no se reconoce y no se convierte al apagar.',
    );
  }

  static bool conservaColaYEsquema({
    required String? claveGuardada,
    required bool borraEsquema,
    required bool borraCola,
  }) {
    return claveGuardada != null && !borraEsquema && !borraCola;
  }

  static void deudaYDevolucion() {
    CxcV1.validarLiquidacion(
      monedaDeuda: 'USD',
      monedaPago: 'USD',
      medioFijado: 1,
      medioPago: 1,
      saldo: '5.00',
      monto: '1.00',
    );
    AjusteV1.validarDevolucion(
      version: 'producto-v1',
      monedaOriginal: 'USD',
      monedaDevolucion: 'USD',
    );
    if (MesaV1.debeDescontarAlCerrar(stockMovido: true)) {
      throw CxcV1Exception('STOCK_REPETIDO');
    }
  }
}
