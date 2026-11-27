// Aviso flotante de «producto agotado».
//
// Lo que se fija aquí:
//  * Sólo las notificaciones de inventario CON producto pasan el filtro; una
//    venta o un «producto disponible» no deben abrir el aviso grande.
//  * La tarjeta se pinta con el producto en el título y «almacén · ubicación»
//    debajo, que es lo que pidió el negocio («se acabó en tal almacén, tal
//    ubicación»).
//  * Se cierra sola al agotar su tiempo y al pulsar la X.
//  * Entra en el Overlay real (sin BuildContext de pantalla) y se quita sin
//    dejar el árbol roto.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/notification_model.dart';
import 'package:ventiq_app/widgets/aviso_producto_agotado.dart';
import 'package:ventiq_app/utils/global_navigator.dart';

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
    }) async {
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
        navigatorKey: globalNavigatorKey,
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
