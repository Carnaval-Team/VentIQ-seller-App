import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/reception_total_widget.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';
import '../services/warehouse_service.dart';
import '../models/warehouse.dart';
import '../models/supplier.dart';
import '../widgets/conversion_info_widget.dart';
import '../widgets/product_quantity_dialog.dart';
import '../widgets/location_selector_widget.dart';
import '../widgets/product_selector_widget.dart';
import '../services/product_search_service.dart';
import '../widgets/ai_reception_sheet.dart';
import '../models/ai_reception_models.dart';
import '../models/fondo_inversion.dart';
import '../services/fondo_inversion_service.dart';
import '../widgets/fdi_recepcion_fuentes.dart';
import '../models/compra.dart';
import '../services/compra_service.dart';
import '../services/compras_costos_calculo.dart';
import '../services/currency_service.dart';
import '../services/financial_service.dart';

class InventoryReceptionScreen extends StatefulWidget {
  const InventoryReceptionScreen({super.key});

  @override
  State<InventoryReceptionScreen> createState() =>
      _InventoryReceptionScreenState();
}

class _InventoryReceptionScreenState extends State<InventoryReceptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _entregadoPorController = TextEditingController();
  final _recibidoPorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _montoTotalController = TextEditingController();
  final _searchController = TextEditingController();

  // Static variables to persist field values across screen instances
  static String _lastEntregadoPor = '';
  static String _lastRecibidoPor = '';
  static String _lastObservaciones = '';

  /// Moneda de la factura de la recepción.
  ///
  /// Con compra manda **la de la compra**: el vínculo guarda esa moneda y el
  /// servidor aborta el aterrizaje si la de la operación no coincide (D9). Sin
  /// compra se registra en USD, como siempre: la conversión de la recepción
  /// libre se hace por producto.
  static const String _monedaSinCompra = 'USD';
  static const Set<String> _monedasValidas = {'USD', 'CUP', 'EUR'};

  String get _selectedCurrency {
    final moneda = _compraSeleccionada?.monedaTotal.trim().toUpperCase() ?? '';
    return _monedasValidas.contains(moneda) ? moneda : _monedaSinCompra;
  }
  List<Map<String, dynamic>> _selectedProducts = [];
  /// Nombres del catálogo de costos (id → denominación) para los chips de
  /// costos adicionales por línea. Si falla, el chip muestra el id y la
  /// recepción sigue: no es un dato que bloquee el guardado.
  Map<int, String> _nombresCosto = {};
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  WarehouseZone? _selectedLocation;
  bool _isLoading = false;
  bool _isLoadingProducts = true;
  bool _isLoadingMotivos = true;
  String _searchQuery = '';
  Supplier? _selectedSupplier;
  List<Map<String, dynamic>> _proveedores = [];
  Map<String, dynamic>? _selectedProveedor;
  bool _isLoadingProveedores = false;

  // Inversión del fondo a amortizar con esta recepción (opcional)
  List<FdiInversion> _inversionesAbiertas = [];
  FdiInversion? _selectedInversion;
  final _tasaInversionController = TextEditingController();
  List<FdiSaldo> _saldosFondo = [];
  List<FdiFuenteRecepcion> _fuentesFondo = [];
  bool _usarFondo = false;
  bool _cargandoFondo = true;
  String? _errorFondo;
  late final String _claveFondo = FondoInversionService().newIdempotencyKey();

  // ── Recepción contra compra (fase 5b) ─────────────────────────────────────
  // Todo este bloque es opcional: si no se elige compra, nada de esto entra en
  // juego y la recepción funciona exactamente como antes.
  List<CompraResumen> _comprasRecepcion = [];
  bool _isLoadingCompras = true;
  String? _errorCompras;
  CompraResumen? _compraSeleccionada;
  List<LineaPendiente> _lineasPendientes = [];
  bool _isLoadingPendiente = false;
  String? _errorPendiente;

  /// Cantidad a recibir por `id_compra_linea`; su presencia es la selección.
  final Map<int, double> _cantidadesCompra = {};
  final Map<int, TextEditingController> _cantidadCompraControllers = {};

  final _pctImportadoraController = TextEditingController();
  final _baseImportadoraController = TextEditingController();
  final _reembolsoImportadoraController = TextEditingController();
  OrigenPagoAjuste _origenPagoImportadora = OrigenPagoAjuste.walletImportadora;

  /// La importadora es opcional: la mayoría de las recepciones no la tienen.
  /// Apagada, el cargo es 0 y no se envía nada al vínculo.
  bool _importadoraActiva = false;

  /// El usuario escribió «Sobre cuánto» a mano: no se pisa al marcar líneas.
  bool _baseImportadoraManual = false;

  /// Costos adicionales de la RECEPCIÓN (transporte, aduana…), repartidos por
  /// cantidad entre las líneas. Se suman a los que ya trae cada producto.
  final List<_CostoExtraRecepcion> _costosExtra = [];
  int? _tipoExtraSeleccionado;
  final _montoExtraCtrl = TextEditingController();

  /// Precio de venta CUP por producto y tasa USD→CUP, para el margen estimado.
  Map<int, double> _precioVentaCup = {};
  double _tasaCup = 0;

  /// Tasa de la factura en la recepción con compra: unidades de la moneda de la
  /// factura por 1 USD (la misma que `fdi_dat_compra.tasa_factura`). El servidor
  /// la exige si la factura no es USD y la guarda en la operación (D8).
  final _tasaFacturaUsdController = TextEditingController();

  /// Autorización de exceso para el envío en curso: se fija tras el diálogo y
  /// solo aplica a esa llamada a `vincularRecepcion`.
  bool _confirmarExcesoCompra = false;

  /// Si el vínculo falla, la recepción ya existe: se guarda su id para impedir
  /// que un segundo intento cree otra recepción duplicada.
  int? _recepcionRegistradaId;

  /// Hay compra seleccionada: cambia el selector de productos y bloquea el fondo.
  bool get _conCompra => _compraSeleccionada != null;

  /// Alguna línea lleva costos adicionales (del producto o de la recepción):
  /// la recepción viaja por el wrapper transaccional y, si la factura no es
  /// USD, ese carril exige la tasa (D8).
  bool get _hayCostos =>
      _costosExtra.isNotEmpty ||
      _selectedProducts.any((p) {
        final costos = p['costos'];
        return costos is List && costos.isNotEmpty;
      });

  /// Hay que pedir y enviar `p_tasa_usd`: factura no-USD y un carril que la
  /// exige (recepción de compra, siempre, porque el aterrizaje posterior la
  /// necesita; o costos que se registran en la misma transacción).
  bool get _requiereTasaFactura {
    if (_selectedCurrency == 'USD') return false;
    if (_conCompra) return true;
    return _hayCostos && (_usarFondo || _selectedInversion == null);
  }

  static String _textoNumero(double valor) {
    if (!valor.isFinite) return '';
    return valor == valor.roundToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toString();
  }

  static double _numeroDe(String texto) {
    final t = texto.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final v = double.tryParse(t);
    return v == null || !v.isFinite ? 0 : v;
  }

  double get _pctImportadora => _numeroDe(_pctImportadoraController.text);
  double get _baseImportadora => _numeroDe(_baseImportadoraController.text);
  double get _reembolsoImportadora =>
      _numeroDe(_reembolsoImportadoraController.text);

  /// `sobre cuánto × % / 100 − devolución`, el mismo cálculo que hace la RPC.
  /// Si el interruptor está apagado, no hay cargo.
  double get _cargoImportadora {
    if (!_importadoraActiva) return 0;
    final cargo =
        _baseImportadora * _pctImportadora / 100 - _reembolsoImportadora;
    return cargo.isFinite ? (cargo * 100).round() / 100 : 0;
  }

  double get _montoRecepcion => _montoTotalController.text.trim().isEmpty
      ? _totalAmount
      : (double.tryParse(_montoTotalController.text.replaceAll(',', '.')) ?? double.nan);

  /// Costos adicionales ya capturados por línea (en USD, como los guarda el
  /// módulo). Es solo para el adelanto en pantalla: el servidor manda.
  double get _adicionalesSeleccionados {
    var total = 0.0;
    for (final producto in _selectedProducts) {
      final costos = producto['costos'];
      if (costos is! List) continue;
      for (final costo in costos) {
        if (costo is Map) total += _numeroDe('${costo['monto_usd']}');
      }
    }
    return total + _extrasTotal;
  }

  Future<void> _loadSaldosFondo() async {
    setState(() { _cargandoFondo = true; _errorFondo = null; });
    try {
      final tienda = await UserPreferencesService().getIdTienda();
      if (tienda == null) throw StateError('No se encontró la tienda');
      final resultado = await FondoInversionService().saldos(tienda);
      if (!mounted) return;
      setState(() => _saldosFondo = resultado.saldos
          .where((s) => s.saldo > 0 && s.idMedioPago != null).toList());
    } catch (e) {
      if (mounted) setState(() => _errorFondo = 'No se pudo cargar el saldo del fondo: $e');
    } finally {
      if (mounted) setState(() => _cargandoFondo = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMotivoOptions();
    _loadProveedores();
    _loadInversionesAbiertas();
    _loadSaldosFondo();
    _loadCompras();
    _cargarNombresCosto();
    _cargarTasaCup();
    _searchController.addListener(_onSearchChanged);

    // Load persisted values from previous entries
    _loadPersistedValues();
  }

  void _loadPersistedValues() {
    _entregadoPorController.text = _lastEntregadoPor;
    _recibidoPorController.text = _lastRecibidoPor;
    _observacionesController.text = _lastObservaciones;
  }

  /// Catálogo de tipos de costo, solo para poner nombre a los chips de la
  /// línea (el importe y el id son los que viajan a la RPC).
  Future<void> _cargarNombresCosto() async {
    try {
      final tienda = await UserPreferencesService().getIdTienda();
      final tipos = await FinancialService().getCostTypes(idTienda: tienda);
      if (!mounted) return;
      setState(() {
        _nombresCosto = {
          for (final t in tipos)
            if ((t['id'] as num?) != null)
              (t['id'] as num).toInt(): t['denominacion']?.toString() ?? '',
        };
      });
    } catch (_) {
      // Sin catálogo, el chip cae al id. No bloquea nada.
    }
  }

  void _savePersistedValues() {
    _lastEntregadoPor = _entregadoPorController.text;
    _lastRecibidoPor = _recibidoPorController.text;
    _lastObservaciones = _observacionesController.text;
  }

  @override
  void dispose() {
    _entregadoPorController.dispose();
    _recibidoPorController.dispose();
    _observacionesController.dispose();
    _montoTotalController.dispose();
    _searchController.dispose();
    _tasaInversionController.dispose();
    _pctImportadoraController.dispose();
    _baseImportadoraController.dispose();
    _reembolsoImportadoraController.dispose();
    _tasaFacturaUsdController.dispose();
    _montoExtraCtrl.dispose();
    for (final c in _costosExtra) {
      c.dispose();
    }
    for (final controller in _cantidadCompraControllers.values) {
      controller.dispose();
    }
    _cantidadCompraControllers.clear();
    super.dispose();
  }

  /// Inversiones abiertas (pendiente/parcial) de la tienda para amortizar
  /// con esta recepción. Si falla la carga, la recepción sigue sin vínculo.
  Future<void> _loadInversionesAbiertas() async {
    try {
      final idTienda = await UserPreferencesService().getIdTienda();
      if (idTienda == null) return;
      final todas = await FondoInversionService().listInversiones(idTienda);
      if (!mounted) return;
      setState(() {
        _inversionesAbiertas = todas
            .where((i) => i.estado == 'pendiente' || i.estado == 'parcial')
            .toList();
      });
    } catch (e) {
      print('ℹ️ Sin inversiones del fondo disponibles: $e');
    }
  }

  // ── Compra (fase 5b): compras, pendiente, líneas y vínculo ────────────────

  /// Compras de la tienda que aceptan recepción (`reservada`, `pagada`,
  /// `entrega_parcial`). `listar` filtra por un solo estado, así que se piden
  /// todas y se filtran aquí.
  Future<void> _loadCompras() async {
    setState(() {
      _isLoadingCompras = true;
      _errorCompras = null;
    });
    try {
      final idTienda = await UserPreferencesService().getIdTienda();
      if (idTienda == null) throw StateError('No se encontró la tienda');
      final compras = await CompraService().listar(idTienda: idTienda);
      if (!mounted) return;
      const recepcionables = {'reservada', 'pagada', 'entrega_parcial'};
      setState(() {
        _comprasRecepcion = compras
            .where((c) => recepcionables.contains(c.estado))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorCompras = 'No se pudieron cargar las compras: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoadingCompras = false);
    }
  }

  /// La compra de la lista por id (el selector trabaja con ids, no con
  /// instancias: así una recarga de la lista no rompe la selección).
  CompraResumen? _compraPorId(int? idCompra) {
    if (idCompra == null) return null;
    for (final compra in _comprasRecepcion) {
      if (compra.id == idCompra) return compra;
    }
    return null;
  }

  /// Cambia de compra (o vuelve a recepción sin compra). Los productos ajenos a
  /// la compra se descartan: con compra, la selección se restringe a su
  /// pendiente y nada más.
  Future<void> _seleccionarCompra(CompraResumen? compra) async {
    if (compra?.id == _compraSeleccionada?.id) return;
    final teniaProductos = _selectedProducts.isNotEmpty;
    for (final controller in _cantidadCompraControllers.values) {
      controller.dispose();
    }
    setState(() {
      _compraSeleccionada = compra;
      _lineasPendientes = [];
      _errorPendiente = null;
      _isLoadingPendiente = false;
      _cantidadesCompra.clear();
      _cantidadCompraControllers.clear();
      _selectedProducts = [];
      _confirmarExcesoCompra = false;
      _baseImportadoraManual = false;
      _pctImportadoraController.clear();
      _reembolsoImportadoraController.clear();
      _baseImportadoraController.clear();
      if (compra != null) {
        // La base es el valor recibido de las líneas que se marquen; se llena
        // en `_sincronizarBaseImportadora`. Nunca la compra entera.
        _baseImportadoraController.clear();
        // Compra y financiación con el fondo no pueden convivir.
        _usarFondo = false;
        _fuentesFondo = [];
        // Tasa congelada en la compra; se precarga y se puede corregir antes de
        // guardar (el servidor la registra en la operación, D8). El resumen del
        // listado no la trae: se lee del detalle.
        _tasaFacturaUsdController.clear();
      } else {
        _tasaFacturaUsdController.clear();
      }
    });
    if (teniaProductos && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se limpiaron los productos que no eran de la compra'),
        ),
      );
    }
    if (compra != null) await _cargarPendiente(compra.id);
    if (compra != null) await _cargarTasaCompra(compra);
  }

  /// Precarga la tasa congelada de la compra (`tasa_factura`). El resumen del
  /// listado no la trae, así que se lee del detalle. Si falla, el campo queda
  /// vacío y el usuario la escribe: el servidor la exige igual (D8).
  Future<void> _cargarTasaCompra(CompraResumen compra) async {
    final moneda = compra.monedaTotal.trim().toUpperCase();
    if (moneda.isEmpty || moneda == 'USD') return;
    try {
      final detalle = await CompraService().detalle(compra.id);
      if (!mounted || _compraSeleccionada?.id != compra.id) return;
      setState(() {
        _tasaFacturaUsdController.text =
            _textoNumero(detalle.compra.tasaFactura);
      });
    } catch (e) {
      print('i️ No se pudo leer la tasa de la compra ${compra.numeroCompra}: $e');
    }
  }

  /// Pendiente por línea (`fn_fdi_compra_recepcion_pendiente`). Solo se
  /// conservan las líneas con pendiente > 0: las completas no se pueden
  /// recepcionar.
  Future<void> _cargarPendiente(int idCompra) async {
    setState(() {
      _isLoadingPendiente = true;
      _errorPendiente = null;
    });
    try {
      final lineas = await CompraService().pendiente(idCompra);
      if (!mounted || _compraSeleccionada?.id != idCompra) return;
      final conPendiente = lineas.where((l) => l.tienePendiente).toList();
      final controllers = <int, TextEditingController>{
        for (final linea in conPendiente)
          linea.idLinea: TextEditingController(
            text: _formatQuantity(linea.pendiente),
          ),
      };
      setState(() {
        for (final controller in _cantidadCompraControllers.values) {
          controller.dispose();
        }
        _lineasPendientes = conPendiente;
        _cantidadCompraControllers
          ..clear()
          ..addAll(controllers);
        _cantidadesCompra.clear();
        _selectedProducts = [];
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorPendiente =
              'No se pudo cargar el pendiente de la compra: ${_mensajeError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingPendiente = false);
    }
  }

  LineaPendiente? _lineaCompraPorId(int idLinea) {
    for (final linea in _lineasPendientes) {
      if (linea.idLinea == idLinea) return linea;
    }
    return null;
  }

  /// Marca o desmarca una línea. Al marcarla precarga el pendiente como
  /// cantidad a recibir (editable después).
  void _toggleLineaCompra(LineaPendiente linea, bool seleccionar) {
    setState(() {
      if (seleccionar) {
        var cantidad =
            _numeroDe(_cantidadCompraControllers[linea.idLinea]?.text ?? '');
        if (cantidad <= 0) {
          cantidad = linea.pendiente;
          _cantidadCompraControllers[linea.idLinea]?.text =
              _formatQuantity(linea.pendiente);
        }
        _cantidadesCompra[linea.idLinea] = cantidad;
      } else {
        _cantidadesCompra.remove(linea.idLinea);
      }
      _rebuildProductosCompra();
      _sincronizarBaseImportadora();
    });
    _cargarPreciosVenta();
  }

  void _setCantidadCompra(int idLinea, String texto) {
    if (!_cantidadesCompra.containsKey(idLinea)) return;
    setState(() {
      _cantidadesCompra[idLinea] = _numeroDe(texto);
      _rebuildProductosCompra();
      _sincronizarBaseImportadora();
    });
    _cargarPreciosVenta();
  }

  /// Convierte las líneas marcadas en los productos que ya sabe manejar el
  /// resto de la pantalla (totales, conversiones y envío de la recepción).
  void _rebuildProductosCompra() {
    final productos = <Map<String, dynamic>>[];
    for (final entry in _cantidadesCompra.entries) {
      final linea = _lineaCompraPorId(entry.key);
      if (linea == null) continue;
      productos.add(_productoDeLineaCompra(linea, entry.value));
    }
    _selectedProducts = productos;
  }

  Map<String, dynamic> _productoDeLineaCompra(
    LineaPendiente linea,
    double cantidad,
  ) => {
    'id': linea.idProducto,
    'id_producto': linea.idProducto,
    'denominacion': linea.producto,
    'sku_producto': '',
    'cantidad': cantidad,
    'precio_unitario': linea.costoUnitario,
    'moneda_precio': _selectedCurrency,
    'precio_referencia': 0.0,
    'descuento_porcentaje': 0.0,
    'descuento_monto': 0.0,
    'bonificacion_cantidad': 0.0,
    // Solo de esta pantalla: no viajan al RPC de recepción y son la llave de
    // `p_lineas` en el vínculo con la compra.
    'id_compra_linea': linea.idLinea,
    'id_compra_pendiente': linea.pendiente,
  };

  List<Map<String, dynamic>> _lineasParaVincular() => [
    for (final entry in _cantidadesCompra.entries)
      if (entry.value > 0)
        {'id_compra_linea': entry.key, 'cantidad_recibida': entry.value},
  ];

  /// Valor de factura de lo que se está recibiendo AHORA.
  ///
  /// Es la base que se declara con el vínculo: el porcentaje de importadora se
  /// cobra sobre lo recibido, no sobre la compra entera (antes se precargaba
  /// `totalMercancia` y dos recepciones parciales duplicaban la base).
  double get _valorRecibidoSeleccionado {
    var total = 0.0;
    for (final entry in _cantidadesCompra.entries) {
      final linea = _lineaCompraPorId(entry.key);
      if (linea == null) continue;
      total += entry.value * linea.costoUnitario;
    }
    return total;
  }

  /// Mantiene la base sincronizada con las líneas marcadas. El servidor, si
  /// recibe 0, la calcula igual; aquí se muestra para que el % se entienda.
  void _sincronizarBaseImportadora() {
    if (_compraSeleccionada == null || _baseImportadoraManual) return;
    _baseImportadoraController.text =
        _valorRecibidoSeleccionado.toStringAsFixed(2);
  }

  Future<void> _cargarTasaCup() async {
    try {
      final tasa = await CurrencyService.getEffectiveUsdToCupRate();
      if (mounted) setState(() => _tasaCup = tasa);
    } catch (_) {
      // Sin tasa no se muestra margen; el costo en USD sigue visible.
    }
  }

  /// Precio de venta base en CUP por producto seleccionado.
  Future<void> _cargarPreciosVenta() async {
    final ids = <int>{};
    for (final p in _selectedProducts) {
      final raw = p['id_producto'] ?? p['id'];
      final id = raw is int ? raw : int.tryParse('$raw');
      if (id != null) ids.add(id);
    }
    if (ids.isEmpty) {
      if (mounted) setState(() => _precioVentaCup = {});
      return;
    }
    if (_precioVentaCup.length == ids.length &&
        ids.every(_precioVentaCup.containsKey)) {
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('app_v_precio_venta_base_vigente')
          .select('id_producto, precio_venta_cup')
          .inFilter('id_producto', ids.toList());
      if (!mounted) return;
      setState(() {
        _precioVentaCup = {
          for (final r in rows)
            (r['id_producto'] as num).toInt():
                (r['precio_venta_cup'] as num?)?.toDouble() ?? 0,
        };
      });
    } catch (_) {
      // Sin precio vigente no se inventa un margen.
    }
  }

  int? _idTipoImportadora() {
    for (final e in _nombresCosto.entries) {
      if (e.value.trim().toLowerCase() == 'importadora') return e.key;
    }
    return null;
  }

  /// La importadora se declara arriba con su %. No se vuelve a ofrecer como
  /// costo adicional por producto: sería contarla dos veces.
  Set<int> get _conceptosOcultosRecepcion {
    if (!_importadoraActiva) return const {};
    final id = _idTipoImportadora();
    return id == null ? const {} : {id};
  }

  double get _totalUnidadesSeleccionadas {
    var total = 0.0;
    for (final p in _selectedProducts) {
      total += (p['cantidad'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }

  double get _extrasTotal {
    var total = 0.0;
    for (final c in _costosExtra) {
      total += c.valor;
    }
    return total;
  }

  void _agregarCostoExtra() {
    final id = _tipoExtraSeleccionado;
    final monto = _numeroDe(_montoExtraCtrl.text);
    if (id == null) {
      _showError('Elige el concepto del costo adicional');
      return;
    }
    if (monto <= 0) {
      _showError('Indica el importe total del costo adicional (USD)');
      return;
    }
    setState(() {
      _costosExtra.add(_CostoExtraRecepcion(id, _textoNumero(monto)));
      _tipoExtraSeleccionado = null;
      _montoExtraCtrl.clear();
    });
  }

  void _quitarCostoExtra(int index) {
    setState(() {
      _costosExtra.removeAt(index).dispose();
    });
  }

  /// Reparte cada costo extra por cantidad entre las líneas y lo suma a los
  /// costos que ya trae cada producto. El residuo de centavos va a la línea de
  /// mayor cantidad, para que Σ filas = importe declarado.
  void _distribuirCostosExtra(List<Map<String, dynamic>> productos) {
    if (_costosExtra.isEmpty || productos.isEmpty) return;
    final cantidades = [
      for (final p in productos) (p['cantidad'] as num?)?.toDouble() ?? 0,
    ];
    for (final extra in _costosExtra) {
      final monto = extra.valor;
      if (monto <= 0) continue;
      final cuotas = ComprasCostosCalculo.repartirPorCantidad(
        cantidades: cantidades,
        monto: monto,
      );
      for (var i = 0; i < productos.length; i++) {
        if (cuotas[i] <= 0) continue;
        final costos = List<Map<String, dynamic>>.from(
          (productos[i]['costos'] as List?) ?? const [],
        );
        costos.add({
          'id_tipo_costo': extra.idTipoCosto,
          'monto_usd': cuotas[i],
        });
        productos[i]['costos'] = costos;
      }
    }
  }

  /// Líneas que superan el pendiente, en texto, para el diálogo de exceso.
  List<String> _lineasSobrePendiente() {
    final detalles = <String>[];
    for (final entry in _cantidadesCompra.entries) {
      final linea = _lineaCompraPorId(entry.key);
      if (linea == null) continue;
      if (entry.value > linea.pendiente + 0.0001) {
        detalles.add(
          '- ${linea.producto}: pendiente '
          '${_formatQuantity(linea.pendiente)} y se intentan recibir '
          '${_formatQuantity(entry.value)}',
        );
      }
    }
    return detalles;
  }

  Future<bool> _confirmarExcesoRecepcion(List<String> detalles) async {
    final compra = _compraSeleccionada;
    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Exceso sobre la compra'),
        content: SingleChildScrollView(
          child: Text(
            'La compra #${compra?.numeroCompra ?? ''} recibiría más de lo '
            'pendiente:\n\n${detalles.join('\n')}\n\n'
            'El servidor acepta el exceso solo si se confirma. '
            '¿Confirmar el exceso?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Corregir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar exceso'),
          ),
        ],
      ),
    );
    return confirmado == true;
  }

  /// Aterriza el cargo de importadora del vínculo recién creado
  /// (`fn_fdi_compra_repartir_aterrizaje`). **No lanza**: la recepción y el
  /// vínculo ya existen y no se deshacen; si el reparto falla, se dice tal cual
  /// y se corrige desde la compra.
  Future<String> _aterrizarCargo(Map<String, dynamic> vinculo) async {
    final idLink = (vinculo['id_compra_recepcion'] as num?)?.toInt();
    if (idLink == null) {
      return ' · el vínculo no devolvió id para aterrizar el cargo.';
    }
    try {
      final r = await CompraService().repartirAterrizaje(idLink);
      final status = r['status']?.toString() ?? '?';
      switch (status) {
        case 'ok':
          final suma = _numeroDe('${r['cargo_suma'] ?? r['suma_monto_usd']}');
          final ajustes = _numeroDe('${r['ajustes_aplicados']}');
          final extra = ajustes > 0
              ? ' · ajustes aplicados: ${_textoNumero(ajustes)} USD'
              : '';
          return ' · cargo aterrizado: ${_textoNumero(suma)} USD$extra';
        case 'sin_cargo':
          return ' · sin cargo de importadora ni ajustes que aterrizar.';
        case 'omitido':
          return ' · el cargo lo paga ${r['origen_pago']}; no se toca el costo.';
        default:
          return ' · el cargo quedó sin aterrizar (estado: $status).';
      }
    } catch (e) {
      return ' · la recepción quedó vinculada, pero el cargo NO se aterrizó: '
          '${_mensajeError(e)}. Corríjalo desde la compra (el detalle muestra '
          'el desvío).';
    }
  }

  /// El vínculo falló pero la recepción ya existe: se dice tal cual y se
  /// bloquea un segundo envío para no duplicar el inventario.
  Future<void> _mostrarVinculoFallido(int? idOperacion, String detalle) async {
    // -1: la recepción se registró pero sin id utilizable; igual bloquea el
    // reenvío.
    setState(() => _recepcionRegistradaId = idOperacion ?? -1);
    if (!mounted) return;
    final numeroCompra = _compraSeleccionada?.numeroCompra;
    final referencia = idOperacion == null
        ? 'La recepción quedó registrada'
        : 'La recepción #$idOperacion quedó registrada';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Recepción registrada, vínculo fallido'),
        content: SingleChildScrollView(
          child: Text(
            '$referencia, pero NO se pudo vincular a la compra '
            '#$numeroCompra.\n\n$detalle\n\n'
            'El inventario ya se actualizó. No vuelvas a registrar la '
            'recepción: el vínculo se corrige desde la compra.',
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

  String _mensajeError(Object e) {
    if (e is PostgrestException) {
      final detalle = e.details?.toString().trim() ?? '';
      return detalle.isEmpty ? e.message : '${e.message} ($detalle)';
    }
    return e.toString();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  Future<void> _loadMotivoOptions() async {
    try {
      setState(() => _isLoadingMotivos = true);
      final motivos = await InventoryService.getMotivoRecepcionOptions();
      setState(() {
        _motivoOptions = motivos;
        if (motivos.isNotEmpty) {
          _selectedMotivo = motivos.first;
        }
        _isLoadingMotivos = false;
      });
    } catch (e) {
      setState(() => _isLoadingMotivos = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar motivos: $e')));
      }
    }
  }

  Future<void> _loadProveedores() async {
    try {
      setState(() => _isLoadingProveedores = true);
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Obtener proveedores de la tienda del usuario
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_dat_proveedor')
          .select('id, denominacion, sku_codigo')
          .eq('idtienda', idTienda)
          .order('denominacion', ascending: true);

      final proveedores = List<Map<String, dynamic>>.from(response);

      setState(() {
        _proveedores = proveedores;
        _selectedProveedor = null; // Sin filtro por defecto
        _isLoadingProveedores = false;
      });

      print(
        '✅ Proveedores cargados de tienda $idTienda: ${_proveedores.length}',
      );
    } catch (e) {
      setState(() => _isLoadingProveedores = false);
      print('❌ Error al cargar proveedores: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proveedores: $e')),
        );
      }
    }
  }

  Future<void> _openAiAssistant() async {
    final result = await showModalBottomSheet<AiReceptionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AiReceptionSheet(),
    );

    if (result != null) {
      // 0. Pre-calculation (Async)
      WarehouseZone? matchedLocation;
      if (result.location != null) {
        try {
          final warehouseService = WarehouseService();
          // Note: This might be redundant if we cached locations, but it's safer to fetch fresh
          final warehouses = await warehouseService.listWarehousesOK();
          for (final w in warehouses) {
            for (final z in w.zones) {
              if (z.name.toLowerCase().contains(
                    result.location!.toLowerCase(),
                  ) ||
                  result.location!.toLowerCase().contains(
                    z.name.toLowerCase(),
                  )) {
                matchedLocation = WarehouseZone(
                  id: z.id,
                  warehouseId: w.id,
                  name: z.name,
                  code: z.code,
                  type: z.type,
                  conditions: z.conditions,
                  capacity: z.capacity,
                  currentOccupancy: z.currentOccupancy,
                  locations: z.locations,
                  conditionCodes: z.conditionCodes,
                );
                break;
              }
            }
            if (matchedLocation != null) break;
          }
        } catch (e) {
          print('Error matching location: $e');
        }
      }

      // 1. Fill Header Fields (Sync)
      setState(() {
        if (result.observations != null) {
          _observacionesController.text = result.observations!;
        }
        if (result.receivedBy != null && result.receivedBy!.isNotEmpty) {
          _recibidoPorController.text = result.receivedBy!;
        }
        if (result.deliveredBy != null && result.deliveredBy!.isNotEmpty) {
          _entregadoPorController.text = result.deliveredBy!;
        }

        // Set Location
        if (matchedLocation != null) {
          _selectedLocation = matchedLocation;
        }

        // Match Reason
        if (result.reason != null) {
          try {
            final matched = _motivoOptions.firstWhere(
              (m) =>
                  m['denominacion'].toString().toLowerCase().contains(
                    result.reason!.toLowerCase(),
                  ) ||
                  result.reason!.toLowerCase().contains(
                    m['denominacion'].toString().toLowerCase(),
                  ),
            );
            _selectedMotivo = matched;
          } catch (_) {
            print('Motivo inferred "${result.reason}" not found in list.');
          }
        }
      });

      // 2. Fill Products
      if (result.items.isNotEmpty) {
        int addedCount = 0;
        for (final draft in result.items) {
          if (draft.productId != null) {
            setState(() {
              _selectedProducts.add({
                'id': draft.productId,
                'denominacion': draft.productName,
                'sku_producto': draft.productSku ?? '',
                'cantidad': draft.quantity,
                'precio_unitario': draft.price ?? 0.0,
                // Defaults
                'sku': draft.productSku ?? '',
                'descripcion': '',
                'es_vendible': true,
                'es_elaborado': false,
                'es_servicio': false,
                'stock_disponible': false,
                'presentaciones': [],
                'variantes_disponibles': [],
              });
              addedCount++;
            });
          }
        }

        if (addedCount > 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Datos importados: $addedCount productos + Encabezados',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    }
  }

  void _addProductToReception(Product product) {
    showDialog(
      context: context,
      builder: (context) => ProductQuantityDialog(
        product: product,
        selectedLocation: _selectedLocation,
        invoiceCurrency: _selectedCurrency,
        exchangeRate: null,
        conceptosOcultos: _conceptosOcultosRecepcion,
        onProductAdded: (productData) {
          setState(() {
            // Identify the incoming product by its numeric ID and presentation
            final incomingId = productData['id_producto'] ?? productData['id'];
            final incomingPresId = productData['id_presentacion'];

            final incomingLote =
                (productData['codigo_lote'] as String?)?.trim() ?? '';

            final existingIndex = _selectedProducts.indexWhere((p) {
              final existingId = p['id_producto'] ?? p['id'];
              final existingPresId = p['id_presentacion'];
              final existingLote =
                  (p['codigo_lote'] as String?)?.trim() ?? '';
              return existingId != null &&
                  existingId == incomingId &&
                  existingPresId == incomingPresId &&
                  existingLote.toLowerCase() == incomingLote.toLowerCase();
            });

            if (existingIndex != -1) {
              // Merge: sum quantity, keep higher unit price (or the new one)
              final existing = Map<String, dynamic>.from(
                _selectedProducts[existingIndex],
              );
              final prevQty = (existing['cantidad'] as num?)?.toDouble() ?? 0.0;
              final newQty =
                  (productData['cantidad'] as num?)?.toDouble() ?? 0.0;
              existing['cantidad'] = prevQty + newQty;
              _selectedProducts[existingIndex] = existing;
            } else {
              _selectedProducts.add(productData);
            }
          });
          _cargarPreciosVenta();
        },
      ),
    );
  }

  void _removeProduct(int index) {
    setState(() {
      final quitado = _selectedProducts.removeAt(index);
      // Un producto de compra se quita desmarcando su línea.
      final idLinea = (quitado['id_compra_linea'] as num?)?.toInt();
      if (idLinea != null) _cantidadesCompra.remove(idLinea);
    });
  }

  double get _totalAmount {
    return _selectedProducts.fold(0.0, (sum, item) {
      final cantidad = item['cantidad'] as double;
      final precio = item['precio_unitario'] as double? ?? 0.0;
      return sum + (cantidad * precio);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _submitReception() async {
    // Si la recepción ya se registró y solo falló el vínculo con la compra, no
    // se vuelve a enviar: duplicaría el inventario.
    if (_recepcionRegistradaId != null) {
      final id = _recepcionRegistradaId!;
      _showError(
        id > 0
            ? 'La recepción #$id ya quedó registrada; no se vuelve a enviar. '
                  'El vínculo con la compra se corrige desde la compra.'
            : 'La recepción ya quedó registrada; no se vuelve a enviar. '
                  'El vínculo con la compra se corrige desde la compra.',
      );
      return;
    }
    // Validaciones mejoradas
    if (!_formKey.currentState!.validate()) {
      _showError('Complete todos los campos requeridos');
      return;
    }
    if (_selectedProducts.isEmpty) {
      _showError('Debe agregar al menos un producto');
      return;
    }
    if (_selectedLocation == null) {
      _showError('Debe seleccionar una ubicación de destino');
      return;
    }
    // Validar que todos los productos tengan datos válidos
    for (final product in _selectedProducts) {
      final precio = product['precio_unitario'] as double?;
      final cantidad = product['cantidad'] as double?;

      if (precio == null || precio < 0) {
        _showError(
          'Producto "${product['denominacion']}" tiene precio inválido',
        );
        return;
      }
      if (cantidad == null || cantidad <= 0) {
        _showError(
          'Producto "${product['denominacion']}" tiene cantidad inválida',
        );
        return;
      }

      // Si el payload trae codigo_lote (producto por lotes), exigir fecha.
      final codigoLote = (product['codigo_lote'] as String?)?.trim() ?? '';
      final fechaVenc = (product['fecha_vencimiento'] as String?)?.trim() ?? '';
      if (codigoLote.isNotEmpty && fechaVenc.isEmpty) {
        _showError(
          'Producto "${product['denominacion']}" tiene lote sin fecha de vencimiento',
        );
        return;
      }
    }

    if (_isLoading) return;
    if (!_montoRecepcion.isFinite || _montoRecepcion < 0 || (_usarFondo && _montoRecepcion == 0)) {
      _showError('Indique un monto de recepción válido');
      return;
    }
    if (_usarFondo) {
      final error = FdiFuenteRecepcion.validar(_fuentesFondo, _montoRecepcion, _selectedCurrency);
      if (error != null) { _showError(error); return; }
    }
    // Recepción contra compra: nada de productos ajenos, y el exceso se
    // confirma ANTES de registrar la recepción para no dejarla a medias.
    if (_conCompra) {
      if (_usarFondo) {
        _showError(
          'Una recepción se financia con el fondo o viene de una compra ya '
          'pagada, no ambas. Desactive una de las dos.',
        );
        return;
      }
      if (_lineasParaVincular().isEmpty) {
        _showError('Seleccione al menos una línea de la compra');
        return;
      }
      if (_importadoraActiva) {
        if (_pctImportadora < 0 || _pctImportadora > 100) {
          _showError('El % de importadora debe estar entre 0 y 100');
          return;
        }
        if (_reembolsoImportadora < 0) {
          _showError('La devolución no puede ser negativa');
          return;
        }
        if (_cargoImportadora < 0) {
          _showError('La devolución supera el cargo de importadora');
          return;
        }
      }
      final excesos = _lineasSobrePendiente();
      if (excesos.isNotEmpty) {
        final confirmado = await _confirmarExcesoRecepcion(excesos);
        if (!confirmado) return;
      }
      _confirmarExcesoCompra = excesos.isNotEmpty;
    }
    // D8: con factura no-USD y costos en la misma transacción, el servidor
    // exige la tasa. Se avisa aquí en vez de dejar que la RPC devuelva 22023.
    if (_requiereTasaFactura &&
        _numeroDe(_tasaFacturaUsdController.text) <= 0) {
      _showError(
        'Indique la tasa de la factura: $_selectedCurrency por 1 USD '
        '(sin ella el costo no se puede aterrizar)',
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      final userUuid = await userPrefs.getUserId();

      if (idTienda == null || userUuid == null) {
        throw Exception('No se encontró información del usuario');
      }

      // Prepare products list with location IDs
      final productosParaEnviar = _selectedProducts.map((product) {
        // Add selected location ID to each product
        final productWithLocation = Map<String, dynamic>.from(product);

        // Fix: Ensure id_producto is set (AI and ProductSelector might use 'id')
        if (productWithLocation['id_producto'] == null &&
            productWithLocation['id'] != null) {
          productWithLocation['id_producto'] = productWithLocation['id'];
        }

        // Claves solo de esta pantalla (compra): no viajan al RPC de recepción.
        productWithLocation.remove('id_compra_linea');
        productWithLocation.remove('id_compra_pendiente');

        if (_selectedLocation != null) {
          // Remove prefix ('z' for zones, 'w' for warehouses) before parsing as int
          try {
            // El LocationSelectorWidget ahora devuelve directamente el ID de la zona
            final locationId = int.parse(_selectedLocation!.id);
            // print("Location ID: $locationId");
            productWithLocation['id_ubicacion'] = locationId;
          } catch (e) {
            throw Exception(
              'Error: ID de ubicación inválido "${_selectedLocation!.id}"',
            );
          }
        }
        return productWithLocation;
      }).toList();

      // Los costos de la recepción (transporte, etc.) se reparten por cantidad
      // y viajan dentro de cada línea al wrapper transaccional.
      if (_costosExtra.isNotEmpty) {
        _distribuirCostosExtra(productosParaEnviar);
      }

      // Debug: Print products list before sending to Supabase
      print("=== PRODUCTOS PARA ENVIAR A SUPABASE ===");
      print("Total productos: ${productosParaEnviar.length}");
      for (int i = 0; i < productosParaEnviar.length; i++) {
        print("Producto ${i + 1}: ${productosParaEnviar[i]}");
      }
      print("==========================================");

      final montoRecepcion = _montoRecepcion;
      final inv = _selectedInversion;
      double? tasaInversion;
      if (inv != null && inv.monedaReferencia != _selectedCurrency) {
        tasaInversion = double.tryParse(
          _tasaInversionController.text.replaceAll(',', '.'),
        );
      }

      var result = await InventoryService.insertInventoryReception(
        entregadoPor: _entregadoPorController.text,
        idTienda: idTienda,
        montoTotal: montoRecepcion,
        motivo: _selectedMotivo?['id'] ?? '',
        observaciones: _observacionesController.text,
        productos: productosParaEnviar,
        recibidoPor: _recibidoPorController.text,
        idProveedor: _selectedSupplier?.id,
        uuid: userUuid,
        monedaFactura: _selectedCurrency,
        // D8: la tasa viaja con la recepción. Sin ella, una factura que no sea
        // USD deja la operación con tasa NULL y el aterrizaje no puede convertir.
        tasaUsd: _requiereTasaFactura
            ? _numeroDe(_tasaFacturaUsdController.text)
            : null,
        idInversion: inv?.id,
        tasaInversion: tasaInversion,
        fuentesFondo: _usarFondo ? _fuentesFondo.map((f) => f.toJson()).toList() : null,
        idempotencyKey: _usarFondo ? _claveFondo : null,
      );

      // La recepción ya quedó registrada; si el vínculo con la inversión
      // excede el total esperado, confirmar el exceso y reintentar solo el
      // vínculo (fn_fdi_vincular_recepcion es separado e idempotente).
      if (mounted &&
          result['status'] == 'requires_confirmation' &&
          result['code'] == 'exceso_recepcion' &&
          inv != null) {
        final confirmar = await _confirmExcesoInversion(result);
        if (confirmar == true) {
          final idOp = (result['id_operacion'] as num?)?.toInt();
          if (idOp != null) {
            final vinculo = await FondoInversionService().vincularRecepcion(
              idOperacion: idOp,
              idInversion: inv.id,
              monto: montoRecepcion,
              moneda: _selectedCurrency,
              tasaARef: inv.monedaReferencia == _selectedCurrency
                  ? 1
                  : (tasaInversion ?? 1),
              confirmarExceso: true,
            );
            if (vinculo['status'] == 'ok') {
              result['status'] = 'success';
            } else {
              result['message'] =
                  'Recepción registrada pero vínculo a inversión falló: '
                  '${vinculo['message'] ?? vinculo}';
            }
          }
        } else {
          // La recepción se registró igual; solo el vínculo quedó pendiente.
          result['status'] = 'success';
          result['message'] =
              'Recepción registrada sin vínculo a la inversión '
              '(exceso no confirmado)';
        }
      }

      if (mounted) {
        if (result['status'] == 'success') {
          final idOperacion = (result['id_operacion'] as num?)?.toInt();
          String? mensajeCompra;

          // ── Vínculo con la compra (solo si se eligió una) ────────────────
          // La recepción ya existe: si el vínculo falla NO se finge éxito ni
          // se vuelve a registrar; se dice que la recepción quedó creada.
          if (_conCompra) {
            if (idOperacion == null) {
              await _mostrarVinculoFallido(
                null,
                'La RPC no devolvió id_operacion, así que no hay a qué '
                'vincular la recepción.',
              );
              return;
            }
            final compra = _compraSeleccionada!;
            try {
              final vinculo = await CompraService().vincularRecepcion(
                idOperacion: idOperacion,
                idCompra: compra.id,
                lineas: _lineasParaVincular(),
                confirmarExceso: _confirmarExcesoCompra,
                pctImportadora: _importadoraActiva ? _pctImportadora : 0,
                baseImportadora: _importadoraActiva ? _baseImportadora : 0,
                reembolsoImportadora:
                    _importadoraActiva ? _reembolsoImportadora : 0,
                origenPago: _importadoraActiva
                    ? _origenPagoImportadora.codigo
                    : OrigenPagoAjuste.walletImportadora.codigo,
              );
              if (vinculo['status'] != 'ok') {
                await _mostrarVinculoFallido(
                  idOperacion,
                  '${vinculo['message'] ?? vinculo}',
                );
                return;
              }
              // El cargo de importadora se aterriza AHORA: el reparto escribe
              // las filas del costo en la recepción, y `_v2` las capitaliza al
              // completar la operación. Sin este paso el cargo queda declarado
              // en el vínculo pero nunca llega al inventario.
              final aterrizaje = await _aterrizarCargo(vinculo);
              mensajeCompra =
                  'vinculada a la compra #${compra.numeroCompra} '
                  '(estado: ${vinculo['estado'] ?? '?'})$aterrizaje';
            } catch (e) {
              await _mostrarVinculoFallido(idOperacion, _mensajeError(e));
              return;
            }
          }

          // Save the values for future use before showing success message
          _savePersistedValues();

          // Capturar referencia al ScaffoldMessenger antes de pop
          if (!mounted) return;
          final messenger = ScaffoldMessenger.of(context);
          Navigator.pop(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                mensajeCompra == null
                    ? 'Recepción registrada exitosamente. ID: $idOperacion'
                    : 'Recepción registrada. ID: $idOperacion · $mensajeCompra',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          throw Exception(result['message'] ?? 'Error desconocido');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar recepción: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Recepción de Inventario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Asistente IA',
            onPressed: _openAiAssistant,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompraSection(),
                    const SizedBox(height: 24),
                    _buildReceptionInfoSection(),
                    const SizedBox(height: 24),
                    _buildLocationSelectionSection(),
                    const SizedBox(height: 24),
                    _buildProductSelectionSection(),
                    const SizedBox(height: 24),
                    _buildSelectedProductsSection(),
                    const SizedBox(height: 24),
                    _buildCostosExtraBlock(),
                    const SizedBox(height: 24),
                    _buildMargenCup(),
                  ],
                ),
              ),
            ),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  /// Conceptos de la tienda (o globales) que se suman a la recepción completa:
  /// transporte, aduana, etc. Se reparten por cantidad entre las líneas.
  Widget _buildCostosExtraBlock() {
    if (_nombresCosto.isEmpty) return const SizedBox.shrink();
    final usados = _costosExtra.map((c) => c.idTipoCosto).toSet();
    final disponibles = _nombresCosto.entries
        .where(
          (e) =>
              !usados.contains(e.key) &&
              !(_importadoraActiva &&
                  e.value.trim().toLowerCase() == 'importadora'),
        )
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Otros costos de la recepción',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Transporte, aduana, seguro… Se reparten por cantidad entre las '
              'líneas y suben el costo unitario. No reemplazan el cargo de '
              'importadora.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (disponibles.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _tipoExtraSeleccionado,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Concepto',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final e in disponibles)
                          DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _tipoExtraSeleccionado = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _montoExtraCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Total USD',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Añadir costo',
                    onPressed: _agregarCostoExtra,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            if (_costosExtra.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < _costosExtra.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _nombresCosto[_costosExtra[i].idTipoCosto] ??
                              'Concepto #${_costosExtra[i].idTipoCosto}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _costosExtra[i].monto,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'USD',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar',
                        onPressed: () => _quitarCostoExtra(i),
                        icon: const Icon(Icons.delete_outline, size: 18),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Total adicional: ${_textoNumero(_extrasTotal)} USD',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Costo estimado por unidad después de esta recepción contra el precio de
  /// venta CUP vigente. Es la ganancia que verá el cliente al confirmar.
  Widget _buildMargenCup() {
    if (_selectedProducts.isEmpty || _tasaCup <= 0) {
      return const SizedBox.shrink();
    }
    if (_selectedCurrency == 'EUR') return const SizedBox.shrink();
    final unidades = _totalUnidadesSeleccionadas;
    if (unidades <= 0) return const SizedBox.shrink();

    final cargoUnit = _cargoImportadora / unidades;
    final extrasUnit = _extrasTotal / unidades;

    double costoUnitCup(double precio) {
      if (_selectedCurrency == 'USD') {
        return (precio + cargoUnit + extrasUnit) * _tasaCup;
      }
      return precio + cargoUnit + extrasUnit * _tasaCup;
    }

    final filas = <Widget>[];
    for (final p in _selectedProducts) {
      final raw = p['id_producto'] ?? p['id'];
      final id = raw is int ? raw : int.tryParse('$raw');
      final venta = id == null ? null : _precioVentaCup[id];
      if (venta == null || venta <= 0) continue;
      final precio = (p['precio_unitario'] as num?)?.toDouble() ?? 0;
      final costo = costoUnitCup(precio);
      final margen = venta - costo;
      filas.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  p['denominacion']?.toString() ?? 'Producto',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                '${_textoNumero(costo)} → ${_textoNumero(venta)}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 8),
              Text(
                '${margen >= 0 ? '+' : ''}${_textoNumero(margen)} CUP',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: margen >= 0 ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (filas.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Costo vs precio de venta (CUP)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Estimado por unidad después de esta recepción, con la tasa '
              '1 USD = ${_textoNumero(_tasaCup)} CUP.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final f in filas) f,
            const SizedBox(height: 4),
            Text(
              'Costo → precio de venta · margen en CUP. El promedio definitivo '
              'lo recalcula el servidor al completar.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Costo por unidad que tendrá el producto si se confirma la recepción:
  /// factura + parte de importadora + otros costos de la recepción + costos
  /// propios del producto.
  String _buildCostoFinalDisplay(Map<String, dynamic> item) {
    final precio = (item['precio_unitario'] as num?)?.toDouble() ?? 0;
    final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 0;
    if (cantidad <= 0) return '';
    final unidades = _totalUnidadesSeleccionadas;

    final esCup = _selectedCurrency == 'CUP';
    final tasa = esCup ? (_tasaCup > 0 ? _tasaCup : 0.0) : 1.0;

    var propiosUsd = 0.0;
    for (final c in _costosDe(item)) {
      propiosUsd += _numeroDe('${c['monto_usd']}');
    }

    final prorrateo = unidades > 0
        ? (_cargoImportadora + _extrasTotal * tasa) / unidades
        : 0.0;
    final propios = (propiosUsd * tasa) / cantidad;
    final finalUnit = precio + prorrateo + propios;

    return 'Costo final estimado: ${finalUnit.toStringAsFixed(2)} '
        '$_selectedCurrency/u (factura ${precio.toStringAsFixed(2)} + '
        '${(prorrateo + propios).toStringAsFixed(2)})';
  }

  Widget _buildCompraSection() {
    final compra = _compraSeleccionada;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compra (opcional)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Sin compra la recepción funciona como siempre. Con compra solo '
              'se pueden recibir sus líneas pendientes y se registra el '
              'vínculo al guardar.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_isLoadingCompras)
              const LinearProgressIndicator()
            else if (_errorCompras != null)
              TextButton(
                onPressed: _loadCompras,
                child: Text('$_errorCompras · Reintentar'),
              )
            else
              DropdownButtonFormField<int?>(
                // La clave por id evita peleas de identidad con la lista.
                key: ValueKey('compra_${compra?.id}'),
                initialValue: compra?.id,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Compra',
                  border: const OutlineInputBorder(),
                  helperText: _usarFondo
                      ? 'Desactive "Financiar con fondo de inversión" para '
                            'elegir una compra'
                      : 'Sin compra = recepción normal, como siempre',
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Sin compra'),
                  ),
                  ..._comprasRecepcion.map(
                    (c) => DropdownMenuItem<int?>(
                      value: c.id,
                      child: Text(
                        '#${c.numeroCompra} · ${c.proveedor} · '
                        '${c.numeroFactura?.trim().isNotEmpty == true ? c.numeroFactura : "sin factura"} · '
                        '${c.totalMercancia.toStringAsFixed(2)} ${c.monedaTotal}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged:
                    (_isLoading || _usarFondo || _recepcionRegistradaId != null)
                    ? null
                    : (idCompra) => _seleccionarCompra(_compraPorId(idCompra)),
              ),
            if (!_isLoadingCompras &&
                _errorCompras == null &&
                _comprasRecepcion.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No hay compras reservadas, pagadas ni con entrega parcial.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            if (compra != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#${compra.numeroCompra} · ${compra.proveedor}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Chip(
                    label: Text(compra.estadoLegible),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Text(
                'Factura: ${compra.numeroFactura ?? '—'} · '
                'Total mercancía: '
                '${compra.totalMercancia.toStringAsFixed(2)} '
                '${compra.monedaTotal}',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              _buildCargoImportadoraBlock(),
              if (_requiereTasaFactura) ...[
                const SizedBox(height: 16),
                _buildTasaFacturaBlock(),
              ],
              const SizedBox(height: 16),
              _buildCifrasRecepcion(),
            ],
          ],
        ),
      ),
    );
  }

  /// Adelanto en vivo de las cifras del aterrizaje. El número que manda es el
  /// del servidor al confirmar (y el de `_v2` al capitalizar); aquí no se
  /// convierte nada entre monedas: si la factura no es USD, el aterrizado por
  /// línea lo calcula el servidor con su tasa.
  Widget _buildCifrasRecepcion() {
    final total = _montoRecepcion;
    final cargo = _cargoImportadora;
    final adicionales = _adicionalesSeleccionados;
    final usd = _selectedCurrency == 'USD';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Cifras de recepción',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'estimado',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.info,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _filaCifra('Total recepción', total, _selectedCurrency),
            if (_importadoraActiva)
              _filaCifra('Cargo importadora', cargo, _selectedCurrency),
            if (usd) _filaCifra('Adicionales', adicionales, 'USD'),
            const Divider(height: 20),
            if (usd)
              _filaCifra(
                'Costo aterrizado',
                total + cargo + adicionales,
                'USD',
                destacada: true,
              )
            else
              Text(
                'Los adicionales se capturan en USD: el costo aterrizado por '
                'línea lo calcula el servidor con la tasa de la factura.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            const SizedBox(height: 4),
            Text(
              'Se aplica al confirmar. El promedio lo recalcula el servidor.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaCifra(
    String etiqueta,
    double valor,
    String moneda, {
    bool destacada = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            '${valor.toStringAsFixed(2)} $moneda',
            style: TextStyle(
              fontSize: destacada ? 18 : 14,
              fontWeight: destacada ? FontWeight.w700 : FontWeight.w600,
              color: destacada ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Tasa de la factura con compra: unidades de la moneda de la factura por
  /// 1 USD. La congela el documento de compra (`tasa_factura`); se puede
  /// corregir antes de guardar y el servidor la registra en la operación (D8).
  Widget _buildTasaFacturaBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tasa de la factura',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Unidades de $_selectedCurrency por 1 USD. Obligatoria: sin ella no '
          'se puede aterrizar el costo de la importadora.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _tasaFacturaUsdController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Tasa $_selectedCurrency por 1 USD',
            border: const OutlineInputBorder(),
          ),
          validator: (v) {
            if (!_requiereTasaFactura) return null;
            final tasa = _numeroDe(v ?? '');
            if (tasa <= 0) return 'Tasa requerida (mayor que 0)';
            if (tasa >= 1e15) return 'Tasa fuera de rango';
            return null;
          },
        ),
      ],
    );
  }

  /// Cargo de importadora que se guarda con el vínculo. La RPC calcula
  /// `base × % / 100 − reembolso`; aquí se muestra en vivo el mismo número.
  Widget _buildCargoImportadoraBlock() {
    final cargo = _cargoImportadora;
    final negativo = cargo < 0;
    final unidades = _totalUnidadesSeleccionadas;
    final porUnidad = unidades > 0 ? cargo / unidades : 0.0;
    final moneda = _compraSeleccionada?.monedaTotal ?? '';

    String etiquetaOrigen(OrigenPagoAjuste origen) => switch (origen) {
      OrigenPagoAjuste.walletImportadora => 'Wallet de la importadora',
      OrigenPagoAjuste.walletProveedor => 'Wallet del proveedor',
      OrigenPagoAjuste.externo => 'Lo pagué por fuera (no sale del fondo)',
      OrigenPagoAjuste.fondo => 'Fondo (no disponible)',
    };

    final estiloAyuda = TextStyle(
      fontSize: 12,
      color: AppColors.textSecondary,
      height: 1.3,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '¿La importadora cobra por esta carga?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: _importadoraActiva,
              onChanged: (v) => setState(() {
                _importadoraActiva = v;
                if (v && _baseImportadoraController.text.trim().isEmpty) {
                  _sincronizarBaseImportadora();
                }
              }),
            ),
          ],
        ),
        if (!_importadoraActiva)
          Text(
            'Déjalo apagado si el proveedor te cobró todo y no hay importadora '
            'de por medio.',
            style: estiloAyuda,
          )
        else ...[
          Text(
            'Es el servicio de la importadora, no la factura del proveedor. '
            'Se suma al costo de lo que estás recibiendo.',
            style: estiloAyuda,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _pctImportadoraController,
                  decoration: const InputDecoration(
                    labelText: '% que cobra',
                    border: OutlineInputBorder(),
                    suffixText: '%',
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _baseImportadoraController,
                  decoration: InputDecoration(
                    labelText: 'Sobre cuánto',
                    helperText: 'Se calcula con las líneas marcadas. Solo '
                        'cámbialo si la importadora cobra sobre otro valor.',
                    helperMaxLines: 2,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: 'Recalcular con las líneas',
                      icon: const Icon(Icons.refresh, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() => _baseImportadoraManual = false);
                        _sincronizarBaseImportadora();
                        setState(() {});
                      },
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) =>
                      setState(() => _baseImportadoraManual = true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _reembolsoImportadoraController,
                  decoration: const InputDecoration(
                    labelText: 'Parte que te devuelve',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<OrigenPagoAjuste>(
                  key: ValueKey('origen_${_origenPagoImportadora.codigo}'),
                  initialValue: _origenPagoImportadora,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '¿Quién lo pagó?',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    // El fondo ya pagó el total financiado de la compra: no
                    // puede volver a pagar el cargo de la recepción.
                    for (final origen in OrigenPagoAjuste.values)
                      if (origen != OrigenPagoAjuste.fondo)
                        DropdownMenuItem(
                          value: origen,
                          child: Text(
                            etiquetaOrigen(origen),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (valor) => setState(
                    () => _origenPagoImportadora =
                        valor ?? OrigenPagoAjuste.walletImportadora,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color:
                  (negativo ? AppColors.error : AppColors.primary).withValues(
                alpha: 0.08,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_textoNumero(_baseImportadora)} × '
                  '${_textoNumero(_pctImportadora)} % − '
                  '${_textoNumero(_reembolsoImportadora)} = '
                  '${_textoNumero(cargo)} $moneda',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: negativo ? AppColors.error : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unidades > 0
                      ? '+${_textoNumero(porUnidad)} por unidad recibida '
                          '(${_textoNumero(unidades)} u)'
                      : 'Marca las líneas para ver cuánto sube por unidad.',
                  style: TextStyle(
                    fontSize: 12,
                    color: negativo
                        ? AppColors.error
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (negativo)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'La devolución supera el cargo: el servidor rechazaría el '
                'vínculo.',
                style: TextStyle(fontSize: 11, color: AppColors.error),
              ),
            ),
        ],
      ],
    );
  }

  /// Selector de productos cuando hay compra: solo líneas con pendiente > 0.
  Widget _buildCompraLineasPicker() {
    final compra = _compraSeleccionada!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Productos de la compra',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Solo las líneas con pendiente de la compra '
              '#${compra.numeroCompra}. La cantidad viene precargada con el '
              'pendiente y se puede bajar; si la sube se pedirá confirmar el '
              'exceso.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_isLoadingPendiente)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorPendiente != null)
              TextButton(
                onPressed: () => _cargarPendiente(compra.id),
                child: Text('$_errorPendiente · Reintentar'),
              )
            else if (_lineasPendientes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Esta compra no tiene líneas pendientes por recibir.'),
              )
            else
              ..._lineasPendientes.map(_buildLineaCompraRow),
          ],
        ),
      ),
    );
  }

  Widget _buildLineaCompraRow(LineaPendiente linea) {
    final seleccionada = _cantidadesCompra.containsKey(linea.idLinea);
    final cantidad = _cantidadesCompra[linea.idLinea] ?? linea.pendiente;
    final excede = seleccionada && cantidad > linea.pendiente + 0.0001;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: seleccionada,
              onChanged: _isLoading
                  ? null
                  : (valor) => _toggleLineaCompra(linea, valor ?? false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      linea.producto,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Comprado ${_formatQuantity(linea.cantidad)} · '
                      'recibido ${_formatQuantity(linea.recibido)} · '
                      'pendiente ${_formatQuantity(linea.pendiente)} · '
                      'costo ${linea.costoUnitario.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _cantidadCompraControllers[linea.idLinea],
                enabled: seleccionada && !_isLoading,
                decoration: const InputDecoration(
                  labelText: 'A recibir',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (texto) => _setCantidadCompra(linea.idLinea, texto),
              ),
            ),
          ],
        ),
        if (excede)
          Padding(
            padding: const EdgeInsets.only(left: 40, bottom: 4),
            child: Text(
              'Excede el pendiente: se pedirá confirmación al registrar',
              style: TextStyle(fontSize: 11, color: AppColors.warning),
            ),
          ),
        const Divider(height: 8),
      ],
    );
  }

  Widget _buildReceptionInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información de Recepción',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _entregadoPorController,
              decoration: const InputDecoration(
                labelText: 'Entregado por',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _recibidoPorController,
              decoration: const InputDecoration(
                labelText: 'Recibido por',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _isLoadingMotivos
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<Map<String, dynamic>>(
                    value: _selectedMotivo,
                    decoration: const InputDecoration(
                      labelText: 'Motivo',
                      border: OutlineInputBorder(),
                    ),
                    items: _motivoOptions.map((motivo) {
                      return DropdownMenuItem(
                        value: motivo,
                        child: Text(
                          motivo['denominacion'] ?? 'Sin denominación',
                        ),
                      );
                    }).toList(),
                    onChanged: (motivo) {
                      setState(() {
                        _selectedMotivo = motivo;
                      });
                    },
                    validator: (value) {
                      if (value == null) return 'Campo requerido';
                      return null;
                    },
                  ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montoTotalController,
              decoration: InputDecoration(
                labelText: 'Monto Total (Opcional)',
                hintText:
                    'Calculado automáticamente: \$${_totalAmount.toStringAsFixed(2)}',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            if (_cargandoFondo) const LinearProgressIndicator(),
            if (_errorFondo != null)
              TextButton(onPressed: _loadSaldosFondo, child: Text('$_errorFondo · Reintentar')),
            if (!_cargandoFondo && _errorFondo == null && _saldosFondo.isEmpty)
              const Text('No hay saldo disponible en el fondo de inversión.'),
            if (_saldosFondo.isNotEmpty) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Financiar con fondo de inversión'),
                subtitle: Text(
                  _conCompra
                      ? 'No disponible con compra: una recepción se financia '
                            'con el fondo o viene de una compra ya pagada, no '
                            'ambas. Quite la compra para financiar.'
                      : 'Descontar de una o varias cuentas y registrar el uso con esta recepción.',
                ),
                value: _usarFondo,
                onChanged: (_isLoading || _conCompra) ? null : (value) => setState(() {
                  _usarFondo = value;
                  _selectedInversion = null;
                  _fuentesFondo = [];
                }),
              ),
              if (_usarFondo)
                FdiRecepcionFuentes(
                  saldos: _saldosFondo, total: _montoRecepcion,
                  moneda: _selectedCurrency, enabled: !_isLoading,
                  onChanged: (fuentes) => _fuentesFondo = fuentes,
                ),
            ],
            // Vínculo opcional con una inversión abierta del fondo
            if (!_usarFondo && !_conCompra && _inversionesAbiertas.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<FdiInversion>(
                initialValue: _selectedInversion,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Amortizar inversión (opcional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final inv in _inversionesAbiertas)
                    DropdownMenuItem(
                      value: inv,
                      child: Text(
                        '${inv.identificador} · '
                        'faltan ${(inv.montoTotalRef - inv.montoRecibidoRef).toStringAsFixed(2)} '
                        '${inv.monedaReferencia}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (inv) => setState(() => _selectedInversion = inv),
              ),
              if (_selectedInversion != null &&
                  _selectedInversion!.monedaReferencia != _selectedCurrency) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tasaInversionController,
                  decoration: InputDecoration(
                    labelText:
                        'Tasa $_selectedCurrency→${_selectedInversion!.monedaReferencia}',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (_selectedInversion == null) return null;
                    final t = double.tryParse((v ?? '').replaceAll(',', '.'));
                    if (t == null || t <= 0) {
                      return 'Tasa requerida (monedas distintas)';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmExcesoInversion(Map<String, dynamic> resp) {
    num f(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Exceso sobre la inversión'),
        content: Text(
          'Esta recepción sumaría ${f(resp['monto_nuevo_ref']).toStringAsFixed(2)} '
          'a lo ya recibido (${f(resp['monto_recibido_ref']).toStringAsFixed(2)}) '
          'y superaría el total esperado '
          '(${f(resp['monto_total_ref']).toStringAsFixed(2)}).\n\n'
          'La recepción ya quedó registrada. ¿Vincularla a la inversión '
          'confirmando el exceso?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No vincular'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar exceso'),
          ),
        ],
      ),
    );
  }

  Widget _buildProductSelectionSection() {
    // Con compra no hay selector libre: el producto tiene que ser una línea de
    // la compra, así que se sustituye por su propio selector.
    if (_conCompra) return _buildCompraLineasPicker();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccionar Productos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Sección de filtro por proveedor
            _buildProveedorFilterSection(),
            const SizedBox(height: 16),

            SizedBox(
              height: 300,
              child: ProductSelectorWidget(
                key: ValueKey(_selectedProveedor?['id']),
                searchType: ProductSearchType.reception,
                requireInventory: false,
                searchHint: 'Buscar productos para recibir...',
                supplierId: _selectedProveedor?['id'] as int?,
                onProductSelected: (productData) {
                  // Convertir Map a Product para mantener compatibilidad
                  final product = Product(
                    id: productData['id']?.toString() ?? '',
                    name:
                        productData['denominacion'] ??
                        productData['nombre_producto'] ??
                        'Sin nombre',
                    denominacion:
                        productData['denominacion'] ??
                        productData['nombre_producto'] ??
                        'Sin nombre',
                    description: productData['descripcion'] ?? '',
                    categoryId: productData['id_categoria']?.toString() ?? '',
                    categoryName: productData['categoria_nombre'] ?? '',
                    brand: '', // No disponible en nueva estructura
                    sku:
                        productData['sku_producto'] ?? productData['sku'] ?? '',
                    barcode: productData['codigo_barras'] ?? '',
                    basePrice:
                        (productData['precio_venta_cup'] as num?)?.toDouble() ??
                        0.0,
                    imageUrl: '', // No disponible en nueva estructura
                    createdAt: DateTime.now(), // Valor por defecto
                    updatedAt: DateTime.now(), // Valor por defecto
                    // Campos específicos de la nueva estructura
                    um: productData['um'],
                    precioVenta:
                        (productData['precio_venta_cup'] as num?)?.toDouble() ??
                        0.0,
                    esVendible: productData['es_vendible'] ?? true,
                    esElaborado: productData['es_elaborado'] ?? false,
                    esServicio: productData['es_servicio'] ?? false,
                    esPorLotes: productData['es_por_lotes'] == true,
                    diasAlertCaducidad:
                        (productData['dias_alert_caducidad'] as num?)
                            ?.toInt() ??
                        0,
                    stockDisponible: productData['stock_disponible'] ?? false,
                    presentaciones:
                        (productData['presentaciones'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [],
                    variantesDisponibles:
                        (productData['variantes_disponibles'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [],
                  );

                  // Debug: Verificar el objeto Product creado
                  print('✅ Product creado:');
                  print('  - name: ${product.name}');
                  print('  - sku: "${product.sku}"');
                  print('  - sku.isEmpty: ${product.sku.isEmpty}');

                  _addProductToReception(product);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Costos adicionales capturados en el diálogo del producto para esa línea.
  List<Map<String, dynamic>> _costosDe(Map<String, dynamic> item) {
    final costos = item['costos'];
    if (costos is! List) return const [];
    return [
      for (final c in costos)
        if (c is Map) Map<String, dynamic>.from(c),
    ];
  }

  /// Chip de una línea: nombre del concepto (o id si el catálogo no cargó) y
  /// su importe en USD, que es como los guarda el módulo de costos.
  Widget _chipCosto(Map<String, dynamic> costo) {
    final id = (costo['id_tipo_costo'] as num?)?.toInt() ?? 0;
    final nombre = _nombresCosto[id] ?? 'Costo #$id';
    final monto = _numeroDe('${costo['monto_usd']}');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$nombre ${monto.toStringAsFixed(2)} USD',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildSelectedProductsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productos Seleccionados (${_selectedProducts.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_selectedProducts.isEmpty)
              const Center(
                child: Text(
                  'No hay productos seleccionados',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _selectedProducts.length,
                itemBuilder: (context, index) {
                  final item = _selectedProducts[index];
                  final originalIndex = _selectedProducts.indexOf(item);
                  return ListTile(
                    title: Text(
                      item['denominacion'] ??
                          item['nombre_producto'] ??
                          'Producto sin nombre',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SKU: ${item['sku_producto'] ?? item['sku'] ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _buildQuantityDisplay(item),
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          _buildPriceDisplay(item),
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          _buildCostoFinalDisplay(item),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        if (_costosDe(item).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final c in _costosDe(item)) _chipCosto(c),
                            ],
                          ),
                        ],
                        if (item['id_compra_pendiente'] != null)
                          Text(
                            'Pendiente de la compra: '
                            '${_formatQuantity((item['id_compra_pendiente'] as num).toDouble())}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if ((item['codigo_lote'] as String?)
                                ?.trim()
                                .isNotEmpty ==
                            true)
                          Text(
                            'Lote: ${item['codigo_lote']}'
                            '${item['fecha_vencimiento'] != null ? ' · Vence: ${item['fecha_vencimiento']}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (item['precio_referencia'] != null &&
                            item['precio_referencia'] > 0)
                          Text(
                            'Precio Ref: \$${item['precio_referencia']?.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        if ((item['descuento_porcentaje'] ?? 0) > 0 ||
                            (item['descuento_monto'] ?? 0) > 0)
                          Text(
                            'Descuento: ${item['descuento_porcentaje'] ?? 0}% + \$${item['descuento_monto']?.toStringAsFixed(2) ?? '0.00'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                        if ((item['bonificacion_cantidad'] ?? 0) > 0)
                          Text(
                            'Bonificación: +${item['bonificacion_cantidad']} unidades',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                            ),
                          ),
                        if (_buildVariantInfo(item).isNotEmpty)
                          Container(
                            margin: EdgeInsets.only(top: 4),
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _buildVariantInfo(item),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.remove_circle,
                        color: AppColors.error,
                      ),
                      onPressed: () => _removeProduct(originalIndex),
                    ),
                  );
                },
              ),
            // NUEVO: Agregar widget de conversiones después de la lista de productos
            ConversionInfoWidget(
              conversions: _selectedProducts,
              showDetails: true,
            ),
          ],
        ),
      ),
    );
  }

  String _buildQuantityDisplay(Map<String, dynamic> item) {
    final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 0;

    // Verificar si se aplicó conversión
    final conversionApplied = item['conversion_applied'] == true;
    final cantidadOriginal = (item['cantidad_original'] as num?)?.toDouble();

    String quantityText;
    if (conversionApplied && cantidadOriginal != null) {
      // Obtener nombres de presentaciones
      final presentacionOriginal = item['presentacion_original_info'];
      final presentacionFinal = item['presentation_info'];

      String presentacionOriginalText = 'unidades';
      String presentacionFinalText = 'unidades base';

      if (presentacionOriginal is Map &&
          presentacionOriginal['denominacion'] != null) {
        presentacionOriginalText = presentacionOriginal['denominacion']
            .toString();
      }

      if (presentacionFinal is Map &&
          presentacionFinal['denominacion'] != null) {
        presentacionFinalText = presentacionFinal['denominacion'].toString();
      }

      quantityText =
          'Cantidad: ${_formatQuantity(cantidadOriginal)} $presentacionOriginalText '
          '→ ${_formatQuantity(cantidad)} $presentacionFinalText';
    } else {
      final presentationInfo = item['presentation_info'];
      final presentationName = presentationInfo is Map
          ? (presentationInfo['denominacion'] ??
                    presentationInfo['presentacion'] ??
                    presentationInfo['nombre'])
                ?.toString()
          : null;
      final visiblePresentation = presentationName?.trim().isNotEmpty == true
          ? presentationName!.trim()
          : 'Presentación base';
      quantityText =
          'Cantidad: ${_formatQuantity(cantidad)} $visiblePresentation';
    }

    return quantityText;
  }

  String _formatQuantity(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');

  String _buildPriceDisplay(Map<String, dynamic> item) {
    final precio = (item['precio_unitario'] as num?)?.toDouble() ?? 0.0;
    return 'Precio: \$${precio.toStringAsFixed(2)} USD';
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Widget de total con conversión de monedas
          ReceptionTotalWidget(
            totalAmount: _totalAmount,
            invoiceCurrency: _selectedCurrency,
            selectedProducts: _selectedProducts,
            onTotalConverted: (convertedAmount, currency) {
              print('Total convertido: $convertedAmount $currency');
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitReception,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      'Registrar Recepción',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSelectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccionar Ubicación',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            LocationSelectorWidget(
              type: LocationSelectorType.single,
              title: 'Seleccionar Ubicación de Destino',
              subtitle: 'Zona donde se almacenarán los productos recibidos',
              selectedLocation: _selectedLocation,
              onLocationChanged: (location) {
                setState(() {
                  _selectedLocation = location;
                });
              },
              validationMessage: _selectedLocation == null
                  ? 'Debe seleccionar una ubicación'
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProveedorFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Filtrar por Proveedor',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (_selectedProveedor != null)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedProveedor = null;
                  });
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Limpiar'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _isLoadingProveedores
            ? const Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedProveedor,
                decoration: InputDecoration(
                  labelText: 'Seleccionar proveedor',
                  border: const OutlineInputBorder(),
                  hintText: _proveedores.isEmpty
                      ? 'No hay proveedores disponibles'
                      : 'Todos los proveedores',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  DropdownMenuItem<Map<String, dynamic>>(
                    value: null,
                    child: const Text('Todos los proveedores'),
                  ),
                  ..._proveedores.map((proveedor) {
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: proveedor,
                      child: Text(
                        proveedor['denominacion'] ?? 'Sin nombre',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ],
                onChanged: (proveedor) {
                  setState(() {
                    _selectedProveedor = proveedor;
                  });
                  print(
                    '✅ Proveedor seleccionado: ${proveedor?['denominacion'] ?? "Todos"}',
                  );
                },
              ),
      ],
    );
  }

  String _buildVariantInfo(Map<String, dynamic> item) {
    List<String> variantParts = [];

    // Priority 1: Use stored variant_info and presentation_info (from dialog selection)
    if (item['variant_info'] != null) {
      final variantInfo = item['variant_info'];
      final atributo =
          variantInfo['atributo']?['denominacion'] ??
          variantInfo['atributo']?['label'] ??
          '';
      final opcion = variantInfo['opcion']?['valor'] ?? '';

      if (atributo.isNotEmpty && opcion.isNotEmpty) {
        variantParts.add('$atributo: $opcion');
      } else if (atributo.isNotEmpty) {
        variantParts.add(atributo);
      }
    }

    if (item['presentation_info'] != null) {
      final presentationInfo = item['presentation_info'];
      final denominacion =
          presentationInfo['denominacion'] ??
          presentationInfo['presentacion'] ??
          presentationInfo['nombre'] ??
          presentationInfo['tipo'] ??
          '';
      final cantidad = presentationInfo['cantidad'] ?? 1;

      if (denominacion.isNotEmpty) {
        variantParts.add('Presentación: $denominacion (${cantidad}x)');
      }
    }

    // Priority 2: Fallback to searching in product data (only if stored info not available)
    if (variantParts.isEmpty) {
      // Add variant information if available
      if (item['id_variante'] != null) {
        // Since we no longer have _availableProducts loaded, we'll skip this fallback
        // The variant info should come from the ProductSelectorWidget data
        // If needed, we can make an individual product query here
        print(
          '⚠️ Variant info fallback skipped - data should come from ProductSelectorWidget',
        );
      }
    }

    return variantParts.join(' | ');
  }
}

/// Costo adicional declarado para la recepción completa (concepto + total USD).
class _CostoExtraRecepcion {
  final int idTipoCosto;
  final TextEditingController monto;

  _CostoExtraRecepcion(this.idTipoCosto, String initial)
      : monto = TextEditingController(text: initial);

  double get valor =>
      double.tryParse(monto.text.trim().replaceAll(',', '.')) ?? 0;

  void dispose() => monto.dispose();
}
