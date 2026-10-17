/// Reglas de presentación y de armado de una **colección temática**
/// (`flow.coleccion`) en el lado cliente.
///
/// Viven fuera de las pantallas a propósito: la vista de marketing de la
/// colección y el asistente de reserva múltiple tienen que decidir lo mismo
/// (qué servicios van juntos, qué se puede reservar, cuánto suma la selección)
/// y sin red. Aquí no hay ni un `Widget` ni una llamada a Supabase, así que se
/// cubre con tests.
///
/// Nada de este archivo cambia el precio: los importes que se muestran son
/// **estimaciones de referencia** sobre el precio base del catálogo. El importe
/// definitivo lo fija el servidor (`flow.cotizar_reserva` /
/// `flow.cliente_reservar_directo`).
library;

import '../models/disponibilidad_dia.dart';
import '../services/home_catalog_service.dart';

/// Los servicios de una colección que publica un mismo establecimiento.
///
/// El orden de [servicios] es el **curado** por el superadmin (el mismo que
/// devuelve `cliente_home_feed` con `p_id_coleccion`): aquí no se reordena nada.
class GrupoEstablecimiento {
  const GrupoEstablecimiento({
    required this.nombre,
    required this.servicios,
    this.ubicacion,
  });

  /// `app_dat_locales.nombre`.
  final String nombre;

  /// Provincia y país del local, o `null` si no están configurados.
  final String? ubicacion;

  final List<HomeCatalogItem> servicios;

  int get total => servicios.length;
}

/// Agrupa por establecimiento **conservando el orden de llegada**.
///
/// Una colección cruza entidades, así que la ficha tiene que decir en qué local
/// se reserva cada cosa: agrupar es lo que evita que el cliente descubra a
/// última hora que los dos servicios que eligió están en locales distintos.
///
/// El grupo aparece en la posición del **primer** servicio de ese local, para
/// que el orden curado siga mandando.
List<GrupoEstablecimiento> agruparPorEstablecimiento(
  List<HomeCatalogItem> items,
) {
  final porLocal = <String, List<HomeCatalogItem>>{};
  final ubicacionPorLocal = <String, String?>{};

  for (final item in items) {
    final nombre = item.venue.trim().isEmpty ? 'Establecimiento' : item.venue;
    porLocal.putIfAbsent(nombre, () => <HomeCatalogItem>[]).add(item);
    ubicacionPorLocal.putIfAbsent(
      nombre,
      () => item.ubicacion ?? item.direccion,
    );
  }

  return [
    for (final entrada in porLocal.entries)
      GrupoEstablecimiento(
        nombre: entrada.key,
        servicios: List<HomeCatalogItem>.unmodifiable(entrada.value),
        ubicacion: ubicacionPorLocal[entrada.key],
      ),
  ];
}

/// Rango de precios base de una lista de servicios, en **una** moneda.
class RangoPrecios {
  const RangoPrecios({
    required this.minimo,
    required this.maximo,
    required this.moneda,
    required this.mixta,
  });

  final double minimo;
  final double maximo;
  final String moneda;

  /// `true` cuando la lista mezcla monedas: entonces el rango solo describe la
  /// moneda mayoritaria y la UI debe decir que hay importes en otra moneda en
  /// vez de sumarlos como si fueran lo mismo.
  final bool mixta;

  bool get unico => (maximo - minimo).abs() < 0.005;
}

/// Precio base mínimo y máximo de [items], o `null` si ninguno tiene precio
/// configurado (`config_precio` vacío es un caso real del catálogo).
///
/// Se queda con la **moneda más frecuente** para que el rango signifique algo:
/// sumar o comparar CUP con USD daría un número inventado.
RangoPrecios? rangoPrecios(List<HomeCatalogItem> items) {
  final porMoneda = <String, List<double>>{};
  for (final item in items) {
    final precio = item.price;
    final moneda = item.currency?.trim();
    if (precio == null || precio <= 0) continue;
    if (moneda == null || moneda.isEmpty) continue;
    porMoneda.putIfAbsent(moneda, () => <double>[]).add(precio);
  }
  if (porMoneda.isEmpty) return null;

  var moneda = porMoneda.keys.first;
  for (final entrada in porMoneda.entries) {
    if (entrada.value.length > porMoneda[moneda]!.length) moneda = entrada.key;
  }
  final valores = porMoneda[moneda]!..sort();
  return RangoPrecios(
    minimo: valores.first,
    maximo: valores.last,
    moneda: moneda,
    mixta: porMoneda.length > 1,
  );
}

/// Cómo va la selección del cliente antes de elegir turnos.
class ResumenSeleccion {
  const ResumenSeleccion({
    required this.servicios,
    required this.establecimientos,
    this.estimado,
    this.moneda,
    this.sumaCompleta = false,
  });

