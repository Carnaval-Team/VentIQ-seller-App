import 'package:supabase_flutter/supabase_flutter.dart';

/// Promoción de `flow.promocion`.
///
/// El alcance es el servicio (`idLocalServicio`) o **toda la entidad**
/// (`idEntidad`): una promo de entidad aplica a todos sus servicios.
class Promocion {
  const Promocion({
    required this.id,
    required this.titulo,
    required this.tipo,
    required this.valor,
    this.descripcion,
    this.moneda,
    this.idLocalServicio,
    this.idEntidad,
    this.desde,
    this.hasta,
    this.cupoTotal,
    this.cupoUsado = 0,
    this.cuposRestantes,
    this.activo = true,
    this.servicio,
    this.local,
  });

  final int id;
  final String titulo;

  /// `'porcentaje'` o `'monto'`.
  final String tipo;
  final double valor;

  final String? descripcion;
  final String? moneda;

  final int? idLocalServicio;
  final int? idEntidad;

  final DateTime? desde;
  final DateTime? hasta;

  final int? cupoTotal;
  final int cupoUsado;

  /// `cupoTotal - cupoUsado`, o `null` si la promo no tiene cupo limitado.
  final int? cuposRestantes;

  final bool activo;

  /// Solo en el listado del panel admin.
  final String? servicio;
  final String? local;

  bool get esPorcentaje => tipo == 'porcentaje';
  bool get tieneCupo => cupoTotal != null;

  /// Texto corto para el badge: "-20 %" o "-5 USD".
  String get etiquetaDescuento => esPorcentaje
      ? '-${formatearNumero(valor)} %'
      : '-${formatearNumero(valor)}${moneda != null ? ' $moneda' : ''}';

