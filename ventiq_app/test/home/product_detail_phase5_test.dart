// Fase 5 · detalle de producto: piezas extraídas y perezosas.
//
//  * `ProductDetailService.productoDesdeRespuestaDetalle`: un solo parser para
//    online y offline (antes la pantalla duplicaba ~140 líneas).
//  * `ElaboratedProductChip` perezoso: con los flags ya resueltos no hace red al
//    montarse (R14).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/services/product_detail_service.dart';
import 'package:ventiq_app/widgets/elaborated_product_chip.dart';

Map<String, dynamic> _respuestaDetalle() => <String, dynamic>{
  'producto': <String, dynamic>{
    'id': 10800,
    'denominacion': 'tacos',
    'descripcion': 'Tacos de la casa',
    'precio_actual': 12,
    'es_refrigerado': false,
    'es_fragil': false,
    'es_peligroso': false,
    'es_elaborado': true,
    'es_servicio': false,
    'es_paquete': false,
    'es_por_lotes': false,
    'categoria': <String, dynamic>{'id': 1112, 'denominacion': 'Alimentos'},
    'presentaciones': <dynamic>[
      <String, dynamic>{'id': 10943, 'cantidad': 1, 'es_base': true},
    ],
    'multimedias': null,
    'foto': null,
    'imagen': null,
  },
  'inventario': <dynamic>[
    <String, dynamic>{
      'id_inventario': 344351,
      'variante': null,
      'presentacion': <String, dynamic>{
        'id': 10943,
        'denominacion': 'Unidad',
        'cantidad': 1,
      },
      'ubicacion': <String, dynamic>{
        'id': 350,
        'denominacion': 'cuarto oscuro legumbres',
        'almacen': <String, dynamic>{'id': 331, 'denominacion': 'Caja 1'},
      },
      'cantidad_disponible': 5,
      'reservado_carnaval': 0,
      'en_ordenes_carnaval': 0,
    },
  ],
};

void main() {
  group('productoDesdeRespuestaDetalle', () {
    test('convierte producto + inventario a Product con sus variantes', () {
      final Product p = ProductDetailService.productoDesdeRespuestaDetalle(
        _respuestaDetalle(),
      );

      expect(p.id, 10800);
      expect(p.denominacion, 'tacos');
      expect(p.precio, 12);
      expect(p.categoria, 'Alimentos');
      expect(p.esElaborado, isTrue);
      expect(p.esServicio, isFalse);
      expect(p.cantidad, 5);
      expect(p.variantes, hasLength(1));

      final ProductVariant v = p.variantes.single;
      expect(v.cantidad, 5);
      expect(v.inventoryMetadata?['id_ubicacion'], 350);
      expect(v.inventoryMetadata?['id_presentacion'], 10943);
      expect(v.inventoryMetadata?['almacen_nombre'], 'Caja 1');
      // El contador de presentaciones es lo que usa el alta rápida.
      expect(p.presentacionesCount, 1);
    });

    test('sin inventario usa el stock del listado como fallback', () {
      final Map<String, dynamic> respuesta = _respuestaDetalle();
      respuesta['inventario'] = <dynamic>[];

      final Product p = ProductDetailService.productoDesdeRespuestaDetalle(
        respuesta,
        fallbackStock: 7,
      );

      expect(p.variantes, isEmpty);
      expect(p.cantidad, 7);
    });
  });

  group('ElaboratedProductChip perezoso', () {
    Future<void> montar(WidgetTester tester, ElaboratedProductChip chip) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: chip))),
      );
      await tester.pump();
    }

    testWidgets('con flags resueltos pinta ELAB sin consultar ingredientes', (
      WidgetTester tester,
    ) async {
      await montar(
        tester,
        const ElaboratedProductChip(
          productId: 10800,
          productName: 'tacos',
          esElaborado: true,
          esServicio: false,
        ),
      );

      expect(find.text('ELAB'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('servicio pinta SERV', (WidgetTester tester) async {
      await montar(
        tester,
        const ElaboratedProductChip(
          productId: 1,
          productName: 'Corte',
          esElaborado: true,
          esServicio: true,
        ),
      );

      expect(find.text('SERV'), findsOneWidget);
    });

    testWidgets('producto normal no pinta nada', (WidgetTester tester) async {
      await montar(
        tester,
        const ElaboratedProductChip(
          productId: 2,
          productName: 'Sal',
          esElaborado: false,
          esServicio: false,
        ),
      );

      expect(find.text('ELAB'), findsNothing);
      expect(find.text('SERV'), findsNothing);
    });
  });
}
