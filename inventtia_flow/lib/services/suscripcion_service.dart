import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/suscripcion.dart';
import '../utils/esquema_pendiente.dart';

/// Resultado de una llamada de suscripción.
///
/// Tres estados, no dos: `ok`, `error` y `esquemaPendiente`. El tercero existe
/// porque el agente no aplica las migraciones — las pega el usuario —, así que
/// la app tiene que funcionar **antes y después** de que se apliquen. Ante una
/// función ausente la UI oculta la sección en silencio; ante un fallo real
/// muestra el motivo. Confundir ambos casos es lo que produce "no se pudo
/// cargar" en una app a la que solo le falta la migración.
class RespuestaSuscripcion<T> {
  const RespuestaSuscripcion._({
    this.data,
    this.error,
    this.esquemaPendiente = false,
  });

  final T? data;
  final String? error;
  final bool esquemaPendiente;

  bool get ok => data != null;

  factory RespuestaSuscripcion.ok(T data) => RespuestaSuscripcion._(data: data);

  factory RespuestaSuscripcion.error(String error) =>
      RespuestaSuscripcion._(error: error);

  factory RespuestaSuscripcion.pendiente() =>
      const RespuestaSuscripcion._(esquemaPendiente: true);

  /// El mensaje de error listo para pintar. `null` si salió bien.
  String? get mensajeError => ok || esquemaPendiente
      ? null
      : (error ?? 'No se pudo completar la operación');
}

/// Acceso a los RPC de suscripciones del schema `flow`.
///
/// Todas las funciones son `security definer` y deciden la autorización con
/// `auth.uid()` en el servidor: la app no manda el uuid del usuario. Por eso aquí
/// no hay ningún parámetro de identidad.
class SuscripcionService {
  const SuscripcionService._();

  static const String _schema = 'flow';

  /// Número de soporte de reserva si el servidor no manda ninguno.
  static const String _soportePorDefecto = '5354590207';

  /// Estado de la suscripción de una entidad.
  static Future<RespuestaSuscripcion<EstadoSuscripcionEntidad>> estado(
    int idEntidad,
  ) {
    return _llamar<EstadoSuscripcionEntidad>(
      'cliente_estado_suscripcion',
      params: {'p_id_entidad': idEntidad},
      parse: (data) => EstadoSuscripcionEntidad.fromJson(_mapaDe(data)),
    );
  }

  /// Planes que el cliente puede comprar. Solo devuelve los activos.
  ///
  /// Este RPC devuelve `{ ok, data: [ ... ] }`: la lista viene dentro de `data`,
  /// así que aquí no se espera un objeto.
  static Future<RespuestaSuscripcion<List<PlanSuscripcion>>> planes() {
    return _llamar<List<PlanSuscripcion>>(
      'cliente_planes_suscripcion',
      parse: (data) {
        if (data is! List) return const <PlanSuscripcion>[];
        return data
            .whereType<Map>()
            .map((e) => PlanSuscripcion.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      },
    );
  }

  /// Intents, pagos y movimientos de la entidad.
  static Future<RespuestaSuscripcion<MiSuscripcion>> miSuscripcion(
    int idEntidad,
  ) {
    return _llamar<MiSuscripcion>(
      'cliente_mis_pagos_suscripcion',
      params: {'p_id_entidad': idEntidad},
      parse: (data) => MiSuscripcion.fromJson(_mapaDe(data)),
    );
  }

  /// Crea el intent de pago y devuelve el deep link de Transfermóvil.
  ///
  /// Solo el dueño de la entidad o un `entidad_admin` pueden llamarlo; lo decide
  /// el servidor. Llamar dos veces genera dos intents distintos: el
  /// `id_transaccion` es único por intento, y tiene que serlo — si se repite,
  /// Transfermóvil reutiliza el importe de la transacción anterior.
  static Future<RespuestaSuscripcion<IntentPagoCreado>> crearIntent({
    required int idEntidad,
    required int idPlan,
  }) {
    return _llamar<IntentPagoCreado>(
      'cliente_crear_intent_suscripcion',
      params: {'p_id_entidad': idEntidad, 'p_id_plan': idPlan},
      parse: (data) => IntentPagoCreado.fromJson(_mapaDe(data)),
    );
  }

  /// El botón "Ya he pagado".
  ///
  /// **No acredita nada**: registra el código de confirmación (único) y el
  /// comprobante, avisa al dueño y deja el pago en la bandeja del superadmin.
  /// Quien acredita el tiempo es `admin_suscripcion_aprobar_pago`, que exige ser
  /// superadmin. Sin código de confirmación el servidor rechaza la llamada.
  static Future<RespuestaSuscripcion<ReportePago>> reportarPago({
    required int idIntent,
    required String codigoConfirmacion,
    String? comprobanteUrl,
  }) {
    return _llamar<ReportePago>(
      'cliente_reportar_pago_suscripcion',
      params: {
        'p_id_intent': idIntent,
        'p_codigo_confirmacion': codigoConfirmacion,
        // Vacío se guarda como NULL en el servidor: el comprobante es opcional.
        'p_comprobante_url': comprobanteUrl ?? '',
      },
      parse: (data) => ReportePago.fromJson(_mapaDe(data)),
    );
  }

  /// Marca el intent como abierto (el cliente lanzó Transfermóvil).
  ///
  /// Es solo telemetría del embudo del panel: no cambia ningún derecho y no debe
  /// molestar si falla, porque el usuario está a punto de pagar.
  static Future<void> marcarIntentAbierto(int idIntent) async {
    try {
      await Supabase.instance.client
          .schema(_schema)
          .rpc(
            'cliente_marcar_intent_abierto',
            params: {'p_id_intent': idIntent},
          );
    } catch (_) {
      // Silencio deliberado.
    }
  }

  /// Enlace `wa.me` con el mensaje ya redactado por el servidor.
  ///
  /// WhatsApp es el canal que el usuario pidió, pero **no hay bot todavía**
  /// (decisión Q33): el aviso automático queda en el outbox del servidor como
  /// `omitida` y la app ofrece este enlace para que el cliente lo mande a mano.
  /// Cuando exista el bot, el envío pasará a ser automático y esto quedará como
  /// respaldo para quien prefiera escribir él mismo.
  static String urlWhatsapp(String numero, String mensaje) {
    final destino = normalizarTelefono(numero);
    return 'https://wa.me/$destino?text=${Uri.encodeComponent(mensaje)}';
  }

  /// Deja el teléfono en formato internacional para `wa.me`.
  ///
  /// Los números se guardan como los escribe la gente: `54590207`,
  /// `+53 54590207`, `5354590207`. WhatsApp quiere solo dígitos, sin `+`. Si el
  /// número no trae código de país se asume Cuba (53), que es donde opera la
  /// plataforma; el código está en un solo sitio a propósito.
  static String normalizarTelefono(String numero) {
    final digitos = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) return _soportePorDefecto;
    if (digitos.startsWith('53')) return digitos;
    if (digitos.length == 8) return '53$digitos';
    return digitos;
  }

