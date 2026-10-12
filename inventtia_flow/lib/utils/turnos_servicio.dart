import '../models/disponibilidad_dia.dart';

/// Reglas de presentación de los turnos de un servicio en la ficha.
///
/// Viven fuera de la pantalla para poder probarlas sin montar `LocalServicio`
/// entero (y sin red): son decisiones pequeñas, pero son justo las que se
/// rompen en silencio al tocar la pantalla.

/// Día cuyos turnos conviene enseñar.
///
/// La disponibilidad llega **por día**, así que se elige el primer día con
/// algún turno con cupo y, si no hay ninguno, el primero que tenga turnos: es
/// mejor poder decir "sin cupo" (y ofrecer la lista de espera) que no decir
/// nada. Devuelve `null` si el servicio no trabaja por turnos.
DisponibilidadDia? diaDeTurnosAMostrar(List<DisponibilidadDia> dias) {
  final conTurnos = dias.where((d) => d.tieneTurnos).toList();
  if (conTurnos.isEmpty) return null;
  for (final dia in conTurnos) {
    if (dia.turnos.any((t) => t.disponibles > 0)) return dia;
  }
  return conTurnos.first;
}

/// Cupo de un turno, en corto: "1 libre", "3 libres" o "Sin cupo".
String etiquetaCupoTurno(int disponibles) {
  if (disponibles <= 0) return 'Sin cupo';
  return disponibles == 1 ? '1 libre' : '$disponibles libres';
}

/// "Hoy" o "Mañana" si la fecha cae en esos días; `null` si es más lejana.
///
/// [ahora] entra por parámetro para poder probarlo sin depender del reloj.
String? etiquetaRelativaDia(DateTime fecha, DateTime ahora) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final diferencia = dia.difference(hoy).inDays;
  if (diferencia == 0) return 'Hoy';
  if (diferencia == 1) return 'Mañana';
  return null;
}

/// Une los turnos que la disponibilidad del día trae **con cupo** y los que el
/// admin tiene **configurados** (sin cupo conocido).
///
/// Para la reserva directa solo valen los del día; para la **lista de espera**
/// hay que poder elegir cualquier turno configurado aunque ese día no quede
/// hueco (que es justo el motivo de anotarse). Manda el dato del día cuando
/// existe, para no perder el cupo real.
List<TurnoDisponible> combinarTurnosConConfig(
  List<TurnoDisponible> delDia,
  List<TurnoDisponible> configurados,
) {
  if (configurados.isEmpty) return List<TurnoDisponible>.of(delDia);
  if (delDia.isEmpty) return List<TurnoDisponible>.of(configurados);

  final yaEstan = {for (final t in delDia) t.idTurno};
  return [
    ...delDia,
    for (final t in configurados)
      if (!yaEstan.contains(t.idTurno)) t,
  ];
}
