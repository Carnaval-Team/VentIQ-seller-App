import '../models/agenda.dart';
import 'reserva_listado.dart';

/// Estados a los que se puede llevar una reserva **cancelada**.
///
/// Espeja las reglas de `flow.staff_marcar_estado_agenda` (migración 58): el
/// servidor es el que manda, pero la interfaz necesita saber qué puede ofrecer
/// para no llevar al usuario a un error.
enum DestinoReactivacion {
  pendiente(
    idEstado: 1,
    etiqueta: 'Dejarla pendiente',
    ayuda: 'Vuelve a estado Reservado y ocupa capacidad otra vez.',
    mensajeOk: 'Reserva reactivada y cliente notificado',
  ),
  completado(
    idEstado: 3,
    etiqueta: 'Marcarla como completada',
    ayuda: 'Queda como atendida y se guarda la hora de atención.',
    mensajeOk: 'Reserva reactivada y marcada como completada',
  );

  const DestinoReactivacion({
    required this.idEstado,
    required this.etiqueta,
    required this.ayuda,
    required this.mensajeOk,
  });

  /// Id real en `flow.nom_estado_agenda`: 1 Reservado, 3 Completado.
  final int idEstado;

  /// Texto del botón.
  final String etiqueta;

  /// Qué implica, debajo del botón.
  final String ayuda;

  /// Aviso de éxito que muestra la pantalla al aplicarlo.
  final String mensajeOk;
}

/// Lo que se puede hacer con la reserva cancelada [agenda].
///
/// Mismas reglas que el servidor:
///   * **pendiente** (Reservado): solo si la reserva es de **hoy o futura**. No
///     tiene sentido devolver a «pendiente» una cita que ya pasó.
///   * **completado**: solo si la reserva es de **hoy o anterior**. Es la forma
///     de cerrar una cancelada que sí se atendió.
///
/// Una reserva de **hoy** admite las dos: puede volver a la cola o darse por
/// completada. Una futura, solo pendiente; una pasada, solo completada.
///
/// [ahora] es inyectable para poder probar los tres casos sin depender del reloj.
List<DestinoReactivacion> destinosReactivacion(
  Agenda agenda, {
  DateTime? ahora,
}) {
  final hoy = _dia(ahora ?? DateTime.now());
  final diaReserva = _dia(agenda.fechaHoraReserva);
  return <DestinoReactivacion>[
    if (!diaReserva.isBefore(hoy)) DestinoReactivacion.pendiente,
    if (!diaReserva.isAfter(hoy)) DestinoReactivacion.completado,
  ];
}

/// Por qué NO se ofrece [destino] para esta reserva, o `null` si sí se ofrece.
///
/// Se usa para explicarlo en el diálogo: un botón ausente sin motivo deja al
/// usuario pensando que la app se equivocó. Incluye la fecha de la reserva,
/// que es el dato que decide.
String? motivoNoDisponible(
  DestinoReactivacion destino,
  Agenda agenda, {
  DateTime? ahora,
}) {
  if (destinosReactivacion(agenda, ahora: ahora).contains(destino)) return null;
  final hoy = _dia(ahora ?? DateTime.now());
  final diaReserva = _dia(agenda.fechaHoraReserva);
  final pasada = diaReserva.isBefore(hoy);
  return switch (destino) {
    DestinoReactivacion.pendiente =>
      pasada
          ? 'La reserva ya pasó: no se puede volver a dejar pendiente.'
          : 'Solo se pueden reactivar reservas de hoy o futuras.',
    DestinoReactivacion.completado =>
      'Solo se pueden dar por completadas las reservas de hoy o anteriores.',
  };
}

/// Cuando la reserva no admite ninguna opción (no debería ocurrir: una cancelada
/// es de hoy, futura o pasada), un texto para explicarlo.
String motivoSinOpciones(Agenda agenda, {DateTime? ahora}) =>
    'No se puede reactivar una reserva del '
    '${_fechaCorta(agenda.fechaHoraReserva)}.';

/// Traduce el fallo de `staff_marcar_estado_agenda` a algo que se entienda.
///
/// El caso importante es el primero: si la migración **58** todavía no está
/// aplicada, el servidor contesta «Estado destino no permitido (use Cancelado o
/// Completado)» y el usuario no tiene forma de saber que lo que falta es un paso
/// en la base de datos.
String mensajeErrorCambioEstado(Object error) {
  final texto = error.toString();
  if (texto.contains('Estado destino no permitido')) {
    return 'Falta aplicar la migración 58 en Supabase: sin ella el servidor solo '
        'deja cancelar o completar, no devolver una reserva a pendiente.';
  }
  if (texto.contains('Solo se pueden reactivar reservas de hoy o fechas futuras')) {
    return 'Esa reserva ya pasó: solo se pueden reactivar las de hoy o futuras. '
        'Para cerrarla, márcala como completada.';
  }
  if (texto.contains(
    'Solo se pueden completar reservas canceladas de hoy o fechas anteriores',
  )) {
    return 'Esa reserva es futura: no se puede dar por completada antes de su '
        'fecha. Reactívala como pendiente.';
  }
  if (texto.contains('Solo se pueden cancelar reservas activas')) {
    return 'Solo se pueden cancelar las reservas activas.';
  }
  if (texto.contains('Solo se pueden reactivar reservas canceladas')) {
    return 'Solo se pueden reactivar las reservas canceladas.';
  }
  return texto.replaceFirst('Exception: ', '');
}

DateTime _dia(DateTime fecha) => DateTime(fecha.year, fecha.month, fecha.day);

/// ¿Se puede confirmar el consumo de esta reserva desde el listado
/// admin/vendedor?
///
/// * **Activa** → sí (es el caso normal; el servidor no pone fecha).
/// * **Cancelada cuya fecha ya llegó** (hoy o antes) → sí. Es la forma de
///   cerrarla, y `staff_marcar_estado_agenda` (migración 58) lo acepta
///   re-consumiendo la capacidad que liberó la cancelación.
/// * **Cancelada futura** → no: el servidor lo rechaza porque aún no ha pasado.
/// * **Completada** → no.
///
/// El par ida+vuelta se comprueba entero (`every`) para no empezar una operación
/// que el servidor rechazaría en la segunda pierna. Como el par agrupa solo las
/// ida+vuelta del MISMO día, en la práctica las dos piernas van juntas.
bool puedeCompletarReserva(ReservaListItem item, {DateTime? ahora}) {
  if (item.esCompletada) return false;
  if (item.esCancelada) {
    final hoy = _dia(ahora ?? DateTime.now());
    return item.agendas.every(
      (a) => !_dia(a.fechaHoraReserva).isAfter(hoy),
    );
  }
  return item.esActiva;
}

/// ¿Se puede ofrecer «Reactivar» (elegir estado destino) para esta reserva?
///
/// Solo para canceladas, y solo si alguna pierna es de hoy o futura: una
/// cancelada que ya pasó no se puede volver a dejar pendiente (el servidor lo
/// rechaza); para cerrarla está [puedeCompletarReserva].
bool puedeReactivarReserva(ReservaListItem item, {DateTime? ahora}) {
  if (!item.esCancelada) return false;
  final hoy = _dia(ahora ?? DateTime.now());
  return item.agendas.any((a) => !_dia(a.fechaHoraReserva).isBefore(hoy));
}

String _fechaCorta(DateTime fecha) {
  final dia = fecha.day.toString().padLeft(2, '0');
  final mes = fecha.month.toString().padLeft(2, '0');
  return '$dia/$mes/${fecha.year}';
}
