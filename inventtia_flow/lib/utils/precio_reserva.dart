import '../models/config_precio.dart';

class ResultadoPrecioReserva {
  final double total;
  final double unitario;
  final String moneda;
  final String origen; // 'base' | 'regla' | 'sin_config'
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

  static ResultadoPrecioReserva calcular({
    required ConfigPrecio config,
    required Map<String, dynamic> datosAdicionales,
    String? moneda,
    int cantidad = 1,
  }) {
    final cant = cantidad < 1 ? 1 : cantidad;
    final monedas = config.monedas.isEmpty ? ['USD'] : config.monedas;
    var mon = moneda ?? config.monedaDefault;
    if (!monedas.contains(mon)) mon = config.monedaDefault;

    for (final regla in config.reglas) {
      if (regla.siClave.isEmpty || regla.preciosOpcion.isEmpty) continue;
      final valor = datosAdicionales[regla.siClave];
      if (valor == null) continue;
      final vs = valor.toString();
      final preciosOpc = regla.preciosOpcion[vs];
      if (preciosOpc == null || preciosOpc.isEmpty) continue;
      final unit = preciosOpc[mon] ?? preciosOpc[config.monedaDefault] ?? 0;
      return ResultadoPrecioReserva(
        total: unit * cant,
        unitario: unit,
        moneda: mon,
        origen: 'regla',
        siClave: regla.siClave,
      );
    }

    final unitBase =
        config.preciosBase[mon] ??
        config.preciosBase[config.monedaDefault] ??
        0;
    return ResultadoPrecioReserva(
      total: unitBase * cant,
      unitario: unitBase,
      moneda: mon,
      origen: config.preciosBase.isEmpty ? 'sin_config' : 'base',
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
