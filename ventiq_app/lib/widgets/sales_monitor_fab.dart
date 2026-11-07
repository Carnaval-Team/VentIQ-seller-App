import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  }

  @override
  void dispose() {
    // Ningún callback debe sobrevivir al widget: si la cuenta atrás siguiera
    // viva dispararía un setState sobre un State ya desmontado.
    _cancelarTimerOcultarTotal();
    _animationController.dispose();
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
        final resumenCierreResponse = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre_v2',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );

        print('📈 Sales Monitor Response: $resumenCierreResponse');
        print('📈 Tipo de respuesta: ${resumenCierreResponse.runtimeType}');

        if (resumenCierreResponse != null) {
          Map<String, dynamic> data;

          // Manejar tanto List como Map de respuesta
          if (resumenCierreResponse is List &&
              resumenCierreResponse.isNotEmpty) {
            data = resumenCierreResponse[0] as Map<String, dynamic>;
            print(
              '📈 SalesMonitor datos extraídos de lista: ${data.keys.toList()}',
            );
          } else if (resumenCierreResponse is Map<String, dynamic>) {
            data = resumenCierreResponse;
            print(
              '📈 SalesMonitor datos recibidos como mapa: ${data.keys.toList()}',
            );
          } else {
            print('⚠️ Formato de respuesta no reconocido en SalesMonitor');
            setState(() {
              _currentSales = null;
              _isLoading = false;
            });
            return;
          }

          setState(() {
            _currentSales = data;
            _isLoading = false;
          });
        } else {
          setState(() {
            _currentSales = null;
            _isLoading = false;
          });
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
                  if (!_isExpanded && _muestraTotalEnPildora && total != null)
                    ...<Widget>[
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
    final double efectivoReal =
        (ventas['efectivo_real'] as num?)?.toDouble() ?? 0;
    final double efectivo = efectivoReal - _egresosEfectivo;
    final double transferencia = total - efectivoReal + _egresosEfectivo;
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
          _buildPaymentBreakdown(efectivo, transferencia),
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

  /// Desglose por medio de pago con barra proporcional: de un vistazo se ve si
  /// el turno está cargado a efectivo o a transferencia.
  Widget _buildPaymentBreakdown(double efectivo, double transferencia) {
    final double totalMedios = efectivo.abs() + transferencia.abs();
    final double fraccionEfectivo =
        totalMedios > 0 ? efectivo.abs() / totalMedios : 0;
    final double fraccionTransferencia =
        totalMedios > 0 ? transferencia.abs() / totalMedios : 0;

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
          const Text(
            'DESGLOSE POR PAGO',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _buildMedioPagoRow(
            'Efectivo',
            efectivo,
            fraccionEfectivo,
            VentiqHomeTheme.success,
          ),
          const SizedBox(height: 9),
          _buildMedioPagoRow(
            'Transferencia',
            transferencia,
            fraccionTransferencia,
            VentiqHomeTheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildMedioPagoRow(
    String etiqueta,
    double monto,
    double fraccion,
    Color color,
  ) {
    return Column(
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
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: VentiqHomeTheme.textPrimary,
                ),
              ),
            ),
            Text(
              '\$${PriceUtils.formatAmount(monto)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraccion.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: VentiqHomeTheme.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
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
