/// Modalidad de pago de un trabajador.
///
/// Un día NO equivale a 8h ni a 24h: es una unidad de pago independiente con
/// su propia tarifa. Nunca se derivan días dividiendo horas.
///
/// El PPR es un bono fijo por jornada en ambas modalidades: esta modalidad
/// solo gobierna el salario base.
enum TipoSalario {
  hora,
  dia;

  static const _dbHora = 'hora';
  static const _dbDia = 'dia';

  /// Parsea el valor de `tipo_salario` que viene de la base de datos.
  /// Cualquier valor desconocido o nulo cae en [TipoSalario.hora], que es el
  /// comportamiento histórico del módulo.
  static TipoSalario fromDb(dynamic value) {
    return value == _dbDia ? TipoSalario.dia : TipoSalario.hora;
  }

  /// Valor a enviar a la base de datos.
  String get dbValue => this == TipoSalario.dia ? _dbDia : _dbHora;

  bool get esPorDia => this == TipoSalario.dia;
  bool get esPorHora => this == TipoSalario.hora;

  /// Etiqueta corta para badges en tablas y listas. Ej: 'DÍA'
  String get badge => this == TipoSalario.dia ? 'DÍA' : 'HORA';

  /// Nombre de la modalidad para textos descriptivos. Ej: 'Por día'
  String get label => this == TipoSalario.dia ? 'Por día' : 'Por hora';

  /// Sufijo de la tarifa. Ej: '/d' -> "\$1500.00/d"
  String get tarifaSufijo => this == TipoSalario.dia ? '/d' : '/h';

  /// Unidad singular de la cantidad pagada. Ej: 'día' / 'hora'
  String get unidad => this == TipoSalario.dia ? 'día' : 'hora';

  /// Unidad plural. Ej: 'días' / 'horas'
  String get unidadPlural => this == TipoSalario.dia ? 'días' : 'horas';

  /// Abreviatura de la unidad para campos compactos. Ej: 'd' / 'h'
  String get unidadCorta => this == TipoSalario.dia ? 'd' : 'h';

  /// Etiqueta del campo editable en el cierre de jornada.
  String get labelCantidadAPagar =>
      this == TipoSalario.dia ? 'Días a pagar:' : 'Horas a pagar:';

  /// Formatea una tarifa con su sufijo. Ej: '\$1500.00/d'
  String formatTarifa(double tarifa) =>
      '\$${tarifa.toStringAsFixed(2)}$tarifaSufijo';

  /// Formatea una cantidad pagada con su unidad.
  /// Modalidad día: '1.5 d'. Modalidad hora: '8h 30m'.
  String formatCantidad(double cantidad) {
    if (this == TipoSalario.dia) {
      // 1 -> "1 d", 1.5 -> "1.5 d"
      final texto = cantidad == cantidad.roundToDouble()
          ? cantidad.toStringAsFixed(0)
          : cantidad.toStringAsFixed(2);
      return '$texto d';
    }
    final h = cantidad.floor();
    final m = ((cantidad - h) * 60).round();
    return '${h}h ${m}m';
  }
}
