import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/presentacion_cadena_local.dart';

/// Paridad de la resolucion offline con fn_presentaciones_producto.
///
/// Los casos NO son inventados: cada uno se corrio contra la funcion viva en
/// produccion (2026-08-27) y el resultado esperado es su salida literal. Si uno
/// de estos falla, el vendedor offline y el servidor dejaron de coincidir, y eso
/// significa cantidades mal registradas en el inventario.
void main() {
  /// Payload como lo guarda AutoSyncService._syncProducts: el nombre viene
  /// anidado en `presentacion`, no plano.
  Map<String, dynamic> fila({
    required int id,
    required int idNom,
    required String nombre,
    required num cantidad,
    required bool esBase,
    String? sku,
  }) => {
        'id': id,
        'id_producto': 999,
        'id_presentacion': idNom,
        'cantidad': cantidad,
        'es_base': esBase,
        'presentacion': {
          'id': idNom,
          'denominacion': nombre,
          'sku_codigo': sku,
          'es_fraccionable': false,
        },
      };

  group('producto 217 — Bulto 10 / Bolsa 1 base', () {
    // fn_presentaciones_producto(217) devuelve:
    //   nivel 1: 337 Bulto  factor 10  rel 10  base=false
    //   nivel 2: 336 Bolsa  factor 1   rel 1   base=true
    final crudas = [
      fila(id: 336, idNom: 4, nombre: 'Bolsa', cantidad: 1.0, esBase: true, sku: 'BOL'),
      fila(id: 337, idNom: 7, nombre: 'Bulto', cantidad: 10.0, esBase: false, sku: 'BLT'),
    ];

    test('ordena de mayor a menor factor, aunque el array venga al revés', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena.map((p) => p.idPresentacion), [337, 336]);
      expect(cadena.map((p) => p.nivel), [1, 2]);
    });

    test('factorRel y esBase coinciden con el SQL', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena[0].nombre, 'Bulto');
      expect(cadena[0].factorRel, 10.0);
      expect(cadena[0].esBase, false);
      expect(cadena[1].nombre, 'Bolsa');
      expect(cadena[1].factorRel, 1.0);
      expect(cadena[1].esBase, true);
    });

    test('lee el sku anidado', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena[0].skuCodigo, 'BLT');
    });
  });

  group('producto 1072 — cadena de 3 niveles Caja 40 / Blister 6 / Unidad 1', () {
    // fn_presentaciones_producto(1072):
    //   nivel 1: 1188 Caja    factor 40  rel 40  base=false
    //   nivel 2: 1187 Blister factor 6   rel 6   base=false
    //   nivel 3: 1186 Unidad  factor 1   rel 1   base=true
    final crudas = [
      fila(id: 1186, idNom: 1, nombre: 'Unidad', cantidad: 1.0, esBase: true, sku: 'UNI'),
      fila(id: 1187, idNom: 22, nombre: 'Blister', cantidad: 6.0, esBase: false, sku: 'BLI'),
      fila(id: 1188, idNom: 3, nombre: 'Caja', cantidad: 40.0, esBase: false, sku: 'CAJ'),
    ];

    test('orden y niveles exactos del SQL', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena.map((p) => p.idPresentacion), [1188, 1187, 1186]);
      expect(cadena.map((p) => p.factorRel), [40.0, 6.0, 1.0]);
      expect(cadena.map((p) => p.esBase), [false, false, true]);
    });

    test('equivalente base de una captura mixta', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      // 1 Caja + 2 Blister + 3 Unidades = 40 + 12 + 3 = 55
      final eq = PresentacionCadenaLocal.equivalenteBase(cadena, {
        1188: 1,
        1187: 2,
        1186: 3,
      });
      expect(eq, 55.0);
    });

    test('texto mixto respeta el orden de la cadena', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(
        FormatoPresentacion.mixto(cadena, {1186: 3, 1188: 1}),
        '1 Caja + 3 Unidades',
      );
    });
  });

  group('producto 4380 — la base tiene factor 30 (anomalía real)', () {
    // Una sola fila: 4445 Unidad factor 30 es_base=true.
    // El SQL da factor_rel = 1 porque se divide por la base, no por 1.
    final crudas = [
      fila(id: 4445, idNom: 1, nombre: 'Unidad', cantidad: 30.0, esBase: true),
    ];

    test('factorRel es 1, no 30: se divide por la base', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena.single.factor, 30.0);
      expect(cadena.single.factorRel, 1.0);
      expect(cadena.single.esBase, true);
    });
  });

  group('producto 9635 — cuatro filas, tres marcadas es_base', () {
    // fn_presentaciones_producto(9635) elige 9768 (menor id entre las es_base)
    // y marca las otras tres como es_base=false, aunque en la tabla lo estén.
    final crudas = [
      fila(id: 10674, idNom: 1, nombre: 'Unidad', cantidad: 1.0, esBase: true),
      fila(id: 10695, idNom: 1, nombre: 'Unidad', cantidad: 1.0, esBase: true),
      fila(id: 10753, idNom: 1, nombre: 'Unidad', cantidad: 1, esBase: false),
      fila(id: 9768, idNom: 1, nombre: 'Unidad', cantidad: 1.0, esBase: true),
    ];

    test('gana la de menor id entre las marcadas', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena.map((p) => p.idPresentacion), [9768, 10674, 10695, 10753]);
      expect(cadena.map((p) => p.esBase), [true, false, false, false]);
    });

    test('solo una fila queda como base', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena.where((p) => p.esBase).length, 1);
      expect(PresentacionCadenaLocal.base(cadena)!.idPresentacion, 9768);
    });
  });

  group('producto sin ninguna fila es_base', () {
    // Los 9 productos así: el SQL cae a la de MENOR factor.
    // Aquí está el bug que la Fase 1 eliminó — el viejo
    // `orElse: presentaciones.first` habría elegido la Caja.
    final crudas = [
      fila(id: 50, idNom: 3, nombre: 'Caja', cantidad: 12.0, esBase: false),
      fila(id: 51, idNom: 1, nombre: 'Unidad', cantidad: 1.0, esBase: false),
    ];

    test('la base es la de menor factor, no la primera del array', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      final base = PresentacionCadenaLocal.base(cadena)!;
      expect(base.idPresentacion, 51);
      expect(base.nombre, 'Unidad');
    });

    test('la Caja queda con factorRel 12', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena[0].nombre, 'Caja');
      expect(cadena[0].factorRel, 12.0);
    });
  });

  group('extraerCrudas — las rutas del payload', () {
    test('presentaciones plano', () {
      final p = {'presentaciones': [fila(id: 1, idNom: 1, nombre: 'Unidad', cantidad: 1, esBase: true)]};
      expect(PresentacionCadenaLocal.extraerCrudas(p).length, 1);
    });

    test('anidado en detalles_completos', () {
      final p = {
        'detalles_completos': {
          'presentaciones': [fila(id: 1, idNom: 1, nombre: 'Unidad', cantidad: 1, esBase: true)],
        },
      };
      expect(PresentacionCadenaLocal.extraerCrudas(p).length, 1);
    });

    test('lista vacía en presentaciones cae al siguiente candidato', () {
      final p = {
        'presentaciones': <dynamic>[],
        'detalles_completos': {
          'presentaciones': [fila(id: 7, idNom: 1, nombre: 'Unidad', cantidad: 1, esBase: true)],
        },
      };
      final crudas = PresentacionCadenaLocal.extraerCrudas(p);
      expect(crudas.length, 1);
      expect(crudas.first['id'], 7);
    });

    test('producto sin presentaciones → lista vacía', () {
      expect(PresentacionCadenaLocal.extraerCrudas({'id': 1}), isEmpty);
      expect(PresentacionCadenaLocal.resolver({'id': 1}), isEmpty);
    });

    test('filas sin id se descartan', () {
      final crudas = [
        {'cantidad': 5, 'es_base': true},
        fila(id: 9, idNom: 1, nombre: 'Unidad', cantidad: 1, esBase: true),
      ];
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(
        crudas.map((e) => Map<String, dynamic>.from(e)).toList(),
      );
      expect(cadena.length, 1);
      expect(cadena.single.idPresentacion, 9);
    });

    test('nombre plano cuando no viene anidado', () {
      final crudas = [
        {'id': 3, 'id_presentacion': 1, 'denominacion': 'Saco', 'cantidad': 50, 'es_base': true},
      ];
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena.single.nombre, 'Saco');
    });

    test('sin cantidad asume 1, como el COALESCE del SQL', () {
      final crudas = [
        {'id': 4, 'id_presentacion': 1, 'denominacion': 'Unidad', 'es_base': true},
      ];
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      expect(cadena.single.factor, 1.0);
      expect(cadena.single.factorRel, 1.0);
    });
  });

  group('FormatoPresentacion — paridad con el SQL', () {
    test('plural', () {
      expect(FormatoPresentacion.plural('Caja', 4), 'Cajas');
      expect(FormatoPresentacion.plural('Caja', 1), 'Caja');
      expect(FormatoPresentacion.plural('Unidad', 4), 'Unidades');
      expect(FormatoPresentacion.plural('Cartón', 3), 'Cartones');
      expect(FormatoPresentacion.plural('Blister', 2), 'Blisteres');
      expect(FormatoPresentacion.plural('Bolsas', 5), 'Bolsas');
      expect(FormatoPresentacion.plural('Pallet', 2), 'Palletes');
      expect(FormatoPresentacion.plural(null, 3), '');
    });

    test('cantidad', () {
      expect(FormatoPresentacion.cantidad(4), '4');
      expect(FormatoPresentacion.cantidad(1.5), '1.5');
      expect(FormatoPresentacion.cantidad(null), '0');
      expect(FormatoPresentacion.cantidad(-4), '-4');
      expect(FormatoPresentacion.cantidad(1.9999), '2');
    });

    test('mixto omite ceros', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas([
        fila(id: 1, idNom: 3, nombre: 'Caja', cantidad: 12, esBase: false),
        fila(id: 2, idNom: 1, nombre: 'Unidad', cantidad: 1, esBase: true),
      ]);
      expect(FormatoPresentacion.mixto(cadena, {1: 0, 2: 11}), '11 Unidades');
      expect(FormatoPresentacion.mixto(cadena, {}), 'Sin cantidad');
    });

    test('equivalencia por eslabón', () {
      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas([
        fila(id: 1, idNom: 3, nombre: 'Caja', cantidad: 12, esBase: false),
        fila(id: 2, idNom: 1, nombre: 'Unidad', cantidad: 1, esBase: true),
      ]);
      expect(
        FormatoPresentacion.equivalencia(cadena[0], 'Unidad'),
        '1 Caja = 12 Unidades',
      );
      expect(
        FormatoPresentacion.equivalencia(cadena[1], 'Unidad'),
        'presentación base',
      );
    });
  });
}
