import 'entidad.dart';
import 'servicio.dart';

class EstadoAgenda {
  final int id;
  final String nombre;
  final String? descripcion;

  EstadoAgenda({required this.id, required this.nombre, this.descripcion});

  factory EstadoAgenda.fromJson(Map<String, dynamic> json) => EstadoAgenda(
    id: (json['id'] as num).toInt(),
    nombre: json['nombre'] as String,
    descripcion: json['descripcion'] as String?,
  );

  bool get esReservado => nombre.toLowerCase() == 'reservado';
  bool get esCancelado => nombre.toLowerCase() == 'cancelado';
  bool get esCompletado => nombre.toLowerCase() == 'completado';
}

class ClientePerfil {
  final int? id;
  final String? uuidUsuario;
  final String? nombre;
  final String? apellidos;
  final String? ci;
  final String? telefono;

  ClientePerfil({
    this.id,
    this.uuidUsuario,
    this.nombre,
    this.apellidos,
    this.ci,
    this.telefono,
  });

  String get nombreCompleto => '${nombre ?? ''} ${apellidos ?? ''}'.trim();

  factory ClientePerfil.fromJson(Map<String, dynamic> json) => ClientePerfil(
    id: (json['id'] as num?)?.toInt(),
    uuidUsuario: json['uuid_usuario'] as String?,
    nombre: json['nombre'] as String?,
    apellidos: json['apellidos'] as String?,
    ci: json['ci'] as String?,
    telefono: json['telefono'] as String?,
  );
}

class Agenda {
  final int id;
  final String? uuidUsuario;
  final int idLocalServicio;
  final int? idEstado;
  final DateTime fechaHoraReserva;
  final DateTime? fechaHoraAtencion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final EstadoAgenda? estado;
  final LocalServicio? localServicio;
  final Entidad? entidad;
  final ClientePerfil? cliente;
  final int cantidad;
  final Map<String, dynamic>? datosAdicionales;
  final String? reservadoPor;
  final double? precioTotal;
  final String? moneda;
  final int? idTurno;
  final String? turnoNombre;
  final String? recursoNombre;
  final String? idViaje;
  final String? tipoTrayecto;

  /// Motivo que escribió quien canceló la reserva (migración 61).
  ///
  /// **Nullable** a propósito: las reservas canceladas antes de esa migración
  /// (y las que no están canceladas) no tienen motivo y las tarjetas deben
  /// seguir funcionando sin pintar nada.
  final String? motivoCancelacion;

  /// Rol de quien canceló: `'cliente' | 'admin' | 'staff' | 'sistema'`
  /// (`agenda.cancelado_por_rol`). Null en reservas sin cancelar y en las
  /// canceladas antes de la migración 61.
  final String? canceladoPorRol;

  /// Estado del **pago por adelantado** (migración 62):
  /// `'pendiente' | 'reportado' | 'verificado' | 'rechazado' | 'expirado'`.
  ///
  /// Null = esta reserva no pide pago por adelantado (es lo normal: el pago es
  /// opcional y solo aparece si el admin lo activó para la entidad).
  final String? pagoEstado;

  /// Importe que se cobra por adelantado y su moneda (`agenda.pago_monto`,
  /// `agenda.pago_moneda`). Null si no hay pago.
  final double? pagoMonto;
  final String? pagoMoneda;

  Agenda({
    required this.id,
    this.uuidUsuario,
    required this.idLocalServicio,
    this.idEstado,
    required this.fechaHoraReserva,
    this.fechaHoraAtencion,
    required this.createdAt,
    required this.updatedAt,
    this.estado,
    this.localServicio,
    this.entidad,
    this.cliente,
    this.cantidad = 1,
    this.datosAdicionales,
    this.reservadoPor,
    this.precioTotal,
    this.moneda,
    this.idTurno,
    this.turnoNombre,
    this.recursoNombre,
    this.idViaje,
    this.tipoTrayecto,
    this.motivoCancelacion,
    this.canceladoPorRol,
    this.pagoEstado,
    this.pagoMonto,
    this.pagoMoneda,
  });

  /// True si la reserva la hizo el usuario [uuid] para un tercero (titular ≠ quien reservó).
  bool esParaTercero(String uuid) =>
      reservadoPor == uuid && uuidUsuario != null && uuidUsuario != uuid;

