import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/turno_service.dart';
import '../services/user_preferences_service.dart';
import '../services/payment_method_service.dart';
import '../models/payment_method.dart';

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

  final UserPreferencesService _userPrefs = UserPreferencesService();

  @override
  void initState() {
    super.initState();
    _checkTurnoAbierto();
    _loadPaymentMethods();
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
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Cargando turno desde cache...');

        // Obtener turno offline
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
        return;
      }

      print('🌐 Modo online - Verificando turno desde servidor...');
      final turno = await TurnoService.getTurnoAbierto();

      setState(() {
        _isLoadingTurno = false;
        if (turno != null) {
          _turnoAbierto = turno;
          // Guardar turno en preferencias
          _userPrefs.saveTurnoData(turno);
        } else {
          _errorMessage = 'No hay turno abierto para realizar egreso';
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingTurno = false;
        _errorMessage = 'Error al verificar turno: $e';
      });
    }
  }

  Future<void> _loadPaymentMethods() async {
    try {
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print(
          '🔌 Modo offline activado - Cargando métodos de pago desde cache...',
        );

        // Obtener datos offline
        final offlineData = await _userPrefs.getOfflineData();
        final paymentMethodsData =
            offlineData?['payment_methods'] as List<dynamic>? ?? [];

        // Convertir a objetos PaymentMethod
        final paymentMethods =
            paymentMethodsData
                .map(
                  (data) =>
                      PaymentMethod.fromJson(data as Map<String, dynamic>),
                )
                .toList();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
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
                          border: Border.all(color: Colors.grey[300]!),
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
                                    color: Color(0xFF1F2937),
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

                      // Monto del egreso
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Monto del Egreso',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _montoController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d+\.?\d{0,2}'),
                                ),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Monto (\$)',
                                prefixIcon: Icon(
                                  Icons.attach_money,
                                  color: Colors.red[600],
                                ),
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
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Motivo del egreso
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Motivo del Egreso',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
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

                      // Medio de pago
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Medio de Pago',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 12),
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
                                  color: Colors.grey[100],
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
                                  prefixIcon: Icon(
                                    Icons.payment,
                                    color: Colors.red[600],
                                  ),
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
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 8),
                                            Text(method.displayName),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                onChanged: (PaymentMethod? newValue) {
                                  setState(() {
                                    _selectedPaymentMethod = newValue;
                                  });
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Debe seleccionar un método de pago';
                                  }
                                  return null;
                                },
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Personas involucradas
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Personas Involucradas',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
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

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1F2937),
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

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Creando egreso offline...');
        await _createOfflineEgreso(
          localTurnoId: localTurnoId,
          serverIdTurno: serverIdTurno,
          monto: monto,
          motivo: motivo,
          nombreAutoriza: nombreAutoriza,
          nombreRecibe: nombreRecibe,
        );
      } else {
        print('🌐 Modo online - Registrando egreso en servidor...');
        if (serverIdTurno == null) {
          throw Exception('No hay id de turno válido para registrar el egreso');
        }
        // Llamar a la función RPC
        final result = await TurnoService.registrarEgresoParcial(
          idTurno: serverIdTurno,
          montoEntrega: monto,
          motivoEntrega: motivo,
          nombreAutoriza: nombreAutoriza,
          nombreRecibe: nombreRecibe,
          idMedioPago: _selectedPaymentMethod?.id,
        );

        if (result['success'] == true) {
          // Mostrar confirmación de éxito
          _showSuccessDialog(result);
        } else {
          // Mostrar error del servidor
          _showErrorMessage(result['message'] ?? 'Error desconocido');
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
                  'Monto: \$${result['monto']?.toStringAsFixed(2) ?? _montoController.text}',
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
                  backgroundColor: const Color(0xFF4A90E2),
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
  }

  /// Crear egreso offline
  Future<void> _createOfflineEgreso({
    String? localTurnoId,
    int? serverIdTurno,
    required double monto,
    required String motivo,
    required String nombreAutoriza,
    required String nombreRecibe,
  }) async {
    try {
      // Crear estructura de egreso offline
      final egresoData = {
        if (serverIdTurno != null) 'id_turno': serverIdTurno,
        if (localTurnoId != null) 'local_turno_id': localTurnoId,
        'monto_entrega': monto,
        'motivo_entrega': motivo,
        'nombre_autoriza': nombreAutoriza,
        'nombre_recibe': nombreRecibe,
        'id_medio_pago': _selectedPaymentMethod?.id,
        'fecha_entrega': DateTime.now().toIso8601String(),
        'es_digital': _selectedPaymentMethod?.esDigital ?? false,
        'medio_pago': _selectedPaymentMethod?.denominacion ?? 'Efectivo',
      };

      // Guardar egreso offline
      await _userPrefs.saveOfflineEgreso(egresoData);

      final egresosCache = await _userPrefs.getEgresosCache();
      final updatedCache = List<Map<String, dynamic>>.from(egresosCache);
      final offlineId = egresoData['offline_id'];
      final alreadyCached = updatedCache.any(
        (item) => item['offline_id'] == offlineId,
      );
      if (!alreadyCached) {
        updatedCache.add({
          'id_egreso': offlineId ?? 0,
          'monto_entrega': monto,
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
        });
        await _userPrefs.saveEgresosCache(updatedCache);
        print('💾 Egreso offline agregado al cache de egresos');
      }

      // Guardar como operación pendiente para sincronización
      await _userPrefs.savePendingOperation({
        'type': 'egreso',
        'data': egresoData,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Egreso creado offline. Se sincronizará cuando tengas conexión.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );

        // Mostrar diálogo de éxito offline
        _showOfflineSuccessDialog(monto);
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

  void _showOfflineSuccessDialog(double monto) {
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
                const Text(
                  'El egreso se ha guardado localmente y se sincronizará automáticamente cuando tengas conexión a internet.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      _buildDialogInfoRow(
                        'Monto:',
                        '\$${monto.toStringAsFixed(2)}',
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
                  Navigator.pop(context); // Cerrar diálogo
                  Navigator.pop(context); // Volver a pantalla anterior
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
              color: Colors.grey[700],
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
