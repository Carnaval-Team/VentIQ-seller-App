class DriverModel {
  // ── Existing fields (unchanged) ──────────────────────────────────────────
  final int? id;
  final DateTime? createdAt;
  final String? name;
  final String? email;
  final String? telefono;
  final bool estado;
  final bool? kyc;
  final String? image;
  final int? vehiculo;
  final String? categoria;
  final String? circulacion;
  final String? carnet;
  final String? licencia;
  final bool? revisado;
  final String? motivo;
  final String? uuid;

  // ── New fields ────────────────────────────────────────────────────────────
  // Discriminator: 'conductor_pasajeros' | 'carrier_carga' | 'dispatcher'
  final String? tipoUsuario;
  // FK to dispatcher that registered this carrier (null = independent)
  final int? dispatcherId;
  // Carrier / dispatcher professional fields
  final String? mcNumber;
  final String? dotNumber;
  final String? tipoCarroceria;
  final double? capacidadTon;
  final double? longitudPlataformaM;
  final bool? seguroCargaVigente;
  final String? seguroCargaUrl;
  // Dispatcher company fields
  final String? empresaNombre;
  final String? empresaRut;
  final String? empresaDireccion;

  DriverModel({
    this.id,
    this.createdAt,
    this.name,
    this.email,
    this.telefono,
    this.estado = false,
    this.kyc,
    this.image,
    this.vehiculo,
    this.categoria,
    this.circulacion,
    this.carnet,
    this.licencia,
    this.revisado,
    this.motivo,
    this.uuid,
    this.tipoUsuario,
    this.dispatcherId,
    this.mcNumber,
    this.dotNumber,
    this.tipoCarroceria,
    this.capacidadTon,
    this.longitudPlataformaM,
    this.seguroCargaVigente,
    this.seguroCargaUrl,
    this.empresaNombre,
    this.empresaRut,
    this.empresaDireccion,
  });

  bool get isConductorPasajeros =>
      tipoUsuario == 'conductor_pasajeros' || tipoUsuario == null;
  bool get isCarrierCarga => tipoUsuario == 'carrier_carga';
  bool get isDispatcher => tipoUsuario == 'dispatcher';

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    return DriverModel(
      id: json['id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      name: json['name'] as String?,
      email: json['email'] as String?,
      telefono: json['telefono'] as String?,
      estado: json['estado'] as bool? ?? false,
      kyc: json['kyc'] as bool?,
      image: json['image'] as String?,
      vehiculo: json['vehiculo'] as int?,
      categoria: json['categoria'] as String?,
      circulacion: json['circulacion'] as String?,
      carnet: json['carnet'] as String?,
      licencia: json['licencia'] as String?,
      revisado: json['revisado'] as bool?,
      motivo: json['motivo'] as String?,
      uuid: json['uuid'] as String?,
      tipoUsuario: json['tipo_usuario'] as String?,
      dispatcherId: json['dispatcher_id'] as int?,
      mcNumber: json['mc_number'] as String?,
      dotNumber: json['dot_number'] as String?,
      tipoCarroceria: json['tipo_carroceria'] as String?,
      capacidadTon: json['capacidad_ton'] != null
          ? (json['capacidad_ton'] as num).toDouble()
          : null,
      longitudPlataformaM: json['longitud_plataforma_m'] != null
          ? (json['longitud_plataforma_m'] as num).toDouble()
          : null,
      seguroCargaVigente: json['seguro_carga_vigente'] as bool?,
      seguroCargaUrl: json['seguro_carga_url'] as String?,
      empresaNombre: json['empresa_nombre'] as String?,
      empresaRut: json['empresa_rut'] as String?,
      empresaDireccion: json['empresa_direccion'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'telefono': telefono,
      'estado': estado,
      'kyc': kyc,
      'image': image,
      'vehiculo': vehiculo,
      'categoria': categoria,
      'circulacion': circulacion,
      'carnet': carnet,
      'licencia': licencia,
      'revisado': revisado,
      'motivo': motivo,
      'uuid': uuid,
      if (tipoUsuario != null) 'tipo_usuario': tipoUsuario,
      if (dispatcherId != null) 'dispatcher_id': dispatcherId,
      if (mcNumber != null) 'mc_number': mcNumber,
      if (dotNumber != null) 'dot_number': dotNumber,
      if (tipoCarroceria != null) 'tipo_carroceria': tipoCarroceria,
      if (capacidadTon != null) 'capacidad_ton': capacidadTon,
      if (longitudPlataformaM != null)
        'longitud_plataforma_m': longitudPlataformaM,
      if (seguroCargaVigente != null) 'seguro_carga_vigente': seguroCargaVigente,
      if (seguroCargaUrl != null) 'seguro_carga_url': seguroCargaUrl,
      if (empresaNombre != null) 'empresa_nombre': empresaNombre,
      if (empresaRut != null) 'empresa_rut': empresaRut,
      if (empresaDireccion != null) 'empresa_direccion': empresaDireccion,
    };
  }

  DriverModel copyWith({
    int? id,
    DateTime? createdAt,
    String? name,
    String? email,
    String? telefono,
    bool? estado,
    bool? kyc,
    String? image,
    int? vehiculo,
    String? categoria,
    String? circulacion,
    String? carnet,
    String? licencia,
    bool? revisado,
    String? motivo,
    String? uuid,
    String? tipoUsuario,
    int? dispatcherId,
    String? mcNumber,
    String? dotNumber,
    String? tipoCarroceria,
    double? capacidadTon,
    double? longitudPlataformaM,
    bool? seguroCargaVigente,
    String? seguroCargaUrl,
    String? empresaNombre,
    String? empresaRut,
    String? empresaDireccion,
  }) {
    return DriverModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      name: name ?? this.name,
      email: email ?? this.email,
      telefono: telefono ?? this.telefono,
      estado: estado ?? this.estado,
      kyc: kyc ?? this.kyc,
      image: image ?? this.image,
      vehiculo: vehiculo ?? this.vehiculo,
      categoria: categoria ?? this.categoria,
      circulacion: circulacion ?? this.circulacion,
      carnet: carnet ?? this.carnet,
      licencia: licencia ?? this.licencia,
      revisado: revisado ?? this.revisado,
      motivo: motivo ?? this.motivo,
      uuid: uuid ?? this.uuid,
      tipoUsuario: tipoUsuario ?? this.tipoUsuario,
      dispatcherId: dispatcherId ?? this.dispatcherId,
      mcNumber: mcNumber ?? this.mcNumber,
      dotNumber: dotNumber ?? this.dotNumber,
      tipoCarroceria: tipoCarroceria ?? this.tipoCarroceria,
      capacidadTon: capacidadTon ?? this.capacidadTon,
      longitudPlataformaM: longitudPlataformaM ?? this.longitudPlataformaM,
      seguroCargaVigente: seguroCargaVigente ?? this.seguroCargaVigente,
      seguroCargaUrl: seguroCargaUrl ?? this.seguroCargaUrl,
      empresaNombre: empresaNombre ?? this.empresaNombre,
      empresaRut: empresaRut ?? this.empresaRut,
      empresaDireccion: empresaDireccion ?? this.empresaDireccion,
    );
  }
}
