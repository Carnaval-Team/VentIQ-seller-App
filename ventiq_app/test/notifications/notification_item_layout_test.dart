// Regresión del ítem de notificación.
//
// El bug: el ítem envolvía su contenido en un `Row` con
// `CrossAxisAlignment.stretch` directamente dentro del `ListView` del panel.
// Un `ListView` mide a sus hijos con altura INFINITA, y `stretch` intenta
// estirarlos a esa altura → «BoxConstraints forces an infinite height» en
// `performLayout`. Cada ítem fallaba al medirse y el panel quedaba **en blanco**
// aunque el contador dijera «N sin leer».
//
// Este test monta el widget real dentro de un `ListView`, que es la condición
// que lo rompía, y exige que se mida y que su título se vea.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_app/models/notification_model.dart';
import 'package:ventiq_app/services/notification_service.dart';
import 'package:ventiq_app/widgets/notification_widget.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // `Supabase.initialize` guarda la sesión con shared_preferences, que es un
    // plugin y no existe en el entorno de test. Sin este mock lanza
    // `MissingPluginException` y **cuelga el runner**: es la razón por la que en
    // este proyecto montar pantallas con Supabase no se hacía en tests.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // El servicio es un singleton que toma `Supabase.instance.client` al
    // construirse. Se inicializa con valores de mentira: no se hace red.
    await Supabase.initialize(
      url: 'https://ejemplo.supabase.co',
      anonKey: 'clave-de-prueba',
    );
  });

  NotificationModel _notificacion({required bool leida}) => NotificationModel(
    id: 1,
    userId: 'u-1',
    tipo: NotificationType.venta,
    titulo: 'Venta registrada',
    mensaje: 'Se registró una venta de prueba.',
    prioridad: NotificationPriority.normal,
    leida: leida,
    archivada: false,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Future<void> montar(WidgetTester tester, NotificationModel n) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            // La condición exacta del bug: un ListView mide con altura infinita.
            child: ListView(
              children: <Widget>[
                NotificationItem(
                  notification: n,
                  notificationService: NotificationService(),
                  onTap: () {},
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('sin leer: se mide dentro del ListView y se ve el título', (
    tester,
  ) async {
    await montar(tester, _notificacion(leida: false));

    expect(
      tester.takeException(),
      isNull,
      reason: 'el ítem no puede reventar al medirse dentro del ListView',
    );
    expect(find.text('Venta registrada'), findsOneWidget);
  });

  testWidgets('leída: se mide igual', (tester) async {
    await montar(tester, _notificacion(leida: true));

    expect(tester.takeException(), isNull);
    expect(find.text('Venta registrada'), findsOneWidget);
  });
}
