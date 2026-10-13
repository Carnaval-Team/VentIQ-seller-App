import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fidelidad.dart';

/// Panel de fidelidad contra el esquema `flow` (el **mismo** proyecto Supabase
/// que consume `inventtia_flow`; no es `carnavalapp`).
///
/// Las 10 RPC comprueban `public.fn_is_superadmin_full_access()`, o sea
/// `nivel_acceso = 1`. La app no decide permisos: solo los refleja.
///
/// ⚠ Cuidado con qué bandera gatea la UI: `AuthService.canWrite()` deja pasar
/// hasta nivel 2, así que usarla aquí mostraría botones que el servidor va a
/// rechazar con "Solo un superadmin con acceso total...". Esta pantalla se gatea
/// con `AuthService.hasFullAccess()`.
class FidelidadService {
  static final _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Desenvuelve la respuesta `{ok, data|error}` común a las 10 RPC.
  ///
  /// Todas devuelven `{ok:false, error}` en vez de lanzar, para que el mensaje
  /// llegue a la UI tal cual. Aquí se convierte en excepción.
  static Map<String, dynamic> _ok(Object? res) {
    final json = res is Map
        ? Map<String, dynamic>.from(res)
        : const <String, dynamic>{};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'La operación no se pudo completar');
    }
    return json;
  }

  static List<T> _lista<T>(
    Object? res,
    T Function(Map<String, dynamic>) construir,
  ) {
    final data = _ok(res)['data'];
    if (data is! List) return const <Never>[];
    return data
        .whereType<Map>()
        .map((e) => construir(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── Interruptor global (migración 33) ──────────────────────────────────────

  static Future<FidelidadConfig> obtenerConfig({
    required String uuidUsuario,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_obtener_fidelidad_config',
          params: {'p_uuid_usuario': uuidUsuario},
        );
    final data = _ok(res)['data'];
    return FidelidadConfig.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{},
    );
  }

  /// Activa o apaga el programa para todos. Devuelve el aviso del servidor para
  /// mostrarlo tal cual (explica que apagar no borra los puntos ganados).
  static Future<String?> guardarConfig({
    required String uuidUsuario,
    required bool activa,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_fidelidad_config',
          params: {'p_uuid_usuario': uuidUsuario, 'p_activa': activa},
        );
    final data = _ok(res)['data'];
    return data is Map ? data['aviso'] as String? : null;
  }

  // ── Reglas de acumulación ──────────────────────────────────────────────────

  static Future<List<ReglaFidelidadAdmin>> listarReglas({
    required String uuidUsuario,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_listar_reglas_fidelidad',
          params: {'p_uuid_usuario': uuidUsuario},
        );
    return _lista(res, ReglaFidelidadAdmin.fromJson);
  }

  /// Alta (`id` nulo) o edición.
  ///
  /// La RPC no tiene DEFAULT en ningún parámetro, así que hay que enviarlos
  /// **todos**, incluidos los nulos: PostgREST no rellena lo que no se manda.
  static Future<void> guardarRegla({
    required String uuidUsuario,
    required String nombre,
    int? idEntidad,
    String? moneda,
    required double puntosPorMonto,
    required double montoBase,
    int? vigenciaDias,
    bool activo = true,
    DateTime? desde,
    DateTime? hasta,
    int? id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_regla_fidelidad',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_nombre': nombre,
            'p_id_entidad': idEntidad,
            'p_moneda': moneda,
            'p_puntos_por_monto': puntosPorMonto,
            'p_monto_base': montoBase,
            'p_vigencia_dias': vigenciaDias,
            'p_activo': activo,
            'p_desde': desde?.toUtc().toIso8601String(),
            'p_hasta': hasta?.toUtc().toIso8601String(),
            'p_id': id,
          },
        );
    _ok(res);
  }

  static Future<void> eliminarRegla({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_eliminar_regla_fidelidad',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
        );
    _ok(res);
  }

  // ── Beneficios de bienvenida ───────────────────────────────────────────────

  static Future<List<BeneficioBienvenidaAdmin>> listarBeneficios({
    required String uuidUsuario,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_listar_beneficios_bienvenida',
          params: {'p_uuid_usuario': uuidUsuario},
        );
    return _lista(res, BeneficioBienvenidaAdmin.fromJson);
  }

  static Future<void> guardarBeneficio({
    required String uuidUsuario,
    required String titulo,
    String? descripcion,
    required String tipo,
    required double valor,
    String? moneda,
    int? idEntidad,
    double? montoMinimo,
    bool activo = true,
    DateTime? desde,
    DateTime? hasta,
    int? id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_beneficio_bienvenida',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_titulo': titulo,
            'p_descripcion': descripcion,
            'p_tipo': tipo,
            'p_valor': valor,
            'p_moneda': moneda,
            'p_id_entidad': idEntidad,
            'p_monto_minimo': montoMinimo,
            'p_activo': activo,
            'p_desde': desde?.toUtc().toIso8601String(),
            'p_hasta': hasta?.toUtc().toIso8601String(),
            'p_id': id,
          },
        );
    _ok(res);
  }

  static Future<void> eliminarBeneficio({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_eliminar_beneficio_bienvenida',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
        );
    _ok(res);
  }

  // ── Auditoría de puntos ────────────────────────────────────────────────────

  static Future<AuditoriaPuntos> auditarPuntos({
    required String uuidUsuario,
    required String uuidDestino,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_listar_movimientos_puntos',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_uuid_destino': uuidDestino,
          },
        );
    final data = _ok(res)['data'];
    return AuditoriaPuntos.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{},
    );
  }

  /// Ajuste manual con motivo obligatorio. El servidor rechaza dejarlo en
  /// negativo y devuelve el saldo antes y después.
  static Future<({int saldoAnterior, int saldoNuevo})> ajustarPuntos({
    required String uuidUsuario,
    required String uuidDestino,
    required int puntos,
    required String motivo,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_ajustar_puntos_usuario',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_uuid_destino': uuidDestino,
            'p_puntos': puntos,
            'p_motivo': motivo,
          },
        );
    final data = _ok(res)['data'];
    final m = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
    return (
      saldoAnterior: (m['saldo_anterior'] as num?)?.toInt() ?? 0,
      saldoNuevo: (m['saldo_nuevo'] as num?)?.toInt() ?? 0,
    );
  }
}