/// Modelos del panel de fidelidad del superadmin.
///
/// Todos los números vienen del servidor: el panel **no recalcula** puntos ni
/// descuentos. Lo único que se calcula aquí son etiquetas para leer mejor una
/// fila, nunca un importe que se vaya a cobrar. Si el panel calculara un saldo,
/// habría dos definiciones de "cuántos puntos tengo" y ya sabemos cómo acaba eso.
library;

/// Fila de `flow.regla_fidelidad`.
///
/// Una regla **global** (`idEntidad == null`) aplica a todos los clientes; una
/// por entidad solo a los servicios de ese negocio. El servidor prefiere la más
/// específica, así que pueden convivir.
class ReglaFidelidadAdmin {
  const ReglaFidelidadAdmin({
    required this.id,
    required this.nombre,
    this.idEntidad,
    this.entidad,
    this.moneda,
    this.puntosPorMonto = 0,
    this.montoBase = 0,
    this.vigenciaDias,
    this.activo = true,
    this.desde,
    this.hasta,
  });

  final int id;
  final String nombre;
  final int? idEntidad;

  /// `flow.entidad.denominacion` (el nombre legible). `null` si es global.
  final String? entidad;

  final String? moneda;
  final double puntosPorMonto;
  final double montoBase;

  /// Días hasta que caducan los puntos. `null` = no caducan.
  final int? vigenciaDias;

  final bool activo;
  final DateTime? desde;
  final DateTime? hasta;

  bool get esGlobal => idEntidad == null;

  String get etiquetaAlcance =>
      esGlobal ? 'Todos los clientes' : (entidad ?? 'Entidad $idEntidad');

  /// "1 punto por cada 10 USD".
  String get etiquetaRegla {
    final p = _numero(puntosPorMonto);
    final m = _numero(montoBase);
    final unidad = puntosPorMonto == 1 ? 'punto' : 'puntos';
    final mon = moneda?.trim();
    final sufijo = (mon != null && mon.isNotEmpty) ? ' $mon' : '';
    return '$p $unidad por cada $m$sufijo';
  }

  String? get etiquetaVigencia {
    final d = vigenciaDias;
    if (d == null) return 'No caducan';
    if (d % 365 == 0) {
      final a = d ~/ 365;
      return a == 1 ? 'Caducan al año' : 'Caducan a los $a años';
    }
    if (d % 30 == 0) {
      final m = d ~/ 30;
      return m == 1 ? 'Caducan al mes' : 'Caducan a los $m meses';
    }
    return 'Caducan a los $d días';
  }

  /// Activa y dentro de su ventana de vigencia, que es como la ve el servidor.
  bool get vigente {
    if (!activo) return false;
    final ahora = DateTime.now();
    if (desde != null && ahora.isBefore(desde!)) return false;
    if (hasta != null && !ahora.isBefore(hasta!)) return false;
    return true;
  }

  factory ReglaFidelidadAdmin.fromJson(Map<String, dynamic> json) {
    return ReglaFidelidadAdmin(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nombre: json['nombre'] as String? ?? 'Regla',
      idEntidad: (json['id_entidad'] as num?)?.toInt(),
      entidad: json['entidad'] as String?,
      moneda: json['moneda'] as String?,
      puntosPorMonto: (json['puntos_por_monto'] as num?)?.toDouble() ?? 0,
      montoBase: (json['monto_base'] as num?)?.toDouble() ?? 0,
      vigenciaDias: (json['vigencia_dias'] as num?)?.toInt(),
      activo: json['activo'] as bool? ?? true,
      desde: _fecha(json['desde']),
      hasta: _fecha(json['hasta']),
    );
  }
}

/// Fila de `flow.beneficio_bienvenida`.
///
/// Se gasta **una sola vez por usuario** (lo impone la base), así que `canjes`
/// es el dato que decide si además se puede borrar.
class BeneficioBienvenidaAdmin {
  const BeneficioBienvenidaAdmin({
    required this.id,
    required this.titulo,
    this.descripcion,
    this.tipo = 'porcentaje',
    this.valor = 0,
    this.moneda,
    this.idEntidad,
    this.entidad,
    this.montoMinimo,
    this.activo = true,
    this.desde,
    this.hasta,
    this.canjes = 0,
  });

  final int id;
  final String titulo;
  final String? descripcion;

  /// `porcentaje` | `monto`.
  final String tipo;
  final double valor;
  final String? moneda;

  final int? idEntidad;
  final String? entidad;

  /// Gasto mínimo (tras la promoción) para que aplique. `null` = sin mínimo.
  final double? montoMinimo;

  final bool activo;
  final DateTime? desde;
  final DateTime? hasta;

  /// Cuántos clientes ya lo canjearon.
  final int canjes;

  bool get esGlobal => idEntidad == null;

  String get etiquetaAlcance =>
      esGlobal ? 'Todos los clientes' : (entidad ?? 'Entidad $idEntidad');

  /// "20% de descuento" / "5 USD de descuento".
  String get etiquetaDescuento {
    if (tipo == 'porcentaje') return '${_numero(valor)}% de descuento';
    final mon = moneda?.trim();
    return (mon != null && mon.isNotEmpty)
        ? '${_numero(valor)} $mon de descuento'
        : '${_numero(valor)} de descuento';
  }

  /// Con canjes anotados **no se puede borrar**: borrar el beneficio borraría el
  /// registro de quién lo usó y esos usuarios volverían a ser elegibles. El
  /// servidor lo rechaza con `on delete restrict` y con un error claro.
  bool get sePuedeBorrar => canjes == 0;

