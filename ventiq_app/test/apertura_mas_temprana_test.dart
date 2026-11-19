import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';

void main() {
  test('la apertura offline real gana a la del servidor con hora del sync', () {
    // Turno 3533 de main: apertura offline 14:36 de Cuba, servidor 16:07.
    const local = '2026-11-17T14:36:20.000-05:00';
    const servidor = '2026-11-17T16:07:17.550868-05:00';

    expect(UserPreferencesService.aperturaMasTemprana(local, servidor), local);
  });

  test('si el servidor es anterior, se usa la del servidor', () {
    const local = '2026-11-17T10:00:00.000-05:00';
    const servidor = '2026-11-17T07:00:14.556538-05:00';

    expect(
      UserPreferencesService.aperturaMasTemprana(local, servidor),
      servidor,
    );
  });

  test('compara instantes aunque una venga sin offset y otra en UTC', () {
    final localSinOffset = DateTime(2026, 11, 18, 8).toIso8601String();
    final servidorUtc =
        DateTime(2026, 11, 18, 9).toUtc().toIso8601String();

    expect(
      UserPreferencesService.aperturaMasTemprana(localSinOffset, servidorUtc),
      localSinOffset,
    );
  });

  test('sin una de las dos fechas devuelve la otra', () {
    const servidor = '2026-11-17T16:07:17.550868-05:00';

    expect(UserPreferencesService.aperturaMasTemprana(null, servidor), servidor);
    expect(UserPreferencesService.aperturaMasTemprana(servidor, null), servidor);
    expect(UserPreferencesService.aperturaMasTemprana(null, null), isNull);
  });
}
