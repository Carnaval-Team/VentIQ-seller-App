/// Interpretación de `flow.app_dat_locales.horario_atencion`.
///
/// La columna es **texto libre**: en producción conviven formatos muy distintos
/// y ninguno tiene estructura garantizada. Valores reales observados:
///
/// ```text
/// "8-4"                        "8:00 a 17:00"
/// "Lun - Dom, 8:30 - 16:00"    "Lun-Sab 8:00am - 6:00pm"
/// "8:30am a 4:00pm"            "9:00am - 3:00pm"
/// "sd"                          null
/// ```
///
/// Este parser **no inventa**: cuando no logra interpretar el texto devuelve
/// [EstadoHorario.desconocido] para que la interfaz diga "Horario no
/// disponible" en lugar de afirmar que el local está abierto. Ese era el
/// defecto anterior, que solo buscaba la palabra "cerrado" y por tanto marcaba
/// como abiertos todos los locales.
library;

/// Resultado de evaluar un horario.
enum EstadoHorario {
  /// El texto se interpretó y `ahora` cae dentro de la franja.
  abierto,

  /// El texto se interpretó y `ahora` cae fuera (o el local se declara cerrado).
  cerrado,

  /// El texto está vacío o no se pudo interpretar. No se puede afirmar nada.
  desconocido,
}

/// Franja horaria dentro de un día, en minutos desde medianoche.
class FranjaHorario {
  const FranjaHorario({required this.desdeMinutos, required this.hastaMinutos});

  final int desdeMinutos;

  /// Puede ser mayor que 1440 cuando la franja cruza medianoche.
  final int hastaMinutos;

  /// `true` si [minutos] del día cae dentro de la franja.
  bool contiene(int minutos) {
    var valor = minutos;
    if (hastaMinutos > 1440 && valor < desdeMinutos) {
      valor += 1440;
    }
    return valor >= desdeMinutos && valor < hastaMinutos;
  }

  @override
  String toString() => 'FranjaHorario($desdeMinutos, $hastaMinutos)';
}

/// Horario de atención ya interpretado.
class HorarioAtencion {
  const HorarioAtencion._({
    required this.texto,
    required this.franjas,
    required this.dias,
    required this.declaradoCerrado,
  });

  /// Texto original tal como está en la base de datos.
  final String texto;

  /// Franjas detectadas. Vacío cuando el horario es desconocido o el local se
  /// declara cerrado.
  final List<FranjaHorario> franjas;

  /// Días de la semana (1 = lunes … 7 = domingo) a los que aplican [franjas].
  /// Vacío significa "todos los días".
  final Set<int> dias;

  /// El texto declara explícitamente que el local está cerrado.
  final bool declaradoCerrado;

  /// Horario no interpretable (texto vacío, "sd", prosa libre…).
  bool get esDesconocido => !declaradoCerrado && franjas.isEmpty;

  /// `true` si se puede afirmar que el local está abierto o cerrado ahora.
  bool get esFiable => !esDesconocido;

  /// Evalúa el horario para un instante dado.
  EstadoHorario evaluar(DateTime ahora) {
    if (declaradoCerrado) return EstadoHorario.cerrado;
    if (esDesconocido) return EstadoHorario.desconocido;
    if (dias.isNotEmpty && !dias.contains(ahora.weekday)) {
      return EstadoHorario.cerrado;
    }
    final minutos = ahora.hour * 60 + ahora.minute;
    final abierto = franjas.any((f) => f.contiene(minutos));
    return abierto ? EstadoHorario.abierto : EstadoHorario.cerrado;
  }

  /// Texto corto y honesto para pintar en una tarjeta.
  String get etiqueta {
    if (declaradoCerrado) return 'Cerrado';
    if (esDesconocido) return 'Horario no disponible';
    return texto;
  }

  /// Horario no interpretable a partir del texto crudo.
  static const HorarioAtencion desconocido = HorarioAtencion._(
    texto: '',
    franjas: <FranjaHorario>[],
    dias: <int>{},
    declaradoCerrado: false,
  );

