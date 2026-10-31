import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cobro.dart';
import 'auth_service.dart';

/// Acceso a los RPC del **pago por adelantado del servicio** (migración 62).
///
/// Todas las funciones son `security definer` y deciden la autorización con
/// `auth.uid()` en el servidor: aquí no viaja nunca el uuid del usuario.
///
/// Contrato de error: si el RPC contesta `ok != true`, se lanza una [Exception]
/// con el texto del servidor. La UI lo pinta tal cual —los mensajes de la
/// migración están escritos para el cliente final— en vez de inventar uno
/// genérico que oculte el motivo real (permiso, plazo vencido, sin tasa…).
class CobroService {
  const CobroService._();

  static const String _schema = 'flow';

  /// ¿Este local-servicio admite pago por adelantado? Devuelve siempre un
  /// [CobroInfo]; con `disponible = false` cuando el admin no lo activó.
  ///
  /// `flow.cliente_cobro_info`.
  static Future<CobroInfo> infoLocalServicio(int idLocalServicio) async {
    final data = await _rpc(
      'cliente_cobro_info',
      params: {'p_id_local_servicio': idLocalServicio},
    );
    return CobroInfo.fromJson(_mapa(data));
  }

  /// Crea el intento de pago de una reserva ya creada y devuelve el deep link.
  ///
  /// **No** cobra nada ni acredita nada: deja `agenda.pago_estado = 'pendiente'`.
  /// El servidor rechaza la llamada si la reserva no está activa, si ya hay un
  /// intento vivo o si la reserva no tiene precio cobrable.
  ///
  /// `flow.cliente_crear_pago_reserva`.
  static Future<PagoReserva> crearPago(int idAgenda) async {
    final data = await _rpc(
      'cliente_crear_pago_reserva',
      params: {'p_id_agenda': idAgenda},
    );
    return PagoReserva.fromJson(_mapa(data));
  }

  /// «Ya he pagado»: registra el código (opcional) y el comprobante (opcional).
  ///
  /// El servidor avisa a los administradores de la entidad y pone
  /// `agenda.pago_estado = 'reportado'`. Quien acredita es la verificación
  /// manual del admin, no esto.
  ///
  /// `flow.cliente_reportar_pago_reserva`.
  static Future<void> reportarPago({
    required int idPago,
    String? codigo,
    String? comprobanteUrl,
  }) async {
    await _rpc(
      'cliente_reportar_pago_reserva',
      params: {
        'p_id_pago': idPago,
        // Vacío se guarda como NULL en el servidor: ambos son opcionales.
        'p_codigo_confirmacion': codigo ?? '',
        'p_comprobante_url': comprobanteUrl ?? '',
      },
    );
  }

  /// Estado del pago de una reserva, o `null` si nunca se pidió pago.
  ///
  /// Es el único camino para refrescar el estado que ve el cliente mientras el
  /// admin decide.
  ///
  /// `flow.cliente_pago_reserva`.
  static Future<PagoReserva?> pagoDeReserva(int idAgenda) async {
    final data = await _rpc(
      'cliente_pago_reserva',
      params: {'p_id_agenda': idAgenda},
    );
    if (data is! Map) return null;
    return PagoReserva.fromJson(Map<String, dynamic>.from(data));
  }

  /// Configuración de cobro de la entidad (`flow.admin_cobro_config_get`).
  static Future<CobroConfig> configGet(int idEntidad) async {
    final data = await _rpc(
      'admin_cobro_config_get',
      params: {'p_id_entidad': idEntidad},
    );
    return CobroConfig.fromJson(_mapa(data));
  }

  /// Guarda la configuración de cobro (`flow.admin_cobro_config_set`).
  ///
  /// El servidor **rechaza** activar el cobro sin número de proveedor; la
  /// pantalla lo explica antes de llamar para no gastar un viaje de red.
  static Future<CobroConfig> configSet({
    required int idEntidad,
    required bool activo,
    required String numeroProveedor,
    String? titulo,
    String? whatsappVerificacion,
    String? soporteWhatsapp,
    String? instrucciones,
    String moneda = 'CUP',
    int horasVigencia = 24,
    bool cancelarSiExpira = true,
  }) async {
    final data = await _rpc(
      'admin_cobro_config_set',
      params: {
        'p_id_entidad': idEntidad,
        'p_activo': activo,
        'p_numero_proveedor': numeroProveedor,
        'p_titulo': titulo ?? '',
        'p_whatsapp_verificacion': whatsappVerificacion ?? '',
        'p_soporte_whatsapp': soporteWhatsapp ?? '',
        'p_instrucciones': instrucciones ?? '',
        'p_moneda': moneda,
        'p_horas_vigencia': horasVigencia,
        'p_cancelar_si_expira': cancelarSiExpira,
      },
    );
    return CobroConfig.fromJson(_mapa(data));
  }

