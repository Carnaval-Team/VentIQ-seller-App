import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_colors.dart';
import '../../models/compra.dart';
import '../../models/supplier.dart';
import '../../services/compra_service.dart';
import '../../services/supplier_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/admin_drawer.dart';
import '../../widgets/product_selector_widget.dart';
import 'compras_widgets.dart';

/// Alta y edición de compras contra `fn_fdi_compra_crear` / `_editar`.
///
/// La edición recibe el [CompraDetalle] ya cargado por la pantalla de detalle:
/// así no se repite la lectura y el formulario sabe si la compra es editable.
class CompraFormScreen extends StatefulWidget {
  const CompraFormScreen({super.key, this.detalle});

  /// `null` = alta. No `null` = edición de esa compra.
  final CompraDetalle? detalle;

  @override
  State<CompraFormScreen> createState() => _CompraFormScreenState();
}

class _CompraFormScreenState extends State<CompraFormScreen> {
  final _service = CompraService();
  final _numeroFacturaCtrl = TextEditingController();
  final _tasaCtrl = TextEditingController(text: '1');
  final _observacionCtrl = TextEditingController();

  int? _idTienda;
  List<Supplier> _proveedores = const [];
  bool _cargandoProveedores = true;
  String? _errorProveedores;

  int? _idProveedor;
  DateTime? _fechaFactura;
  String _moneda = 'USD';
  String _modoLiquidacion = CompraModoLiquidacion.fondo.codigo;
  String _politicaPago = CompraPoliticaPago.alPagar.codigo;

  final List<_LineaForm> _lineasForm = [];
  final List<_AjusteForm> _ajustesForm = [];

  /// Una sola clave por alta, reutilizada en los reintentos del mismo
  /// formulario. La edición no usa idempotencia.
  String? _idempotencyKey;

  bool _guardando = false;

  bool get _esEdicion => widget.detalle != null;

  @override
  void initState() {
    super.initState();
    if (!_esEdicion) {
      _idempotencyKey = _service.newIdempotencyKey();
    } else {
      _hidratarDesdeDetalle(widget.detalle!);
    }
    _cargarContexto();
  }

  @override
  void dispose() {
    _numeroFacturaCtrl.dispose();
    _tasaCtrl.dispose();
    _observacionCtrl.dispose();
    for (final l in _lineasForm) {
      l.dispose();
    }
    for (final a in _ajustesForm) {
      a.dispose();
    }
    super.dispose();
  }

  void _hidratarDesdeDetalle(CompraDetalle detalle) {
    final c = detalle.compra;
    _idProveedor = c.idProveedor;
    _numeroFacturaCtrl.text = c.numeroFactura ?? '';
    _fechaFactura = c.fechaFactura;
    final moneda = c.monedaTotal.trim().toUpperCase();
    _moneda = const ['USD', 'CUP', 'EUR'].contains(moneda) ? moneda : 'USD';
    _tasaCtrl.text = _textoNumero(c.tasaFactura);
    _modoLiquidacion = c.modoLiquidacion;
    _politicaPago = c.politicaPago;
    _observacionCtrl.text = c.observacion ?? '';
    for (final l in detalle.lineas) {
      final form = _LineaForm(
        idProducto: l.idProducto,
        nombre: (l.producto ?? '').trim().isEmpty
            ? 'Producto #${l.idProducto}'
            : l.producto!,
        cantidad: _textoNumero(l.cantidad),
        costo: _textoNumero(l.costoUnitario),
      );
      form.escuchar(_alCambiar);
      _lineasForm.add(form);
    }
    for (final a in detalle.ajustes) {
      final form = _AjusteForm(
        base: a.base,
        reparto: a.reparto,
        origenPago: a.origenPago,
        valor: _textoNumero(a.valor),
      );
      form.escuchar(_alCambiar);
      _ajustesForm.add(form);
    }
  }