  /// Llamada genérica a un RPC que devuelve `{ ok, data | error }`.
  ///
  /// Mira `ok` **antes** de leer `data`: en el error `data` no viene. Y acepta
  /// cualquier forma en `data` porque no todos los RPC devuelven un objeto —
  /// `cliente_planes_suscripcion` devuelve un array.
  static Future<RespuestaSuscripcion<T>> _llamar<T>(
    String funcion, {
    Map<String, dynamic>? params,
    required T Function(dynamic data) parse,
  }) async {
    try {
      final res = await Supabase.instance.client
          .schema(_schema)
          .rpc(funcion, params: params);

      if (res is! Map) {
        return RespuestaSuscripcion.error('Respuesta inesperada del servidor');
      }

      final mapa = Map<String, dynamic>.from(res);

      if (mapa['ok'] == false) {
        return RespuestaSuscripcion.error(
          mapa['error'] as String? ?? 'La operación no se pudo completar',
        );
      }

      if (!mapa.containsKey('data')) {
        return RespuestaSuscripcion.error('Respuesta inesperada del servidor');
      }

      return RespuestaSuscripcion.ok(parse(mapa['data']));
    } catch (e) {
      if (esErrorDeEsquemaAusente(e, tabla: 'suscripcion')) {
        return RespuestaSuscripcion.pendiente();
      }
      return RespuestaSuscripcion.error(_mensajeDeError(e));
    }
  }

  /// Convierte el error crudo en algo que un usuario pueda leer.
  ///
  /// Se conserva el texto original cuando no se reconoce: un mensaje raro pero
  /// real es más útil para soporte que un "algo salió mal" genérico.
  static String _mensajeDeError(Object e) {
    final texto = e.toString();
    if (texto.contains('JWT') || texto.contains('not authenticated')) {
      return 'Tu sesión caducó. Vuelve a entrar para continuar.';
    }
    if (texto.contains('SocketException') ||
        texto.contains('Connection') ||
        texto.contains('TimeoutException')) {
      return 'Sin conexión. Revisa tu red e inténtalo de nuevo.';
    }
    if (texto.contains('PGRST202') || texto.contains('42P01')) {
      return 'La función de suscripciones no está disponible todavía.';
    }
    return 'No se pudo completar la operación. Inténtalo de nuevo.';
  }

  /// Un `data` que debería ser objeto. Si no lo es, un mapa vacío hace que los
  /// `fromJson` apliquen sus valores por defecto en vez de reventar.
  static Map<String, dynamic> _mapaDe(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
}
