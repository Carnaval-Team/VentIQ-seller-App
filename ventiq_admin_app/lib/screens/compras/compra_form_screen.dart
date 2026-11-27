import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_colors.dart';
import '../../models/compra.dart';
import '../../models/fondo_inversion.dart';
import '../../models/supplier.dart';
import '../../services/compra_service.dart';
import '../../services/compras_costos_calculo.dart';
import '../../services/currency_service.dart';
import '../../services/financial_service.dart';
import '../../services/fondo_inversion_service.dart';
import '../../services/supplier_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/admin_drawer.dart';
import '../../widgets/compra_aportes_panel.dart';
import '../../widgets/fdi_recepcion_fuentes.dart';
import '../../widgets/product_selector_widget.dart';
import '../suppliers/add_edit_supplier_screen.dart';
import 'compra_ayuda.dart';
import 'compra_tutorial.dart';
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

  // Claves de los campos que resalta el tutorial. Son `GlobalKey` porque el
  // recorrido necesita medir el widget real en pantalla, no solo pintarlo.
  final _claveProveedor = GlobalKey();
  final _claveNumeroFactura = GlobalKey();
  final _claveFecha = GlobalKey();
  final _claveMoneda = GlobalKey();
  final _claveTasa = GlobalKey();
  final _claveModoLiquidacion = GlobalKey();
  final _clavePoliticaPago = GlobalKey();
  final _claveLineas = GlobalKey();
  final _claveAjustes = GlobalKey();
  final _clavePreviewCosto = GlobalKey();
  final _clavePanelReserva = GlobalKey();
  final _claveTotales = GlobalKey();
  final _claveBotonTutorial = GlobalKey();

  /// Burbuja de aviso viva, para cerrarla al salir de la pantalla.
  AvisoTutorial? _avisoTutorial;

  bool _avisoTutorialAbierto = false;

  /// Ya se mostró el aviso en esta visita: no se repite al volver al pulsar el
  /// icono si el usuario lo cerró.
  bool _avisoTutorialMostrado = false;

  int? _idTienda;
  List<Supplier> _proveedores = const [];
  bool _cargandoProveedores = true;
  String? _errorProveedores;

  /// Tipos de costo del nomenclador (`app_cont_tipo_costo`), para que el ajuste
  /// diga «Flete» y no «Ajuste 1». Solo lectura: el cliente no los edita.
  List<Map<String, dynamic>> _tiposCosto = const [];

  int? _idProveedor;
  DateTime? _fechaFactura;
  String _moneda = 'USD';
  String _modoLiquidacion = CompraModoLiquidacion.fondo.codigo;
  String _politicaPago = CompraPoliticaPago.alPagar.codigo;

  /// Tasa USD→CUP configurada para la tienda. Es el valor por defecto de una
  /// factura en CUP; el usuario puede desbloquearla con el botón de editar.
  double? _tasaTiendaCup;
  bool _tasaEditable = false;

  /// Reserva del fondo desde el alta (modo fondo, compra nueva).
  List<FdiSaldo> _saldosFondo = const [];
  bool _cargandoSaldos = false;
  bool _reservarAlCrear = false;
  List<FdiFuenteRecepcion> _fuentesReserva = const [];
  late final String _claveReserva = _service.newIdempotencyKey();

  /// En modo inversores, al crear se abre el panel de aportes (activado por
  /// defecto). Así no hay que ir al detalle para repartir el total.
  bool _aportesAlCrear = true;

  final List<_LineaForm> _lineasForm = [];
  final List<_AjusteForm> _ajustesForm = [];

  /// Una sola clave por alta, reutilizada en los reintentos del mismo
  /// formulario. La edición no usa idempotencia.
  String? _idempotencyKey;

  bool _guardando = false;

  /// Alta rápida de proveedor en curso (deshabilita el botón «+»).
  bool _creandoProveedor = false;

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
    _cerrarAvisoTutorial();
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
        idTipoCosto: a.idTipoCosto,
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
    await Future.wait([
      _cargarProveedores(),
      _cargarTiposCosto(),
      _cargarTasaTienda(),
      _cargarSaldosFondo(),
    ]);
    if (mounted) _avisarUnaVez();
  }

  /// Tasa USD→CUP de la tienda: la misma que usa el TPV. Una factura en CUP
  /// nace con esta tasa y queda bloqueada; el botón de editar la desbloquea.
  Future<void> _cargarTasaTienda() async {
    try {
      final tasa = await CurrencyService.getEffectiveUsdToCupRate();
      if (!mounted) return;
      setState(() => _tasaTiendaCup = tasa > 0 ? tasa : null);
    } catch (_) {
      // Sin tasa de tienda el campo queda editable y el usuario la escribe.
    }
  }

  /// Saldos del fondo para ofrecer la reserva en el mismo alta.
  Future<void> _cargarSaldosFondo() async {
    final tienda = _idTienda;
    if (tienda == null) return;
    setState(() => _cargandoSaldos = true);
    try {
      final resultado = await FondoInversionService().saldos(tienda);
      if (!mounted) return;
      final disponibles = resultado.saldos
          .where((s) => s.saldo > 0 && s.idMedioPago != null)
          .toList();
      setState(() {
        _saldosFondo = disponibles;
        // Por defecto la reserva va activada: es el paso que sigue al alta.
        if (_modoLiquidacion == 'fondo' && disponibles.isNotEmpty) {
          _reservarAlCrear = true;
        }
      });
    } catch (_) {
      // Sin saldos no se ofrece reservar; la compra se crea igual.
    } finally {
      if (mounted) setState(() => _cargandoSaldos = false);
    }
  }

  /// Primera vez en el formulario: cuelga la burbuja del icono para que se vea
  /// que hay tutorial. Si el usuario la cierra, no vuelve en esta visita.
  void _avisarUnaVez() {
    if (_avisoTutorialMostrado) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _avisoTutorialMostrado) return;
      // Solo si el icono está en la barra (en el alta no editable no lo está).
      if (_claveBotonTutorial.currentContext == null) return;
      _mostrarAvisoTutorial();
    });
  }

  /// Nomenclador de costos. Si falla, el ajuste sigue funcionando: solo pierde
  /// la etiqueta del concepto.
  Future<void> _cargarTiposCosto() async {
    try {
      final tipos = await FinancialService().getCostTypes(idTienda: _idTienda);
      if (!mounted) return;
      setState(() => _tiposCosto = tipos);
    } catch (_) {
      // Sin catálogo, el ajuste se declara por base y valor; no se bloquea.
    }
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

  /// Alta rápida de proveedor sin salir de la compra: abre la misma pantalla
  /// del módulo Proveedores, recarga la lista y deja elegido el recién creado.
  Future<void> _crearProveedor() async {
    setState(() => _creandoProveedor = true);
    try {
      final creado = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AddEditSupplierScreen()),
      );
      if (!mounted || creado != true) return;

      await _cargarProveedores();
      if (!mounted || _proveedores.isEmpty) return;

      // El nuevo suele ser el de `id` más alto: se preselecciona para no
      // obligar a buscarlo en el desplegable recién recargado.
      final nuevo = _proveedores.reduce((a, b) => a.id >= b.id ? a : b);
      setState(() => _idProveedor = nuevo.id);
      _snack('Proveedor «${nuevo.denominacion}» creado y seleccionado.');
    } finally {
      if (mounted) setState(() => _creandoProveedor = false);
    }
  }

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

    // Costo sugerido = el último con el que se compró ese producto. Se puede
    // corregir en la línea; solo evita teclear de cero.
    double? ultimo;
    final tienda = _idTienda;
    if (tienda != null) {
      try {
        ultimo = await _service.ultimoCostoCompra(
          idTienda: tienda,
          idProducto: id,
        );
      } catch (_) {
        // Sin histórico, la línea nace en 0 y el usuario escribe.
      }
    }
    if (!mounted) return;

    final form = _LineaForm(
      idProducto: id,
      nombre: nombre.isEmpty ? 'Producto #$id' : nombre,
      cantidad: '1',
      costo: ultimo != null && ultimo > 0 ? _textoNumero(ultimo) : '0',
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
    final form = _AjusteForm(
      reparto: 'cantidad',
      origenPago: _modoLiquidacion == 'inversores' ? 'externo' : 'fondo',
    );
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
    if (_numeroFacturaCtrl.text.trim().isEmpty) {
      errores.add('Escribe el número de factura del proveedor.');
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
    if (_reservarAlCrear && _modoLiquidacion != 'inversores') {
      final error = FdiFuenteRecepcion.validar(
        _fuentesReserva,
        _totalesPreview.financiado,
        _monedaPreview,
      );
      if (error != null) errores.add('Reserva del fondo: $error');
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

      final idCompra = (r['id_compra'] as num?)?.toInt();
      String? avisoReserva;
      if (_reservarAlCrear &&
          _modoLiquidacion != 'inversores' &&
          idCompra != null) {
        final totalServidor =
            (r['total_financiado'] as num?)?.toDouble() ??
            _totalesPreview.financiado;
        final error = FdiFuenteRecepcion.validar(
          _fuentesReserva,
          totalServidor,
          _monedaPreview,
        );
        if (error != null) {
          avisoReserva =
              'La compra quedó creada, pero la reserva no se envió: $error';
        } else {
          try {
            await _service.reservar(
              idCompra: idCompra,
              fuentes: [
                for (final f in _fuentesReserva)
                  FuenteReserva(
                    idCuenta: f.saldo.idCuenta,
                    idMedioPago: f.saldo.idMedioPago!,
                    moneda: f.saldo.moneda,
                    monto: f.monto,
                    tasaATotal: f.tasaARef,
                  ),
              ],
              idempotencyKey: _claveReserva,
            );
            avisoReserva = 'Compra creada y reservada del fondo.';
          } catch (e) {
            avisoReserva = 'La compra quedó creada, pero la reserva falló: $e';
          }
        }
      }

      if (_modoLiquidacion == 'inversores' &&
          _aportesAlCrear &&
          idCompra != null &&
          mounted) {
        await _abrirAportes(idCompra);
        if (!mounted) return;
      }

      if (avisoReserva != null && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reserva del fondo'),
            content: Text(
              '$avisoReserva\n\nLa compra ya existe; puede reintentar la '
              'reserva desde su detalle.',
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
      if (!mounted) return;
      _snack(avisoReserva ?? _mensajeGuardado('Compra creada', r));
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
  // Tutorial guiado
  // ==========================================================================

  /// Recorrido campo por campo. Cada paso deja el resto en sombra y explica
  /// para qué sirve lo que está resaltado.
  List<PasoTutorialCompra> _pasosTutorial() {
    return [
      PasoTutorialCompra(
        clave: _claveProveedor,
        titulo: 'Proveedor',
        icono: Icons.storefront_outlined,
        texto:
            '¿A quién le compras? Elige uno de la lista o pulsa el «+» de al '
            'lado para crear uno nuevo sin salir de esta pantalla. Es '
            'obligatorio: la compra tiene que saber a quién se le debe.',
      ),
      PasoTutorialCompra(
        clave: _claveNumeroFactura,
        titulo: 'Nº de factura',
        icono: Icons.receipt_long_outlined,
        texto:
            'El número que trae el papel del proveedor. Es obligatorio: sin él '
            'no se puede guardar la compra, y el sistema evita que cargues dos '
            'veces la misma factura del mismo proveedor.',
      ),
      PasoTutorialCompra(
        clave: _claveFecha,
        titulo: 'Fecha de factura',
        icono: Icons.event_outlined,
        texto:
            'El día en que el proveedor emitió la factura, no el día en que la '
            'estás capturando. Sirve para los reportes por periodo.',
      ),
      PasoTutorialCompra(
        clave: _claveMoneda,
        titulo: 'Moneda de la factura',
        icono: Icons.currency_exchange,
        texto:
            'La moneda en la que viene la factura. Los costos de las líneas y '
            'de los ajustes se escriben en esta misma moneda.',
      ),
      PasoTutorialCompra(
        clave: _claveTasa,
        titulo: 'Tasa de la factura',
        icono: Icons.trending_up,
        texto:
            'Cuántas unidades de esta moneda equivalen a 1 USD. En USD es 1. En '
            'CUP se toma la tasa extraoficial configurada de la tienda y queda '
            'bloqueada; el botón de editar permite cambiarla y queda congelada '
            'en esta compra.',
      ),
      if (!_esEdicion) ...[
        PasoTutorialCompra(
          clave: _claveModoLiquidacion,
          titulo: 'Modo de liquidación',
          icono: Icons.account_balance_outlined,
          texto:
              '¿Quién pone el dinero? «Fondo» lo paga la empresa con sus '
              'cuentas. «Inversores» lo cubren los aportes de inversores y el '
              'fondo no se toca. Es excluyente: uno u otro.',
        ),
        PasoTutorialCompra(
          clave: _clavePoliticaPago,
          titulo: 'Política de pago',
          icono: Icons.schedule_outlined,
          texto:
              'Cuándo se le paga al proveedor: de una vez al hacer la compra, o '
              'cuando llegue la mercancía. No cambia los importes, cambia el '
              'momento en que sale el dinero.',
        ),
      ],
      PasoTutorialCompra(
        clave: _claveLineas,
        titulo: 'Líneas de la compra',
        icono: Icons.list_alt,
        texto:
            'Qué compraste y a cómo. En cada línea pones la cantidad y el costo '
            'de UNA unidad; el costo de la línea lo calcula el sistema '
            '(cantidad × costo unitario) y no se edita.',
      ),
      PasoTutorialCompra(
        clave: _claveAjustes,
        titulo: 'Ajustes',
        icono: Icons.tune,
        texto:
            'Los costos de traer la mercancía: flete, aduana, seguro, el '
            'servicio de la importadora. Se reparten por cantidad de unidades y '
            'quién los paga lo decide el modo de liquidación. Son los que '
            'convierten el precio de compra en costo aterrizado.',
      ),
      PasoTutorialCompra(
        clave: _clavePreviewCosto,
        titulo: 'Costo por unidad',
        icono: Icons.price_change_outlined,
        texto:
            'Aquí ves, antes de guardar, cuánto sube cada unidad con los ajustes '
            'repartidos. Es la cuenta que de verdad importa: el costo de compra '
            'no es el costo final del producto.',
      ),
      if (!_esEdicion)
        PasoTutorialCompra(
          clave: _clavePanelReserva,
          titulo: 'Financiación al crear',
          icono: Icons.account_balance_wallet_outlined,
          texto:
              'En modo fondo reservas aquí mismo el dinero, sin ir al detalle. '
              'En modo inversores, al guardar se abre el panel de aportes para '
              'repartir el total entre los inversores.',
        ),
      PasoTutorialCompra(
        clave: _claveTotales,
        titulo: 'Las cifras',
        icono: Icons.summarize_outlined,
        texto:
            'Mercancía es lo que cuestan los productos. Financiado es lo que '
            'tiene que poner el fondo. Aterrizado del documento es mercancía + '
            'ajustes; los cargos de la recepción se suman en el detalle. Son '
            'números distintos: nunca se suman entre ellos.',
      ),
    ];
  }

  Future<void> _abrirTutorial() async {
    _cerrarAvisoTutorial();
    if (!mounted) return;
    await mostrarTutorialCompra(context, pasos: _pasosTutorial());
  }

  /// Icono de la barra: pulsarlo cuelga debajo la burbuja «¿Tienes dudas? Ve el
  /// tutorial», y de esa burbuja arranca el recorrido.
  Widget _botonTutorial() {
    return IconButton(
      key: _claveBotonTutorial,
      icon: const Icon(Icons.school_outlined),
      tooltip: 'Tutorial de esta pantalla',
      onPressed: () {
        if (_avisoTutorialAbierto) {
          _cerrarAvisoTutorial();
        } else {
          _mostrarAvisoTutorial();
        }
      },
    );
  }

  /// Colgar la burbuja del icono. `alAceptar` arranca el recorrido.
  void _mostrarAvisoTutorial() {
    if (_avisoTutorialAbierto) return;
    _avisoTutorialMostrado = true;
    // Si el ancla no está montada el helper devuelve `null`: no se marca como
    // abierto para que no quede un estado mintiendo sobre lo que se ve.
    final aviso = insertarAvisoTutorial(
      context,
      ancla: _claveBotonTutorial,
      alAceptar: _abrirTutorial,
      alCerrar: _alCerrarAvisoPorUsuario,
    );
    if (aviso == null) return;
    _avisoTutorial = aviso;
    setState(() => _avisoTutorialAbierto = true);
  }

  /// Lo llama la burbuja cuando el usuario la cierra. Aquí la entrada **ya**
  /// está retirada, así que solo se sincroniza el estado de la pantalla; si se
  /// cerrara la entrada otra vez, Flutter aborta con «An OverlayEntry should be
  /// removed only once».
  void _alCerrarAvisoPorUsuario() {
    _avisoTutorial = null;
    if (!mounted) return;
    if (!_avisoTutorialAbierto) return;
    setState(() => _avisoTutorialAbierto = false);
  }

  /// Retirada programática (al salir de la pantalla, al arrancar el tutorial).
  /// Es idempotente: `AvisoTutorial.cerrar` aguanta llamadas repetidas.
  void _cerrarAvisoTutorial() {
    final aviso = _avisoTutorial;
    _avisoTutorial = null;
    if (aviso == null || aviso.cerrada) return;
    aviso.cerrar();
    if (mounted && _avisoTutorialAbierto) {
      setState(() => _avisoTutorialAbierto = false);
    }
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
          KeyedSubtree(
            key: _clavePreviewCosto,
            child: _panelPreviewCosto(),
          ),
          if (!_esEdicion)
            KeyedSubtree(
              key: _clavePanelReserva,
              child: _panelFinanciacion(),
            ),
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
              _botonTutorial(),
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
          tituloSeccionCompras(
            'Factura del proveedor',
            trailing: textoMetaCompras('* obligatorio'),
          ),
          if (compacto)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _selectorProveedor(),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _claveNumeroFactura,
                  child: _campoNumeroFactura(),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(key: _claveFecha, child: _campoFechaFactura()),
                const SizedBox(height: 12),
                KeyedSubtree(key: _claveMoneda, child: _selectorMoneda()),
                const SizedBox(height: 12),
                KeyedSubtree(key: _claveTasa, child: _campoTasa()),
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(width: 300, child: _selectorProveedor()),
                SizedBox(
                  width: 200,
                  child: KeyedSubtree(
                    key: _claveNumeroFactura,
                    child: _campoNumeroFactura(),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: KeyedSubtree(
                    key: _claveFecha,
                    child: _campoFechaFactura(),
                  ),
                ),
                SizedBox(
                  width: 250,
                  child: KeyedSubtree(
                    key: _claveMoneda,
                    child: _selectorMoneda(),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: KeyedSubtree(key: _claveTasa, child: _campoTasa()),
                ),
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
                KeyedSubtree(
                  key: _claveModoLiquidacion,
                  child: _bloqueModoLiquidacion(),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _clavePoliticaPago,
                  child: _bloquePoliticaPago(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Fondo | Inversores, excluyentes, con la explicación al lado.
  Widget _bloqueModoLiquidacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Modo de liquidación',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            botonAyuda(ayudaModoLiquidacion, tamano: 16),
          ],
        ),
        textoMetaCompras('Excluyentes: uno u otro. No se cambia después.'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final m in CompraModoLiquidacion.values)
              ChoiceChip(
                label: Text(m.etiqueta),
                selected: _modoLiquidacion == m.codigo,
                onSelected: (_) => setState(() {
                  _modoLiquidacion = m.codigo;
                  _reservarAlCrear =
                      m.codigo == 'fondo' && _saldosFondo.isNotEmpty;
                  _aportesAlCrear = m.codigo == 'inversores';
                  // El origen de los ajustes lo decide el modo, no una elección
                  // aparte: fondo lo financia; inversores lo declaran externo.
                  for (final a in _ajustesForm) {
                    a.origenPago =
                        m.codigo == 'inversores' ? 'externo' : 'fondo';
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }

  /// Momento del pago, con la explicación al lado.
  Widget _bloquePoliticaPago() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Política de pago',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            botonAyuda(ayudaPoliticaPago, tamano: 16),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 280,
          child: DropdownButtonFormField<String>(
            initialValue: _politicaPago,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: [
              for (final p in CompraPoliticaPago.values)
                DropdownMenuItem(value: p.codigo, child: Text(p.etiqueta)),
            ],
            onChanged: (valor) {
              if (valor != null) setState(() => _politicaPago = valor);
            },
          ),
        ),
      ],
    );
  }

  /// Proveedor con su alta rápida al lado: el desplegable solo no basta cuando
  /// el proveedor es nuevo y todavía no está en el catálogo.
  Widget _selectorProveedor() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: KeyedSubtree(
            key: _claveProveedor,
            child: _dropdownProveedor(),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Tooltip(
            message: 'Crear proveedor',
            child: OutlinedButton(
              onPressed: _creandoProveedor ? null : _crearProveedor,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(46, 46),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Icon(Icons.add_business_outlined, size: 20),
            ),
          ),
        ),
      ],
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
        hintText: 'Obligatorio',
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
        suffixIcon: botonAyuda(ayudaMonedaFactura, tamano: 16),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
      ),
      child: Wrap(
        spacing: 6,
        children: [
          for (final m in const ['USD', 'CUP', 'EUR'])
            ChoiceChip(
              label: Text(m, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              selected: _moneda == m,
              onSelected: (_) => setState(() {
                _moneda = m;
                _tasaEditable = false;
                // En USD la tasa es 1 por definición: dejarla escrita evita que
                // se guarde una tasa vieja de cuando era CUP.
                if (m == 'USD') {
                  _tasaCtrl.text = '1';
                } else if (m == 'CUP' && _tasaTiendaCup != null) {
                  // La tasa configurada de la tienda, bloqueada por defecto.
                  _tasaCtrl.text = _textoNumero(_tasaTiendaCup!);
                } else {
                  // EUR (o CUP sin tasa configurada): se escribe a mano. Se
                  // limpia el 1 de USD para no guardarlo como tasa de otra
                  // moneda por descuido.
                  _tasaEditable = true;
                  _tasaCtrl.clear();
                }
              }),
            ),
        ],
      ),
    );
  }

  Widget _campoTasa() {
    final esUsd = _moneda == 'USD';
    final bloqueada = esUsd || !_tasaEditable;
    final ayuda = esUsd
        ? 'En USD la tasa es 1'
        : (_moneda == 'CUP' && _tasaTiendaCup != null && !_tasaEditable
            ? 'Tasa configurada de la tienda: '
                '${_textoNumero(_tasaTiendaCup!)} CUP por 1 USD'
            : 'Unidades de $_moneda por 1 USD');
    return TextField(
      controller: _tasaCtrl,
      readOnly: bloqueada,
      enabled: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Tasa factura',
        helperText: ayuda,
        helperMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!esUsd)
              IconButton(
                tooltip: _tasaEditable
                    ? 'Volver a la tasa de la tienda'
                    : 'Editar la tasa',
                icon: Icon(
                  _tasaEditable ? Icons.lock_open : Icons.edit_outlined,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _tasaEditable = !_tasaEditable;
                  if (!_tasaEditable &&
                      _moneda == 'CUP' &&
                      _tasaTiendaCup != null) {
                    _tasaCtrl.text = _textoNumero(_tasaTiendaCup!);
                  }
                }),
              ),
            botonAyuda(ayudaTasaFactura, tamano: 16),
          ],
        ),
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
      child: KeyedSubtree(
        key: _claveLineas,
        child: panelCompras(
          children: [
            tituloSeccionCompras(
              'Líneas',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  pastillaCompras(
                    '${_lineasForm.length} ${_lineasForm.length == 1 ? 'línea' : 'líneas'}',
                    denso: true,
                  ),
                  botonAyuda(ayudaLineasCompra, tamano: 16),
                ],
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
              'El costo de una línea es cantidad × costo unitario. Lo calcula el '
              'sistema y no se edita.',
            ),
          ],
        ),
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
      child: KeyedSubtree(
        key: _claveAjustes,
        child: panelCompras(
          children: [
            tituloSeccionCompras(
              'Ajustes del costo',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  botonAyuda(ayudaAjustes, tamano: 16),
                  if (_ajustesForm.isNotEmpty)
                    TextButton.icon(
                      onPressed: _agregarAjuste,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Añadir'),
                    ),
                ],
              ),
            ),
            textoMetaCompras(
              'Costos de traer la mercancía: flete, aduana, seguro, el servicio '
              'de la importadora. No son productos, pero se suman al costo de '
              'cada línea.',
            ),
            const SizedBox(height: 10),
            if (_ajustesForm.isEmpty)
              _invitacionAjustes()
            else ...[
              for (var i = 0; i < _ajustesForm.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _filaAjuste(i),
                ),
              if (_ajustesForm.length < 8)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _agregarAjuste,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Añadir otro ajuste'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Estado vacío del panel. Antes bastaba un texto gris; ahora explica en dos
  /// líneas para qué sirve y ofrece el primer paso, porque «Ajustes» era el
  /// bloque que nadie entendía.
  Widget _invitacionAjustes() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '¿Y esto para qué?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Si el proveedor te cobró solo la mercancía, no hay nada que poner '
            'aquí: el aterrizado será igual a la mercancía. Si además pagaste '
            'flete, aduana o un % a la importadora, se declaran aquí para que '
            'el costo real de cada producto los incluya.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _agregarAjuste,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Añadir un ajuste'),
            ),
          ),
        ],
      ),
    );
  }

  /// Fila de ajuste como tarjeta: los campos arriba, el importe resuelto abajo
  /// en palabras. Antes los cinco campos iban sueltos en un `Wrap` y el usuario
  /// no sabía cuál era el número que contaba.
  Widget _filaAjuste(int index) {
    final a = _ajustesForm[index];
    final totales = _totalesPreview;
    final monto = montoAjusteCompra(
      a.aAjuste(),
      mercancia: totales.mercancia,
      cantidad: _cantidadTotal,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Ajuste ${index + 1}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Spacer(),
              Tooltip(
                message: 'Quitar ajuste',
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.textSecondary,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _quitarAjuste(index),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Cada campo con su etiqueta de mostrador y su ⓘ al lado.
          LayoutBuilder(
            builder: (context, restricciones) {
              final ancho = restricciones.maxWidth;
              final enFila = ancho >= 760;
              final concepto = _dropdownConcepto(a);

              final campoConcepto = concepto == null
                  ? null
                  : SizedBox(
                      width: enFila ? 180 : double.infinity,
                      child: concepto,
                    );
              final campoBase = SizedBox(
                width: enFila ? 190 : double.infinity,
                child: _dropdownBase(a),
              );
              final campoValor = SizedBox(
                width: enFila ? 110 : double.infinity,
                child: _campoValorAjuste(a),
              );

              final piezas = [
                if (campoConcepto != null) campoConcepto,
                campoBase,
                campoValor,
              ];

              if (enFila) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.start,
                  children: piezas,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < piezas.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    piezas[i],
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          _montoAjusteResuelto(a, monto),
        ],
      ),
    );
  }

  /// El importe que de verdad cuenta, en una frase.
  Widget _montoAjusteResuelto(_AjusteForm a, double monto) {
    final moneda = _monedaPreview;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 12, color: AppColors.textLight),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _explicacionAjuste(a, monto, moneda),
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// «10 % de 1.000,00 = 100,00 USD, lo paga el fondo».
  String _explicacionAjuste(_AjusteForm a, double monto, String moneda) {
    return explicacionAjusteCompra(
      base: a.base,
      valor: a.valorValor,
      monto: monto,
      mercancia: _totalesPreview.mercancia,
      cantidad: _cantidadTotal,
      moneda: moneda,
      origenPago: a.origenPago,
    );
  }

  Widget _campoValorAjuste(_AjusteForm a) {
    final sufijo = switch (a.base) {
      'porcentaje' => '%',
      'unidad' => 'u',
      _ => null,
    };
    return TextField(
      controller: a.valor,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: _decoracionCelda('Valor').copyWith(suffixText: sufijo),
    );
  }

  /// «Qué costo es»: Flete, Aduana, Importadora... Sale del nomenclador.
  /// Si el catálogo no cargó, el desplegable no se pinta y el ajuste se
  /// declara igual por base y valor.
  Widget? _dropdownConcepto(_AjusteForm a) {
    if (_tiposCosto.isEmpty) return null;
    return DropdownButtonFormField<int?>(
      initialValue: a.idTipoCosto,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Qué costo es',
        helperText: 'Flete, aduana, importadora...',
        helperMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Sin clasificar'),
        ),
        for (final t in _tiposCosto)
          DropdownMenuItem<int?>(
            value: (t['id'] as num).toInt(),
            child: Text(
              t['denominacion']?.toString() ?? '',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (valor) => setState(() => a.idTipoCosto = valor),
    );
  }

  /// «Cómo se calcula»: el nombre de la base en lenguaje llano.
  Widget _dropdownBase(_AjusteForm a) {
    return DropdownButtonFormField<String>(
      initialValue: a.base,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Cómo se calcula',
        helperText: _textoBase(a.base),
        helperMaxLines: 2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        suffixIcon: botonAyuda(ayudaBaseAjuste, tamano: 15),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 28,
        ),
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

  String _textoBase(String base) => switch (base) {
    'porcentaje' => 'Un % de la mercancía',
    'unidad' => 'Un importe por unidad',
    _ => 'Un importe fijo total',
  };

  double get _cantidadTotal =>
      _lineasForm.fold<double>(0, (suma, l) => suma + l.cantidadValor);

  // ==========================================================================
  // Panel de cifras
  // ==========================================================================

  /// «0,50 → 0,70»: lo que el usuario necesita ver para entender que un ajuste
  /// de 5.000 sobre 25.000 unidades sube 0,20 a CADA unidad.
  Widget _panelPreviewCosto() {
    if (_lineasForm.isEmpty) return const SizedBox.shrink();
    final cantidad = _cantidadTotal;
    if (cantidad <= 0) return const SizedBox.shrink();
    final totales = _totalesPreview;

    var ajustesTotal = 0.0;
    for (final a in _ajustesForm) {
      ajustesTotal += montoAjusteCompra(
        a.aAjuste(),
        mercancia: totales.mercancia,
        cantidad: cantidad,
      );
    }
    final ajustesPorUnidad = ComprasCostosCalculo.ajustesPorUnidad(
      ajustesTotal: ajustesTotal,
      cantidadTotal: cantidad,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Costo por unidad',
            trailing: pastillaCompras('estimado', denso: true),
          ),
          textoMetaCompras(
            'Los ajustes se reparten por cantidad. Si recibes toda la compra, '
            'cada unidad queda así:',
          ),
          const SizedBox(height: 8),
          for (final l in _lineasForm)
            _filaPreviewCosto(l, ajustesPorUnidad),
        ],
      ),
    );
  }

  Widget _filaPreviewCosto(_LineaForm l, double ajustesPorUnidad) {
    final base = l.costoValor;
    final finalUnit = ComprasCostosCalculo.costoUnitarioAterrizado(
      costoUnitario: base,
      ajustesTotal: ajustesPorUnidad,
      cantidadTotal: 1,
    );
    final delta = finalUnit - base;
    final pct = base > 0 ? (delta / base) * 100 : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${formatearImporte(base)} → ${formatearImporte(finalUnit)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(
            '+${formatearImporte(delta)} (${pct.toStringAsFixed(1)} %)',
            style: TextStyle(
              fontSize: 12,
              color: delta > 0 ? AppColors.warning : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Reserva del fondo en el mismo alta: el dinero se compromete al crear y el
  /// pago se confirma después, igual que desde el detalle.
  Widget _panelReserva() {
    if (_modoLiquidacion == 'inversores') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Reservar del fondo',
            trailing: pastillaCompras('opcional', denso: true),
          ),
          if (_cargandoSaldos)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _reservarAlCrear,
              onChanged: _guardando || _saldosFondo.isEmpty
                  ? null
                  : (v) => setState(() => _reservarAlCrear = v),
              title: const Text(
                'Reservar al crear la compra',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _saldosFondo.isEmpty
                    ? 'No hay saldos del fondo disponibles.'
                    : 'El dinero se compromete al guardar; el pago se '
                        'confirma después.',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          if (_reservarAlCrear && _saldosFondo.isNotEmpty) ...[
            const SizedBox(height: 8),
            FdiRecepcionFuentes(
              saldos: _saldosFondo,
              total: _totalesPreview.financiado,
              moneda: _monedaPreview,
              enabled: !_guardando,
              tasaUsdCup: _tasaTiendaCup,
              onChanged: (fuentes) =>
                  setState(() => _fuentesReserva = fuentes),
            ),
          ],
        ],
      ),
    );
  }

  Widget _panelFinanciacion() {
    if (_modoLiquidacion == 'inversores') return _panelAportesCreacion();
    return _panelReserva();
  }

  /// En modo inversores, el alta ofrece registrar los aportes al crear y abre
  /// el mismo panel del detalle, para no obligar a pasar por ahí.
  Widget _panelAportesCreacion() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Aportes de inversores',
            trailing: pastillaCompras('opcional', denso: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _aportesAlCrear,
            onChanged: _guardando
                ? null
                : (v) => setState(() => _aportesAlCrear = v),
            title: const Text(
              'Registrar aportes al crear la compra',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Al guardar se abre el panel para repartir el total entre los '
              'inversores. Puedes cerrarlo y hacerlo después desde el detalle.',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirAportes(int idCompra) async {
    final tienda = _idTienda;
    if (!mounted || tienda == null) return;
    final size = MediaQuery.sizeOf(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width: size.width < 940 ? size.width - 24 : 900,
          height: size.height < 720 ? size.height - 24 : 640,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Aportes de inversores',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: CompraAportesPanel(
                  idCompra: idCompra,
                  moneda: _monedaPreview,
                  estado: 'creada',
                  modoLiquidacion: 'inversores',
                  idTienda: tienda,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelTotales(ComprasTamano tamano) {
    final totales = _totalesPreview;
    final apilado = tamano == ComprasTamano.expandido;
    return KeyedSubtree(
      key: _claveTotales,
      child: panelCompras(
        children: [
          tituloSeccionCompras(
            'Cifras',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                pastillaCompras(
                  _monedaPreview,
                  denso: true,
                  icono: Icons.payments_outlined,
                ),
                botonAyuda(ayudaCifrasCompra, tamano: 16),
              ],
            ),
          ),
          bloqueTotalesCompra(
            totales: totales,
            moneda: _monedaPreview,
            apilado: apilado,
            helperAterrizado:
                'Mercancía + ajustes declarados (sin cargos de recepción).',
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
      ),
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

  /// Tipo del nomenclador (`app_cont_tipo_costo`): «Flete», «Aduana»... Es lo
  /// que convierte la fila en algo legible de un vistazo.
  int? idTipoCosto;

  final TextEditingController valor;

  _AjusteForm({
    this.base = 'global',
    this.reparto = 'cantidad',
    this.origenPago = 'fondo',
    this.idTipoCosto,
    String valor = '0',
  }) : valor = TextEditingController(text: valor);

  double? get valorParse => _parseNumero(valor.text);
  double get valorValor => valorParse ?? 0;

  void escuchar(VoidCallback alCambiar) => valor.addListener(alCambiar);

  CompraAjuste aAjuste() => CompraAjuste(
    idTipoCosto: idTipoCosto,
    base: base,
    valor: valorValor,
    reparto: reparto,
    origenPago: origenPago,
  );

  void dispose() => valor.dispose();
}