  /// Cuántos servicios de la entidad siguen **marcados** con pago por
  /// adelantado (`app_dat_servicios.cobro_adelantado = true`).
  ///
  /// Es el número que la pantalla necesita para avisar antes de apagar el
  /// interruptor maestro: apagarlo **no** desmarca ningún servicio —cada uno
  /// conserva su columna—, solo deja de ofrecerlos; al reactivarlo volverían a
  /// cobrar. Sin este dato el admin apagaba a ciegas (P2-7).
  ///
  /// Va por PostgREST y no por RPC a propósito: la RLS `servicios_select_all` es
  /// `using(true)`, así que basta con filtrar por entidad, sin migración nueva.
  /// Si la migración 67 no está aplicada la columna no existe y PostgREST falla:
  /// el llamador lo trata como «no se sabe» y nunca bloquea el guardado.
  static Future<int> serviciosMarcados(int idEntidad) async {
    final res = await Supabase.instance.client
        .schema(_schema)
        .from('app_dat_servicios')
        .select('id')
        .eq('id_entidad', idEntidad)
        .eq('cobro_adelantado', true);
    return res.length;
  }

  /// Bandeja de pagos de la entidad (`flow.admin_listar_pagos_reserva`).
  ///
  /// [estado] filtra por un estado exacto (`creado`, `reportado`, `verificado`,
  /// `rechazado`, `expirado`). Con `null` devuelve todos.
  static Future<List<PagoAdminItem>> listarPagos({
    required int idEntidad,
    String? estado,
  }) async {
    final data = await _rpc(
      'admin_listar_pagos_reserva',
      params: {
        'p_id_entidad': idEntidad,
        // Se omite cuando no hay filtro: así manda el `default null` del RPC.
        if (estado != null) 'p_estado': estado,
      },
    );
    return pagosAdminDesde(data);
  }

  /// Verifica el pago y confirma la reserva
  /// (`flow.admin_verificar_pago_reserva`). [observaciones] es opcional.
  static Future<void> verificarPago({
    required int idPago,
    String? observaciones,
  }) async {
    await _rpc(
      'admin_verificar_pago_reserva',
      params: {'p_id_pago': idPago, 'p_observaciones': observaciones ?? ''},
    );
  }

  /// Rechaza el pago con motivo **obligatorio**
  /// (`flow.admin_rechazar_pago_reserva`). Sin motivo el servidor falla.
  static Future<void> rechazarPago({
    required int idPago,
    required String motivo,
  }) async {
    await _rpc(
      'admin_rechazar_pago_reserva',
      params: {'p_id_pago': idPago, 'p_motivo': motivo},
    );
  }

  /// Cierra los intentos vencidos (`flow.reserva_pago_expirar`).
  ///
  /// Idempotente: la bandeja lo llama al abrir y el servidor puede llamarlo por
  /// cron. Devuelve cuántos intentos se marcaron `expirado`.
  static Future<int> expirarPagos() async {
    final data = await _rpc('reserva_pago_expirar');
    final mapa = _mapa(data);
    return (mapa['expirados'] as num?)?.toInt() ?? 0;
  }

  /// Identificador de la última reserva del usuario para un local-servicio.
  ///
  /// Existe porque `AgendaService.reservarDirecto` no devuelve el id que acaba
  /// de crear (`cliente_reservar_directo` sí lo trae en `data.id_agenda`, pero la
  /// firma pública del servicio es `Future<void>` y ese fichero pertenece a otro
  /// frente de este mismo cambio). Para ofrecer «Pagar por adelantado» justo
  /// después de reservar hace falta ese id, así que se lee la propia agenda: la
  /// RLS deja al dueño ver sus reservas y también las que hizo para un tercero
  /// (`reservado_por = auth.uid()`).
  ///
  /// Con [desde] se acota a las creadas a partir de ese instante —se pasa el
  /// momento anterior a reservar— y se toma la de `id` más alto, que es
  /// exactamente la recién creada. Devuelve `null` si no hay ninguna.
  static Future<int?> ultimaReservaDe({
    required int idLocalServicio,
    DateTime? desde,
  }) async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return null;

