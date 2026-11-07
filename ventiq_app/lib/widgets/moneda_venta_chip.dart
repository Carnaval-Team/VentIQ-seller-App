import 'package:flutter/material.dart';

import '../services/currency_service.dart';
import '../services/moneda_venta_service.dart';
import '../utils/price_utils.dart';

/// Chip para elegir la **moneda de venta** de este teléfono.
///
/// Decisión B: la moneda elegida fija la visualización de precios y la moneda de
/// cobro por defecto del checkout. Se persiste con [MonedaVentaService].
///
/// Se oculta sola cuando la tienda solo acepta una divisa con tasa (el caso
/// mayoritario), así que las tiendas de siempre no ven ningún control extra.
/// La excepción es la tienda que **fuerza** la divisa: ahí el chip se muestra
/// bloqueado, porque el vendedor tiene que entender por qué ya no puede
/// cambiarla.
class MonedaVentaChip extends StatefulWidget {
  const MonedaVentaChip({super.key, this.onChanged});

  /// Se avisa al cambiar para que la pantalla que lo contiene refresque sus
  /// precios sin esperar a reconstruirse entera.
  final ValueChanged<String>? onChanged;

  @override
  State<MonedaVentaChip> createState() => _MonedaVentaChipState();
}

class _MonedaVentaChipState extends State<MonedaVentaChip> {
  String _actual = PriceUtils.baseCurrency;

  /// Divisa impuesta por la tienda, o `null` si el chip es libre.
  String? _forzada;

  List<Map<String, dynamic>> _monedas = const [];
  Map<String, double> _tasas = const {};
  bool _cargando = true;
  bool _abierto = false;

  /// Divisas que la tienda acepta **y** tienen tasa resoluble.
  List<String> get _disponibles {
    final base = PriceUtils.baseCurrency;
    return _monedas
        .map((m) => (m['codigo'] ?? '').toString().trim().toUpperCase())
        .where((c) => c.isNotEmpty && (c == base || (_tasas[c] ?? 0) > 0))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final monedas = await CurrencyService.getMonedasTienda();
      final tasas = await CurrencyService.getRatesForStore();

      final disponibles = monedas
          .map((m) => (m['codigo'] ?? '').toString().trim().toUpperCase())
          .where(
            (c) =>
                c.isNotEmpty &&
                (c == PriceUtils.baseCurrency || (tasas[c] ?? 0) > 0),
          )
          .toList();

      // El chip y el formateador tienen que decir lo mismo. Sin esto, el chip
      // montado en una pantalla a la que se entra directo (productos, pedidos)
      // mostraría una divisa mientras los precios seguirían en CUP.
      //
      // Solo se resuelve si la consulta trajo algo: si falla la red,
      // `disponibles` queda vacío y no se debe degradar a CUP un formateador
      // que el Home ya había configurado bien. Se usa el mismo método que el
      // arranque del Home, que es el único que decide si la tienda bloquea la
      // divisa.
      final actual = disponibles.isEmpty
          ? MonedaVentaService.actual
          : await MonedaVentaService.aplicarParaTienda(
              disponibles: disponibles,
              tasasDisponibles: tasas,
            );

      if (!mounted) return;
      setState(() {
        _monedas = monedas;
        _tasas = tasas;
        _actual = actual;
        _forzada = MonedaVentaService.forzada;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  Future<void> _elegir() async {
    // Con la divisa forzada no hay nada que elegir. La guarda es redundante
    // con el `build`, pero deja el método seguro ante cualquier llamada.
    if (_forzada != null) return;

    final opciones = _disponibles;
    if (opciones.length < 2 || _abierto) return;

    _abierto = true;
    final elegida = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Moneda de venta',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Los precios se mostrarán en esta moneda y será la moneda '
                  'de cobro por defecto. Puedes cambiarla por línea en el cobro.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              ...opciones.map((codigo) {
                final tasa = _tasas[codigo] ?? 1;
                return ListTile(
                  title: Text(codigo),
                  subtitle: codigo == PriceUtils.baseCurrency
                      ? const Text('Moneda base')
                      : Text('1 $codigo = ${tasa.toStringAsFixed(2)} '
                          '${PriceUtils.baseCurrency}'),
                  trailing: codigo == _actual
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () => Navigator.of(context).pop(codigo),
                );
              }),
            ],
          ),
        );
      },
    );
    _abierto = false;

    if (elegida == null || elegida == _actual) return;
    await MonedaVentaService.guardar(elegida);
    // Actualizar el estado en memoria es lo que hace que `formatearPrecio`
    // devuelva la divisa nueva: el `onChanged` solo repinta, no convierte.
    MonedaVentaService.configurar(moneda: elegida, tasasDisponibles: _tasas);
    if (!mounted) return;
    setState(() => _actual = elegida);
    widget.onChanged?.call(elegida);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const SizedBox.shrink();
    }

    // Bloqueado por la tienda: se muestra (no se esconde) para que el vendedor
    // que venía cambiando la divisa entienda que ya no puede, en vez de creer
    // que el control desapareció por un fallo.
    final forzada = _forzada;
    if (forzada != null) {
      return _buildBloqueado(forzada);
    }

    if (_disponibles.length < 2) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: 'Moneda de venta',
      child: InkWell(
        onTap: _elegir,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white54),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _actual,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  /// Chip **no interactivo** para la divisa que impone la tienda.
  ///
  /// Mismo formato que el libre (mismo tamaño y contraste) con un candado en
  /// lugar de la flecha: el vendedor ve la divisa activa y, en el tooltip, el
  /// motivo de que no se pueda cambiar.
  Widget _buildBloqueado(String moneda) {
    return Tooltip(
      message: 'La tienda fuerza esta moneda. No puedes cambiarla aquí.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white54),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 12, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              moneda,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}