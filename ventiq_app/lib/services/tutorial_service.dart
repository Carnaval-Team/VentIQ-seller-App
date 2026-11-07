import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia del tutorial guiado de venta (normal y restaurante).
///
/// Se guarda en `SharedPreferences` con el uuid del usuario y el modo, de forma
/// que quien ya hizo el recorrido no lo vuelve a ver, pero un usuario nuevo (o
/// tras reiniciarlo) sí.
class TutorialService {
  TutorialService._();

  /// Subirla republica el tutorial para todos (una vez).
  static const String version = 'v1';

  static const String valorVisto = 'visto';
  static const String valorOmitido = 'omitido';

  static String _clave(String uuidUsuario, bool restaurante) =>
      'ventiq_tutorial_venta_${version}_${restaurante ? 'restaurante' : 'normal'}_$uuidUsuario';

  static Future<bool> debeMostrar(String uuidUsuario, bool restaurante) async {
    if (uuidUsuario.isEmpty) return false;
    return !await _estaMarcado(_clave(uuidUsuario, restaurante));
  }

  static Future<String?> estado(String uuidUsuario, bool restaurante) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_clave(uuidUsuario, restaurante));
  }

  static Future<void> marcarVisto(String uuidUsuario, bool restaurante) =>
      _escribir(_clave(uuidUsuario, restaurante), valorVisto);

  static Future<void> marcarOmitido(String uuidUsuario, bool restaurante) =>
      _escribir(_clave(uuidUsuario, restaurante), valorOmitido);

  static Future<void> reiniciar(String uuidUsuario, bool restaurante) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave(uuidUsuario, restaurante));
  }

  static Future<bool> _estaMarcado(String clave) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(clave);
  }

  static Future<void> _escribir(String clave, String valor) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(clave, valor);
  }
}
