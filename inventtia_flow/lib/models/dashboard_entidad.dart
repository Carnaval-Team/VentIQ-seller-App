/// Modelos del dashboard de una entidad (punto 1 del plan de mejoras).
///
/// Todo viene de una sola llamada a `flow.admin_dashboard_entidad`, que ya
/// calcula los agregados en la base de datos. El parseo es **tolerante**: un
/// conteo ausente vale 0 y una fecha ilegible se descarta, de modo que un
/// cambio en la RPC no tumbe la pantalla de Gestión entera.
library;

/// Conteo de algo que puede estar activo o no (locales, servicios, pares).
class ConteoActivo {
  const ConteoActivo({required this.total, required this.activos});

  final int total;
  final int activos;

  /// Derivado, no viene de la RPC: así nunca puede contradecir a [total] y
  /// [activos].
  int get inactivos => (total - activos).clamp(0, total);

  /// 0..1. Con [total] == 0 devuelve 0 en vez de NaN.
  double get proporcionActiva => total == 0 ? 0 : activos / total;

  factory ConteoActivo.fromJson(Object? raw) {
    if (raw is! Map) return const ConteoActivo(total: 0, activos: 0);
    final total = _int(raw['total']);
    final activos = _int(raw['activos']).clamp(0, total < 0 ? 0 : total);
    return ConteoActivo(total: total < 0 ? 0 : total, activos: activos);
  }

  static const ConteoActivo vacio = ConteoActivo(total: 0, activos: 0);
}

/// Reservas por estado. Los nombres replican `flow.nom_estado_agenda`:
/// 1 = Reservado, 2 = Cancelado, 3 = Completado.
class ReservasResumen {
  const ReservasResumen({
    required this.total,
    required this.reservado,
    required this.completado,
    required this.cancelado,
  });

  final int total;
  final int reservado;
  final int completado;
  final int cancelado;

  factory ReservasResumen.fromJson(Object? raw) {
    if (raw is! Map) return ReservasResumen.cero;
    return ReservasResumen(
      total: _int(raw['total']),
      reservado: _int(raw['reservado']),
      completado: _int(raw['completado']),
      cancelado: _int(raw['cancelado']),
    );
  }

  static const ReservasResumen cero = ReservasResumen(
    total: 0,
    reservado: 0,
    completado: 0,
    cancelado: 0,
  );
}

/// Un día de la serie del gráfico.
class ReservasDia {
  const ReservasDia({
    required this.fecha,
    required this.total,
    required this.reservadas,
    required this.completadas,
    required this.canceladas,
  });

  final DateTime fecha;
  final int total;
  final int reservadas;
  final int completadas;
  final int canceladas;

  static ReservasDia? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final f = raw['fecha'];
    if (f is! String) return null;
    final fecha = DateTime.tryParse(f);
    if (fecha == null) return null;
    return ReservasDia(
      fecha: DateTime(fecha.year, fecha.month, fecha.day),
      total: _int(raw['total']),
      reservadas: _int(raw['reservadas']),
      completadas: _int(raw['completadas']),
      canceladas: _int(raw['canceladas']),
    );
  }
}

/// Fila del top de servicios por reservas.
class TopServicio {
  const TopServicio({
    required this.idLocalServicio,
    required this.servicio,
    required this.local,
    required this.total,
    required this.reservadas,
    required this.canceladas,
  });

  final int idLocalServicio;
  final String servicio;
  final String local;
  final int total;
  final int reservadas;
  final int canceladas;

  static TopServicio? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return TopServicio(
      idLocalServicio: _int(raw['id_local_servicio']),
      servicio: (raw['servicio'] as String?)?.trim().isNotEmpty == true
          ? (raw['servicio'] as String).trim()
          : 'Servicio',
      local: (raw['local'] as String?)?.trim() ?? '',
      total: _int(raw['total']),
      reservadas: _int(raw['reservadas']),
      canceladas: _int(raw['canceladas']),
    );
  }
}

/// Respuesta completa de `flow.admin_dashboard_entidad`.
class DashboardEntidad {
  const DashboardEntidad({
    required this.dias,
    required this.locales,
    required this.servicios,
    required this.localServicios,
    required this.reservas,
    required this.porDia,
    required this.topServicios,
  });

  /// Ventana de la serie, en días (30 por defecto).
  final int dias;

  final ConteoActivo locales;
  final ConteoActivo servicios;
  final ConteoActivo localServicios;
  final ReservasResumen reservas;

  /// Serie ordenada por fecha; puede venir vacía.
  final List<ReservasDia> porDia;

  final List<TopServicio> topServicios;

  /// Mayor total diario: la escala del gráfico. Nunca 0 (evita dividir por 0 en
  /// el pintado de barras) y nunca menor que 1 para que un día con reservas no
  /// salga al 100 % del alto con un único valor.
  int get maximoDiario {
    var max = 0;
    for (final d in porDia) {
      if (d.total > max) max = d.total;
    }
    return max < 1 ? 1 : max;
  }

  /// Total de la serie. Sirve para comprobar que el gráfico y el resumen
  /// cuentan lo mismo cuando la ventana cubre todas las reservas.
  int get totalSerie {
    var suma = 0;
    for (final d in porDia) {
      suma += d.total;
    }
    return suma;
  }

  factory DashboardEntidad.fromJson(Map<String, dynamic> json) {
    final dias = _int(json['dias']);
    return DashboardEntidad(
      dias: dias > 0 ? dias : 30,
      locales: ConteoActivo.fromJson(json['locales']),
      servicios: ConteoActivo.fromJson(json['servicios']),
      localServicios: ConteoActivo.fromJson(json['local_servicios']),
      reservas: ReservasResumen.fromJson(json['reservas']),
      porDia:
          (json['reservas_por_dia'] as List?)
              ?.map(ReservasDia.fromJson)
              .whereType<ReservasDia>()
              .toList() ??
          const <ReservasDia>[],
      topServicios:
          (json['top_servicios'] as List?)
              ?.map(TopServicio.fromJson)
              .whereType<TopServicio>()
              .toList() ??
          const <TopServicio>[],
    );
  }

  static const DashboardEntidad vacio = DashboardEntidad(
    dias: 30,
    locales: ConteoActivo.vacio,
    servicios: ConteoActivo.vacio,
    localServicios: ConteoActivo.vacio,
    reservas: ReservasResumen.cero,
    porDia: <ReservasDia>[],
    topServicios: <TopServicio>[],
  );
}

int _int(Object? raw) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}
