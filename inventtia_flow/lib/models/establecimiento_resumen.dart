import '../models/config_precio.dart';
import '../utils/horario_atencion.dart';
import '../utils/precio_reserva.dart';

/// Un establecimiento (local) con lo que el cliente puede reservar dentro.
///
/// Sale de `flow.cliente_locales_publicos(...)` (migración 57), que ya aplica la
/// misma regla de visibilidad que el feed: un local solo aparece si tiene al
/// menos un par local-servicio reservable, y la entidad tiene que estar al día.
///
/// `rating`/`totalResenas` se agregan en el servidor **por local** (suma de
/// puntuaciones / número de reseñas), no promediando los promedios por servicio:
/// es el dato exacto. Sin reseñas, `rating` es `null` y la tarjeta no pinta
/// estrellas — no se le supone una valoración a nadie.
///
/// `precioDesde` se resuelve en Dart con [precioBaseDe], la misma regla que usan
/// el Home, el catálogo y el detalle. La RPC devuelve el `config_precio` crudo de
/// cada servicio precisamente para no tener una tercera implementación del
/// precio en SQL.
class EstablecimientoResumen {
  const EstablecimientoResumen({
    required this.idLocal,
    required this.nombre,
    this.descripcion,
    this.direccion,
    this.pais,
    this.provincia,
    this.foto,
    this.horarioTexto,
    this.horarioDetalle,
    this.entidad,
    this.entidadTelefono,
    this.entidadDireccion,
    this.totalServicios = 0,
    this.totalResenas = 0,
    this.rating,
    this.tieneReservaDirecta = false,
    this.precioDesde,
    this.monedaDesde,
  });

  final int idLocal;
  final String nombre;
  final String? descripcion;
  final String? direccion;
  final String? pais;
  final String? provincia;

  /// Foto del local (`flow.app_dat_locales.foto`). Puede faltar.
  final String? foto;

  final String? horarioTexto;
  final Map<String, dynamic>? horarioDetalle;

  final String? entidad;
  final String? entidadTelefono;
  final String? entidadDireccion;

  /// Pares local-servicio visibles de este local.
  final int totalServicios;

  final int totalResenas;
  final double? rating;

  /// Alguno de sus servicios admite reserva directa (sin lista de espera).
  final bool tieneReservaDirecta;

  /// Precio base más bajo de sus servicios, en la moneda del servicio más
  /// barato. `null` si ninguno tiene precio configurado.
  final double? precioDesde;
  final String? monedaDesde;

  /// Misma condición que `HomeCatalogItem.tieneValoracion`: sin reseñas no se
  /// pintan estrellas ni un «0.0».
  bool get tieneValoracion => totalResenas > 0 && (rating ?? 0) > 0;

  /// `"Villa Clara Province"`, o la dirección si no hay provincia.
  String? get ubicacion {
    final p = provincia?.trim();
    if (p != null && p.isNotEmpty) return p;
    final d = direccion?.trim();
    if (d != null && d.isNotEmpty) return d;
    return null;
  }

  String get etiquetaServicios =>
      totalServicios == 1 ? '1 servicio' : '$totalServicios servicios';

  String get etiquetaResenas =>
      totalResenas == 1 ? '1 reseña' : '$totalResenas reseñas';

  /// `"2500 CUP"`: el importe más bajo, sin la palabra «Desde».
  ///
  /// Es lo que pinta la tarjeta del listado en su propia línea. Antes se pintaba
  /// «Desde XXX CUP» entero en una columna estrecha y el texto salía cortado con
  /// puntos suspensivos; separarlo en dos líneas («Desde» pequeño arriba, el
  /// importe debajo) hace que quepa sin recortar.
  String? get precioDesdeMontoLabel {
    final precio = precioDesde;
    if (precio == null || precio <= 0) return null;
    final monto = precio == precio.roundToDouble()
        ? precio.toStringAsFixed(0)
        : precio.toStringAsFixed(2);
    return '$monto ${monedaDesde ?? 'USD'}';
  }

