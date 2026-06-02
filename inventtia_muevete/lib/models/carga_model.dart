class CargaModel {
  final int id;
  final String shipperId;

  // Tipo de carga — FK a app_nom_tipo_carga
  final int tipoCargaId;
  final String? tipoCargaNombre;      // enriquecido por JOIN
  final String? tipoCargaAbreviacion; // enriquecido por JOIN (e.g. 'FTL', 'LTL')

  // Estado — campo de cache (fuente autoritativa: app_dat_estado_carga)
  final String estado;
  // estados: 'publicada','en_matching','ofertada','aceptada',
  //          'en_transito','entregada','completada','cancelada','disputa','tomada','completada_carrier'

  // Origen
  final String dirOrigen;
  final double latOrigen;
  final double lonOrigen;
  final String? ciudadOrigen;
  final String? estadoOrigen;
  final String? paisOrigen;
  final String? nombreUbicacionOrigen;
  final String? cpOrigen;
  final String? contactoOrigenNombre;
  final String? contactoOrigenTel;

  // Destino
  final String dirDestino;
  final double latDestino;
  final double lonDestino;
  final String? ciudadDestino;
  final String? estadoDestino;
  final String? paisDestino;
  final String? nombreUbicacionDestino;
  final String? cpDestino;
  final String? contactoDestinoNombre;
  final String? contactoDestinoTel;

  // Mercancía
  final String? descripcion;

  // Tipo de mercancía — FK a app_nom_tipo_mercancia
  final int? tipoMercanciaId;
  final String? tipoMercanciaNombre;      // enriquecido por JOIN
  final String? tipoMercanciaCodigo;      // enriquecido por JOIN (ej: 'DRY_GOODS')
  final String? tipoMercanciaNmfc;        // código NMFC, si aplica

  // Commodity — FK a app_nom_commodity
  final int? commodityNomId;
  final String? commodityNomNombre;       // enriquecido por JOIN
  final String? commodityNomCodigo;       // enriquecido por JOIN

  final double? pesoKg;
  final double? volumenM3;
  final double? longitudM;
  final double? anchoM;
  final double? altoM;
  final double? valorDeclarado;
  final bool requiereRefrigeracion;
  final double? temperaturaMin;
  final double? temperaturaMax;
  final bool requiereSeguro;
  final String? instrucciones;

  // Opciones de manejo/equipo adicional — M:N con app_nom_equipo_manejo_carga
  final List<int> opcionesEquipoManejo;          // IDs de la tabla pivot
  final List<String> opcionesEquipoManejoNombres; // enriquecido por JOIN
  final List<String> opcionesEquipoManejoCodigos; // enriquecido por JOIN

  // Tipo de equipo — FK a app_nom_tipo_equipo (compartido con vehiculos)
  final int? tipoEquipoId;
  final String? tipoEquipoNombre;      // enriquecido por JOIN
  final String? tipoEquipoAbreviacion; // enriquecido por JOIN

  // Tipo de vehículo requerido — FK a muevete.vehicle_type
  final int? idTipoVehiculo;

  // Fechas
  final DateTime? fechaRecogida;
  final DateTime? fechaEntrega;
  final String? ventanaRecogidaDesde;
  final String? ventanaRecogidaHasta;
  final String? ventanaEntregaDesde;
  final String? ventanaEntregaHasta;

  // Precio
  final double? precioOfertado;
  final double? precioFinal;
  final String moneda;

  // Comercial
  final List<String> numerosReferencia;

  // Visibilidad
  final bool destacada;
  final DateTime? destacadaHasta;
  final DateTime? exclusivaHasta;
  final bool esPrivada;
  final int? horasAnticipacionPublica;

  // Distancia
  final double? distanciaKm;
  final double? distanciaMillas;

  // LTL
  final bool esLtl;
  final double? ltlEspacioOcupado;

  // Recurrencia
  final bool esRecurrente;

  // Carrier asignado
  final int? carrierDriverId;
  final String? carrierUuid;     // UUID directo del carrier (asignado por shipper)
  final int? ofertaAceptadaId;

  // Tracking
  final double? ultimaLat;
  final double? ultimaLon;
  final DateTime? ultimaUbicacionAt;

  // Prioridad asignada por el shipper
  final String prioridad; // 'normal' | 'alta' | 'urgente'

  // Metadata
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  // Peso + horas
  final String unidadPeso;   // 'kg' | 'tonelada'
  final double? horasCarga;
  final double? horasDescarga;

  // Datos enriquecidos (JOIN)
  final String? shipperNombre;
  final String? carrierNombre;
  final int? ofertasCount;

  const CargaModel({
    required this.id,
    required this.shipperId,
    required this.tipoCargaId,
    this.tipoCargaNombre,
    this.tipoCargaAbreviacion,
    required this.estado,
    required this.dirOrigen,
    required this.latOrigen,
    required this.lonOrigen,
    this.ciudadOrigen,
    this.estadoOrigen,
    this.paisOrigen,
    required this.dirDestino,
    required this.latDestino,
    required this.lonDestino,
    this.ciudadDestino,
    this.estadoDestino,
    this.paisDestino,
    this.descripcion,
    this.tipoMercanciaId,
    this.tipoMercanciaNombre,
    this.tipoMercanciaCodigo,
    this.tipoMercanciaNmfc,
    this.commodityNomId,
    this.commodityNomNombre,
    this.commodityNomCodigo,
    this.pesoKg,
    this.volumenM3,
    this.longitudM,
    this.anchoM,
    this.altoM,
    this.valorDeclarado,
    this.requiereRefrigeracion = false,
    this.temperaturaMin,
    this.temperaturaMax,
    this.requiereSeguro = false,
    this.instrucciones,
    this.nombreUbicacionOrigen,
    this.cpOrigen,
    this.contactoOrigenNombre,
    this.contactoOrigenTel,
    this.nombreUbicacionDestino,
    this.cpDestino,
    this.contactoDestinoNombre,
    this.contactoDestinoTel,
    this.opcionesEquipoManejo = const [],
    this.opcionesEquipoManejoNombres = const [],
    this.opcionesEquipoManejoCodigos = const [],
    this.numerosReferencia = const [],
    this.tipoEquipoId,
    this.tipoEquipoNombre,
    this.tipoEquipoAbreviacion,
    this.idTipoVehiculo,
    this.fechaRecogida,
    this.fechaEntrega,
    this.ventanaRecogidaDesde,
    this.ventanaRecogidaHasta,
    this.ventanaEntregaDesde,
    this.ventanaEntregaHasta,
    this.precioOfertado,
    this.precioFinal,
    this.moneda = 'USD',
    this.destacada = false,
    this.destacadaHasta,
    this.exclusivaHasta,
    this.esPrivada = false,
    this.horasAnticipacionPublica,
    this.distanciaKm,
    this.distanciaMillas,
    this.esLtl = false,
    this.ltlEspacioOcupado,
    this.esRecurrente = false,
    this.carrierDriverId,
    this.carrierUuid,
    this.ofertaAceptadaId,
    this.ultimaLat,
    this.ultimaLon,
    this.ultimaUbicacionAt,
    required this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.unidadPeso = 'kg',
    this.horasCarga,
    this.horasDescarga,
    this.shipperNombre,
    this.carrierNombre,
    this.ofertasCount,
    this.prioridad = 'normal',
  });

  factory CargaModel.fromJson(Map<String, dynamic> json) {
    return CargaModel(
      id: json['id'] as int,
      shipperId: json['shipper_id'] as String,
      tipoCargaId: json['tipo_carga_id'] as int? ?? 1,
      tipoCargaNombre: json['tipo_carga_nombre'] as String?,
      tipoCargaAbreviacion: json['tipo_carga_abreviacion'] as String?,
      estado: (json['estado_actual'] ?? json['estado']) as String? ?? 'publicada',
      dirOrigen: json['dir_origen'] as String? ?? '',
      latOrigen: (json['lat_origen'] as num?)?.toDouble() ?? 0,
      lonOrigen: (json['lon_origen'] as num?)?.toDouble() ?? 0,
      ciudadOrigen: json['ciudad_origen'] as String?,
      estadoOrigen: json['estado_origen'] as String?,
      paisOrigen: json['pais_origen'] as String?,
      dirDestino: json['dir_destino'] as String? ?? '',
      latDestino: (json['lat_destino'] as num?)?.toDouble() ?? 0,
      lonDestino: (json['lon_destino'] as num?)?.toDouble() ?? 0,
      ciudadDestino: json['ciudad_destino'] as String?,
      estadoDestino: json['estado_destino'] as String?,
      paisDestino: json['pais_destino'] as String?,
      descripcion: json['descripcion'] as String?,
      tipoMercanciaId: json['tipo_mercancia_id'] as int?,
      tipoMercanciaNombre: json['tipo_mercancia_nombre'] as String?,
      tipoMercanciaCodigo: json['tipo_mercancia_codigo'] as String?,
      tipoMercanciaNmfc: json['tipo_mercancia_nmfc'] as String?,
      commodityNomId: json['commodity_nom_id'] as int?,
      commodityNomNombre: json['commodity_nom_nombre'] as String?,
      commodityNomCodigo: json['commodity_nom_codigo'] as String?,
      pesoKg: (json['peso_kg'] as num?)?.toDouble(),
      volumenM3: (json['volumen_m3'] as num?)?.toDouble(),
      longitudM: (json['longitud_m'] as num?)?.toDouble(),
      anchoM: (json['ancho_m'] as num?)?.toDouble(),
      altoM: (json['alto_m'] as num?)?.toDouble(),
      valorDeclarado: (json['valor_declarado'] as num?)?.toDouble(),
      requiereRefrigeracion:
          json['requiere_refrigeracion'] as bool? ?? false,
      temperaturaMin: (json['temperatura_min'] as num?)?.toDouble(),
      temperaturaMax: (json['temperatura_max'] as num?)?.toDouble(),
      requiereSeguro: json['requiere_seguro'] as bool? ?? false,
      instrucciones: json['instrucciones'] as String?,
      nombreUbicacionOrigen: json['nombre_ubicacion_origen'] as String?,
      cpOrigen: json['cp_origen'] as String?,
      contactoOrigenNombre: json['contacto_origen_nombre'] as String?,
      contactoOrigenTel: json['contacto_origen_tel'] as String?,
      nombreUbicacionDestino: json['nombre_ubicacion_destino'] as String?,
      cpDestino: json['cp_destino'] as String?,
      contactoDestinoNombre: json['contacto_destino_nombre'] as String?,
      contactoDestinoTel: json['contacto_destino_tel'] as String?,
      opcionesEquipoManejo: (json['opciones_equipo_manejo_ids'] as List<dynamic>?)?.cast<int>() ?? [],
      opcionesEquipoManejoNombres: (json['opciones_equipo_manejo_nombres'] as List<dynamic>?)?.cast<String>() ?? [],
      opcionesEquipoManejoCodigos: (json['opciones_equipo_manejo_codigos'] as List<dynamic>?)?.cast<String>() ?? [],
      numerosReferencia: (json['numeros_referencia'] as List<dynamic>?)?.cast<String>() ?? [],
      tipoEquipoId: json['tipo_equipo_id'] as int?,
      tipoEquipoNombre: json['tipo_equipo_nombre'] as String?,
      tipoEquipoAbreviacion: json['tipo_equipo_abreviacion'] as String?,
      idTipoVehiculo: json['id_tipo_vehiculo'] as int?,
      fechaRecogida: json['fecha_recogida'] != null
          ? DateTime.tryParse(json['fecha_recogida'] as String)
          : null,
      fechaEntrega: json['fecha_entrega'] != null
          ? DateTime.tryParse(json['fecha_entrega'] as String)
          : null,
      ventanaRecogidaDesde: json['ventana_recogida_desde'] as String?,
      ventanaRecogidaHasta: json['ventana_recogida_hasta'] as String?,
      ventanaEntregaDesde: json['ventana_entrega_desde'] as String?,
      ventanaEntregaHasta: json['ventana_entrega_hasta'] as String?,
      precioOfertado: (json['precio_ofertado'] as num?)?.toDouble(),
      precioFinal: (json['precio_final'] as num?)?.toDouble(),
      moneda: json['moneda'] as String? ?? 'USD',
      destacada: json['destacada'] as bool? ?? false,
      destacadaHasta: json['destacada_hasta'] != null
          ? DateTime.tryParse(json['destacada_hasta'] as String)
          : null,
      exclusivaHasta: json['exclusiva_hasta'] != null
          ? DateTime.tryParse(json['exclusiva_hasta'] as String)
          : null,
      esPrivada: json['es_privada'] as bool? ?? false,
      horasAnticipacionPublica: json['horas_anticipacion_publica'] as int?,
      distanciaKm: (json['distancia_km'] as num?)?.toDouble(),
      distanciaMillas: (json['distancia_millas'] as num?)?.toDouble(),
      esLtl: json['es_ltl'] as bool? ?? false,
      ltlEspacioOcupado: (json['ltl_espacio_ocupado'] as num?)?.toDouble(),
      esRecurrente: json['es_recurrente'] as bool? ?? false,
      carrierDriverId: json['carrier_driver_id'] as int?,
      carrierUuid: json['carrier_uuid'] as String?,
      ofertaAceptadaId: json['oferta_aceptada_id'] as int?,
      ultimaLat: (json['ultima_lat'] as num?)?.toDouble(),
      ultimaLon: (json['ultima_lon'] as num?)?.toDouble(),
      ultimaUbicacionAt: json['ultima_ubicacion_at'] != null
          ? DateTime.tryParse(json['ultima_ubicacion_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      unidadPeso: json['unidad_peso'] as String? ?? 'kg',
      horasCarga: (json['horas_carga'] as num?)?.toDouble(),
      horasDescarga: (json['horas_descarga'] as num?)?.toDouble(),
      shipperNombre: json['shipper_nombre'] as String?,
      carrierNombre: json['carrier_nombre'] as String?,
      ofertasCount: json['ofertas_count'] as int?,
      prioridad: json['prioridad'] as String? ?? 'normal',
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'shipper_id': shipperId,
      'tipo_carga_id': tipoCargaId,
      'dir_origen': dirOrigen,
      'lat_origen': latOrigen,
      'lon_origen': lonOrigen,
      if (ciudadOrigen != null) 'ciudad_origen': ciudadOrigen,
      if (estadoOrigen != null) 'estado_origen': estadoOrigen,
      if (paisOrigen != null) 'pais_origen': paisOrigen,
      'dir_destino': dirDestino,
      'lat_destino': latDestino,
      'lon_destino': lonDestino,
      if (ciudadDestino != null) 'ciudad_destino': ciudadDestino,
      if (estadoDestino != null) 'estado_destino': estadoDestino,
      if (paisDestino != null) 'pais_destino': paisDestino,
      if (descripcion != null) 'descripcion': descripcion,
      if (tipoMercanciaId != null) 'tipo_mercancia_id': tipoMercanciaId,
      if (commodityNomId != null) 'commodity_nom_id': commodityNomId,
      if (pesoKg != null) 'peso_kg': pesoKg,
      if (volumenM3 != null) 'volumen_m3': volumenM3,
      if (longitudM != null) 'longitud_m': longitudM,
      if (anchoM != null) 'ancho_m': anchoM,
      if (altoM != null) 'alto_m': altoM,
      if (valorDeclarado != null) 'valor_declarado': valorDeclarado,
      'requiere_refrigeracion': requiereRefrigeracion,
      if (temperaturaMin != null) 'temperatura_min': temperaturaMin,
      if (temperaturaMax != null) 'temperatura_max': temperaturaMax,
      'requiere_seguro': requiereSeguro,
      if (instrucciones != null) 'instrucciones': instrucciones,
      if (nombreUbicacionOrigen != null) 'nombre_ubicacion_origen': nombreUbicacionOrigen,
      if (cpOrigen != null) 'cp_origen': cpOrigen,
      if (contactoOrigenNombre != null) 'contacto_origen_nombre': contactoOrigenNombre,
      if (contactoOrigenTel != null) 'contacto_origen_tel': contactoOrigenTel,
      if (nombreUbicacionDestino != null) 'nombre_ubicacion_destino': nombreUbicacionDestino,
      if (cpDestino != null) 'cp_destino': cpDestino,
      if (contactoDestinoNombre != null) 'contacto_destino_nombre': contactoDestinoNombre,
      if (contactoDestinoTel != null) 'contacto_destino_tel': contactoDestinoTel,
      // opcionesEquipoManejo se inserta en la tabla pivot cargas_equipo_manejo — NO va aquí
      if (numerosReferencia.isNotEmpty) 'numeros_referencia': numerosReferencia,
      'es_privada': esPrivada,
      if (horasAnticipacionPublica != null) 'horas_anticipacion_publica': horasAnticipacionPublica,
      if (tipoEquipoId != null) 'tipo_equipo_id': tipoEquipoId,
      if (idTipoVehiculo != null) 'id_tipo_vehiculo': idTipoVehiculo,
      if (fechaRecogida != null)
        'fecha_recogida': fechaRecogida!.toIso8601String().split('T').first,
      if (fechaEntrega != null)
        'fecha_entrega': fechaEntrega!.toIso8601String().split('T').first,
      if (ventanaRecogidaDesde != null)
        'ventana_recogida_desde': ventanaRecogidaDesde,
      if (ventanaRecogidaHasta != null)
        'ventana_recogida_hasta': ventanaRecogidaHasta,
      if (ventanaEntregaDesde != null)
        'ventana_entrega_desde': ventanaEntregaDesde,
      if (ventanaEntregaHasta != null)
        'ventana_entrega_hasta': ventanaEntregaHasta,
      if (precioOfertado != null) 'precio_ofertado': precioOfertado,
      'moneda': moneda,
      'destacada': destacada,
      'es_ltl': esLtl,
      'es_recurrente': esRecurrente,
      'unidad_peso': unidadPeso,
      if (horasCarga != null) 'horas_carga': horasCarga,
      if (horasDescarga != null) 'horas_descarga': horasDescarga,
      if (distanciaKm != null) 'distancia_km': distanciaKm,
      'prioridad': prioridad,
    };
  }

  String get estadoLabel {
    const labels = {
      'publicada':            'Publicada',
      'en_matching':          'En Matching',
      'ofertada':             'Con Ofertas',
      'aceptada':             'Aceptada',
      'tomada':               'Tomada',
      'en_transito':          'En Tránsito',
      'completada_carrier':   'Completada (Carrier)',
      'entregada':            'Entregada',
      'completada':           'Completada',
      'cancelada':            'Cancelada',
    };
    return labels[estado] ?? estado;
  }

  String get tipoLabel => tipoCargaAbreviacion ?? tipoCargaNombre ?? 'FTL';

  /// Compatibilidad retroactiva — devuelve la abreviación en minúsculas ('ftl'/'ltl')
  String get tipo => (tipoCargaAbreviacion ?? 'FTL').toLowerCase();

  /// Compatibilidad retroactiva — devuelve el nombre del tipo de equipo
  String? get tipoEquipo => tipoEquipoNombre ?? tipoEquipoAbreviacion;

  /// Compatibilidad retroactiva — devuelve el nombre del tipo de mercancía
  String? get tipoMercancia => tipoMercanciaNombre;

  /// Compatibilidad retroactiva — devuelve el nombre del commodity
  String? get commodityNombre => commodityNomNombre;

  /// Compatibilidad retroactiva — devuelve los códigos de opciones de manejo
  List<String> get opcionesEquipo => opcionesEquipoManejoCodigos;

  /// Texto para UI: tipo de mercancía con NMFC si aplica
  String? get tipoMercanciaDisplay {
    final nombre = tipoMercanciaNombre;
    if (nombre == null) return null;
    final nmfc = tipoMercanciaNmfc;
    if (nmfc != null && nmfc.isNotEmpty) {
      return '$nombre (NMFC: $nmfc)';
    }
    return nombre;
  }

  /// Texto para UI: tipo de equipo con abreviación si aplica
  String? get tipoEquipoDisplay {
    final nombre = tipoEquipoNombre;
    final abrev = tipoEquipoAbreviacion;
    if (nombre != null && abrev != null) {
      return '$nombre (${abrev.toUpperCase()})';
    }
    return nombre ?? abrev?.toUpperCase();
  }

  /// Texto para UI: opciones de manejo (prefiere nombres del nomenclador)
  String get opcionesEquipoDisplay => opcionesEquipoManejoNombres.isNotEmpty
      ? opcionesEquipoManejoNombres.join(', ')
      : opcionesEquipoManejoCodigos.join(', ');

  /// Medidas L × A × H en metros
  String? get medidasDisplay {
    if (longitudM == null && anchoM == null && altoM == null) return null;
    String part(double? v) =>
        v != null ? '${v.toStringAsFixed(2)} m' : '—';
    return '${part(longitudM)} × ${part(anchoM)} × ${part(altoM)}';
  }

  /// Ventana horaria de recogida (horario de carga)
  String? get ventanaRecogidaDisplay {
    final desde = ventanaRecogidaDesde;
    final hasta = ventanaRecogidaHasta;
    if (desde == null && hasta == null) return null;
    if (desde != null && hasta != null) return '$desde – $hasta';
    return desde ?? hasta;
  }

  /// Ventana horaria de entrega (horario de descarga)
  String? get ventanaEntregaDisplay {
    final desde = ventanaEntregaDesde;
    final hasta = ventanaEntregaHasta;
    if (desde == null && hasta == null) return null;
    if (desde != null && hasta != null) return '$desde – $hasta';
    return desde ?? hasta;
  }

  String get prioridadLabel {
    const labels = {'normal': 'Normal', 'alta': 'Alta', 'urgente': 'Urgente'};
    return labels[prioridad] ?? prioridad;
  }

  String get rutaCorta {
    final origen = ciudadOrigen ?? dirOrigen;
    final destino = ciudadDestino ?? dirDestino;
    return '$origen → $destino';
  }
}
