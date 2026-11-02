// Tests del alta rápida del Home (Fase 4.2):
//
//  * reglas puras de `QuickAddService.decidir`: solo se añade directo si hay
//    UNA presentación y UNA ubicación, sin promoción ni nada que elegir;
//  * guardas de `agregar` (stock, promoción con la cantidad final, órdenes
//    pendientes);
//  * interacción de la hoja de cantidad (cargando → lista → agregar/cancelar).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/services/quick_add_service.dart';
import 'package:ventiq_app/widgets/home/quick_add_sheet.dart';

// ── Datos de apoyo ─────────────────────────────────────────────────────────

const Map<String, dynamic> _meta = <String, dynamic>{
  'id_inventario': 99,
  'id_variante': null,
  'id_opcion_variante': null,
  'id_presentacion': 10951,
  'id_ubicacion': 349,
  'id_almacen': 331,
  'sku_producto': 'SKU-10808',
  'sku_ubicacion': 'UBI-349',
  'cantidad_disponible': 5,
  'presentacion_nombre': 'Caja',
  'presentacion_factor_rel': 1.0,
  'ubicacion_nombre': 'refrigerada',
  'almacen_nombre': 'Caja 1',
};

ProductVariant _variante({
  int id = 1,
  double precio = 12,
  double stock = 5,
  Map<String, dynamic>? meta,
}) => ProductVariant(
  id: id,
  nombre: 'Caja',
  precio: precio,
  cantidad: stock,
  inventoryMetadata: meta ?? _meta,
);

Product _producto({
  int id = 10808,
  String nombre = 'Jugo de Limón Concentrado',
  double precio = 12,
  double stock = 5,
  int presentaciones = 1,
  bool elaborado = false,
  bool servicio = false,
  List<ProductVariant>? variantes,
}) => Product(
  id: id,
  denominacion: nombre,
  precio: precio,
  cantidad: stock,
  esRefrigerado: false,
  esFragil: false,
  esPeligroso: false,
  esVendible: true,
  esComprable: true,
  esInventariable: true,
  esPorLotes: false,
  esElaborado: elaborado,
  esServicio: servicio,
  categoria: 'Alimentos',
  variantes:
      variantes ?? <ProductVariant>[_variante(precio: precio, stock: stock)],
  presentacionesCount: presentaciones,
);

QuickAddEvaluacion _decidir(
  Product producto, {
  QuickAddPromociones promociones = const QuickAddPromociones(),
  double cantidad = 1,
  bool esServicio = false,
  bool esElaborado = false,
  double? elaborable,
  List<ProductPresentation>? presentaciones,
}) => QuickAddService.decidir(
  producto: producto,
  promociones: promociones,
  cantidad: cantidad,
  esServicio: esServicio,
  esElaborado: esElaborado,
  elaborable: elaborable,
  presentaciones: presentaciones,
);

const Map<String, dynamic> _promoMin1 = <String, dynamic>{
  'id': 1,
  'id_tipo_promocion': 1,
  'valor_descuento': 10.0,
  'min_compra': 1,
};

const Map<String, dynamic> _promoMin3 = <String, dynamic>{
  'id': 2,
  'id_tipo_promocion': 1,
  'valor_descuento': 10.0,
  'min_compra': 3,
};

Future<void> _nada({
  required Product producto,
  required ProductVariant? variante,
  required double cantidad,
  required String ubicacionAlmacen,
  required Map<String, dynamic> inventoryData,
  required double precioUnitario,
  required double precioBase,
  Map<String, dynamic>? promotionData,
}) async {}