  /// Cuántos servicios están seleccionados.
  final int servicios;

  /// Cuántos establecimientos distintos hay entre los seleccionados.
  final int establecimientos;

  /// Suma de los precios base, o `null` cuando no se puede afirmar.
  final double? estimado;

  final String? moneda;

  /// `true` cuando **todos** los seleccionados tienen precio y comparten moneda:
  /// solo entonces la suma es un total y no un "desde".
  final bool sumaCompleta;

  bool get haySeleccion => servicios > 0;

  static const ResumenSeleccion vacio = ResumenSeleccion(
    servicios: 0,
    establecimientos: 0,
  );

  /// Texto del recuento: "1 servicio", "3 servicios · 2 establecimientos".
  String get etiquetaServicios =>
      servicios == 1 ? '1 servicio' : '$servicios servicios';

  String get etiquetaEstablecimientos => establecimientos == 1
      ? '1 establecimiento'
      : '$establecimientos establecimientos';
}

/// Resume la selección sin tocar la red.
///
/// [estimado] solo se calcula si **todos** los seleccionados traen precio y
/// comparten moneda; si falta alguno, se devuelve `null` en vez de un total
/// incompleto que el cliente leería como el importe a pagar.
ResumenSeleccion resumirSeleccion(List<HomeCatalogItem> seleccionados) {
  if (seleccionados.isEmpty) return ResumenSeleccion.vacio;

  final locales = <String>{};
  final monedas = <String>{};
  var suma = 0.0;
  var todosConPrecio = true;

  for (final item in seleccionados) {
    locales.add(item.venue.trim().isEmpty ? 'Establecimiento' : item.venue);
    final precio = item.price;
    final moneda = item.currency?.trim();
    if (precio == null || precio <= 0 || moneda == null || moneda.isEmpty) {
      todosConPrecio = false;
      continue;
    }
    monedas.add(moneda);
    suma += precio;
  }

  final homogenea = monedas.length == 1;
  final puedeSumar = todosConPrecio && homogenea;

  return ResumenSeleccion(
    servicios: seleccionados.length,
    establecimientos: locales.length,
    estimado: puedeSumar ? suma : null,
    moneda: homogenea ? monedas.first : null,
    sumaCompleta: puedeSumar,
  );
}

/// `true` cuando el servicio **solo** admite lista de espera.
///
/// Es la misma regla que la barra de acciones del detalle
/// (`LocalServicio.permiteReservaDirecta`) y la condición que valida
/// `flow.cliente_reservar_directo`: sin ella el servidor rechazaría la reserva.
/// La colección lo enseña en la tarjeta para no ofrecer algo que no se puede
/// cerrar en el asistente.
bool soloListaDeEspera(HomeCatalogItem item) => !item.permiteReservaDirecta;

/// Por qué un servicio **no** puede entrar en el asistente de reserva múltiple.
/// `null` cuando sí puede.
///
/// Dos casos, ambos reales y ambos con salida por la ficha del servicio:
///
/// * `permite_reserva_directa = false`: el servidor responde
///   *"Reserva directa no habilitada para este servicio"*; por ahí solo se
///   entra a la **lista de espera**.
/// * Transporte ómnibus (`transporte_omnibus`): su reserva tiene su propio
///   formulario (ida/vuelta, dos fechas y dos turnos) y su propia lectura de
///   disponibilidad (`cliente_obtener_disponibilidad_transporte`), así que no
///   se puede cerrar desde un selector de día + turno.
///
/// Se enseña en la tarjeta en vez de esconder el servicio: el cliente tiene que
/// poder llegar a él, solo que por el camino que sí funciona.
String? motivoNoReservableEnLote(HomeCatalogItem item) {
  if (item.localServicio?.esTransporteOmnibus ?? false) {
    return 'Se reserva en su ficha';
  }
  if (!item.permiteReservaDirecta) return 'Solo lista de espera';
  return null;
}

/// `true` cuando el asistente de reserva múltiple puede cerrar este servicio.
bool reservableEnLote(HomeCatalogItem item) =>
    motivoNoReservableEnLote(item) == null;

/// `true` cuando el servicio tiene precio configurado y por tanto se puede
/// **cotizar** contra el servidor antes de reservar.
///
/// `config_precio = '{}'` es un caso real del catálogo: ahí la app dice
/// "Consultar precio" y no debe inventar un total (un "0 USD" sería peor que no
/// decir nada). Es la misma condición que usa `ConfigPrecio.tienePrecio`.
bool precioCotizable(HomeCatalogItem item) =>
    item.localServicio?.servicio?.configPrecio.tienePrecio ?? false;

