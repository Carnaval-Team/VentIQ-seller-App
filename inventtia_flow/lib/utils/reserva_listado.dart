import '../models/agenda.dart';

/// Ítem del listado admin/vendedor: una agenda suelta, o el par ida+vuelta
/// del mismo día agrupado en una sola fila.
class ReservaListItem {
  /// Pierna principal (ida si es par mismo día; o la única agenda).
  final Agenda principal;

  /// Pierna de vuelta cuando es ida+vuelta el mismo día.
  final Agenda? pareja;

  const ReservaListItem({required this.principal, this.pareja});

  bool get esIdaVueltaMismoDia => pareja != null;

  List<Agenda> get agendas => [
        principal,
        if (pareja != null) pareja!,
      ];

  /// Etiqueta de tipo para la tarjeta.
  /// - Par mismo día → "Ida y Regreso"
  /// - Pierna suelta → "Ida" / "Regreso"
  String get etiquetaTipo {
    if (esIdaVueltaMismoDia) return 'Ida y Regreso';

    final trayecto = principal.tipoTrayecto?.toLowerCase();
    if (trayecto == 'ida') return 'Ida';
    if (trayecto == 'vuelta') return 'Regreso';

    final viaje = principal.datosAdicionales?['tipo_viaje']?.toString().toLowerCase();
    if (viaje == 'ida') return 'Ida';
    if (viaje == 'vuelta') return 'Regreso';
    if (viaje == 'ida_vuelta') {
      // Sin tipo_trayecto aún: no inventar "Ida y Regreso" en una sola fila.
      return 'Pasaje';
    }
    return '';
  }

  double? get precioTotal {
    final sum = agendas.fold<double>(
      0,
      (acc, a) => acc + (a.precioTotal ?? 0),
    );
    return sum > 0 ? sum : null;
  }

  String? get moneda =>
      principal.moneda ?? pareja?.moneda;

  bool get esCancelada =>
      agendas.every((a) => a.estado?.esCancelado == true);

  bool get esCompletada =>
      agendas.every((a) => a.estado?.esCompletado == true);

  bool get esActiva => !esCancelada && !esCompletada;

  /// Motivo con el que se canceló la reserva (migración 61), o `null` si no lo
  /// hay (p. ej. cancelaciones anteriores a esa migración).
  ///
  /// Fuente única para las tres tarjetas (admin, vendedor y «Mis tickets»): el
  /// par ida+vuelta comparte cancelación, así que se toma el primero que
  /// exista. Un texto en blanco cuenta como sin motivo.
  String? get motivoCancelacion {
    for (final a in agendas) {
      final texto = a.motivoCancelacion?.trim();
      if (texto != null && texto.isNotEmpty) return texto;
    }
    return null;
  }

  /// Rol de quien canceló (`cliente`/`admin`/`staff`/`sistema`), o `null`.
  String? get canceladoPorRol {
    for (final a in agendas) {
      final rol = a.canceladoPorRol?.trim();
      if (rol != null && rol.isNotEmpty) return rol;
    }
    return null;
  }

  /// Pasajeros de este ítem (no duplica ida+vuelta mismo día).
  int get pasajeros {
    final n = principal.cantidad;
    return n <= 0 ? 1 : n;
  }
}

/// Suma de precios por moneda usando el listado agrupado (ida+vuelta mismo
/// día cuenta una sola vez, sumando ambos tramos si el precio está partido).
/// Solo cuenta reservas **Reservado** y **Completado** (excluye canceladas).
Map<String, double> sumarPreciosReservas(List<Agenda> reservas) {
  final out = <String, double>{};
  for (final item in agruparReservasParaListado(reservas)) {
    if (item.esCancelada) continue;
    if (!(item.esActiva || item.esCompletada)) continue;
    final monto = item.precioTotal;
    if (monto == null || monto <= 0) continue;
    final mon = item.moneda ?? 'USD';
    out[mon] = (out[mon] ?? 0) + monto;
  }
  return out;
}

/// Cantidad de reservas/pasajes para el resumen (ida+vuelta mismo día = 1).
int contarReservasAgrupadas(
  List<Agenda> reservas, {
  bool excluirCanceladas = true,
}) {
  var n = 0;
  for (final item in agruparReservasParaListado(reservas)) {
    if (excluirCanceladas && item.esCancelada) continue;
    n += item.pasajeros;
  }
  return n;
}