void main() {
  group('regla: cuándo se puede añadir sin abrir el detalle', () {
    test('1 presentación + 1 ubicación + sin promo ⇒ listo', () {
      final QuickAddEvaluacion e = _decidir(_producto());

      expect(e.estado, QuickAddEstado.listo);
      final QuickAddPreparado p = e.preparado!;
      expect(p.producto.id, 10808);
      expect(p.stockDisponible, 5);
      expect(p.factorPresentacion, 1);
      expect(p.precioUnitario, 12);
      expect(p.ubicacion, 'Caja 1 - refrigerada');
      expect(p.inventoryData['id_producto'], 10808);
      expect(p.inventoryData['id_ubicacion'], 349);
      expect(p.inventoryData['id_presentacion'], 10951);
      expect(p.inventoryData['sku_producto'], 'SKU-10808');
    });

    test('el factor de la presentación multiplica el precio', () {
      final Map<String, dynamic> meta = <String, dynamic>{
        ..._meta,
        'presentacion_factor_rel': 24.0,
        'presentacion_nombre': 'Bulto',
      };
      final QuickAddEvaluacion e = _decidir(
        _producto(
          precio: 2,
          variantes: <ProductVariant>[_variante(precio: 2, meta: meta)],
        ),
      );

      expect(e.estado, QuickAddEstado.listo);
      expect(e.preparado!.precioUnitario, 48);
      expect(e.preparado!.factorPresentacion, 24);
    });

    test('varias ubicaciones/variantes ⇒ detalle', () {
      final QuickAddEvaluacion e = _decidir(
        _producto(
          variantes: <ProductVariant>[
            _variante(),
            _variante(id: 2, meta: {..._meta, 'id_ubicacion': 353}),
          ],
        ),
      );

      expect(e.estado, QuickAddEstado.requiereDetalle);
      expect(e.motivo, contains('varias ubicaciones'));
    });

    test('varias presentaciones ⇒ detalle aunque solo haya una con stock', () {
      final QuickAddEvaluacion e = _decidir(_producto(presentaciones: 3));

      expect(e.estado, QuickAddEstado.requiereDetalle);
      expect(e.motivo, contains('varias presentaciones'));
    });

    test(
      'producto elaborado con 1 presentación/ubicación ⇒ se añade directo',
      () {
        // Elaborado ya no se manda al detalle si es inequívoco: el pedido a
        // cocina y los ingredientes los resuelve OrderService igual que el
        // detalle.
        final QuickAddEvaluacion e = _decidir(_producto(elaborado: true));

        expect(e.estado, QuickAddEstado.listo);
        expect(e.preparado!.producto.esElaborado, isTrue);
      },
    );

    test('servicio o paquete ⇒ detalle', () {
      expect(
        _decidir(_producto(servicio: true), esServicio: true).estado,
        QuickAddEstado.requiereDetalle,
      );
      expect(
        _decidir(_producto()).estado,
        QuickAddEstado.listo,
        reason: 'un producto normal no se bloquea',
      );
    });

    test(
      'elaborado sin saldo propio ⇒ detalle (puede venderse por ingredientes)',
      () {
        final QuickAddEvaluacion e = _decidir(
          _producto(elaborado: true, stock: 0),
        );

        expect(e.estado, QuickAddEstado.requiereDetalle);
        expect(e.motivo, contains('ingredientes'));
      },
    );

    test('sin stock ⇒ sinStock, no abre detalle', () {
      final QuickAddEvaluacion e = _decidir(_producto(stock: 0));

      expect(e.estado, QuickAddEstado.sinStock);
    });

    test('promoción que ya aplica con 1 ⇒ detalle (no duplicar precios)', () {
      final QuickAddEvaluacion e = _decidir(
        _producto(),
        promociones: const QuickAddPromociones(
          producto: <Map<String, dynamic>>[_promoMin1],
        ),
      );

      expect(e.estado, QuickAddEstado.requiereDetalle);
      expect(e.motivo, contains('promoción'));
    });

    test('promoción global ⇒ detalle', () {
      final QuickAddEvaluacion e = _decidir(
        _producto(),
        promociones: const QuickAddPromociones(
          global: <String, dynamic>{
            'id': 9,
            'aplica_todo': true,
            'id_tipo_promocion': 1,
            'valor_descuento': 5.0,
          },
        ),
      );

      expect(e.estado, QuickAddEstado.requiereDetalle);
    });

    test('promoción con mínimo 3 no bloquea la compra de 1', () {
      // Con 1 unidad no aplica; se permite el alta rápida. La cantidad final se
      // revisa al agregar.
      final QuickAddEvaluacion e = _decidir(
        _producto(),
        promociones: const QuickAddPromociones(
          producto: <Map<String, dynamic>>[_promoMin3],
        ),
      );

      expect(e.estado, QuickAddEstado.listo);
    });
  });

  group('elaborados: se venden por materia prima, no por su stock propio', () {
    ProductPresentation unidad({int id = 10943, double factor = 1}) {
      return ProductPresentation(
        id: id,
        idProducto: 10800,
        idPresentacion: 1,
        cantidad: factor,
        esBase: true,
        presentacion: Presentation(
          id: 1,
          denominacion: 'Unidad',
          skuCodigo: 'UN',
        ),
      );
    }

    test(
      'usa la disponibilidad elaborable y no el stock de la fila de barra',
      () {
        // Caso real: 10800 tacos. En barra queda 1 unidad suelta, pero la cocina
        // tiene materia prima para 41000.
        final QuickAddEvaluacion e = _decidir(
          _producto(
            id: 10800,
            nombre: 'tacos',
            elaborado: true,
            variantes: const <ProductVariant>[],
          ),
          esElaborado: true,
          elaborable: 41000,
          presentaciones: <ProductPresentation>[unidad()],
        );

        expect(e.estado, QuickAddEstado.listo);
        final QuickAddPreparado p = e.preparado!;
        expect(p.stockDisponible, 41000);
        expect(p.variante, isNull, reason: 'se consume receta, no SKU propio');
        expect(
          p.inventoryData['id_ubicacion'],
          isNull,
          reason: 'el servidor resuelve la ubicación de la cocina',
        );
        expect(p.inventoryData['id_presentacion'], 10943);
        expect(p.precioUnitario, 12);
      },
    );

    test('sin materia prima suficiente ⇒ sinStock con motivo explícito', () {
      final QuickAddEvaluacion e = _decidir(
        _producto(elaborado: true, variantes: const <ProductVariant>[]),
        esElaborado: true,
        elaborable: 0,
        presentaciones: <ProductPresentation>[unidad()],
      );

      expect(e.estado, QuickAddEstado.sinStock);
      expect(e.motivo, contains('materia prima'));
    });

    test('elaborado con varias presentaciones ⇒ detalle', () {
      final QuickAddEvaluacion e = _decidir(
        _producto(elaborado: true, variantes: const <ProductVariant>[]),
        esElaborado: true,
        elaborable: 10,
        presentaciones: <ProductPresentation>[unidad(id: 1), unidad(id: 2)],
      );

      expect(e.estado, QuickAddEstado.requiereDetalle);
      expect(e.motivo, contains('varias presentaciones'));
    });

    test('el factor de la presentación multiplica el precio', () {
      final QuickAddEvaluacion e = _decidir(
        _producto(
          elaborado: true,
          precio: 2,
          variantes: const <ProductVariant>[],
        ),
        esElaborado: true,
        elaborable: 10,
        presentaciones: <ProductPresentation>[unidad(factor: 24)],
      );

      expect(e.preparado!.factorPresentacion, 24);
      expect(e.preparado!.precioUnitario, 48);
    });

    test('servicio con disponibilidad no entra por la rama de elaborado', () {
      final QuickAddEvaluacion e = _decidir(
        _producto(servicio: true, variantes: const <ProductVariant>[]),
        esServicio: true,
        esElaborado: true,
        elaborable: 10,
      );

      expect(e.estado, QuickAddEstado.requiereDetalle);
    });
  });

  group('agregar al carrito', () {
    QuickAddService servicio({
      required Future<void> Function({
        required Product producto,
        required ProductVariant? variante,
        required double cantidad,
        required String ubicacionAlmacen,
        required Map<String, dynamic> inventoryData,
        required double precioUnitario,
        required double precioBase,
        Map<String, dynamic>? promotionData,
      })
      agregarItem,
      Future<Map<String, dynamic>?> Function()? storeConfig,
      Future<bool> Function()? pendientes,
    }) => QuickAddService(
      agregarItem: agregarItem,
      cargarStoreConfig: storeConfig ?? () async => null,
      hayOrdenesPendientes: pendientes,
    );

    test(
      'manda a la orden el precio con factor y los ids del inventario',
      () async {
        final List<Map<String, dynamic>> llamadas = <Map<String, dynamic>>[];
        final QuickAddService s = servicio(
          agregarItem: ({
            required Product producto,
            required ProductVariant? variante,
            required double cantidad,
            required String ubicacionAlmacen,
            required Map<String, dynamic> inventoryData,
            required double precioUnitario,
            required double precioBase,
            Map<String, dynamic>? promotionData,
          }) async {
            llamadas.add(<String, dynamic>{
              'cantidad': cantidad,
              'precio': precioUnitario,
              'ubicacion': ubicacionAlmacen,
              'inventory': inventoryData,
            });
          },
        );

        final QuickAddEvaluacion e = _decidir(
          _producto(
            precio: 2,
            variantes: <ProductVariant>[
              _variante(
                precio: 2,
                meta: {..._meta, 'presentacion_factor_rel': 24.0},
              ),
            ],
          ),
        );

        final QuickAddResultado r = await s.agregar(e.preparado!, 2);

        expect(r.agregado, isTrue);
        expect(llamadas.single['cantidad'], 2);
        expect(llamadas.single['precio'], 48);
        expect(llamadas.single['ubicacion'], 'Caja 1 - refrigerada');
        expect(
          (llamadas.single['inventory']
              as Map<String, dynamic>)['id_ubicacion'],
          349,
        );
      },
    );

    test('no deja vender más que el stock disponible', () async {
      final QuickAddService s = servicio(agregarItem: _nada);
      final QuickAddEvaluacion e = _decidir(_producto(stock: 5));

      expect(
        () => s.agregar(e.preparado!, 6),
        throwsA(
          isA<QuickAddException>().having(
            (QuickAddException ex) => ex.mensaje,
            'mensaje',
            contains('Solo hay 5'),
          ),
        ),
      );
    });

    test('cantidad 0 no es válida', () async {
      final QuickAddService s = servicio(agregarItem: _nada);
      final QuickAddEvaluacion e = _decidir(_producto());

      expect(
        () => s.agregar(e.preparado!, 0),
        throwsA(isA<QuickAddException>()),
      );
    });

    test(
      'si con la cantidad final aparece una promoción, manda al detalle',
      () async {
        int agregados = 0;
        final QuickAddService s = servicio(
          agregarItem: ({
            required Product producto,
            required ProductVariant? variante,
            required double cantidad,
            required String ubicacionAlmacen,
            required Map<String, dynamic> inventoryData,
            required double precioUnitario,
            required double precioBase,
            Map<String, dynamic>? promotionData,
          }) async {
            agregados++;
          },
        );

        final QuickAddEvaluacion e = _decidir(
          _producto(),
          promociones: const QuickAddPromociones(
            producto: <Map<String, dynamic>>[_promoMin3],
          ),
        );

        final QuickAddResultado r = await s.agregar(e.preparado!, 3);

        expect(r.requiereDetalle, isTrue);
        expect(
          agregados,
          0,
          reason: 'no debe vender con un precio promocional mal calculado',
        );
      },
    );

    test('respeta la guarda de órdenes pendientes de la tienda', () async {
      final QuickAddService s = servicio(
        agregarItem: _nada,
        storeConfig:
            () async => <String, dynamic>{
              'need_all_orders_completed_to_continue': true,
            },
        pendientes: () async => true,
      );
      final QuickAddEvaluacion e = _decidir(_producto());

      expect(
        () => s.agregar(e.preparado!, 1),
        throwsA(
          isA<QuickAddException>().having(
            (QuickAddException ex) => ex.mensaje,
            'mensaje',
            contains('órdenes pendientes'),
          ),
        ),
      );
    });
  });

  group('hoja de cantidad', () {
    testWidgets('carga, deja elegir cantidad y devuelve el alta', (
      WidgetTester tester,
    ) async {
      final Completer<QuickAddEvaluacion> evaluando =
          Completer<QuickAddEvaluacion>();
      double? agregada;
      QuickAddSalida? salida;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (BuildContext context) => ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet<QuickAddSalida>(
                        context: context,
                        isScrollControlled: true,
                        builder:
                            (_) => QuickAddSheet(
                              nombreProducto: 'Jugo de Limón Concentrado',
                              evaluar: () => evaluando.future,
                              agregar: (
                                QuickAddPreparado p,
                                double cantidad,
                              ) async {
                                agregada = cantidad;
                                return QuickAddResultado.agregado(p.producto);
                              },
                            ),
                      ).then((QuickAddSalida? value) => salida = value);
                    },
                    child: const Text('abrir'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Comprobando presentación'), findsOneWidget);

      final QuickAddEvaluacion listo = _decidir(_producto());
      evaluando.complete(listo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Agregar al carrito'), findsOneWidget);
      expect(
        find.textContaining('Ubicación: Caja 1 - refrigerada'),
        findsOneWidget,
      );
      expect(find.text('Disponible: 5'), findsOneWidget);

      // Subir la cantidad con el «+» dos veces: 1 → 3.
      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await tester.pump();

      final TextField campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.controller!.text, '3');

      await tester.tap(find.text('Agregar al carrito'));
      await tester.pumpAndSettle();

      expect(agregada, 3);
      expect(salida, isNotNull);
      expect(salida!.tipo, QuickAddSalidaTipo.agregado);
      expect(salida!.cantidad, 3);
    });

    testWidgets('si el producto no es inequívoco se cierra y pide el detalle', (
      WidgetTester tester,
    ) async {
      QuickAddSalida? salida;
      final QuickAddEvaluacion detalle = _decidir(_producto(presentaciones: 2));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (BuildContext context) => ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet<QuickAddSalida>(
                        context: context,
                        isScrollControlled: true,
                        builder:
                            (_) => QuickAddSheet(
                              nombreProducto: 'Jugo de Limón Concentrado',
                              evaluar: () async => detalle,
                              agregar:
                                  (
                                    QuickAddPreparado p,
                                    double cantidad,
                                  ) async =>
                                      QuickAddResultado.agregado(p.producto),
                            ),
                      ).then((QuickAddSalida? value) => salida = value);
                    },
                    child: const Text('abrir'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Agregar al carrito'), findsNothing);
      expect(salida, isNotNull);
      expect(salida!.tipo, QuickAddSalidaTipo.requiereDetalle);
      expect(salida!.producto!.id, 10808);
    });

    testWidgets('un error de la orden se queda en la hoja, no la cierra', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (BuildContext context) => ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet<QuickAddSalida>(
                        context: context,
                        isScrollControlled: true,
                        builder:
                            (_) => QuickAddSheet(
                              nombreProducto: 'Jugo de Limón Concentrado',
                              evaluar: () async => _decidir(_producto()),
                              agregar: (
                                QuickAddPreparado p,
                                double cantidad,
                              ) async {
                                throw QuickAddException(
                                  'Hay órdenes pendientes.',
                                );
                              },
                            ),
                      );
                    },
                    child: const Text('abrir'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Agregar al carrito'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Hay órdenes pendientes.'), findsOneWidget);
      expect(find.text('Agregar al carrito'), findsOneWidget);
    });
  });
}