  Future<void> _cargarContexto() async {
    try {
      _idTienda ??= await UserPreferencesService().getIdTienda();
    } catch (_) {
      // Se reintenta en _cargarProveedores; el guardado valida la tienda.
    }
    await _cargarProveedores();
  }

  Future<void> _cargarProveedores() async {
    setState(() {
      _cargandoProveedores = true;
      _errorProveedores = null;
    });
    try {
      final proveedores = await SupplierService.getAllSuppliers(
        activeOnly: false,
      );
      if (!mounted) return;
      setState(() {
        _proveedores = proveedores;
        _cargandoProveedores = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoProveedores = false;
        _errorProveedores = _mensajeDe(e);
      });
    }
  }

  // ==========================================================================
  // Derivados
  // ==========================================================================

  String _mensajeDe(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '');
    return texto.isEmpty ? 'No se pudo completar la operación.' : texto;
  }

  static String _textoNumero(double valor) {
    if (valor == valor.roundToDouble()) return valor.toInt().toString();
    return valor.toString();
  }

  double get _tasaValor => _parseNumero(_tasaCtrl.text) ?? 0;

  TotalesCompra get _totalesPreview => calcularTotalesCompra([
    for (final l in _lineasForm)
      CompraLinea(
        idProducto: l.idProducto,
        cantidad: l.cantidadValor,
        costoUnitario: l.costoValor < 0 ? 0 : l.costoValor,
      ),
  ], _ajustesForm.map((a) => a.aAjuste()).toList());

  String get _monedaPreview => _moneda;

  void _alCambiar() {
    if (mounted) setState(() {});
  }

  // ==========================================================================
  // Líneas
  // ==========================================================================

  Future<void> _agregarProducto() async {
    final ancho = MediaQuery.sizeOf(context).width;
    final producto = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elegir producto'),
        contentPadding: const EdgeInsets.only(top: 8),
        content: SizedBox(
          width: ancho < comprasAnchoCompacto ? ancho * 0.8 : 520,
          height: 440,
          child: ProductSelectorWidget(
            searchHint: 'Buscar por nombre o SKU...',
            onProductSelected: (p) => Navigator.pop(ctx, p),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (producto == null || !mounted) return;

    final idCrudo = producto['id_producto'] ?? producto['id'];
    final id = idCrudo is num ? idCrudo.toInt() : int.tryParse('$idCrudo');
    if (id == null) {
      _snack('El producto elegido no trae identificador.', error: true);
      return;
    }
    final nombre =
        (producto['denominacion'] ?? producto['nombre_producto'] ?? '')
            .toString()
            .trim();
    final form = _LineaForm(
      idProducto: id,
      nombre: nombre.isEmpty ? 'Producto #$id' : nombre,
      cantidad: '1',
      costo: '0',
    );
    form.escuchar(_alCambiar);
    setState(() => _lineasForm.add(form));
  }

  void _quitarLinea(int index) {
    final linea = _lineasForm.removeAt(index);
    linea.dispose();
    setState(() {});
  }

  void _quitarAjuste(int index) {
    final ajuste = _ajustesForm.removeAt(index);
    ajuste.dispose();
    setState(() {});
  }

  void _agregarAjuste() {
    final form = _AjusteForm();
    form.escuchar(_alCambiar);
    setState(() => _ajustesForm.add(form));
  }

  // ==========================================================================
  // Guardado
  // ==========================================================================

  List<String> _validar() {
    final errores = <String>[];
    if (_idProveedor == null) {
      errores.add('Elige el proveedor de la compra.');
    }
    if (_lineasForm.isEmpty) {
      errores.add('Añade al menos una línea con un producto.');
    }
    for (var i = 0; i < _lineasForm.length; i++) {
      final l = _lineasForm[i];
      final cantidad = l.cantidadParse;
      if (cantidad == null || !(cantidad > 0)) {
        errores.add(
          'Línea ${i + 1} (${l.nombre}): la cantidad debe ser mayor que 0.',
        );
      }
      final costo = l.costoParse;
      if (costo == null || costo < 0) {
        errores.add(
          'Línea ${i + 1} (${l.nombre}): el costo unitario debe ser un número mayor o igual que 0.',
        );
      }
    }
    if (!(_tasaValor > 0)) {
      errores.add('La tasa de factura debe ser un número mayor que 0.');
    }
    for (var i = 0; i < _ajustesForm.length; i++) {
      final a = _ajustesForm[i];
      final valor = a.valorParse;
      if (valor == null || valor < 0) {
        errores.add(
          'Ajuste ${i + 1}: el valor debe ser un número mayor o igual que 0.',
        );
      }
    }
    return errores;
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final errores = _validar();
    if (errores.isNotEmpty) {
      await _mostrarErrores(errores);
      return;
    }
    final idTienda = _idTienda;
    if (idTienda == null) {
      _snack('No se pudo determinar la tienda del usuario.', error: true);
      return;
    }
    final idProveedor = _idProveedor;
    if (idProveedor == null) return;

    final lineas = [
      for (final l in _lineasForm)
        CompraLinea(
          idProducto: l.idProducto,
          cantidad: l.cantidadParse!,
          costoUnitario: l.costoParse!,
        ),
    ];
    final ajustes = [for (final a in _ajustesForm) a.aAjuste()];
    final numeroFactura = _numeroFacturaCtrl.text.trim();
    final observacion = _observacionCtrl.text.trim();

    setState(() => _guardando = true);
    try {
      if (_esEdicion) {
        final detalle = widget.detalle!;
        final r = await _service.editar(
          idCompra: detalle.idCompra,
          numeroFactura: numeroFactura.isEmpty ? null : numeroFactura,
          fechaFactura: _fechaFactura,
          monedaTotal: _moneda,
          tasaFactura: _tasaValor,
          lineas: lineas,
          ajustes: ajustes,
          observacion: observacion.isEmpty ? null : observacion,
        );
        if (!mounted) return;
        _snack(_mensajeGuardado('Compra actualizada', r));
        Navigator.pop(context, true);
        return;
      }

      final r = await _service.crear(
        idTienda: idTienda,
        idProveedor: idProveedor,
        numeroFactura: numeroFactura.isEmpty ? null : numeroFactura,
        fechaFactura: _fechaFactura,
        monedaTotal: _moneda,
        tasaFactura: _tasaValor,
        lineas: lineas,
        ajustes: ajustes,
        modoLiquidacion: _modoLiquidacion,
        politicaPago: _politicaPago,
        observacion: observacion.isEmpty ? null : observacion,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;

      if (r['duplicada'] == true) {
        final idCompra = r['id_compra'];
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Este envío ya se registró'),
            content: Text(
              'El servidor reconoció la clave de idempotencia de este formulario'
              '${idCompra == null ? '' : ' y devolvió la compra #$idCompra'}.\n\n'
              'No se creó una compra nueva. Revisa el listado antes de volver a intentarlo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      _snack(_mensajeGuardado('Compra creada', r));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack(_mensajeDe(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String _mensajeGuardado(String prefijo, Map<String, dynamic> r) {
    final numero = r['numero_compra'];
    final numeroTexto = numero == null ? '' : ' #$numero';
    final aterrizado = r['costo_aterrizado'];
    if (aterrizado is num) {
      return '$prefijo$numeroTexto · aterrizado ${formatearImporte(aterrizado)} $_moneda';
    }
    return '$prefijo$numeroTexto.';
  }

  Future<void> _mostrarErrores(List<String> errores) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revisa el formulario'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in errores)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e,
                            style: const TextStyle(fontSize: 13, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _snack(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final detalle = widget.detalle;
    if (detalle != null && !detalle.compra.esEditable) {
      return _pantallaNoEditable(detalle);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tamano = comprasTamanoDe(constraints.maxWidth);
        final conPanel = tamano == ComprasTamano.expandido;
        final compacto = tamano == ComprasTamano.compacto;

        final contenido = <Widget>[
          if (_esEdicion) _franjaEdicion(detalle!),
          _panelCabecera(tamano),
          _panelLineas(tamano),
          _panelAjustes(),
          _panelObservacion(),
          if (!conPanel) _panelTotales(tamano),
          if (!conPanel) const SizedBox(height: 8),
        ];

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: const BackButton(color: Colors.white),
            title: Text(
              _esEdicion
                  ? 'Editar compra #${detalle!.numeroCompra}'
                  : 'Nueva compra',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: AppColors.primary,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (conPanel)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton.icon(
                    onPressed: _guardando ? null : _guardar,
                    icon: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, color: Colors.white),
                    label: Text(
                      _esEdicion ? 'Guardar cambios' : 'Crear compra',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          drawer: const AdminDrawer(),
          bottomNavigationBar: conPanel ? null : _barraInferior(compacto),
          body: conPanel
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: contenido,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 360,
                        child: SingleChildScrollView(
                          child: _panelTotales(tamano),
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: contenido,
                  ),
                ),
        );
      },
    );
  }

  Widget _pantallaNoEditable(CompraDetalle detalle) {
    final c = detalle.compra;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Compra #${c.numeroCompra}'),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              chipEstadoCompra(c.estado),
              const SizedBox(height: 16),
              const Text(
                'Esta compra ya no se puede editar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Solo se editan las compras en estado «Creada». '
                'Esta está en «${c.estadoLegible}».',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _franjaEdicion(CompraDetalle detalle) {
    final c = detalle.compra;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: avisoCompras(
        'Compra #${c.numeroCompra} · ${c.estadoLegible}. Al guardar se '
        'reemplazan todas las líneas y ajustes de la compra.',
        icono: Icons.edit_note,
        color: AppColors.info,
      ),
    );
  }

  // ==========================================================================
  // Cabecera
  // ==========================================================================

  Widget _panelCabecera(ComprasTamano tamano) {
    final compacto = tamano == ComprasTamano.compacto;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras('Factura del proveedor'),
          if (compacto)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dropdownProveedor(),
                const SizedBox(height: 12),
                _campoNumeroFactura(),
                const SizedBox(height: 12),
                _campoFechaFactura(),
                const SizedBox(height: 12),
                _selectorMoneda(),
                const SizedBox(height: 12),
                _campoTasa(),
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 260, child: _dropdownProveedor()),
                SizedBox(width: 200, child: _campoNumeroFactura()),
                SizedBox(width: 210, child: _campoFechaFactura()),
                SizedBox(width: 230, child: _selectorMoneda()),
                SizedBox(width: 150, child: _campoTasa()),
              ],
            ),
          const SizedBox(height: 12),
          if (_esEdicion)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                pastillaCompras(
                  'Liquidación: ${CompraModoLiquidacion.etiquetaDe(_modoLiquidacion)}',
                  icono: Icons.account_balance,
                  color: AppColors.primary,
                ),
                pastillaCompras(
                  'Pago: ${CompraPoliticaPago.etiquetaDe(_politicaPago)}',
                  icono: Icons.schedule,
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Modo de liquidación',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    textoMetaCompras('Excluyentes: uno u otro'),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in CompraModoLiquidacion.values)
                      ChoiceChip(
                        label: Text(m.etiqueta),
                        selected: _modoLiquidacion == m.codigo,
                        onSelected: (_) =>
                            setState(() => _modoLiquidacion = m.codigo),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    initialValue: _politicaPago,
                    isExpanded: true,
                    isDense: true,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Política de pago',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: [
                      for (final p in CompraPoliticaPago.values)
                        DropdownMenuItem(
                          value: p.codigo,
                          child: Text(p.etiqueta),
                        ),
                    ],
                    onChanged: (valor) {
                      if (valor != null) setState(() => _politicaPago = valor);
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dropdownProveedor() {
    final ids = _proveedores.map((p) => p.id).toSet();
    final valor = ids.contains(_idProveedor) ? _idProveedor : null;
    if (_cargandoProveedores) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Proveedor',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text('Cargando proveedores...'),
      );
    }
    if (_errorProveedores != null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Proveedor',
          border: const OutlineInputBorder(),
          isDense: true,
          errorText: 'No se pudieron cargar los proveedores',
          suffixIcon: IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Reintentar',
            onPressed: _cargarProveedores,
          ),
        ),
        child: const Text('—'),
      );
    }
    return DropdownButtonFormField<int?>(
      initialValue: valor,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Proveedor *',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Elegir proveedor'),
        ),
        ..._proveedores.map(
          (p) => DropdownMenuItem<int?>(
            value: p.id,
            child: Text(p.denominacion, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _idProveedor = v),
      validator: (_) => _idProveedor == null ? 'Elige el proveedor' : null,
    );
  }

  Widget _campoNumeroFactura() {
    return TextField(
      controller: _numeroFacturaCtrl,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Nº de factura',
        hintText: 'Opcional',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _campoFechaFactura() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _elegirFechaFactura,
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          labelText: 'Fecha de factura',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: _fechaFactura == null
              ? const Icon(Icons.event, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Quitar fecha',
                  onPressed: () => setState(() => _fechaFactura = null),
                ),
        ),
        child: Text(
          _fechaFactura == null ? 'Sin fecha' : formatearFecha(_fechaFactura),
          style: TextStyle(
            fontSize: 14,
            color: _fechaFactura == null
                ? AppColors.textLight
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Future<void> _elegirFechaFactura() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaFactura ?? ahora,
      firstDate: DateTime(ahora.year - 4),
      lastDate: DateTime(ahora.year + 2),
      helpText: 'Fecha de factura',
    );
    if (fecha == null || !mounted) return;
    setState(() => _fechaFactura = fecha);
  }

  Widget _selectorMoneda() {
    return InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Moneda',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      child: Wrap(
        spacing: 6,
        children: [
          for (final m in const ['USD', 'CUP', 'EUR'])
            ChoiceChip(
              label: Text(m, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              selected: _moneda == m,
              onSelected: (_) => setState(() => _moneda = m),
            ),
        ],
      ),
    );
  }

  Widget _campoTasa() {
    return TextField(
      controller: _tasaCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Tasa factura',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _panelObservacion() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras('Observación'),
          TextField(
            controller: _observacionCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Notas internas de la compra (opcional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Líneas
  // ==========================================================================

  Widget _panelLineas(ComprasTamano tamano) {
    final compacto = tamano == ComprasTamano.compacto;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Líneas',
            trailing: pastillaCompras(
              '${_lineasForm.length} ${_lineasForm.length == 1 ? 'línea' : 'líneas'}',
              denso: true,
            ),
          ),
          if (!compacto && _lineasForm.isNotEmpty) _cabeceraLineas(),
          if (_lineasForm.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: textoMetaCompras(
                'Sin líneas todavía. Añade el primer producto para calcular la mercancía.',
              ),
            )
          else
            for (var i = 0; i < _lineasForm.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: compacto ? _lineaCompacta(i) : _lineaFila(i),
              ),
          const SizedBox(height: 4),
          _botonAgregarProducto(),
          const SizedBox(height: 6),
          textoMetaCompras(
            'El costo de línea lo calcula el sistema: cantidad × costo unitario. '
            'No es editable.',
          ),
        ],
      ),
    );
  }

  Widget _cabeceraLineas() {
    const estilo = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Expanded(flex: 4, child: Text('Producto', style: estilo)),
          const SizedBox(width: 90, child: Text('Cantidad', style: estilo)),
          const SizedBox(width: 12),
          const SizedBox(width: 110, child: Text('Costo unit.', style: estilo)),
          const SizedBox(width: 12),
          const SizedBox(width: 130, child: Text('Costo línea', style: estilo)),
          const SizedBox(width: 36, child: SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _lineaFila(int index) {
    final l = _lineasForm[index];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Producto #${l.idProducto}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 90,
          child: TextField(
            controller: l.cantidad,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: _decoracionCelda('Cantidad'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: TextField(
            controller: l.costo,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: _decoracionCelda('Costo unit.'),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 130, child: _costoLineaReadOnly(l)),
        SizedBox(
          width: 36,
          child: IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Quitar línea',
            color: AppColors.textSecondary,
            onPressed: () => _quitarLinea(index),
          ),
        ),
      ],
    );
  }

  Widget _lineaCompacta(int index) {
    final l = _lineasForm[index];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Quitar línea',
                color: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
                onPressed: () => _quitarLinea(index),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: l.cantidad,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: _decoracionCelda('Cantidad'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: l.costo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: _decoracionCelda('Costo unit.'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 12,
                color: AppColors.textLight,
              ),
              const SizedBox(width: 4),
              Text(
                'Costo línea: ${formatearImporte(l.costoValor * l.cantidadValor)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _decoracionCelda(String etiqueta) {
    return InputDecoration(
      isDense: true,
      labelText: etiqueta,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    );
  }

  Widget _costoLineaReadOnly(_LineaForm l) {
    final valor = l.cantidadValor * l.costoValor;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.lock_outline, size: 12, color: AppColors.textLight),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              formatearImporte(valor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonAgregarProducto() {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _agregarProducto,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.add_circle_outline, size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Buscar o escanear producto',
                style: TextStyle(fontSize: 13, color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // Ajustes
  // ==========================================================================

  Widget _panelAjustes() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Ajustes',
            trailing: TextButton.icon(
              onPressed: _agregarAjuste,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Añadir'),
            ),
          ),
          textoMetaCompras(
            'Flete, aduana, servicio de importadora... Cada ajuste declara quién lo paga.',
          ),
          const SizedBox(height: 8),
          if (_ajustesForm.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: textoMetaCompras(
                'Sin ajustes: el aterrizado es igual a la mercancía.',
              ),
            )
          else
            for (var i = 0; i < _ajustesForm.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _filaAjuste(i),
              ),
        ],
      ),
    );
  }

  /// Fila de ajuste que refluye con `Wrap`: en PC cabe en una línea, y en
  /// tablet/móvil se apila sin recortar ningún campo.
  Widget _filaAjuste(int index) {
    final a = _ajustesForm[index];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 130, child: _dropdownBase(a)),
          SizedBox(
            width: 110,
            child: TextField(
              controller: a.valor,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: _decoracionCelda('Valor'),
            ),
          ),
          SizedBox(width: 130, child: _dropdownReparto(a)),
          SizedBox(width: 180, child: _dropdownOrigen(a)),
          SizedBox(width: 140, child: _montoAjusteReadOnly(a)),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Quitar ajuste',
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: () => _quitarAjuste(index),
          ),
        ],
      ),
    );
  }

  Widget _dropdownBase(_AjusteForm a) {
    return DropdownButtonFormField<String>(
      initialValue: a.base,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Base',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      items: [
        for (final b in CompraBaseAjuste.values)
          DropdownMenuItem(value: b.codigo, child: Text(b.etiqueta)),
      ],
      onChanged: (valor) {
        if (valor != null) setState(() => a.base = valor);
      },
    );
  }

  Widget _dropdownReparto(_AjusteForm a) {
    return DropdownButtonFormField<String>(
      initialValue: a.reparto,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Reparto',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      items: [
        for (final r in CompraRepartoAjuste.values)
          DropdownMenuItem(value: r.codigo, child: Text(r.etiqueta)),
      ],
      onChanged: (valor) {
        if (valor != null) setState(() => a.reparto = valor);
      },
    );
  }

  Widget _dropdownOrigen(_AjusteForm a) {
    return DropdownButtonFormField<String>(
      initialValue: a.origenPago,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Origen de pago',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      items: [
        for (final o in OrigenPagoAjuste.values)
          DropdownMenuItem(value: o.codigo, child: Text(o.etiqueta)),
      ],
      onChanged: (valor) {
        if (valor != null) setState(() => a.origenPago = valor);
      },
    );
  }

  Widget _montoAjusteReadOnly(_AjusteForm a) {
    final totales = _totalesPreview;
    final monto = montoAjusteCompra(
      a.aAjuste(),
      mercancia: totales.mercancia,
      cantidad: _cantidadTotal,
    );
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 12, color: AppColors.textLight),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Monto ${formatearImporte(monto)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double get _cantidadTotal =>
      _lineasForm.fold<double>(0, (suma, l) => suma + l.cantidadValor);

  // ==========================================================================
  // Panel de cifras
  // ==========================================================================

  Widget _panelTotales(ComprasTamano tamano) {
    final totales = _totalesPreview;
    final apilado = tamano == ComprasTamano.expandido;
    return panelCompras(
      children: [
        tituloSeccionCompras(
          'Cifras',
          trailing: pastillaCompras(
            _monedaPreview,
            denso: true,
            icono: Icons.payments_outlined,
          ),
        ),
        bloqueTotalesCompra(
          totales: totales,
          moneda: _monedaPreview,
          apilado: apilado,
          helperAterrizado:
              'Incluye los ajustes pagados por la wallet de importadora.',
        ),
        const SizedBox(height: 10),
        avisoCompras(
          'Previsualización calculada en el dispositivo. Los totales definitivos '
          'los calcula la base de datos al guardar la compra.',
          color: AppColors.info,
        ),
        if (tamano == ComprasTamano.expandido) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_esEdicion ? 'Guardar cambios' : 'Crear compra'),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ],
    );
  }

  Widget _barraInferior(bool compacto) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            if (!compacto) ...[
              Expanded(
                child: Text(
                  'Financiado ${formatearImporte(_totalesPreview.financiado)} $_monedaPreview · '
                  'Aterrizado ${formatearImporte(_totalesPreview.aterrizado)} $_monedaPreview',
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ] else
              const Spacer(),
            TextButton(
              onPressed: _guardando ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_esEdicion ? 'Guardar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Modelos de edición (solo UI: no son el contrato de la RPC)
// ===========================================================================

double? _parseNumero(String texto) {
  final limpio = texto.trim().replaceAll(',', '.');
  if (limpio.isEmpty) return null;
  return double.tryParse(limpio);
}

class _LineaForm {
  final int idProducto;
  final String nombre;
  final TextEditingController cantidad;
  final TextEditingController costo;

  _LineaForm({
    required this.idProducto,
    required this.nombre,
    String cantidad = '1',
    String costo = '0',
  }) : cantidad = TextEditingController(text: cantidad),
       costo = TextEditingController(text: costo);

  double? get cantidadParse => _parseNumero(cantidad.text);
  double? get costoParse => _parseNumero(costo.text);

  double get cantidadValor => cantidadParse ?? 0;
  double get costoValor => costoParse ?? 0;

  void escuchar(VoidCallback alCambiar) {
    cantidad.addListener(alCambiar);
    costo.addListener(alCambiar);
  }

  void dispose() {
    cantidad.dispose();
    costo.dispose();
  }
}

class _AjusteForm {
  String base;
  String reparto;
  String origenPago;
  final TextEditingController valor;

  _AjusteForm({
    this.base = 'global',
    this.reparto = 'valor',
    this.origenPago = 'fondo',
    String valor = '0',
  }) : valor = TextEditingController(text: valor);

  double? get valorParse => _parseNumero(valor.text);
  double get valorValor => valorParse ?? 0;

  void escuchar(VoidCallback alCambiar) => valor.addListener(alCambiar);

  CompraAjuste aAjuste() => CompraAjuste(
    base: base,
    valor: valorValor,
    reparto: reparto,
    origenPago: origenPago,
  );

  void dispose() => valor.dispose();
}
