import '../models/establecimiento_resumen.dart';
import '../widgets/filtros_servicios_sheet.dart';
import 'horario_atencion.dart';

/// Cómo se ordena el listado de establecimientos.
///
/// Es una decisión de la pantalla (no del servidor): `cliente_locales_publicos`
/// devuelve por nombre para que la lista sea estable, y aquí se reordena en
/// memoria. Así un cambio de orden no cuesta una petición.
enum OrdenEstablecimientos {
  mejorValorados('Mejor valorados'),
  masServicios('Más servicios'),
  nombre('A - Z');

  const OrdenEstablecimientos(this.etiqueta);

  final String etiqueta;
}

/// Ordena una copia de [establecimientos] según [orden].
///
/// Regla de honestidad del proyecto: en «Mejor valorados» los locales **sin
/// reseñas van al final**, nunca se les supone una valoración. Es la misma
/// regla que el orden del servidor en `cliente_home_feed(p_mejor_valorados)` y
/// que `HomeCatalogItem.tieneValoracion`.
List<EstablecimientoResumen> ordenarEstablecimientos(
  List<EstablecimientoResumen> establecimientos,
  OrdenEstablecimientos orden,
) {
  final copia = List<EstablecimientoResumen>.of(establecimientos);

  int porNombre(EstablecimientoResumen a, EstablecimientoResumen b) =>
      a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());

  switch (orden) {
    case OrdenEstablecimientos.mejorValorados:
      copia.sort((a, b) {
        // Lo primero es tener valoración, no cuánto vale.
        if (a.tieneValoracion != b.tieneValoracion) {
          return a.tieneValoracion ? -1 : 1;
        }
        if (a.tieneValoracion && b.tieneValoracion) {
          final porRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
          if (porRating != 0) return porRating;
          final porResenas = b.totalResenas.compareTo(a.totalResenas);
          if (porResenas != 0) return porResenas;
        }
        return porNombre(a, b);
      });
    case OrdenEstablecimientos.masServicios:
      copia.sort((a, b) {
        final porServicios = b.totalServicios.compareTo(a.totalServicios);
        if (porServicios != 0) return porServicios;
        final porRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
        if (porRating != 0) return porRating;
        return porNombre(a, b);
      });
    case OrdenEstablecimientos.nombre:
      copia.sort(porNombre);
  }

  return copia;
}

/// `true` si el establecimiento pasa los filtros del sheet.
///
/// Se apoya en `FiltrosServicios.coincide` —la MISMA regla que usan el Home y el
/// catálogo— rellenando los primitivos con lo que el local sí tiene:
///   * `precioDesde`/`monedaDesde` (el precio más bajo de sus servicios),
///   * su `provincia`,
///   * su valoración real (o `null` si no tiene reseñas: con «★ o más» activo
///     queda fuera, que es lo correcto),
///   * si está abierto ahora, recalculado con [ahora].
///
/// [idSubcategoriaActiva] es la subcategoría por la que ya filtró el servidor
/// (si el usuario viene del listado de categorías): se declara como si cada
/// local fuera de esa subcategoría para que el filtro no vacíe la lista.
/// El sheet de esta pantalla no ofrece subcategorías justamente por eso: el
/// filtro de subcategoría ya lo aplica el servidor.
bool pasaFiltrosEstablecimiento(
  EstablecimientoResumen establecimiento,
  FiltrosServicios filtros, {
  DateTime? ahora,
  int? idSubcategoriaActiva,
}) {
  final momento = ahora ?? DateTime.now();
  final estado = establecimiento.estadoHorario(momento);

  return filtros.coincide(
    precioItem: establecimiento.precioDesde,
    monedaItem: establecimiento.monedaDesde,
    provinciaItem: establecimiento.provincia,
    ratingItem: establecimiento.tieneValoracion ? establecimiento.rating : null,
    idLocalItem: establecimiento.idLocal,
    idSubcategoriaItem: idSubcategoriaActiva,
    // Un horario que no se pudo interpretar no es «abierto».
    abiertoItem: estado == EstadoHorario.desconocido
        ? null
        : estado == EstadoHorario.abierto,
  );
}

/// Opciones reales del sheet para esta pantalla, deducidas de los locales
/// cargados. Sin precios no se pinta la sección de precio; sin reseñas, la de
/// valoración. Nunca una opción que filtre a cero.
OpcionesFiltros opcionesFiltrosEstablecimientos(
  List<EstablecimientoResumen> establecimientos, {
  bool hayFavoritos = false,
  int totalFavoritos = 0,
}) {
  final precios = <OfertaPrecio>[];
  final provincias = <String>{};
  final locales = <int, LocalOpcion>{};
  var hayValoraciones = false;

  for (final e in establecimientos) {
    final precio = e.precioDesde;
    final moneda = e.monedaDesde;
    if (precio != null && precio > 0 && (moneda ?? '').isNotEmpty) {
      precios.add(OfertaPrecio(precio: precio, moneda: moneda!));
    }

    final provincia = e.provincia?.trim();
    if (provincia != null && provincia.isNotEmpty) provincias.add(provincia);

    locales.putIfAbsent(
      e.idLocal,
      () => LocalOpcion(
        id: e.idLocal,
        nombre: e.nombre,
        provincia: (provincia ?? '').isEmpty ? null : provincia,
      ),
    );

    if (e.tieneValoracion) hayValoraciones = true;
  }

  final listaProvincias = provincias.toList()..sort();
  final listaLocales = locales.values.toList()
    ..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));

  return OpcionesFiltros(
    precios: precios,
    provincias: listaProvincias,
    locales: listaLocales,
    hayValoraciones: hayValoraciones,
    hayFavoritos: hayFavoritos,
    totalFavoritos: totalFavoritos,
  );
}