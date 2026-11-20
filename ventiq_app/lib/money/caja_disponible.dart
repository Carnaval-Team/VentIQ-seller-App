import '../utils/price_utils.dart';

/// Un cobro o un egreso de la caja, en el importe NATIVO de su moneda.
class MovimientoCaja {
  final String moneda;
  final double monto;
  final int? idMedio;

  /// Sale/entra del cajón físico. Falso: cuenta digital de un medio concreto.
  final bool efectivo;

  const MovimientoCaja({
    required this.moneda,
    required this.monto,
    required this.idMedio,
    required this.efectivo,
  });
}

/// Dinero que hay en la caja del turno por moneda y medio de pago.
///
/// * Efectivo: el cajón es uno solo. Disponible = efectivo inicial + cobros en
///   efectivo − egresos en efectivo, de esa moneda, sin importar cuál medio en
///   efectivo se eligió (si no, el mismo billete se podría sacar dos veces).
/// * Digital: solo lo cobrado con ese medio y esa moneda menos lo egresado con
///   ese medio y esa moneda. El efectivo inicial no cuenta.
///
/// Nada se convierte entre monedas: un sobrante en USD no cubre un faltante
/// en CUP.
class CajaDisponible {
  final Map<String, double> inicialPorMoneda;
  final List<MovimientoCaja> cobros;
  final List<MovimientoCaja> egresos;

  const CajaDisponible({
    required this.inicialPorMoneda,
    required this.cobros,
    required this.egresos,
  });

  static const CajaDisponible vacia = CajaDisponible(
    inicialPorMoneda: {},
    cobros: [],
    egresos: [],
  );

  /// Cobros y egresos a partir de mapas con las claves de la base y del
  /// caché: pagos (`moneda`, `monto`, `id_medio_pago`, `es_efectivo`) y filas
  /// de egreso (`moneda`, `monto_entrega`, `id_medio_pago`, `es_digital`).
  factory CajaDisponible.desdeMapas({
    required Map<String, double> inicialPorMoneda,
    required Iterable<Map<String, dynamic>> pagos,
    required Iterable<Map<String, dynamic>> egresos,
  }) {
    final cobros = <MovimientoCaja>[];
    for (final pago in pagos) {
      if (PriceUtils.paymentIsPending(pago)) continue;
      final monto = PriceUtils.paymentAmount(pago);
      if (monto == 0) continue;
      cobros.add(
        MovimientoCaja(
          moneda: PriceUtils.paymentCurrency(pago),
          monto: monto,
          idMedio: _idMedio(pago),
          efectivo: PriceUtils.paymentIsCash(pago),
        ),
      );
    }

    final salidas = <MovimientoCaja>[];
    for (final fila in egresos) {
      final monto = _numero(fila['monto_entrega']);
      if (monto == 0) continue;
      salidas.add(
        MovimientoCaja(
          moneda: PriceUtils.paymentCurrency({'moneda': fila['moneda']}),
          monto: monto,
          idMedio: _idMedio(fila),
          // Igual que el cierre: solo es digital si se marcó; null es efectivo.
          efectivo: fila['es_digital'] != true,
        ),
      );
    }

    return CajaDisponible(
      inicialPorMoneda: {
        for (final e in inicialPorMoneda.entries)
          e.key.trim().toUpperCase(): e.value,
      },
      cobros: cobros,
      egresos: salidas,
    );
  }

  /// Efectivo inicial por moneda de un turno o de un resumen (RPC o caché).
  ///
  /// Prioriza `efectivo_inicial_por_moneda`; si no está, `efectivo_inicial`
  /// es la moneda base y `efectivo_inicial_usd` la única divisa extra que el
  /// backend separaba.
  static Map<String, double> inicialDeMapa(Map<String, dynamic>? data) {
    if (data == null) return const {};
    final porMoneda = data['efectivo_inicial_por_moneda'];
    if (porMoneda is Map && porMoneda.isNotEmpty) {
      return {
        for (final e in porMoneda.entries)
          e.key.toString().trim().toUpperCase(): _numero(e.value),
      };
    }
    final base = data['efectivo_inicial'] ?? data['monto_inicial_caja'];
    return {
      if (base != null) PriceUtils.baseCurrency: _numero(base),
      if (data['efectivo_inicial_usd'] != null)
        'USD': _numero(data['efectivo_inicial_usd']),
    };
  }

  double disponible({
    required String moneda,
    required int? idMedio,
    required bool efectivo,
  }) {
    final divisa = moneda.trim().toUpperCase();
    bool cuenta(MovimientoCaja m) =>
        m.moneda == divisa &&
        m.efectivo == efectivo &&
        (efectivo || m.idMedio == idMedio);

    var total = efectivo ? (inicialPorMoneda[divisa] ?? 0.0) : 0.0;
    for (final cobro in cobros.where(cuenta)) {
      total += cobro.monto;
    }
    for (final egreso in egresos.where(cuenta)) {
      total -= egreso.monto;
    }
    return _redondear(total);
  }

  /// Mensaje de rechazo si [monto] supera lo disponible; null si se puede.
  String? rechazo({
    required double monto,
    required String moneda,
    required int? idMedio,
    required bool efectivo,
    String? nombreMedio,
  }) {
    final libre = disponible(moneda: moneda, idMedio: idMedio, efectivo: efectivo);
    if (_redondear(monto) <= libre) return null;
    final donde = efectivo ? 'en efectivo' : 'en ${nombreMedio ?? 'este medio'}';
    final texto = libre <= 0 ? '0.00' : libre.toMoneyString(2);
    return 'No hay dinero suficiente: disponible $texto $moneda $donde';
  }

  static int? _idMedio(Map<String, dynamic> fila) {
    final raw = fila['id_medio_pago'] ?? fila['medio_pago_id'];
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}');
  }

  static double _numero(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0.0;
  }

  static double _redondear(double v) => (v * 100).roundToDouble() / 100;
}
