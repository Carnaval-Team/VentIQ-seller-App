// Contrato de los hechos del checklist que se quedaban sin resolver.
//
// El fallo medido (tienda 43 en debug): con productos recepcionados y tasa
// USD→CUP activa, «Carga las existencias» y «Revisa tu tasa de cambio» seguían
// sin el check. La causa no era la consulta: era que las dos tareas nacían
// `estadoSinHecho`, es decir, pendientes hasta que la pantalla las guardara con
// `marcarTarea`, y `marcarTarea` no se llama desde ningún sitio.
//
// Estos tests son de fuente a propósito: lo que hay que impedir es que alguien
// vuelva a convertirlas en tareas «de adorno» o que el servicio deje de mirar
// las tablas que de verdad tienen el dato.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final modelo = File('lib/models/onboarding_tareas.dart').readAsStringSync();
  final servicio = File('lib/services/onboarding_service.dart').readAsStringSync();

  group('las tareas tienen hecho real', () {
    test('inventario sale de HechosTienda, no de un estado guardado', () {
      expect(
        modelo,
        contains("estadoDe('inventario', hechos.tieneExistencias)"),
        reason:
            'con estadoSinHecho la tarea quedaba pendiente para siempre: nada '
            'llamaba a marcarTarea',
      );
      expect(modelo, isNot(contains("estadoSinHecho('inventario')")));
    });

    test('moneda sale de HechosTienda, no de un estado guardado', () {
      expect(
        modelo,
        contains("estadoDe('moneda', hechos.tieneTasaCambio)"),
      );
      expect(modelo, isNot(contains("estadoSinHecho('moneda')")));
    });

    test('el modelo expone los dos hechos', () {
      expect(modelo, contains('final bool tieneExistencias;'));
      expect(modelo, contains('final bool tieneTasaCambio;'));
    });
  });

  group('el servicio consulta las tablas correctas', () {
    test('las existencias salen del ledger de inventario', () {
      expect(
        servicio,
        contains(".from('app_dat_inventario_productos')"),
        reason:
            'es la única fuente del saldo: una recepción contabilizada escribe '
            'ahí y en ningún otro sitio',
      );
      expect(
        servicio,
        contains('cantidad_final'),
        reason: 'el stock de un grupo es el cantidad_final de su último movimiento',
      );
      expect(
        servicio,
        contains("order('id', ascending: false)"),
        reason:
            'hay que leer de lo más nuevo a lo más viejo para quedarse con el '
            'saldo vigente de cada grupo',
      );
    });

    test('la tasa sale de la tasa de la propia tienda', () {
      expect(servicio, contains(".from('tasa_cambio_extraoficial')"));
      expect(
        servicio,
        contains("eq('id_tienda', storeId)"),
        reason:
            'una tasa de otra tienda no dice nada de esta; sin el filtro el '
            'check se marcaría por la fila de cualquier vecino',
      );
      expect(servicio, contains("eq('id_moneda_origen', _idMonedaUsd)"));
      expect(servicio, contains("eq('id_moneda_destino', _idMonedaCup)"));
      expect(
        servicio,
        contains("eq('activo', true)"),
        reason: 'una tasa desactivada no es la vigente',
      );
    });

    test('las ubicaciones se traen todas, no solo la primera', () {
      expect(
        servicio,
        isNot(
          contains(
            ".select('id, id_almacen')\n                .inFilter('id_almacen', idsAlmacenes)\n                .isFilter('deleted_at', null)\n                .limit(1)",
          ),
        ),
        reason:
            'con limit(1) solo se conocía una ubicación y los saldos del resto '
            'de la tienda no se podían leer',
      );
    });
  });
}
