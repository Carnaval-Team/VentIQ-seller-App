import 'package:supabase_flutter/supabase_flutter.dart';

/// Un movimiento del libro de puntos (`flow.puntos_movimiento`).
///
/// El libro es **append-only**: nunca se edita ni se borra una fila. El saldo no
/// es una columna, es la suma de estos movimientos (ver `flow.fn_saldo_puntos`),
/// así que la auditoría y el saldo no pueden desincronizarse.
class MovimientoPuntos {
  const MovimientoPuntos({
    required this.id,
    required this.puntos,
    required this.tipo,
    this.motivo,
    this.moneda,
    this.monto,
    this.venceEn,
    this.vencido = false,
    this.createdAt,
  });

  final int id;

  /// Positivo acumula; negativo es canje, vencimiento o ajuste a la baja.
  final int puntos;

  /// `acumulacion` | `canje` | `vencimiento` | `ajuste`.
  final String tipo;

  final String? motivo;
  final String? moneda;

  /// Importe de la reserva que generó el movimiento, si aplica.
  final double? monto;

  /// Cuándo caducan estos puntos. `null` = no caducan.
  final DateTime? venceEn;

  /// `true` si ya pasaron su fecha y **todavía** no se han asentado con un
  /// movimiento de vencimiento. El saldo ya los excluye en ese caso.
  final bool vencido;

  final DateTime? createdAt;

  /// "+3" / "-5", con el signo explícito para que se lea de un vistazo.
  String get etiquetaPuntos => puntos >= 0 ? '+$puntos' : '$puntos';

  /// Texto legible del tipo, para la lista de movimientos.
  String get etiquetaTipo {
    switch (tipo) {
      case 'acumulacion':
        return 'Acumulados';
      case 'canje':
        return 'Canjeados';
      case 'vencimiento':
        return 'Caducados';
      case 'ajuste':
        return 'Ajuste';
      default:
        return tipo;
    }
  }

  factory MovimientoPuntos.fromJson(Map<String, dynamic> json) {
    return MovimientoPuntos(
      id: (json['id'] as num?)?.toInt() ?? 0,
      puntos: (json['puntos'] as num?)?.toInt() ?? 0,
      tipo: json['tipo'] as String? ?? 'ajuste',
      motivo: json['motivo'] as String?,
      moneda: json['moneda'] as String?,
      monto: (json['monto'] as num?)?.toDouble(),
      venceEn: _fecha(json['vence_en']),
      vencido: json['vencido'] == true,
      createdAt: _fecha(json['created_at']),
    );
  }

  static DateTime? _fecha(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}

/// Regla de acumulación vigente (`flow.regla_fidelidad`, la global).
class ReglaFidelidad {
  const ReglaFidelidad({
    required this.puntosPorMonto,
    required this.montoBase,
    this.vigenciaDias,
    this.moneda,
  });

  /// Puntos que se otorgan por cada [montoBase] de gasto.
  final double puntosPorMonto;

  /// Cada cuánto dinero se otorga [puntosPorMonto]. Por defecto 10.
  final double montoBase;

  /// Días que duran los puntos ganados. `null` = no caducan.
  final int? vigenciaDias;

  /// `null` = la regla sirve para cualquier moneda.
  final String? moneda;

  /// Frase para el Home: "Ganas 1 punto por cada 10 USD".
  ///
  /// Se construye aquí y no en el servidor para que la app pueda cambiar la
  /// redacción sin tocar la base.
  String get explicacion {
    final p = _cantidad(puntosPorMonto);
    final m = _cantidad(montoBase);
    final unidad = puntosPorMonto == 1 ? 'punto' : 'puntos';
    final mon = moneda?.trim();
    final sufijo = (mon != null && mon.isNotEmpty) ? ' $mon' : '';
    return 'Ganas $p $unidad por cada $m$sufijo';
  }

  /// "Caducan a los 12 meses" o `null` si no caducan.
  String? get etiquetaVigencia {
    final d = vigenciaDias;
    if (d == null) return null;
    if (d % 365 == 0) {
      final anios = d ~/ 365;
      return anios == 1 ? 'Caducan al año' : 'Caducan a los $anios años';
    }
    if (d % 30 == 0) {
      final meses = d ~/ 30;
      return meses == 1 ? 'Caducan al mes' : 'Caducan a los $meses meses';
    }
    return 'Caducan a los $d días';
  }

  factory ReglaFidelidad.fromJson(Map<String, dynamic> json) {
    return ReglaFidelidad(
      puntosPorMonto: (json['puntos_por_monto'] as num?)?.toDouble() ?? 0,
      montoBase: (json['monto_base'] as num?)?.toDouble() ?? 0,
      vigenciaDias: (json['vigencia_dias'] as num?)?.toInt(),
      moneda: json['moneda'] as String?,
    );
  }
}

/// Beneficio de bienvenida pendiente (`flow.beneficio_bienvenida`).
///
/// Es **una sola vez por usuario** y lo impone la base (`unique` en
/// `flow.beneficio_canje.uuid_usuario`), no la app.
class BeneficioBienvenida {
  const BeneficioBienvenida({
    required this.id,
    required this.titulo,
    this.descripcion,
    required this.tipo,
    required this.valor,
    this.moneda,
    this.montoMinimo,
  });

