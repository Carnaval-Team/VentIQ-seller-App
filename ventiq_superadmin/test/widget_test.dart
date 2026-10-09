// Test básico para Inventtia Super Admin
//
// Este test verifica que la aplicación se inicializa correctamente
// y muestra la pantalla de login cuando no hay usuario autenticado.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ventiq_superadmin/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Sin esto `AuthService.isLoggedIn()` se queda esperando a
    // `SharedPreferences.getInstance()` y `AuthWrapper` no sale nunca del
    // `CircularProgressIndicator`: el `pumpAndSettle` expira y el test no llega
    // a mirar la pantalla.
    //
    // Con las preferencias vacías, `isLoggedIn` es `false` y no se entra en
    // `checkAuthStatus()`, así que tampoco hace falta inicializar Supabase.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

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