import 'dart:math' as math;

import 'presentacion_cadena_local.dart';

/// Resolutor LOCAL del plan de desarme ("abrir") para vender unidades sueltas.
///
/// Espeja la SIMULACION 1 · ABRIR de `fn_preview_rebalanceo`, pero sin red:
/// usa la cadena de `PresentacionCadenaLocal` (misma cascada que
/// `fn_presentaciones_producto`) y los saldos que la pantalla ya tiene en
/// memoria. Es SOLO CONSULTA: no escribe, no reserva y no sustituye al
/// servidor, que al sincronizar la venta ejecuta el rebalanceo real
/// (`fn_rebalancear_presentaciones`) y es la autoridad final.
///
/// Regla del negocio (decisión del vendedor):
///   - Si el saldo propio alcanza → sin plan.
///   - Si no, se propone romper el bulto más cercano (menor nivel que cubra),
///     convirtiendo TODO el bulto a la presentación pedida (sin fracciones
///     sueltas: lo no consumido queda como presentacion pedida disponible).
class PlanDesarme {
  /// Presentación que se rompe (nivel i, empaque más grande que cubre).
  final PresentacionLocal origen;

  /// Cuántos empaques del origen hay que romper.
  final double cantidadOrigen;

  /// Unidades que entran a la presentación pedida al romper.
  final double cantidadDestino;

  /// Saldo de la presentación pedida ANTES del desarme.
  final double saldoPropio;

  /// Saldo de la presentación pedida DESPUÉS de romper (antes de vender).
  final double saldoDespuesConversion;

  /// Mensaje para el vendedor, con plural correcto via `FormatoPresentacion`.
  final String mensaje;

  const PlanDesarme({
    required this.origen,
    required this.cantidadOrigen,
    required this.cantidadDestino,
    required this.saldoPropio,
    required this.saldoDespuesConversion,
    required this.mensaje,
  });
}

/// Resultado de evaluar una venta contra los saldos locales.
class EvaluacionDesarme {
  /// `'alcanza'` | `'desarmar'` | `'imposible'`.
  final String estrategia;

  final PlanDesarme? plan;

  /// Máximo servible de la presentación pedida con lo que hay (imposible).
  final double maximoServible;

  const EvaluacionDesarme._({
    required this.estrategia,
    this.plan,
    this.maximoServible = 0,
  });

  bool get alcanza => estrategia == 'alcanza';
  bool get requiereDesarme => estrategia == 'desarmar';
  bool get esImposible => estrategia == 'imposible';
}

class DesarmeBultoLocal {
  DesarmeBultoLocal._();

  /// Evalúa vender [cantidadPedida] de [idPresentacionPedida].
  ///
  /// [stocks] son los saldos vigentes POR FILA de presentación
  /// (`app_dat_producto_presentacion.id`, el mismo id que
  /// `PresentacionLocal.idPresentacion`). Si la cadena o el saldo de la
  /// presentación pedida no se pueden resolver, devuelve `alcanza` para no
  /// bloquear la venta: el servidor manda al vender de verdad.
  static EvaluacionDesarme evaluar({
    required List<PresentacionLocal> cadena,
    required Map<int, double> stocks,
    required int idPresentacionPedida,
    required double cantidadPedida,
  }) {
    if (cantidadPedida <= 0 || cadena.isEmpty) return _alcanza;

    final idx = cadena
        .indexWhere((p) => p.idPresentacion == idPresentacionPedida);
    if (idx < 0) return _alcanza; // sin cadena conocida: no bloquear

    final t = cadena[idx];
    final saldoPropio = _redondear(stocks[t.idPresentacion] ?? 0);

    if (saldoPropio >= cantidadPedida) return _alcanza;

    // Equivalente total en unidades de la presentación pedida.
    var equivalente = 0.0;
    for (final p in cadena) {
      final f = p.factorRel / t.factorRel;
      equivalente += _redondear((stocks[p.idPresentacion] ?? 0) * f);
    }
    final maximo = _redondear(equivalente);
    if (maximo < cantidadPedida) {
      return EvaluacionDesarme._(
        estrategia: 'imposible',
        maximoServible: maximo,
      );
    }

    // ── Simulación ABRIR: del nivel inmediatamente mayor hacia arriba ─────
    // En cada paso se rompe lo justo (ceil) y el excedente queda en la
    // presentación pedida. Se elige el primer nivel (empaque más pequeño que
    // cubre) igual que hace el SQL.
    final faltante = _redondear(cantidadPedida - saldoPropio);
    var saldoTrabajo = saldoPropio;

    for (var i = idx - 1; i >= 0; i--) {
      final origen = cadena[i];
      final stockOrigen = _redondear(stocks[origen.idPresentacion] ?? 0);
      if (stockOrigen <= 0) continue;

      final factorHijo = origen.factorRel / t.factorRel;
      if (factorHijo <= 0) continue;

      final aAbrir = _redondear((faltante / factorHijo).ceilToDouble());
      if (aAbrir <= 0 || aAbrir > stockOrigen) continue;

      final producidos = _redondear(aAbrir * factorHijo);
      final saldoFinal = _redondear(saldoTrabajo + producidos);

      final mensaje = 'Se desarmará ${FormatoPresentacion.cantidad(aAbrir)} '
          '${FormatoPresentacion.plural(origen.nombre, aAbrir)} para servir '
          '${FormatoPresentacion.cantidad(cantidadPedida)} '
          '${FormatoPresentacion.plural(t.nombre, cantidadPedida)}. '
          'Quedarán ${FormatoPresentacion.cantidad(saldoFinal - cantidadPedida)} '
          '${FormatoPresentacion.plural(t.nombre, saldoFinal - cantidadPedida)} '
          'disponibles.';

      return EvaluacionDesarme._(
        estrategia: 'desarmar',
        plan: PlanDesarme(
          origen: origen,
          cantidadOrigen: aAbrir,
          cantidadDestino: producidos,
          saldoPropio: saldoPropio,
          saldoDespuesConversion: saldoFinal,
          mensaje: mensaje,
        ),
      );
    }

    return EvaluacionDesarme._(
      estrategia: 'imposible',
      maximoServible: maximo,
    );
  }

  static const _alcanza = EvaluacionDesarme._(estrategia: 'alcanza');

  /// Máximo servible de [idPresentacionPedida] con TODO el stock convertible
  /// (sumando equivalencias de los bultos de niveles mayores).
  ///
  /// Es el mismo número que devuelve `evaluar` en `maximoServible`, pero sin
  /// evaluar una cantidad concreta: sirve para habilitar la venta por la
  /// presentación base cuando su saldo propio es 0 y hay bultos que romper.
  /// Sin cadena o sin saldos devuelve [saldoPropio] para no bloquear.
  static double maximoServible({
    required List<PresentacionLocal> cadena,
    required Map<int, double> stocks,
    required int idPresentacionPedida,
    required double saldoPropio,
  }) {
    final idx = cadena
        .indexWhere((p) => p.idPresentacion == idPresentacionPedida);
    if (idx < 0) return saldoPropio;

    final t = cadena[idx];
    var equivalente = 0.0;
    for (final p in cadena) {
      final f = t.factorRel == 0 ? 0 : p.factorRel / t.factorRel;
      equivalente += _redondear((stocks[p.idPresentacion] ?? 0) * f);
    }
    return _redondear(equivalente);
  }

  static double _redondear(double v) {
    final f = math.pow(10, 6).toDouble();
    return (v * f).roundToDouble() / f;
  }
}
