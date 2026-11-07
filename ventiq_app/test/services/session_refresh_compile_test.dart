// Guardia de compilación de `SessionRefreshService`.
//
// Este fichero llegó a romper el build **web** (`dart2js`) usando
// `AuthState.signOutReason` / `SignOutReason`, que no existen en la versión de
// `gotrue` que resuelve el lock (2.13.0). Los tests no lo detectaron porque
// **no lo importaba ningún test**: `flutter test` solo compila lo que alcanza
// desde cada fichero de test, así que un servicio que nadie importa puede
// quedarse roto sin que la suite se entere.
//
// Importarlo y referenciarlo aquí obliga al compilador a validarlo en cada
// `flutter test`, que es la vía barata de que no vuelva a pasar. Es el mismo
// truco que `test/home/app_compile_test.dart` y nace de la misma lección.
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/services/session_refresh_service.dart';

void main() {
  test('SessionRefreshService se construye y es singleton', () {
    // El constructor no toca Supabase ni SharedPreferences: `_client` es un
    // getter perezoso, así que instanciarlo aquí no necesita red ni plugins.
    final SessionRefreshService primero = SessionRefreshService();
    final SessionRefreshService segundo = SessionRefreshService();

    expect(identical(primero, segundo), isTrue);
  });
}