  /// Interpreta [raw]. Nunca lanza: ante cualquier duda devuelve un horario con
  /// [esDesconocido] en `true`.
  static HorarioAtencion parse(String? raw) {
    final texto = (raw ?? '').trim();
    if (texto.isEmpty) return desconocido;

    final normalizado = _sinAcentos(texto.toLowerCase());
    final tiempos = _patronHora.allMatches(normalizado).toList();
    final mencionaCierre = _marcadoresCerrado.any(normalizado.contains);

    // "Cerrado" a secas sí es concluyente. Si además hay horas
    // ("Lun-Vie 8-4, Sáb cerrado") el texto mezcla casos que este parser no
    // modela, así que se prefiere declararlo desconocido antes que mentir.
    if (mencionaCierre) {
      if (tiempos.isNotEmpty) return desconocido;
      return HorarioAtencion._(
        texto: texto,
        franjas: const <FranjaHorario>[],
        dias: const <int>{},
        declaradoCerrado: true,
      );
    }

    if (tiempos.length < 2) return desconocido;

    // Solo se interpretan las dos primeras horas: los formatos reales son
    // "apertura <separador> cierre". Un tercer número suele ser texto suelto.
    final desde = _minutosDe(tiempos[0]);
    final hastaCrudo = _minutosDe(tiempos[1]);
    if (desde == null || hastaCrudo == null) return desconocido;

    var hasta = hastaCrudo;
    if (hasta <= desde) {
      // Sin meridiem explícito, "8-4" es 8:00 → 16:00. Si tampoco cuadra,
      // se asume una franja que cruza medianoche.
      hasta = hasta + 720 > desde ? hasta + 720 : hasta + 1440;
    }

    return HorarioAtencion._(
      texto: texto,
      franjas: <FranjaHorario>[
        FranjaHorario(desdeMinutos: desde, hastaMinutos: hasta),
      ],
      dias: _diasDe(normalizado),
      declaradoCerrado: false,
    );
  }

  /// Interpreta el horario preferiendo el detalle estructurado.
  ///
  /// Cuando el admin usó el constructor de días + hora apertura/cierre,
  /// `horario_detalle` es la fuente exacta y se ignora la heurística del texto:
  /// **ese** es el arreglo del bug por el que "Lun, Mié, Vie" se leía como
  /// lunes-viernes. Si no hay detalle (modo texto libre, o un local anterior a
  /// la migración 40), se cae al parser clásico.
  static HorarioAtencion parseConDetalle(String? texto, Object? detalle) {
    final d = HorarioDetalle.fromJson(detalle);
    if (d == null) return parse(texto);

    final t = (texto ?? '').trim();
    return HorarioAtencion._(
      texto: t.isEmpty ? textoDesdeDetalle(d) : t,
      franjas: <FranjaHorario>[
        FranjaHorario(
          desdeMinutos: d.desdeMinutos,
          hastaMinutos: d.hastaMinutos,
        ),
      ],
      dias: d.dias.toSet(),
      declaradoCerrado: false,
    );
  }

  static const List<String> _marcadoresCerrado = <String>[
    'cerrado',
    'closed',
    'no abre',
    'no atiende',
  ];

  /// `hh`, `hh:mm` con `am`/`pm` opcional pegado o separado por espacio.
  static final RegExp _patronHora = RegExp(
    r'(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?',
  );

  static int? _minutosDe(RegExpMatch match) {
    final hora = int.tryParse(match.group(1) ?? '');
    if (hora == null) return null;
    final minuto = int.tryParse(match.group(2) ?? '') ?? 0;
    if (minuto > 59) return null;

    final meridiem = (match.group(3) ?? '').replaceAll('.', '');
    var h = hora;
    if (meridiem == 'pm') {
      h = (hora % 12) + 12;
    } else if (meridiem == 'am') {
      h = hora % 12;
    }
    if (h < 0 || h > 24) return null;
    if (h == 24) h = 0;
    return h * 60 + minuto;
  }

