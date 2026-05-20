class VehicleModel {
  final int? id;
  final DateTime? createdAt;
  final String? marca;
  final String? modelo;
  final String? chapa;
  final String? circulacion;
  final String? categoria;
  final String? capacidad;
  final String? image;
  final String? descripcion;
  final String? color;

  // FK a muevete.vehicle_type (igual que solicitudes_transporte)
  final int? idTipoVehiculo;

  // Tipo de equipo/carrocería — FK a app_nom_tipo_equipo
  final int? tipoEquipoId;
  final String? tipoEquipoNombre;      // enriquecido por JOIN
  final String? tipoEquipoAbreviacion; // enriquecido por JOIN

  // Legacy — se mantiene para compatibilidad
  final String? tipoCarroceria;
  final double? capacidadTon;
  final double? capacidadM3;
  final int? anio;
  final int? numEjes;
  final double? longitudM;
  final double? anchoM;
  final double? altoM;
  final bool tieneGps;
  final bool tieneEld;
  final bool seguroVigente;
  final DateTime? seguroVence;
  final DateTime? inspeccionVence;

  VehicleModel({
    this.id,
    this.createdAt,
    this.marca,
    this.modelo,
    this.chapa,
    this.circulacion,
    this.categoria,
    this.capacidad,
    this.image,
    this.descripcion,
    this.color,
    this.idTipoVehiculo,
    this.tipoEquipoId,
    this.tipoEquipoNombre,
    this.tipoEquipoAbreviacion,
    this.tipoCarroceria,
    this.capacidadTon,
    this.capacidadM3,
    this.anio,
    this.numEjes,
    this.longitudM,
    this.anchoM,
    this.altoM,
    this.tieneGps = false,
    this.tieneEld = false,
    this.seguroVigente = false,
    this.seguroVence,
    this.inspeccionVence,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      marca: json['marca'] as String?,
      modelo: json['modelo'] as String?,
      chapa: json['chapa'] as String?,
      circulacion: json['circulacion'] as String?,
      categoria: json['categoria'] as String?,
      capacidad: json['capacidad'] as String?,
      image: json['image'] as String?,
      descripcion: json['descripcion'] as String?,
      color: json['color'] as String?,
      idTipoVehiculo: json['id_tipo_vehiculo'] as int?,
      tipoEquipoId: json['tipo_equipo_id'] as int?,
      tipoEquipoNombre: json['tipo_equipo_nombre'] as String?,
      tipoEquipoAbreviacion: json['tipo_equipo_abreviacion'] as String?,
      tipoCarroceria: json['tipo_carroceria'] as String?,
      capacidadTon: (json['capacidad_ton'] as num?)?.toDouble(),
      capacidadM3: (json['capacidad_m3'] as num?)?.toDouble(),
      anio: json['año'] as int?,
      numEjes: json['num_ejes'] as int?,
      longitudM: (json['longitud_m'] as num?)?.toDouble(),
      anchoM: (json['ancho_m'] as num?)?.toDouble(),
      altoM: (json['alto_m'] as num?)?.toDouble(),
      tieneGps: json['tiene_gps'] as bool? ?? false,
      tieneEld: json['tiene_eld'] as bool? ?? false,
      seguroVigente: json['seguro_vigente'] as bool? ?? false,
      seguroVence: json['seguro_vence'] != null
          ? DateTime.tryParse(json['seguro_vence'] as String)
          : null,
      inspeccionVence: json['inspeccion_vence'] != null
          ? DateTime.tryParse(json['inspeccion_vence'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'marca': marca,
      'modelo': modelo,
      'chapa': chapa,
      'circulacion': circulacion,
      'categoria': categoria,
      'capacidad': capacidad,
      'image': image,
      'descripcion': descripcion,
      'color': color,
      if (idTipoVehiculo != null) 'id_tipo_vehiculo': idTipoVehiculo,
      if (tipoEquipoId != null) 'tipo_equipo_id': tipoEquipoId,
      if (tipoCarroceria != null) 'tipo_carroceria': tipoCarroceria,
      if (capacidadTon != null) 'capacidad_ton': capacidadTon,
      if (capacidadM3 != null) 'capacidad_m3': capacidadM3,
      if (anio != null) 'año': anio,
      if (numEjes != null) 'num_ejes': numEjes,
      if (longitudM != null) 'longitud_m': longitudM,
      if (anchoM != null) 'ancho_m': anchoM,
      if (altoM != null) 'alto_m': altoM,
      'tiene_gps': tieneGps,
      'tiene_eld': tieneEld,
      'seguro_vigente': seguroVigente,
      if (seguroVence != null)
        'seguro_vence': seguroVence!.toIso8601String().split('T').first,
      if (inspeccionVence != null)
        'inspeccion_vence': inspeccionVence!.toIso8601String().split('T').first,
    };
  }

  VehicleModel copyWith({
    int? id,
    DateTime? createdAt,
    String? marca,
    String? modelo,
    String? chapa,
    String? circulacion,
    String? categoria,
    String? capacidad,
    String? image,
    String? descripcion,
    String? color,
    int? idTipoVehiculo,
    int? tipoEquipoId,
    String? tipoEquipoNombre,
    String? tipoEquipoAbreviacion,
    String? tipoCarroceria,
    double? capacidadTon,
    double? capacidadM3,
    int? anio,
    int? numEjes,
    double? longitudM,
    double? anchoM,
    double? altoM,
    bool? tieneGps,
    bool? tieneEld,
    bool? seguroVigente,
    DateTime? seguroVence,
    DateTime? inspeccionVence,
  }) {
    return VehicleModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      chapa: chapa ?? this.chapa,
      circulacion: circulacion ?? this.circulacion,
      categoria: categoria ?? this.categoria,
      capacidad: capacidad ?? this.capacidad,
      image: image ?? this.image,
      descripcion: descripcion ?? this.descripcion,
      color: color ?? this.color,
      idTipoVehiculo: idTipoVehiculo ?? this.idTipoVehiculo,
      tipoEquipoId: tipoEquipoId ?? this.tipoEquipoId,
      tipoEquipoNombre: tipoEquipoNombre ?? this.tipoEquipoNombre,
      tipoEquipoAbreviacion: tipoEquipoAbreviacion ?? this.tipoEquipoAbreviacion,
      tipoCarroceria: tipoCarroceria ?? this.tipoCarroceria,
      capacidadTon: capacidadTon ?? this.capacidadTon,
      capacidadM3: capacidadM3 ?? this.capacidadM3,
      anio: anio ?? this.anio,
      numEjes: numEjes ?? this.numEjes,
      longitudM: longitudM ?? this.longitudM,
      anchoM: anchoM ?? this.anchoM,
      altoM: altoM ?? this.altoM,
      tieneGps: tieneGps ?? this.tieneGps,
      tieneEld: tieneEld ?? this.tieneEld,
      seguroVigente: seguroVigente ?? this.seguroVigente,
      seguroVence: seguroVence ?? this.seguroVence,
      inspeccionVence: inspeccionVence ?? this.inspeccionVence,
    );
  }
}
