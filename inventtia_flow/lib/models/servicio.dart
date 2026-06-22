class Servicio {
  final int id;
  final String nombre;
  final String? descripcion;
  final String? foto;
  final DateTime createdAt;

  Servicio({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.foto,
    required this.createdAt,
  });

  factory Servicio.fromJson(Map<String, dynamic> json) => Servicio(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        foto: json['foto'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class Local {
  final int id;
  final String nombre;
  final String? descripcion;
  final String? horarioAtencion;
  final String? terminosCondiciones;
  final Map<String, dynamic>? coordenadas;
  final String? direccion;
  final String? pais;
  final String? provincia;
  final String? foto;
  final DateTime createdAt;

  Local({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.horarioAtencion,
    this.terminosCondiciones,
    this.coordenadas,
    this.direccion,
    this.pais,
    this.provincia,
    this.foto,
    required this.createdAt,
  });

  String get ubicacion {
    final parts = [provincia, pais].where((v) => v != null && v.isNotEmpty).toList();
    return parts.join(', ');
  }

  factory Local.fromJson(Map<String, dynamic> json) => Local(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        horarioAtencion: json['horario_atencion'] as String?,
        terminosCondiciones: json['terminos_condiciones'] as String?,
        coordenadas: json['coordenadas'] as Map<String, dynamic>?,
        direccion: json['direccion'] as String?,
        pais: json['pais'] as String?,
        provincia: json['provincia'] as String?,
        foto: json['foto'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class LocalServicio {
  final int id;
  final int idLocal;
  final int idServicio;
  final Local? local;
  final Servicio? servicio;
  final DateTime createdAt;

  LocalServicio({
    required this.id,
    required this.idLocal,
    required this.idServicio,
    this.local,
    this.servicio,
    required this.createdAt,
  });

  factory LocalServicio.fromJson(Map<String, dynamic> json) => LocalServicio(
        id: json['id'] as int,
        idLocal: json['id_local'] as int,
        idServicio: json['id_servicio'] as int,
        local: json['app_dat_locales'] != null
            ? Local.fromJson(json['app_dat_locales'] as Map<String, dynamic>)
            : null,
        servicio: json['app_dat_servicios'] != null
            ? Servicio.fromJson(json['app_dat_servicios'] as Map<String, dynamic>)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