/// Una agenda representativa por ítem (para totales de campos adicionales).
List<Agenda> agendasRepresentativas(List<Agenda> reservas) =>
    agruparReservasParaListado(reservas).map((i) => i.principal).toList();


/// Agrupa agendas del mismo [idViaje] y misma fecha calendario en un solo
/// ítem ("Ida y vuelta"). Piernas en fechas distintas quedan independientes
/// con tipo Ida / Vuelta.
List<ReservaListItem> agruparReservasParaListado(List<Agenda> reservas) {
  final used = <int>{};
  final result = <ReservaListItem>[];

  bool mismaFecha(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  final byViaje = <String, List<Agenda>>{};
  for (final r in reservas) {
    final id = r.idViaje;
    if (id != null && id.isNotEmpty) {
      byViaje.putIfAbsent(id, () => []).add(r);
    }
  }

  // Fallback sin id_viaje: mismo cliente + servicio + día + tipo_viaje ida_vuelta.
  String claveFallback(Agenda r) {
    final dia =
        '${r.fechaHoraReserva.year}-${r.fechaHoraReserva.month}-${r.fechaHoraReserva.day}';
    return '${r.idLocalServicio}|${r.uuidUsuario}|$dia';
  }

  final byFallback = <String, List<Agenda>>{};
  for (final r in reservas) {
    final viaje = r.datosAdicionales?['tipo_viaje']?.toString();
    if (viaje == 'ida_vuelta' && (r.idViaje == null || r.idViaje!.isEmpty)) {
      byFallback.putIfAbsent(claveFallback(r), () => []).add(r);
    }
  }

  ReservaListItem? emparejarMismoDia(List<Agenda> sameDay) {
    if (sameDay.length < 2) return null;
    Agenda ida = sameDay.first;
    Agenda vuelta = sameDay.last;
    for (final a in sameDay) {
      if (a.tipoTrayecto == 'ida') ida = a;
      if (a.tipoTrayecto == 'vuelta') vuelta = a;
    }
    if (ida.id == vuelta.id) {
      vuelta = sameDay.firstWhere((a) => a.id != ida.id);
    }
    used.addAll(sameDay.map((a) => a.id));
    return ReservaListItem(principal: ida, pareja: vuelta);
  }

  for (final r in reservas) {
    if (used.contains(r.id)) continue;

    final idViaje = r.idViaje;
    if (idViaje != null && idViaje.isNotEmpty) {
      final grupo = byViaje[idViaje] ?? const <Agenda>[];
      final sameDay =
          grupo.where((o) => mismaFecha(o.fechaHoraReserva, r.fechaHoraReserva)).toList();
      final par = emparejarMismoDia(sameDay);
      if (par != null) {
        result.add(par);
        continue;
      }
    } else {
      final grupo = byFallback[claveFallback(r)] ?? const <Agenda>[];
      final par = emparejarMismoDia(grupo);
      if (par != null) {
        result.add(par);
        continue;
      }
    }

    used.add(r.id);
    result.add(ReservaListItem(principal: r));
  }

  return result;
}

/// Normaliza un tipo de trayecto / nombre de turno a etiqueta de UI.
/// "vuelta" → "Regreso"; "ida y vuelta" → "Ida y Regreso".
String etiquetaTrayectoUi(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  final low = s.toLowerCase();
  if (low == 'vuelta' || low == 'regreso' || low == 'solo vuelta') {
    return 'Regreso';
  }
  if (low == 'ida' || low == 'solo ida') return 'Ida';
  if (low.contains('ida') &&
      (low.contains('vuelta') || low.contains('regreso'))) {
    return 'Ida y Regreso';
  }
  if (low.contains('vuelta') || low.contains('regreso')) return 'Regreso';
  if (low.contains('ida')) return 'Ida';
  return s[0].toUpperCase() + s.substring(1);
}

/// ¿Puede el **cliente** cancelar esta reserva por su cuenta?
///
/// Fuente única de verdad para el botón "Cancelar reserva" del listado de
/// tickets. Es una función pura (sin Supabase) para poder testearla con
/// [ahora] inyectado.
///
/// Reglas (decisión D3 del plan):
/// 1. Solo si el estado es `Reservado`: nunca se cancela algo ya cancelado
///    ni algo ya completado.
/// 2. La reserva no ha pasado: si la fecha/hora de la reserva es igual o
///    anterior a [ahora], ya no se puede cancelar.
/// 3. Si la entidad exige un plazo de anticipación
///    (`horas_anticipacion_cancelacion > 0`), todavía debe quedar ese margen;
///    con `0` o `null` se puede cancelar en cualquier momento hasta la propia
///    hora de la reserva.
bool puedeCancelarCliente(Agenda agenda, {DateTime? ahora}) {
  // 1. Solo reservas en estado Reservado (ni canceladas ni completadas).
  if (agenda.estado?.esReservado != true) return false;

  final momento = ahora ?? DateTime.now();

  // 2. La fecha/hora de la reserva debe seguir en el futuro.
  if (!momento.isBefore(agenda.fechaHoraReserva)) return false;

  // 3. Plazo de anticipación configurado por la entidad (0/null = sin plazo).
  final horas = agenda.entidad?.horasAnticipacionCancelacion ?? 0;
  if (horas > 0) {
    final limite = agenda.fechaHoraReserva.subtract(Duration(hours: horas));
    if (!momento.isBefore(limite)) return false;
  }

  return true;
}

/// Clave de tramo para totales: solo Ida o Regreso (nunca el paquete).
String? claveTramoParaTotales(Agenda r) {
  final trayecto = r.tipoTrayecto?.toLowerCase().trim();
  if (trayecto == 'ida') return 'Ida';
  if (trayecto == 'vuelta') return 'Regreso';

  final nombre = (r.turnoNombre ?? '').toLowerCase();
  if (nombre.contains('ida') &&
      !(nombre.contains('vuelta') || nombre.contains('regreso'))) {
    return 'Ida';
  }
  if ((nombre.contains('vuelta') || nombre.contains('regreso')) &&
      !nombre.contains('ida')) {
    return 'Regreso';
  }
  // Turno combinado sin tipo_trayecto: no atribuir a un solo tramo aquí.
  return null;
}

/// Grupo de estado en el listado de reservas del cliente.
///
/// 0 = activas (las que aún importan), 1 = canceladas, 2 = completadas.
/// Cualquier otro estado (o ninguno) cuenta como activo: es lo que el cliente
/// necesita ver primero.
int prioridadEstadoReserva(Agenda agenda) {
  final estado = agenda.estado;
  if (estado?.esCompletado == true) return 2;
  if (estado?.esCancelado == true) return 1;
  return 0;
}

/// Orden del listado de reservas del cliente.
///
/// 1. Primero las **activas** (reservado), después las **canceladas** y al final
///    las **completadas** (ver [prioridadEstadoReserva]).
/// 2. Dentro de cada grupo, por fecha **más cercana a [ahora]**: en las activas
///    sale primero la próxima cita y en las completadas/canceladas la más
///    reciente. Se compara la distancia absoluta a [ahora], así que una reserva
///    de hoy se ve arriba aunque ya haya pasado su hora.
/// 3. Desempate determinista: la más próxima en el futuro y, si coinciden,
///    el `id` mayor (lo último creado).
///
/// Devuelve una **copia**: no reordena la lista que recibe.
List<Agenda> ordenarReservasCliente(
  List<Agenda> reservas, {
  DateTime? ahora,
}) {
  final referencia = ahora ?? DateTime.now();
  final copia = List<Agenda>.of(reservas);
  copia.sort((a, b) {
    final grupo = prioridadEstadoReserva(
      a,
    ).compareTo(prioridadEstadoReserva(b));
    if (grupo != 0) return grupo;

    final distanciaA = a.fechaHoraReserva.difference(referencia).abs();
    final distanciaB = b.fechaHoraReserva.difference(referencia).abs();
    final porDistancia = distanciaA.compareTo(distanciaB);
    if (porDistancia != 0) return porDistancia;

    final porFecha = a.fechaHoraReserva.compareTo(b.fechaHoraReserva);
    if (porFecha != 0) return porFecha;
    return b.id.compareTo(a.id);
  });
  return copia;
}

