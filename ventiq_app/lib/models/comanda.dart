/// Modelo de comanda de cocina (KDS).
///
/// Refleja lo que devuelve `fn_listar_comandas_cocina`: la cabecera con sus
/// items anidados. Es de solo lectura desde la app de cocina; los cambios se
/// hacen por RPC (`fn_cambiar_estado_comanda*`) y se recarga.
library;

/// Estados de preparación. Coinciden con el CHECK de `app_dat_comanda.estado`.
class EstadoComanda {
  static const int pendiente = 1;
  static const int enPreparacion = 2;
  static const int listo = 3;
  static const int entregado = 4;
  static const int cancelado = 5;

  /// Lo que la cocina tiene que atender ahora.
  static const List<int> vivos = [pendiente, enPreparacion, listo];

  /// Historial.
  static const List<int> cerrados = [entregado, cancelado];

  static String etiqueta(int? estado) {
    switch (estado) {
      case pendiente:
        return 'Pendiente';
      case enPreparacion:
        return 'Preparando';
      case listo:
        return 'Listo';
      case entregado:
        return 'Entregado';
      case cancelado:
        return 'Cancelado';
      default:
        return 'Desconocido';
    }
  }
}

class Comanda {
  final int id;
  final int? numero;
  final int estado;
  final int idCocina;
  final String? cocina;
  final int? idCuenta;
  final int? idMesa;
  final String? mesa;
  final String? zona;
  final int? idTpv;
  final String? notas;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? readyAt;

  /// Minutos desde que entró la comanda, calculado por el servidor. Se usa el
  /// del servidor y no la hora local porque la tablet de cocina puede tener el
  /// reloj desajustado.
  final int esperaMinutos;

  final int totalItems;
  final int itemsListos;
  final List<ComandaItem> items;

  const Comanda({
    required this.id,
    this.numero,
    required this.estado,
    required this.idCocina,
    this.cocina,
    this.idCuenta,
    this.idMesa,
    this.mesa,
    this.zona,
    this.idTpv,
    this.notas,
    required this.createdAt,
    this.startedAt,
    this.readyAt,
    required this.esperaMinutos,
    required this.totalItems,
    required this.itemsListos,
    this.items = const [],
  });

  bool get pendiente => estado == EstadoComanda.pendiente;
  bool get enPreparacion => estado == EstadoComanda.enPreparacion;
  bool get lista => estado == EstadoComanda.listo;
  bool get entregada => estado == EstadoComanda.entregado;
  bool get cancelada => estado == EstadoComanda.cancelado;

  /// Sigue siendo trabajo de la cocina.
  bool get viva => EstadoComanda.vivos.contains(estado);

  /// Texto de la mesa para cantar la comanda. Cae a la cuenta o al TPV si la
  /// comanda no vino de una mesa (venta directa).
  String get destino {
    if (mesa != null && mesa!.isNotEmpty) {
      return zona != null && zona!.isNotEmpty ? '$mesa · $zona' : mesa!;
    }
    if (idCuenta != null) return 'Cuenta $idCuenta';
    return 'Mostrador';
  }

  String get titulo => numero != null ? '#$numero' : 'Comanda $id';

  /// Progreso para la barra de la tarjeta.
  double get progreso => totalItems == 0 ? 0 : itemsListos / totalItems;

  /// Umbrales de demora. No son configurables todavía: son los que usa la
  /// industria como referencia gruesa (bajo 10 min normal, 10–20 atención,
  /// más de 20 crítico).
  bool get demorada => esperaMinutos >= 10 && esperaMinutos < 20;
  bool get critica => esperaMinutos >= 20;