/// `true` cuando el cliente tiene que elegir opciones (campos adicionales,
/// "para alguien más" o moneda) antes de poder reservar.
///
/// Réplica exacta de la condición con la que el detalle de un servicio decide
/// abrir la hoja de datos (`_recolectarDatosReserva`). El asistente la usa para
/// exigir ese paso por servicio: sin él, un servicio con reglas de precio se
/// reservaría sin los valores que el servidor necesita para cotizar.
bool requiereOpciones(HomeCatalogItem item) {
  final servicio = item.localServicio?.servicio;
  if (servicio == null) return false;
  return servicio.permiteTercero ||
      servicio.camposAdicionales.isNotEmpty ||
      servicio.configPrecio.tienePrecio;
}

/// Días que **de verdad** se pueden reservar: los que el servidor devolvió con
/// cupo, ordenados por fecha.
///
/// El riel del selector no puede inventar días: si un día no viene en
/// `cliente_obtener_disponibilidad` o llega en cero, no se ofrece.
List<DisponibilidadDia> diasReservables(List<DisponibilidadDia> dias) {
  final out = dias.where((d) => d.disponibles > 0).toList()
    ..sort((a, b) => a.fecha.compareTo(b.fecha));
  return out;
}

/// Cupo que se puede tomar en un día concreto, con o sin turno elegido.
int cupoDe({required DisponibilidadDia dia, TurnoDisponible? turno}) {
  final cupo = turno?.disponibles ?? dia.disponibles;
  return cupo < 0 ? 0 : cupo;
}

/// Máximo de plazas que el cliente puede pedir de una vez.
///
/// Es el mínimo entre lo que el admin permite por reserva
/// (`cantidad_max_capacidad`) y el cupo que queda. Nunca devuelve menos de 1:
/// un cupo desconocido (`0` en la respuesta de turnos configurados) no puede
/// dejar el asistente sin poder reservar.
int maxCantidadReservable({
  required HomeCatalogItem item,
  required DisponibilidadDia dia,
  TurnoDisponible? turno,
}) {
  final tope = item.cantidadMaxCapacidad < 1 ? 1 : item.cantidadMaxCapacidad;
  final libre = cupoDe(dia: dia, turno: turno);
  final util = libre < 1 ? 1 : libre;
  return tope < util ? tope : util;
}

const List<String> _abreviaturasDia = [
  'Lun',
  'Mar',
  'Mié',
  'Jue',
  'Vie',
  'Sáb',
  'Dom',
];

const List<String> _nombresDia = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

/// `"Lun"`, `"Sáb"`… sin depender del locale ni de `intl`.
String abreviaturaDia(DateTime fecha) => _abreviaturasDia[fecha.weekday - 1];

/// `"lunes"`, `"sábado"`…
String nombreDia(DateTime fecha) => _nombresDia[fecha.weekday - 1];

/// `"Hoy"`, `"Mañana"` o `"Lun 12"`.
///
/// [ahora] entra por parámetro para poder probarlo sin depender del reloj.
String etiquetaDiaCorto(DateTime fecha, DateTime ahora) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dia = DateTime(fecha.year, fecha.month, fecha.day);
  final diferencia = dia.difference(hoy).inDays;
  if (diferencia == 0) return 'Hoy';
  if (diferencia == 1) return 'Mañana';
  return '${abreviaturaDia(fecha)} ${fecha.day}';
}

/// `"12 mar"` — fecha corta para el resumen de una reserva ya elegida.
String fechaCorta(DateTime fecha) {
  const meses = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${fecha.day} ${meses[fecha.month - 1]}';
}

/// Etiqueta larga del día elegido: `"Hoy, 12 mar"`.
String etiquetaDiaLargo(DateTime fecha, DateTime ahora) {
  final corto = etiquetaDiaCorto(fecha, ahora);
  final esRelativo = corto == 'Hoy' || corto == 'Mañana';
  return esRelativo
      ? '$corto, ${fechaCorta(fecha)}'
      : '$corto · ${nombreDia(fecha)}';
}

/// `"Turno mañana · 09:00 – 11:00"`, o solo el nombre si el admin no puso horas.
String etiquetaTurno(TurnoDisponible turno) {
  final hora = turno.etiquetaHora;
  final nombre = turno.turno.trim().isEmpty ? 'Turno' : turno.turno.trim();
  return hora == null ? nombre : '$nombre · $hora';
}

/// Importe con el formato de la app: `"18 USD"`, `"1500 CUP"`.
String importeCorto(double monto, String? moneda) {
  final txt = monto == monto.roundToDouble()
      ? monto.toStringAsFixed(0)
      : monto.toStringAsFixed(2);
  final m = (moneda == null || moneda.trim().isEmpty) ? 'USD' : moneda.trim();
  return '$txt $m';
}
