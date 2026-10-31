import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/agenda.dart';
import '../models/disponibilidad_dia.dart';

class AgendaService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Handle schema permission errors with user-friendly messages
  static Exception handleSchemaPermissionError(Exception e) {
    if (e.toString().contains('permission denied') ||
        e.toString().contains('42501')) {
      return Exception(
        'ERROR DE PERMISOS DE BASE DE DATOS\n\n'
        'No se puede acceder al esquema "flow" de la base de datos.\n\n'
        'SOLUCIÓN:\n'
        '1. Ve al panel de Supabase > SQL Editor\n'
        '2. Ejecuta los siguientes comandos:\n\n'
        'GRANT USAGE ON SCHEMA flow TO authenticated;\n'
        'GRANT USAGE ON SCHEMA flow TO anon;\n'
        'GRANT ALL ON ALL TABLES IN SCHEMA flow TO authenticated;\n'
        'GRANT ALL ON ALL TABLES IN SCHEMA flow TO anon;\n'
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO authenticated;\n'
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO anon;\n\n'
        'Error original: ${e.toString()}',
      );
    }
    return e;
  }

  /// Días con disponibilidad para reserva directa de un local_servicio.
  static Future<List<DisponibilidadDia>> getDisponibilidad(
    int idLocalServicio,
  ) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .rpc(
            'cliente_obtener_disponibilidad',
            params: {'p_id_local_servicio': idLocalServicio},
          );
      if (res == null) return [];
      return (res as List)
          .map((e) => DisponibilidadDia.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  /// Turnos que el admin tiene **configurados** para un servicio, tenga cupo o no.
  ///
  /// `cliente_obtener_disponibilidad` solo devuelve los turnos con plazas libres
  /// y los días con cupo, así que para la **lista de espera** no sirve: ahí se
  /// anota justo quien no encontró hueco. Esta consulta lee la configuración
  /// (`flow.recurso` + `flow.turno`, ambos con `select` para `authenticated`)
  /// para poder ofrecer todos los turnos aunque el día esté lleno.
  ///
  /// Devuelven `disponibles: 0` (no se conoce el cupo); quien la use debe
  /// cruzarla con la disponibilidad real del día si la tiene.
  ///
  /// Nunca lanza: si la tabla no existe o RLS no deja leerla, devuelve `[]` y el
  /// flujo de la cola sigue funcionando (el cliente se anota sin turno, que el
  /// servidor acepta como "cualquier turno").
  static Future<List<TurnoDisponible>> getTurnosConfigurados(
    int idLocalServicio,
  ) async {
    try {
      final recursos = await _supabase
          .schema(_schema)
          .from('recurso')
          .select('id, nombre, orden')
          .eq('id_local_servicio', idLocalServicio)
          .eq('activo', true)
          .order('orden');

      if (recursos.isEmpty) return [];

      final ids = recursos
          .map((r) => (r['id'] as num).toInt())
          .toList(growable: false);
      final nombrePorRecurso = {
        for (final r in recursos)
          (r['id'] as num).toInt(): r['nombre'] as String? ?? '',
      };

      final turnos = await _supabase
          .schema(_schema)
          .from('turno')
          .select('id, nombre, orden, id_recurso')
          .inFilter('id_recurso', ids)
          .eq('activo', true)
          // `id` como segundo criterio porque `orden` suele venir a 0 en todos:
          // así el orden es estable y coincide con el de la RPC (t_orden, id).
          .order('orden')
          .order('id');

      // Agrupado en el orden de `recurso.orden` (el de `turno.orden` solo ordena
      // dentro de cada recurso): es el mismo orden que usa la RPC.
      final porRecurso = <int, List<Map<String, dynamic>>>{};
      for (final t in turnos) {
        final idRec = (t['id_recurso'] as num).toInt();
        porRecurso.putIfAbsent(idRec, () => []).add(t);
      }

      final salida = <TurnoDisponible>[];
      for (final idRec in ids) {
        for (final t in porRecurso[idRec] ?? const []) {
          salida.add(
            TurnoDisponible(
              idRecurso: idRec,
              recurso: nombrePorRecurso[idRec] ?? '',
              idTurno: (t['id'] as num).toInt(),
              turno: t['nombre'] as String? ?? 'Turno',
              disponibles: 0,
            ),
          );
        }
      }
      return salida;
    } catch (e) {
      // Sin permisos o sin tablas: la cola no depende de esto.
      return [];
    }
  }

  /// Reserva directa (sin cola) para una fecha con cupo. Lanza si falla.
  /// Permite cantidad (1..disponibles), datos adicionales y reservar para tercero.
  static Future<void> reservarDirecto({
    required String uuidUsuario,
    required int idLocalServicio,
    required DateTime fecha,
    int? cantidad,
    Map<String, dynamic>? datosAdicionales,
    bool paraTercero = false,
    String? terceroNombre,
    String? terceroApellidos,
    String? terceroCi,
    String? terceroTelefono,
    String? moneda,
    int? idTurno,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .rpc(
            'cliente_reservar_directo',
            params: {
              'p_uuid_usuario': uuidUsuario,
              'p_id_local_servicio': idLocalServicio,
              'p_fecha': fecha.toIso8601String().substring(0, 10),
              if (cantidad != null) 'p_cantidad': cantidad,
              if (datosAdicionales != null)
                'p_datos_adicionales': datosAdicionales,
              'p_para_tercero': paraTercero,
              if (paraTercero) 'p_t_nombre': terceroNombre,
              if (paraTercero) 'p_t_apellidos': terceroApellidos,
              if (paraTercero) 'p_t_ci': terceroCi,
              if (paraTercero) 'p_t_telefono': terceroTelefono,
              if (moneda != null) 'p_moneda': moneda,
              if (idTurno != null) 'p_id_turno': idTurno,
            },
          );
      final json = res as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'No se pudo reservar');
      }
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<List<Agenda>> getMisTickets(
    String uuidUsuario, {
    int? idEstado,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .rpc(
            'cliente_obtener_agendas',
            params: {
              'p_uuid_usuario': uuidUsuario,
              if (idEstado != null) 'p_id_estado': idEstado,
            },
          );
      if (res == null) return [];
      final list = res as List;
      var tickets = list
          .map((e) => Agenda.fromJson(e as Map<String, dynamic>))
          .toList();
      if (desde != null) {
        tickets = tickets
            .where((t) => !t.fechaHoraReserva.isBefore(desde))
            .toList();
      }
      if (hasta != null) {
        tickets = tickets
            .where((t) => !t.fechaHoraReserva.isAfter(hasta))
            .toList();
      }
      return tickets;
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<Agenda> crearTicket({
    required String uuidUsuario,
    required int idLocalServicio,
    required DateTime fechaHoraReserva,
  }) async {
    try {
      // Estado 'reservado' = id 1
      final estadoRes = await _supabase
          .schema(_schema)
          .from('nom_estado_agenda')
          .select('id')
          .eq('nombre', 'reservado')
          .single();
      final idEstado = estadoRes['id'] as int;

      final res = await _supabase
          .schema(_schema)
          .from('agenda')
          .insert({
            'uuid_usuario': uuidUsuario,
            'id_local_servicio': idLocalServicio,
            'id_estado': idEstado,
            'fecha_hora_reserva': fechaHoraReserva.toIso8601String(),
          })
          .select(
            '*, nom_estado_agenda(*), local_servicio(*, app_dat_locales(*), app_dat_servicios(*))',
          )
          .single();
      return Agenda.fromJson(res);
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<Agenda> cancelarTicket(int idAgenda, {String? motivo}) async {
    try {
      // Usamos una RPC con SECURITY DEFINER para evitar problemas de RLS
      // cuando un administrador cancela una reserva de su entidad.
      // [61] `admin_cancelar_agenda` exige el motivo: sin él falla.
      final motivoLimpio = motivo?.trim();
      final res = await _supabase
          .schema(_schema)
          .rpc(
            'admin_cancelar_agenda',
            params: {
              'p_id_agenda': idAgenda,
              if (motivoLimpio != null && motivoLimpio.isNotEmpty)
                'p_motivo': motivoLimpio,
            },
          );
      return Agenda.fromJson(res as Map<String, dynamic>);
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  /// Cancela una reserva como cliente. Si la entidad configuró horas de
  /// anticipación, valida el plazo; de lo contrario permite cancelar en cualquier momento.
  ///
  /// [motivo] es **opcional** para el cliente (migración 61): si viene vacío o
  /// nulo la reserva se cancela sin motivo y la tarjeta no pinta el bloque.
  static Future<void> cancelarTicketCliente({
    required String uuidUsuario,
    required int idAgenda,
    String? motivo,
  }) async {
    final motivoLimpio = motivo?.trim();
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'cliente_cancelar_reserva',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_agenda': idAgenda,
            if (motivoLimpio != null && motivoLimpio.isNotEmpty)
              'p_motivo': motivoLimpio,
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo cancelar la reserva');
    }
  }

  static Future<List<EstadoAgenda>> getEstados() async {
    final res = await _supabase
        .schema(_schema)
        .from('nom_estado_agenda')
        .select()
        .order('id');
    return (res as List).map((e) => EstadoAgenda.fromJson(e)).toList();
  }
}
