/// Tasa de cambio del día («el toque») tal y como la sirve el backend.
///
/// La forma del JSON la fijan `flow.tasas_actuales()` (migración 60) y la Edge
/// Function `flow-tasas`:
///
/// ```json
/// { "ok": true, "fecha": "2026-10-27", "hora": "07:00:06",
///   "fuente": "directoriocubano", "actualizado": "2026-10-27 07:00:06",
///   "vigente": true,
///   "tasas": { "USD": {"CUP": 840, ...}, ... },
///   "conversiones": { "USD": {"CUP": 840, "EUR": 0.908108, ...}, ... } }
/// ```
///
/// `conversiones` es la matriz ya normalizada entre las monedas de la app
/// (`USD`, `EUR`, `CUP`, `MLC`) e **incluye el cruce por CUP**, que es lo que
/// evita que la app tenga que calcular factores por su cuenta.
///
/// Este modelo es puro (sin Flutter ni Supabase) y tolerante al parseo: acepta
/// `num` o texto numérico, fechas ISO o `dd/mm/aaaa`, y descarta las claves que
/// no entiende en vez de lanzar.
class TasasDia {
  /// Día al que corresponde la tasa (sólo fecha, sin hora).
  final DateTime? fecha;

  /// Hora que publicó el proveedor (`HH:mm:ss`), tal cual.
  final String? hora;

  /// Marca de actualización del proveedor, tal cual llega (texto).
  final String? actualizado;

  /// `true` sólo si la tasa se guardó HOY (día de La Habana).
  final bool vigente;

  /// JSON crudo del proveedor: `tasas[origen][destino] = valor`.
  final Map<String, dynamic> tasas;

  /// Matriz normalizada `conversiones[origen][destino] = factor`.
  ///
  /// Ya trae el cruce por CUP y la identidad (`USD → USD = 1`). Si falta una
  /// clave, esa conversión **no existe**: no se supone 1.
  final Map<String, Map<String, double>> conversiones;

  /// Origen de la tasa (p. ej. el proveedor), para la tarjeta de estado.
  final String? fuente;

  /// Aviso opcional del backend («no se pudo refrescar», «no se pudo cachear»).
  final String? aviso;

  const TasasDia({
    this.fecha,
    this.hora,
    this.actualizado,
    this.vigente = false,
    this.tasas = const {},
    this.conversiones = const {},
    this.fuente,
    this.aviso,
  });

  /// `true` si la matriz de conversiones trae algo usable.
  bool get hayDatos => conversiones.isNotEmpty;

  /// Factor `origen → destino` (1 unidad de origen = N de destino), o `null`.
  ///
  /// No inventa nada: si la moneda no está en la matriz (o el factor es 0 o
  /// negativo, que no sirve para convertir) devuelve `null`, **no** 1.
  double? factor(String origen, String destino) {
    final o = origen.trim().toUpperCase();
    final d = destino.trim().toUpperCase();
    if (o.isEmpty || d.isEmpty) return null;
    final fila = conversiones[o];
    if (fila == null) return null;
    final valor = fila[d];
    if (valor == null || !valor.isFinite || valor <= 0) return null;
    return valor;
  }

  /// `true` si [fecha] es el mismo día que [referencia].
  bool esDelDia(DateTime referencia) {
    final f = fecha;
    if (f == null) return false;
    return f.year == referencia.year &&
        f.month == referencia.month &&
        f.day == referencia.day;
  }

  /// `true` si la tasa es de hoy (reloj del dispositivo).
  bool get esDeHoy => esDelDia(DateTime.now());

  /// Fecha en `dd/mm/aaaa` para pintarla; `—` si no llegó.
  String get fechaTexto {
    final f = fecha;
    if (f == null) return '—';
    return '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/${f.year}';
  }

  /// Hora legible: la del proveedor o `—`.
  String get horaTexto {
    final h = (hora ?? '').trim();
    return h.isEmpty ? '—' : h;
  }

  factory TasasDia.fromJson(Map<String, dynamic> json) {
    return TasasDia(
      fecha: _fechaDesde(json['fecha']),
      hora: _texto(json['hora']),
      actualizado: _texto(json['actualizado']),
      vigente: json['vigente'] == true,
      tasas: _mapa(json['tasas']),
      conversiones: _conversiones(json['conversiones']),
      fuente: _texto(json['fuente']),
      aviso: _texto(json['aviso']),
    );
  }

  Map<String, dynamic> toJson() => {
    if (fecha != null) 'fecha': _fechaIso(fecha!),
    if (hora != null) 'hora': hora,
    if (actualizado != null) 'actualizado': actualizado,
    'vigente': vigente,
    'tasas': tasas,
    'conversiones': conversiones,
    if (fuente != null) 'fuente': fuente,
    if (aviso != null) 'aviso': aviso,
  };

  /// Igual que [fromJson] pero devuelve `null` si el backend dijo `ok: false`
  /// o si no llegó ninguna conversión (no hay nada que convertir).
  static TasasDia? desdeRespuesta(Object? data) {
    final json = _mapa(data);
    if (json['ok'] == false) return null;
    final tasas = TasasDia.fromJson(json);
    return tasas.hayDatos ? tasas : null;
  }

  @override
  String toString() =>
      'TasasDia(fecha: $fechaTexto, vigente: $vigente, '
      'monedas: ${conversiones.keys.join(",")})';
}

// ── Parseo tolerante (privado del modelo) ────────────────────────────────────

String? _texto(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _mapa(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return {for (final e in raw.entries) e.key.toString(): e.value};
  }
  return const {};
}

DateTime? _fechaDesde(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) {
    return DateTime(raw.year, raw.month, raw.day);
  }
  final texto = raw.toString().trim();
  if (texto.isEmpty) return null;

  // ISO: "2026-10-27" o "2026-10-27T07:00:06Z".
  final iso = DateTime.tryParse(texto);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);

  // dd/mm/aaaa (formato en que se pinta, por si vuelve de caché local).
  final dmy = RegExp(
    r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$',
  ).firstMatch(texto);
  if (dmy != null) {
    final d = int.tryParse(dmy.group(1)!);
    final m = int.tryParse(dmy.group(2)!);
    final y = int.tryParse(dmy.group(3)!);
    if (d != null && m != null && y != null && m >= 1 && m <= 12) {
      return DateTime(y, m, d);
    }
  }
  return null;
}

String _fechaIso(DateTime f) =>
    '${f.year.toString().padLeft(4, '0')}-'
    '${f.month.toString().padLeft(2, '0')}-'
    '${f.day.toString().padLeft(2, '0')}';

double? _double(Object? raw) {
  if (raw is num) {
    final v = raw.toDouble();
    return v.isFinite ? v : null;
  }
  if (raw is String) {
    final v = double.tryParse(raw.trim());
    return (v != null && v.isFinite) ? v : null;
  }
  return null;
}

Map<String, Map<String, double>> _conversiones(Object? raw) {
  final out = <String, Map<String, double>>{};
  final mapa = _mapa(raw);
  if (mapa.isEmpty) return out;
  for (final fila in mapa.entries) {
    final origen = fila.key.trim().toUpperCase();
    if (origen.isEmpty) continue;
    final destinos = <String, double>{};
    for (final par in _mapa(fila.value).entries) {
      final destino = par.key.trim().toUpperCase();
      if (destino.isEmpty) continue;
      final valor = _double(par.value);
      if (valor == null || valor <= 0) continue;
      destinos[destino] = valor;
    }
    if (destinos.isNotEmpty) out[origen] = destinos;
  }
  return out;
}