    var query = Supabase.instance.client
        .schema(_schema)
        .from('agenda')
        .select('id')
        .eq('id_local_servicio', idLocalServicio)
        // La reserva para un tercero queda con `uuid_usuario` del tercero y
        // `reservado_por` del que la hizo: hay que mirar los dos.
        .or('uuid_usuario.eq.$uuid,reservado_por.eq.$uuid');

    if (desde != null) {
      // Margen de 2 minutos: el reloj del teléfono puede ir por detrás del de la
      // base y la reserva se crea en el servidor.
      final corte = desde.subtract(const Duration(minutes: 2)).toUtc();
      query = query.gte('created_at', corte.toIso8601String());
    }

    final res = await query.order('id', ascending: false).limit(1);
    if (res.isEmpty) return null;
    return (res.first['id'] as num?)?.toInt();
  }

  /// Reserva **activa** más reciente del usuario en un local-servicio que aún
  /// admite pago por adelantado (o `null` si no tiene ninguna).
  ///
  /// Es lo que decide si la ficha del servicio puede ofrecer «Pagar por
  /// adelantado»: antes el botón se pintaba siempre que el servicio aceptara
  /// cobro, y al pulsarlo salía «Primero reserva un turno», un callejón sin
  /// salida. Con esto el botón solo aparece cuando hay algo que pagar y, al
  /// pulsarlo, se va **directo** al pago (no a un aviso).
  ///
  /// Devuelve también `pago_estado` para poder **reanudar** un intento vivo
  /// (`pendiente`/`reportado`) en vez de crear otro, que el servidor rechazaría.
  /// Se excluyen las que ya están `verificado`: esas no tienen nada que pagar.
  ///
  /// Va por PostgREST (no hay RPC para esto): la RLS de `agenda` deja al dueño
  /// ver sus reservas y las que hizo para un tercero (`reservado_por`).
  static Future<({int id, String? pagoEstado})?> reservaPendienteDePago({
    required int idLocalServicio,
  }) async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) return null;

    try {
      final res = await Supabase.instance.client
          .schema(_schema)
          .from('agenda')
          .select('id, pago_estado, nom_estado_agenda(nombre)')
          .eq('id_local_servicio', idLocalServicio)
          .or('uuid_usuario.eq.$uuid,reservado_por.eq.$uuid')
          .order('id', ascending: false)
          // Un puñado basta: la más nueva activa es la que interesa.
          .limit(8);

      for (final fila in res) {
        final estado =
            (fila['nom_estado_agenda'] as Map?)?['nombre'] as String?;
        if (estado != 'Reservado') continue;
        final pagoEstado = fila['pago_estado'] as String?;
        if (pagoEstado == 'verificado') continue;
        final id = (fila['id'] as num?)?.toInt();
        if (id == null) continue;
        return (id: id, pagoEstado: pagoEstado);
      }
      return null;
    } catch (e) {
      // Sin red o sin permiso de lectura: se trata como «no hay nada que pagar»
      // y la ficha no ofrece el botón (mejor eso que un botón que falla).
      debugPrint('[flow] CobroService.reservaPendienteDePago ERROR: $e');
      return null;
    }
  }

  // ── Interno ──────────────────────────────────────────────────────────────

  /// Llama a un RPC que devuelve `{ ok, data | error }` y devuelve su `data`.
  ///
  /// Mira `ok` **antes** de leer `data`: en el error, `data` no viene.
  static Future<dynamic> _rpc(
    String funcion, {
    Map<String, dynamic>? params,
  }) async {
    final res = await Supabase.instance.client
        .schema(_schema)
        .rpc(funcion, params: params);

    if (res is! Map) {
      throw Exception('Respuesta inesperada del servidor');
    }
    final json = Map<String, dynamic>.from(res);
    if (json['ok'] != true) {
      throw Exception(
        json['error'] as String? ?? 'La operación no se pudo completar',
      );
    }
    return json['data'];
  }

  /// Un `data` que debería ser objeto. Si no lo es, un mapa vacío hace que los
  /// `fromJson` apliquen sus valores por defecto en vez de reventar.
  static Map<String, dynamic> _mapa(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
}
