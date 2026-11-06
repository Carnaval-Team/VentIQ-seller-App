import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso al catálogo global de monedas, sus denominaciones y las tasas globales.
///
/// Fase 1 del plan multimoneda. Contrato SQL en:
///   docs/plan-multimoneda/fase1_catalogo_monedas.sql
///
/// Las escrituras NO van por `insert`/`update` directos: pasan por RPC con
/// `SECURITY DEFINER` que validan `fn_is_superadmin_full_access()`.
/// Si el usuario no es superadministrador de nivel 1, la base responde con un
/// error y no se escribe nada. `fn_crear_moneda` además escribe `monedas` y
/// `tipos_moneda` en la misma transacción: si una existe y la otra no, la
/// moneda no serviría para cobrar.
class MonedasService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _tablaMonedas = 'monedas';
  static const String _tablaDenominaciones = 'app_dat_denominaciones_moneda';
  static const String _tablaTasasGlobales = 'tasas_conversion';

  /// Catálogo completo ordenado por `orden` y luego por código.
  static Future<List<Map<String, dynamic>>> listar() async {
    final rows = await _supabase
        .from(_tablaMonedas)
        .select(
          'codigo, nombre, simbolo, pais, activo, decimales, orden, '
          'es_base, es_sistema',
        )
        .order('orden')
        .order('codigo');
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Crea una moneda nueva (atómico: `monedas` + `tipos_moneda`).
  static Future<void> crear({
    required String codigo,
    required String nombre,
    String? simbolo,
    String? pais,
    int decimales = 2,
    int orden = 100,
  }) async {
    await _supabase.rpc(
      'fn_crear_moneda',
      params: {
        'p_codigo': codigo.trim().toUpperCase(),
        'p_nombre': nombre.trim(),
        'p_simbolo': _nuloSiVacio(simbolo),
        'p_pais': _nuloSiVacio(pais),
        'p_decimales': decimales,
        'p_orden': orden,
      },
    );
  }

  /// Actualiza metadatos. Los parámetros `null` conservan el valor actual.
  static Future<void> actualizar({
    required String codigo,
    String? nombre,
    String? simbolo,
    String? pais,
    int? decimales,
    int? orden,
    bool? activo,
  }) async {
    await _supabase.rpc(
      'fn_actualizar_moneda',
      params: {
        'p_codigo': codigo.trim().toUpperCase(),
        'p_nombre': _nuloSiVacio(nombre),
        'p_simbolo': _nuloSiVacio(simbolo),
        'p_pais': _nuloSiVacio(pais),
        'p_decimales': decimales,
        'p_orden': orden,
        'p_activo': activo,
      },
    );
  }

  /// Denominaciones (billetes/monedas) configuradas para un código.
  static Future<List<Map<String, dynamic>>> listarDenominaciones(
    String codigo,
  ) async {
    final rows = await _supabase
        .from(_tablaDenominaciones)
        .select('id, codigo_moneda, denominacion, active')
        .eq('codigo_moneda', codigo.trim().toUpperCase())
        .order('denominacion', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Guarda el juego completo de denominaciones.
  ///
  /// El RPC hace *upsert*: una denominación que ya existe se actualiza, una
  /// nueva se inserta. Para "quitar" una denominación se envía con
  /// `active: false`, no se borra (así el histórico no pierde la referencia).
  static Future<void> guardarDenominaciones(
    String codigo,
    List<Map<String, dynamic>> denominaciones,
  ) async {
    await _supabase.rpc(
      'fn_guardar_denominaciones',
      params: {
        'p_codigo': codigo.trim().toUpperCase(),
        'p_denominaciones': denominaciones
            .map(
              (d) => {
                'denominacion': d['denominacion'],
                'active': d['active'] ?? true,
              },
            )
            .toList(),
      },
    );
  }

  /// Tasas globales (tabla `tasas_conversion`, versionada por fecha).
  static Future<List<Map<String, dynamic>>> listarTasasGlobales() async {
    final rows = await _supabase
        .from(_tablaTasasGlobales)
        .select(
          'id, moneda_origen, moneda_destino, tasa, fecha_actualizacion',
        )
        .order('fecha_actualizacion', ascending: false)
        .limit(200);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Inserta una nueva versión de la tasa global para el par.
  static Future<void> guardarTasaGlobal({
    required String origen,
    required String destino,
    required double tasa,
  }) async {
    await _supabase.rpc(
      'fn_guardar_tasa_global',
      params: {
        'p_moneda_origen': origen.trim().toUpperCase(),
        'p_moneda_destino': destino.trim().toUpperCase(),
        'p_tasa': tasa,
      },
    );
  }

  /// Tasa vigente de un par (tienda opcional). `null` si no hay tasa definida.
  static Future<double?> tasaActual({
    required String origen,
    required String destino,
    int? idTienda,
  }) async {
    final res = await _supabase.rpc(
      'fn_tasa_cambio',
      params: {
        'p_moneda_origen': origen.trim().toUpperCase(),
        'p_moneda_destino': destino.trim().toUpperCase(),
        if (idTienda != null) 'p_id_tienda': idTienda,
      },
    );
    if (res == null) return null;
    if (res is num) return res.toDouble();
    return double.tryParse(res.toString());
  }

  /// Códigos activos del catálogo, para poblar desplegables de otras pantallas.
  ///
  /// Sin caché a propósito: el catálogo cambia poco y este método se llama al
  /// abrir un diálogo, no en cada frame. Un desplegable con datos viejos es peor
  /// que una consulta de más.
  static Future<List<String>> codigos() async {
    try {
      final rows = await _supabase
          .from(_tablaMonedas)
          .select('codigo')
          .eq('activo', true)
          .order('orden');
      return List<String>.from(
        (rows as List)
            .map((r) => (r['codigo'] ?? '').toString().trim())
            .where((c) => c.isNotEmpty),
      );
    } catch (_) {
      return const ['CUP', 'USD'];
    }
  }

  /// Estado de la tasa automática («el toque»), para mostrarlo en la UI.
  ///
  /// Devuelve `{disponible, ok, fecha, hora, fuente, actualizado, vigente,
  /// tasas_cup:{USD,EUR,MLC}, monedas_cubiertas:[...]}`.
  /// `vigente == false` significa que la caché NO es de hoy.
  ///
  /// Se apoya en el esquema `flow` de inventtia_flow. Si ese esquema no existe,
  /// devuelve `null` y la pantalla simplemente no muestra la tarjeta.
  static Future<Map<String, dynamic>?> estadoTasaAutomatica() async {
    try {
      final res = await _supabase.rpc('fn_tasa_automatica_estado');
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Tasa automática de un par. `null` si el par NO está cubierto.
  ///
  /// El proveedor cubre **solo USD, EUR y MLC** (CUP es el pivote). Cualquier
  /// otra moneda creada desde esta pantalla necesitará tasa manual.
  static Future<double?> tasaAutomatica({
    required String origen,
    required String destino,
  }) async {
    final res = await _supabase.rpc(
      'fn_tasa_automatica',
      params: {
        'p_origen': origen.trim().toUpperCase(),
        'p_destino': destino.trim().toUpperCase(),
      },
    );
    if (res == null) return null;
    if (res is num) return res.toDouble();
    return double.tryParse(res.toString());
  }

  /// Dispara el refresco y espera en el CLIENTE a que llegue la respuesta.
  ///
  /// Importante: el refresco es asíncrono en el servidor (`pg_net`) y el rol
  /// `authenticated` tiene `statement_timeout = 8s`, así que las RPC NO deben
  /// bloquear esperando al proveedor. El sondeo se hace aquí, con esperas
  /// cortas entre llamadas idempotentes a `fn_tasas_ingerir`.
  static Future<Map<String, dynamic>?> refrescarTasas({
    bool forzar = false,
    int intentos = 4,
    Duration espera = const Duration(seconds: 3),
  }) async {
    final disparo = await _supabase.rpc(
      'fn_tasas_refrescar',
      params: {'p_forzar': forzar},
    );
    if (disparo is! Map) return null;
    var estado = Map<String, dynamic>.from(disparo);

    // Si ya estaba vigente, no hay nada que esperar.
    if (estado['estado'] != 'solicitado') return estado;
    if (estado['disponible'] == false) return estado;

    for (var i = 0; i < intentos; i++) {
      await Future<void>.delayed(espera);
      final recogida = await ingerirTasas();
      if (recogida == null) break;
      estado = recogida;
      final ingeridos = (recogida['ingeridos'] as num?)?.toInt() ?? 0;
      if (ingeridos > 0 || recogida['vigente'] == true) break;
    }
    return estado;
  }

  /// Recoge las respuestas del proveedor que ya hayan llegado (idempotente).
  static Future<Map<String, dynamic>?> ingerirTasas() async {
    try {
      final res = await _supabase.rpc('fn_tasas_ingerir');
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _nuloSiVacio(String? valor) {
    final t = valor?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }
}