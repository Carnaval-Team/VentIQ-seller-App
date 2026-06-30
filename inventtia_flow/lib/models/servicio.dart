import 'campo_adicional.dart';

class Servicio {
  final int id;
  final String nombre;
  final String? descripcion;
  final String? foto;
  final DateTime createdAt;
  final List<CampoAdicional> camposAdicionales;
  final bool permiteTercero;

  Servicio({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.foto,
    required this.createdAt,
    List<CampoAdicional>? camposAdicionales,
    this.permiteTercero = false,
  }) : camposAdicionales = camposAdicionales ?? [];

  factory Servicio.fromJson(Map<String, dynamic> json) => Servicio(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        foto: json['foto'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        camposAdicionales: (json['campos_adicionales'] as List?)
                ?.map((e) =>
                    CampoAdicional.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        permiteTercero: (json['permite_tercero'] as bool?) ?? false,
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
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        descripcion: json['descripcion'] as String?,
        horarioAtencion: json['horario_atencion'] as String?,
        terminosCondiciones: json['terminos_condiciones'] as String?,
        coordenadas: json['coordenadas'] as Map<String, dynamic>?,
        direccion: json['direccion'] as String?,
        pais: json['pais'] as String?,
        provincia: json['provincia'] as String?,
        foto: json['foto'] as String?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
      );
}

class LocalServicio {
  final int id;
  final int idLocal;
  final int idServicio;
  final Local? local;
  final Servicio? servicio;
  final DateTime createdAt;
  final bool permiteReservaDirecta;
  final int cantidadDefault;
  final int cantidadMaxCapacidad;

  LocalServicio({
    required this.id,
    required this.idLocal,
    required this.idServicio,
    this.local,
    this.servicio,
    required this.createdAt,
    this.permiteReservaDirecta = false,
    this.cantidadDefault = 1,
    this.cantidadMaxCapacidad = 1,
  });

  factory LocalServicio.fromJson(Map<String, dynamic> json) {
    // Soporta formato RPC (id_local_servicio, local, servicio)
    // y formato PostgREST (id, app_dat_locales, app_dat_servicios)
    final id = (json['id_local_servicio'] ?? json['id']) as int;
    final localRaw = json['local'] ?? json['app_dat_locales'];
    final servicioRaw = json['servicio'] ?? json['app_dat_servicios'];
    return LocalServicio(
      id: id,
      idLocal: (json['id_local'] as int?) ?? (localRaw != null ? (localRaw as Map<String,dynamic>)['id'] as int : 0),
      idServicio: (json['id_servicio'] as int?) ?? (servicioRaw != null ? (servicioRaw as Map<String,dynamic>)['id'] as int : 0),
      local: localRaw != null
          ? Local.fromJson(localRaw as Map<String, dynamic>)
          : null,
      servicio: servicioRaw != null
          ? Servicio.fromJson(servicioRaw as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      permiteReservaDirecta:
          (json['permite_reserva_directa'] as bool?) ?? false,
      cantidadDefault: (json['cantidad_default'] as num?)?.toInt() ?? 1,
      cantidadMaxCapacidad:
          (json['cantidad_max_capacidad'] as num?)?.toInt() ?? 1,
    );
  }

  LocalServicio copyWith({
    bool? permiteReservaDirecta,
    int? cantidadDefault,
    int? cantidadMaxCapacidad,
  }) =>
      LocalServicio(
        id: id,
        idLocal: idLocal,
        idServicio: idServicio,
        local: local,
        servicio: servicio,
        createdAt: createdAt,
        permiteReservaDirecta:
            permiteReservaDirecta ?? this.permiteReservaDirecta,
        cantidadDefault: cantidadDefault ?? this.cantidadDefault,
        cantidadMaxCapacidad:
            cantidadMaxCapacidad ?? this.cantidadMaxCapacidad,
      );
}
