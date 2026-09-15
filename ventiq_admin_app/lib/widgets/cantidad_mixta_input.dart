import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/presentacion_cadena_service.dart';

/// Una linea capturada: cuanto se movio de una presentacion concreta.
class LineaMixta {
  final PresentacionCadena presentacion;
  final double cantidad;

  /// Precio de UNA unidad de esta presentacion (el precio de una caja, si la
  /// linea es en cajas). Null cuando el formulario no captura precios.
  ///
  /// Se captura por presentacion en vez de derivarlo del precio base x factor
  /// porque una caja no cuesta exactamente 12 veces la unidad: hay descuento por
  /// volumen. Derivarlo seria reintroducir por el lado del dinero el mismo
  /// aplanado que la Fase 1 elimino del inventario.
  final double? precioUnitario;

  const LineaMixta({
    required this.presentacion,
    required this.cantidad,
    this.precioUnitario,
  });

  /// Equivalente en unidades base de esta linea sola.
  double get equivalenteBase => cantidad * presentacion.factorRel;

  /// Importe de la linea.
  double get importe => (precioUnitario ?? 0) * cantidad;
}

/// Captura de cantidades por presentacion: un campo por eslabon de la cadena.
///
/// FASE 2 de presentaciones (docs/PLAN_PRESENTACIONES_INVENTARIO.md).
///
/// Reemplaza el patron "un dropdown de presentacion + un campo de cantidad", que
/// obligaba a agregar el mismo producto dos veces para entrar 4 cajas y 4
/// unidades. Aca se escriben las dos en el mismo formulario y salen como dos
/// lineas, cada una con su `id_presentacion`.
///
/// Lo que NO hace, a proposito:
///   - no convierte nada a la presentacion base (eso murio en la Fase 1);
///   - no decide el orden de la cadena ni los factores: los pide a
///     `fn_presentaciones_producto` via [PresentacionCadenaService];
///   - no arma el texto del equivalente con logica propia de plurales cuando
///     puede mostrar el que ya calculo el SQL.
class CantidadMixtaInput extends StatefulWidget {
  final int idProducto;

  /// Se llama en cada cambio con las lineas que tienen cantidad > 0.
  final ValueChanged<List<LineaMixta>> onChanged;

  /// Saldo actual para mostrar de referencia (opcional). Si se pasa, cada campo
  /// muestra "disponible: N" y se avisa cuando lo que se pide excede el saldo
  /// propio de esa presentacion.
  final StockMixto? stockActual;

  /// En egresos conviene avisar que el servidor puede abrir empaques; en
  /// recepciones no aplica.
  final bool avisarRebalanceo;

  /// Si true, cada fila con cantidad tambien pide su precio.
  ///
  /// Se usa en recepcion. El precio va POR PRESENTACION porque una caja no
  /// cuesta 12 veces la unidad (descuento por volumen); derivarlo del precio
  /// base seria el mismo aplanado que la Fase 1 saco del inventario.
  final bool capturarPrecio;

  /// Etiqueta de la moneda para los campos de precio ('USD', 'CUP', ...).
  final String? monedaLabel;

  /// Cantidades iniciales por `id_presentacion` (para editar una linea ya
  /// agregada).
  final Map<int, double>? inicial;

  /// Precios iniciales por `id_presentacion`.
  final Map<int, double>? preciosIniciales;

  /// Precio sugerido cuando no hay historial por presentacion (p. ej. el ultimo
  /// precio de compra del producto). Se usa solo para prellenar la fila base.
  final double? precioSugeridoBase;

  const CantidadMixtaInput({
    super.key,
    required this.idProducto,
    required this.onChanged,
    this.stockActual,
    this.avisarRebalanceo = false,
    this.capturarPrecio = false,
    this.monedaLabel,
    this.inicial,
    this.preciosIniciales,
    this.precioSugeridoBase,
  });

  @override
  State<CantidadMixtaInput> createState() => _CantidadMixtaInputState();
}

