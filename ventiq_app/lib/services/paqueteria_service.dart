import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio responsable de registrar órdenes de paquetería, que crean
/// simultáneamente una Orden en `carnavalapp.Orders` (con su `OrderDetail`,
/// lo cual dispara el trigger `crear_orden_desde_carnaval` en Inventtia) y
/// un registro en `public.paqueteria_ordenes` con el detalle del paquete.
class PaqueteriaService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _photoBucket = 'productos';
  static const String _photoFolder = 'paqueteria';

  /// Pide al backend el siguiente número correlativo de paquete para la tienda.
  /// Se reinicia automáticamente cada mes por tienda (RPC
  /// `fn_get_next_numero_paquete`). Devuelve algo como `P-001`. Si falla,
  /// retorna `null` y el caller debe decidir un fallback.
  Future<String?> getNextNumeroPaquete(int idTienda) async {
    try {
      final response = await _supabase.rpc(
        'fn_get_next_numero_paquete',
        params: {'p_id_tienda': idTienda},
      );
      if (response is Map) {
        final map = Map<String, dynamic>.from(response);
        if (map['status'] == 'success') {
          final code = map['numero_paquete']?.toString();
          if (code != null && code.isNotEmpty) return code;
        }
        debugPrint('⚠️ fn_get_next_numero_paquete: $map');
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error obteniendo numero_paquete: $e');
      return null;
    }
  }

  /// Sube una foto del paquete al bucket `productos/paqueteria/` y devuelve
  /// la URL pública. Si la carga falla retorna `null`.
  ///
  /// En Flutter Web `uploadBinary` por defecto envía `application/octet-stream`
  /// si no se pasa `contentType`, y eso provoca que Supabase Storage rechace
  /// la imagen o la guarde sin tipo, mientras que en Android/iOS la librería
  /// infiere el MIME del path nativo. Por eso pasamos el `contentType` de
  /// forma explícita siempre.
  Future<String?> uploadPackagePhoto({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) async {
    try {
      final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path =
          '$_photoFolder/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      final resolvedMime =
          (mimeType != null && mimeType.isNotEmpty)
              ? mimeType
              : _guessMimeFromName(safeName);

      await _supabase.storage.from(_photoBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: resolvedMime,
            ),
          );

      return _supabase.storage.from(_photoBucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('❌ Error subiendo foto de paquete: $e');
      return null;
    }
  }

  String _guessMimeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.heif')) return 'image/heif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/jpeg';
  }

  /// Resuelve el `id` del proveedor en Carnaval (`carnavalapp.proveedores.id`)
  /// asociado a la tienda actual (`public.app_dat_tienda.id`). Se usa el
  /// campo `id_tienda_carnaval` de `app_dat_tienda`.
  Future<int?> resolveProveedorCarnaval(int idTienda) async {
    try {
      final row = await _supabase
          .from('app_dat_tienda')
          .select('id_tienda_carnaval')
          .eq('id', idTienda)
          .maybeSingle();
      if (row == null) return null;
      final v = row['id_tienda_carnaval'];
      if (v == null) return null;
      return (v as num).toInt();
    } catch (e) {
      debugPrint('❌ Error resolviendo id_tienda_carnaval: $e');
      return null;
    }
  }

  /// Invoca la función RPC `fn_registrar_orden_paqueteria` con el payload
  /// completo de la orden. Retorna el JSONB de respuesta (`status`,
  /// `id_orden_carnaval`, `id_operacion`, ...).
  Future<Map<String, dynamic>> registrarOrdenPaqueteria(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _supabase.rpc(
        'fn_registrar_orden_paqueteria_v2',
        params: {'p_payload': payload},
      );

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
      return {'status': 'error', 'message': 'Respuesta RPC inesperada'};
    } catch (e) {
      debugPrint('❌ Error registrando orden de paquetería: $e');
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
