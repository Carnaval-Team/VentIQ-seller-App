import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_admin_app/services/user_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('updateAccessToken alinea expiry con Session.expiresAt (segundos)', () async {
    final prefs = UserPreferencesService();
    const expiresAtSec = 1_900_000_000; // ~2030

    await prefs.updateAccessToken('jwt-rotado', expiresAt: expiresAtSec);

    expect(await prefs.getAccessToken(), 'jwt-rotado');
    expect(await prefs.isLoggedIn(), isTrue);
    expect(await prefs.isTokenValid(), isTrue);
    expect(await prefs.hasValidSession(), isTrue);
  });

  test('saveUserData con tokenExpiresAt no usa el techo fijo de 24h', () async {
    final prefs = UserPreferencesService();
    final farFutureSec =
        DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch ~/
        1000;

    await prefs.saveUserData(
      userId: 'u1',
      email: 'a@b.c',
      accessToken: 'jwt',
      tokenExpiresAt: farFutureSec,
    );

    expect(await prefs.isTokenValid(), isTrue);
    expect(await prefs.hasValidSession(), isTrue);
  });

  test('token caducado en prefs deja hasValidSession en false', () async {
    final prefs = UserPreferencesService();
    final pastSec =
        DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;

    await prefs.saveUserData(
      userId: 'u1',
      email: 'a@b.c',
      accessToken: 'jwt-viejo',
      tokenExpiresAt: pastSec,
    );

    expect(await prefs.isTokenValid(), isFalse);
    expect(await prefs.hasValidSession(), isFalse);
  });
}
