import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/expense.dart';
import '../models/payment_method.dart';
import '../services/order_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/printer_manager.dart';
import '../services/web_summary_printer_service.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';
import '../services/currency_service.dart';
import '../services/moneda_venta_service.dart';
import '../theme/ventiq_home_theme.dart';
import '../utils/platform_utils.dart';
import '../utils/price_utils.dart';
import '../widgets/egresos_list_screen.dart';
import '../widgets/filtered_orders_screen.dart';
import '../screens/orders_screen.dart';

class VentaTotalScreen extends StatefulWidget {
  const VentaTotalScreen({Key? key}) : super(key: key);

  @override
  State<VentaTotalScreen> createState() => _VentaTotalScreenState();
}

class _VentaTotalScreenState extends State<VentaTotalScreen> {
  final OrderService _orderService = OrderService();
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  final PrinterManager _printerManager = PrinterManager();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  List<OrderItem> _productosVendidos = [];
  List<Order> _ordenesVendidas = [];
  double _totalVentas = 0.0; // consolidado en moneda base (order.total)
  double _totalProductos = 0.0;
  double _totalEgresado = 0.0; // Cambio: era _totalCosto

  // Importes NATIVOS acumulados por código de divisa ISO-4217. Son el único
  // origen de verdad del resumen: cualquier divisa que el servidor acepte
  // entra por estos mapas sin tocar el resto de la pantalla, y con una sola
  // divisa los importes son exactamente los que calculaba la versión binaria.
  Map<String, double> _ventasPorDivisa = {};
  Map<String, double> _efectivoPorDivisa = {};
  Map<String, double> _digitalPorDivisa = {};
  Map<String, double> _egresosEfectivoPorDivisa = {};
  Map<String, double> _egresosDigitalPorDivisa = {};
  Map<String, double> _totalesPorMedioPago = {};
  bool _isLoading = true;
  bool _hasActiveTurno = false;

  // Expenses data
  List<Expense> _expenses = [];
  double _totalEgresos = 0.0;

  // Tasa a la moneda base de cada divisa de la tienda (0 = sin tasa
  // resoluble). Se carga una vez porque `build()` la necesita de forma
  // síncrona para decidir qué divisas dibujar y con qué decimales.
  Map<String, double> _ratesByCurrency = {};
  bool _isLoadingRates = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _loadRates();
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  /// Suma [monto] bajo [clave] dentro de un acumulador.
  ///
  /// Existe para no repetir el `update(... ifAbsent:)` en cada cubo y, sobre
  /// todo, para que admitir una divisa nueva sea sólo un dato: no hay ninguna
  /// rama por código de divisa que recordar.
  static void _acumular(
    Map<String, double> acumulador, {
    required String clave,
    required double monto,
  }) {
    acumulador.update(clave, (valor) => valor + monto, ifAbsent: () => monto);
  }

  /// Tasa de [divisa] a la moneda base, o `null` si no hay ninguna resoluble.
  ///
  /// La moneda base vale 1 por definición. Se devuelve `null` (y no 0) para
  /// que `paymentCupEquivalent` prefiera la tasa guardada en el propio pago en
  /// lugar de inventar una conversión.
  double? _rateToBase(String divisa) {
    if (divisa == PriceUtils.baseCurrency) return 1;
    final tasa = _ratesByCurrency[divisa];
    return (tasa != null && tasa > 0) ? tasa : null;
  }

  /// Desglose de pagos de las órdenes: importes NATIVOS por código de divisa.
  ///
  /// La divisa de cada línea sale del propio pago (`PriceUtils.paymentCurrency`
  /// devuelve el código ISO real): un cobro en EUR cae en `ventasPorDivisa` de
  /// EUR, no en el cubo de la moneda base como hacía el desglose binario.
  Future<
    ({
      Map<String, double> ventasPorDivisa,
      Map<String, double> efectivoPorDivisa,
      Map<String, double> digitalPorDivisa,
      double total,
      int productos,
      Map<String, double> porMedio,
    })
  >
  _calculatePaymentBreakdownFromOrders(List<Order> orders) async {
    final ventasPorDivisa = <String, double>{};
    final efectivoPorDivisa = <String, double>{};
    final digitalPorDivisa = <String, double>{};
    double total = 0.0;
    int productos = 0;
    final porMedio = <String, double>{};

    for (final order in orders) {
      final isCompletedOrOffline =
          order.status == OrderStatus.completada ||
          order.status == OrderStatus.pagoConfirmado ||
          order.status == OrderStatus.pendienteDeSincronizacion ||
          order.status == OrderStatus.enviada;

      if (!isCompletedOrOffline) continue;

      total += order.total;
      productos += order.items.fold<int>(
        0,
        (sum, item) => sum + item.cantidad.toInt(),
      );

      double clasificadoCup = 0.0;
      final pagos = order.pagos;

      if (pagos != null && pagos.isNotEmpty) {
        for (final raw in pagos) {
          final pago = PriceUtils.asPaymentMap(raw);
          if (pago == null) continue;

          final divisa = PriceUtils.paymentCurrency(pago);
          final montoNativo = PriceUtils.paymentAmount(pago);
          final montoCup = PriceUtils.paymentCupEquivalent(
            pago,
            fallbackRate: _rateToBase(divisa),
          );
          final nombre = PriceUtils.paymentMethodName(pago);
          final etiqueta = PriceUtils.paymentIsPending(pago)
              ? 'Cuenta por cobrar ($divisa)'
              : '$nombre ($divisa)';

          _acumular(porMedio, clave: etiqueta, monto: montoNativo);
          _acumular(ventasPorDivisa, clave: divisa, monto: montoNativo);

          if (PriceUtils.paymentIsPending(pago)) {
            clasificadoCup += montoCup;
            continue;
          }

          _acumular(
            PriceUtils.paymentIsCash(pago)
                ? efectivoPorDivisa
                : digitalPorDivisa,
            clave: divisa,
            monto: montoNativo,
          );
          clasificadoCup += montoCup;
        }
      }

      final montoSinClasificar = order.total - clasificadoCup;
      if (montoSinClasificar > 0.01) {
        final esCuentaPorCobrar = await _orderService.isVentaPendienteDePago(
          order,
        );
        // Sin líneas de pago no hay divisa que leer: se asume la moneda base,
        // que es la unidad contable con la que se registró el pedido.
        final divisa = PriceUtils.baseCurrency;
        final etiqueta =
            esCuentaPorCobrar
                ? 'Cuenta por cobrar ($divisa)'
                : 'Efectivo ($divisa)';
        _acumular(porMedio, clave: etiqueta, monto: montoSinClasificar);
        _acumular(ventasPorDivisa, clave: divisa, monto: montoSinClasificar);
        if (!esCuentaPorCobrar) {
          _acumular(efectivoPorDivisa, clave: divisa, monto: montoSinClasificar);
        }
      }
    }

    return (
      ventasPorDivisa: ventasPorDivisa,
      efectivoPorDivisa: efectivoPorDivisa,
      digitalPorDivisa: digitalPorDivisa,
      total: total,
      productos: productos,
      porMedio: porMedio,
    );
  }

