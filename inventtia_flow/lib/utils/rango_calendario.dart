/// Rango de meses navegables del calendario de reserva / lista de espera.
///
/// **Problema que resuelve:** el rango salía solo de los días con datos
/// (`firstDay` = mes del primer día con cupo, `lastDay` = fin del mes del último
/// día con cupo). Si el admin únicamente tenía planes del mes en curso, el
/// `lastDay` quedaba a fin de mes y el `PageView` del calendario **rebotaba**:
/// se veía el gesto de cambio de mes pero la página volvía ("hace como para
/// cambiar y se queda"). El RPC `cliente_entrar_sala_espera_reserva` acepta
/// cualquier fecha (no valida mes), así que el límite era puramente de UI.
///
/// Por eso el rango ya **no depende solo de los datos**: se garantiza un
/// horizonte mínimo hacia delante (12 meses al anotarse en la lista, 6 meses en
/// reserva directa) contado desde el mes actual, y nunca se recorta un mes que
/// ya tenga días con datos.
library;

/// Horizonte en meses hacia delante cuando se permite anotarse sin cupo.
const int _mesesHorizonteEspera = 12;

/// Horizonte en meses hacia delante para la reserva directa (solo días con cupo).
const int _mesesHorizonteReserva = 6;

/// Calcula el primer y el último día que el calendario debe permitir navegar.
///
/// - [diasDisponibles] son los días con disponibilidad devueltos por el backend
///   (puede venir vacía y en cualquier orden).
/// - [paraEspera] indica modo lista de espera (cualquier fecha futura sirve) o
///   reserva directa (solo días con cupo).
/// - [ahora] permite fijar "hoy" en los tests; por defecto `DateTime.now()`.
///
/// Reglas:
/// - `firstDay`: primer día del **mes actual**; si el primer día disponible es
///   anterior, se usa el mes de ese día (nunca dejar fuera días con datos).
/// - `lastDay`: el mayor entre el último día del mes del último día disponible y
///   el último día del mes que resulta de sumar el horizonte a `ahora`.
/// - Lista vacía: mes actual + horizonte (el calendario sigue siendo navegable,
///   que es justo lo que hace falta para anotarse en la cola).
({DateTime firstDay, DateTime lastDay}) rangoCalendario({
  required List<DateTime> diasDisponibles,
  required bool paraEspera,
  DateTime? ahora,
}) {
  final hoy = ahora ?? DateTime.now();
  final mesesHorizonte =
      paraEspera ? _mesesHorizonteEspera : _mesesHorizonteReserva;

  // `DateTime(y, m + horizonte + 1, 0)` = último día del mes (actual + horizonte),
  // ya que el día 0 de un mes es el último del mes anterior.
  final finHorizonte = DateTime(
    hoy.year,
    hoy.month + mesesHorizonte + 1,
    0,
  );

  // Sin datos no hay nada que respetar: mes actual + horizonte completo.
  if (diasDisponibles.isEmpty) {
    return (firstDay: DateTime(hoy.year, hoy.month, 1), lastDay: finHorizonte);
  }

  // Se recorren todos los días (no `first`/`last`) porque el orden de la lista
  // no está garantizado por el contrato del backend.
  DateTime? primerDia;
  DateTime? ultimoDia;
  for (final d in diasDisponibles) {
    final dia = DateTime(d.year, d.month, d.day);
    if (primerDia == null || dia.isBefore(primerDia)) primerDia = dia;
    if (ultimoDia == null || dia.isAfter(ultimoDia)) ultimoDia = dia;
  }

  final mesActual = DateTime(hoy.year, hoy.month, 1);
  final mesPrimerDato = DateTime(primerDia!.year, primerDia.month, 1);
  final firstDay =
      mesPrimerDato.isBefore(mesActual) ? mesPrimerDato : mesActual;

  final finMesUltimoDato = DateTime(ultimoDia!.year, ultimoDia.month + 1, 0);
  final lastDay =
      finMesUltimoDato.isAfter(finHorizonte) ? finMesUltimoDato : finHorizonte;

  return (firstDay: firstDay, lastDay: lastDay);
}
