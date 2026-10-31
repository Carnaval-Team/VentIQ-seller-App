/// Acceso a `flow.admin_calendario_reservas` (punto 3 del plan, §1.1).
///
/// La carga en dos tiempos de la pantalla vive aquí en forma de llamadas:
/// contadores del rango (`incluirItems: false`, barato, para los marcadores) e
/// items de un día o de todo el rango (`incluirItems: true`).
///
/// Diferencia clave con `AgendaAdminService`: **aquí no se usa `_tsParam`**.
/// `p_desde`/`p_hasta` son de tipo `date`, así que van como `yyyy-MM-dd`; mandar
/// un `timestamp` haría que Postgres lo castee en el huso del servidor y un día
/// se correría de fecha.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/resumen_reservas.dart';
import '../utils/esquema_pendiente.dart';
import 'auth_service.dart';

class CalendarioService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _schema = 'flow';
  static const String _rpc = 'admin_calendario_reservas';

  /// `yyyy-MM-dd` local: es lo que espera un parámetro `date` de Postgres.
  static String? _fechaParam(DateTime? fecha) {
    if (fecha == null) return null;
    final y = fecha.year.toString().padLeft(4, '0');
    final m = fecha.month.toString().padLeft(2, '0');
    final d = fecha.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// La RPC devuelve `jsonb`: normalmente llega ya decodificado como mapa, pero
  /// si el driver lo entrega como texto se decodifica antes de leer `ok`.
  static Map<String, dynamic> _comoMapa(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is String && res.trim().isNotEmpty) {
      try {
        final decodificado = jsonDecode(res);
        if (decodificado is Map) {
          return Map<String, dynamic>.from(decodificado);
        }
      } catch (_) {
        // Texto que no es JSON: se trata como respuesta vacía.
      }
    }
    return const <String, dynamic>{};
  }

  /// Resumen de las reservas de la entidad.
  ///
  /// - [idEntidad] entidad del admin (se valida en el servidor: la RPC exige
  ///   que el usuario sea admin de esa entidad).
  /// - [desde]/[hasta]: extremos del rango. Si se omiten, el servidor usa hoy
  ///   como extremo inferior y el final del último mes con reservas como
  ///   superior. Si [hasta] es igual a [desde] se consulta un solo día.
  /// - [incluirItems]: `false` devuelve solo contadores por día (marcadores);
  ///   `true` añade la lista de reservas de cada día.
  static Future<ResumenReservas> calcular({
    required int idEntidad,
    DateTime? desde,
    DateTime? hasta,
    bool incluirItems = false,
  }) async {
    final uuid = await AuthService.getCurrentUserId();
    if (uuid == null) {
      throw Exception(
        'No se pudo identificar al usuario. Vuelve a iniciar sesión.',
      );
    }

    dynamic res;
    try {
      res = await _supabase
          .schema(_schema)
          .rpc(
            _rpc,
            params: {
              'p_uuid_usuario': uuid,
              'p_id_entidad': idEntidad,
              if (desde != null) 'p_desde': _fechaParam(desde),
              if (hasta != null) 'p_hasta': _fechaParam(hasta),
              'p_incluir_items': incluirItems,
            },
          );
    } catch (e) {
      // La base de *release* todavía no tiene la migración 63: sin esta rama el
      // admin vería "PGRST202" y no sabría qué pasa.
      if (esErrorDeEsquemaAusente(e)) {
        throw Exception(
          'El calendario de reservas todavía no está disponible en la base '
          'de datos de este servidor.',
        );
      }
      throw Exception('No se pudo cargar el resumen de reservas: $e');
    }

    final json = _comoMapa(res);
    final ok = json['ok'];
    if (ok != true) {
      final error = json['error']?.toString().trim();
      throw Exception(
        error == null || error.isEmpty
            ? 'No se pudo cargar el resumen de reservas.'
            : error,
      );
    }
    return ResumenReservas.fromJson(json);
  }
}
