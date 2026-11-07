import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../services/moneda_venta_service.dart';
import '../../services/quick_add_service.dart';
import '../../theme/ventiq_home_theme.dart';

/// Qué decidió el vendedor en la hoja de cantidad.
enum QuickAddSalidaTipo { agregado, requiereDetalle }

/// Resultado que devuelve la hoja al cerrarse.
class QuickAddSalida {
  const QuickAddSalida._(this.tipo, {this.cantidad = 0, this.producto});

  factory QuickAddSalida.agregado(double cantidad, Product producto) =>
      QuickAddSalida._(
        QuickAddSalidaTipo.agregado,
        cantidad: cantidad,
        producto: producto,
      );

  factory QuickAddSalida.requiereDetalle(Product producto) =>
      QuickAddSalida._(QuickAddSalidaTipo.requiereDetalle, producto: producto);

  final QuickAddSalidaTipo tipo;
  final double cantidad;
  final Product? producto;
}

/// Hoja de cantidad para añadir un producto al carrito sin abrir el detalle.
///
/// La abre el «+» de cada fila del drawer del Home. Flujo:
///
///  1. mientras carga el detalle enseña el nombre y un progreso;
///  2. si el producto **no** es inequívoco (varias presentaciones/ubicaciones,
///     promoción, elaborado...), se cierra sola y el llamador abre el detalle
///     con el producto ya cargado;
///  3. si es inequívoco, deja elegir cantidad con −/+ o tecleándola, avisa del
///     stock disponible y muestra el total;
///  4. «Agregar» mete la línea en el carrito; si con la cantidad final aparece
///     una promoción, también manda al detalle.
///
/// No conoce Supabase: recibe [evaluar] y [agregar] ya resueltos, así se puede
/// probar la interacción con dobles.
class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({
    super.key,
    required this.nombreProducto,
    required this.evaluar,
    required this.agregar,
  });

  /// Nombre que se pinta en la cabecera mientras carga el detalle. Sirve tanto
  /// para la fila del drawer (`HomeProducto`) como para los resultados de la
  /// búsqueda global (`Product`).
  final String nombreProducto;

  final Future<QuickAddEvaluacion> Function() evaluar;

  final Future<QuickAddResultado> Function(
    QuickAddPreparado preparado,
    double cantidad,
  )
  agregar;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final TextEditingController _cantidadCtrl = TextEditingController(text: '1');

  QuickAddEvaluacion? _evaluacion;
  bool _cargando = true;
  bool _agregando = false;
  String? _error;

  double get _cantidad {
    final String texto = _cantidadCtrl.text.replaceAll(',', '.').trim();
    return double.tryParse(texto) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _evaluar();
  }

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _evaluar() async {
    try {
      final QuickAddEvaluacion evaluacion = await widget.evaluar();
      if (!mounted) return;

      if (evaluacion.estado == QuickAddEstado.requiereDetalle) {
        Navigator.of(
          context,
        ).pop(QuickAddSalida.requiereDetalle(evaluacion.producto));
        return;
      }

      setState(() {
        _evaluacion = evaluacion;
        _cargando = false;
        if (evaluacion.estado == QuickAddEstado.sinStock) {
          _error = evaluacion.motivo ?? 'Sin stock disponible.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo preparar el producto.\nInténtalo de nuevo.';
      });
    }
  }

  Future<void> _agregar() async {
    final QuickAddPreparado? preparado = _evaluacion?.preparado;
    if (preparado == null || _agregando) return;

    final double cantidad = _cantidad;
    if (cantidad <= 0) {
      setState(() => _error = 'La cantidad debe ser mayor que cero.');
      return;
    }
    if (cantidad > preparado.stockDisponible + 1e-9) {
      setState(
        () =>
            _error =
                'Solo hay ${_formato(preparado.stockDisponible)} disponibles.',
      );
      return;
    }

    setState(() {
      _agregando = true;
      _error = null;
    });

    try {
      final QuickAddResultado resultado = await widget.agregar(
        preparado,
        cantidad,
      );
      if (!mounted) return;

      if (resultado.requiereDetalle) {
        Navigator.of(context).pop(
          QuickAddSalida.requiereDetalle(
            resultado.producto ?? preparado.producto,
          ),
        );
        return;
      }

      Navigator.of(
        context,
      ).pop(QuickAddSalida.agregado(cantidad, preparado.producto));
    } on QuickAddException catch (e) {
      if (!mounted) return;
      setState(() {
        _agregando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _agregando = false;
        _error = 'No se pudo agregar al carrito. Inténtalo de nuevo.';
      });
    }
  }

  void _cambiarCantidad(double delta) {
    final QuickAddPreparado? preparado = _evaluacion?.preparado;
    final double actual = _cantidad <= 0 ? 1 : _cantidad;
    double nueva = actual + delta;
    if (nueva < 1) nueva = 1;
    final double? maximo = preparado?.stockDisponible;
    if (maximo != null && nueva > maximo) nueva = maximo;
    _cantidadCtrl.text = _formato(nueva);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final double altoTeclado = MediaQuery.viewInsetsOf(context).bottom;
    final QuickAddPreparado? preparado = _evaluacion?.preparado;

    return Padding(
      padding: EdgeInsets.only(bottom: altoTeclado),
      child: Material(
        color: VentiqHomeTheme.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: VentiqHomeTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            preparado?.producto.denominacion ??
                                widget.nombreProducto,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              color: VentiqHomeTheme.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: VentiqHomeTheme.textSecondary,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (_cargando) ...<Widget>[
                      const SizedBox(height: 6),
                      const LinearProgressIndicator(minHeight: 3),
                      const SizedBox(height: 12),
                      const Text(
                        'Comprobando presentación y ubicación…',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: VentiqHomeTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (_error != null && preparado == null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: VentiqHomeTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                    ] else if (preparado != null) ...<Widget>[
                      _detallePreparado(preparado),
                      const SizedBox(height: 14),
                      _selectorCantidad(preparado),
                      const SizedBox(height: 14),
                      _total(preparado),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: VentiqHomeTheme.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _agregando ? null : _agregar,
                        style: FilledButton.styleFrom(
                          backgroundColor: VentiqHomeTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon:
                            _agregando
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(
                                  Icons.add_shopping_cart_rounded,
                                  size: 18,
                                ),
                        label: Text(
                          _agregando ? 'Agregando…' : 'Agregar al carrito',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detallePreparado(QuickAddPreparado preparado) {
    final String presentacion =
        preparado.factorPresentacion > 1
            ? 'Presentación única · factor ${_formato(preparado.factorPresentacion)}'
            : 'Presentación única';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            presentacion,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: VentiqHomeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Ubicación: ${preparado.ubicacion}',
            style: const TextStyle(
              fontSize: 12,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Disponible: ${_formato(preparado.stockDisponible)}',
            style: const TextStyle(
              fontSize: 12,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorCantidad(QuickAddPreparado preparado) {
    return Row(
      children: <Widget>[
        _BotonCantidad(
          icono: Icons.remove_rounded,
          tooltip: 'Quitar uno',
          onTap: () => _cambiarCantidad(-1),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _cantidadCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: VentiqHomeTheme.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Cantidad',
              filled: true,
              fillColor: VentiqHomeTheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: VentiqHomeTheme.border),
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        const SizedBox(width: 10),
        _BotonCantidad(
          icono: Icons.add_rounded,
          tooltip: 'Añadir uno',
          onTap: () => _cambiarCantidad(1),
        ),
      ],
    );
  }

  Widget _total(QuickAddPreparado preparado) {
    final double total = preparado.precioUnitario * _cantidad;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        const Text(
          'Total',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: VentiqHomeTheme.textSecondary,
          ),
        ),
        Text(
          MonedaVentaService.formatearPrecio(total),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: VentiqHomeTheme.primary,
          ),
        ),
      ],
    );
  }

  static String _formato(double valor) =>
      valor == valor.roundToDouble()
          ? valor.toStringAsFixed(0)
          : valor.toStringAsFixed(2);
}

class _BotonCantidad extends StatelessWidget {
  const _BotonCantidad({
    required this.icono,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icono;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VentiqHomeTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: VentiqHomeTheme.border),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icono, size: 20),
        color: VentiqHomeTheme.primary,
      ),
    );
  }
}