  String get etiquetaCanjes => canjes == 1 ? '1 canje' : '$canjes canjes';

  bool get vigente {
    if (!activo) return false;
    final ahora = DateTime.now();
    if (desde != null && ahora.isBefore(desde!)) return false;
    if (hasta != null && !ahora.isBefore(hasta!)) return false;
    return true;
  }

  factory BeneficioBienvenidaAdmin.fromJson(Map<String, dynamic> json) {
    return BeneficioBienvenidaAdmin(
      id: (json['id'] as num?)?.toInt() ?? 0,
      titulo: json['titulo'] as String? ?? 'Beneficio',
      descripcion: json['descripcion'] as String?,
      tipo: json['tipo'] as String? ?? 'porcentaje',
      valor: (json['valor'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda'] as String?,
      idEntidad: (json['id_entidad'] as num?)?.toInt(),
      entidad: json['entidad'] as String?,
      montoMinimo: (json['monto_minimo'] as num?)?.toDouble(),
      activo: json['activo'] as bool? ?? true,
      desde: _fecha(json['desde']),
      hasta: _fecha(json['hasta']),
      canjes: (json['canjes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Fila del libro `flow.puntos_movimiento` vista por el superadmin.
class MovimientoPuntosAdmin {
  const MovimientoPuntosAdmin({
    required this.id,
    required this.puntos,
    required this.tipo,
    this.motivo,
    this.moneda,
    this.monto,
    this.venceEn,
    this.liquidado = false,
    this.createdAt,
    this.idAgenda,
    this.idEntidad,
    this.regla,
    this.vencido = false,
  });

  final int id;
  final int puntos;

  /// `acumulacion` | `canje` | `vencimiento` | `ajuste`.
  final String tipo;

  final String? motivo;
  final String? moneda;
  final double? monto;
  final DateTime? venceEn;
  final bool liquidado;
  final DateTime? createdAt;
  final int? idAgenda;
  final int? idEntidad;

  /// Nombre de la regla que lo generó, si vino de una acumulación.
  final String? regla;

  final bool vencido;

  String get etiquetaPuntos =>
      puntos > 0 ? '+$puntos' : '$puntos';

  String get etiquetaTipo => switch (tipo) {
    'acumulacion' => 'Acumulados',
    'canje' => 'Canjeados',
    'vencimiento' => 'Caducados',
    'ajuste' => 'Ajuste',
    _ => tipo,
  };

  factory MovimientoPuntosAdmin.fromJson(Map<String, dynamic> json) {
    return MovimientoPuntosAdmin(
      id: (json['id'] as num?)?.toInt() ?? 0,
      puntos: (json['puntos'] as num?)?.toInt() ?? 0,
      tipo: json['tipo'] as String? ?? 'ajuste',
      motivo: json['motivo'] as String?,
      moneda: json['moneda'] as String?,
      monto: (json['monto'] as num?)?.toDouble(),
      venceEn: _fecha(json['vence_en']),
      liquidado: json['liquidado'] == true,
      createdAt: _fecha(json['created_at']),
      idAgenda: (json['id_agenda'] as num?)?.toInt(),
      idEntidad: (json['id_entidad'] as num?)?.toInt(),
      regla: json['regla'] as String?,
      vencido: json['vencido'] == true,
    );
  }
}

/// Respuesta de `admin_listar_movimientos_puntos`: el saldo y su historial.
class AuditoriaPuntos {
  const AuditoriaPuntos({
    required this.uuidUsuario,
    required this.saldo,
    this.yaCanjeo = false,
    this.movimientos = const <MovimientoPuntosAdmin>[],
  });

  final String uuidUsuario;
  final int saldo;
  final bool yaCanjeo;
  final List<MovimientoPuntosAdmin> movimientos;

  bool get sinMovimientos => movimientos.isEmpty;

  factory AuditoriaPuntos.fromJson(Map<String, dynamic> json) {
    final crudos = json['movimientos'];
    return AuditoriaPuntos(
      uuidUsuario: json['uuid_usuario'] as String? ?? '',
      saldo: (json['saldo'] as num?)?.toInt() ?? 0,
      yaCanjeo: json['ya_canjeo'] == true,
      movimientos: crudos is List
          ? crudos
                .whereType<Map>()
                .map((e) => MovimientoPuntosAdmin.fromJson(
                      Map<String, dynamic>.from(e),
                    ))
                .toList()
          : const <MovimientoPuntosAdmin>[],
    );
  }
}

/// Estado del interruptor global (`flow.fidelidad_config`).
class FidelidadConfig {
  const FidelidadConfig({
    this.activa = true,
    this.updatedAt,
    this.updatedBy,
  });

  /// `false` = el programa está apagado para todos: no se acreditan puntos y el
  /// Home no muestra la sección. **No borra nada**: el libro se conserva.
  final bool activa;

  final DateTime? updatedAt;
  final String? updatedBy;

  factory FidelidadConfig.fromJson(Map<String, dynamic> json) {
    return FidelidadConfig(
      activa: json['activa'] != false,
      updatedAt: _fecha(json['updated_at']),
      updatedBy: json['updated_by'] as String?,
    );
  }
}

DateTime? _fecha(dynamic v) => v is String ? DateTime.tryParse(v) : null;

/// Número sin decimales de relleno: 20.0 -> "20", 7.5 -> "7.5".
String _numero(num v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}