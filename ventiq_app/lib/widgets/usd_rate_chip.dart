import 'package:flutter/material.dart';

import '../services/currency_service.dart';

/// Chip con la tasa del dólar del día.
///
/// Se extrae a un widget propio porque en el Home viejo había **tres copias**
/// de esto (móvil, web y una muerta en el detalle de producto) con dos tamaños
/// distintos. Aquí hay una sola, con parámetro de tamaño.
///
/// Tocar el chip vuelve a pedir la tasa: es lo que espera el vendedor cuando el
/// número no cuadra con el cartel de la tienda.
class UsdRateChip extends StatefulWidget {
  const UsdRateChip({super.key, this.compacto = true});

  /// `true` = versión pequeña para el Home; `false` = la del listado.
  final bool compacto;

  @override
  State<UsdRateChip> createState() => _UsdRateChipState();
}

class _UsdRateChipState extends State<UsdRateChip> {
  double _tasa = 0;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (_cargando) return;
    setState(() => _cargando = true);
    try {
      final double tasa = await CurrencyService.getUsdRate();
      if (!mounted) return;
      setState(() => _tasa = tasa);
    } catch (e) {
      debugPrint('⚠️ No se pudo obtener la tasa USD: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sin tasa no se pinta nada: un chip que diga "$1 = 0" es peor que no
    // tener chip, porque el vendedor lo tomaría por bueno.
    if (_tasa <= 0) return const SizedBox.shrink();

    final double fuente = widget.compacto ? 12 : 14;
    final double icono = widget.compacto ? 16 : 20;
    final EdgeInsets relleno = widget.compacto
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 10);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _cargar,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          padding: relleno,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: const Color(0xFFE0E6ED)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x1A2B3A67),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.attach_money_rounded,
                size: icono,
                color: const Color(0xFF43A047),
              ),
              const SizedBox(width: 6),
              Text(
                '1 USD = ${_tasa.toStringAsFixed(0)} CUP',
                style: TextStyle(
                  fontSize: fuente,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF14224A),
                ),
              ),
              if (_cargando) ...<Widget>[
                const SizedBox(width: 6),
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
