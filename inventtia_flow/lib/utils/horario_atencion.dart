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

  /// Días mencionados en el texto. Si aparecen dos o más, se toma el rango
  /// cerrado entre el primero y el último; uno solo restringe a ese día.
  static Set<int> _diasDe(String normalizado) {
    final encontrados = <int>[];
    // Las claves abreviadas primero para no confundir "lun" con "lunes".
    for (final entrada in _nombresDia.entries) {
      final indice = normalizado.indexOf(entrada.key);
      if (indice < 0) continue;
      if (encontrados.contains(entrada.value)) continue;
      encontrados.add(entrada.value);
    }
    if (encontrados.isEmpty) return const <int>{};
    if (encontrados.length == 1) return <int>{encontrados.first};

    final primero = encontrados.first;
    final ultimo = encontrados.last;
    if (primero == ultimo) return <int>{primero};
    final resultado = <int>{};
    var dia = primero;
    while (true) {
      resultado.add(dia);
      if (dia == ultimo) break;
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