  /// Número sin decimales cuando es entero, con dos si no. Público porque el
  /// formulario de administración rellena el campo con este mismo formato.
  static String formatearNumero(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  factory Promocion.fromJson(Map<String, dynamic> json) => Promocion(
    id: (json['id'] as num).toInt(),
    titulo: json['titulo'] as String? ?? 'Promoción',
    tipo: json['tipo'] as String? ?? 'porcentaje',
    valor: (json['valor'] as num?)?.toDouble() ?? 0,
    descripcion: json['descripcion'] as String?,
    moneda: json['moneda'] as String?,
    idLocalServicio: (json['id_local_servicio'] as num?)?.toInt(),
    idEntidad: (json['id_entidad'] as num?)?.toInt(),
    desde: _fecha(json['desde']),
    hasta: _fecha(json['hasta']),
    cupoTotal: (json['cupo_total'] as num?)?.toInt(),
    cupoUsado: (json['cupo_usado'] as num?)?.toInt() ?? 0,
    cuposRestantes: (json['cupos_restantes'] as num?)?.toInt(),
    activo: json['activo'] as bool? ?? true,
    servicio: json['servicio'] as String?,
    local: json['local'] as String?,
  );

  static DateTime? _fecha(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}

/// Resultado de cotizar una reserva (`flow.cotizar_reserva`).
///
/// Es la **única** fuente del precio que se muestra: sale del mismo cálculo que
/// luego cobra `cliente_reservar_directo`. Antes la app calculaba el precio por
/// su cuenta en Dart y el servidor lo calculaba otra vez al cobrar: dos
/// implementaciones de la misma regla, que es como aparecen los descuadres.
class CotizacionReserva {
  const CotizacionReserva({
    required this.precioLista,
    required this.precioTotal,
    required this.descuento,
    required this.moneda,
    required this.precioUnit,
    this.idPromocion,
    this.promoTitulo,
  });

  /// Precio sin promoción. Es el que se pinta tachado.
  final double precioLista;

  /// Lo que se cobra de verdad.
  final double precioTotal;

  final double descuento;
  final String moneda;
  final double precioUnit;

  final int? idPromocion;
  final String? promoTitulo;

  bool get tieneDescuento => descuento > 0 && precioLista > precioTotal;
  bool get hayPrecio => precioLista > 0;

  static const CotizacionReserva vacia = CotizacionReserva(
    precioLista: 0,
    precioTotal: 0,
    descuento: 0,
    moneda: 'USD',
    precioUnit: 0,
  );

  factory CotizacionReserva.fromJson(Map<String, dynamic>? json) {
    if (json == null || json['ok'] != true) return vacia;
    return CotizacionReserva(
      precioLista: (json['precio_lista'] as num?)?.toDouble() ?? 0,
      precioTotal: (json['precio_total'] as num?)?.toDouble() ?? 0,
      descuento: (json['descuento'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda'] as String? ?? 'USD',
      precioUnit: (json['precio_unit'] as num?)?.toDouble() ?? 0,
      idPromocion: (json['id_promocion'] as num?)?.toInt(),
      promoTitulo: json['promo_titulo'] as String?,
    );
  }
}

/// Excepción de cotización con el código del servidor cuando lo hay.
///
/// `promo_agotada` es el caso que importa: la promo se acabó entre que el
/// cliente vio el precio y pulsó reservar. Se distingue para poder avisarle en
/// vez de mostrar un error genérico.
class PromocionAgotadaException implements Exception {
  final String mensaje;
  const PromocionAgotadaException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Promociones y cotización contra `flow`.
class PromocionService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Cotiza una reserva. **No consume cupo**: solo informa del precio de ahora.
  ///
  /// Lo que devuelve es exactamente lo que se cobrará al confirmar, porque
  /// ambos caminos comparten `_resolver_promocion` en el servidor.
  static Future<CotizacionReserva> cotizar({
    required String uuidUsuario,
    required int idLocalServicio,
    Map<String, dynamic>? datosAdicionales,
    String? moneda,
    int cantidad = 1,
    int? idTurno,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'cotizar_reserva',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_local_servicio': idLocalServicio,
            if (datosAdicionales != null && datosAdicionales.isNotEmpty)
              'p_datos': datosAdicionales,
            if (moneda != null) 'p_moneda': moneda,
            'p_cantidad': cantidad,
            if (idTurno != null) 'p_id_turno': idTurno,
          },
        );
    if (res is! Map) return CotizacionReserva.vacia;
    final json = Map<String, dynamic>.from(res);
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo cotizar la reserva');
    }
    return CotizacionReserva.fromJson(json);
  }

  /// Promos vigentes del servicio (propias y de su entidad).
  static Future<List<Promocion>> deServicio(int idLocalServicio) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'promociones_de_servicio',
          params: {'p_id_local_servicio': idLocalServicio},
        );
    if (res is! List) return const [];
    return res
        .whereType<Map>()
        .map((e) => Promocion.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Mejor promo aplicable a cada servicio, en una sola llamada.
  ///
  /// El servidor ya resuelve la prioridad (promo propia antes que la de la
  /// entidad, luego el porcentaje más alto). El Home solo tiene que pintar el
  /// badge: no necesita saber nada de entidades ni de prioridades.
  static Future<Map<int, Promocion>> porServicio() async {
    final res = await _supabase.schema(_schema).rpc('promociones_por_servicio');
    if (res is! List) return const {};
    return {
      for (final fila in res.whereType<Map>())
        (fila['id_local_servicio'] as num).toInt(): Promocion.fromJson(
          Map<String, dynamic>.from(fila),
        ),
    };
  }

  /// Listado para el panel admin (solo promos de las entidades del usuario).
  static Future<List<Promocion>> listar({
    required String uuidUsuario,
    int? idLocalServicio,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_listar_promociones',
          params: {
            'p_uuid_usuario': uuidUsuario,
            if (idLocalServicio != null) 'p_id_local_servicio': idLocalServicio,
          },
        );
    if (res is! Map) return const [];
    final json = Map<String, dynamic>.from(res);
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudieron leer las promociones');
    }
    final lista = json['data'];
    if (lista is! List) return const [];
    return lista
        .whereType<Map>()
        .map((e) => Promocion.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<int> guardar({
    required String uuidUsuario,
    required int idLocalServicio,
    required String titulo,
    required String tipo,
    required double valor,
    String? moneda,
    String? descripcion,
    DateTime? desde,
    DateTime? hasta,
    int? cupoTotal,
    bool activo = true,
    int? id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_guardar_promocion',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_local_servicio': idLocalServicio,
            'p_titulo': titulo,
            'p_tipo': tipo,
            'p_valor': valor,
            if (moneda != null) 'p_moneda': moneda,
            if (desde != null) 'p_desde': desde.toUtc().toIso8601String(),
            if (hasta != null) 'p_hasta': hasta.toUtc().toIso8601String(),
            if (cupoTotal != null) 'p_cupo_total': cupoTotal,
            'p_activo': activo,
            if (id != null) 'p_id': id,
          },
        );
    final json = res is Map ? Map<String, dynamic>.from(res) : const {};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar la promoción');
    }
    return ((json['data'] as Map<String, dynamic>)['id'] as num).toInt();
  }

  static Future<void> eliminar({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'admin_eliminar_promocion',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
        );
    final json = res is Map ? Map<String, dynamic>.from(res) : const {};
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar la promoción');
    }
  }
}
