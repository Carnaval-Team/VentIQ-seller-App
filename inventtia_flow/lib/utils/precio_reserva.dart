import '../models/config_precio.dart';

class ResultadoPrecioReserva {
  final double total;
  final double unitario;
  final String moneda;
  final String origen; // 'base' | 'regla' | 'turno' | 'sin_config'
  final String? siClave;

  const ResultadoPrecioReserva({
    required this.total,
    required this.unitario,
    required this.moneda,
    this.origen = 'sin_config',
    this.siClave,
  });
}

/// Calcula el precio de una reserva según la configuración del servicio.
class PrecioReserva {
  PrecioReserva._();

  /// Precio unitario × [cantidad] para [datosAdicionales].
  ///
  /// Orden de resolución (idéntico al de `flow.calcular_precio_con_reglas`):
  ///  1. **Base**: [baseUnitario] si viene (precio propio del turno, `origen`
  ///     `'turno'`), si no `config.preciosBase` en la moneda elegida y, como
  ///     respaldo, en la moneda por defecto.
  ///  2. **Reglas** en orden: gana la primera que coincide y cuyo precio sea
  ///     resoluble en la moneda elegida (o en la moneda por defecto). Una regla
  ///     sin precio para ninguna de las dos se ignora y no devuelve `0`.
  static ResultadoPrecioReserva calcular({
    required ConfigPrecio config,
    required Map<String, dynamic> datosAdicionales,
    String? moneda,
    int cantidad = 1,
    double? baseUnitario,
  }) {
    final cant = cantidad < 1 ? 1 : cantidad;
    final monedas = config.monedas.isEmpty ? ['USD'] : config.monedas;
    var mon = moneda ?? config.monedaDefault;
    if (!monedas.contains(mon)) mon = config.monedaDefault;

    // La base es el precio propio del turno si viene (transporte), y si no el
    // `precios_base` del servicio. Las reglas se aplican ENCIMA de esa base.
    final unitBase = baseUnitario ??
        config.preciosBase[mon] ??
        config.preciosBase[config.monedaDefault];
    final origenBase = baseUnitario != null
        ? 'turno'
        : (config.preciosBase.isEmpty ? 'sin_config' : 'base');

    for (final regla in config.reglas) {
      if (regla.siClave.isEmpty || regla.preciosOpcion.isEmpty) continue;
      final valor = datosAdicionales[regla.siClave];
      if (valor == null) continue;
      final vs = valor.toString();
      final preciosOpc = regla.preciosOpcion[vs];
      if (preciosOpc == null || preciosOpc.isEmpty) continue;
      // Una regla que casa pero no tiene precio para la moneda elegida ni para
      // la moneda por defecto se IGNORA: nunca se cobra 0 por este motivo, se
      // sigue con la base (o con la siguiente regla que sí tenga precio).
      final unit = preciosOpc[mon] ?? preciosOpc[config.monedaDefault];
      if (unit == null) continue;
      return ResultadoPrecioReserva(
        total: unit * cant,
        unitario: unit,
        moneda: mon,
        origen: 'regla',
        siClave: regla.siClave,
      );
    }

    final unit = unitBase ?? 0;
    return ResultadoPrecioReserva(
      total: unit * cant,
      unitario: unit,
      moneda: mon,
      origen: origenBase,
    );
  }

  static String formatear(double monto, String moneda) {
    final sim = MonedasApp.simbolo(moneda);
    final dec = monto == monto.roundToDouble() ? 0 : 2;
    final txt = monto.toStringAsFixed(dec);
    if (moneda == 'USD' || moneda == 'EUR') return '$sim$txt';
    return '$txt $sim';
  }
}

/// Precio base del servicio en su moneda por defecto, o `null` si no tiene.
///
/// A diferencia de [PrecioReserva.calcular] —que devuelve `0` con origen
/// `sin_config` porque necesita un número para sumar— aquí el `null` es
/// intencional: `config_precio = '{}'` es un caso real en el catálogo, y una
/// tarjeta debe decir "Consultar" en vez de mostrar un precio de 0.
///
/// Vive aquí, y no en cada pantalla, porque el Home, la pantalla de favoritos y
/// el catálogo necesitan exactamente la misma regla.
({double precio, String moneda})? precioBaseDe(ConfigPrecio? config) {
  if (config == null || config.preciosBase.isEmpty) return null;
  final moneda = config.preciosBase.containsKey(config.monedaDefault)
      ? config.monedaDefault
      : config.preciosBase.keys.first;
  final valor = config.preciosBase[moneda];
  if (valor == null || valor <= 0) return null;
  return (precio: valor, moneda: moneda);
}

/// `"18 USD"` / `"1500 CUP"`, o `null` si el servicio no tiene precio base.
String? etiquetaPrecioBase(ConfigPrecio? config) {
  final base = precioBaseDe(config);
  if (base == null) return null;
  final monto = base.precio == base.precio.roundToDouble()
      ? base.precio.toStringAsFixed(0)
      : base.precio.toStringAsFixed(2);
  return '$monto ${base.moneda}';
}
