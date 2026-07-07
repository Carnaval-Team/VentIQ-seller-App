/// Modelo de Mesa para modo restaurante.
///
/// Las mesas están asociadas a una tienda y agrupan órdenes (cuentas separadas
/// de comensales). El estado libre/ocupada se calcula a partir de
/// `ordenesAbiertas` — no se guarda como columna.
class Mesa {
  final int id;
  final int idTienda;
  final String numero;
  final int capacidad;
  final String? zona;
  final String? notas;
  final bool activa;

  /// Órdenes con estado 1 (Pendiente) o 4 (En Proceso) — equivale a comensales activos.
  final int ordenesAbiertas;

  /// Órdenes con estado 2 (Completada) — histórico total.
  final int ordenesCompletadasHistoricas;

  /// Igual a `ordenesAbiertas` (semánticamente "comensales sentados ahora").
  final int comensalesActivos;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  Mesa({
    required this.id,
    required this.idTienda,
    required this.numero,
    required this.capacidad,
    this.zona,
    this.notas,
    this.activa = true,
    this.ordenesAbiertas = 0,
    this.ordenesCompletadasHistoricas = 0,
    this.comensalesActivos = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// `true` si tiene al menos una orden abierta.
  bool get ocupada => ordenesAbiertas > 0;

  /// Etiqueta de estado para UI.
  String get estadoTexto {
    if (!activa) return 'Inactiva';
    if (ordenesAbiertas == 0) return 'Libre';
    if (ordenesAbiertas == 1) return '1 cuenta';
    return '$ordenesAbiertas cuentas';
  }

  factory Mesa.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    DateTime? _toDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    return Mesa(
      id: _toInt(json['id']),
      idTienda: _toInt(json['id_tienda']),
      numero: json['numero']?.toString() ?? '',
      capacidad: _toInt(json['capacidad'], 4),
      zona: json['zona']?.toString(),
      notas: json['notas']?.toString(),
      activa: json['activa'] as bool? ?? true,
      ordenesAbiertas: _toInt(json['ordenes_abiertas']),
      ordenesCompletadasHistoricas:
          _toInt(json['ordenes_completadas_historicas']),
      comensalesActivos:
          _toInt(json['comensales_activos'], _toInt(json['ordenes_abiertas'])),
      createdAt: _toDate(json['created_at']),
      updatedAt: _toDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'id_tienda': idTienda,
        'numero': numero,
        'capacidad': capacidad,
        'zona': zona,
        'notas': notas,
        'activa': activa,
        'ordenes_abiertas': ordenesAbiertas,
        'ordenes_completadas_historicas': ordenesCompletadasHistoricas,
        'comensales_activos': comensalesActivos,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  Mesa copyWith({
    int? id,
    int? idTienda,
    String? numero,
    int? capacidad,
    String? zona,
    String? notas,
    bool? activa,
    int? ordenesAbiertas,
    int? ordenesCompletadasHistoricas,
    int? comensalesActivos,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Mesa(
      id: id ?? this.id,
      idTienda: idTienda ?? this.idTienda,
      numero: numero ?? this.numero,
      capacidad: capacidad ?? this.capacidad,
      zona: zona ?? this.zona,
      notas: notas ?? this.notas,
      activa: activa ?? this.activa,
      ordenesAbiertas: ordenesAbiertas ?? this.ordenesAbiertas,
      ordenesCompletadasHistoricas:
          ordenesCompletadasHistoricas ?? this.ordenesCompletadasHistoricas,
      comensalesActivos: comensalesActivos ?? this.comensalesActivos,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Resumen global de mesas para el header de la pantalla.
class MesasResumen {
  final int total;
  final int ocupadas;
  final int libres;
  final int ordenesPendientesTotal;

  /// Mesa con más comensales activos (puede ser null si no hay).
  final MesaTopComensales? mesaTopComensales;

  MesasResumen({
    required this.total,
    required this.ocupadas,
    required this.libres,
    required this.ordenesPendientesTotal,
    this.mesaTopComensales,
  });

  factory MesasResumen.empty() => MesasResumen(
        total: 0,
        ocupadas: 0,
        libres: 0,
        ordenesPendientesTotal: 0,
      );

  factory MesasResumen.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    MesaTopComensales? top;
    final topRaw = json['mesa_top_comensales'];
    if (topRaw is Map<String, dynamic>) {
      top = MesaTopComensales.fromJson(topRaw);
    }

    return MesasResumen(
      total: _toInt(json['total']),
      ocupadas: _toInt(json['ocupadas']),
      libres: _toInt(json['libres']),
      ordenesPendientesTotal: _toInt(json['ordenes_pendientes_total']),
      mesaTopComensales: top,
    );
  }
}

class MesaTopComensales {
  final int id;
  final String numero;
  final int comensales;

  MesaTopComensales({
    required this.id,
    required this.numero,
    required this.comensales,
  });

  factory MesaTopComensales.fromJson(Map<String, dynamic> json) {
    int _toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return MesaTopComensales(
      id: _toInt(json['id']),
      numero: json['numero']?.toString() ?? '',
      comensales: _toInt(json['comensales']),
    );
  }
}
