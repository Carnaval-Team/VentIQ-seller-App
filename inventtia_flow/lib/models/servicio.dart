import 'campo_adicional.dart';
import 'config_precio.dart';

class Servicio {
  final int id;
  final String nombre;
  final String? descripcion;
  final String? foto;
  final DateTime createdAt;
  final List<CampoAdicional> camposAdicionales;
  final bool permiteTercero;
  final ConfigPrecio configPrecio;
  final int? idTipoActividad;
  final String? tipoActividad;

  /// Nombre legible de la fila apuntada por [idTipoActividad]. Llega en el
  /// payload del feed y de `cliente_obtener_servicios` desde la migración
  /// `48_home_feed_categorias_subcategorias.sql`; sin ella se cae al código
  /// embellecido, como antes.
  final String? tipoActividadNombre;

  /// `nom_tipo_actividad_servicio.id_padre` de la fila apuntada por
  /// [idTipoActividad].
  ///
  /// Desde la migración `47_categorias_reales_subcategorias.sql` la taxonomía
  /// tiene dos niveles y el servicio apunta a la HOJA:
  ///
  ///   * `null` → [tipoActividad] ya es una categoría.
  ///   * con valor → [tipoActividad] es una **subcategoría** y su categoría es
  ///     este id.
  ///
  /// Se guarda el id y no el nombre porque el nombre lo resuelve `Taxonomia` con
  /// la lectura del nomenclador que la pantalla ya tiene: así este modelo no
  /// depende de un join extra en cada RPC.
  final int? idPadreTipoActividad;

  /// Si es false, el servicio no se muestra en NINGÚN local ni admite reservas.
  /// Se combina con [Local.activo] y [LocalServicio.activo] en
  /// [LocalServicio.activoEfectivo].
  final bool activo;

  /// Si este servicio se puede **pagar por adelantado** (migración 67).
  ///
  /// Es el interruptor por servicio: la entidad aporta la cuenta que cobra
  /// (`flow.cobro_config`) y aquí se decide qué servicios la usan. Hacen falta
  /// las dos cosas para que el cliente vea la opción.
  final bool cobroAdelantado;

  Servicio({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.foto,
    required this.createdAt,
    List<CampoAdicional>? camposAdicionales,
    this.permiteTercero = false,
    ConfigPrecio? configPrecio,
    this.idTipoActividad,
    this.tipoActividad,
    this.tipoActividadNombre,
    this.idPadreTipoActividad,
    this.activo = true,
    this.cobroAdelantado = false,
  }) : camposAdicionales = camposAdicionales ?? [],
       configPrecio = configPrecio ?? ConfigPrecio();

