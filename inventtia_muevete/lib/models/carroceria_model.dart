class CarroceriaModel {
  final int? id;
  final int driverId;
  final String? marca;
  final String? modelo;
  final String? matricula;
  final String tipoCarroceria;
  final double? capacidadTon;
  final double? longitudM;
  final bool seguroVigente;
  final DateTime? seguroVence;
  final String? seguroUrl;
  final String? licCirculacionFrenteUrl;
  final String? licCirculacionDorsoUrl;
  final String? licOperativaFrenteUrl;
  final String? licOperativaDorsoUrl;
  final String? vehiclePhotoUrl;  // Foto opcional del vehículo
  final bool activo;
  final DateTime? createdAt;

  const CarroceriaModel({
    this.id,
    required this.driverId,
    this.marca,
    this.modelo,
    this.matricula,
    required this.tipoCarroceria,
    this.capacidadTon,
    this.longitudM,
    this.seguroVigente = false,
    this.seguroVence,
    this.seguroUrl,
    this.licCirculacionFrenteUrl,
    this.licCirculacionDorsoUrl,
    this.licOperativaFrenteUrl,
    this.licOperativaDorsoUrl,
    this.vehiclePhotoUrl,  // Foto opcional del vehículo
    this.activo = true,
    this.createdAt,
  });

  factory CarroceriaModel.fromJson(Map<String, dynamic> json) {
    return CarroceriaModel(
      id: json['id'] as int?,
      driverId: json['driver_id'] as int,
      marca: json['marca'] as String?,
      modelo: json['modelo'] as String?,
      matricula: json['matricula'] as String?,
      tipoCarroceria: json['tipo_carroceria'] as String,
      capacidadTon: json['capacidad_ton'] != null
          ? (json['capacidad_ton'] as num).toDouble()
          : null,
      longitudM: json['longitud_m'] != null
          ? (json['longitud_m'] as num).toDouble()
          : null,
      seguroVigente: json['seguro_vigente'] as bool? ?? false,
      seguroVence: json['seguro_vence'] != null
          ? DateTime.tryParse(json['seguro_vence'] as String)
          : null,
      seguroUrl: json['seguro_url'] as String?,
      licCirculacionFrenteUrl: json['lic_circulacion_frente_url'] as String?,
      licCirculacionDorsoUrl: json['lic_circulacion_dorso_url'] as String?,
      licOperativaFrenteUrl: json['lic_operativa_frente_url'] as String?,
      licOperativaDorsoUrl: json['lic_operativa_dorso_url'] as String?,
      vehiclePhotoUrl: json['vehicle_photo_url'] as String?,  // Foto opcional del vehículo
      activo: json['activo'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'driver_id': driverId,
        'tipo_carroceria': tipoCarroceria,
        if (marca != null && marca!.isNotEmpty) 'marca': marca,
        if (modelo != null && modelo!.isNotEmpty) 'modelo': modelo,
        if (matricula != null && matricula!.isNotEmpty) 'matricula': matricula,
        if (capacidadTon != null) 'capacidad_ton': capacidadTon,
        if (longitudM != null) 'longitud_m': longitudM,
        'seguro_vigente': seguroVigente,
        if (seguroVence != null)
          'seguro_vence': seguroVence!.toIso8601String().substring(0, 10),
        if (seguroUrl != null) 'seguro_url': seguroUrl,
        if (licCirculacionFrenteUrl != null && licCirculacionFrenteUrl!.isNotEmpty)
          'lic_circulacion_frente_url': licCirculacionFrenteUrl,
        if (licCirculacionDorsoUrl != null && licCirculacionDorsoUrl!.isNotEmpty)
          'lic_circulacion_dorso_url': licCirculacionDorsoUrl,
        if (licOperativaFrenteUrl != null && licOperativaFrenteUrl!.isNotEmpty)
          'lic_operativa_frente_url': licOperativaFrenteUrl,
        if (licOperativaDorsoUrl != null && licOperativaDorsoUrl!.isNotEmpty)
          'lic_operativa_dorso_url': licOperativaDorsoUrl,
        if (vehiclePhotoUrl != null && vehiclePhotoUrl!.isNotEmpty)
          'vehicle_photo_url': vehiclePhotoUrl,
        'activo': activo,
      };

  CarroceriaModel copyWith({
    int? id,
    int? driverId,
    String? marca,
    String? modelo,
    String? matricula,
    String? tipoCarroceria,
    double? capacidadTon,
    double? longitudM,
    bool? seguroVigente,
    DateTime? seguroVence,
    String? seguroUrl,
    String? licCirculacionFrenteUrl,
    String? licCirculacionDorsoUrl,
    String? licOperativaFrenteUrl,
    String? licOperativaDorsoUrl,
    String? vehiclePhotoUrl,
    bool? activo,
    DateTime? createdAt,
  }) {
    return CarroceriaModel(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      matricula: matricula ?? this.matricula,
      tipoCarroceria: tipoCarroceria ?? this.tipoCarroceria,
      capacidadTon: capacidadTon ?? this.capacidadTon,
      longitudM: longitudM ?? this.longitudM,
      seguroVigente: seguroVigente ?? this.seguroVigente,
      seguroVence: seguroVence ?? this.seguroVence,
      seguroUrl: seguroUrl ?? this.seguroUrl,
      licCirculacionFrenteUrl:
          licCirculacionFrenteUrl ?? this.licCirculacionFrenteUrl,
      licCirculacionDorsoUrl:
          licCirculacionDorsoUrl ?? this.licCirculacionDorsoUrl,
      licOperativaFrenteUrl:
          licOperativaFrenteUrl ?? this.licOperativaFrenteUrl,
      licOperativaDorsoUrl: licOperativaDorsoUrl ?? this.licOperativaDorsoUrl,
      vehiclePhotoUrl: vehiclePhotoUrl ?? this.vehiclePhotoUrl,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