  /// Días mencionados en el texto.
  ///
  /// Si los días van **enumerados** ("Lun, Mié, Vie") se devuelve exactamente
  /// ese conjunto. Solo si van **encadenados** ("Lun-Vie", "Lun a Dom") se toma
  /// el rango cerrado, que es lo que el texto significa.
  ///
  /// Antes se tomaba siempre el rango entre el primero y el último mencionados,
  /// así que "Lun, Mié, Vie 8:00-17:00" se leía como lunes a viernes y el local
  /// aparecía **abierto** martes y jueves. Ahora el separador decide.
  static Set<int> _diasDe(String normalizado) {
    // Se recorre por POSICIÓN en el texto (no por orden del mapa) para que
    // "Vie a Lun" signifique lo mismo leído de izquierda a derecha.
    final posiciones = <int, int>{};
    for (final entrada in _nombresDia.entries) {
      final indice = normalizado.indexOf(entrada.key);
      if (indice < 0) continue;
      posiciones[indice] = entrada.value;
    }
    if (posiciones.isEmpty) return const <int>{};

    final ordenadas = posiciones.keys.toList()..sort();
    if (ordenadas.length == 1) return <int>{posiciones[ordenadas.first]!};

    final primero = ordenadas.first;
    final ultimo = ordenadas.last;
    final entre = normalizado.substring(primero, ultimo);
    final enumera =
        entre.contains(',') || entre.contains(' y ') || entre.contains(' e ');

    if (enumera) return posiciones.values.toSet();

    final desde = posiciones[primero]!;
    final hasta = posiciones[ultimo]!;
    if (desde == hasta) return <int>{desde};
    final resultado = <int>{};
    var dia = desde;
    while (true) {
      resultado.add(dia);
      if (dia == hasta) break;
      dia = dia == 7 ? 1 : dia + 1;
    }
    return resultado;
  }

  /// Orden de inserción relevante: se recorre en orden y se conserva el
  /// primero que aparece en el texto.
  static const Map<String, int> _nombresDia = <String, int>{
    'lun': DateTime.monday,
    'mar': DateTime.tuesday,
    'mie': DateTime.wednesday,
    'jue': DateTime.thursday,
    'vie': DateTime.friday,
    'sab': DateTime.saturday,
    'dom': DateTime.sunday,
  };

  static String _sinAcentos(String valor) => valor
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u');

  @override
  String toString() =>
      'HorarioAtencion("$texto", franjas: $franjas, dias: $dias, '
      'cerrado: $declaradoCerrado)';
}

// ---------------------------------------------------------------------------
// Horario estructurado (punto 10 del plan de mejoras)
// ---------------------------------------------------------------------------

/// Horario de atención construido por el admin: días + hora de apertura y de
/// cierre. Es el contenido de `flow.app_dat_locales.horario_detalle`:
///
/// ```json
/// { "dias": [1, 2, 3, 4, 5], "apertura": "08:00", "cierre": "17:00" }
/// ```
///
/// Vive junto al parser porque son las dos caras del mismo dato: el texto libre
/// (`horario_atencion`) se sigue interpretando con [HorarioAtencion.parse] y el
/// detalle exacto con [HorarioDetalle.fromJson] desde
/// [HorarioAtencion.parseConDetalle].
class HorarioDetalle {
  const HorarioDetalle._({
    required this.dias,
    required this.desdeMinutos,
    required this.hastaMinutos,
  });

  /// Días de la semana, 1 = lunes … 7 = domingo, ordenados y sin repetir.
  final List<int> dias;

  /// Minutos desde medianoche.
  final int desdeMinutos;

  /// Minutos desde medianoche. Puede superar 1440 cuando la franja cruza
  /// medianoche (22:00 → 02:00 queda como 1320 → 1560).
  final int hastaMinutos;