  factory Servicio.fromJson(Map<String, dynamic> json) => Servicio(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    descripcion: json['descripcion'] as String?,
    foto: json['foto'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.now(),
    camposAdicionales:
        (json['campos_adicionales'] as List?)
            ?.map((e) => CampoAdicional.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    permiteTercero: (json['permite_tercero'] as bool?) ?? false,
    configPrecio: ConfigPrecio.fromJson(
      json['config_precio'] as Map<String, dynamic>?,
    ),
    idTipoActividad: (json['id_tipo_actividad'] as num?)?.toInt(),
    tipoActividad:
        (json['tipo_actividad'] as Map?)?['codigo'] as String? ??
        json['tipo_actividad_codigo'] as String?,
    tipoActividadNombre: _nombreTipoActividadDe(json),
    // Solo llega cuando el payload incluye la fila del nomenclador con
    // `id_padre` (feed del Home y `cliente_obtener_servicios`). Sin él, la
    // pantalla resuelve la jerarquía con `Taxonomia.categoriaDe`.
    idPadreTipoActividad:
        (json['tipo_actividad'] as Map?)?['id_padre'] as int? ??
        (json['id_padre_tipo_actividad'] as num?)?.toInt(),
    // `?? true`: los payloads antiguos (o PostgREST sin la columna) siguen
    // tratando el servicio como publicado en vez de ocultarlo por accidente.
    activo: (json['activo'] as bool?) ?? true,
    // `?? false`: sin la migración 67 (o en payloads que no traen la columna) el
    // servicio NO ofrece pago por adelantado, que es el estado por defecto.
    cobroAdelantado: (json['cobro_adelantado'] as bool?) ?? false,
  );

  /// Nombre legible de la actividad, venga como objeto `tipo_actividad` o como
  /// campo plano. `null` cuando el payload solo trae el código.
  static String? _nombreTipoActividadDe(Map<String, dynamic> json) {
    final objeto = json['tipo_actividad'];
    if (objeto is Map) {
      final nombre = (objeto['nombre'] as String?)?.trim();
      if (nombre != null && nombre.isNotEmpty) return nombre;
    }
    final plano = (json['tipo_actividad_nombre'] as String?)?.trim();
    return (plano == null || plano.isEmpty) ? null : plano;
  }
}

class Local {
  final int id;
  final String nombre;
  final String? descripcion;
  final String? horarioAtencion;

  /// Horario estructurado del local, tal cual lo devuelve la BD:
  /// `{"dias": [1..7], "apertura": "HH:MM", "cierre": "HH:MM"}`.
  ///
  /// Es `null` cuando el admin usó el modo de texto libre. En ese caso la única
  /// fuente es [horarioAtencion] y se interpreta con el parser clásico.
  /// Se guarda crudo (no como [HorarioDetalle]) para no acoplar el modelo a
  /// `utils/` y para tolerar JSON inesperado sin romper el parseo del resto.
  final Map<String, dynamic>? horarioDetalle;
  final String? terminosCondiciones;
  final Map<String, dynamic>? coordenadas;
  final String? direccion;
  final String? pais;
  final String? provincia;
  final String? foto;
  final DateTime createdAt;

  /// Si es false, este local y TODOS sus servicios dejan de mostrarse y de
  /// poder reservarse.
  final bool activo;

  Local({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.horarioAtencion,
    this.horarioDetalle,
    this.terminosCondiciones,
    this.coordenadas,
    this.direccion,
    this.pais,
    this.provincia,
    this.foto,
    required this.createdAt,
    this.activo = true,
  });

  String get ubicacion {
    final parts = [
      provincia,
      pais,
    ].where((v) => v != null && v.isNotEmpty).toList();
    return parts.join(', ');
  }

  factory Local.fromJson(Map<String, dynamic> json) => Local(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    descripcion: json['descripcion'] as String?,
    horarioAtencion: json['horario_atencion'] as String?,
    horarioDetalle: json['horario_detalle'] as Map<String, dynamic>?,
    terminosCondiciones: json['terminos_condiciones'] as String?,
    coordenadas: json['coordenadas'] as Map<String, dynamic>?,
    direccion: json['direccion'] as String?,
    pais: json['pais'] as String?,
    provincia: json['provincia'] as String?,
    foto: json['foto'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : DateTime.now(),
    activo: (json['activo'] as bool?) ?? true,
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

  /// Si es false, esta combinación local-servicio no se ofrece ni se reserva.
  final bool activo;

  /// Modo simplificado: la UI no muestra recursos ni tramos. En BD se traduce en
  /// un recurso oculto y un tramo oculto por turno.
  final bool soloTurnos;

  /// Modo simplificado: se ocultan los tramos, se conservan los recursos. Cada
  /// turno recibe un tramo oculto propio.
  final bool sinTramos;

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
    this.activo = true,
    this.soloTurnos = false,
    this.sinTramos = false,
  });

  bool get esTransporteOmnibus =>
      servicio?.tipoActividad == 'transporte_omnibus';

  /// Réplica Dart de `flow._ls_disponible(id)`.
  ///
  /// Es la ÚNICA definición de "este par es visible y reservable" en la app: la
  /// usan el filtro defensivo del cliente y los chips del admin. Si el servidor
  /// ya filtró, esto no cambia nada; existe para que una fila vieja en caché o
  /// un payload sin los tres campos no enseñe algo que no se puede reservar.
  ///
  /// `local`/`servicio` pueden ser null (payload PostgREST sin joins): en ese
  /// caso se consideran publicados y manda sólo [activo], para no ocultar datos
  /// por una limitación del payload.
  bool get activoEfectivo =>
      activo && (local?.activo ?? true) && (servicio?.activo ?? true);

  /// true si la UI debe ocultar la sección de tramos.
  bool get ocultaTramos => sinTramos || soloTurnos;

  factory LocalServicio.fromJson(Map<String, dynamic> json) {
    // Soporta formato RPC (id_local_servicio, local, servicio)
    // y formato PostgREST (id, app_dat_locales, app_dat_servicios)
    final idRaw = json['id_local_servicio'] ?? json['id'];
    final id = (idRaw as num).toInt();
    final localRaw = json['local'] ?? json['app_dat_locales'];
    final servicioRaw = json['servicio'] ?? json['app_dat_servicios'];
    return LocalServicio(
      id: id,
      idLocal:
          (json['id_local'] as num?)?.toInt() ??
          (localRaw != null
              ? ((localRaw as Map<String, dynamic>)['id'] as num).toInt()
              : 0),
      idServicio:
          (json['id_servicio'] as num?)?.toInt() ??
          (servicioRaw != null
              ? ((servicioRaw as Map<String, dynamic>)['id'] as num).toInt()
              : 0),
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
      activo: (json['activo'] as bool?) ?? true,
      soloTurnos: (json['solo_turnos'] as bool?) ?? false,
      sinTramos: (json['sin_tramos'] as bool?) ?? false,
    );
  }

  LocalServicio copyWith({
    bool? permiteReservaDirecta,
    int? cantidadDefault,
    int? cantidadMaxCapacidad,
    bool? activo,
    bool? soloTurnos,
    bool? sinTramos,
    Local? local,
    Servicio? servicio,
  }) => LocalServicio(
    id: id,
    idLocal: idLocal,
    idServicio: idServicio,
    local: local ?? this.local,
    servicio: servicio ?? this.servicio,
    createdAt: createdAt,
    permiteReservaDirecta: permiteReservaDirecta ?? this.permiteReservaDirecta,
    cantidadDefault: cantidadDefault ?? this.cantidadDefault,
    cantidadMaxCapacidad: cantidadMaxCapacidad ?? this.cantidadMaxCapacidad,
    activo: activo ?? this.activo,
    soloTurnos: soloTurnos ?? this.soloTurnos,
    sinTramos: sinTramos ?? this.sinTramos,
  );
}
