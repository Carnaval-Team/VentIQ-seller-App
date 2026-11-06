import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/inventory_product.dart';
import '../models/expense.dart';
import '../services/order_service.dart';
import '../services/notification_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/uuid_generator.dart';
import '../services/turno_service.dart';
import '../services/shift_workers_service.dart';
import '../services/printer_manager.dart';
import '../services/inventory_service.dart';
import '../services/auto_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/server_time_service.dart';
import '../utils/navigation_helper.dart';
import '../utils/price_utils.dart';
import '../theme/ventiq_home_theme.dart';
import '../widgets/cash_count_dialog.dart';

class CierreScreen extends StatefulWidget {
  const CierreScreen({Key? key}) : super(key: key);

  @override
  State<CierreScreen> createState() => _CierreScreenState();
}

class _CierreScreenState extends State<CierreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _observacionesController = TextEditingController();
  final OrderService _orderService = OrderService();
  final UserPreferencesService _userPrefs = UserPreferencesService();

  // ─── Arqueo por divisa (Fase 4) ──────────────────────────────────────────
  // Todo el efectivo vive en mapas con UNA ENTRADA POR DIVISA y con importes
  // NATIVOS: es la única fuente de verdad del cierre. Antes había pares
  // `x`/`xUsd`, lo que obligaba a que el código de divisa decidiera las sumas y
  // hacía imposible reconstruir el arqueo cuando entraba una tercera moneda.
  //
  // * [_divisasCaja]: divisas habilitadas, en orden (un campo por cada una).
  // * [_efectivoInicialPorDivisa]: efectivo al abrir el turno.
  // * [_efectivoPorDivisa]: cobros EN EFECTIVO del turno.
  // * [_efectivoRealControllers]: efectivo contado, un campo por divisa.
  List<String> _divisasCaja = const [PriceUtils.baseCurrency, 'USD'];
  Map<String, double> _efectivoInicialPorDivisa = {};
  Map<String, double> _efectivoPorDivisa = {};
  Map<String, double> _transferenciaPorDivisa = {};

  /// Efectivo por divisa del turno según el servidor (`desglose_monedas` de las
  /// RPC `_v2`). Vacío cuando el backend todavía no las tiene o no responde.
  ///
  /// Se guarda aparte porque [_calcularDatosCierre] vuelve a derivar el detalle
  /// de las órdenes locales y no debe perder las divisas que solo el servidor
  /// conoce: una tercera divisa sin órdenes cargadas se leía como 0.
  Map<String, double> _efectivoDesgloseServidor = {};

  /// Lo mismo para las transferencias/digital: el cobro por transferencia
  /// también se hace en una divisa concreta y el desglose del servidor es la
  /// única fuente para las divisas de las que no hay órdenes locales cargadas.
  Map<String, double> _digitalDesgloseServidor = {};
  final Map<String, TextEditingController> _efectivoRealControllers = {
    PriceUtils.baseCurrency: TextEditingController(),
    'USD': TextEditingController(text: '0'),
  };

  bool _isProcessing = false;
  bool _isLoadingData = true;
  bool _isLoadingInventory =
      false; // Cambiado a false para que cargue al abrir el modal
  bool _isLoadingExpenses = true;

  // Inventory data
  List<InventoryProduct> _inventoryProducts = [];
  Map<int, TextEditingController> _inventoryControllers = {};

  /// Stock real por producto (RPC batch / offline). Key = id_producto.
  Map<int, _StockRealProducto> _stockRealByProduct = {};
  bool _inventorySet = false;

  // Conteos de inventario introducidos localmente (persistidos).
  Map<int, double> _pendingInventoryCounts = {};
  Timer? _inventorySaveTimer;

  // Productos que aún no tienen cantidad ingresada (marcados al guardar).
  final Set<int> _missingInventoryProductIds = {};

  // New state variables for conditional inventory
  bool _isLastOpenShift = false;
  bool _checkingShiftStatus = true;

  // Expenses data
  List<Expense> _expenses = [];
  double _totalEgresos = 0.0; // Total de todos los egresos
  double _egresosEfectivo = 0.0; // Solo egresos en efectivo (no digitales)
  double _egresosTransferencias =
      0.0; // Solo egresos por transferencias/digitales

  /// Egresos EN EFECTIVO por divisa (importes NATIVOS).
  ///
  /// Es el desglose con el que se descuenta el arqueo: el egreso guarda en qué
  /// divisa salió el dinero, así que un egreso en USD baja el USD esperado y no
  /// el CUP.
  Map<String, double> _egresosEfectivoPorDivisa = {};

  // Data from RPC
  double _ventasTotales = 0.0;
  double _totalEfectivo = 0.0;
  double _totalTransferencias = 0.0;
  // FASE 3 presentaciones: `num`, no `int`. La RPC v2 devuelve
  // `productos_vendidos` como numeric porque la original lo casteaba a integer
  // y REDONDEABA (tres lineas de 0,5 kg daban 2). Si el Dart lo volviera a
  // meter en un int, el redondeo se moveria del SQL al cliente y el arreglo no
  // serviria de nada.
  num _productosVendidos = 0;

  /// Equivalente en unidades base (`SUM(cantidad * factor_rel)`), de la v2.
  num? _productosVendidosBase;

  /// Desglose ya formateado por el SQL: "2 Cajas + 5 Unidades", de la v2.
  String? _productosVendidosDesglose;
  double _ticketPromedio = 0.0;
  double _porcentajeEfectivo = 0.0;
  double _porcentajeOtros = 0.0;

  // New fields from updated RPC
  int _operacionesTotales = 0;
  double _operacionesPorHora = 0.0;
  String _conciliacionEstado = '';

  // Shift workers closed
  int _trabajadoresCerrados = 0;

  // Fecha/hora real de apertura del turno que se está cerrando (para mostrar
  // en el encabezado junto a la hora actual y evitar confusiones cuando el
  // turno lleva abierto varios días).
  DateTime? _fechaAperturaTurno;

  // Orders data
  int _ordenesAbiertas = 0;
  List<Order> _ordenesPendientes = [];
  String _userName = 'Cargando...';
  bool _manejaInventario =
      false; // Nueva variable para controlar si mostrar inventario
  bool _mostrarDebeHaberEnConteo = false;
  bool _autocompletarCantidadRealConteo = false;

  // Worker configuration for inventory control
  bool _trabajadorManejaAperturaControl =
      true; // Default to true (safe behavior)

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStoreConfiguration();
    _loadWorkerConfig(); // Load worker inventory control settings
    _loadDivisasCaja(); // Divisas habilitadas → un campo de efectivo por cada una
    _loadDailySummary(); // también recalcula órdenes del turno
    _loadExpenses();
  }

  /// Check if this is the last open shift in the warehouse
  Future<void> _checkIfLastOpenShift() async {
    try {
      setState(() {
        _checkingShiftStatus = true;
      });

      final idAlmacen = await _userPrefs.getIdAlmacen();
      if (idAlmacen == null) {
        print('❌ No warehouse ID found for shift check');
        setState(() {
          _checkingShiftStatus = false;
        });
        return;
      }

      final supabase = Supabase.instance.client;

      // Get all active shifts (estado = 1) for the same warehouse
      final activeShiftsResponse = await supabase
          .from('app_dat_caja_turno')
          .select('id, app_dat_tpv!inner(id_almacen)')
          .eq('estado', 1)
          .eq('app_dat_tpv.id_almacen', idAlmacen);

      final activeShifts = activeShiftsResponse as List<dynamic>;

      // If only 1 shift is open, this is the last one
      final isLastShift = activeShifts.length == 1;

      if (mounted) {
        setState(() {
          _isLastOpenShift = isLastShift;
          _checkingShiftStatus = false;
        });

        if (isLastShift) {
          print(
            '⚠️ This is the LAST open shift in warehouse $idAlmacen. Inventory is MANDATORY.',
          );
        } else {
          print(
            'ℹ️ There are ${activeShifts.length} open shifts in warehouse $idAlmacen. Inventory is OPTIONAL.',
          );
        }
      }
    } catch (e) {
      print('❌ Error checking shift status: $e');
      if (mounted) {
        setState(() {
          _checkingShiftStatus = false;
          // Default to mandatory (safe)
          _isLastOpenShift = true;
        });
      }
    }
  }

  /// Cargar productos de inventario desde cache offline (sin categorías)
  Future<void> _loadInventoryProductsOffline() async {
    try {
      final products =
          (await InventoryService.buildFromOfflineCache())
              .where((product) => product.cantidadFinal > 0)
              .toList();
      for (var product in products) {
        if (!_inventoryControllers.containsKey(product.id)) {
          _inventoryControllers[product.id] = TextEditingController();
        }
      }

      setState(() {
        _inventoryProducts = products;
      });

      print('✅ ${products.length} productos offline cargados para inventario');
    } catch (e, stack) {
      print('❌ Error cargando productos offline: $e');
      print(stack);
      setState(() {
        _inventoryProducts = [];
      });
    }
  }

  Future<void> _loadStoreConfiguration() async {
    try {
      final isOffline = await _userPrefs.shouldUseLocalData();
      final storeConfig = await _userPrefs.getStoreConfig();

      if (storeConfig != null) {
        final manejaInventario = storeConfig['maneja_inventario'] ?? false;
        final mostrarDebeHaber =
            storeConfig['mostrar_debe_haber_en_conteo_inventario'] ?? false;
        final autocompletarCantidad =
            storeConfig['autocompletar_cantidad_real_conteo'] ?? false;
        print(
          '🏪 Configuración de tienda cargada - Maneja inventario 2: $manejaInventario, '
          'Mostrar debe haber: $mostrarDebeHaber, '
          'Autocompletar cantidad real: $autocompletarCantidad',
        );

        if (mounted) {
          setState(() {
            _manejaInventario = manejaInventario;
            _mostrarDebeHaberEnConteo = mostrarDebeHaber;
            _autocompletarCantidadRealConteo = autocompletarCantidad;
            print(
              '✅ setState ejecutado - _manejaInventario ahora es: $_manejaInventario',
            );
          });

          // If inventory is managed, check if this is the last open shift (solo online)
          if (_manejaInventario) {
            if (!isOffline) {
              _checkIfLastOpenShift();
            } else {
              setState(() {
                _checkingShiftStatus = false;
              });
            }
          } else {
            setState(() {
              _checkingShiftStatus = false;
            });
          }
        } else {
          print('⚠️ Widget no montado, no se puede ejecutar setState');
        }
      } else {
        print('⚠️ No se encontró configuración de tienda');
        if (mounted) {
          setState(() {
            _manejaInventario = false;
            _mostrarDebeHaberEnConteo = false;
            _autocompletarCantidadRealConteo = false;
            _checkingShiftStatus = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error cargando configuración de tienda: $e');
      if (mounted) {
        setState(() {
          _manejaInventario = false;
          _mostrarDebeHaberEnConteo = false;
          _autocompletarCantidadRealConteo = false;
          _checkingShiftStatus = false;
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      final workerProfile = await _userPrefs.getWorkerProfile();

      setState(() {
        _userName = '${workerProfile['nombres']} ${workerProfile['apellidos']}';
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _userName = 'Usuario';
      });
    }
  }

  /// Cargar configuración del trabajador para control de inventario
  Future<void> _loadWorkerConfig() async {
    try {
      final manejaAperturaControl =
          await _userPrefs.loadWorkerManejaAperturaControl();

      if (mounted) {
        setState(() {
          _trabajadorManejaAperturaControl = manejaAperturaControl;
        });

        print(
          '👤 Trabajador maneja apertura control (cierre): $_trabajadorManejaAperturaControl',
        );
      }
    } catch (e) {
      print('❌ Error cargando configuración de trabajador: $e');
      // Mantener valor por defecto (true) en caso de error
    }
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  /// Efectivo inicial de la moneda base (la RPC lo devuelve sin desglose).
  double get _montoInicialCaja =>
      _efectivoInicialPorDivisa[PriceUtils.baseCurrency] ?? 0.0;

  /// Ajusta los campos de efectivo real a las divisas habilitadas en la tienda.
  ///
  /// Solo añade: un controlador ya creado se conserva (y se libera en
  /// [dispose]) para no perder lo tecleado mientras se resolvía la consulta.
  Future<void> _loadDivisasCaja() async {
    final divisas = await TurnoService.divisasDeCaja();
    if (!mounted) return;
    setState(() {
      for (final divisa in divisas) {
        _efectivoRealControllers.putIfAbsent(
          divisa,
          () => TextEditingController(text: '0'),
        );
      }
      _divisasCaja = divisas;
    });
  }

  /// Efectivo esperado por divisa = inicial + efectivo cobrado **de esa divisa**,
  /// menos los egresos en efectivo de esa misma divisa.
  ///
  /// Cada importe se descuenta de su divisa: un egreso en USD no puede bajar el
  /// CUP que debe haber en el cajón. Con una sola divisa el resultado es el de
  /// siempre.
  Map<String, double> get _efectivoEsperadoPorDivisa {
    final divisas = <String>{
      ..._divisasCaja,
      ..._efectivoInicialPorDivisa.keys,
      ..._efectivoPorDivisa.keys,
      ..._egresosEfectivoPorDivisa.keys,
    };
    final esperado = <String, double>{
      for (final divisa in divisas)
        divisa:
            (_efectivoInicialPorDivisa[divisa] ?? 0) +
            (_efectivoPorDivisa[divisa] ?? 0),
    };
    for (final egreso in _egresosEfectivoPorDivisa.entries) {
      esperado[egreso.key] = (esperado[egreso.key] ?? 0) - egreso.value;
    }
    return esperado;
  }

  /// Efectivo contado de una divisa (importe nativo tecleado).
  double _efectivoRealDe(String divisa) =>
      _parseDouble(_efectivoRealControllers[divisa]?.text);

  /// Efectivo contado por divisa, leído de los campos (importes nativos).
  ///
  /// Se enumeran las divisas habilitadas, no el mapa de controladores: así el
  /// mapa que viaja a la RPC tiene exactamente una entrada por campo visible.
  Map<String, double> get _efectivoRealPorDivisa => {
    for (final divisa in _divisasCaja) divisa: _efectivoRealDe(divisa),
  };

  /// Diferencia contado − esperado para cada divisa habilitada.
  Map<String, double> get _diferenciaPorDivisa {
    final esperado = _efectivoEsperadoPorDivisa;
    return {
      for (final divisa in _divisasCaja)
        divisa: _efectivoRealDe(divisa) - (esperado[divisa] ?? 0),
    };
  }

  /// Efectivo inicial por divisa de un resumen (RPC o caché).
  ///
  /// Prioriza el mapa nuevo `efectivo_inicial_por_moneda`; si no está, usa las
  /// columnas vigentes: `efectivo_inicial` es la moneda base y
  /// `efectivo_inicial_usd` la única divisa extra que el backend separaba.
  Map<String, double> _montoInicialDeResumen(Map<String, dynamic> data) {
    final porDivisa = _mapaPorDivisa(data['efectivo_inicial_por_moneda']);
    if (porDivisa.isNotEmpty) return porDivisa;

    return {
      PriceUtils.baseCurrency: _parseDouble(
        data['efectivo_inicial'] ?? data['monto_inicial_caja'],
      ),
      if (data['efectivo_inicial_usd'] != null)
        'USD': _parseDouble(data['efectivo_inicial_usd']),
    };
  }

  /// Efectivo cobrado por divisa de un resumen (RPC o caché).
  ///
  /// `desglose_monedas` (`fn_resumen_diario_cierre_v4` y las `_v2` de turno) es
  /// la fuente exacta por divisa; las columnas vigentes solo distinguen base y
  /// USD, así que se usan como respaldo.
  Map<String, double> _efectivoDeResumen(Map<String, dynamic> data) {
    final desglose = _desgloseEfectivoNativo(data['desglose_monedas']);
    if (desglose.isNotEmpty) return desglose;

    return {
      PriceUtils.baseCurrency: _parseDouble(
        data['total_efectivo'] ?? data['efectivo_real'],
      ),
      if (data['efectivo_usd'] != null || data['ventas_usd_efectivo'] != null)
        'USD': _parseDouble(
          data['efectivo_usd'] ?? data['ventas_usd_efectivo'],
        ),
    };
  }

  /// Importe **nativo** de un campo concreto por divisa desde
  /// `desglose_monedas`: `[{"moneda":"USD","efectivo_nativo":10,...}, ...]`.
  ///
  /// Se parametriza por campo en vez de duplicar el bucle: efectivo y digital
  /// tienen exactamente la misma forma y solo cambia la clave.
  Map<String, double> _desgloseNativo(dynamic raw, String campo) {
    if (raw is! List) return const {};
    final porDivisa = <String, double>{};
    for (final fila in raw) {
      if (fila is! Map) continue;
      final divisa = (fila['moneda'] ?? '').toString().trim().toUpperCase();
      if (divisa.isEmpty) continue;
      porDivisa[divisa] = _parseDouble(fila[campo]);
    }
    return porDivisa;
  }

  Map<String, double> _desgloseEfectivoNativo(dynamic raw) =>
      _desgloseNativo(raw, 'efectivo_nativo');

  /// Normaliza un jsonb `{"CUP":1000,"USD":20}` a `Map<String,double>`.
  Map<String, double> _mapaPorDivisa(dynamic raw) {
    if (raw is! Map) return const {};
    final porDivisa = <String, double>{};
    raw.forEach((codigo, monto) {
      final divisa = codigo.toString().trim().toUpperCase();
      if (divisa.isEmpty) return;
      porDivisa[divisa] = _parseDouble(monto);
    });
    return porDivisa;
  }

  /// Efectivo por divisa de las órdenes locales, completado con el desglose que
  /// envió el servidor.
  ///
  /// Las órdenes locales mandan en las divisas que conocen —incluyen ventas
  /// offline que el servidor todavía no tiene— y el desglose rellena las que no
  /// aparecen. Sin él, una divisa de la que no hubiera órdenes cargadas se leía
  /// como 0.
  Map<String, double> _conDesgloseServidor(
    Map<String, double> locales,
    Map<String, double> servidor,
  ) => servidor.isEmpty ? locales : {...servidor, ...locales};

  /// Calcula totales de cierre a partir de las órdenes locales. Soporta pagos
  /// mixtos y usa las mismas claves que devuelve listar_ordenes.
  ///
  /// `efectivoBase` / `transferenciaBase` son los consolidados en moneda base
  /// (lo que suman las ventas); los mapas guardan el importe NATIVO por divisa,
  /// que es con lo que se cuadra la caja.
  ({
    double ventas,
    double efectivoBase,
    double transferenciaBase,
    Map<String, double> efectivoPorDivisa,
    Map<String, double> transferenciaPorDivisa,
    num productos,
    int operaciones,
  })
  _calculateClosureTotalsFromOrders(List<Order> orders) {
    double ventas = 0.0;
    double efectivoBase = 0.0;
    double transferenciaBase = 0.0;
    final efectivoPorDivisa = <String, double>{};
    final transferenciaPorDivisa = <String, double>{};
    // FASE 3 presentaciones: `num`, no `int`. Antes se acumulaba con
    // `item.cantidad.toInt()`, que TRUNCA cada linea por separado: media
    // libra (0,5) sumaba 0, y tres lineas de 0,5 kg daban 0 en vez de 1,5.
    // El cierre offline tiene que dar lo mismo que el online, que ya no
    // redondea desde fn_resumen_diario_cierre_v2.
    num productos = 0;
    int operaciones = 0;

    for (final order in orders) {
      final isVendida =
          order.status == OrderStatus.completada ||
          order.status == OrderStatus.pagoConfirmado ||
          order.status == OrderStatus.pendienteDeSincronizacion ||
          order.status == OrderStatus.enviada;

      if (!isVendida) continue;

      operaciones++;
      ventas += order.total;
      productos += order.items.fold<num>(
        0,
        (sum, item) => sum + item.cantidad,
      );

      double efectivoOrdenCup = 0.0;
      double transferenciaOrdenCup = 0.0;
      final pagos = order.pagos;

      if (pagos != null && pagos.isNotEmpty) {
        for (final raw in pagos) {
          final pago = PriceUtils.asPaymentMap(raw);
          if (pago == null) continue;
          if (PriceUtils.paymentIsPending(pago)) continue;

          final moneda = PriceUtils.paymentCurrency(pago);
          final montoNativo = PriceUtils.paymentAmount(pago);
          final montoCup = PriceUtils.paymentCupEquivalent(pago);

          if (PriceUtils.paymentIsCash(pago)) {
            // Importe NATIVO de la divisa: es lo que hay físicamente en caja y
            // lo que el arqueo compara contra el esperado de ESA divisa. Antes
            // se apartaba solo el USD y el resto se consolidaba, así que una
            // tercera moneda no se podía cuadrar.
            efectivoPorDivisa.update(
              moneda,
              (total) => total + montoNativo,
              ifAbsent: () => montoNativo,
            );
            efectivoBase += montoCup;
            efectivoOrdenCup += montoCup;
          } else {
            transferenciaPorDivisa.update(
              moneda,
              (total) => total + montoNativo,
              ifAbsent: () => montoNativo,
            );
            transferenciaBase += montoCup;
            transferenciaOrdenCup += montoCup;
          }
        }
      }

      // Fallback solo para órdenes offline sin pagos desglosados.
      if (order.isOfflineOrder &&
          efectivoOrdenCup + transferenciaOrdenCup == 0 &&
          order.total > 0) {
        final method = (order.paymentMethod ?? '').toLowerCase();
        // Sin desglose no hay divisa que atribuir: la venta se registró en la
        // moneda base, igual que antes de esto.
        final esEfectivo =
            method.contains('efectivo') || method.contains('cash');
        if (esEfectivo) {
          efectivoBase += order.total;
        } else {
          transferenciaBase += order.total;
        }
        final porDivisa = esEfectivo ? efectivoPorDivisa : transferenciaPorDivisa;
        porDivisa.update(
          PriceUtils.baseCurrency,
          (total) => total + order.total,
          ifAbsent: () => order.total,
        );
      }
    }

    return (
      ventas: ventas,
      efectivoBase: efectivoBase,
      transferenciaBase: transferenciaBase,
      efectivoPorDivisa: efectivoPorDivisa,
      transferenciaPorDivisa: transferenciaPorDivisa,
      productos: productos,
      operaciones: operaciones,
    );
  }

  Future<void> _loadDailySummary() async {
    try {
      setState(() {
        _isLoadingData = true;
      });

      final useLocal = await _userPrefs.shouldUseLocalData();

      // Turno abierto obligatorio para el cierre.
      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) {
        print('⚠️ No open shift found');
        final closedPending =
            await _userPrefs.getClosedPendingOfflineTurnos();
        if (!mounted) return;
        setState(() {
          _isLoadingData = false;
        });
        if (closedPending.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, '/cierre-pendiente');
          });
          return;
        }
        if (mounted) {
          _showNoOpenShiftAlert();
        }
        return;
      }

      _fechaAperturaTurno =
          DateTime.tryParse(
            turnoAbierto['fecha_apertura']?.toString() ?? '',
          )?.toLocal();

      // Cargar TODAS las órdenes de ESTE turno combinando cache offline +
      // pendientes de sincronización + (si hay conexión real) datos frescos
      // del servidor. Así, si se pasó a modo offline habiendo ya ventas
      // hechas en línea, esas ventas se siguen sumando en el cierre. La
      // sincronización de pendientes hacia el servidor sigue siendo
      // responsabilidad independiente de auto_sync_service.
      await _orderService.loadOrdersForOpenTurnoUnified();

      if (useLocal) {
        print('🔌 Modo local - Resumen del turno abierto...');
        await _loadDailySummaryOffline();
      } else {
        print('🌐 Modo online - Resumen del turno abierto...');
        await _loadDailySummaryOnline(turnoAbierto);
      }

      await _calcularDatosCierre();
    } catch (e) {
      print('❌ Error loading daily summary: $e');
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  Future<void> _loadDailySummaryOnline(
    Map<String, dynamic> turnoAbierto,
  ) async {
    try {
      // Preferir resumen por id de turno (no el diario, que mezcla turnos).
      final idRaw = turnoAbierto['id'] ?? turnoAbierto['server_id_turno'];
      final idTurno =
          idRaw is int
              ? idRaw
              : (idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw'));

      Map<String, dynamic>? data;
      if (idTurno != null) {
        print('🧪 Loading summary with fn_resumen_turno_por_id ($idTurno)');
        data = await TurnoService.getResumenTurnoPorId(idTurno);
      }
      data ??= await TurnoService.getResumenTurnoKPI();

      if (data == null) {
        // Último recurso: RPC diario (puede incluir más de un turno del día).
        final idTpv = await _userPrefs.getIdTpv();
        final userID = await _userPrefs.getUserId();
        if (idTpv != null) {
          print(
            '⚠️ Fallback resumen diario de cierre - TPV: $idTpv (puede mezclar turnos)',
          );
          // FASE 4: `_v4` trae `desglose_monedas` (efectivo nativo por divisa)
          // y cae sola a `_v2` si el backend aún no la tiene.
          data = await TurnoService.getResumenDiarioCierre(
            idTpv: idTpv,
            usuario: userID,
          );
        }
      }

      if (data == null) {
        setState(() {
          _isLoadingData = false;
        });
        return;
      }

      final resumen = data;
      final efectivoInicial = _montoInicialDeResumen(resumen);
      final efectivoDelTurno = _efectivoDeResumen(resumen);
      // Desglose autoritativo del servidor (RPC `_v2`): se guarda aparte para
      // que el recálculo desde las órdenes locales no borre las divisas que
      // solo él conoce. Vacío si el backend aún no devuelve la columna.
      final desgloseServidor = _desgloseEfectivoNativo(
        resumen['desglose_monedas'],
      );
      final desgloseDigitalServidor = _desgloseNativo(
        resumen['desglose_monedas'],
        'digital_nativo',
      );

      setState(() {
        _efectivoInicialPorDivisa = efectivoInicial;
        _efectivoPorDivisa = efectivoDelTurno;
        _efectivoDesgloseServidor = desgloseServidor;
        _digitalDesgloseServidor = desgloseDigitalServidor;
        _ventasTotales = (resumen['ventas_totales'] ?? 0.0).toDouble();
        _productosVendidos = (resumen['productos_vendidos'] as num?) ?? 0;
        _productosVendidosBase = resumen['productos_vendidos_base'] as num?;
        _productosVendidosDesglose =
            resumen['productos_vendidos_desglose'] as String?;
        _ticketPromedio = (resumen['ticket_promedio'] ?? 0.0).toDouble();
        _operacionesTotales = (resumen['operaciones_totales'] ?? 0).toInt();
        _operacionesPorHora =
            (resumen['operaciones_por_hora'] ?? 0.0).toDouble();
        _totalEfectivo =
            (resumen['total_efectivo'] ?? resumen['efectivo_real'] ?? 0.0)
                .toDouble();
        _totalTransferencias =
            (resumen['total_transferencias'] ??
                    (_ventasTotales - _totalEfectivo))
                .toDouble();
        _porcentajeEfectivo =
            (resumen['porcentaje_efectivo'] ?? 70.0).toDouble();
        _porcentajeOtros = (resumen['porcentaje_otros'] ?? 30.0).toDouble();
        _conciliacionEstado =
            resumen['conciliacion_estado']?.toString() ?? 'Pendiente';
        _isLoadingData = false;
      });
    } catch (e) {
      print('❌ Error loading online daily summary: $e');
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  Future<void> _loadDailySummaryOffline() async {
    try {
      print('📱 Cargando resumen de cierre desde cache offline...');

      // Obtener resumen de cierre actualizado con órdenes offline
      final resumenCierre =
          await _userPrefs.getResumenCierreWithOfflineOrders();

      if (resumenCierre != null) {
        print('✅ Resumen de cierre cargado desde cache offline');
        print('📊 Datos disponibles: ${resumenCierre.keys.toList()}');

        setState(() {
          // Mapear campos desde el cache del resumen de cierre
          _efectivoInicialPorDivisa = _montoInicialDeResumen(resumenCierre);
          _efectivoPorDivisa = _efectivoDeResumen(resumenCierre);
          _ventasTotales =
              (resumenCierre['total_ventas'] ??
                      resumenCierre['ventas_totales'] ??
                      0.0)
                  .toDouble();
          _productosVendidos =
              (resumenCierre['productos_vendidos'] as num?) ?? 0;
          _productosVendidosBase =
              resumenCierre['productos_vendidos_base'] as num?;
          _productosVendidosDesglose =
              resumenCierre['productos_vendidos_desglose'] as String?;
          _ticketPromedio =
              (resumenCierre['ticket_promedio'] ?? 0.0).toDouble();

          // Campos específicos del resumen de cierre
          _operacionesTotales =
              (resumenCierre['operaciones_totales'] ?? 0).toInt();
          _operacionesPorHora =
              (resumenCierre['operaciones_por_hora'] ?? 0.0).toDouble();
          // Sin desglose se deja en 0: repartir las ventas con un porcentaje
          // fijo (70/30) inventaba un efectivo que no cuadra con ninguna
          // divisa y volvía ficción la diferencia del arqueo.
          _totalEfectivo =
              (resumenCierre['total_efectivo'] ??
                      resumenCierre['efectivo_real'] ??
                      0.0)
                  .toDouble();
          _totalTransferencias =
              (resumenCierre['total_transferencias'] ??
                      _ventasTotales - _totalEfectivo)
                  .toDouble();
          _porcentajeEfectivo =
              (resumenCierre['porcentaje_efectivo'] ?? 0.0).toDouble();
          _porcentajeOtros =
              (resumenCierre['porcentaje_otros'] ?? 0.0).toDouble();
          _conciliacionEstado =
              resumenCierre['conciliacion_estado'] ?? 'Pendiente';
          // _manejaInventario = resumenCierre['maneja_inventario'] ?? false; // Comentado: se usa valor de configuración

          _isLoadingData = false;
        });

        print('💰 Datos cargados desde cache offline (con órdenes offline):');
        print('  - Monto inicial: $_montoInicialCaja');
        print('  - Ventas totales: $_ventasTotales');
        print('  - Productos vendidos: $_productosVendidos');
        print('  - Ticket promedio: $_ticketPromedio');
        print('  - Total efectivo: $_totalEfectivo');
        print('  - Total transferencias: $_totalTransferencias');

        // Mostrar información de órdenes offline si las hay
        if (resumenCierre['ordenes_offline'] != null &&
            resumenCierre['ordenes_offline'] > 0) {
          print('📱 Órdenes offline incluidas:');
          print('  - Órdenes offline: ${resumenCierre['ordenes_offline']}');
          print('  - Ventas offline: \$${resumenCierre['ventas_offline']}');
        }
      } else {
        // Fallback: intentar cargar desde resumen de turno si no hay resumen de cierre
        print('⚠️ No hay resumen de cierre - intentando resumen de turno...');
        final resumenTurno = await _userPrefs.getTurnoResumenCache();

        if (resumenTurno != null) {
          print('✅ Usando resumen de turno como fallback');
          setState(() {
            _efectivoInicialPorDivisa = _montoInicialDeResumen(resumenTurno);
            _efectivoPorDivisa = _efectivoDeResumen(resumenTurno);
            _ventasTotales = (resumenTurno['ventas_totales'] ?? 0.0).toDouble();
            _productosVendidos =
                (resumenTurno['productos_vendidos'] as num?) ?? 0;
            _productosVendidosBase =
                resumenTurno['productos_vendidos_base'] as num?;
            _productosVendidosDesglose =
                resumenTurno['productos_vendidos_desglose'] as String?;
            _ticketPromedio =
                (resumenTurno['ticket_promedio'] ?? 0.0).toDouble();

            // Campos ausentes: se dejan en 0. El 70/30 que había aquí no
            // significa nada con varias divisas e inventaba el "debe haber".
            _operacionesTotales = 0;
            _operacionesPorHora = 0.0;
            _totalEfectivo =
                (resumenTurno['total_efectivo'] ??
                        resumenTurno['efectivo_real'] ??
                        0.0)
                    .toDouble();
            _totalTransferencias =
                (resumenTurno['total_transferencias'] ?? 0.0).toDouble();
            _porcentajeEfectivo = 0.0;
            _porcentajeOtros = 0.0;
            _conciliacionEstado = 'Pendiente (Fallback)';
            // _manejaInventario = false; // Comentado: se usa valor de configuración

            _isLoadingData = false;
          });
        } else {
          print('⚠️ No hay cache disponible - usando valores por defecto');
          setState(() {
            // Valores por defecto cuando no hay cache
            _efectivoInicialPorDivisa = {PriceUtils.baseCurrency: 500.0};
            _efectivoPorDivisa = {};
            _ventasTotales = 0.0;
            _productosVendidos = 0;
            _ticketPromedio = 0.0;
            _operacionesTotales = 0;
            _operacionesPorHora = 0.0;
            _totalEfectivo = 0.0;
            _totalTransferencias = 0.0;
            _porcentajeEfectivo = 0.0;
            _porcentajeOtros = 0.0;
            _conciliacionEstado = 'Sin datos';
            // _manejaInventario = false; // Comentado: se usa valor de configuración

            _isLoadingData = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error cargando resumen offline: $e');
      setState(() {
        // Fallback por defecto
        _efectivoInicialPorDivisa = {PriceUtils.baseCurrency: 500.0};
        _ventasTotales = 0.0;
        _isLoadingData = false;
      });
    }
  }

  void _showNoOpenShiftAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('No hay turno abierto'),
            content: const Text(
              'No se puede crear un cierre sin un turno abierto',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                ),
                child: const Text('Volver'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _observacionesController.dispose();
    _inventorySaveTimer?.cancel();
    // Dispose inventory controllers
    for (var controller in _inventoryControllers.values) {
      controller.dispose();
    }
    // Dispose de los campos de efectivo real (uno por divisa).
    for (final controller in _efectivoRealControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInventoryProducts() async {
    // Offline / full-offline: cache local (evitar RPCs).
    final isOffline = await _userPrefs.shouldUseLocalData();
    if (isOffline) {
      print('🔌 Modo offline - cargando inventario desde cache');
      return _loadInventoryProductsOffline();
    }

    if (!_manejaInventario) {
      print('⏭️ Tienda no maneja inventario - Omitiendo carga');
      return;
    }

    try {
      print('📦 Cargando productos de inventario para cierre...');

      final idTienda = await _userPrefs.getIdTienda();
      print('🏪 ID Tienda obtenido: $idTienda');
      if (idTienda == null) {
        throw Exception('ID de tienda no encontrado');
      }
      final idAlmacen = await _userPrefs.getIdAlmacen();

      print(
        '🔄 Llamando a fn_listar_inventario_productos_paged... ${idAlmacen}',
      );
      final response = await Supabase.instance.client.rpc(
        'fn_listar_inventario_productos_paged2',
        params: {
          'p_id_tienda': idTienda,
          'p_limite': 9999,
          'p_mostrar_sin_stock': false,
          'p_pagina': 1,
          'p_id_almacen': idAlmacen,
        },
      );
      print('✅ Respuesta recibida: ${response?.length ?? 0} items');

      if (response != null && response is List) {
        // Agrupar productos SOLO por id_producto (sin considerar ubicaciones ni presentaciones)
        final Map<int, InventoryProduct> productsByIdMap = {};

        for (var item in response) {
          // print(item);
          try {
            final product = InventoryProduct.fromSupabaseRpc(item);

            // Solo agregar el primer producto de cada ID (ignorar duplicados por presentación/ubicación)
            if (!productsByIdMap.containsKey(product.id)) {
              productsByIdMap[product.id] = product;
              print(
                '📦 Producto agregado: ${product.nombreProducto} (ID: ${product.id})',
              );
            } else {
              print(
                '⏭️ Omitiendo duplicado: ${product.nombreProducto} (ID: ${product.id})',
              );
            }
          } catch (e) {
            print('❌ Error procesando producto: $e');
          }
        }

        // Crear lista consolidada (solo con stock) y controllers
        final products =
            productsByIdMap.values.toList()..sort(
              (a, b) => a.nombreProducto.toLowerCase().compareTo(
                b.nombreProducto.toLowerCase(),
              ),
            );
        for (var product in products) {
          // Crear controller para cada producto único
          if (!_inventoryControllers.containsKey(product.id)) {
            _inventoryControllers[product.id] = TextEditingController();
          }
        }

        setState(() {
          _inventoryProducts = products;
        });

        print('✅ ${products.length} productos únicos de inventario cargados');
      } else {
        setState(() {
          _inventoryProducts = [];
        });
      }
    } catch (e) {
      print('❌ Error cargando productos de inventario: $e');
      rethrow;
    }
  }

  /// Mostrar modal de control de inventario
  Future<void> _showInventoryCountModal() async {
    if (_isLoadingInventory) return;

    print('🔍 Estado antes de cargar:');
    print('  - _inventoryProducts.isEmpty: ${_inventoryProducts.isEmpty}');
    print('  - _inventoryProducts.length: ${_inventoryProducts.length}');

    setState(() {
      _isLoadingInventory = true;
    });

    try {
      // Cargar productos ANTES de mostrar el modal
      if (_inventoryProducts.isEmpty) {
        print('📦 Cargando productos antes de mostrar modal...');
        await _loadInventoryProducts();
      } else {
        print('⏭️ Productos ya cargados');
      }

      await _loadStockRealProductos();
      await _loadInventoryCounts();

      // Restaurar conteos previos o dejar vacío para marcarlos como pendientes.
      for (final product in _inventoryProducts) {
        final controller = _inventoryControllers[product.id];
        if (controller == null) continue;
        final savedQty = _pendingInventoryCounts[product.id];
        if (savedQty != null) {
          controller.text = _formatInventoryQty(savedQty);
        } else {
          controller.text = '';
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInventory = false;
        });
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: _buildInventoryCountModal(),
        );
      },
    );
  }

  /// Una sola llamada: stock_sistema + pendiente + en_camino + debe_haber.
  /// Offline: suma cantidades del cache local.
  Future<void> _loadStockRealProductos() async {
    _stockRealByProduct = {};
    if (_inventoryProducts.isEmpty) return;

    try {
      final isOffline = await _userPrefs.shouldUseLocalData();
      if (isOffline) {
        await _loadStockRealProductosOffline();
        return;
      }

      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) return;

      final idAlmacen = await _userPrefs.getIdAlmacen();
      final productIds = _inventoryProducts.map((p) => p.id).toList();
      print(
        '📦 RPC fn_stock_real_productos_cierre '
        '(tienda=$idTienda, almacen=$idAlmacen, ${productIds.length} productos)...',
      );

      final response = await Supabase.instance.client.rpc(
        'fn_stock_real_productos_cierre',
        params: {
          'p_id_tienda': idTienda,
          // Solo el almacén del vendedor (no toda la tienda).
          'p_id_almacen': idAlmacen,
          'p_ids_producto': productIds,
        },
      );

      final map = <int, _StockRealProducto>{};
      if (response is List) {
        for (final raw in response) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          final id = (row['id_producto'] as num?)?.toInt();
          if (id == null) continue;
          map[id] = _StockRealProducto(
            stockSistema: (row['stock_sistema'] as num?)?.toDouble() ?? 0,
            pendienteCarnaval:
                (row['pendiente_carnaval'] as num?)?.toDouble() ?? 0,
            enCamino: (row['en_camino'] as num?)?.toDouble() ?? 0,
            debeHaber: (row['debe_haber'] as num?)?.toDouble() ?? 0,
          );
        }
      }

      // Completar productos sin fila (0).
      for (final p in _inventoryProducts) {
        map.putIfAbsent(
          p.id,
          () => const _StockRealProducto(
            stockSistema: 0,
            pendienteCarnaval: 0,
            enCamino: 0,
            debeHaber: 0,
          ),
        );
      }

      _stockRealByProduct = map;
      print('✅ Stock real cargado para ${map.length} productos');
    } catch (e) {
      print('⚠️ Error cargando stock real batch: $e');
      _stockRealByProduct = {
        for (final p in _inventoryProducts)
          p.id: _StockRealProducto(
            stockSistema: p.cantidadFinal,
            pendienteCarnaval: 0,
            enCamino: 0,
            debeHaber: p.cantidadFinal,
          ),
      };
    }
  }

  Future<void> _loadStockRealProductosOffline() async {
    // Usar cantidades ya resueltas por InventoryService.buildFromOfflineCache.
    _stockRealByProduct = {
      for (final p in _inventoryProducts)
        p.id: _StockRealProducto(
          stockSistema: p.cantidadFinal,
          pendienteCarnaval: 0,
          enCamino: 0,
          debeHaber: p.cantidadFinal,
        ),
    };
  }

  /// Carga los conteos de inventario previamente guardados localmente.
  Future<void> _loadInventoryCounts() async {
    final idTpv = await _userPrefs.getIdTpv();
    final saved = await _userPrefs.getInventoryCountCierre(idTpv);
    _pendingInventoryCounts = saved.map(
      (key, value) => MapEntry(int.tryParse(key) ?? 0, value),
    );
  }

  /// Guarda los conteos localmente con un pequeño retardo para no saturar
  /// SharedPreferences mientras el usuario escribe.
  void _onInventoryCountChanged(int productId, String value) {
    final qty = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    _pendingInventoryCounts[productId] = qty;
    _scheduleSaveInventoryCounts();
  }

  void _scheduleSaveInventoryCounts() {
    _inventorySaveTimer?.cancel();
    _inventorySaveTimer = Timer(const Duration(milliseconds: 500), () async {
      final idTpv = await _userPrefs.getIdTpv();
      await _userPrefs.saveInventoryCountCierre(
        idTpv,
        _pendingInventoryCounts.map((k, v) => MapEntry(k.toString(), v)),
      );
    });
  }

  Future<void> _clearInventoryCounts() async {
    _inventorySaveTimer?.cancel();
    _pendingInventoryCounts.clear();
    final idTpv = await _userPrefs.getIdTpv();
    await _userPrefs.clearInventoryCountCierre(idTpv);
  }

  /// Widget del modal de control de inventario
  Widget _buildInventoryCountModal() {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return StatefulBuilder(
          builder: (modalContext, modalSetState) {
            final keyboardOpen =
                MediaQuery.viewInsetsOf(modalContext).bottom > 0;
            return Container(
              decoration: const BoxDecoration(
                color: VentiqHomeTheme.card,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: VentiqHomeTheme.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2, color: Colors.white),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Control de Inventario',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // Info text — ocultar con teclado para ganar espacio
                  if (!keyboardOpen)
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: VentiqHomeTheme.primary.withValues(alpha: 0.06),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: VentiqHomeTheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _mostrarDebeHaberEnConteo
                                  ? 'Compara el "debe haber" e ingresa la cantidad real contada'
                                  : 'Ingresa la cantidad real contada de cada producto',
                              style: const TextStyle(
                                fontSize: 14,
                                color: VentiqHomeTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Acciones masivas — ocultar con teclado
                  if (!keyboardOpen &&
                      !_isLoadingInventory &&
                      _inventoryProducts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: VentiqHomeTheme.surface,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          if (_mostrarDebeHaberEnConteo &&
                              _autocompletarCantidadRealConteo)
                            TextButton.icon(
                              onPressed: () {
                                for (final p in _inventoryProducts) {
                                  final debe =
                                      _stockRealByProduct[p.id]?.debeHaber ??
                                      p.cantidadFinalReal;
                                  _inventoryControllers[p.id]
                                      ?.text = _formatInventoryQty(debe);
                                  _pendingInventoryCounts[p.id] = debe;
                                }
                                _scheduleSaveInventoryCounts();
                                modalSetState(() {});
                              },
                              icon: const Icon(Icons.auto_fix_high, size: 18),
                              label: const Text("Rellenar con 'debe haber'"),
                            ),
                          TextButton.icon(
                            onPressed: () {
                              for (final p in _inventoryProducts) {
                                _inventoryControllers[p.id]?.text = '0';
                                _pendingInventoryCounts[p.id] = 0.0;
                              }
                              _scheduleSaveInventoryCounts();
                              modalSetState(() {});
                            },
                            icon: const Icon(Icons.exposure_zero, size: 18),
                            label: const Text('Todo en 0'),
                          ),
                        ],
                      ),
                    ),

                  // Lista de productos
                  Expanded(
                    child:
                        _isLoadingInventory
                            ? const Center(child: CircularProgressIndicator())
                            : _inventoryProducts.isEmpty
                            ? const Center(
                              child: Text('No hay productos de inventario'),
                            )
                            : ListView.builder(
                              controller: scrollController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
                              itemCount: _inventoryProducts.length,
                              itemBuilder: (context, index) {
                                final product = _inventoryProducts[index];
                                final controller =
                                    _inventoryControllers[product.id]!;
                                final debeHaber =
                                    _stockRealByProduct[product.id]
                                        ?.debeHaber ??
                                    product.cantidadFinalReal;
                                final isMissing = _missingInventoryProductIds
                                    .contains(product.id);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color:
                                        isMissing
                                            ? VentiqHomeTheme.danger.withValues(
                                              alpha: 0.06,
                                            )
                                            : VentiqHomeTheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color:
                                          isMissing
                                              ? VentiqHomeTheme.danger
                                                  .withValues(alpha: 0.30)
                                              : VentiqHomeTheme.border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (isMissing) ...[
                                        const Icon(
                                          Icons.warning_amber_rounded,
                                          color: VentiqHomeTheme.danger,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.nombreProducto,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    VentiqHomeTheme.textPrimary,
                                              ),
                                            ),
                                            if (_mostrarDebeHaberEnConteo) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Debe haber: ${_formatInventoryQty(debeHaber)}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color:
                                                      VentiqHomeTheme.primary,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 100,
                                        child: TextFormField(
                                          controller: controller,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          textInputAction: TextInputAction.next,
                                          scrollPadding: const EdgeInsets.only(
                                            bottom: 120,
                                          ),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'^\d+\.?\d{0,2}'),
                                            ),
                                          ],
                                          decoration: InputDecoration(
                                            labelText: 'Real',
                                            hintText: '0',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    VentiqHomeTheme.radiusField,
                                                  ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                            isDense: true,
                                          ),
                                          style: const TextStyle(fontSize: 14),
                                          onChanged: (value) {
                                            _onInventoryCountChanged(
                                              product.id,
                                              value,
                                            );
                                            if (_missingInventoryProductIds
                                                .contains(product.id)) {
                                              _missingInventoryProductIds
                                                  .remove(product.id);
                                              modalSetState(() {});
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                  ),

                  // Botones — se mantienen visibles; el Padding exterior ya los
                  // sube por encima del teclado.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: VentiqHomeTheme.card,
                      border: Border(
                        top: BorderSide(color: VentiqHomeTheme.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(
                                color: VentiqHomeTheme.border,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              final missing =
                                  _inventoryProducts
                                      .where(
                                        (p) =>
                                            (_inventoryControllers[p.id]?.text
                                                    .trim()
                                                    .isEmpty ??
                                                true),
                                      )
                                      .map((p) => p.id)
                                      .toSet();
                              if (missing.isNotEmpty) {
                                modalSetState(() {
                                  _missingInventoryProductIds
                                    ..clear()
                                    ..addAll(missing);
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Faltan ${missing.length} productos por contar',
                                    ),
                                    backgroundColor: VentiqHomeTheme.warning,
                                  ),
                                );
                                return;
                              }

                              _inventorySaveTimer?.cancel();
                              _scheduleSaveInventoryCounts();

                              setState(() {
                                _missingInventoryProductIds.clear();
                                _inventorySet = true;
                              });
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Inventario controlado correctamente',
                                  ),
                                  backgroundColor: VentiqHomeTheme.success,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: VentiqHomeTheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Guardar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadExpenses() async {
    try {
      setState(() {
        _isLoadingExpenses = true;
      });

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      List<Expense> expenses = [];

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Cargando egresos desde cache...');
        // Cargar egresos desde cache offline
        expenses = await _loadExpensesOffline();
      } else {
        print('🌐 Modo online - Obteniendo egresos desde servidor...');
        expenses = await TurnoService.getEgresosEnriquecidos();
      }

      // Calculate total expenses and separate by payment type
      double total = 0.0;
      double efectivo = 0.0;
      double transferencias = 0.0;
      // Desglose nativo de los egresos en efectivo: es el que descuenta el
      // arqueo, cada importe de SU divisa.
      final egresosEfectivoPorDivisa = <String, double>{};

      for (final expense in expenses) {
        total += expense.montoEntrega;
        // ✅ Solo es transferencia si esDigital == true. null cuenta como efectivo.
        final isDigital = expense.esDigital == true;
        if (isDigital) {
          transferencias += expense.montoEntrega;
        } else {
          efectivo += expense.montoEntrega;
          egresosEfectivoPorDivisa.update(
            expense.moneda,
            (acumulado) => acumulado + expense.montoEntrega,
            ifAbsent: () => expense.montoEntrega,
          );
        }
      }

      setState(() {
        _expenses = expenses;
        _totalEgresos = total;
        _egresosEfectivo = efectivo;
        _egresosTransferencias = transferencias;
        _egresosEfectivoPorDivisa = egresosEfectivoPorDivisa;
        _isLoadingExpenses = false;
      });
    } catch (e) {
      print('Error loading expenses: $e');
      setState(() {
        _isLoadingExpenses = false;
      });
    }
  }

  Future<List<Expense>> _loadExpensesOffline() async {
    try {
      print('📱 Cargando egresos desde cache offline...');

      // Obtener egresos desde cache específico (no desde offlineData general)
      final egresosData = await _userPrefs.getEgresosCache();

      if (egresosData.isNotEmpty) {
        final expenses =
            egresosData.map((expenseJson) {
              return Expense(
                idEgreso: expenseJson['id_egreso'] ?? 0,
                montoEntrega: (expenseJson['monto_entrega'] ?? 0.0).toDouble(),
                motivoEntrega: expenseJson['motivo_entrega'] ?? 'Sin motivo',
                nombreRecibe: expenseJson['nombre_recibe'] ?? 'Sin nombre',
                nombreAutoriza:
                    expenseJson['nombre_autoriza'] ?? 'Sin autorización',
                fechaEntrega:
                    expenseJson['fecha_entrega'] != null
                        ? DateTime.parse(expenseJson['fecha_entrega'])
                        : DateTime.now(),
                idMedioPago: expenseJson['id_medio_pago'],
                turnoEstado: expenseJson['turno_estado'] ?? 1,
                medioPago: expenseJson['medio_pago'],
                esDigital: expenseJson['es_digital'] ?? false,
                // Sin `moneda` (egresos previos a la Fase 4 o cache viejo) el
                // modelo asume la moneda base, que es donde se registraron. El
                // `??` es obligatorio: `Expense.moneda` no es nullable, así que
                // pasar null daría TypeError y el catch de arriba devolvería
                // una lista vacía, perdiendo TODOS los egresos.
                moneda: expenseJson['moneda'] ?? PriceUtils.baseCurrency,
              );
            }).toList();

        print('✅ Egresos cargados desde cache offline: ${expenses.length}');
        return expenses;
      } else {
        print('ℹ️ No hay egresos en cache offline');
        return [];
      }
    } catch (e) {
      print('❌ Error cargando egresos offline: $e');
      return [];
    }
  }

  /// Órdenes del turno abierto.
  ///
  /// `_orderService.orders` ya viene acotado al turno abierto por
  /// [OrderService.loadOrdersForOpenTurnoUnified] (que prioriza el match por
  /// id de turno y sólo cae a un filtro por fecha como respaldo). Volver a
  /// filtrar aquí por fecha de forma estricta podía descartar órdenes
  /// válidas del turno por pequeñas diferencias de zona horaria entre el
  /// `fecha_creacion` de la orden y el `fecha_apertura` del turno, por eso
  /// simplemente se devuelve la lista ya cargada.
  Future<List<Order>> _ordersOfOpenTurno() async {
    return List<Order>.from(_orderService.orders);
  }

  Future<void> _calcularDatosCierre() async {
    final orders = await _ordersOfOpenTurno();

    // Calcular totales reales desde las órdenes locales (online + offline).
    // Esto asegura que el cierre refleje los pagos reales, incluyendo ajustes
    // parciales hechos en el desglose de pagos.
    final totals = _calculateClosureTotalsFromOrders(orders);

    // Órdenes pendientes que deben cerrarse
    final pendientes =
        orders
            .where(
              (order) =>
                  order.status == OrderStatus.enviada ||
                  order.status == OrderStatus.procesando ||
                  order.status == OrderStatus.pagoConfirmado,
            )
            .toList();

    if (!mounted) return;
    setState(() {
      // Solo pisar los totales si tenemos órdenes cargadas; si no, conservar
      // los valores que vengan del resumen del servidor/cache.
      if (orders.isNotEmpty) {
        _ventasTotales = totals.ventas;
        _totalEfectivo = totals.efectivoBase;
        _totalTransferencias = totals.transferenciaBase;
        // El detalle nativo por divisa es lo que cuadra la caja; el esperado se
        // deriva de él (inicial + cobrado), no se guarda por separado. Las
        // divisas que solo conoce el servidor las completa `desglose_monedas`.
        _efectivoPorDivisa = _conDesgloseServidor(
          totals.efectivoPorDivisa,
          _efectivoDesgloseServidor,
        );
        _transferenciaPorDivisa = _conDesgloseServidor(
          totals.transferenciaPorDivisa,
          _digitalDesgloseServidor,
        );
        _productosVendidos = totals.productos;
        _operacionesTotales = totals.operaciones;
        _ticketPromedio =
            totals.operaciones > 0 ? totals.ventas / totals.operaciones : 0.0;
      }
      _ordenesAbiertas = pendientes.length;
      _ordenesPendientes = pendientes;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Efectivo que "debe haber" por divisa (inicial + cobrado, menos egresos en
    // la moneda base). Se calcula una vez por frame: lo usan el resumen, el
    // helper de cada campo y el widget de diferencia.
    final efectivoEsperado = _efectivoEsperadoPorDivisa;

    print('🔍 BUILD - _manejaInventario: $_manejaInventario');

    return Scaffold(
      backgroundColor: VentiqHomeTheme.surface,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: VentiqHomeTheme.primary,
        elevation: 0,
        title: const Text(
          'Crear Cierre',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Información del cierre
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: VentiqHomeTheme.border),
                  boxShadow: VentiqHomeTheme.shadowCard,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lock,
                          color: VentiqHomeTheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Cierre de Caja',
                          style: VentiqHomeTheme.tituloSeccion,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      'Fecha actual:',
                      _formatDate(DateTime.now().toLocal()),
                    ),
                    _buildInfoRow(
                      'Hora actual:',
                      _formatTime(DateTime.now().toLocal()),
                    ),
                    if (_fechaAperturaTurno != null) ...[
                      _buildInfoRow(
                        'Turno abierto desde:',
                        '${_formatDate(_fechaAperturaTurno!)} '
                            '${_formatTime(_fechaAperturaTurno!)}',
                      ),
                    ],
                    _buildInfoRow('Usuario:', _userName),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Resumen de ventas
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: VentiqHomeTheme.border),
                  boxShadow: VentiqHomeTheme.shadowCard,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resumen del Turno',
                      style: VentiqHomeTheme.tituloSeccion,
                    ),
                    const SizedBox(height: 12),

                    if (_isLoadingData) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: VentiqHomeTheme.primary,
                          ),
                        ),
                      ),
                    ] else ...[
                      // Ventas y productos
                      _buildInfoRow(
                        'Monto inicial:',
                        '\$${_montoInicialCaja.toMoneyString(2)}',
                      ),
                      _buildInfoRow(
                        'Ventas totales:',
                        '\$${_ventasTotales.toMoneyString(2)}',
                      ),
                      _buildInfoRow(
                        'Productos vendidos:',
                        _textoProductosVendidos(),
                      ),
                      _buildInfoRow(
                        'Ticket promedio:',
                        '\$${_ticketPromedio.toMoneyString(2)}',
                      ),
                      _buildInfoRow(
                        'Operaciones totales:',
                        '$_operacionesTotales operaciones',
                      ),
                      _buildInfoRow(
                        'Operaciones por hora:',
                        '${_operacionesPorHora.toStringAsFixed(1)} op/h',
                      ),

                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Medios de pago
                      const Text(
                        'Medios de Pago',
                        style: VentiqHomeTheme.rotuloBloque,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Total efectivo ${PriceUtils.baseCurrency}:',
                        '\$${_totalEfectivo.toMoneyString(2)} (${_porcentajeEfectivo.toStringAsFixed(1)}%)',
                      ),
                      // Efectivo NATIVO de cada divisa: sin convertir, que es
                      // como se cuenta en caja. La moneda base ya está arriba
                      // consolidada, así que solo se listan las demás.
                      for (final divisa in _divisasCaja)
                        if (divisa != PriceUtils.baseCurrency)
                          _buildInfoRow(
                            'Total efectivo $divisa:',
                            '\$${(_efectivoPorDivisa[divisa] ?? 0).toMoneyString(2)} $divisa',
                          ),
                      _buildInfoRow(
                        'Transferencias/Otros:',
                        '\$${_totalTransferencias.toMoneyString(2)} (${_porcentajeOtros.toStringAsFixed(1)}%)',
                      ),
                      for (final divisa in _divisasCaja)
                        _buildInfoRow(
                          'Efectivo esperado $divisa:',
                          '\$${(efectivoEsperado[divisa] ?? 0).toMoneyString(2)} $divisa',
                        ),

                      // Show expenses breakdown if there are any
                      if (_totalEgresos > 0) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          'Egresos del Turno',
                          style: VentiqHomeTheme.rotuloBloque,
                        ),
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          'Egresos en efectivo:',
                          '-\$${_egresosEfectivo.toMoneyString(2)}',
                          isNegative: true,
                        ),
                        _buildInfoRow(
                          'Egresos digitales:',
                          '-\$${_egresosTransferencias.toMoneyString(2)}',
                          isNegative: true,
                        ),
                        _buildInfoRow(
                          'Total egresos:',
                          '-\$${_totalEgresos.toMoneyString(2)}',
                          isNegative: true,
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                      ],
                      // Show conciliation status
                      if (_conciliacionEstado.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _conciliacionEstado == 'Conciliado'
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color:
                                  _conciliacionEstado == 'Conciliado'
                                      ? VentiqHomeTheme.success
                                      : VentiqHomeTheme.warning,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Estado: $_conciliacionEstado',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color:
                                    _conciliacionEstado == 'Conciliado'
                                        ? VentiqHomeTheme.success
                                        : VentiqHomeTheme.warning,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    // Órdenes pendientes warning (always show if there are pending orders)
                    if (_ordenesAbiertas > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: VentiqHomeTheme.warning.withValues(
                            alpha: 0.10,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: VentiqHomeTheme.warning.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning,
                              color: VentiqHomeTheme.warning,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _trabajadorManejaAperturaControl
                                  ? '$_ordenesAbiertas órdenes pendientes. Debes cerrarlas antes...'
                                  : '$_ordenesAbiertas órdenes pendientes. No se completarán automáticamente.',
                              style: TextStyle(
                                fontSize: 12,
                                color: VentiqHomeTheme.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Egresos del turno
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: VentiqHomeTheme.border),
                  boxShadow: VentiqHomeTheme.shadowCard,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.money_off,
                          color: VentiqHomeTheme.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Egresos del Turno',
                          style: VentiqHomeTheme.tituloSeccion,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Salidas de dinero registradas durante el turno',
                      style: TextStyle(
                        fontSize: 12,
                        color: VentiqHomeTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildExpensesList(),

                    // Show total expenses summary if there are expenses
                    if (_expenses.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Egresos:',
                            style: VentiqHomeTheme.tituloSeccion,
                          ),
                          Text(
                            '\$${_totalEgresos.toMoneyString(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: VentiqHomeTheme.danger,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Monto final en caja
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: VentiqHomeTheme.border),
                  boxShadow: VentiqHomeTheme.shadowCard,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monto Final en Caja',
                      style: VentiqHomeTheme.tituloSeccion,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ingrese el monto real contado en caja',
                      style: TextStyle(
                        fontSize: 12,
                        color: VentiqHomeTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showCashCountDialog,
                        icon: const Icon(
                          Icons.calculate_outlined,
                          color: VentiqHomeTheme.primary,
                        ),
                        label: const Text(
                          'Contar billetes',
                          style: TextStyle(color: VentiqHomeTheme.primary),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: VentiqHomeTheme.primary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Un campo "Efectivo real" por divisa habilitada, con su
                    // propio "Debe haber". La moneda base es obligatoria (es la
                    // unidad contable); el resto se puede dejar en 0.
                    for (final divisa in _divisasCaja) ...[
                      TextFormField(
                        controller: _efectivoRealControllers[divisa],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        scrollPadding: const EdgeInsets.only(bottom: 140),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}'),
                          ),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Efectivo real $divisa',
                          helperText:
                              'Debe haber: \$${(efectivoEsperado[divisa] ?? 0).toMoneyString(2)} $divisa',
                          prefixIcon: const Icon(Icons.attach_money),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              VentiqHomeTheme.radiusField,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        validator: (value) {
                          final texto = value?.trim() ?? '';
                          final esBase = divisa == PriceUtils.baseCurrency;
                          if (texto.isEmpty) {
                            return esBase ? 'El monto final es requerido' : null;
                          }
                          final monto = double.tryParse(texto);
                          if (monto == null || monto < 0) {
                            return 'Ingrese un monto válido';
                          }
                          return null;
                        },
                        onChanged: (_) {
                          setState(() {}); // Para actualizar la diferencia
                        },
                      ),
                      // Diferencia de ESA divisa, solo si hay algo tecleado.
                      if ((_efectivoRealControllers[divisa]?.text ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildDiferenciaDivisa(
                          divisa,
                          efectivoEsperado[divisa] ?? 0,
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),

              // Órdenes pendientes
              if (_ordenesPendientes.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: VentiqHomeTheme.border),
                    boxShadow: VentiqHomeTheme.shadowCard,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Órdenes Pendientes',
                        style: VentiqHomeTheme.tituloSeccion,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _trabajadorManejaAperturaControl
                            ? 'Debes cerrar estas órdenes antes de realizar el cierre'
                            : 'Estas órdenes no se completarán automáticamente',
                        style: const TextStyle(
                          fontSize: 12,
                          color: VentiqHomeTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._ordenesPendientes
                          .take(3)
                          .map((order) => _buildOrderItem(order)),
                      if (_ordenesPendientes.length > 3)
                        Text(
                          'Y ${_ordenesPendientes.length - 3} órdenes más...',
                          style: const TextStyle(
                            fontSize: 12,
                            color: VentiqHomeTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Observaciones
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: VentiqHomeTheme.border),
                  boxShadow: VentiqHomeTheme.shadowCard,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Observaciones',
                      style: VentiqHomeTheme.tituloSeccion,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Opcional - Notas sobre el cierre del día',
                      style: TextStyle(
                        fontSize: 12,
                        color: VentiqHomeTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _observacionesController,
                      maxLines: 3,
                      scrollPadding: const EdgeInsets.only(bottom: 140),
                      decoration: InputDecoration(
                        hintText: 'Ej: Cierre normal, inventario cuadrado...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            VentiqHomeTheme.radiusField,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Botón de control de inventario (si maneja inventario)
              if (_manejaInventario) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isLoadingInventory ? null : _showInventoryCountModal,
                    icon:
                        _isLoadingInventory
                            ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : Icon(
                              _inventorySet ? Icons.edit : Icons.inventory_2,
                            ),
                    label: Text(
                      _isLoadingInventory
                          ? 'Cargando inventario...'
                          : (_inventorySet
                              ? 'Editar Inventario'
                              : (_isLastOpenShift
                                  ? 'Controlar Inventario'
                                  : 'Controlar Inventario (OPCIONAL)')),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _inventorySet
                              ? VentiqHomeTheme.success
                              : (_isLastOpenShift
                                  ? VentiqHomeTheme.warning
                                  : VentiqHomeTheme.primary),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: (_inventorySet
                              ? VentiqHomeTheme.success
                              : (_isLastOpenShift
                                  ? VentiqHomeTheme.warning
                                  : VentiqHomeTheme.primary))
                          .withValues(alpha: 0.7),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 30),

              // Botón crear cierre
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _crearCierre,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VentiqHomeTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isProcessing
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                          : const Text(
                            'Crear Cierre',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Texto de "Productos vendidos" para el resumen del cierre.
  ///
  /// FASE 3 presentaciones. Prioriza el desglose que ya formatea el SQL
  /// ("2 Cajas + 5 Unidades") y, cuando hay mas de una presentacion, agrega el
  /// equivalente en unidades base entre parentesis — ese es el numero
  /// comparable, porque sumar cajas con unidades no significa nada.
  ///
  /// Sin desglose (RPC vieja o una sola presentacion) cae al numero de siempre,
  /// pero sin `.toInt()`: 0,5 kg debe leerse "0.5 unidades", no "1 unidades".
  String _textoProductosVendidos() {
    final desglose = _productosVendidosDesglose;
    final base = _productosVendidosBase;

    if (desglose != null && desglose.trim().isNotEmpty) {
      // Solo se agrega el equivalente si aporta algo (mas de una presentacion,
      // es decir cuando el desglose lleva un " + ").
      if (base != null && desglose.contains(' + ')) {
        return '$desglose  (= ${_fmtCantidad(base)} u. base)';
      }
      return desglose;
    }
    return '${_fmtCantidad(_productosVendidos)} unidades';
  }

  String _fmtCantidad(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  Widget _buildInfoRow(String label, String value, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isNegative ? FontWeight.w800 : FontWeight.w600,
                color:
                    isNegative
                        ? VentiqHomeTheme.danger
                        : VentiqHomeTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Vuelca el conteo de billetes en los campos de efectivo real.
  ///
  /// El diálogo devuelve importes **nativos** por divisa
  /// (`{'CUP': 1500.0, 'USD': 18.0}`). Antes devolvía un único total ya
  /// convertido a CUP y se escribía en el campo CUP: el efectivo en USD subía
  /// como si fueran CUP y el arqueo por divisa era imposible.
  Future<void> _showCashCountDialog() async {
    final contado = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) => CashCountDialog(userPreferencesService: _userPrefs),
    );
    if (contado == null || !mounted) return;

    setState(() {
      for (final entry in contado.entries) {
        final divisa = entry.key.trim().toUpperCase();
        if (divisa.isEmpty) continue;
        // Una divisa contada que no tuviera campo (configuración cambiada en
        // caliente) recibe el suyo: perder efectivo contado sería peor.
        if (!_divisasCaja.contains(divisa)) {
          _divisasCaja = [..._divisasCaja, divisa];
        }
        _efectivoRealControllers
            .putIfAbsent(divisa, () => TextEditingController())
            .text = entry.value.toStringAsFixed(2);
      }
    });
  }

  /// Diferencia de UNA divisa (contado − esperado). El código de divisa es un
  /// dato del widget, no una rama: el mismo widget sirve para cualquier moneda.
  Widget _buildDiferenciaDivisa(String divisa, double montoEsperado) {
    final diferencia = _efectivoRealDe(divisa) - montoEsperado;
    final isPositive = diferencia >= 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isPositive ? VentiqHomeTheme.success : VentiqHomeTheme.danger)
            .withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPositive ? VentiqHomeTheme.success : VentiqHomeTheme.danger,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Diferencia $divisa:',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color:
                  isPositive ? VentiqHomeTheme.success : VentiqHomeTheme.danger,
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}\$${diferencia.toMoneyString(2)} $divisa',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color:
                  isPositive ? VentiqHomeTheme.success : VentiqHomeTheme.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              order.id,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
          ),
          Text(
            '\$${order.total.toMoneyString(2)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: VentiqHomeTheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    return '${localDate.day.toString().padLeft(2, '0')}/${localDate.month.toString().padLeft(2, '0')}/${localDate.year}';
  }

  String _formatInventoryCount(double quantity) {
    if (quantity.isNaN || quantity.isInfinite) return '0';
    if (quantity % 1 == 0) return quantity.toInt().toString();
    return quantity.toStringAsFixed(2);
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildExpensesList() {
    if (_isLoadingExpenses) {
      return Container(
        height: 200,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: VentiqHomeTheme.primary),
              SizedBox(height: 16),
              Text('Cargando egresos...'),
            ],
          ),
        ),
      );
    }

    if (_expenses.isEmpty) {
      return Container(
        height: 120,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.money_off_outlined,
                size: 48,
                color: VentiqHomeTheme.textSecondary,
              ),
              SizedBox(height: 16),
              Text(
                'No hay egresos registrados en este turno',
                style: TextStyle(
                  color: VentiqHomeTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: _expenses.length > 3 ? 200 : null,
      child: ListView.builder(
        shrinkWrap: _expenses.length <= 3,
        itemCount: _expenses.length,
        itemBuilder: (context, index) {
          final expense = _expenses[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VentiqHomeTheme.danger.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: VentiqHomeTheme.danger.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        expense.motivoEntrega,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: VentiqHomeTheme.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      expense.formattedAmount,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: VentiqHomeTheme.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      expense.formattedTime,
                      style: const TextStyle(
                        fontSize: 12,
                        color: VentiqHomeTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.payment,
                      size: 12,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      expense.medioPago ?? 'N/A',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            expense.medioPago == 'Efectivo'
                                ? VentiqHomeTheme.success
                                : VentiqHomeTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.person,
                      size: 12,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Recibe: ${expense.nombreRecibe}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: VentiqHomeTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (expense.nombreAutoriza.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user,
                        size: 12,
                        color: VentiqHomeTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Autoriza: ${expense.nombreAutoriza}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: VentiqHomeTheme.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Comprueba si las cocinas de este TPV tienen comandas sin servir y, si las
  /// hay, pide confirmacion. Devuelve true si se puede seguir con el cierre.
  ///
  /// Si la consulta falla (sin red, cocina no configurada) NO se interrumpe el
  /// cierre: cuadrar la caja no puede depender de que responda esta RPC.
  Future<bool> _confirmarComandasPendientes() async {
    try {
      final idTpv = await _userPrefs.getIdTpv();
      if (idTpv == null) return true;

      final res = await Supabase.instance.client.rpc(
        'fn_comandas_abiertas_turno',
        params: {'p_id_tpv': idTpv},
      );

      final mapa =
          res is Map
              ? Map<String, dynamic>.from(res)
              : (res is List && res.isNotEmpty && res.first is Map
                  ? Map<String, dynamic>.from(res.first as Map)
                  : null);

      if (mapa == null || mapa['status'] != 'success') return true;

      final total = (mapa['total'] as num?)?.toInt() ?? 0;
      if (total == 0) return true;

      final sinCobrar = (mapa['con_cuenta_abierta'] as num?)?.toInt() ?? 0;
      final comandas = mapa['comandas'];
      final detalle = <String>[];
      if (comandas is List) {
        for (final c in comandas.take(6)) {
          if (c is! Map) continue;
          final mesa = c['mesa'] ?? 'Mostrador';
          final estado = c['estado_texto'] ?? '';
          final min = c['espera_minutos'] ?? 0;
          detalle.add('#${c['numero']} · $mesa · $estado · $min min');
        }
        if (comandas.length > 6) {
          detalle.add('... y ${comandas.length - 6} mas');
        }
      }

      if (!mounted) return true;

      final seguir = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.soup_kitchen_outlined,
                    color:
                        sinCobrar > 0
                            ? VentiqHomeTheme.danger
                            : VentiqHomeTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Hay comandas sin servir')),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mapa['message']?.toString() ??
                        '$total comanda(s) pendientes',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (sinCobrar > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Ojo: hay mesas sin cobrar. Al cerrar el turno esa venta '
                      'queda sin registrar.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: VentiqHomeTheme.danger,
                      ),
                    ),
                  ],
                  if (detalle.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (final d in detalle)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(d, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Revisar cocina'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        sinCobrar > 0 ? VentiqHomeTheme.danger : null,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cerrar igual'),
                ),
              ],
            ),
      );

      return seguir == true;
    } catch (e) {
      print('⚠️ No se pudo consultar comandas pendientes: $e');
      return true;
    }
  }

  void _crearCierre() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Fase 5: comandas de cocina sin servir. Cerrar un turno con platos en
    // cocina significa comida cocinada que nadie cobro, o comensales que
    // siguen esperando. Se AVISA y no se bloquea: si la cocina se fue sin
    // marcar los tickets, bloquear dejaria al vendedor sin cuadrar la caja.
    if (!await _confirmarComandasPendientes()) return;

    // Arqueo por divisa: un solo mapa escrito y otro leído de los campos.
    // Se congelan aquí (no tras los `await`) porque los controladores pueden
    // cambiar mientras corre la validación de comandas.
    final efectivoRealPorDivisa = _efectivoRealPorDivisa;
    final diferencias = _diferenciaPorDivisa;
    final montoFinal =
        efectivoRealPorDivisa[PriceUtils.baseCurrency] ?? 0.0;
    final diferencia = diferencias[PriceUtils.baseCurrency] ?? 0.0;

    final currentPendingOrders =
        (await _ordersOfOpenTurno())
            .where(
              (order) =>
                  order.status == OrderStatus.enviada ||
                  order.status == OrderStatus.procesando ||
                  order.status == OrderStatus.pagoConfirmado,
            )
            .toList();

    final carnavalOrderIdsToReactivate = <String>{};
    for (final order in currentPendingOrders) {
      final notas = order.notas;
      if (notas == null) continue;

      final match = RegExp(r'Venta desde orden (\d+)').firstMatch(notas);
      final carnavalOrderId = match?.group(1);
      if (carnavalOrderId != null) {
        carnavalOrderIdsToReactivate.add(carnavalOrderId);
      }
    }

    if (currentPendingOrders.isNotEmpty &&
        carnavalOrderIdsToReactivate.isNotEmpty) {
      NotificationService()
          .reactivateVentaNotificationsForOrdenIds(carnavalOrderIdsToReactivate)
          .catchError((e) {
            print('❌ Error reactivando notificaciones Carnaval: $e');
            return 0;
          });
    }

    if (currentPendingOrders.isNotEmpty) {
      setState(() {
        _ordenesAbiertas = currentPendingOrders.length;
        _ordenesPendientes = currentPendingOrders;
      });

      if (_trabajadorManejaAperturaControl) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tienes ${currentPendingOrders.length} órdenes pendientes. Debes cerrarlas antes de cerrar el turno.',
            ),
            backgroundColor: VentiqHomeTheme.warning,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    // Confirmación si CUALQUIER divisa descuadra: mezclar divisas al comparar
    // es precisamente lo que impedía ver el faltante de una sola moneda.
    if (diferencias.values.any((d) => d.abs() > 0.01)) {
      final confirmar = await _showDiferenciaDialog(diferencias);
      if (!confirmar) return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Validar que si maneja inventario y es el último turno, se haya establecido
      // Si NO es el último turno, el inventario es opcional
      // NUEVO: También es opcional si el trabajador tiene maneja_apertura_control = false
      if (_manejaInventario &&
          _isLastOpenShift &&
          !_inventorySet &&
          _trabajadorManejaAperturaControl) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Debes controlar el inventario antes de cerrar el último turno',
            ),
            backgroundColor: VentiqHomeTheme.warning,
          ),
        );
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      // Validar que todos los productos tengan cantidad ingresada
      if (_manejaInventario && _inventorySet) {
        int productosVacios = 0;
        for (var product in _inventoryProducts) {
          final controller = _inventoryControllers[product.id];
          final cantidadText = controller?.text ?? '';
          if (cantidadText.isEmpty) {
            productosVacios++;
          }
        }

        if (productosVacios > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Debes ingresar la cantidad para todos los productos ($productosVacios pendientes)',
              ),
              backgroundColor: VentiqHomeTheme.warning,
              duration: const Duration(seconds: 4),
            ),
          );
          setState(() {
            _isProcessing = false;
          });
          return;
        }
      }

      // Preparar datos de inventario y generar observaciones si está habilitado
      List<Map<String, dynamic>>? productCounts;
      String observacionesInventario = '';

      if (_manejaInventario && _inventorySet) {
        productCounts = [];
        final List<String> excesos = [];
        final List<String> defectos = [];

        for (var product in _inventoryProducts) {
          final controller = _inventoryControllers[product.id];
          final cantidadText = controller?.text ?? '';

          if (cantidadText.isNotEmpty) {
            final cantidadContada = double.tryParse(cantidadText);
            if (cantidadContada != null && cantidadContada >= 0) {
              // Agregar producto con TODOS los campos requeridos
              productCounts.add({
                'id_producto': product.id,
                'id_variante': product.idVariante,
                'id_ubicacion': product.idUbicacion,
                'id_presentacion': product.idPresentacion,
                'cantidad': cantidadContada,
              });

              // Calcular diferencia vs "debe haber" (stock real del RPC batch)
              final cantidadSistema =
                  _stockRealByProduct[product.id]?.debeHaber ??
                  product.cantidadFinalReal;
              final diferencia = cantidadContada - cantidadSistema;

              if (diferencia > 0) {
                // Hay exceso
                excesos.add(
                  'Sobran ${diferencia.toStringAsFixed(2)} unidades de ${product.nombreProducto}',
                );
              } else if (diferencia < 0) {
                // Hay defecto
                defectos.add(
                  'Faltan ${diferencia.abs().toStringAsFixed(2)} unidades de ${product.nombreProducto}',
                );
              }
            }
          }
        }

        // Construir observaciones de inventario
        if (excesos.isNotEmpty || defectos.isNotEmpty) {
          final List<String> observaciones = [];

          if (defectos.isNotEmpty) {
            observaciones.add('FALTANTES:');
            observaciones.addAll(defectos);
          }

          if (excesos.isNotEmpty) {
            if (observaciones.isNotEmpty) observaciones.add('');
            observaciones.add('EXCESOS:');
            observaciones.addAll(excesos);
          }

          observacionesInventario = observaciones.join('\n');
          print('📋 Observaciones de inventario generadas:');
          print(observacionesInventario);
        }

        print('📦 Productos contados: ${productCounts.length}');
      }

      // Combinar observaciones del usuario con observaciones de inventario
      String observacionesFinales = _observacionesController.text.trim();
      if (observacionesInventario.isNotEmpty) {
        if (observacionesFinales.isNotEmpty) {
          observacionesFinales +=
              '\n\n--- INVENTARIO ---\n$observacionesInventario';
        } else {
          observacionesFinales = observacionesInventario;
        }
      }

      print('📦 Productos para cierre:');
      if (productCounts != null && productCounts.isNotEmpty) {
        for (var prod in productCounts) {
          print(
            '  - ID: ${prod['id_producto']}, Ubicación: ${prod['id_ubicacion']}, Variante: ${prod['id_variante']}, Presentación: ${prod['id_presentacion']}, Cantidad: ${prod['cantidad']}',
          );
        }
      }
      print('📊 Total productos: ${productCounts?.length ?? 0}');
      print('📝 Observaciones finales: $observacionesFinales');

      // Cerrar trabajadores activos antes de cerrar el turno
      await _closeActiveWorkers();

      // Modo offline (config o auto por pérdida de red) o sin conexión:
      // guardar SOLO local. No intentar cierre online primero (evita el
      // fallback "intentó online → falló → cartel offline").
      //
      // OJO: un turno abierto online se cachea en la cola por resiliencia
      // (`origen_apertura == 'online'`). Con modo online + red real, ese
      // cache no debe forzar el camino offline (quedaría pending sin
      // necesidad). Sí debe ir por cola si la apertura fue genuinamente
      // offline.
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();
      final hasNetwork =
          await ConnectivityService().performImmediateCheck();
      final forceLocalOnly = isOfflineModeEnabled || !hasNetwork;
      final offlineOpen = await _userPrefs.getOfflineTurno();
      final aperturaOffline = offlineOpen?['apertura'];
      final isCachedOnlineTurno =
          aperturaOffline is Map &&
          aperturaOffline['origen_apertura'] == 'online';
      final useOfflineTurnoPath =
          forceLocalOnly ||
          (offlineOpen != null && !isCachedOnlineTurno);

      if (useOfflineTurnoPath) {
        print(
          '🔌 Cierre vía turno offline'
          '${offlineOpen != null ? ' (${offlineOpen['local_id']})' : ''}'
          ' forceLocalOnly=$forceLocalOnly '
          'offlineMode=$isOfflineModeEnabled hasNetwork=$hasNetwork...',
        );
        await _createOfflineCierre(
          efectivoRealPorDivisa: efectivoRealPorDivisa,
          productos: productCounts ?? [],
          observaciones: observacionesFinales,
          allowImmediateServerSync: !forceLocalOnly,
        );
      } else {
        print('🌐 Modo online - Creando cierre en Supabase...');
        final turnoBeforeClose = await TurnoService.getTurnoAbierto();
        final serverTurnoIdRaw =
            turnoBeforeClose?['id'] ?? turnoBeforeClose?['server_id_turno'];
        final serverTurnoId =
            serverTurnoIdRaw is int
                ? serverTurnoIdRaw
                : (serverTurnoIdRaw is num
                    ? serverTurnoIdRaw.toInt()
                    : int.tryParse('$serverTurnoIdRaw'));

        final result = await TurnoService.cerrarTurnoDetailed(
          efectivoRealPorDivisa: efectivoRealPorDivisa,
          productos: productCounts ?? [],
          observaciones:
              observacionesFinales.isEmpty ? null : observacionesFinales,
        );
        if (result.success) {
          await _snapshotTurnoResumenToCache(
            efectivoRealPorDivisa: efectivoRealPorDivisa,
            serverTurnoId: serverTurnoId,
          );
          await _userPrefs.finalizeTurnoAfterOnlineClose(
            serverTurnoId: serverTurnoId,
          );
          if (serverTurnoId != null) {
            await _userPrefs.saveClosedTurnoMarker(
              serverTurnoId,
              fechaCierre: DateTime.now().toIso8601String(),
            );
          }
          print('🧹 Turno online cerrado — resúmenes conservados en cache');

          await _clearInventoryCounts();
          PrinterManager().clearSavedPrinter();
          _showSuccessDialog(montoFinal, diferencia);
        } else if (result.isNetworkError) {
          print(
            '📵 Error de red en cierre online. Guardando solo offline '
            '(sin reintentar sync inmediato)',
          );
          await _createOfflineCierre(
            efectivoRealPorDivisa: efectivoRealPorDivisa,
            productos: productCounts ?? [],
            observaciones: observacionesFinales,
            allowImmediateServerSync: false,
          );
        } else {
          // Error de negocio: NO crear cierre offline. Mostrar mensaje real.
          print('⚠️ Cierre rechazado por el servidor: ${result.message}');
          _showErrorMessage(result.message ?? 'No se pudo cerrar el turno');
        }
      }
    } catch (e) {
      _showErrorMessage('Error al crear el cierre: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Cerrar automáticamente todos los trabajadores activos del turno
  Future<void> _closeActiveWorkers() async {
    try {
      print('👥 Verificando trabajadores activos para cerrar...');

      // Obtener turno abierto
      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) {
        print('⚠️ No hay turno abierto, omitiendo cierre de trabajadores');
        return;
      }

      final idRaw = turnoAbierto['id'] ?? turnoAbierto['server_id_turno'];
      final idTurno =
          idRaw is int
              ? idRaw
              : (idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw'));
      if (idTurno == null) {
        print(
          '⚠️ Turno offline sin id de servidor; omitiendo cierre de trabajadores',
        );
        return;
      }

      // Obtener trabajadores del turno
      final workers = await ShiftWorkersService.getShiftWorkers(idTurno);

      // Filtrar solo los trabajadores activos (sin hora de salida)
      final activeWorkers = workers.where((w) => w.isActive).toList();

      if (activeWorkers.isEmpty) {
        print('✅ No hay trabajadores activos para cerrar');
        return;
      }

      print('👥 Cerrando ${activeWorkers.length} trabajador(es) activo(s)...');

      // Hora de cierre del turno (ahora)
      final horaCierre = DateTime.now();

      // Registrar salida de todos los trabajadores activos
      final idsRegistros = activeWorkers.map((w) => w.id!).toList();
      final result = await ShiftWorkersService.registerWorkersExit(
        idsRegistros: idsRegistros,
        horaSalida: horaCierre,
      );

      if (result['success'] == true) {
        _trabajadoresCerrados = activeWorkers.length;
        print(
          '✅ $_trabajadoresCerrados trabajador(es) cerrado(s) automáticamente',
        );
        print('⏰ Hora de cierre: ${horaCierre.toIso8601String()}');
      } else {
        print('⚠️ Error cerrando trabajadores: ${result['message']}');
      }
    } catch (e) {
      print('❌ Error al cerrar trabajadores activos: $e');
      // No lanzar error para no interrumpir el cierre del turno
    }
  }

  /// Confirmación de cierre cuando alguna divisa descuadra.
  ///
  /// [diferencias] llega ya calculada por divisa: el diálogo solo lista las que
  /// superan el umbral, con su importe nativo.
  Future<bool> _showDiferenciaDialog(Map<String, double> diferencias) async {
    final parts = <String>[];
    for (final divisa in _divisasCaja) {
      final diferencia = diferencias[divisa] ?? 0;
      if (diferencia.abs() <= 0.01) continue;
      parts.add('$divisa: \$${diferencia.toMoneyString(2)}');
    }
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Diferencia en Caja'),
            content: Text(
              'Hay diferencia entre lo esperado y lo contado:\n\n'
              '${parts.join('\n')}\n\n'
              '¿Desea continuar con el cierre?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  void _showSuccessDialog(double montoFinal, double diferencia) {
    final stateContext = context;
    showDialog(
      context: stateContext,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: VentiqHomeTheme.success,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text('Cierre Creado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El cierre de caja ha sido registrado exitosamente.',
                ),
                const SizedBox(height: 12),
                Text('Monto final: \$${montoFinal.toMoneyString(2)}'),
                Text('Ventas del día: \$${_ventasTotales.toMoneyString(2)}'),
                if (diferencia.abs() > 0.01)
                  Text('Diferencia: \$${diferencia.toMoneyString(2)}'),
                Text('Órdenes pendientes: ${_ordenesPendientes.length}'),
                if (_trabajadoresCerrados > 0)
                  Text('Trabajadores cerrados: $_trabajadoresCerrados'),
                Text('Fecha: ${_formatDate(DateTime.now())}'),
                Text('Hora: ${_formatTime(DateTime.now())}'),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await NavigationHelper.goHome(stateContext);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: VentiqHomeTheme.danger),
    );
  }

  /// Persiste el cuadre del turno en cache antes de finalizar el cierre online.
  ///
  /// Guarda el detalle NATIVO por divisa (`efectivo_real_por_moneda`) y, además,
  /// las columnas escalares vigentes —`efectivo_real_usd` incluida— porque el
  /// admin y el sync offline todavía las leen.
  Future<void> _snapshotTurnoResumenToCache({
    required Map<String, double> efectivoRealPorDivisa,
    int? serverTurnoId,
  }) async {
    final base = PriceUtils.baseCurrency;
    final efectivoFinal = efectivoRealPorDivisa[base] ?? 0;
    final esperadoPorDivisa = _efectivoEsperadoPorDivisa;
    final diferenciaPorDivisa = _diferenciaPorDivisa;
    final snapshot = <String, dynamic>{
      'efectivo_inicial': _montoInicialCaja,
      'efectivo_inicial_por_moneda': _efectivoInicialPorDivisa,
      'ventas_totales': _ventasTotales,
      'total_efectivo': _totalEfectivo,
      'total_transferencias': _totalTransferencias,
      'transferencia_por_moneda': _transferenciaPorDivisa,
      'productos_vendidos': _productosVendidos,
      'operaciones_totales': _operacionesTotales,
      'ticket_promedio': _ticketPromedio,
      'egresos_efectivo': _egresosEfectivo,
      'egresos_digitales': _egresosTransferencias,
      'egresos_totales': _totalEgresos,
      'efectivo_esperado': esperadoPorDivisa[base] ?? 0,
      'efectivo_esperado_por_moneda': esperadoPorDivisa,
      'efectivo_final': efectivoFinal,
      'efectivo_real': efectivoFinal,
      'efectivo_real_usd': efectivoRealPorDivisa['USD'] ?? 0,
      'efectivo_real_por_moneda': efectivoRealPorDivisa,
      'estado_turno': 2,
      'diferencia': diferenciaPorDivisa[base] ?? 0,
      'diferencia_por_moneda': diferenciaPorDivisa,
      'fecha_apertura': _fechaAperturaTurno?.toIso8601String(),
      'fecha_cierre': DateTime.now().toIso8601String(),
      'cerrado_online': true,
      'status': UserPreferencesService.offlineTurnoStatusSynced,
      if (serverTurnoId != null) 'id': serverTurnoId,
      if (serverTurnoId != null) 'server_id_turno': serverTurnoId,
    };
    await _userPrefs.saveTurnoResumenCache(snapshot);
    await _userPrefs.saveResumenCierreCache({
      ...snapshot,
      'total_ventas': _ventasTotales,
      'efectivo_real': efectivoFinal,
    });
  }

  /// Crear cierre offline.
  ///
  /// [efectivoRealPorDivisa] son importes NATIVOS por divisa; el payload
  /// conserva las columnas escalares (`efectivo_final` en moneda base y
  /// `efectivo_real_usd`) porque `AutoSyncService` todavía las lee, y añade el
  /// mapa completo para el arqueo por moneda.
  ///
  /// [allowImmediateServerSync]: si false (modo offline, sin red, o fallback
  /// tras error de red), solo guarda en cola local — no intenta subir ahora.
  Future<void> _createOfflineCierre({
    required Map<String, double> efectivoRealPorDivisa,
    required List<Map<String, dynamic>> productos,
    required String observaciones,
    bool allowImmediateServerSync = true,
  }) async {
    try {
      final base = PriceUtils.baseCurrency;
      final efectivoFinal = efectivoRealPorDivisa[base] ?? 0;
      final esperadoPorDivisa = _efectivoEsperadoPorDivisa;
      final diferencia = efectivoFinal - (esperadoPorDivisa[base] ?? 0);
      final diferenciaPorDivisa = {
        for (final e in efectivoRealPorDivisa.entries)
          e.key: e.value - (esperadoPorDivisa[e.key] ?? 0),
      };
      final userData = await _userPrefs.getUserData();
      final openTurno = await _userPrefs.getOfflineTurno();
      if (openTurno == null) {
        throw StateError(
          'No hay turno abierto en la cola offline para guardar el cierre. '
          'Reabre el turno o sincroniza antes de cerrar.',
        );
      }
      // Usar el mismo id_tpv con el que se abrió ESTE turno, no el TPV
      // seleccionado actualmente en preferencias (puede haber cambiado entre
      // la apertura y el cierre). Si no está disponible, caer al de prefs.
      final aperturaTpvRaw =
          openTurno['id_tpv'] ??
          (openTurno['apertura'] is Map
              ? (openTurno['apertura'] as Map)['id_tpv']
              : null);
      final idTpv =
          (aperturaTpvRaw is int
              ? aperturaTpvRaw
              : (aperturaTpvRaw is num
                  ? aperturaTpvRaw.toInt()
                  : int.tryParse('$aperturaTpvRaw'))) ??
          await _userPrefs.getIdTpv();
      final userUuid = userData['userId'];

      if (idTpv == null || userUuid == null) {
        throw Exception('Faltan datos requeridos para el cierre offline');
      }

      // Generar ID único para el cierre offline + client_uuid de idempotencia.
      final cierreId = '${DateTime.now().millisecondsSinceEpoch}';
      final clientUuid = UuidGenerator.v4();
      final localTurnoId =
          openTurno['local_id']?.toString() ??
          openTurno['local_turno_id']?.toString();
      if (localTurnoId == null || localTurnoId.isEmpty) {
        throw StateError(
          'El turno offline no tiene local_id; no se puede guardar el cierre.',
        );
      }

      // Hora corregida contra el servidor (ver ServerTimeService), para que
      // fecha_cierre no quede desfasada si el reloj del dispositivo está mal.
      final nowServerCorrected = ServerTimeService().now();

      // Crear estructura de cierre offline
      final cierreData = {
        'id': cierreId,
        'client_uuid': clientUuid,
        'id_tpv': idTpv,
        'usuario': userUuid,
        'tipo_operacion': 'cierre',
        'efectivo_final': efectivoFinal,
        'efectivo_real_usd': efectivoRealPorDivisa['USD'] ?? 0,
        'efectivo_real_por_moneda': efectivoRealPorDivisa,
        'diferencia': diferencia,
        'diferencia_por_moneda': diferenciaPorDivisa,
        'fecha_cierre': nowServerCorrected.toIso8601String(),
        'observaciones': observaciones.isEmpty ? null : observaciones,
        'maneja_inventario': _manejaInventario,
        'productos': productos,
        'created_offline_at': nowServerCorrected.toIso8601String(),
        if (localTurnoId != null) 'local_turno_id': localTurnoId,
      };

      // Snapshot del cuadre para que el admin lo vea offline (multi-turno).
      final resumenSnapshot = {
        'efectivo_inicial': _montoInicialCaja,
        'efectivo_inicial_por_moneda': _efectivoInicialPorDivisa,
        'ventas_totales': _ventasTotales,
        'total_efectivo': _totalEfectivo,
        'total_transferencias': _totalTransferencias,
        'transferencia_por_moneda': _transferenciaPorDivisa,
        'productos_vendidos': _productosVendidos,
        'operaciones_totales': _operacionesTotales,
        'ticket_promedio': _ticketPromedio,
        'egresos_efectivo': _egresosEfectivo,
        'egresos_digitales': _egresosTransferencias,
        'egresos_totales': _totalEgresos,
        'efectivo_esperado': esperadoPorDivisa[base] ?? 0,
        'efectivo_esperado_por_moneda': esperadoPorDivisa,
        'efectivo_final': efectivoFinal,
        'efectivo_real': efectivoFinal,
        'efectivo_real_usd': efectivoRealPorDivisa['USD'] ?? 0,
        'efectivo_real_por_moneda': efectivoRealPorDivisa,
        'estado_turno': 2,
        'diferencia': diferencia,
        'diferencia_por_moneda': diferenciaPorDivisa,
        'fecha_apertura': openTurno['fecha_apertura'],
        'fecha_cierre': cierreData['fecha_cierre'],
        'observaciones': observaciones.isEmpty ? null : observaciones,
        'reconstruido': false,
      };

      // Cola multi-turno: marca closed_pending_sync (no borra el historial).
      print(
        '[TURNO_SYNC] _createOfflineCierre → markOfflineTurnoClosed '
        'localTurnoId=$localTurnoId '
        'openTurno.id=${openTurno['id']} '
        'openTurno.server_id=${openTurno['server_id_turno']} '
        'openTurno.status=${openTurno['status']} '
        'efectivoFinal=$efectivoFinal diferencia=$diferencia '
        'productos=${productos.length}',
      );
      await _userPrefs.markOfflineTurnoClosed(
        localId: localTurnoId,
        cierrePayload: cierreData,
        resumen: resumenSnapshot,
      );
      await _userPrefs.dumpOfflineTurnosQueue(
        'post markClosed en _createOfflineCierre',
      );

      // 3ra fuente de verdad al vender: marcador local persistente de que
      // este turno (server_id) ya fue cerrado, aunque la entrada de cola
      // se pierda o no matchee en getTurnoAbierto.
      final serverTurnoIdRaw =
          openTurno['server_id_turno'] ??
          (openTurno['apertura'] is Map
              ? ((openTurno['apertura'] as Map)['server_id_turno'] ??
                  (openTurno['apertura'] as Map)['id'])
              : null);
      final serverTurnoId =
          serverTurnoIdRaw is int
              ? serverTurnoIdRaw
              : (serverTurnoIdRaw is num
                  ? serverTurnoIdRaw.toInt()
                  : int.tryParse('$serverTurnoIdRaw'));
      if (serverTurnoId != null) {
        await _userPrefs.saveClosedTurnoMarker(
          serverTurnoId,
          fechaCierre: cierreData['fecha_cierre'] as String,
        );
      }

      await _clearInventoryCounts();
      PrinterManager().clearSavedPrinter();

      // Solo intentar subir si el caller lo permite Y no hay modo offline.
      // Subir con modo offline ON (o tras fallo de red) duplicaba aperturas /
      // mostraba el cartel de "intentó online y falló".
      var syncedToServer = false;
      String? syncMessage;
      final isOfflineMode = await _userPrefs.isOfflineModeEnabled();
      final hasNetwork = await ConnectivityService().performImmediateCheck();
      final tryServerSync =
          allowImmediateServerSync && !isOfflineMode && hasNetwork;

      // Marcador remoto inmediato: aunque el cuadre completo quede en cola,
      // otros dispositivos/clientes ya no ven el turno como vendible.
      if (serverTurnoId != null && hasNetwork) {
        await TurnoService.marcarCierreSolicitadoEnServidor(
          serverTurnoId: serverTurnoId,
          fechaCierre: nowServerCorrected,
        );
      }

      if (tryServerSync) {
        print(
          '[TURNO_SYNC] _createOfflineCierre tiene red y modo online → '
          'syncOfflineTurnoAfterLocalCierre(localId=$localTurnoId)',
        );
        final syncResult = await AutoSyncService()
            .syncOfflineTurnoAfterLocalCierre(localId: localTurnoId);
        syncedToServer = syncResult['success'] == true;
        syncMessage = syncResult['message']?.toString();
        print(
          '[TURNO_SYNC] sync post-cierre result: '
          'success=$syncedToServer msg=$syncMessage',
        );
        await _userPrefs.dumpOfflineTurnosQueue(
          'post syncOfflineTurnoAfterLocalCierre',
        );
      } else {
        print(
          '[TURNO_SYNC] _createOfflineCierre SIN sync inmediato → '
          'allowImmediateServerSync=$allowImmediateServerSync '
          'hasNetwork=$hasNetwork isOfflineMode=$isOfflineMode',
        );
        syncMessage =
            isOfflineMode
                ? 'Modo offline: el cierre se sincronizará al desactivar el modo offline'
                : 'Sin conexión a internet';
      }

      if (syncedToServer) {
        await _userPrefs.purgeFinalizedSyncedOrdersForTurno(localTurnoId);
      }

      if (mounted) {
        if (syncedToServer) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cierre registrado en el servidor.'),
              backgroundColor: VentiqHomeTheme.success,
              duration: Duration(seconds: 3),
            ),
          );
          _showSuccessDialog(efectivoFinal, diferencia);
        } else if (allowImmediateServerSync && !isOfflineMode) {
          // Intentó sync inmediato en modo online y falló.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                syncMessage ??
                    'No se pudo registrar en el servidor. Quedó pendiente de sync.',
              ),
              backgroundColor: VentiqHomeTheme.warning,
              duration: const Duration(seconds: 5),
            ),
          );
          _showOfflineSuccessDialog(
            efectivoFinal,
            diferencia,
            syncFailedOnline: true,
            syncMessage: syncMessage,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOfflineMode
                    ? 'Cierre guardado localmente. Se sincronizará al desactivar el modo offline.'
                    : 'Cierre guardado localmente. Se sincronizará cuando haya conexión.',
              ),
              backgroundColor: VentiqHomeTheme.warning,
              duration: const Duration(seconds: 3),
            ),
          );
          _showOfflineSuccessDialog(efectivoFinal, diferencia);
        }
      }

      print(
        syncedToServer
            ? '✅ Cierre offline sincronizado al servidor: $cierreId'
            : '✅ Cierre offline pendiente de sync: $cierreId',
      );
    } catch (e, stackTrace) {
      print('❌ Error creando cierre offline: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        _showErrorMessage('Error creando cierre offline: $e');
      }
    }
  }

  void _showOfflineSuccessDialog(
    double montoFinal,
    double diferencia, {
    bool syncFailedOnline = false,
    String? syncMessage,
  }) {
    final stateContext = context;
    showDialog(
      context: stateContext,
      barrierDismissible: false,
      builder:
          (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  syncFailedOnline ? Icons.sync_problem : Icons.cloud_off,
                  color: VentiqHomeTheme.warning,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    syncFailedOnline
                        ? 'Cierre pendiente de sync'
                        : 'Cierre Offline Creado',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  syncFailedOnline
                      ? (syncMessage ??
                          'Estabas en modo online, pero no se pudo registrar el cierre en el servidor. Quedó guardado localmente para reintentar.')
                      : 'El cierre se ha guardado localmente y se sincronizará automáticamente cuando tengas conexión a internet.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: VentiqHomeTheme.border),
                  ),
                  child: Column(
                    children: [
                      _buildDialogInfoRow(
                        'Monto Final:',
                        '\$${montoFinal.toMoneyString(2)}',
                      ),
                      if (diferencia.abs() > 0.01)
                        _buildDialogInfoRow(
                          'Diferencia:',
                          '${diferencia >= 0 ? '+' : ''}\$${diferencia.toMoneyString(2)}',
                          isHighlight: true,
                          color:
                              diferencia >= 0
                                  ? VentiqHomeTheme.success
                                  : VentiqHomeTheme.danger,
                        ),
                      _buildDialogInfoRow(
                        'Estado:',
                        'Pendiente de sincronización',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pushReplacementNamed(
                    stateContext,
                    '/cierre-pendiente',
                  );
                },
                child: const Text('Ver detalle'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await NavigationHelper.goHome(stateContext);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
  }

  Widget _buildDialogInfoRow(
    String label,
    String value, {
    bool isHighlight = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: VentiqHomeTheme.textSecondary,
                fontWeight: isHighlight ? FontWeight.w700 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color ?? VentiqHomeTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatInventoryQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

/// Totales de stock real por producto para el control de inventario (cierre).
class _StockRealProducto {
  final double stockSistema;
  final double pendienteCarnaval;
  final double enCamino;
  final double debeHaber;

  const _StockRealProducto({
    required this.stockSistema,
    required this.pendienteCarnaval,
    required this.enCamino,
    required this.debeHaber,
  });
}