  void _applyPaymentBreakdown(
    ({
      Map<String, double> ventasPorDivisa,
      Map<String, double> efectivoPorDivisa,
      Map<String, double> digitalPorDivisa,
      double total,
      int productos,
      Map<String, double> porMedio,
    })
    breakdown,
  ) {
    _totalVentas = breakdown.total;
    _totalProductos = breakdown.productos.toDouble();
    _ventasPorDivisa = breakdown.ventasPorDivisa;
    _efectivoPorDivisa = breakdown.efectivoPorDivisa;
    _digitalPorDivisa = breakdown.digitalPorDivisa;
    _totalesPorMedioPago = breakdown.porMedio;
  }

  /// Efectivo real de la moneda base para el impresor web, que todavía recibe
  /// un único importe. Es un valor derivado (no un acumulador paralelo) para
  /// que no pueda quedar desincronizado de los desgloses.
  double get _totalEfectivoReal =>
      _baseAmount(_efectivoPorDivisa) - _baseAmount(_egresosEfectivoPorDivisa);

  /// Importe de un desglose en la moneda base, sin convertir.
  ///
  /// Los detalles que se abren desde aquí (`FilteredOrdersScreen`,
  /// `EgresosListScreen`) reciben un único importe: se les pasa la porción en
  /// moneda base, que es justo lo que mostraban antes de multimoneda.
  double _baseAmount(Map<String, double> montos) =>
      montos[PriceUtils.baseCurrency] ?? 0.0;

  /// Suma dos desgloses por divisa conservando las claves con importe 0.
  ///
  /// Se combinan los mapas al pintar en vez de mantener acumuladores
  /// paralelos: un acumulador que nadie asigna es precisamente el defecto que
  /// dejaba «Egresado USD» en 0.0 permanente.
  Map<String, double> _sumarPorDivisa(
    Map<String, double> a,
    Map<String, double> b,
  ) {
    final total = <String, double>{...a};
    for (final entrada in b.entries) {
      _acumular(total, clave: entrada.key, monto: entrada.value);
    }
    return total;
  }

  /// Resta [b] a [a] por divisa. Las claves de [a] se conservan aunque queden
  /// en cero: la línea debe seguir apareciendo, como hacía el resumen binario.
  Map<String, double> _restarPorDivisa(
    Map<String, double> a,
    Map<String, double> b,
  ) {
    final total = <String, double>{...a};
    for (final entrada in b.entries) {
      _acumular(total, clave: entrada.key, monto: -entrada.value);
    }
    return total;
  }

  /// Divisas que debe pintar el resumen, en orden estable: la moneda base
  /// primero y después las de la tienda, más las que aparezcan en [montos].
  ///
  /// Se siembra con las divisas de la tienda aunque no tengan movimiento para
  /// que el resumen muestre las mismas líneas que el arqueo (una tienda
  /// CUP/USD sigue pintando las dos de siempre) y se añaden las que sólo
  /// existen en los datos para no ocultar una venta en una divisa que la
  /// tienda ya no acepta.
  List<String> _displayCurrencies(Map<String, double> montos) {
    final divisas = <String>[PriceUtils.baseCurrency];
    for (final codigo in [..._ratesByCurrency.keys, ...montos.keys]) {
      if (codigo.isNotEmpty && !divisas.contains(codigo)) divisas.add(codigo);
    }
    return divisas;
  }

  /// Decimales con los que se pinta cada divisa.
  ///
  /// La moneda base va sin decimales (es la unidad contable y sus importes son
  /// grandes) y las demás con dos (importes nominales pequeños): exactamente
  /// el formato que ya tenían CUP y USD.
  int _decimalsFor(String divisa) =>
      divisa == PriceUtils.baseCurrency ? 0 : 2;

  /// Importe por divisa tal y como se pinta en las tarjetas: una línea por
  /// divisa, `$importe DIVISA`.
  String _formatAmountsByCurrency(Map<String, double> montos) {
    return _displayCurrencies(montos)
        .map((divisa) {
          final importe = (montos[divisa] ?? 0).toMoneyString(
            _decimalsFor(divisa),
          );
          return '\$$importe $divisa';
        })
        .join('\n');
  }

  /// Código de divisa de una etiqueta «Medio (DIVISA)».
  ///
  /// Las etiquetas del desglose por medio de pago terminan siempre con el
  /// código entre paréntesis; leerlo evita adivinar la divisa (antes se
  /// comparaba con `contains('(USD)')`, que no admite una tercera divisa).
  String _currencyOfLabel(String etiqueta) {
    final abre = etiqueta.lastIndexOf('(');
    if (abre < 0 || !etiqueta.endsWith(')')) return PriceUtils.baseCurrency;
    final codigo = etiqueta.substring(abre + 1, etiqueta.length - 1).trim();
    return codigo.isEmpty ? PriceUtils.baseCurrency : codigo;
  }

  Future<void> _initializeData() async {
    if (mounted) setState(() => _isLoading = true);
    final isOffline = await _userPreferencesService.isOfflineModeEnabled();
    final onlineTurno = isOffline ? null : await TurnoService.getTurnoAbierto();
    final offlineTurno = await _userPreferencesService.getOpenOfflineTurno();
    final hasActiveTurno = onlineTurno != null || offlineTurno != null;

    if (!mounted) return;
    setState(() {
      _hasActiveTurno = hasActiveTurno;
      if (!hasActiveTurno) _isLoading = false;
    });
    if (!hasActiveTurno) return;

    await _loadExpenses();
    await _calcularVentaTotal();
  }

  /// Carga la tasa de TODAS las divisas de la tienda (antes sólo la de USD).
  ///
  /// `getRatesForStore()` resuelve cada divisa con la misma función que usa el
  /// servidor al registrar el cobro, así que el importe que ve el cajero y el
  /// que guarda la base no pueden discrepar por usar reglas distintas.
  Future<void> _loadRates() async {
    setState(() {
      _isLoadingRates = true;
    });

    Map<String, double> tasas = const {};
    try {
      tasas = await CurrencyService.getRatesForStore();
    } catch (e) {
      print('❌ Error cargando tasas por divisa: $e');
    }

    if (!mounted) return;
    setState(() {
      _ratesByCurrency = tasas;
      _isLoadingRates = false;
    });
  }