  factory Comanda.fromJson(Map<String, dynamic> json) {
    int? entero(String k) => json[k] is num ? (json[k] as num).toInt() : null;
    DateTime? fecha(String k) => json[k] == null
        ? null
        : DateTime.tryParse(json[k] as String? ?? '');

    final itemsRaw = json['items'];
    final items = <ComandaItem>[];
    if (itemsRaw is List) {
      for (final raw in itemsRaw) {
        if (raw is Map) {
          items.add(ComandaItem.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }

    return Comanda(
      id: (json['id'] as num).toInt(),
      numero: entero('numero'),
      estado: entero('estado') ?? EstadoComanda.pendiente,
      idCocina: (json['id_cocina'] as num).toInt(),
      cocina: json['cocina'] as String?,
      idCuenta: entero('id_cuenta'),
      idMesa: entero('id_mesa'),
      mesa: json['mesa'] as String?,
      zona: json['zona'] as String?,
      idTpv: entero('id_tpv'),
      notas: json['notas'] as String?,
      createdAt: fecha('created_at') ?? DateTime.now(),
      startedAt: fecha('started_at'),
      readyAt: fecha('ready_at'),
      esperaMinutos: entero('espera_minutos') ?? 0,
      totalItems: entero('total_items') ?? items.length,
      itemsListos: entero('items_listos') ?? 0,
      items: items,
    );
  }
}

class ComandaItem {
  final int id;
  final int idProducto;
  final String denominacion;
  final double cantidad;

  /// `al_pedido` o `por_tanda`, congelado al pedirse.
  final String modoElaboracion;

  final int estado;

  /// Nota del comensal: "sin cebolla", "al punto". Es lo que la cocina NO debe
  /// pasar por alto, de ahí que la UI la destaque.
  final String? notas;

  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? readyAt;

  const ComandaItem({
    required this.id,
    required this.idProducto,
    required this.denominacion,
    required this.cantidad,
    required this.modoElaboracion,
    required this.estado,
    this.notas,
    required this.createdAt,
    this.startedAt,
    this.readyAt,
  });

  bool get pendiente => estado == EstadoComanda.pendiente;
  bool get enPreparacion => estado == EstadoComanda.enPreparacion;
  bool get listo => estado == EstadoComanda.listo;
  bool get entregado => estado == EstadoComanda.entregado;
  bool get cancelado => estado == EstadoComanda.cancelado;

  bool get tieneNota => notas != null && notas!.trim().isNotEmpty;

  /// Cantidad sin decimales cuando es entera: "2" en vez de "2.0".
  String get cantidadTexto =>
      cantidad % 1 == 0 ? cantidad.toInt().toString() : cantidad.toString();

  /// Siguiente estado natural al tocar el item en el KDS. Un toque avanza:
  /// pendiente → preparando → listo → entregado. Devuelve `null` si ya es
  /// terminal.
  int? get siguienteEstado {
    switch (estado) {
      case EstadoComanda.pendiente:
        return EstadoComanda.enPreparacion;
      case EstadoComanda.enPreparacion:
        return EstadoComanda.listo;
      case EstadoComanda.listo:
        return EstadoComanda.entregado;
      default:
        return null;
    }
  }

  /// Verbo de la acción que ejecuta el siguiente toque.
  String? get accionSiguiente {
    switch (estado) {
      case EstadoComanda.pendiente:
        return 'Empezar';
      case EstadoComanda.enPreparacion:
        return 'Listo';
      case EstadoComanda.listo:
        return 'Entregar';
      default:
        return null;
    }
  }

  factory ComandaItem.fromJson(Map<String, dynamic> json) {
    DateTime? fecha(String k) => json[k] == null
        ? null
        : DateTime.tryParse(json[k] as String? ?? '');

    return ComandaItem(
      id: (json['id'] as num).toInt(),
      idProducto: (json['id_producto'] as num).toInt(),
      denominacion: json['denominacion'] as String? ?? 'Plato',
      cantidad: (json['cantidad'] as num?)?.toDouble() ?? 1.0,
      modoElaboracion: json['modo_elaboracion'] as String? ?? 'al_pedido',
      estado: json['estado'] is num
          ? (json['estado'] as num).toInt()
          : EstadoComanda.pendiente,
      notas: json['notas'] as String?,
      createdAt: fecha('created_at') ?? DateTime.now(),
      startedAt: fecha('started_at'),
      readyAt: fecha('ready_at'),
    );
  }
}

/// Cocina que el usuario puede operar, según `fn_cocinas_del_usuario`.
class CocinaAsignada {
  final int idCocina;
  final String denominacion;
  final int idTienda;
  final int idAlmacen;
  final bool activa;
  final bool esJefe;

  /// Cómo obtuvo el acceso: `jefe_cocina`, `cocinero`, `gerente`, `supervisor`.
  final String via;

  const CocinaAsignada({
    required this.idCocina,
    required this.denominacion,
    required this.idTienda,
    required this.idAlmacen,
    required this.activa,
    required this.esJefe,
    required this.via,
  });

  factory CocinaAsignada.fromJson(Map<String, dynamic> json) {
    return CocinaAsignada(
      idCocina: (json['id_cocina'] as num).toInt(),
      denominacion: json['denominacion'] as String? ?? 'Cocina',
      idTienda: (json['id_tienda'] as num).toInt(),
      idAlmacen: (json['id_almacen'] as num).toInt(),
      activa: json['activa'] as bool? ?? true,
      esJefe: json['es_jefe'] as bool? ?? false,
      via: json['via'] as String? ?? 'cocinero',
    );
  }
}
