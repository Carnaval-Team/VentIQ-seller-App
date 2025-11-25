// Test básico para Inventtia Super Admin
//
// Este test verifica que la aplicación se inicializa correctamente
// y muestra la pantalla de login cuando no hay usuario autenticado.

import 'package:flutter_test/flutter_test.dart';

import 'package:ventiq_superadmin/main.dart';

void main() {
  testWidgets('App initialization test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const VentIQSuperAdminApp());

    // Wait for the auth check to complete
    await tester.pumpAndSettle();

    // Verify that login screen is shown
    expect(find.text('Inventtia Super Admin'), findsOneWidget);
    expect(find.text('Sistema de Administración Global'), findsOneWidget);
    expect(find.text('Correo Electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Iniciar Sesión'), findsOneWidget);
  });
}