class _CantidadMixtaInputState extends State<CantidadMixtaInput> {
  List<PresentacionCadena> _cadena = [];
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, TextEditingController> _precioControllers = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarCadena();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final c in _precioControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarCadena() async {
    final cadena = await PresentacionCadenaService.cadena(widget.idProducto);
    if (!mounted) return;

    for (final p in cadena) {
      final inicial = widget.inicial?[p.idPresentacion];
      _controllers[p.idPresentacion] = TextEditingController(
        text: (inicial != null && inicial > 0) ? _fmt(inicial) : '',
      );

      if (widget.capturarPrecio) {
        // Prioridad: precio ya capturado > precio_promedio de esa presentacion
        // > el sugerido (solo para la base). Nunca se deriva base x factor.
        final pIni = widget.preciosIniciales?[p.idPresentacion];
        final sugerido = pIni ?? (p.esBase ? widget.precioSugeridoBase : null);
        _precioControllers[p.idPresentacion] = TextEditingController(
          text: (sugerido != null && sugerido > 0)
              ? sugerido.toStringAsFixed(2)
              : '',
        );
      }
    }

    setState(() {
      _cadena = cadena;
      _cargando = false;
    });

    // Si venia con valores iniciales, notificar de entrada.
    if (widget.inicial != null && widget.inicial!.isNotEmpty) {
      _notificar();
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double _valorDe(int idPresentacion) {
    final txt = _controllers[idPresentacion]?.text.trim().replaceAll(',', '.');
    if (txt == null || txt.isEmpty) return 0.0;
    return double.tryParse(txt) ?? 0.0;
  }

  double? _precioDe(int idPresentacion) {
    if (!widget.capturarPrecio) return null;
    final txt = _precioControllers[idPresentacion]?.text.trim().replaceAll(
      ',',
      '.',
    );
    if (txt == null || txt.isEmpty) return null;
    return double.tryParse(txt);
  }

  List<LineaMixta> get _lineas {
    final out = <LineaMixta>[];
    for (final p in _cadena) {
      final v = _valorDe(p.idPresentacion);
      if (v > 0) {
        out.add(
          LineaMixta(
            presentacion: p,
            cantidad: v,
            precioUnitario: _precioDe(p.idPresentacion),
          ),
        );
      }
    }
    return out;
  }

  double get _equivalenteTotal =>
      _lineas.fold(0.0, (s, l) => s + l.equivalenteBase);

  void _notificar() => widget.onChanged(_lineas);

  /// Nombre de la presentacion base, para rotular el equivalente.
  String get _nombreBase {
    for (final p in _cadena) {
      if (p.esBase) return p.nombre;
    }
    return _cadena.isNotEmpty ? _cadena.last.nombre : 'unidad';
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_cadena.isEmpty) {
      // Producto sin presentaciones configuradas. No se inventa una: se avisa,
      // porque escribir sin id_presentacion deja al SQL resolviendo la base y
      // eso puede no ser lo que el usuario espera.
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade800, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Este producto no tiene presentaciones configuradas. '
                'Configúrelas en la ficha del producto antes de moverlo.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.inventory_2, size: 18, color: AppColors.primary),
            const SizedBox(width: 6),
            const Text(
              'Cantidad por presentación',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const Spacer(),
            if (widget.stockActual != null)
              Flexible(
                child: Text(
                  'Actual: ${widget.stockActual!.texto}',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Un campo por eslabon, del empaque mas grande al mas chico.
        ..._cadena.map(_buildCampo),

        const SizedBox(height: 8),
        _buildEquivalente(),

        if (widget.avisarRebalanceo && _hayFaltanteEnAlgunaPresentacion())
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildAvisoRebalanceo(),
          ),
      ],
    );
  }

  Widget _buildCampo(PresentacionCadena p) {
    final disponible = widget.stockActual?.saldoDe(p.idPresentacion);
    final pedido = _valorDe(p.idPresentacion);
    final excede =
        disponible != null && pedido > disponible && widget.avisarRebalanceo;
    final equivalencia = p.esBase
        ? 'Equivale a 1 $_nombreBase'
        : '1 ${p.nombre} = ${_fmt(p.factorRel)} $_nombreBase';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: AppColors.surface.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  p.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (p.esBase) _buildEstadoChip('Base', AppColors.primary),
                _buildEstadoChip(
                  p.esFraccionable ? 'Fraccionable' : 'Enteros',
                  p.esFraccionable ? Colors.teal : AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(equivalencia, style: _equivalenciaStyle),
            if (disponible != null)
              Text(
                'Disponible: ${_fmt(disponible)} ${p.nombre}',
                style: _disponibleStyle(excede),
              ),
            const SizedBox(height: 10),
            _buildCamposCaptura(p, pedido, excede),
          ],
        ),
      ),
    );
  }

  static const _equivalenciaStyle = TextStyle(
    fontSize: 11,
    color: AppColors.textSecondary,
  );

  TextStyle _disponibleStyle(bool excede) => TextStyle(
    fontSize: 11,
    color: excede ? Colors.orange.shade800 : AppColors.textSecondary,
  );

  Widget _buildEstadoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCamposCaptura(PresentacionCadena p, double pedido, bool excede) {
    final cantidad = _buildCantidadField(p, excede);
    final precio = _buildPrecioField(p, pedido);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = widget.capturarPrecio && constraints.maxWidth >= 380;
        final campos = horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cantidad),
                  const SizedBox(width: 10),
                  Expanded(child: precio!),
                ],
              )
            : Column(
                children: [
                  cantidad,
                  if (widget.capturarPrecio) ...[
                    const SizedBox(height: 10),
                    precio!,
                  ],
                ],
              );

        final precioValor = _precioDe(p.idPresentacion) ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            campos,
            if (widget.capturarPrecio && pedido > 0 && precioValor > 0)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 2),
                child: Text(
                  '${_fmt(pedido)} × ${precioValor.toStringAsFixed(2)} = '
                  '${(pedido * precioValor).toStringAsFixed(2)}'
                  '${widget.monedaLabel != null ? ' ${widget.monedaLabel}' : ''}',
                  style: _equivalenciaStyle,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCantidadField(PresentacionCadena p, bool excede) {
    return TextFormField(
      controller: _controllers[p.idPresentacion],
      decoration: InputDecoration(
        labelText: 'Cantidad',
        hintText: '0',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: const OutlineInputBorder(),
        suffixIcon: excede
            ? Tooltip(
                message: 'Más de lo que hay suelto en esta presentación',
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.orange.shade800,
                ),
              )
            : null,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) {
        setState(() {});
        _notificar();
      },
    );
  }

  Widget? _buildPrecioField(PresentacionCadena p, double pedido) {
    if (!widget.capturarPrecio) return null;
    return TextFormField(
      controller: _precioControllers[p.idPresentacion],
      decoration: InputDecoration(
        labelText:
            'Precio${widget.monedaLabel != null ? ' (${widget.monedaLabel})' : ''}',
        hintText: '0.00',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: const OutlineInputBorder(),
        errorText: pedido > 0 && (_precioDe(p.idPresentacion) ?? 0) <= 0
            ? 'Falta'
            : null,
        errorStyle: const TextStyle(fontSize: 10),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) {
        setState(() {});
        _notificar();
      },
    );
  }

  Widget _buildEquivalente() {
    final lineas = _lineas;

    if (lineas.isEmpty) {
      return const Text(
        'Escriba al menos una cantidad',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }

    // Formato acordado en el plan: mixto + equivalente en la misma linea.
    //   "4 Cajas + 4 Unidades  ·  = 52 Unidades"
    final mixto = lineas
        .map((l) => '${_fmt(l.cantidad)} ${l.presentacion.nombre}')
        .join(' + ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            mixto,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.primary,
            ),
          ),
          Text(
            '· Equivalente: ${_fmt(_equivalenteTotal)} $_nombreBase',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          if (widget.capturarPrecio && _importeTotal > 0)
            Text(
              '· Total: ${_importeTotal.toStringAsFixed(2)}'
              '${widget.monedaLabel != null ? ' ${widget.monedaLabel}' : ''}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
        ],
      ),
    );
  }

  double get _importeTotal => _lineas.fold(0.0, (s, l) => s + l.importe);

  bool _hayFaltanteEnAlgunaPresentacion() {
    if (widget.stockActual == null) return false;
    for (final l in _lineas) {
      final disp = widget.stockActual!.saldoDe(l.presentacion.idPresentacion);
      if (l.cantidad > disp) return true;
    }
    return false;
  }

  Widget _buildAvisoRebalanceo() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Falta saldo suelto en alguna presentación. Al confirmar, el '
              'sistema abrirá el empaque mayor y lo dejará registrado.',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }
}
