import 'dart:async';

import 'package:flutter/material.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';
import '../models/expense.dart';
import '../theme/ventiq_home_theme.dart';
import '../utils/navigation_helper.dart';
import '../utils/price_utils.dart';

class SalesMonitorFAB extends StatefulWidget {
  const SalesMonitorFAB({Key? key}) : super(key: key);

  @override
  State<SalesMonitorFAB> createState() => _SalesMonitorFABState();
}

class _SalesMonitorFABState extends State<SalesMonitorFAB>
    with TickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isLoading = false;
  bool _isOfflineMode = false;
  Map<String, dynamic>? _currentSales;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  /// Entrada animada del desglose (medios de pago + monedas).
  ///
  /// Un único controlador para todas las filas: el escalonado sale de repartir
  /// su `value` con un desfase por índice (`_progreso`), así no hace falta un
  /// controller por fila ni estado extra. Se reinicia con `forward(from: 0)`
  /// cuando llegan los datos, de modo que al reabrir el panel la animación
  /// vuelve a correr entera en vez de quedarse a medias.
  late AnimationController _desgloseCtrl;

  /// Cuánto tiempo el total sigue en la píldora después de cerrar el panel.
  ///
  /// Cerrar es el momento en que el vendedor quiere quedarse con el total del
  /// turno, así que se deja a la vista unos segundos. Pasado ese rato el
  /// importe es ruido: la píldora vive pegada al chip del USD del Home y, si
  /// se queda ahí, lo tapa y le roba sitio al rótulo. Cinco segundos dan
  /// tiempo a leerlo sin dejar la píldora deformada de forma permanente.
  static const Duration _duracionTotalEnPildora = Duration(seconds: 5);

  /// Si la píldora debe mostrar el importe del turno ahora mismo. Es solo
  /// estado de presentación: NO se toca `_currentSales`, porque el resumen
  /// cargado lo sigue necesitando el panel al volver a abrirse (y así no hay
  /// que recargarlo).
  bool _muestraTotalEnPildora = false;

  /// Cuenta atrás que retira el importe de la píldora. Hay como mucho uno vivo:
  /// cada cierre cancela el anterior antes de programar el siguiente.
  Timer? _timerOcultarTotal;

  /// Si el bloque «POR MONEDA» está plegado.
  ///
  /// `null` = criterio automático (ver [_buildBloqueMonedas]). En cuanto el
  /// vendedor toca el rótulo manda su elección y el automático deja de aplicar;
  /// se deja en `null` hasta ese primer toque para que el bloque siga
  /// adaptándose al número de divisas que traiga el turno.
  bool? _monedasPlegadas;

  /// El sistema pidió reducir movimiento: se pinta el estado final sin animar.
  ///
  /// Es la misma comprobación que hace [_progreso] para las filas, y la que usa
  /// el pliegue del bloque de monedas. En un TPV de mostrador el panel se abre
  /// decenas de veces por turno; marear aquí no aporta nada.
  bool get _sinAnimaciones =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  // Expenses data
  List<Expense> _expenses = [];
  double _egresosEfectivo = 0.0;
  double _egresosTransferencias = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _desgloseCtrl = AnimationController(
      duration: const Duration(milliseconds: 620),
      vsync: this,
    );
  }

  @override
  void dispose() {
    // Ningún callback debe sobrevivir al widget: si la cuenta atrás siguiera
    // viva dispararía un setState sobre un State ya desmontado.
    _cancelarTimerOcultarTotal();
    _animationController.dispose();
    _desgloseCtrl.dispose();
    super.dispose();
  }

  /// Descarta la cuenta atrás pendiente, si la hay, sin tocar el estado visible.
  void _cancelarTimerOcultarTotal() {
    _timerOcultarTotal?.cancel();
    _timerOcultarTotal = null;
  }

  /// Tras cerrar el panel, deja el total a la vista en la píldora durante
  /// [_duracionTotalEnPildora] y programa su retirada.
  void _programarOcultarTotal() {
    // Sin resumen cargado no hay importe que mostrar: nada que programar.
    if (_currentSales == null) return;

    // Un único timer: se descarta cualquier cuenta anterior antes de crear la
    // nueva, así cerrar y volver a cerrar nunca acumula temporizadores.
    _cancelarTimerOcultarTotal();

    setState(() {
      _muestraTotalEnPildora = true;
    });

    _timerOcultarTotal = Timer(_duracionTotalEnPildora, () {
      // El widget pudo desmontarse mientras corría la cuenta (y `dispose` ya
      // canceló el timer); sin `mounted` el setState sería un error.
      if (!mounted) return;
      setState(() {
        _muestraTotalEnPildora = false;
      });
    });
  }

  void _toggleExpansion() {
    final bool abriendo = !_isExpanded;

    // Abrir cancela la cuenta atrás pendiente: el usuario está mirando los datos
    // y la píldora no debe cambiar sola por debajo de lo que está leyendo. Al
    // volver a cerrar, la cuenta arranca de cero con un único timer.
    _cancelarTimerOcultarTotal();

    setState(() {
      _isExpanded = abriendo;
      // Al abrir, la píldora vuelve ya a su rótulo normal: el total se lee en el
      // propio panel, no hace falta duplicarlo detrás.
      _muestraTotalEnPildora = false;
    });

    if (abriendo) {
      _animationController.forward();
      // Si el resumen ya estaba cargado (reabrir el panel), el desglose se
      // anima ya; si no, lo arranca `_loadSalesData` cuando llegan los datos.
      if (_currentSales != null) _desgloseCtrl.forward(from: 0);
      _loadDataSequentially();
    } else {
      _animationController.reverse();
      _programarOcultarTotal();
    }
  }

  Future<void> _loadDataSequentially() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _isOfflineMode = await UserPreferencesService().isOfflineModeEnabled();
    } catch (_) {
      _isOfflineMode = false;
    }

    await _loadExpenses();
    await _loadSalesData();
  }

  Future<void> _loadSalesData() async {
    try {
      final userPrefs = UserPreferencesService();

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print(
          '🔌 SalesMonitor - Modo offline activado, cargando desde cache...',
        );
        await _loadSalesDataOffline();
        return;
      }

      // Modo online: cargar desde servidor
      print('🌐 SalesMonitor - Modo online, cargando desde servidor...');

      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();

      if (idTpv != null) {
        print(
          '🧪 Loading sales data with fn_resumen_diario_cierre_v2 - TPV: $idTpv',
        );

        // FASE 3 presentaciones: v2. La original devolvia productos_vendidos
        // como integer y REDONDEABA (tres lineas de 0,5 kg daban 2). La v2 lo
        // devuelve numeric y agrega productos_vendidos_base (equivalente en
        // unidades base) y productos_vendidos_desglose ("2 Cajas + 5 Unidades").
        // La original sigue viva para las apps sin actualizar.
        // `_v4` primero: es la que devuelve `desglose_monedas`, la fuente del
        // bloque por moneda. Si el backend todavía no la tiene, el servicio cae
        // solo a la `_v2`. Antes se llamaba a la `_v2` directa y por eso el
        // panel no veía más de una divisa aunque hubiera cobros en USD.
        final Map<String, dynamic>? resumen =
            await TurnoService.getResumenDiarioCierre(
              idTpv: idTpv,
              usuario: userID,
            );

        print('📈 SalesMonitor resumen: ${resumen?.keys.toList()}');

        setState(() {
          _currentSales = resumen;
          _isLoading = false;
        });
        // La animación del desglose se lanza cuando hay datos de verdad: si
        // arrancara al abrir el panel (mientras carga) se gastaría sobre el
        // esqueleto y el usuario no la vería.
        if (resumen != null && _isExpanded) {
          _desgloseCtrl.forward(from: 0);
        }
      } else {
        setState(() {
          _currentSales = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Error loading sales data: $e');
    }
  }

  /// Cargar datos de ventas en modo offline
  Future<void> _loadSalesDataOffline() async {
    try {
      print('📱 SalesMonitor - Cargando datos desde cache offline...');

      final userPrefs = UserPreferencesService();

      // Obtener resumen de cierre actualizado con órdenes offline
      final resumenCierre = await userPrefs.getResumenCierreWithOfflineOrders();

      if (resumenCierre != null) {
        print('✅ SalesMonitor - Resumen de cierre cargado desde cache offline');
        print('📊 Datos disponibles: ${resumenCierre.keys.toList()}');

        setState(() {
          _currentSales = resumenCierre;
          _isLoading = false;
        });

        print('💰 SalesMonitor - Datos cargados desde cache offline:');
        print('  - Ventas totales: \$${resumenCierre['ventas_totales']}');
        print('  - Productos vendidos: ${resumenCierre['productos_vendidos']}');

        // Mostrar información de órdenes offline si las hay
        if (resumenCierre['ordenes_offline'] != null &&
            resumenCierre['ordenes_offline'] > 0) {
          print('📱 SalesMonitor - Órdenes offline incluidas:');
          print('  - Órdenes offline: ${resumenCierre['ordenes_offline']}');
          print('  - Ventas offline: \$${resumenCierre['ventas_offline']}');
        }
      } else {
        print('⚠️ SalesMonitor - No hay resumen de cierre en cache');
        setState(() {
          _currentSales = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ SalesMonitor - Error cargando datos offline: $e');
      setState(() {
        _currentSales = null;
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
          '🔌 SalesMonitor - Modo offline activado, cargando egresos desde cache...',
        );
        expenses = await _loadExpensesOffline();
      } else {
        print(
          '🌐 SalesMonitor - Modo online, obteniendo egresos desde servidor...',
        );
        expenses = await TurnoService.getEgresosEnriquecidos();
      }

      // Calculate expenses by payment type
      double efectivo = 0.0;
      double transferencias = 0.0;

      for (final expense in expenses) {
        // Si esDigital es false explícitamente, es efectivo
        // Si esDigital es true o null, considerarlo como transferencia/digital
        if (expense.esDigital == false) {
          efectivo += expense.montoEntrega;
        } else {
          transferencias += expense.montoEntrega;
        }
      }

      setState(() {
        _expenses = expenses;
        _egresosEfectivo = efectivo;
        _egresosTransferencias = transferencias;
      });

      print('DEBUG - Sales Monitor Expenses loaded:');
      print('Egresos efectivo: $_egresosEfectivo');
      print('Egresos transferencias: $_egresosTransferencias');
    } catch (e) {
      print('Error loading expenses in sales monitor: $e');
      setState(() {
        _expenses = [];
        _egresosEfectivo = 0.0;
        _egresosTransferencias = 0.0;
      });
    }
  }

  Future<List<Expense>> _loadExpensesOffline() async {
    try {
      print('📱 SalesMonitor - Cargando egresos desde cache offline...');

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
                // Fase 4: el egreso se registró en una divisa concreta y
                // `montoEntrega` es su importe NATIVO, así que hay que
                // conservarla. Sin ella el modelo asume la moneda base y un
                // egreso en USD se leería como CUP. Los egresos anteriores a la
                // Fase 4 (y el cache viejo) no traen el campo: caen en la base,
                // exactamente como antes.
                moneda: expenseJson['moneda'] ?? PriceUtils.baseCurrency,
              );
            }).toList();

        print(
          '✅ SalesMonitor - Egresos cargados desde cache offline: ${expenses.length}',
        );
        return expenses;
      } else {
        print('ℹ️ SalesMonitor - No hay egresos en cache offline');
        return [];
      }
    } catch (e) {
      print('❌ SalesMonitor - Error cargando egresos offline: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: <Widget>[
        // Panel expandible
        AnimatedBuilder(
          animation: _expandAnimation,
          builder: (BuildContext context, Widget? child) {
            return Transform.scale(
              scale: _expandAnimation.value.clamp(0.0, 1.05),
              alignment: Alignment.bottomRight,
              child: Opacity(
                opacity: _expandAnimation.value.clamp(0.0, 1.0),
                child:
                    _isExpanded ? _buildSalesPanel() : const SizedBox.shrink(),
              ),
            );
          },
        ),
        _buildBotonFlotante(),
      ],
    );
  }

  /// Botón «Mis ventas»: píldora con degradado de marca, etiqueta siempre
  /// visible y, durante los [_duracionTotalEnPildora] siguientes a cerrar el
  /// panel, el total del turno en un badge. El badge es temporal a propósito:
  /// en el Home la píldora comparte fila con el chip del USD y un importe fijo
  /// ahí lo tapa, así que se retira solo y el botón vuelve a su rótulo normal.
  Widget _buildBotonFlotante() {
    final double? total =
        (_currentSales?['ventas_totales'] as num?)?.toDouble();

    return Semantics(
      button: true,
      label: _isExpanded ? 'Cerrar Mis ventas' : 'Abrir Mis ventas',
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        shadowColor: VentiqHomeTheme.primary.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: _toggleExpansion,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  VentiqHomeTheme.primaryLight,
                  VentiqHomeTheme.primary,
                ],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedRotation(
                    turns: _isExpanded ? 0.125 : 0.0,
                    duration: const Duration(milliseconds: 260),
                    child: Icon(
                      _isExpanded
                          ? Icons.close_rounded
                          : Icons.insights_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isExpanded ? 'Cerrar' : 'Mis ventas',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (!_isExpanded &&
                      _muestraTotalEnPildora &&
                      total != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '\$${PriceUtils.formatAmount(total)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  if (!_isExpanded && _isOfflineMode) ...<Widget>[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.cloud_off_rounded,
                      color: Colors.white70,
                      size: 15,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Texto de "Productos vendidos" para el panel del FAB.
  ///
  /// FASE 3 presentaciones. Prioridad:
  ///   1. `productos_vendidos_desglose` — ya formateado por el SQL con el mismo
  ///      `fn_plural_presentacion` que usa el resto de la app, asi que el texto
  ///      es identico en el FAB, el kardex y los reportes.
  ///   2. `productos_vendidos_base` — el equivalente en unidades base, que es
  ///      el numero comparable entre turnos, etiquetado `u. base`.
  ///   3. `productos_vendidos` — lo que devolvia la RPC vieja.
  ///
  /// Se formatea sin decimales cuando el valor es entero, para no mostrar
  /// "12.0 uds" donde antes decia "12 uds".
  String _textoProductosVendidos() {
    final desglose = _currentSales?['productos_vendidos_desglose'];
    if (desglose is String && desglose.trim().isNotEmpty) return desglose;

    final base = _currentSales?['productos_vendidos_base'];
    if (base is num) return '${_fmtCantidad(base)} u. base';

    final crudo = _currentSales?['productos_vendidos'];
    if (crudo is num) return '${_fmtCantidad(crudo)} uds';
    return '0 uds';
  }

  String _fmtCantidad(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  Widget _buildSalesPanel() {
    return Container(
      margin: const EdgeInsets.only(right: 16, bottom: 78),
      width: 340,
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusBlock),
        border: Border.all(color: VentiqHomeTheme.border),
        boxShadow: VentiqHomeTheme.shadowBuscador,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildPanelHeader(),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(
                color: VentiqHomeTheme.primary,
                strokeWidth: 2.6,
              ),
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _buildSalesContent(),
            ),
        ],
      ),
    );
  }

  /// Cabecera con degradado de marca: título, estado del turno, total grande y
  /// refresco. El total vive aquí (no en una tarjeta) porque es el dato que el
  /// vendedor quiere ver de un vistazo.
  Widget _buildPanelHeader() {
    final double total =
        (_currentSales?['ventas_totales'] as num?)?.toDouble() ?? 0;
    final int operaciones =
        (_currentSales?['operaciones_totales'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: VentiqHomeTheme.heroGradient,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Mis ventas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Icon(
                      _isOfflineMode
                          ? Icons.cloud_off_rounded
                          : Icons.schedule_rounded,
                      size: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _isOfflineMode
                            ? 'Offline · $operaciones operaciones'
                            : 'Turno en curso · $operaciones operaciones',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_currentSales != null) ...<Widget>[
            Text(
              '\$${PriceUtils.formatAmount(total)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(width: 2),
          ],
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _isLoading ? null : _loadDataSequentially,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesContent() {
    if (_currentSales == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
        child: Column(
          children: <Widget>[
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: VentiqHomeTheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                color: VentiqHomeTheme.textSecondary.withValues(alpha: 0.7),
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Aún no hay ventas en este turno',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cuando registres ventas verás aquí el resumen del turno.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: VentiqHomeTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final Map<String, dynamic> ventas = _currentSales!;
    final double total = (ventas['ventas_totales'] as num?)?.toDouble() ?? 0;
    final int operaciones =
        (ventas['operaciones_totales'] as num?)?.toInt() ?? 0;
    final double ticketPromedio = operaciones > 0 ? total / operaciones : 0;

    // ── Criterio de agregación del bloque de medios de pago ────────────────
    //
    // `desglose_monedas` es el único dato que llega ya consolidado por divisa
    // (`importe_base` = `Σ monto × tasa`), así que cuando está se reconstruye
    // desde él el efectivo cobrado: cada `efectivo_nativo` se reparte con la
    // tasa media implícita de su fila (`importe_base / importe_nativo`) y la
    // suma queda en moneda base.
    //
    // Por qué se prefiere a `efectivo_real`: esa columna de
    // `fn_resumen_diario_cierre_v2` es `SUM(pv.monto)` de los pagos en efectivo
    // **sin convertir**, así que en un turno con CUP y USD suma unidades
    // distintas (1 000 CUP + 10 USD se leen como «1 010 CUP»). Es el defecto
    // contable que la fase 4 parchea en el servidor; mientras una instalación
    // siga con la `_v2` sin parchear, el desglose es la fuente correcta.
    // Sin desglose se cae al `efectivo_real` de siempre: la degradación con RPC
    // antigua queda idéntica a la que había.
    final List<_MonedaDesglose> monedas = _leerDesgloseMonedas();
    final double efectivoReal;
    if (monedas.isEmpty) {
      efectivoReal = (ventas['efectivo_real'] as num?)?.toDouble() ?? 0;
    } else {
      efectivoReal = monedas.fold<double>(
        0,
        (double suma, _MonedaDesglose moneda) => suma + moneda.efectivoEnBase,
      );
    }
    final double efectivo = efectivoReal - _egresosEfectivo;
    // La transferencia es el RESTO y no un segundo cálculo: así las dos filas
    // del desglose suman siempre `ventas_totales`, que es lo primero que el
    // vendedor cuadra contra el total de la cabecera.
    final double transferencia = total - efectivo;
    final double egresosTotales = _egresosEfectivo + _egresosTransferencias;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _buildMetricCard(
                  'Operaciones',
                  '$operaciones',
                  Icons.receipt_long_rounded,
                  VentiqHomeTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricCard(
                  'Ticket promedio',
                  '\$${PriceUtils.formatAmount(ticketPromedio)}',
                  Icons.local_offer_rounded,
                  VentiqHomeTheme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDesglose(efectivo, transferencia),
          if (egresosTotales > 0) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VentiqHomeTheme.danger.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: VentiqHomeTheme.danger.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.south_west_rounded,
                    size: 16,
                    color: VentiqHomeTheme.danger,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Egresos del turno',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: VentiqHomeTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '\$${PriceUtils.formatAmount(egresosTotales)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: VentiqHomeTheme.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(
                Icons.inventory_2_outlined,
                size: 15,
                color: VentiqHomeTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Productos vendidos',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  _textoProductosVendidos(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAccionesRapidas(),
        ],
      ),
    );
  }

  // ────────────────────────── Desglose del turno ──────────────────────────

  /// Progreso (0..1) de la fila [indice] dentro de la entrada del desglose.
  ///
  /// Sale de un solo controlador con un desfase creciente por índice: el
  /// escalonado no cuesta un controller por fila y, como se reinicia con
  /// `forward(from: 0)`, al reabrir el panel la cascada vuelve a correr limpia.
  /// Con las animaciones desactivadas en el sistema se devuelve 1 directamente:
  /// en un TPV de mostrador no se debe marear a nadie.
  double _progreso(int indice) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return 1;
    final double desde = (indice * 0.07).clamp(0.0, 0.50);
    final double t = ((_desgloseCtrl.value - desde) / (1 - desde)).clamp(
      0.0,
      1.0,
    );
    return Curves.easeOutCubic.transform(t);
  }

  /// Fade + deslizamiento corto de la fila [indice]. El desplazamiento es de
  /// 10 px: suficiente para leerse como «entra», no tanto como para marear.
  Widget _aparece(int indice, Widget hijo) {
    final double p = _progreso(indice);
    return Opacity(
      opacity: p,
      child: Transform.translate(offset: Offset(0, (1 - p) * 10), child: hijo),
    );
  }

  /// Los dos bloques del desglose: medios de pago y, cuando hay más de una
  /// divisa, el detalle por moneda.
  Widget _buildDesglose(double efectivo, double transferencia) {
    final List<_MonedaDesglose> monedas = _leerDesgloseMonedas();
    final double totalBase = _num(_currentSales?['total_base']);

    return AnimatedBuilder(
      animation: _desgloseCtrl,
      builder: (BuildContext context, Widget? _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _aparece(0, _buildBloqueMedios(efectivo, transferencia)),
            // Con una sola divisa este bloque repetiría el total que ya está
            // arriba: no aporta y roba alto al panel. Es el mismo criterio que
            // el resto de la app, que esconde las vistas por divisa cuando solo
            // hay una.
            if (monedas.length >= 2) ...<Widget>[
              const SizedBox(height: 10),
              _aparece(1, _buildBloqueMonedas(monedas, totalBase)),
            ],
          ],
        );
      },
    );
  }

  /// Desglose agregado por medio de pago (todas las divisas juntas).
  Widget _buildBloqueMedios(double efectivo, double transferencia) {
    final double totalMedios = efectivo.abs() + transferencia.abs();
    final double fEfectivo = totalMedios > 0 ? efectivo.abs() / totalMedios : 0;
    final double fDigital =
        totalMedios > 0 ? transferencia.abs() / totalMedios : 0;

    return _tarjetaDesglose(
      titulo: 'POR MEDIO DE PAGO',
      // El bloque está agregado en moneda base. Se rotula la unidad UNA vez en
      // la cabecera en vez de repetirla en cada fila: en 288 px de ancho útil,
      // dos «CUP» más los importes empujarían la etiqueta a los puntos
      // suspensivos. Es además lo que quita la ambigüedad del `$` delante de
      // cada importe.
      detalle: PriceUtils.baseCurrency,
      hijos: <Widget>[
        _filaMedio('Efectivo', efectivo, fEfectivo, VentiqHomeTheme.success, 2),
        const SizedBox(height: 10),
        _filaMedio(
          'Digital / Transferencia',
          transferencia,
          fDigital,
          VentiqHomeTheme.primary,
          3,
        ),
      ],
    );
  }

  Widget _filaMedio(
    String etiqueta,
    double monto,
    double fraccion,
    Color color,
    int indice,
  ) {
    final double p = _progreso(indice);
    // `excludeSemantics` + una etiqueta con los valores FINALES: sin esto el
    // lector de pantalla iría anunciando cada fotograma del conteo (una decena
    // de importes por fila). El importe va en la moneda base en la que está
    // expresado el bloque, y el porcentaje se redondea igual que en pantalla.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          '$etiqueta: ${PriceUtils.formatAmount(monto)} '
          '${PriceUtils.baseCurrency}, '
          '${(fraccion * 100).round()} por ciento del total',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  etiqueta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
              ),
              Text(
                '\$${PriceUtils.formatAmount(monto * p)}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 34,
                child: Text(
                  '${(fraccion * p * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _barra(fraccion * p, color),
        ],
      ),
    );
  }

  /// Detalle por divisa: lo cobrado en cada una, con el reparto efectivo/digital
  /// y el equivalente cuando no es la moneda base.
  Widget _buildBloqueMonedas(List<_MonedaDesglose> monedas, double totalBase) {
    final List<Widget> filas = <Widget>[
      _leyendaApilada(),
      const SizedBox(height: 10),
    ];
    for (int i = 0; i < monedas.length; i++) {
      if (i > 0) filas.add(const SizedBox(height: 12));
      filas.add(_filaMoneda(monedas[i], 4 + i));
    }
    if (totalBase > 0) {
      final double p = _progreso(4 + monedas.length);
      filas.addAll(<Widget>[
        const SizedBox(height: 10),
        Container(height: 1, color: VentiqHomeTheme.border),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Consolidado',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: VentiqHomeTheme.textSecondary,
                ),
              ),
            ),
            Text(
              '\$${PriceUtils.formatAmount(totalBase * p)}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
          ],
        ),
      ]);
    }
    // Con dos divisas —el caso normal CUP + USD— el bloque se abre solo, para que
    // el desglose se vea sin tocar nada. Con tres o más nace plegado: es el
    // único bloque cuya altura depende de los datos y, abierto, empujaría los
    // accesos rápidos fuera de pantalla. El vendedor puede abrirlo tocando el
    // rótulo; a partir de ahí manda su elección, no el automático.
    final bool plegado = _monedasPlegadas ?? monedas.length > 2;
    return _tarjetaDesglose(
      titulo: 'POR MONEDA',
      detalle: '${monedas.length} divisas',
      plegado: plegado,
      onToggle:
          () => setState(() {
            _monedasPlegadas = !plegado;
          }),
      hijos: filas,
    );
  }

  Widget _filaMoneda(_MonedaDesglose m, int indice) {
    final double p = _progreso(indice);
    final bool esBase = m.moneda == PriceUtils.baseCurrency;
    // El importe nativo SIEMPRE con su código, también para el lector de
    // pantalla: en una app multimoneda un «$» suelto no distingue CUP de USD y
    // estos importes no son sumables entre filas. La etiqueta usa los valores
    // finales para no anunciar el conteo fotograma a fotograma.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          '${m.moneda}: ${PriceUtils.formatAmount(m.nativo)} ${m.moneda}, '
          '${m.operaciones} operaciones. '
          'Efectivo ${PriceUtils.formatAmount(m.efectivo)} ${m.moneda}, '
          'digital ${PriceUtils.formatAmount(m.digital)} ${m.moneda}'
          '${esBase ? '' : '. Equivale a ${PriceUtils.formatAmount(m.base)} '
                  '${PriceUtils.baseCurrency}'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _chipMoneda(m.moneda),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${m.operaciones} op${m.operaciones == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ),
              // Importe NATIVO con su código: en una app multimoneda un `$` suelto
              // no distingue CUP de USD, y estos importes no son sumables entre
              // filas.
              Text(
                '${PriceUtils.formatAmount(m.nativo * p)} ${m.moneda}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: VentiqHomeTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _barraApilada(
            efectivo: m.efectivo,
            digital: m.digital,
            progreso: p,
            alto: 7,
          ),
          if (!esBase) ...<Widget>[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '≈ ${PriceUtils.formatAmount(m.base * p)} ${PriceUtils.baseCurrency}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: VentiqHomeTheme.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Barra de un solo tramo que crece desde la izquierda.
  Widget _barra(double fraccion, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: VentiqHomeTheme.border),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraccion.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Barra apilada efectivo/digital de una divisa. Las proporciones van fijas
  /// dentro del `FractionallySizedBox`: así la barra entera crece con la
  /// animación en vez de saltar de tamaño al cambiar los `flex`.
  Widget _barraApilada({
    required double efectivo,
    required double digital,
    required double progreso,
    required double alto,
  }) {
    final double total = efectivo + digital;
    final int flexEfectivo =
        total > 0 ? ((efectivo / total) * 1000).round() : 0;
    final int flexDigital = total > 0 ? 1000 - flexEfectivo : 1000;

    return ClipRRect(
      borderRadius: BorderRadius.circular(alto),
      child: SizedBox(
        height: alto,
        child: ColoredBox(
          color: VentiqHomeTheme.border,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progreso.clamp(0.0, 1.0),
              heightFactor: 1,
              child: Row(
                // Sin `stretch` los tramos (ColoredBox sin hijo) se quedan con
                // altura 0 y la barra se ve solo gris.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (flexEfectivo > 0)
                    Expanded(
                      flex: flexEfectivo,
                      child: const ColoredBox(color: VentiqHomeTheme.success),
                    ),
                  if (flexDigital > 0)
                    Expanded(
                      flex: flexDigital,
                      child: const ColoredBox(color: VentiqHomeTheme.primary),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _leyendaApilada() {
    return Row(
      children: <Widget>[
        _punto(VentiqHomeTheme.success),
        const SizedBox(width: 4),
        const Text(
          'Efectivo',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: VentiqHomeTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        _punto(VentiqHomeTheme.primary),
        const SizedBox(width: 4),
        const Text(
          'Digital',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: VentiqHomeTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _punto(Color color) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _chipMoneda(String moneda) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: VentiqHomeTheme.primary.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        moneda,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: VentiqHomeTheme.primary,
        ),
      ),
    );
  }

  /// Tarjeta contenedora de un bloque del desglose.
  ///
  /// Con [onToggle] la cabecera pasa a ser pulsable y el contenido se pliega
  /// con [AnimatedSize]. El bloque de monedas es el único cuya altura depende
  /// de los datos —una fila por divisa— y el panel vive pegado a la esquina sin
  /// scroll, así que con tres o más divisas lo abierto empujaría los accesos
  /// rápidos fuera de pantalla. El bloque de medios de pago no pasa [onToggle]
  /// y se pinta exactamente como antes.
  Widget _tarjetaDesglose({
    required String titulo,
    required List<Widget> hijos,
    String? detalle,
    bool plegado = false,
    VoidCallback? onToggle,
  }) {
    const TextStyle estiloTitulo = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      color: VentiqHomeTheme.textSecondary,
    );

    final Widget cabecera = Row(
      children: <Widget>[
        Expanded(
          child: Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: estiloTitulo,
          ),
        ),
        if (detalle != null) ...<Widget>[
          const SizedBox(width: 6),
          Text(
            detalle,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
        ],
        if (onToggle != null) ...<Widget>[
          const SizedBox(width: 2),
          // Girado 180° cuando está abierto: el chevron apunta arriba, que es
          // hacia donde se recoge.
          AnimatedRotation(
            turns: plegado ? 0 : 0.5,
            duration:
                _sinAnimaciones
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
            child: const Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
        ],
      ],
    );

    final Widget cuerpo = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: hijos,
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (onToggle == null)
            cabecera
          else
            Semantics(
              button: true,
              excludeSemantics: true,
              label:
                  plegado
                      ? 'Mostrar el desglose por moneda'
                      : 'Ocultar el desglose por moneda',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: cabecera,
                ),
              ),
            ),
          // El cuerpo se pinta SIEMPRE que no esté plegado. Antes esta rama
          // estaba condicionada a `onToggle`, así que la tarjeta de medios de
          // pago (que no se pliega) salía solo con la cabecera.
          if (onToggle == null)
            cuerpo
          else
            AnimatedSize(
              duration:
                  _sinAnimaciones
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: plegado ? const SizedBox(width: double.infinity) : cuerpo,
            ),
        ],
      ),
    );
  }

  /// `numeric` de Postgres llega como `int`, `double` o **texto** según cómo lo
  /// serialice PostgREST: se acepta cualquiera en vez de asumir un subtipo y
  /// romper el panel entero.
  static double _num(dynamic valor) {
    if (valor is num) return valor.toDouble();
    return double.tryParse('${valor ?? ''}'.replaceAll(',', '.')) ?? 0;
  }

  /// Lee `desglose_monedas` del resumen del turno.
  ///
  /// Formato real (verificado en producción): lista de mapas con `moneda`,
  /// `operaciones`, `importe_nativo`, `importe_base`, `efectivo_nativo` y
  /// `digital_nativo`. Si la RPC desplegada es la antigua, la clave no viene y
  /// esto devuelve vacío: el bloque por moneda simplemente no se pinta.
  List<_MonedaDesglose> _leerDesgloseMonedas() {
    final dynamic crudo = _currentSales?['desglose_monedas'];
    if (crudo is! List) return const <_MonedaDesglose>[];

    final List<_MonedaDesglose> salida = <_MonedaDesglose>[];
    for (final dynamic fila in crudo) {
      if (fila is! Map) continue;
      final String moneda =
          (fila['moneda'] ?? '').toString().trim().toUpperCase();
      if (moneda.isEmpty) continue;
      salida.add(
        _MonedaDesglose(
          moneda: moneda,
          operaciones: _num(fila['operaciones']).toInt(),
          nativo: _num(fila['importe_nativo']),
          base: _num(fila['importe_base']),
          efectivo: _num(fila['efectivo_nativo']),
          digital: _num(fila['digital_nativo']),
        ),
      );
    }
    return salida;
  }

  /// Atajos que convierten el panel en algo accionable: ver órdenes, ir al
  /// carrito o cerrar la caja sin salir de la pantalla en la que está.
  Widget _buildAccionesRapidas() {
    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              _cerrarPanel();
              Navigator.pushNamed(context, '/orders');
            },
            icon: const Icon(Icons.receipt_long_rounded, size: 15),
            label: const Text('Órdenes'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              _cerrarPanel();
              NavigationHelper.goCarrito(context);
            },
            icon: const Icon(Icons.shopping_cart_outlined, size: 15),
            label: const Text('Carrito'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              _cerrarPanel();
              Navigator.pushNamed(context, '/cierre');
            },
            icon: const Icon(Icons.point_of_sale_rounded, size: 15),
            label: const Text('Cierre'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _cerrarPanel() {
    if (!_isExpanded) return;
    // Cerrar desde los accesos rápidos (Órdenes / Carrito / Cierre) cuenta como
    // cualquier otro cierre: mismo único timer y misma retirada del importe.
    _cancelarTimerOcultarTotal();
    setState(() {
      _isExpanded = false;
      _muestraTotalEnPildora = false;
    });
    _animationController.reverse();
    _programarOcultarTotal();
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Una divisa del `desglose_monedas` del resumen del turno.
///
/// `nativo` es lo cobrado en ESA divisa (no sumable con las demás); `base` es su
/// equivalente en la moneda base. `efectivo` y `digital` son también nativos y
/// su suma da `nativo`: son los dos tramos de la barra apilada.
class _MonedaDesglose {
  const _MonedaDesglose({
    required this.moneda,
    required this.operaciones,
    required this.nativo,
    required this.base,
    required this.efectivo,
    required this.digital,
  });

  final String moneda;
  final int operaciones;
  final double nativo;
  final double base;
  final double efectivo;
  final double digital;

  /// Tasa media que aplicó el servidor al consolidar esta divisa
  /// (`importe_base / importe_nativo`). 0 si no hay importe nativo.
  ///
  /// Es la tasa real de la fila, no la del día: repartir con ella da el mismo
  /// número que haber convertido pago a pago.
  double get tasaImplicita => nativo > 0 ? base / nativo : 0;

  /// Efectivo de esta divisa expresado en **moneda base**.
  ///
  /// Permite sumar el efectivo de todas las divisas sin mezclar unidades, que
  /// es justo lo que no se puede hacer con `efectivo` (nativo). Sin
  /// `importe_nativo` no hay tasa posible y devuelve 0: mejor no sumar ese
  /// tramo que inventar una conversión.
  double get efectivoEnBase => efectivo * tasaImplicita;
}
