import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia del estado del tutorial guiado.
///
/// Se guarda en `SharedPreferences` (no hay tabla de preferencias de usuario en
/// Supabase y no hace falta): la clave incluye el uuid del usuario y, en el caso
/// del admin, el id de la entidad, de modo que al crear una entidad nueva el
/// tutorial vuelve a mostrarse para esa entidad.
///
/// Valores posibles: `visto` y `omitido`. Los dos significan "no volver a
/// mostrar"; solo cambia el motivo (lo terminó o lo saltó).
class TutorialService {
  TutorialService._();

  static const String _prefijoCliente = 'flow_tutorial_cliente';
  static const String _prefijoAdmin = 'flow_tutorial_admin';

  /// Versión del guion. Subirla republica el tutorial para todos.
  static const String version = 'v1';

  static const String valorVisto = 'visto';
  static const String valorOmitido = 'omitido';

  static String claveCliente(String uuidUsuario) =>
      '${_prefijoCliente}_${version}_$uuidUsuario';

  static String claveAdmin(String uuidUsuario, int idEntidad) =>
      '${_prefijoAdmin}_${version}_${uuidUsuario}_$idEntidad';

  // ── Cliente ────────────────────────────────────────────────────────────

  static Future<bool> debeMostrarCliente(String uuidUsuario) async {
    if (uuidUsuario.isEmpty) return false;
    return !await estaMarcado(claveCliente(uuidUsuario));
  }

  static Future<String?> estadoCliente(String uuidUsuario) async =>
      await _leer(claveCliente(uuidUsuario));

  static Future<void> marcarVistoCliente(String uuidUsuario) =>
      _escribir(claveCliente(uuidUsuario), valorVisto);

  static Future<void> marcarOmitidoCliente(String uuidUsuario) =>
      _escribir(claveCliente(uuidUsuario), valorOmitido);

  static Future<void> reiniciarCliente(String uuidUsuario) =>
      _borrar(claveCliente(uuidUsuario));

  // ── Admin (por usuario y entidad) ──────────────────────────────────────

  static Future<bool> debeMostrarAdmin(
    String uuidUsuario,
    int idEntidad,
  ) async {
    if (uuidUsuario.isEmpty) return false;
    return !await estaMarcado(claveAdmin(uuidUsuario, idEntidad));
  }

  static Future<String?> estadoAdmin(String uuidUsuario, int idEntidad) async =>
      await _leer(claveAdmin(uuidUsuario, idEntidad));

  static Future<void> marcarVistoAdmin(String uuidUsuario, int idEntidad) =>
      _escribir(claveAdmin(uuidUsuario, idEntidad), valorVisto);

  static Future<void> marcarOmitidoAdmin(String uuidUsuario, int idEntidad) =>
      _escribir(claveAdmin(uuidUsuario, idEntidad), valorOmitido);

  static Future<void> reiniciarAdmin(String uuidUsuario, int idEntidad) =>
      _borrar(claveAdmin(uuidUsuario, idEntidad));

  // ── Interno ────────────────────────────────────────────────────────────

  static Future<bool> estaMarcado(String clave) async {
    final valor = await _leer(clave);
    return valor == valorVisto || valor == valorOmitido;
  }

  static Future<String?> _leer(String clave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(clave);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _escribir(String clave, String valor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(clave, valor);
    } catch (_) {
      // Sin almacenamiento el tutorial simplemente se volverá a mostrar.
    }
  }

  static Future<void> _borrar(String clave) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(clave);
    } catch (_) {}
  }
}