  /// Nombres largos, indexados por `weekday - 1`.
  static const List<String> nombresDia = <String>[
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  /// Abreviaturas, indexadas por `weekday - 1`.
  static const List<String> abreviaturasDia = <String>[
    'Lun',
    'Mar',
    'Mié',
    'Jue',
    'Vie',
    'Sáb',
    'Dom',
  ];

  /// Cierre == apertura significa "abierto todo el día".
  bool get es24Horas => desdeMinutos == 0 && hastaMinutos >= 1440;

  String get aperturaTexto => _hhmm(desdeMinutos);

  /// Hora de cierre en formato `HH:MM`. Si la franja cruza medianoche devuelve
  /// la hora real del reloj (`02:00`), no los minutos acumulados.
  String get cierreTexto => _hhmm(hastaMinutos % 1440);

  /// `"Lun-Vie"`, `"Lun, Mié, Vie"`, `"Sáb-Dom"` o `"Lun-Dom"`.
  String get etiquetaDias {
    if (dias.length == 7) return 'Lun-Dom';
    final partes = <String>[];
    var i = 0;
    while (i < dias.length) {
      var j = i;
      // Se agrupa solo lo que es contiguo de verdad: [1,3,5] no es un rango.
      while (j + 1 < dias.length && dias[j + 1] == dias[j] + 1) {
        j++;
      }
      if (j - i >= 2) {
        partes.add(
          '${abreviaturasDia[dias[i] - 1]}-${abreviaturasDia[dias[j] - 1]}',
        );
      } else {
        for (var k = i; k <= j; k++) {
          partes.add(abreviaturasDia[dias[k] - 1]);
        }
      }
      i = j + 1;
    }
    return partes.join(', ');
  }

  /// `"08:00-17:00"` o `"24 h"`.
  String get etiquetaRango =>
      es24Horas ? '24 h' : '$aperturaTexto-$cierreTexto';

  /// `"Lun-Vie 08:00-17:00"`: el texto canónico que se guarda en
  /// `horario_atencion` para que el resto de la app (y el parser clásico)
  /// entiendan lo mismo sin conocer el detalle.
  String get etiqueta => '$etiquetaDias $etiquetaRango';

  /// Horas de un día concreto para la tabla del cliente. Cadena vacía si ese día
  /// está cerrado.
  String horasDeDia(int dia) => dias.contains(dia) ? etiquetaRango : '';

  /// Construye un detalle validado, o `null` si los datos no son usables.
  ///
  /// Reglas:
  ///  · hace falta al menos un día válido (1..7);
  ///  · apertura y cierre tienen que venir las dos y en `H:MM` / `HH:MM`;
  ///  · apertura == cierre ⇒ 24 horas;
  ///  · cierre < apertura ⇒ la franja cruza medianoche (turno de noche).
  static HorarioDetalle? crear({
    required Iterable<int> dias,
    required String? apertura,
    required String? cierre,
  }) {
    final limpios = dias.where((d) => d >= 1 && d <= 7).toSet().toList()
      ..sort();
    if (limpios.isEmpty) return null;

    final desde = _minutosDeTexto(apertura);
    final hasta = _minutosDeTexto(cierre);
    if (desde == null || hasta == null) return null;

    if (desde == hasta) {
      return HorarioDetalle._(
        dias: limpios,
        desdeMinutos: 0,
        hastaMinutos: 1440,
      );
    }
    return HorarioDetalle._(
      dias: limpios,
      desdeMinutos: desde,
      hastaMinutos: hasta < desde ? hasta + 1440 : hasta,
    );
  }

  /// Lee la forma jsonb de la BD. Devuelve `null` ante cualquier dato inválido:
  /// un horario malformado no puede tumbar la ficha del local, solo hace que se
  /// use el parser de texto.
  static HorarioDetalle? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final diasRaw = raw['dias'];
    if (diasRaw is! List) return null;
    final dias = <int>[];
    for (final d in diasRaw) {
      if (d is num) dias.add(d.toInt());
    }
    return crear(
      dias: dias,
      apertura: raw['apertura'] is String ? raw['apertura'] as String : null,
      cierre: raw['cierre'] is String ? raw['cierre'] as String : null,
    );
  }

  /// Forma jsonb que se guarda en `horario_detalle`. Reversible con [fromJson].
  Map<String, dynamic> toJson() => <String, dynamic>{
    'dias': dias,
    'apertura': aperturaTexto,
    'cierre': cierreTexto,
  };

  /// Minutos desde medianoche de un texto `HH:MM`. `null` si no es válido.
  static int? minutosDeTexto(String? texto) => _minutosDeTexto(texto);

  /// `"HH:MM"` a partir de minutos desde medianoche.
  static String textoDeMinutos(int minutos) => _hhmm(minutos % 1440);

  @override
  String toString() => 'HorarioDetalle($etiqueta)';
}

/// Texto canónico de un [HorarioDetalle] (`"Lun-Vie 08:00-17:00"`).
///
/// Es lo que se guarda en `horario_atencion`, así que el cliente y el admin
/// leen lo mismo aunque uno use el detalle y el otro el parser de texto.
String textoDesdeDetalle(HorarioDetalle detalle) => detalle.etiqueta;

String _hhmm(int minutos) {
  final m = minutos % 1440;
  final h = m ~/ 60;
  return '${h.toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Acepta `"8:00"`, `"08:00"` y `"8"` (hora en punto). `null` si nada cuadra.
int? _minutosDeTexto(String? texto) {
  if (texto == null) return null;
  final t = texto.trim();
  if (t.isEmpty) return null;
  final partes = t.split(':');
  if (partes.length > 2) return null;
  final h = int.tryParse(partes[0]);
  if (h == null || h < 0 || h > 23) return null;
  final m = partes.length == 2 ? int.tryParse(partes[1]) : 0;
  if (m == null || m < 0 || m > 59) return null;
  return h * 60 + m;
}