  Future<void> _calcularVentaTotal() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Obtener preferencias del usuario
      final userPrefs = UserPreferencesService();

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Cargando datos desde cache...');
        await _calcularVentaTotalOffline();
        return;
      }

      // Modo online: cargar desde Supabase
      print('🌐 Modo online - Cargando datos desde servidor...');

      // Cargar TODAS las órdenes del turno combinando cache offline +
      // pendientes de sincronización + datos frescos del servidor, para que
      // ninguna venta hecha en línea antes de pasar a offline se pierda.
      await _orderService.loadOrdersForOpenTurnoUnified();

      // Obtener datos del turno abierto
      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();

      if (idTpv != null) {
        // Llamar a la función de resumen diario
        //
        // FASE 3 presentaciones: v2. La original devolvia productos_vendidos
        // como integer y REDONDEABA las ventas fraccionadas; la v2 lo devuelve
        // numeric y agrega el equivalente en base y el desglose por presentacion.
        final resumenCierreResponse = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre_v2',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );

        print('📈 VentaTotal Resumen Response: $resumenCierreResponse');
        print('📈 Tipo de respuesta: ${resumenCierreResponse.runtimeType}');

        if (resumenCierreResponse != null) {
          Map<String, dynamic> data;

          // Manejar tanto List como Map de respuesta
          if (resumenCierreResponse is List &&
              resumenCierreResponse.isNotEmpty) {
            // Si es una lista, tomar el primer elemento
            data = resumenCierreResponse[0] as Map<String, dynamic>;
            print(
              '📈 VentaTotal datos extraídos de lista: ${data.keys.toList()}',
            );
          } else if (resumenCierreResponse is Map<String, dynamic>) {
            // Si ya es un mapa, usarlo directamente
            data = resumenCierreResponse;
            print(
              '📈 VentaTotal datos recibidos como mapa: ${data.keys.toList()}',
            );
          } else {
            print('⚠️ Formato de respuesta no reconocido en VentaTotalScreen');
            setState(() {
              _isLoading = false;
            });
            return;
          }

          // Obtener órdenes locales para productos vendidos (ahora ya cargadas)
          final orders = _orderService.orders;
          final productosVendidos = <OrderItem>[];
          final ordenesVendidas = <Order>[];

          for (final order in orders) {
            final isCompletedOrOffline =
                order.status == OrderStatus.completada ||
                order.status == OrderStatus.pagoConfirmado ||
                order.status == OrderStatus.pendienteDeSincronizacion ||
                order.status == OrderStatus.enviada;

            if (isCompletedOrOffline) {
              ordenesVendidas.add(order);
              for (final item in order.items) {
                productosVendidos.add(item);
              }
            }
          }

          // Calcular totales y desglose por tipo de pago desde las órdenes
          // locales (online + pendientes offline). Esto evita duplicar ventas
          // y asegura que el efectivo/transferencia cuadren con los pagos reales.
          final breakdown = await _calculatePaymentBreakdownFromOrders(
            ordenesVendidas,
          );

          setState(() {
            _productosVendidos = productosVendidos;
            _ordenesVendidas = ordenesVendidas;
            _applyPaymentBreakdown(breakdown);
            _totalEgresado = _totalEgresos;
            _isLoading = false;
          });

          print('DEBUG - Venta Total Screen Data:');
          print('Ventas Totales: $_totalVentas');
          print('Productos Vendidos: $_totalProductos');
          print('Órdenes cargadas: ${orders.length}');
          print('Órdenes completadas: ${ordenesVendidas.length}');
          print('Productos vendidos: ${productosVendidos.length}');
          print(
            'Ventas por divisa: $_ventasPorDivisa | '
            'efectivo: $_efectivoPorDivisa | digital: $_digitalPorDivisa',
          );
          print(
            'Efectivo Real (${PriceUtils.baseCurrency}): '
            '\$${_totalEfectivoReal.toMoneyString(2)}',
          );
        }
      }
    } catch (e) {
      print('Error al calcular venta total: $e');
      // Fallback a cálculo local con las órdenes ya cargadas
      final orders = _orderService.orders;
      final productosVendidos = <OrderItem>[];
      final ordenesVendidas = <Order>[];

      for (final order in orders) {
        final isCompletedOrOffline =
            order.status == OrderStatus.completada ||
            order.status == OrderStatus.pagoConfirmado ||
            order.status == OrderStatus.pendienteDeSincronizacion ||
            order.status == OrderStatus.enviada;

        if (isCompletedOrOffline) {
          ordenesVendidas.add(order);
          for (final item in order.items) {
            productosVendidos.add(item);
          }
        }
      }

      final breakdown = await _calculatePaymentBreakdownFromOrders(
        ordenesVendidas,
      );

      setState(() {
        _productosVendidos = productosVendidos;
        _ordenesVendidas = ordenesVendidas;
        _applyPaymentBreakdown(breakdown);
        _totalEgresado = _totalEgresos;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadExpenses() async {
    try {
      final userPrefs = UserPreferencesService();

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await userPrefs.isOfflineModeEnabled();

      List<Expense> expenses = [];

      if (isOfflineModeEnabled) {
        print(
          '🔌 VentaTotal - Modo offline activado, cargando egresos desde cache...',
        );
        expenses = await _loadExpensesOffline();
      } else {
        print(
          '🌐 VentaTotal - Modo online, obteniendo egresos desde servidor...',
        );
        expenses = await TurnoService.getEgresosEnriquecidos();
      }

      // Calculate total expenses and separate by payment type
      double total = 0.0;
      final egresosEfectivoPorDivisa = <String, double>{};
      final egresosDigitalPorDivisa = <String, double>{};

      for (final expense in expenses) {
        total += expense.montoEntrega;

        // ✅ Solo es transferencia si esDigital == true. null cuenta como efectivo.
        //
        // Cada egreso guarda en qué divisa salió el dinero (`Expense.moneda`,
        // de `app_dat_entregas_parciales_caja.moneda`) y `montoEntrega` es su
        // importe NATIVO, así que el cubo es el de esa divisa: atribuirlo a la
        // moneda base descuadraría el arqueo. Los egresos anteriores a la Fase 4
        // no traen divisa y caen en la base, como antes.
        _acumular(
          expense.esDigital == true
              ? egresosDigitalPorDivisa
              : egresosEfectivoPorDivisa,
          clave: expense.moneda,
          monto: expense.montoEntrega,
        );
      }

      setState(() {
        _expenses = expenses;
        _totalEgresos = total;
        _egresosEfectivoPorDivisa = egresosEfectivoPorDivisa;
        _egresosDigitalPorDivisa = egresosDigitalPorDivisa;
      });

      print('DEBUG - Expenses loaded:');
      print('Total egresos: $_totalEgresos');
      print('Egresos efectivo por divisa: $_egresosEfectivoPorDivisa');
      print('Egresos digital por divisa: $_egresosDigitalPorDivisa');
    } catch (e) {
      print('Error loading expenses: $e');
      setState(() {
        _expenses = [];
        _totalEgresos = 0.0;
        _egresosEfectivoPorDivisa = {};
        _egresosDigitalPorDivisa = {};
      });
    }
  }

  Future<List<Expense>> _loadExpensesOffline() async {
    try {
      print('📱 VentaTotal - Cargando egresos desde cache offline...');

      final userPrefs = UserPreferencesService();

      // Obtener egresos desde cache específico
      final egresosData = await userPrefs.getEgresosCache();

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
                // Sin `moneda` (egresos previos a la Fase 4, o cache viejo) el
                // modelo asume la moneda base, que es donde se registraron. El
                // `??` es obligatorio: `Expense.moneda` no es nullable, así que
                // pasar null daría TypeError y el catch de arriba devolvería
                // una lista vacía, perdiendo TODOS los egresos.
                moneda: expenseJson['moneda'] ?? PriceUtils.baseCurrency,
              );
            }).toList();

        print(
          '✅ VentaTotal - Egresos cargados desde cache offline: ${expenses.length}',
        );
        return expenses;
      } else {
        print('ℹ️ VentaTotal - No hay egresos en cache offline');
        return [];
      }
    } catch (e) {
      print('❌ VentaTotal - Error cargando egresos offline: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Divisas distintas de la moneda base que se anuncian en el chip inferior.
    // Se oculta el chip cuando la tienda sólo maneja la moneda base: un
    // «USD: $0» de una divisa que no existe no informa de nada.
    final divisasConTasa =
        _ratesByCurrency.keys
            .where((codigo) => codigo != PriceUtils.baseCurrency)
            .toList()
          ..sort();

    return Scaffold(
      backgroundColor: VentiqHomeTheme.surface,
      appBar: AppBar(
        backgroundColor: VentiqHomeTheme.primary,
        elevation: 0,
        title: const Text(
          'Venta Total',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _initializeData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body:
          !_isLoading && !_hasActiveTurno
              ? _buildNoActiveTurnoState()
              : Stack(
                children: [
                  Column(
                    children: [
                      // Resumen de ventas
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: VentiqHomeTheme.card,
                          border: Border(
                            bottom: BorderSide(
                              color: VentiqHomeTheme.border,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.receipt_long,
                                  color: VentiqHomeTheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Resumen de Ventas',
                                  style: VentiqHomeTheme.tituloSeccion,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildClickableSummaryCard(
                                    'Total Egresado',
                                    _formatAmountsByCurrency(
                                      _sumarPorDivisa(
                                        _egresosEfectivoPorDivisa,
                                        _egresosDigitalPorDivisa,
                                      ),
                                    ),
                                    Icons.attach_money,
                                    VentiqHomeTheme.danger,
                                    onTap: _showEgresosList,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildClickableSummaryCard(
                                    'Total Ventas',
                                    _formatAmountsByCurrency(_ventasPorDivisa),
                                    Icons.attach_money,
                                    VentiqHomeTheme.success,
                                    onTap: _showAllOrders,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildClickableSummaryCard(
                                    'Transferencia',
                                    _formatAmountsByCurrency(_digitalPorDivisa),
                                    Icons.credit_card,
                                    VentiqHomeTheme.warning,
                                    onTap: _showTransferOrders,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildClickableSummaryCard(
                                    'Efectivo Real',
                                    _formatAmountsByCurrency(
                                      _restarPorDivisa(
                                        _efectivoPorDivisa,
                                        _egresosEfectivoPorDivisa,
                                      ),
                                    ),
                                    Icons.account_balance_wallet,
                                    VentiqHomeTheme.success,
                                    onTap: _showCashOrders,
                                  ),
                                ),
                              ],
                            ),
                            if (_totalesPorMedioPago.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Por medio / moneda',
                                  style: VentiqHomeTheme.rotuloBloque.copyWith(
                                    fontSize: 11,
                                    color: VentiqHomeTheme.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...(_totalesPorMedioPago.entries.toList()
                                    ..sort(
                                      (a, b) => a.key.toLowerCase().compareTo(
                                        b.key.toLowerCase(),
                                      ),
                                    ))
                                  .map((e) {
                                    final divisa = _currencyOfLabel(e.key);
                                    final importe = e.value.toMoneyString(
                                      _decimalsFor(divisa),
                                    );
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              e.key,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: VentiqHomeTheme.textSecondary,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '\$$importe $divisa',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: VentiqHomeTheme.textPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                            ],
                          ],
                        ),
                      ),

                      // Lista de órdenes vendidas
                      Expanded(
                        child:
                            _isLoading
                                ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 16),
                                      Text('Cargando datos de ventas...'),
                                    ],
                                  ),
                                )
                                : _ordenesVendidas.isEmpty
                                ? _buildEmptyState()
                                : _buildOrdersList(),
                      ),
                    ],
                  ),
                  // Rate chip positioned at bottom left
                  if (_isLoadingRates || divisasConTasa.isNotEmpty)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: _buildRateChip(divisasConTasa),
                    ),
                ],
              ),
    );
  }

  Widget _buildNoActiveTurnoState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: VentiqHomeTheme.primary.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_clock_outlined,
                size: 48,
                color: VentiqHomeTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No hay turno activo',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Abre un turno para consultar el resumen de ventas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: VentiqHomeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VentiqHomeTheme.border),
        boxShadow: VentiqHomeTheme.shadowCard,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: VentiqHomeTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.15,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildClickableSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: VentiqHomeTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VentiqHomeTheme.border),
          boxShadow: VentiqHomeTheme.shadowCard,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: VentiqHomeTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: _summaryValueFontSize(value),
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.15,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Tamaño del importe en las tarjetas del resumen.
  ///
  /// El resumen tiene una línea por divisa y la tarjeta no puede crecer, así
  /// que la tipografía se encoge al crecer el número de líneas. Con una o dos
  /// líneas se ve exactamente igual que antes (una sola divisa o CUP/USD).
  double _summaryValueFontSize(String value) {
    final lineas = value.split('\n').length;
    if (lineas <= 1) return 19;
    if (lineas == 2) return 13;
    return 10;
  }

  void _showEgresosList() {
    print('🔍 Mostrando lista de egresos...');
    print('📊 Total egresos: $_totalEgresos');
    print('💰 Egresos efectivo por divisa: $_egresosEfectivoPorDivisa');
    print('💳 Egresos digital por divisa: $_egresosDigitalPorDivisa');
    print('📋 Número de egresos: ${_expenses.length}');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => EgresosListScreen(
              expenses: _expenses,
              totalEgresos: _totalEgresos,
              egresosEfectivo: _baseAmount(_egresosEfectivoPorDivisa),
              egresosTransferencias: _baseAmount(_egresosDigitalPorDivisa),
            ),
      ),
    );
  }

  void _showAllOrders() {
    print('🔍 Navegando a todas las órdenes...');
    print('📊 Total órdenes: ${_orderService.orders.length}');
    print('💰 Total ventas: $_totalVentas');

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OrdersScreen()),
    );
  }

  void _showCashOrders() {
    print('🔍 Mostrando órdenes pagadas con efectivo...');
    print('💰 Efectivo por divisa: $_efectivoPorDivisa');

    final completedOrders =
        _orderService.orders
            .where(
              (order) =>
                  order.status == OrderStatus.completada ||
                  order.status == OrderStatus.pagoConfirmado ||
                  order.status == OrderStatus.pendienteDeSincronizacion ||
                  order.status == OrderStatus.enviada,
            )
            .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => FilteredOrdersScreen(
              filter: PaymentFilter.cash,
              title: 'Órdenes - Efectivo',
              orders: completedOrders,
              totalAmount: _baseAmount(_efectivoPorDivisa),
            ),
      ),
    );
  }

  void _showTransferOrders() {
    print('🔍 Mostrando órdenes pagadas con transferencias...');
    print('💳 Digital por divisa: $_digitalPorDivisa');

    final completedOrders =
        _orderService.orders
            .where(
              (order) =>
                  order.status == OrderStatus.completada ||
                  order.status == OrderStatus.pagoConfirmado ||
                  order.status == OrderStatus.pendienteDeSincronizacion ||
                  order.status == OrderStatus.enviada,
            )
            .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => FilteredOrdersScreen(
              filter: PaymentFilter.transfer,
              title: 'Órdenes - Transferencias',
              orders: completedOrders,
              totalAmount: _baseAmount(_digitalPorDivisa),
            ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: VentiqHomeTheme.primary.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_outlined,
              size: 52,
              color: VentiqHomeTheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No hay ventas registradas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: VentiqHomeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Los productos vendidos aparecerán aquí',
            style: TextStyle(
              fontSize: 14,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header de la lista
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: VentiqHomeTheme.surface,
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Orden',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Cliente',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Acción',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Lista de órdenes
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children:
                  _ordenesVendidas
                      .map((order) => _buildOrderItem(order))
                      .toList(),
            ),
          ),

          // Resumen de productos detallado
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VentiqHomeTheme.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: VentiqHomeTheme.border),
              boxShadow: VentiqHomeTheme.shadowCard,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.primary.withOpacity(0.08),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.summarize,
                        color: VentiqHomeTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Resumen Detallado de Productos',
                          style: VentiqHomeTheme.tituloSeccion,
                        ),
                      ),
                      IconButton(
                        onPressed: _imprimirResumenDetallado,
                        icon: const Icon(Icons.print),
                        color: VentiqHomeTheme.primary,
                        tooltip: 'Imprimir resumen',
                      ),
                    ],
                  ),
                ),
                _buildDetailedProductsTable(),
              ],
            ),
          ),

          // Total final
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: VentiqHomeTheme.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: VentiqHomeTheme.border),
              boxShadow: VentiqHomeTheme.shadowCard,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL GENERAL:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
                Text(
                  '\$${_totalVentas.toMoneyString(0)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: VentiqHomeTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VentiqHomeTheme.border),
        boxShadow: VentiqHomeTheme.shadowCard,
      ),
      child: Row(
        children: [
          // Información de la orden
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orden ${order.id}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.items.length} productos',
                  style: const TextStyle(
                    fontSize: 12,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Cliente
          Expanded(
            child: Text(
              order.buyerName ?? 'Sin nombre',
              style: const TextStyle(
                fontSize: 12,
                color: VentiqHomeTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Total
          Expanded(
            child: Text(
              MonedaVentaService.formatearPrecio(
                order.total,
                decimales: 0,
                conSimbolo: true,
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: VentiqHomeTheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Botón de imprimir
          Expanded(
            child: Center(
              child: IconButton(
                onPressed: () => _imprimirTicketIndividual(order),
                icon: const Icon(Icons.print),
                color: VentiqHomeTheme.primary,
                tooltip: 'Imprimir ticket',
                iconSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedProductsTable() {
    // Agrupar productos por nombre para mostrar cantidades totales
    final productosAgrupados = <String, Map<String, dynamic>>{};

    for (final item in _productosVendidos) {
      print('🔍 Procesando item: ${item.nombre}');
      print('🔍 Ingredientes: ${item.ingredientes?.length ?? 0}');

      // Si el producto tiene ingredientes, mostrar los ingredientes en lugar del producto
      if (item.ingredientes != null && item.ingredientes!.isNotEmpty) {
        print('🍽️ Producto elaborado detectado: ${item.nombre}');

        // Procesar cada ingrediente
        for (final ingrediente in item.ingredientes!) {
          final nombreIngrediente =
              ingrediente['nombre_ingrediente'] as String? ?? 'Ingrediente';
          final cantidadVendida =
              (ingrediente['cantidad_vendida'] as num?)?.toDouble() ?? 0.0;
          final cantidadFinal =
              (ingrediente['cantidad_final'] as num?)?.toDouble() ?? 0.0;
          // Calcular cantidad inicial como: final + vendido
          final cantidadInicial = cantidadFinal + cantidadVendida;
          final unidadMedida =
              ingrediente['unidad_medida'] as String? ?? 'unidades';
          final precioUnitario =
              (ingrediente['precio_unitario'] as num?)?.toDouble() ?? 0.0;
          final importe = (ingrediente['importe'] as num?)?.toDouble() ?? 0.0;

          final keyIngrediente = '$nombreIngrediente ($unidadMedida)';

          print('📦 Procesando ingrediente: $keyIngrediente');
          print('   - Cantidad vendida: $cantidadVendida');
          print('   - Cantidad final: $cantidadFinal');
          print(
            '   - Cantidad inicial (calculada): $cantidadInicial = $cantidadFinal + $cantidadVendida',
          );
          print('   - Precio unitario: $precioUnitario');
          print('   - Importe: $importe');

          if (productosAgrupados.containsKey(keyIngrediente)) {
            // Sumar cantidades vendidas e importes de ingredientes duplicados
            productosAgrupados[keyIngrediente]!['cantidad'] += cantidadVendida;
            productosAgrupados[keyIngrediente]!['subtotal'] += importe;
            // Recalcular cantidad inicial como: final + total vendido para ingredientes
            if (productosAgrupados[keyIngrediente]!['cantidadFinal'] != null) {
              productosAgrupados[keyIngrediente]!['cantidadInicial'] =
                  productosAgrupados[keyIngrediente]!['cantidadFinal'] +
                  productosAgrupados[keyIngrediente]!['cantidad'];
            }
            if (productosAgrupados[keyIngrediente]!['cantidadFinal'] == null) {
              productosAgrupados[keyIngrediente]!['cantidadFinal'] =
                  cantidadFinal;
              // Recalcular inicial después de asignar final
              productosAgrupados[keyIngrediente]!['cantidadInicial'] =
                  cantidadFinal +
                  productosAgrupados[keyIngrediente]!['cantidad'];
            }
          } else {
            // Crear entrada para el ingrediente
            productosAgrupados[keyIngrediente] = {
              'item': OrderItem(
                id:
                    'ING-${ingrediente['id_ingrediente']}-${DateTime.now().millisecondsSinceEpoch}',
                producto:
                    item.producto, // Usar el producto padre para referencia
                cantidad: cantidadVendida.toDouble(),
                precioUnitario:
                    precioUnitario, // Precio unitario del ingrediente
                ubicacionAlmacen: item.ubicacionAlmacen,
              ),
              'nombre': nombreIngrediente,
              'unidadMedida': unidadMedida,
              'cantidad': cantidadVendida,
              'subtotal': importe, // Importe del ingrediente
              'cantidadInicial': cantidadInicial,
              'cantidadFinal': cantidadFinal,
              'entradasProducto':
                  (ingrediente['entradas_producto'] as num?)?.toDouble() ?? 0.0,
              'esIngrediente': true,
            };
          }
        }
      } else {
        // Producto (elaborado o normal)
        final key = item.nombre;
        final esElaborado = item.producto.esElaborado;

        if (esElaborado) {
          print('🍽️ Producto elaborado: $key');
        } else {
          print('📦 Producto normal: $key');
        }

        if (productosAgrupados.containsKey(key)) {
          productosAgrupados[key]!['cantidad'] += item.cantidad;
          productosAgrupados[key]!['subtotal'] += item.subtotal;

          // Solo calcular cantidades iniciales y finales para productos NO elaborados
          if (!esElaborado) {
            // Recalcular cantidad inicial como: final + total vendido
            if (productosAgrupados[key]!['cantidadFinal'] != null) {
              productosAgrupados[key]!['cantidadInicial'] =
                  productosAgrupados[key]!['cantidadFinal'] +
                  productosAgrupados[key]!['cantidad'];
            }
            if (productosAgrupados[key]!['cantidadFinal'] == null &&
                item.cantidadFinal != null) {
              productosAgrupados[key]!['cantidadFinal'] = item.cantidadFinal;
              // Recalcular inicial después de asignar final
              productosAgrupados[key]!['cantidadInicial'] =
                  (item.cantidadFinal ?? 0.0) +
                  productosAgrupados[key]!['cantidad'];
            }
          }
        } else {
          if (esElaborado) {
            // Para productos elaborados: cantidades inicial y final = null (se mostrarán como "-")
            productosAgrupados[key] = {
              'item': item,
              'nombre': item.nombre,
              'cantidad': item.cantidad,
              'subtotal': item.subtotal,
              'cantidadInicial': null, // Se mostrará como "-"
              'cantidadFinal': null, // Se mostrará como "-"
              'entradasProducto': item.entradasProducto ?? 0.0,
              'esIngrediente': false,
              'esElaborado': true,
            };
          } else {
            // Calcular cantidad inicial como: final + vendido para productos normales
            final cantidadInicialCalculada =
                (item.cantidadFinal ?? 0.0) + item.cantidad;

            productosAgrupados[key] = {
              'item': item,
              'nombre': item.nombre,
              'cantidad': item.cantidad,
              'subtotal': item.subtotal,
              'cantidadInicial': cantidadInicialCalculada,
              'cantidadFinal': item.cantidadFinal,
              'entradasProducto': item.entradasProducto ?? 0.0,
              'esIngrediente': false,
              'esElaborado': false,
            };
          }
        }
      }
    }

    final productosFinales = productosAgrupados.values.toList();
    print('📋 Total items en resumen: ${productosFinales.length}');

    return Column(
      children: [
        // Header de la tabla detallada
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: VentiqHomeTheme.surface,
          child: const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Producto',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Inicial',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Entra.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Vend.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Final',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),

        // Lista de productos detallada
        ...productosFinales.map(
          (producto) => _buildDetailedProductItem(producto),
        ),
      ],
    );
  }

  Widget _buildDetailedProductItem(Map<String, dynamic> producto) {
    final item = producto['item'] as OrderItem;
    final cantidad = producto['cantidad'] as num;
    final subtotal = producto['subtotal'] as double;
    final cantidadInicial = producto['cantidadInicial'] as double?;
    final cantidadFinal = producto['cantidadFinal'] as double?;
    final entradasProducto = producto['entradasProducto'] as double? ?? 0.0;
    final esIngrediente = producto['esIngrediente'] as bool? ?? false;
    final esElaborado = producto['esElaborado'] as bool? ?? false;
    final nombre = producto['nombre'] as String? ?? item.nombre;
    final unidadMedida = producto['unidadMedida'] as String?;

    // Para ingredientes, usar las cantidades reales del ingrediente
    final cantidadMostrar =
        esIngrediente ? cantidad.toDouble() : cantidad.toDouble();

    // Para productos elaborados, mostrar "-" en cantidades inicial, entradas y final
    final cantidadInicialTexto =
        (esElaborado && cantidadInicial == null)
            ? "-"
            : (cantidadInicial ?? 0.0).toStringAsFixed(esIngrediente ? 1 : 0);
    final entradasTexto =
        esElaborado
            ? "-"
            : entradasProducto.toStringAsFixed(esIngrediente ? 1 : 0);
    final cantidadFinalTexto =
        (esElaborado && cantidadFinal == null)
            ? "-"
            : (cantidadFinal ?? 0.0).toStringAsFixed(esIngrediente ? 1 : 0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: VentiqHomeTheme.border)),
        // Fondo diferente para ingredientes
        color:
            esIngrediente
                ? VentiqHomeTheme.warning.withOpacity(0.06)
                : VentiqHomeTheme.card,
      ),
      child: Row(
        children: [
          // Nombre del producto/ingrediente
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Ícono para ingredientes
                    if (esIngrediente) ...[
                      const Icon(
                        Icons.restaurant,
                        size: 14,
                        color: VentiqHomeTheme.warning,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        nombre,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              esIngrediente
                                  ? VentiqHomeTheme.warning
                                  : VentiqHomeTheme.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (esIngrediente) ...[
                  Text(
                    'Ingrediente${unidadMedida != null ? ' ($unidadMedida)' : ''}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: VentiqHomeTheme.warning,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Text(
                    '${MonedaVentaService.formatearPrecio(item.precioUnitario, conSimbolo: true)} c/u',
                    style: const TextStyle(
                      fontSize: 10,
                      color: VentiqHomeTheme.warning,
                    ),
                  ),
                ] else ...[
                  Text(
                    '${MonedaVentaService.formatearPrecio(item.precioUnitario, decimales: 0, conSimbolo: true)} c/u',
                    style: const TextStyle(
                      fontSize: 10,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Cantidad Inicial
          Expanded(
            child: Text(
              cantidadInicialTexto,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: VentiqHomeTheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Entradas del Producto
          Expanded(
            child: Text(
              entradasTexto,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: VentiqHomeTheme.accent,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Cantidad Vendida
          Expanded(
            child: Text(
              cantidadMostrar.toStringAsFixed(esIngrediente ? 1 : 0),
              style: const TextStyle(
                fontSize: 12,
                color: VentiqHomeTheme.warning,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Cantidad Final
          Expanded(
            child: Text(
              cantidadFinalTexto,
              style: const TextStyle(
                fontSize: 12,
                color: VentiqHomeTheme.success,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Total (ahora incluye ingredientes)
          Expanded(
            child: Text(
              MonedaVentaService.formatearPrecio(
                subtotal,
                decimales: esIngrediente ? 2 : 0,
                conSimbolo: true,
              ),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color:
                    esIngrediente
                        ? VentiqHomeTheme.warning
                        : VentiqHomeTheme.primary,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // Método para imprimir ticket individual
  Future<void> _imprimirTicketIndividual(Order order) async {
    try {
      print(
        '🖨️ Iniciando impresión de ticket individual para orden ${order.id}',
      );

      // Usar PrinterManager para manejar tanto web como Bluetooth
      final result = await _printerManager.printInvoice(context, order);

      if (result.success) {
        _showSuccessDialog('¡Ticket Impreso!', result.message);
        print('✅ ${result.message}');
        if (result.details != null) {
          print('ℹ️ Detalles: ${result.details}');
        }
      } else {
        _showErrorDialog('Error de Impresión', result.message);
        print('❌ ${result.message}');
        if (result.details != null) {
          print('ℹ️ Detalles: ${result.details}');
        }
      }
    } catch (e) {
      _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
      print('❌ Error en _imprimirTicketIndividual: $e');
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: VentiqHomeTheme.danger),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: VentiqHomeTheme.success),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  // Método para imprimir resumen detallado de productos
  Future<void> _imprimirResumenDetallado() async {
    try {
      print('🖨️ Iniciando impresión de resumen detallado');

      // Verificar si estamos en web
      if (PlatformUtils.isWeb) {
        // Usar impresión web
        await _imprimirResumenDetalladoWeb();
      } else {
        // Usar impresión Bluetooth
        await _imprimirResumenDetalladoBluetooth();
      }
    } catch (e) {
      _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
      print('❌ Error en _imprimirResumenDetallado: $e');
    }
  }

  // Método para imprimir resumen detallado en web
  Future<void> _imprimirResumenDetalladoWeb() async {
    try {
      // Mostrar diálogo de confirmación
      bool shouldPrint = await _showPrintSummaryConfirmationDialog();
      if (!shouldPrint) return;

      print('🌐 Imprimiendo resumen detallado en web...');

      // Importar el servicio web
      final webSummaryService = WebSummaryPrinterService();

      // Imprimir usando el servicio web
      bool printed = await webSummaryService.printDetailedSummary(
        productosVendidos: _productosVendidos,
        totalVentas: _totalVentas,
        totalProductos: _totalProductos,
        totalEgresado: _totalEgresado,
        totalEfectivoReal: _totalEfectivoReal,
        totalesPorMedioPago: _totalesPorMedioPago,
      );

      if (printed) {
        _showSuccessDialog(
          '¡Resumen Impreso!',
          'El resumen detallado se ha enviado a impresión web correctamente.',
        );
        print('✅ Resumen detallado impreso en web exitosamente');
      } else {
        _showErrorDialog(
          'Error de Impresión Web',
          'No se pudo imprimir el resumen detallado en web.',
        );
        print('❌ Error imprimiendo resumen detallado en web');
      }
    } catch (e) {
      _showErrorDialog('Error Web', 'Ocurrió un error al imprimir en web: $e');
      print('❌ Error en _imprimirResumenDetalladoWeb: $e');
    }
  }

  // Método para imprimir resumen detallado en Bluetooth
  Future<void> _imprimirResumenDetalladoBluetooth() async {
    try {
      // Mostrar diálogo de confirmación
      bool shouldPrint = await _showPrintSummaryConfirmationDialog();
      if (!shouldPrint) return;

      // Mostrar diálogo de selección de dispositivo
      final device = await _printerService.showDeviceSelectionDialog(context);
      if (device == null) return;

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Conectando e imprimiendo resumen...'),
                ],
              ),
            ),
      );

      // Conectar a la impresora
      bool connected = await _printerService.connectToDevice(device);
      if (!connected) {
        Navigator.pop(context);
        _showErrorDialog(
          'Error de Conexión',
          'No se pudo conectar a la impresora.',
        );
        return;
      }

      // Imprimir el resumen
      bool printed = await _printDetailedSummary();
      Navigator.pop(context);

      if (printed) {
        _showSuccessDialog(
          '¡Resumen Impreso!',
          'El resumen detallado se ha impreso correctamente.',
        );
      } else {
        _showErrorDialog(
          'Error de Impresión',
          'No se pudo imprimir el resumen.',
        );
      }

      // Margen extra tras el drain interno, luego desconectar
      if (printed) {
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      await _printerService.disconnect();
    } catch (e) {
      Navigator.pop(context);
      _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
    }
  }

  Future<bool> _showPrintSummaryConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.summarize, color: VentiqHomeTheme.primary),
                    const SizedBox(width: 8),
                    const Text('Imprimir Resumen'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '¿Deseas imprimir el resumen detallado de productos?',
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Productos: ${PriceUtils.formatQuantity(_totalProductos)}',
                          ),
                          Text(
                            'Total Ventas: ${_formatAmountsByCurrency(_ventasPorDivisa).replaceAll('\n', ' · ')}',
                          ),
                          Text(
                            'Total Egresado: ${_formatAmountsByCurrency(_sumarPorDivisa(_egresosEfectivoPorDivisa, _egresosDigitalPorDivisa)).replaceAll('\n', ' · ')}',
                          ),
                          Text(
                            'Efectivo Real: ${_formatAmountsByCurrency(_restarPorDivisa(_efectivoPorDivisa, _egresosEfectivoPorDivisa)).replaceAll('\n', ' · ')}',
                          ),
                          Text(
                            'Transferencia: ${_formatAmountsByCurrency(_digitalPorDivisa).replaceAll('\n', ' · ')}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.print),
                    label: const Text('Imprimir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VentiqHomeTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<bool> _printDetailedSummary() async {
    try {
      // Obtener información del vendedor
      final workerProfile = await _userPreferencesService.getWorkerProfile();
      final userEmail = await _userPreferencesService.getUserEmail();

      final sellerName =
          '${workerProfile['nombres'] ?? ''} ${workerProfile['apellidos'] ?? ''}'
              .trim();
      final sellerEmail = userEmail ?? 'Sin email';

      // Crear el contenido de impresión usando el formato ESC/POS
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      // Header
      bytes += generator.text(
        'INVENTTIA',
        styles: PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        'RESUMEN DE VENTAS',
        styles: PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '================================',
        styles: PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);

      // Información del vendedor y fecha
      final now = DateTime.now();
      bytes += generator.text(
        'VENDEDOR: $sellerName',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        'EMAIL: $sellerEmail',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        'FECHA: ${_formatDateForPrint(now)}',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.emptyLines(1);

      // Resumen general
      bytes += generator.text(
        'RESUMEN GENERAL:',
        styles: PosStyles(align: PosAlign.left, bold: true),
      );
      bytes += generator.text(
        '--------------------------------',
        styles: PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        'Total Productos: ${PriceUtils.formatQuantity(_totalProductos)}',
        styles: PosStyles(align: PosAlign.left),
      );
      // Una línea por divisa real: el ticket deja de tener columnas fijas
      // CUP/USD y pasa a listar exactamente las divisas del turno.
      void addCurrencyLines(String rotulo, Map<String, double> montos) {
        for (final divisa in _displayCurrencies(montos)) {
          final importe = (montos[divisa] ?? 0).toMoneyString(
            _decimalsFor(divisa),
            ' ',
          );
          bytes += generator.text(
            '$rotulo $divisa: \$$importe',
            styles: PosStyles(align: PosAlign.left),
          );
        }
      }

      addCurrencyLines('Total Ventas', _ventasPorDivisa);
      final mediosPago =
          _totalesPorMedioPago.entries.toList()..sort(
            (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
          );
      for (final medio in mediosPago) {
        final divisa = _currencyOfLabel(medio.key);
        final importe = medio.value.toMoneyString(_decimalsFor(divisa), ' ');
        bytes += generator.text(
          '${medio.key}: \$$importe $divisa',
          styles: PosStyles(align: PosAlign.left),
        );
      }
      addCurrencyLines(
        'Egresado',
        _sumarPorDivisa(_egresosEfectivoPorDivisa, _egresosDigitalPorDivisa),
      );
      addCurrencyLines(
        'Efectivo Real',
        _restarPorDivisa(_efectivoPorDivisa, _egresosEfectivoPorDivisa),
      );
      addCurrencyLines('Transferencia', _digitalPorDivisa);
      bytes += generator.emptyLines(1);

      // Detalle de productos (solo nombre + cantidad vendida)
      bytes += generator.text(
        'DETALLE POR PRODUCTO:',
        styles: PosStyles(align: PosAlign.left, bold: true),
      );
      bytes += generator.text(
        '--------------------------------',
        styles: PosStyles(align: PosAlign.center),
      );

      // Agrupar productos por nombre
      final productosAgrupados = <String, double>{};
      for (final item in _productosVendidos) {
        productosAgrupados.update(
          item.nombre,
          (qty) => qty + item.cantidad,
          ifAbsent: () => item.cantidad,
        );
      }

      // Una línea compacta por producto para no saturar la impresora
      final nombres = productosAgrupados.keys.toList()..sort();
      for (final nombre in nombres) {
        final cantidad = productosAgrupados[nombre]!;
        final qtyStr = PriceUtils.formatQuantity(cantidad);
        final maxNameLen = (28 - qtyStr.length).clamp(8, 27);
        final displayName =
            nombre.length > maxNameLen
                ? '${nombre.substring(0, maxNameLen - 1)}.'
                : nombre;
        final spaces = 28 - displayName.length - qtyStr.length;
        final pad = spaces > 0 ? ' ' * spaces : ' ';
        bytes += generator.text(
          '$displayName$pad$qtyStr',
          styles: PosStyles(align: PosAlign.left),
        );
      }

      // Footer
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        'TOTAL GENERAL: \$${_totalVentas.toMoneyString(0, ' ')}',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      );
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        'INVENTTIA - Sistema de Ventas',
        styles: PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(3);
      bytes += generator.cut();

      // Enviar a la impresora (troceado + espera antes de cortar BT)
      bool result = await _printerService.writeBytesSafe(
        bytes,
        jobName: 'Resumen Detallado',
      );
      return result;
    } catch (e) {
      debugPrint('Error printing detailed summary: $e');
      return false;
    }
  }

  String _formatDateForPrint(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year} "
        "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  /// Chip de tasas: una entrada por divisa distinta de la moneda base.
  ///
  /// Con una sola divisa extra se lee igual que antes («USD: $900»); con
  /// varias, separadas por «·».
  Widget _buildRateChip(List<String> divisas) {
    final texto = divisas
        .map(
          (divisa) =>
              '$divisa: \$${(_ratesByCurrency[divisa] ?? 0).toStringAsFixed(0)}',
        )
        .join('  ·  ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VentiqHomeTheme.border),
        boxShadow: VentiqHomeTheme.shadowCard,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.attach_money,
            size: 16,
            color: VentiqHomeTheme.primary,
          ),
          const SizedBox(width: 4),
          _isLoadingRates
              ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: VentiqHomeTheme.primary,
                ),
              )
              : Text(
                texto,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: VentiqHomeTheme.textPrimary,
                ),
              ),
        ],
      ),
    );
  }

  /// Calcular venta total en modo offline usando cache
  Future<void> _calcularVentaTotalOffline() async {
    try {
      print('📱 Calculando venta total desde cache offline...');

      final userPrefs = UserPreferencesService();

      // Cargar TODAS las órdenes del turno combinando cache offline +
      // pendientes de sincronización + (si hay conexión real) datos frescos
      // del servidor, así ninguna venta ya hecha en línea se pierde al
      // pasar a modo offline.
      await _orderService.loadOrdersForOpenTurnoUnified();

      // Obtener resumen de cierre base desde cache
      final resumenCierre = await userPrefs.getResumenCierreCache();

      if (resumenCierre != null) {
        print('✅ Resumen de cierre cargado desde cache offline');
        print('📊 Datos disponibles: ${resumenCierre.keys.toList()}');

        // Obtener órdenes locales (offline)
        final orders = _orderService.orders;
        final productosVendidos = <OrderItem>[];
        final ordenesVendidas = <Order>[];

        // Filtrar órdenes completadas y offline
        for (final order in orders) {
          final isCompletedOrOffline =
              order.status == OrderStatus.completada ||
              order.status == OrderStatus.pagoConfirmado ||
              order.status == OrderStatus.pendienteDeSincronizacion ||
              order.status == OrderStatus.enviada;

          if (isCompletedOrOffline) {
            ordenesVendidas.add(order);
            for (final item in order.items) {
              productosVendidos.add(item);
            }
          }
        }

        // Calcular totales y desglose por tipo de pago desde las órdenes
        // locales (offline + pendientes). Evita duplicar ventas si el resumen
        // cache ya incluye órdenes offline.
        final breakdown = await _calculatePaymentBreakdownFromOrders(
          ordenesVendidas,
        );

        setState(() {
          _productosVendidos = productosVendidos;
          _ordenesVendidas = ordenesVendidas;
          _applyPaymentBreakdown(breakdown);
          _totalEgresado = _totalEgresos;
          _isLoading = false;
        });

        print('💰 Datos calculados desde cache offline:');
        print('  - Ventas Totales: $_totalVentas');
        print('  - Productos Vendidos: $_totalProductos');
        print('  - Órdenes locales: ${orders.length}');
        print('  - Órdenes completadas/offline: ${ordenesVendidas.length}');
        print('  - Items vendidos: ${productosVendidos.length}');
        print(
          '  - Total Egresado: $_totalEgresado (efectivo: $_egresosEfectivoPorDivisa, digital: $_egresosDigitalPorDivisa)',
        );
        print('  - Ventas por divisa: $_ventasPorDivisa');
        print('  - Efectivo por divisa: $_efectivoPorDivisa');
        print('  - Digital por divisa: $_digitalPorDivisa');
        print(
          '  - Efectivo Real (${PriceUtils.baseCurrency}): $_totalEfectivoReal',
        );

        // Mostrar información de órdenes offline si las hay
        final offlineOrdersCount = orders.where((o) => o.isOfflineOrder).length;
        if (offlineOrdersCount > 0) {
          print('📱 Órdenes offline incluidas en el cálculo:');
          print('  - Órdenes offline: $offlineOrdersCount');
        }
      } else {
        print('⚠️ No hay resumen de cierre en cache - usando cálculo local');
        await _calcularVentaTotalLocalFallback();
      }
    } catch (e) {
      print('❌ Error calculando venta total offline: $e');
      await _calcularVentaTotalLocalFallback();
    }
  }

  /// Fallback: calcular usando solo órdenes locales
  Future<void> _calcularVentaTotalLocalFallback() async {
    try {
      print('🔄 Calculando venta total usando solo órdenes locales...');

      final orders = _orderService.orders;
      final productosVendidos = <OrderItem>[];
      final ordenesVendidas = <Order>[];

      for (final order in orders) {
        if (order.status == OrderStatus.completada ||
            order.status == OrderStatus.pagoConfirmado ||
            order.status == OrderStatus.pendienteDeSincronizacion ||
            order.status == OrderStatus.enviada) {
          ordenesVendidas.add(order);
          for (final item in order.items) {
            productosVendidos.add(item);
          }
        }
      }

      final breakdown = await _calculatePaymentBreakdownFromOrders(
        ordenesVendidas,
      );

      setState(() {
        _productosVendidos = productosVendidos;
        _ordenesVendidas = ordenesVendidas;
        _applyPaymentBreakdown(breakdown);
        _totalEgresado = _totalEgresos;
        _isLoading = false;
      });

      print('💰 Datos calculados localmente (fallback):');
      print('  - Ventas Totales: $_totalVentas');
      print('  - Productos Vendidos: $_totalProductos');
      print('  - Órdenes completadas: ${ordenesVendidas.length}');
      print('  - Items vendidos: ${productosVendidos.length}');
      print(
        '  - Efectivo por divisa: $_efectivoPorDivisa',
      );
    } catch (e) {
      print('❌ Error en cálculo local fallback: $e');
      setState(() {
        _isLoading = false;
        // Valores por defecto en caso de error total
        _totalVentas = 0.0;
        _totalProductos = 0.0;
        _productosVendidos = [];
        _ordenesVendidas = [];
        _totalEgresado = 0.0;
        _ventasPorDivisa = {};
        _efectivoPorDivisa = {};
        _digitalPorDivisa = {};
      });
    }
  }
}