  /// `"Desde 2500 CUP"`, o `null` si ningún servicio tiene precio.
  String? get precioDesdeLabel {
    final monto = precioDesdeMontoLabel;
    if (monto == null) return null;
    return 'Desde $monto';
  }

  /// Estado del horario evaluado con el reloj que se le pase (inyectable para
  /// tests: un local «abierto ahora» depende de la hora).
  EstadoHorario estadoHorario(DateTime ahora) => HorarioAtencion.parseConDetalle(
    horarioTexto,
    horarioDetalle,
  ).evaluar(ahora);

  bool abiertoAhora(DateTime ahora) =>
      estadoHorario(ahora) == EstadoHorario.abierto;

  factory EstablecimientoResumen.fromJson(Map<String, dynamic> json) {
    final entidad = json['entidad'];
    final entidadMap = entidad is Map
        ? Map<String, dynamic>.from(entidad)
        : null;

    // El servidor manda el `config_precio` de cada servicio visible; aquí se
    // aplica la regla de precio de siempre.
    //
    // El «desde» se calcula SIEMPRE en una sola moneda: la del local (aquella en
    // la que están precios la mayoría de sus servicios). Comparar importes de
    // monedas distintas por su número no significa nada —5 USD no es «más barato»
    // que 3000 CUP— y era lo que hacía que un local con casi todo en CUP
    // anunciara «Desde 5 USD» por un único servicio en dólares.
    final porMoneda = <String, List<double>>{};
    for (final crudo in (json['precios'] as List?) ?? const <dynamic>[]) {
      final config = ConfigPrecio.fromJson(
        crudo is Map ? Map<String, dynamic>.from(crudo) : null,
      );
      final base = precioBaseDe(config);
      if (base == null) continue;
      porMoneda.putIfAbsent(base.moneda, () => <double>[]).add(base.precio);
    }

    double? precioDesde;
    String? monedaDesde;
    for (final entrada in porMoneda.entries) {
      final minimo = entrada.value.reduce((a, b) => a < b ? a : b);
      // Gana la moneda con más servicios (la del local); a igualdad, la más
      // barata. Nunca se mezclan importes de monedas distintas.
      final actual = porMoneda[monedaDesde];
      final gana = monedaDesde == null ||
          entrada.value.length > (actual?.length ?? 0) ||
          (entrada.value.length == (actual?.length ?? 0) &&
              minimo < (precioDesde ?? double.infinity));
      if (gana) {
        precioDesde = minimo;
        monedaDesde = entrada.key;
      }
    }

    return EstablecimientoResumen(
      idLocal: (json['id'] as num?)?.toInt() ?? 0,
      nombre: (json['nombre'] as String?)?.trim() ?? 'Establecimiento',
      descripcion: (json['descripcion'] as String?)?.trim(),
      direccion: (json['direccion'] as String?)?.trim(),
      pais: (json['pais'] as String?)?.trim(),
      provincia: (json['provincia'] as String?)?.trim(),
      foto: (json['foto'] as String?)?.trim(),
      horarioTexto: (json['horario_atencion'] as String?)?.trim(),
      horarioDetalle: json['horario_detalle'] is Map
          ? Map<String, dynamic>.from(json['horario_detalle'] as Map)
          : null,
      entidad: (entidadMap?['denominacion'] as String?)?.trim(),
      entidadTelefono: (entidadMap?['telefono'] as String?)?.trim(),
      entidadDireccion: (entidadMap?['direccion'] as String?)?.trim(),
      totalServicios: (json['total_servicios'] as num?)?.toInt() ?? 0,
      totalResenas: (json['total_resenas'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble(),
      tieneReservaDirecta: json['tiene_reserva_directa'] == true,
      precioDesde: precioDesde,
      monedaDesde: monedaDesde,
    );
  }
}