  factory Agenda.fromJson(Map<String, dynamic> json) {
    // Soporta dos formatos:
    // 1. RPC admin: local/servicio/entidad/cliente como objetos planos al nivel raíz
    // 2. RPC cliente / PostgREST: local_servicio anidado + local/servicio planos
    LocalServicio? ls;
    if (json['local_servicio'] != null) {
      final lsJson = Map<String, dynamic>.from(json['local_servicio'] as Map);
      if (json['local'] != null) lsJson['local'] = json['local'];
      if (json['servicio'] != null) lsJson['servicio'] = json['servicio'];
      ls = LocalServicio.fromJson(lsJson);
    } else if (json['local'] != null || json['servicio'] != null) {
      ls = LocalServicio.fromJson(json);
    }

    // Entidad dueña del local (disponible en el RPC cliente).
    Entidad? entidad;
    if (json['entidad'] != null) {
      entidad = Entidad.fromJson(json['entidad'] as Map<String, dynamic>);
    }

    // Turno reservado (recursos). Bloque 'turno' = { id, nombre, recurso:{...} }.
    String? turnoNombre;
    String? recursoNombre;
    final turnoRaw = json['turno'];
    if (turnoRaw is Map) {
      turnoNombre = turnoRaw['nombre'] as String?;
      final recursoRaw = turnoRaw['recurso'];
      if (recursoRaw is Map) recursoNombre = recursoRaw['nombre'] as String?;
    }

    return Agenda(
      id: (json['id'] as num).toInt(),
      uuidUsuario: json['uuid_usuario'] as String?,
      idLocalServicio: (json['id_local_servicio'] as num).toInt(),
      idEstado: (json['id_estado'] as num?)?.toInt(),
      fechaHoraReserva: DateTime.parse(json['fecha_hora_reserva'] as String),
      fechaHoraAtencion: json['fecha_hora_atencion'] != null
          ? DateTime.parse(json['fecha_hora_atencion'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      estado: (json['estado'] ?? json['nom_estado_agenda']) != null
          ? EstadoAgenda.fromJson(
              (json['estado'] ?? json['nom_estado_agenda'])
                  as Map<String, dynamic>,
            )
          : null,
      localServicio: ls,
      entidad: entidad,
      cliente: json['cliente'] != null
          ? ClientePerfil.fromJson(json['cliente'] as Map<String, dynamic>)
          : null,
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 1,
      datosAdicionales: (json['datos_adicionales'] as Map?)
          ?.cast<String, dynamic>(),
      reservadoPor: json['reservado_por'] as String?,
      precioTotal: (json['precio_total'] as num?)?.toDouble(),
      moneda: json['moneda'] as String?,
      idTurno: (json['id_turno'] as num?)?.toInt(),
      turnoNombre: turnoNombre,
      recursoNombre: recursoNombre,
      idViaje: json['id_viaje']?.toString(),
      tipoTrayecto: json['tipo_trayecto'] as String?,
      // [61] Los 4 listados ya devuelven estas dos columnas. Se normaliza el
      // texto vacío a null para que las tarjetas solo pinten el motivo cuando
      // de verdad hay algo escrito.
      motivoCancelacion: _textoOpcional(json['motivo_cancelacion']),
      canceladoPorRol: _textoOpcional(json['cancelado_por_rol']),
      // [62] Pago por adelantado. Los 4 listados (migración 63) ya devuelven
      // estas columnas; en una base sin migrar llegan ausentes y quedan null,
      // que es exactamente «esta reserva no pide pago».
      pagoEstado: _textoOpcional(json['pago_estado']),
      pagoMonto: (json['pago_monto'] as num?)?.toDouble(),
      pagoMoneda: _textoOpcional(json['pago_moneda']),
    );
  }
}

/// `String?` tolerante: acepta `null`, cadenas y cualquier valor con
/// `toString()` (los RPC devuelven `text`, pero un `jsonb` mal tipado no debe
/// tumbar el parseo de todo el listado). Devuelve `null` si queda vacío.
String? _textoOpcional(dynamic valor) {
  if (valor == null) return null;
  final texto = valor.toString().trim();
  return texto.isEmpty ? null : texto;
}
