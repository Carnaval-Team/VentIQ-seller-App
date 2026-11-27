// Aviso flotante de «producto agotado» en el panel de administración.
//
// Fija lo mismo que el de la app de caja: sólo pasa el agotado (inventario con
// producto), la tarjeta pone el producto en el título y «almacén · ubicación»
// debajo, y se cierra sola, con la ✕ o con un tirón hacia arriba.
//
// Se añade además el tope de ancho: en el dashboard web la tarjeta se monta
// sobre una ventana de hasta 1600 px y sin `maxWidth` se estiraba de lado a
// lado, así que aquí el test comprueba que no pasa de 520.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/main.dart' show appNavigatorKey;
import 'package:ventiq_admin_app/models/notification_model.dart';
import 'package:ventiq_admin_app/widgets/aviso_producto_agotado.dart';

NotificationModel _agotado() => NotificationModel(
  id: 7,
  userId: 'u-1',
  tipo: NotificationType.inventario,
  titulo: 'Producto agotado',
  mensaje:
      'El producto "producto a invertir" se agotó en el almacén "almacen 1" '
      '(ubicación "la zona").',
  data: <String, dynamic>{
    'id_tienda': 9,
    'id_producto': 18,
    'id_almacen': 8,
    'id_ubicacion': 8,
    'producto_nombre': 'producto a invertir',
    'almacen_nombre': 'almacen 1',
    'ubicacion_nombre': 'la zona',
    'stock_actual': 0,
  },
  prioridad: NotificationPriority.alta,
  leida: false,
  archivada: false,
  createdAt: DateTime(2026, 11, 27, 10, 5),
  updatedAt: DateTime(2026, 11, 27, 10, 5),
);

void main() {
  tearDown(AvisoProductoAgotado.ocultarTodo);

  group('filtro', () {
    test('una notificación de agotado pasa', () {
      expect(AvisoProductoAgotado.esProductoAgotado(_agotado()), isTrue);
    });

    test('una venta no pasa', () {
      final NotificationModel venta = _agotado().copyWith(
        tipo: NotificationType.venta,
        titulo: 'Venta registrada',
      );
      expect(AvisoProductoAgotado.esProductoAgotado(venta), isFalse);
    });

    test('inventario sin producto (ej. disponible) no pasa', () {
      final NotificationModel disponible = _agotado().copyWith(
        titulo: 'Producto disponible',
        data: <String, dynamic>{'id_tienda': 9},
      );
      expect(AvisoProductoAgotado.esProductoAgotado(disponible), isFalse);
    });
  });

  group('tarjeta', () {
    Future<void> montar(
      WidgetTester tester, {
      VoidCallback? onCerrar,
      VoidCallback? onAbrir,
      Duration duracion = const Duration(seconds: 7),
      Size tamano = const Size(1600, 900),
    }) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                AvisoProductoAgotadoCard(
                  notificacion: _agotado(),
                  duracion: duracion,
                  onCerrar: onCerrar ?? () {},
                  onAbrir: onAbrir ?? () {},
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('muestra producto, almacén y ubicación', (tester) async {
      await montar(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      expect(find.text('PRODUCTO AGOTADO'), findsOneWidget);
      expect(find.text('producto a invertir'), findsOneWidget);
      expect(find.text('almacen 1 · la zona'), findsOneWidget);
    });

    testWidgets('en pantalla ancha no se estira sin tope', (tester) async {
      await montar(tester);
      await tester.pump(const Duration(milliseconds: 500));

      final Size caja = tester.getSize(
        find.byKey(const Key('aviso_agotado_tarjeta')),
      );
      expect(caja.width, lessThanOrEqualTo(520));
    });

    testWidgets('la X cierra el aviso', (tester) async {
      int cerrado = 0;
      await montar(tester, onCerrar: () => cerrado++);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(cerrado, 1);
    });

    testWidgets('se cierra solo al agotar su tiempo', (tester) async {
      int cerrado = 0;
      await montar(
        tester,
        onCerrar: () => cerrado++,
        duracion: const Duration(milliseconds: 300),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(cerrado, 0);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(cerrado, 1);
    });

    testWidgets('tocar la tarjeta la abre', (tester) async {
      int abierto = 0;
      await montar(tester, onAbrir: () => abierto++);
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('producto a invertir'));
      await tester.pumpAndSettle();

      expect(abierto, 1);
    });
  });

  testWidgets('mostrar() entra en el Overlay real y se puede quitar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    await tester.pump();

    AvisoProductoAgotado.mostrar(_agotado());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('producto a invertir'), findsOneWidget);

    AvisoProductoAgotado.ocultarTodo();
    await tester.pump();

    expect(find.text('producto a invertir'), findsNothing);
  });
}
