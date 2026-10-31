/// Utilidades puras del **resumen de reservas del admin** (punto 3 del plan).
///
/// Vive aparte de la pantalla a propósito: el rango del calendario, la clave de
/// día y el agrupado son las tres cosas que se pueden equivocar en silencio
/// (días fuera del rango, marcadores que no aparecen, listas desordenadas) y
/// son exactamente las que se pueden fijar con tests sin levantar Flutter.
///
/// **Sin horizonte artificial**: a diferencia de `rango_calendario.dart` (que
/// sí lo necesita para que el cliente pueda reservar a futuro), aquí el rango
/// sale **solo de los datos**: del mes de hoy al último mes que tenga reservas.
/// Añadir meses vacíos solo haría al admin navegar por meses sin nada.
library;

/// Modo de visualización del resumen.
enum VistaReservas { calendario, lista }

/// Modo con el que se abre la pantalla.
///
/// Es una función (y no una constante) para que el día que se decida recordar
/// la última elección del admin solo cambie este punto.
VistaReservas vistaReservasPorDefecto() => VistaReservas.calendario;

/// Último día del mes de [dia], a medianoche.
///
/// `DateTime(y, m + 1, 0)` es el día 0 del mes siguiente, o sea el último del
/// mes de [dia]; Dart normaliza el mes 13 a enero del año siguiente, así que
/// diciembre y los cruces de año salen solos.
DateTime ultimoDiaDelMes(DateTime dia) => DateTime(dia.year, dia.month + 1, 0);

/// Rango navegable del calendario de resumen.
///
/// - `firstDay`: primer día del **mes de [hoy]**. El rango empieza en el mes en
///   curso para que el calendario no abra en mitad de un mes.
/// - `lastDay`: último día del mes de [ultimoDiaConReserva]. Si es `null` o
///   **anterior a [hoy]** —por ejemplo una entidad cuyas reservas se acabaron
///   el mes pasado— se usa el último día del mes de [hoy]: nunca se recorta por
///   debajo del mes en el que el admin ya está mirando.
///
/// El resultado no depende de la hora de los argumentos: solo del día.
({DateTime firstDay, DateTime lastDay}) rangoReservas({
  required DateTime hoy,
  DateTime? ultimoDiaConReserva,
}) {
  final primerDiaDeMes = DateTime(hoy.year, hoy.month, 1);
  final hoySinHora = DateTime(hoy.year, hoy.month, hoy.day);

  if (ultimoDiaConReserva == null) {
    return (firstDay: primerDiaDeMes, lastDay: ultimoDiaDelMes(hoySinHora));
  }

  final ultimo = DateTime(
    ultimoDiaConReserva.year,
    ultimoDiaConReserva.month,
    ultimoDiaConReserva.day,
  );

  if (ultimo.isBefore(hoySinHora)) {
    return (firstDay: primerDiaDeMes, lastDay: ultimoDiaDelMes(hoySinHora));
  }

  return (firstDay: primerDiaDeMes, lastDay: ultimoDiaDelMes(ultimo));
}

/// Clave de un día: `yyyy-MM-dd`, sin hora y sin zona.
///
/// Es la misma forma que devuelve la RPC en `dias[].fecha`, así que sirve de
/// índice del calendario sin conversiones de por medio.
String claveDia(DateTime dia) {
  final y = dia.year.toString().padLeft(4, '0');
  final m = dia.month.toString().padLeft(2, '0');
  final d = dia.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Agrupa [items] por la clave de día de [fecha].
///
/// El orden de entrada se conserva dentro de cada día (no se ordena: quien
/// ordena es la fuente de los datos) y el mapa resultante sale en el orden de
/// primera aparición de cada día.
Map<String, List<T>> agruparPorClaveDia<T>(
  Iterable<T> items,
  DateTime Function(T) fecha,
) {
  final agrupado = <String, List<T>>{};
  for (final item in items) {
    agrupado.putIfAbsent(claveDia(fecha(item)), () => <T>[]).add(item);
  }
  return agrupado;
}
