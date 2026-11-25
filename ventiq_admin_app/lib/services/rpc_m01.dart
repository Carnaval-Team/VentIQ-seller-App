import 'package:supabase_flutter/supabase_flutter.dart';

/// Llama a la RPC `<base>_m01` primero y cae al nombre antiguo `<base>`
/// únicamente cuando la función no existe en el proyecto (PGRST202, caché de
/// esquema o «does not exist»). Un 42501 / permiso denegado nunca cae: abrir
/// otra vía de escritura tras una denegación saltaría la política de acceso.
///
/// Las reglas de «función inexistente» replican `AutoSyncService._isRpcUnavailable`.
class RpcM01 {
  RpcM01._();

  static String m01Name(String base) => '${base}_m01';

  static bool isUnavailable(Object error, String functionName) {
    final text = error.toString().toLowerCase();
    // 42501 y el resto de denegaciones no son una función ausente. Si el
    // mensaje menciona "schema cache", igual no se abre otra vía de escritura.
    if (text.contains('42501') ||
        text.contains('insufficient_privilege') ||
        text.contains('permission denied') ||
        text.contains('acceso denegado')) {
      return false;
    }
    final fn = functionName.toLowerCase();
    return text.contains('pgrst202') ||
        text.contains('could not find the function') ||
        text.contains('schema cache') ||
        (text.contains('does not exist') && text.contains(fn));
  }

  /// Intenta `<baseName>_m01`; si no existe, `<baseName>`. Otros errores se
  /// relanzan sin intentar el nombre antiguo.
  static Future<dynamic> call(
    String baseName, {
    required Map<String, dynamic> params,
  }) async {
    final m01 = m01Name(baseName);
    try {
      return await Supabase.instance.client.rpc(m01, params: params);
    } catch (e) {
      if (!isUnavailable(e, m01)) rethrow;
      return Supabase.instance.client.rpc(baseName, params: params);
    }
  }
}
