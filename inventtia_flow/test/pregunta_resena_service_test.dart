import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/pregunta_resena_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reglas de "a quién se le pide la reseña", que es lo que evita que el cartel
/// se convierta en un incordio.
///
/// Lo importante: **una vez por reserva** aunque el usuario cierre sin escribir,
/// **una por sesión** (no se encadenan carteles si tiene varias pendientes) y
/// nunca se repite por el mismo servicio.
///
/// `ResenaService.pendientes()` no se puede mockear aquí sin inyectar Supabase,
/// así que lo que se prueba es el estado que gobierna el servicio: la marca de
/// sesión y el historial persistido. La consulta al servidor ya está cubierta
/// por contrato en `resena_pendiente_test` (forma del JSON).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PreguntaResenaService.limpiar();
  });

  group('marca de sesión', () {
    test('arranca sin haber preguntado', () {
      expect(PreguntaResenaService.yaPreguntadoEnEstaSesion, isFalse);
    });

    test('marcar una reserva deja la sesión como usada', () async {
      await PreguntaResenaService.marcarPreguntada(41);
      expect(PreguntaResenaService.yaPreguntadoEnEstaSesion, isTrue);
    });

    test('reiniciarSesion vuelve a permitir preguntar', () async {
      await PreguntaResenaService.marcarPreguntada(41);
      PreguntaResenaService.reiniciarSesion();
      expect(PreguntaResenaService.yaPreguntadoEnEstaSesion, isFalse);
    });

    test('limpiar borra también el historial persistido', () async {
      await PreguntaResenaService.marcarPreguntada(41);
      await PreguntaResenaService.limpiar();
      expect(PreguntaResenaService.yaPreguntadoEnEstaSesion, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('flow_resenas_pedidas'), isNull);
    });
  });

  group('una sola vez por sesión', () {
    test('tras preguntar, siguientePendiente no devuelve nada', () async {
      // Es la regla que impide encadenar carteles: si tiene tres reservas sin
      // reseñar, solo se le pide una por entrada a la app.
      await PreguntaResenaService.marcarPreguntada(41);
      final siguiente = await PreguntaResenaService.siguientePendiente();
      expect(siguiente, isNull);
    });
  });

  group('historial de reservas ya pedidas', () {
    test('guarda el id como texto y no lo duplica', () async {
      await PreguntaResenaService.marcarPreguntada(41);
      await PreguntaResenaService.marcarPreguntada(41);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('flow_resenas_pedidas'), <String>['41']);
    });

    test('acumula reservas distintas (una por reserva)', () async {
      // Cada reserva nueva se recuerda aparte: es lo que permite pedir la
      // reseña de un servicio diferente sin volver a pedir la anterior.
      await PreguntaResenaService.marcarPreguntada(41);
      PreguntaResenaService.reiniciarSesion();
      await PreguntaResenaService.marcarPreguntada(42);
      PreguntaResenaService.reiniciarSesion();
      await PreguntaResenaService.marcarPreguntada(43);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('flow_resenas_pedidas'),
        <String>['41', '42', '43'],
      );
    });

    test('no crece sin freno: conserva las últimas 60', () async {
      for (var id = 1; id <= 65; id++) {
        PreguntaResenaService.reiniciarSesion();
        await PreguntaResenaService.marcarPreguntada(id);
      }
      final prefs = await SharedPreferences.getInstance();
      final guardadas = prefs.getStringList('flow_resenas_pedidas')!;
      expect(guardadas.length, 60);
      // Se tiran las más viejas, no las nuevas: una reserva antigua ya no va a
      // aparecer como pendiente.
      expect(guardadas.first, '6');
      expect(guardadas.last, '65');
    });

    test('un historial corrupto no rompe nada', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flow_resenas_pedidas': <String>['41', 'no-es-un-id', ''],
      });
      // No lanza: los valores no numéricos se descartan.
      await PreguntaResenaService.marcarPreguntada(42);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('flow_resenas_pedidas'), <String>['41', '42']);
    });
  });
}