  final int id;
  final String titulo;
  final String? descripcion;

  /// `porcentaje` | `monto`.
  final String tipo;
  final double valor;
  final String? moneda;

  /// Gasto mínimo para que aplique. `null` = sin mínimo.
  final double? montoMinimo;

  /// "20% de descuento" / "5 USD de descuento".
  String get etiqueta {
    if (tipo == 'porcentaje') {
      return '${_cantidad(valor)}% de descuento';
    }
    final mon = moneda?.trim();
    return (mon != null && mon.isNotEmpty)
        ? '${_cantidad(valor)} $mon de descuento'
        : '${_cantidad(valor)} de descuento';
  }

  factory BeneficioBienvenida.fromJson(Map<String, dynamic> json) {
    return BeneficioBienvenida(
      id: (json['id'] as num?)?.toInt() ?? 0,
      titulo: json['titulo'] as String? ?? '',
      descripcion: json['descripcion'] as String?,
      tipo: json['tipo'] as String? ?? 'porcentaje',
      valor: (json['valor'] as num?)?.toDouble() ?? 0,
      moneda: json['moneda'] as String?,
      montoMinimo: (json['monto_minimo'] as num?)?.toDouble(),
    );
  }
}

/// Todo lo que el Home necesita para pintar la fidelidad, en una sola llamada.
class MiFidelidad {
  const MiFidelidad({
    required this.conSesion,
    required this.saldo,
    this.activa = true,
    this.regla,
    this.beneficio,
    this.yaCanjeo = false,
    this.movimientos = const <MovimientoPuntos>[],
  });

  /// `false` cuando no hay `auth.uid()` (el RPC se llamó sin sesión).
  final bool conSesion;

  /// Interruptor global del superadmin (`flow.fidelidad_config.activa`).
  ///
  /// Con `false` el programa está apagado para todos y el Home no pinta la
  /// sección, por muchos puntos que el usuario tenga. Se asume `true` salvo que
  /// el servidor diga lo contrario, que es el valor por defecto de la base.
  ///
  /// Apagar no borra: el libro de movimientos se conserva y al reactivar cada
  /// cliente recupera su saldo.
  final bool activa;

  final int saldo;
  final ReglaFidelidad? regla;
  final BeneficioBienvenida? beneficio;

  /// Si ya gastó su beneficio de bienvenida. Entonces no hay [beneficio] aunque
  /// el programa siga activo.
  final bool yaCanjeo;

  final List<MovimientoPuntos> movimientos;

  /// "1 punto" / "12 puntos".
  String get etiquetaPuntos => saldo == 1 ? '1 punto' : '$saldo puntos';

  /// Hay algo que contar: el programa encendido, sesión, y una regla configurada
  /// o movimientos reales.
  ///
  /// El interruptor va primero a propósito: si el superadmin lo apagó, el Home no
  /// muestra nada aunque haya regla y saldo.
  bool get hayAlgoQueMostrar =>
      activa && conSesion && (regla != null || movimientos.isNotEmpty);

  factory MiFidelidad.fromJson(Map<String, dynamic> json) {
    final regla = json['regla'];
    final beneficio = json['beneficio'];
    final movs = json['movimientos'];
    return MiFidelidad(
      conSesion: json['con_sesion'] == true,
      // Solo es `false` si el servidor lo dice explícitamente: una respuesta sin
      // el campo (migración intermedia) no debe apagar la sección.
      activa: json['activa'] != false,
      saldo: (json['saldo'] as num?)?.toInt() ?? 0,
      regla: regla is Map
          ? ReglaFidelidad.fromJson(Map<String, dynamic>.from(regla))
          : null,
      beneficio: beneficio is Map
          ? BeneficioBienvenida.fromJson(Map<String, dynamic>.from(beneficio))
          : null,
      yaCanjeo: json['ya_canjeo'] == true,
      movimientos: movs is List
          ? movs
                .whereType<Map>()
                .map((e) =>
                    MovimientoPuntos.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <MovimientoPuntos>[],
    );
  }
}

/// Lectura del programa de fidelidad del usuario.
class FidelidadService {
  const FidelidadService._();

  static const String _schema = 'flow';

  /// Saldo, regla vigente, beneficio pendiente y últimos movimientos.
  ///
  /// Devuelve `null` si la migración `31_fidelidad.sql` no está aplicada, si no
  /// hay sesión o si el RPC falla. Es deliberado: el Home se pinta sin la
  /// sección, en vez de mostrar un "20 % de descuento" inventado como hacía
  /// antes, o de romperse.
  ///
  /// El RPC es `security invoker`, así que los movimientos que devuelve son
  /// siempre los de quien llama: el filtro por usuario lo hace RLS, no el
  /// cliente.
  static Future<MiFidelidad?> miFidelidad() async {
    try {
      final res = await Supabase.instance.client
          .schema(_schema)
          .rpc('cliente_mi_fidelidad');

      // `cliente_mi_fidelidad()` devuelve un objeto `jsonb`, no una lista.
      if (res is! Map) return null;
      return MiFidelidad.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return null;
    }
  }
}

/// Número sin decimales de relleno: 20.0 -> "20", 7.5 -> "7.5".
String _cantidad(num v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}