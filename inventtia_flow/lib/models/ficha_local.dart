import 'establecimiento_resumen.dart';
import '../services/campana_service.dart';
import '../services/home_catalog_service.dart';

/// Cabecera común de la ficha de un establecimiento.
///
/// Existe porque la MISMA pantalla (`FichaLocalScreen`) se abre desde dos sitios
/// con datos de origen distinto:
///   * **Espacio patrocinado** (`flow.campanas_activas()`): la campaña trae los
///     datos del local ya resueltos y añade su titular, su degradado y su
///     vigencia.
///   * **Listado de establecimientos** (`flow.cliente_locales_publicos()`,
///     migración 57): no hay campaña; el local viene con su valoración real y su
///     número de servicios.
///
/// Normalizar aquí evita que la pantalla tenga dos ramas de pintado con campos
/// distintos, que es como se acaba mostrando «null» en algún hueco.
class FichaLocal {
  const FichaLocal({
    required this.nombre,
    this.idLocal,
    this.titular,
    this.subtitulo,
    this.descripcion,
    this.descripcionDestacada,
    this.direccion,
    this.provincia,
    this.pais,
    this.horarioTexto,
    this.horarioDetalle,
    this.foto,
    this.entidad,
    this.entidadTelefono,
    this.icono,
    this.colorInicio,
    this.colorFin,
    this.rating,
    this.totalResenas = 0,
    this.totalServicios,
    this.hasta,
    this.destacado = false,
  });

  final int? idLocal;
  final String nombre;

  /// Segunda línea de la cabecera: el titular de la campaña o quién publica el
  /// local.
  final String? titular;

  final String? subtitulo;
  final String? descripcion;
  final String? descripcionDestacada;
  final String? direccion;
  final String? provincia;
  final String? pais;
  final String? horarioTexto;
  final Map<String, dynamic>? horarioDetalle;
  final String? foto;
  final String? entidad;
  final String? entidadTelefono;

  /// Clave corta del icono de campaña (`spa`, `storefront`...). La pantalla la
  /// traduce; aquí se guarda cruda para que este modelo no dependa de Flutter.
  final String? icono;

  /// Colores de la campaña en hex (`#RRGGBB` o `#AARRGGBB`). `null` = degradado
  /// de marca.
  final String? colorInicio;
  final String? colorFin;

  final double? rating;
  final int totalResenas;
  final int? totalServicios;

  /// Fin de vigencia de la campaña, si la hay.
  final DateTime? hasta;

  /// `true` cuando viene del espacio patrocinado (sello y bloque de campaña).
  final bool destacado;

  String? get ubicacion {
    final p = provincia?.trim();
    final pa = pais?.trim();
    if (p != null && p.isNotEmpty) {
      if (pa != null && pa.isNotEmpty && pa != p) return '$p, $pa';
      return p;
    }
    return (pa != null && pa.isNotEmpty) ? pa : null;
  }

  bool get tieneValoracion => totalResenas > 0 && (rating ?? 0) > 0;

  /// Una ficha de campaña: el local manda como nombre y el titular de la
  /// campaña queda debajo.
  factory FichaLocal.desdeCampana(CampanaPatrocinada campana) {
    final local = campana.local?.trim() ?? '';
    final hayLocal = local.isNotEmpty;
    return FichaLocal(
      idLocal: campana.idLocal,
      nombre: hayLocal ? local : campana.titulo.trim(),
      titular: hayLocal ? campana.titulo.trim() : campana.subtitulo?.trim(),
      subtitulo: campana.subtitulo?.trim(),
      descripcion: campana.localDescripcion?.trim(),
      descripcionDestacada: campana.descripcion?.trim(),
      direccion: campana.localDireccion?.trim(),
      provincia: campana.localProvincia?.trim(),
      pais: campana.localPais?.trim(),
      horarioTexto: campana.localHorarioAtencion?.trim(),
      horarioDetalle: campana.localHorarioDetalle,
      foto: campana.imagenPrincipal,
      entidad: campana.entidad?.trim(),
      entidadTelefono: campana.entidadTelefono?.trim(),
      icono: campana.icono,
      colorInicio: campana.colorInicio,
      colorFin: campana.colorFin,
      hasta: campana.hasta,
      destacado: true,
    );
  }

  /// Una ficha normal: el local con su valoración y sus servicios.
  factory FichaLocal.desdeEstablecimiento(EstablecimientoResumen e) {    return FichaLocal(
      idLocal: e.idLocal,
      nombre: e.nombre,
      titular: e.entidad,
      descripcion: e.descripcion,
      direccion: e.direccion,
      provincia: e.provincia,
      pais: e.pais,
      horarioTexto: e.horarioTexto,
      horarioDetalle: e.horarioDetalle,
      foto: e.foto,
      entidad: e.entidad,
      entidadTelefono: e.entidadTelefono,
      rating: e.rating,
      totalResenas: e.totalResenas,
      totalServicios: e.totalServicios,
      destacado: false,
    );
  }

  /// Ficha a partir de un ítem del feed del Home.
  ///
  /// La usa la sección «Establecimientos» del Home, que trabaja con
  /// `HomeCatalogItem` (un local-servicio) y no con el listado agregado: al tocar
  /// una de esas tarjetas se abre la misma ficha del espacio patrocinado, en vez
  /// de saltar al catálogo filtrado como antes.
  ///
  /// Se prefiere la FOTO DEL LOCAL a la del servicio: la ficha presenta el
  /// establecimiento, no un servicio concreto.
  factory FichaLocal.desdeItem(HomeCatalogItem item) {
    final local = item.localServicio?.local;
    final fotoLocal = local?.foto?.trim();
    return FichaLocal(
      idLocal: item.localServicio?.idLocal ?? local?.id,
      nombre: item.venue,
      descripcion: local?.descripcion?.trim(),
      direccion: item.direccion?.trim(),
      provincia: item.provincia?.trim(),
      pais: item.pais?.trim(),
      horarioTexto: item.horarioTexto.trim().isEmpty ? null : item.horarioTexto.trim(),
      horarioDetalle: item.horarioDetalle,
      foto: (fotoLocal != null && fotoLocal.isNotEmpty) ? fotoLocal : item.imageUrl,
      rating: item.rating,
      totalResenas: item.totalResenas,
      destacado: false,
    );
  }
}