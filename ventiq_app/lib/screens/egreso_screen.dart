import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/turno_service.dart';
import '../services/user_preferences_service.dart';
import '../services/payment_method_service.dart';
import '../services/server_time_service.dart';
import '../services/connectivity_service.dart';
import '../services/caja_disponible_service.dart';
import '../money/caja_disponible.dart';
import '../money/fondo_caja_moneda.dart';
import '../models/payment_method.dart';
import '../utils/uuid_generator.dart';
import '../utils/price_utils.dart';
import '../theme/ventiq_home_theme.dart';

class EgresoScreen extends StatefulWidget {
  const EgresoScreen({Key? key}) : super(key: key);

  @override
  State<EgresoScreen> createState() => _EgresoScreenState();
}

class _EgresoScreenState extends State<EgresoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _motivoController = TextEditingController();
  final _nombreAutorizaController = TextEditingController();
  final _nombreRecibeController = TextEditingController();
  bool _isProcessing = false;
  bool _isLoadingTurno = true;
  bool _isLoadingPaymentMethods = true;
  Map<String, dynamic>? _turnoAbierto;
  String? _errorMessage;
  List<PaymentMethod> _paymentMethods = [];
  PaymentMethod? _selectedPaymentMethod;
  Map<String, dynamic>? _defaultCashFund;
  bool _contabilizarFondoCaja = false;
  bool _isLoadingCashFund = true;

  /// Dinero que hay en la caja del turno. Null mientras se calcula o si no se
  /// pudo calcular; sin él no se deja registrar ningún egreso.
  CajaDisponible? _caja;
  bool _isLoadingCaja = true;
  String? _errorCaja;

  /// Divisas que acepta la tienda, en orden (la moneda base primero).
  ///
  /// El egreso sale del cajón en UNA divisa concreta: `montoEntrega` es su
  /// importe nativo, así que la divisa viaja con él hasta la fila de la base.
  List<String> _divisasCaja = const [PriceUtils.baseCurrency];
  String _selectedDivisa = PriceUtils.baseCurrency;

  final UserPreferencesService _userPrefs = UserPreferencesService();

  @override
  void initState() {
    super.initState();
    _checkTurnoAbierto();
    _loadPaymentMethods();
    _loadDefaultCashFund();
    _loadDivisasCaja();
  }

  @override
  void dispose() {
    _montoController.dispose();
    _motivoController.dispose();
    _nombreAutorizaController.dispose();
    _nombreRecibeController.dispose();
    super.dispose();
  }

  Future<void> _checkTurnoAbierto() async {
    try {
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();
      final hasNetwork = await ConnectivityService().performImmediateCheck();
      final useLocal = isOfflineModeEnabled || !hasNetwork;

      if (useLocal) {
        print(
          '🔌 Egreso vía datos locales '
          '(offlineMode=$isOfflineModeEnabled hasNetwork=$hasNetwork)...',
        );

        final turnoOffline = await _userPrefs.getOfflineTurno();

        setState(() {
          _isLoadingTurno = false;
          if (turnoOffline != null) {
            _turnoAbierto = turnoOffline;
            print('✅ Turno offline cargado: ID ${turnoOffline['id']}');
          } else {
            _errorMessage = 'No hay turno abierto offline para realizar egreso';
          }
        });
        if (turnoOffline != null) _cargarCaja();
        return;
      }

      print('🌐 Modo online - Verificando turno desde servidor...');
      final turno = await TurnoService.getTurnoAbierto();

      setState(() {
        _isLoadingTurno = false;
        if (turno != null) {
          _turnoAbierto = turno;
          _userPrefs.saveTurnoData(turno);
        } else {
          _errorMessage = 'No hay turno abierto para realizar egreso';
        }
      });
      if (turno != null) _cargarCaja();
    } catch (e) {
      setState(() {
        _isLoadingTurno = false;
        _errorMessage = 'Error al verificar turno: $e';
      });
    }
  }

  /// Calcula lo que hay en la caja ahora mismo. Devuelve null si no se pudo.
  Future<CajaDisponible?> _cargarCaja() async {
    final turno = _turnoAbierto;
    if (turno == null) return null;
    if (mounted) {
      setState(() {
        _isLoadingCaja = true;
        _errorCaja = null;
      });
    }
    try {
      final caja = await CajaDisponibleService.cargar(turno);
      if (mounted) {
        setState(() {
          _caja = caja;
          _isLoadingCaja = false;
        });
        _revalidarMonto();
      }
      return caja;
    } catch (e) {
      print('❌ Egreso: no se pudo calcular el dinero disponible: $e');
      if (mounted) {
        setState(() {
          _isLoadingCaja = false;
          _errorCaja = 'No se pudo calcular el dinero disponible en caja';
        });
      }
      return null;
    }
  }

  /// Por qué el egreso en la moneda elegida no puede ir al Fondo de Caja
  /// (null si puede o si no hay cuenta, caso que la pantalla ya explica).
  String? get _rechazoFondo =>
      _defaultCashFund == null
          ? null
          : FondoCajaMoneda.rechazo(_defaultCashFund, _selectedDivisa);

  /// Un medio cuenta como efectivo salvo que sea digital (igual que el cierre).
  bool get _medioEsEfectivo => !(_selectedPaymentMethod?.esDigital ?? false);

  double? _disponibleEn(String divisa) => _caja?.disponible(
    moneda: divisa,
    idMedio: _selectedPaymentMethod?.id,
    efectivo: _medioEsEfectivo,
  );

  String? _rechazoPorSaldo(CajaDisponible? caja, double monto) {
    if (caja == null) {
      return _errorCaja ?? 'Calculando el dinero disponible en caja…';
    }
    final medio = _selectedPaymentMethod;
    if (medio == null) return 'Debe seleccionar un método de pago';
    return caja.rechazo(
      monto: monto,
      moneda: _selectedDivisa,
      idMedio: medio.id,
      efectivo: _medioEsEfectivo,
      nombreMedio: medio.denominacion,
    );
  }

  /// Dinero disponible del medio elegido, una línea por moneda de la caja.
  Widget _buildDisponibleCard() {
    final medio = _selectedPaymentMethod;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Disponible en caja',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                visualDensity: VisualDensity.compact,
                onPressed: _isLoadingCaja ? null : _cargarCaja,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          Text(
            medio == null
                ? 'Seleccione un método de pago'
                : _medioEsEfectivo
                ? '${medio.displayName} · cajón de efectivo'
                : '${medio.displayName} · solo lo cobrado con este medio',
            style: const TextStyle(
              fontSize: 12,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingCaja)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_errorCaja != null)
            Text(
              '$_errorCaja. Toque actualizar para reintentar.',
              style: TextStyle(color: Colors.red[600], fontSize: 13),
            )
          else if (medio != null)
            for (final divisa in _divisasCaja)
              _buildInfoRow(
                divisa,
                '${(_disponibleEn(divisa) ?? 0).toMoneyString(2)} $divisa',
                destacar: divisa == _selectedDivisa,
              ),
        ],
      ),
    );
  }

  Future<void> _loadPaymentMethods() async {
    try {
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();
      final hasNetwork = await ConnectivityService().performImmediateCheck();
      final useLocal = isOfflineModeEnabled || !hasNetwork;

      if (useLocal) {
        print(
          '🔌 Modo offline activado - Cargando métodos de pago desde cache...',
        );

        // Obtener datos offline
        final offlineData = await _userPrefs.getOfflineData();
        final paymentMethodsData =
            offlineData?['payment_methods'] as List<dynamic>? ?? [];

        // Convertir a objetos PaymentMethod
        final todos =
            paymentMethodsData
                .map(
                  (data) =>
                      PaymentMethod.fromJson(
                        Map<String, dynamic>.from(data as Map),
                      ),
                )
                .where((m) => !m.esPagoPendiente)
                .toList();
        // Mismos medios que online (solo efectivo). Si el caché es tan viejo
        // que ninguno trae la marca, se ofrecen todos antes que ninguno.
        final efectivo = todos.where((m) => m.esEfectivo).toList();
        final paymentMethods = efectivo.isNotEmpty ? efectivo : todos;

        setState(() {
          _paymentMethods = paymentMethods;
          _isLoadingPaymentMethods = false;
          // Set default payment method (first one, usually "Efectivo")
          if (paymentMethods.isNotEmpty) {
            _selectedPaymentMethod = paymentMethods.first;
          }
        });

        print(
          '✅ Métodos de pago cargados desde cache offline: ${paymentMethods.length}',
        );
        return;
      }

      print('🌐 Modo online - Cargando métodos de pago desde servidor...');
      final paymentMethods = await PaymentMethodService.getActivePaymentMethods(
        only_efectivo: true,
      );

      setState(() {
        _paymentMethods = paymentMethods;
        _isLoadingPaymentMethods = false;
        // Set default payment method (first one, usually "Efectivo")
        if (paymentMethods.isNotEmpty) {
          _selectedPaymentMethod = paymentMethods.first;
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingPaymentMethods = false;
      });
      print('Error loading payment methods: $e');
    }
  }

  /// Carga las divisas de la caja y deja seleccionada la moneda base.
  ///
  /// [TurnoService.divisasDeCaja] ya resuelve tienda → caché → respaldo y
  /// garantiza que la moneda base vaya primero; si falla, la lista se queda en
  /// la base y la pantalla se comporta como antes de la Fase 4.
  Future<void> _loadDivisasCaja() async {
    var divisas = const [PriceUtils.baseCurrency];
    try {
      divisas = await TurnoService.divisasDeCaja();
    } catch (e) {
      print('⚠️ Egreso: no se pudieron cargar las divisas de la caja: $e');
    }
    if (!mounted) return;
    setState(() {
      _divisasCaja = divisas;
      if (!divisas.contains(_selectedDivisa)) {
        _selectedDivisa = divisas.first;
      }
    });
  }

  Future<void> _loadDefaultCashFund() async {
    try {
      final offlineData = await _userPrefs.getOfflineData();
      Map<String, dynamic>? account;
      final cached = offlineData?['default_cash_fund'];
      if (cached is Map) account = Map<String, dynamic>.from(cached);

      final isOffline = await _userPrefs.isOfflineModeEnabled();
      final hasNetwork = await ConnectivityService().performImmediateCheck();
      if (!isOffline && hasNetwork) {
        final storeId = await _userPrefs.getIdTienda();
        if (storeId != null) {
          final response =
              await Supabase.instance.client
                  .from('dep_dat_banco')
                  .select(FondoCajaMoneda.selectCuenta)
                  .eq('idtienda', storeId)
                  .eq('activo', true)
                  .eq('es_predeterminada_fondo_caja', true)
                  .maybeSingle();
          account = response;
          if (response != null) {
            await _userPrefs.mergeOfflineData({'default_cash_fund': response});
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _defaultCashFund = account;
        _isLoadingCashFund = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingCashFund = false);
      print('Error cargando cuenta predeterminada de Fondo de Caja: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VentiqHomeTheme.surface,
      appBar: AppBar(
        backgroundColor: VentiqHomeTheme.primary,
        elevation: 0,
        title: const Text(
          'Crear Egreso',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          _isLoadingTurno
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Verificando turno abierto...'),
                  ],
                ),
              )
              : _errorMessage != null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(fontSize: 16, color: Colors.red[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Volver'),
                    ),
                  ],
                ),
              )
              : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Información del egreso
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VentiqHomeTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.money_off,
                                  color: Colors.red[600],
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Registro de Egreso',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: VentiqHomeTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              'Fecha:',
                              _formatDate(DateTime.now()),
                            ),
                            _buildInfoRow('Hora:', _formatTime(DateTime.now())),
                            _buildInfoRow(
                              'Turno ID:',
                              _turnoAbierto!['id'].toString(),
                            ),
                            _buildInfoRow(
                              'Efectivo Inicial:',
                              '\$${_turnoAbierto!['efectivo_inicial']}',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // 1) Moneda y 2) medio de pago: de ahí se sabe de dónde sale
                      // el dinero y cuánto hay.
                      _buildOrigenCard(),

                      const SizedBox(height: 20),

                      _buildDisponibleCard(),

                      const SizedBox(height: 20),

                      // 3) Monto, validado mientras se escribe.
                      _buildMontoCard(),

                      const SizedBox(height: 20),
                      // Motivo del egreso
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VentiqHomeTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Motivo del Egreso',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: VentiqHomeTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _motivoController,
                              decoration: InputDecoration(
                                labelText: 'Motivo de la entrega',
                                prefixIcon: const Icon(Icons.description),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El motivo es requerido';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VentiqHomeTheme.border),
                        ),
                        child: CheckboxListTile(
                          value: _contabilizarFondoCaja,
                          onChanged:
                              _defaultCashFund != null &&
                                      !_isLoadingCashFund &&
                                      _rechazoFondo == null
                                  ? (value) => setState(
                                    () =>
                                        _contabilizarFondoCaja = value ?? false,
                                  )
                                  : null,
                          title: const Text('Contabilizar en Fondo de Caja'),
                          subtitle: Text(
                            _isLoadingCashFund
                                ? 'Verificando cuenta predeterminada...'
                                : _defaultCashFund == null
                                ? 'Configure una cuenta predeterminada de Fondo de Caja'
                                : _rechazoFondo ??
                                    'Ingresará en ${_defaultCashFund!['denominacion']} '
                                        '(${FondoCajaMoneda.codigo(_defaultCashFund)})',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Personas involucradas
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VentiqHomeTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Personas Involucradas',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: VentiqHomeTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Nombre quien autoriza
                            TextFormField(
                              controller: _nombreAutorizaController,
                              decoration: InputDecoration(
                                labelText: 'Nombre quien autoriza',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El nombre de quien autoriza es requerido';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: 12),

                            // Nombre quien recibe
                            TextFormField(
                              controller: _nombreRecibeController,
                              decoration: InputDecoration(
                                labelText: 'Nombre quien recibe',
                                prefixIcon: const Icon(Icons.person),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El nombre de quien recibe es requerido';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // Botón registrar egreso
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _registrarEgreso,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[600],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
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
                                    'Registrar Egreso',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
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

  /// Moneda (primero) y medio de pago (segundo) del egreso.
  Widget _buildOrigenCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿De dónde sale el dinero?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: VentiqHomeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '1. Moneda',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final divisa in _divisasCaja)
                ChoiceChip(
                  key: ValueKey('egreso-moneda-$divisa'),
                  label: Text(divisa),
                  selected: divisa == _selectedDivisa,
                  onSelected: (_) => _seleccionarDivisa(divisa),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '2. Medio de pago',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingPaymentMethods)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_paymentMethods.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VentiqHomeTheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'No hay métodos de pago disponibles',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            DropdownButtonFormField<PaymentMethod>(
              value: _selectedPaymentMethod,
              decoration: InputDecoration(
                labelText: 'Seleccionar método de pago',
                prefixIcon: Icon(Icons.payment, color: Colors.red[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items:
                  _paymentMethods.map((PaymentMethod method) {
                    return DropdownMenuItem<PaymentMethod>(
                      value: method,
                      child: Row(
                        children: [
                          Icon(
                            method.typeIcon,
                            size: 20,
                            color: VentiqHomeTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(method.displayName),
                        ],
                      ),
                    );
                  }).toList(),
              onChanged: (PaymentMethod? newValue) {
                setState(() => _selectedPaymentMethod = newValue);
                _revalidarMonto();
              },
              validator: (value) {
                if (value == null) return 'Debe seleccionar un método de pago';
                return null;
              },
            ),
        ],
      ),
    );
  }

  void _seleccionarDivisa(String divisa) {
    if (divisa == _selectedDivisa) return;
    setState(() {
      _selectedDivisa = divisa;
      // El fondo no convierte: solo admite la moneda de su cuenta.
      if (_rechazoFondo != null) _contabilizarFondoCaja = false;
    });
    _revalidarMonto();
  }

  /// Vuelve a evaluar el monto escrito cuando cambia la moneda o el medio.
  void _revalidarMonto() {
    if (_montoController.text.trim().isNotEmpty) {
      _formKey.currentState?.validate();
    }
  }

  /// Texto bajo el monto: lo que hay en la caja para la moneda y el medio.
  String _ayudaMonto() {
    if (_selectedPaymentMethod == null) return 'Elija primero el medio de pago';
    if (_isLoadingCaja) return 'Calculando dinero disponible…';
    final libre = _disponibleEn(_selectedDivisa);
    if (libre == null) return _errorCaja ?? 'Disponible no calculado';
    final donde = _medioEsEfectivo ? 'en efectivo' : 'en este medio';
    return 'Disponible: ${libre.toMoneyString(2)} $_selectedDivisa $donde';
  }

  /// Monto: se valida a medida que se escribe contra lo disponible.
  Widget _buildMontoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '3. Monto del Egreso',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: VentiqHomeTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _montoController,
            enabled: _selectedPaymentMethod != null,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Monto ($_selectedDivisa)',
              helperText: _ayudaMonto(),
              prefixIcon: Icon(Icons.attach_money, color: Colors.red[600]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El monto es requerido';
              }
              final monto = double.tryParse(value);
              if (monto == null || monto <= 0) {
                return 'Ingrese un monto válido mayor a 0';
              }
              return _rechazoPorSaldo(_caja, monto);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool destacar = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: VentiqHomeTheme.textSecondary,
              fontWeight: destacar ? FontWeight.w700 : FontWeight.normal,
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
                fontWeight: destacar ? FontWeight.w800 : FontWeight.w500,
                color:
                    destacar
                        ? VentiqHomeTheme.primary
                        : VentiqHomeTheme.textPrimary,
              ),
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

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }

  void _registrarEgreso() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final monto = double.parse(_montoController.text.trim());

      // La caja pudo cambiar desde que se abrió la pantalla (otro egreso, otra
      // venta): se recalcula justo antes de registrar y no se envía si no cubre.
      final caja = await _cargarCaja();
      final rechazo = _rechazoPorSaldo(caja, monto);
      if (rechazo != null) {
        _showErrorMessage(rechazo);
        _formKey.currentState?.validate();
        return;
      }

      if (_contabilizarFondoCaja && _rechazoFondo != null) {
        _showErrorMessage(_rechazoFondo!);
        return;
      }

      final motivo = _motivoController.text.trim();
      final nombreAutoriza = _nombreAutorizaController.text.trim();
      final nombreRecibe = _nombreRecibeController.text.trim();
      final turnoIdRaw = _turnoAbierto!['id'];
      final serverIdTurno =
          _turnoAbierto!['server_id_turno'] as int? ??
          (turnoIdRaw is int ? turnoIdRaw : null);
      final localTurnoId =
          _turnoAbierto!['local_id']?.toString() ??
          _turnoAbierto!['local_turno_id']?.toString();

      // Modo offline o sin red: guardar solo local (cola egresos_offline).
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();
      final hasNetwork = await ConnectivityService().performImmediateCheck();
      final forceLocalOnly = isOfflineModeEnabled || !hasNetwork;

      if (forceLocalOnly) {
        print(
          '🔌 Creando egreso offline '
          '(offlineMode=$isOfflineModeEnabled hasNetwork=$hasNetwork)...',
        );
        if (_contabilizarFondoCaja && _defaultCashFund == null) {
          throw Exception(
            'No hay cuenta predeterminada de Fondo de Caja en cache. '
            'Sincronice online o prepare el dispositivo antes de marcar '
            'Contabilizar en Fondo de Caja.',
          );
        }
        if (localTurnoId == null || localTurnoId.isEmpty) {
          throw Exception(
            'No hay turno offline abierto al que asociar el egreso',
          );
        }
        await _createOfflineEgreso(
          localTurnoId: localTurnoId,
          serverIdTurno: serverIdTurno,
          monto: monto,
          motivo: motivo,
          nombreAutoriza: nombreAutoriza,
          nombreRecibe: nombreRecibe,
          contabilizarFondoCaja: _contabilizarFondoCaja,
        );
      } else {
        print('🌐 Modo online - Registrando egreso en servidor...');
        if (serverIdTurno == null) {
          throw Exception('No hay id de turno válido para registrar el egreso');
        }
        final clientUuid = UuidGenerator.v4();
        try {
          final Map<String, dynamic> result;
          if (_contabilizarFondoCaja) {
            final storeId = await _userPrefs.getIdTienda();
            final userId = await _userPrefs.getUserId();
            if (storeId == null || _defaultCashFund == null) {
              throw Exception('No hay cuenta predeterminada de Fondo de Caja');
            }
            final response = await Supabase.instance.client.rpc(
              'fn_registrar_egreso_fondo_caja_v2',
              params: {
                'p_moneda': _selectedDivisa,
                'p_client_uuid': clientUuid,
                'p_idtienda': storeId,
                'p_id_turno': serverIdTurno,
                'p_monto_entrega': monto,
                'p_nombre_recibe': nombreRecibe,
                'p_nombre_autoriza': nombreAutoriza,
                'p_motivo_entrega': motivo,
                'p_id_medio_pago': _selectedPaymentMethod?.id,
                'p_uuid_usuario': userId,
              },
            );
            result = Map<String, dynamic>.from(response as Map);
          } else {
            result = await _registrarEgresoConClave(
              clientUuid: clientUuid,
              idTurno: serverIdTurno,
              monto: monto,
              motivo: motivo,
              nombreAutoriza: nombreAutoriza,
              nombreRecibe: nombreRecibe,
            );
          }

          if (result['success'] == true) {
            _showSuccessDialog(result);
          } else {
            _showErrorMessage(result['message'] ?? 'Error desconocido');
          }
        } catch (e) {
          if (_pareceErrorDeRed(e)) {
            print('📵 Error de red en egreso online → guardando offline');
            await _createOfflineEgreso(
              localTurnoId: localTurnoId,
              serverIdTurno: serverIdTurno,
              monto: monto,
              motivo: motivo,
              nombreAutoriza: nombreAutoriza,
              nombreRecibe: nombreRecibe,
              contabilizarFondoCaja: _contabilizarFondoCaja,
              clientUuid: clientUuid,
            );
          } else {
            rethrow;
          }
        }
      }
    } catch (e) {
      _showErrorMessage('Error al registrar el egreso: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showSuccessDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 24),
                const SizedBox(width: 8),
                const Text('Egreso Registrado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result['message'] ??
                      'El egreso ha sido registrado exitosamente.',
                ),
                const SizedBox(height: 12),
                Text('ID Egreso: ${result['egreso_id']}'),
                Text(
                  'Monto: \$${result['monto'] is num ? PriceUtils.formatAmount(result['monto'] as num) : _montoController.text}',
                ),
                Text('Motivo: ${_motivoController.text}'),
                Text('Autoriza: ${_nombreAutorizaController.text}'),
                Text('Recibe: ${_nombreRecibeController.text}'),
                _buildInfoRow('Fecha:', _formatDate(DateTime.now().toLocal())),
                _buildInfoRow('Hora:', _formatTime(DateTime.now().toLocal())),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Cerrar diálogo
                  Navigator.pop(context); // Volver a pantalla anterior
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

  /// El egreso online usa la RPC con clave. Si no está desplegada, queda el
  /// alta sin clave. Una denegación no abre esa alta.
  Future<Map<String, dynamic>> _registrarEgresoConClave({
    required String clientUuid,
    required int idTurno,
    required double monto,
    required String motivo,
    required String nombreAutoriza,
    required String nombreRecibe,
  }) async {
    final userId = await _userPrefs.getUserId();
    final params = <String, dynamic>{
      'p_client_uuid': clientUuid,
      'p_id_turno': idTurno,
      'p_monto_entrega': monto,
      'p_nombre_recibe': nombreRecibe,
      'p_nombre_autoriza': nombreAutoriza,
      'p_motivo_entrega': motivo,
      'p_id_medio_pago': _selectedPaymentMethod?.id,
      'p_uuid_usuario': userId,
    };
    dynamic response;
    try {
      response = await Supabase.instance.client.rpc(
        'fn_registrar_egreso_offline_v2',
        params: {...params, 'p_moneda': _selectedDivisa},
      );
    } catch (e) {
      if (!_egresoRpcAusente(e, 'fn_registrar_egreso_offline_v2')) rethrow;
      try {
        response = await Supabase.instance.client.rpc(
          'fn_registrar_egreso_offline',
          params: params,
        );
      } catch (e2) {
        if (!_egresoRpcAusente(e2, 'fn_registrar_egreso_offline')) rethrow;
        return TurnoService.registrarEgresoParcial(
          idTurno: idTurno,
          montoEntrega: monto,
          motivoEntrega: motivo,
          nombreAutoriza: nombreAutoriza,
          nombreRecibe: nombreRecibe,
          idMedioPago: _selectedPaymentMethod?.id,
          moneda: _selectedDivisa,
        );
      }
    }
    if (response is Map) return Map<String, dynamic>.from(response);
    return {
      'success': false,
      'message': 'Respuesta inválida del servidor',
      'egreso_id': null,
    };
  }

  bool _pareceErrorDeRed(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('failed host lookup');
  }

  bool _egresoRpcAusente(Object error, String functionName) {
    final text = error.toString().toLowerCase();
    if (text.contains('42501') ||
        text.contains('insufficient_privilege') ||
        text.contains('permission denied') ||
        text.contains('acceso denegado')) {
      return false;
    }
    final fn = functionName.toLowerCase();
    return text.contains('pgrst202') ||
        text.contains('could not find the function') ||
        text.contains('schema cache') ||
        (text.contains('does not exist') && text.contains(fn));
  }

  Future<void> _createOfflineEgreso({
    String? localTurnoId,
    int? serverIdTurno,
    required double monto,
    required String motivo,
    required String nombreAutoriza,
    required String nombreRecibe,
    required bool contabilizarFondoCaja,
    String? clientUuid,
  }) async {
    try {
      // Crear estructura de egreso offline
      final egresoData = {
        if (serverIdTurno != null) 'id_turno': serverIdTurno,
        if (localTurnoId != null) 'local_turno_id': localTurnoId,
        'monto_entrega': monto,
        // Importe NATIVO de esta divisa: el sync la necesita para no registrar
        // el egreso en la moneda base por defecto.
        'moneda': _selectedDivisa,
        'motivo_entrega': motivo,
        'nombre_autoriza': nombreAutoriza,
        'nombre_recibe': nombreRecibe,
        'id_medio_pago': _selectedPaymentMethod?.id,
        // Hora corregida contra el servidor (ver ServerTimeService) para que
        // el egreso no quede fuera del rango del turno por desfase de reloj.
        'fecha_entrega': ServerTimeService().now().toIso8601String(),
        'es_digital': _selectedPaymentMethod?.esDigital ?? false,
        'medio_pago': _selectedPaymentMethod?.denominacion ?? 'Efectivo',
        'contabilizar_fondo_caja': contabilizarFondoCaja,
        if (clientUuid != null) 'client_uuid': clientUuid,
      };

      // Cola real de sync: egresos_offline (no pending_operations type=egreso).
      await _userPrefs.saveOfflineEgreso(egresoData);

      final egresosCache = await _userPrefs.getEgresosCache();
      final updatedCache = List<Map<String, dynamic>>.from(egresosCache);
      final offlineId = egresoData['offline_id']?.toString();
      final alreadyCached = updatedCache.any(
        (item) => item['offline_id']?.toString() == offlineId,
      );
      if (!alreadyCached) {
        updatedCache.add({
          'id_egreso': 0,
          'monto_entrega': monto,
          'moneda': _selectedDivisa,
          'motivo_entrega': motivo,
          'nombre_autoriza': nombreAutoriza,
          'nombre_recibe': nombreRecibe,
          'fecha_entrega': egresoData['fecha_entrega'],
          'id_medio_pago': _selectedPaymentMethod?.id,
          'turno_estado': 1,
          'medio_pago': _selectedPaymentMethod?.denominacion ?? 'Efectivo',
          'es_digital': _selectedPaymentMethod?.esDigital ?? false,
          'offline_id': offlineId,
          'created_offline_at': egresoData['created_offline_at'],
          'pending_sync': true,
        });
        await _userPrefs.saveEgresosCache(updatedCache);
        print('💾 Egreso offline agregado al cache de egresos');
      }

      final isOfflineMode = await _userPrefs.isOfflineModeEnabled();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOfflineMode
                  ? 'Egreso guardado localmente. Se sincronizará al desactivar el modo offline.'
                  : 'Egreso guardado localmente. Se sincronizará cuando haya conexión.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        _showOfflineSuccessDialog(monto, isOfflineMode: isOfflineMode);
      }

      print('✅ Egreso offline creado exitosamente');
    } catch (e, stackTrace) {
      print('❌ Error creando egreso offline: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        _showErrorMessage('Error creando egreso offline: $e');
      }
    }
  }

  void _showOfflineSuccessDialog(double monto, {bool isOfflineMode = true}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.orange[700], size: 28),
                const SizedBox(width: 8),
                const Text(
                  'Egreso Offline Creado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOfflineMode
                      ? 'El egreso se guardó localmente y se sincronizará al desactivar el modo offline (o con sync explícito).'
                      : 'El egreso se guardó localmente y se sincronizará automáticamente cuando haya conexión.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VentiqHomeTheme.border),
                  ),
                  child: Column(
                    children: [
                      _buildDialogInfoRow(
                        'Monto:',
                        '\$${PriceUtils.formatAmount(monto)}',
                      ),
                      _buildDialogInfoRow('Motivo:', _motivoController.text),
                      _buildDialogInfoRow(
                        'Autoriza:',
                        _nombreAutorizaController.text,
                      ),
                      _buildDialogInfoRow(
                        'Recibe:',
                        _nombreRecibeController.text,
                      ),
                      _buildDialogInfoRow(
                        'Método de pago:',
                        _selectedPaymentMethod?.denominacion ?? 'N/A',
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
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
  }

  Widget _buildDialogInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: VentiqHomeTheme.textSecondary,
              fontWeight: FontWeight.normal,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
