import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';

class AperturaScreen extends StatefulWidget {
  const AperturaScreen({Key? key}) : super(key: key);

  @override
  State<AperturaScreen> createState() => _AperturaScreenState();
}

class _AperturaScreenState extends State<AperturaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montoInicialController = TextEditingController();
  final _observacionesController = TextEditingController();
  final UserPreferencesService _userPrefs = UserPreferencesService();

  bool _isProcessing = false;
  bool _isLoadingPreviousShift = true;
  // Inventory options are now hardcoded to false
  final bool _manejaInventario = false;
  String _userName = 'Cargando...';

  // Previous shift data
  double _previousShiftSales = 0.0;
  double _previousShiftCash = 0.0;
  int _previousShiftProducts = 0;
  double _previousShiftTicketAvg = 0.0;

  @override
  void initState() {
    super.initState();
    _checkExistingShift();
  }

  Future<void> _checkExistingShift() async {
    try {
      final turnoAbierto = await TurnoService.getTurnoAbierto();

      if (turnoAbierto != null) {
        if (mounted) {
          _showExistingShiftAlert();
        }
        return;
      }

      // If no open shift, proceed with normal initialization
      _loadUserData();
      _loadPreviousShiftSummary();
    } catch (e) {
      print('Error checking existing shift: $e');
      // If error, proceed with normal initialization
      _loadUserData();
      _loadPreviousShiftSummary();
    }
  }

  void _showExistingShiftAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('Turno ya abierto'),
            content: const Text(
              'Ya existe un turno abierto para este TPV. Debe cerrar el turno actual antes de abrir uno nuevo.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                ),
                child: const Text('Volver'),
              ),
            ],
          ),
    );
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

  // Inventory loading removed since inventory management is disabled

  Future<void> _loadPreviousShiftSummary() async {
    try {
      setState(() {
        _isLoadingPreviousShift = true;
      });

      final resumenTurno = await TurnoService.getResumenTurnoKPI();

      if (resumenTurno != null) {
        print('🔍 Debug - Resumen Turno Data: $resumenTurno');
        setState(() {
          _previousShiftSales =
              (resumenTurno['ventas_totales'] ?? 0.0).toDouble();
          _previousShiftCash =
              (resumenTurno['efectivo_inicial'] ?? 0.0).toDouble();
          _previousShiftProducts =
              (resumenTurno['productos_vendidos'] ?? 0).toInt();
          _previousShiftTicketAvg =
              (resumenTurno['ticket_promedio'] ?? 0.0).toDouble();
          _isLoadingPreviousShift = false;
        });
      } else {
        setState(() {
          _isLoadingPreviousShift = false;
        });
      }
    } catch (e) {
      print('Error loading previous shift summary: $e');
      setState(() {
        _isLoadingPreviousShift = false;
      });
    }
  }

  @override
  void dispose() {
    _montoInicialController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Crear Apertura',
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
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                          Icons.lock_open,
                          color: const Color(0xFF4A90E2),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Apertura de Caja',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('Fecha:', _formatDate(DateTime.now().toLocal())),
                    _buildInfoRow('Hora:', _formatTime(DateTime.now().toLocal())),
                    _buildInfoRow('Usuario:', _userName),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              _buildPreviousShiftSummary(),

              const SizedBox(height: 20),

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
                    // Row(
                      // children: [
                      //   Icon(
                      //     Icons.checklist,
                      //     color: const Color(0xFF4A90E2),
                      //     size: 20,
                      //   ),
                      //   const SizedBox(width: 8),
                      //   const Text(
                      //     'Opciones de Apertura',
                      //     style: TextStyle(
                      //       fontSize: 16,
                      //       fontWeight: FontWeight.w600,
                      //       color: Color(0xFF1F2937),
                      //     ),
                      //   ),
                      // ],
                    //),
                    // const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: const Color(0xFF4A90E2),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Opciones de Inventario',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF4A90E2),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '1. ',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'Este turno no manejará inventario (solo ventas)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '2. ',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  'La apertura se realizará sin conteo de productos',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

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
                      'Monto Inicial en Caja',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _montoInicialController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Monto inicial (\$)',
                        prefixIcon: const Icon(Icons.attach_money),
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
                          return 'El monto inicial es requerido';
                        }
                        final monto = double.tryParse(value);
                        if (monto == null || monto < 0) {
                          return 'Ingrese un monto válido';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Inventory counting section removed since it's disabled

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
                      'Observaciones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Opcional - Notas adicionales sobre la apertura',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _observacionesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText:
                            'Ej: Apertura normal del día, billetes verificados...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
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

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _crearApertura,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
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
                            'Crear Apertura',
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

  // Inventory list method removed since inventory management is disabled

  void _crearApertura() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final montoInicial = double.parse(_montoInicialController.text);
    if (_previousShiftCash > 0) {
      final diferencia = montoInicial - _previousShiftCash;
      if (diferencia.abs() > 0) {
        final shouldContinue = await _showCashDifferenceDialog(
          montoInicial,
          _previousShiftCash,
          diferencia,
        );
        if (!shouldContinue) {
          return;
        }
      }
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final workerProfile = await _userPrefs.getWorkerProfile();
      final userData = await _userPrefs.getUserData();
      final sellerId = await _userPrefs.getIdSeller();
      final tpvId = await _userPrefs.getIdTpv();
      final userUuid = userData['userId'];

      print('🔍 Debug - Worker Profile: $workerProfile');
      print('🔍 Debug - TPV ID: $tpvId');
      print('🔍 Debug - Seller ID: $sellerId');
      print('🔍 Debug - User UUID: $userUuid');

      if (sellerId == null) {
        throw Exception('ID de vendedor no encontrado');
      }

      if (tpvId == null) {
        throw Exception('ID de TPV no encontrado');
      }

      if (userUuid == null) {
        throw Exception('UUID de usuario no encontrado');
      }

      // No product counting since inventory management is disabled
      final List<Map<String, dynamic>> productCounts = [];
      
      print('📦 Productos para apertura: $productCounts (inventario deshabilitado)');
      print('📊 Total productos: ${productCounts.length}');

      // Usar el nuevo método del TurnoService
      final result = await TurnoService.registrarAperturaTurno(
        efectivoInicial: double.parse(_montoInicialController.text),
        idTpv: tpvId,
        idVendedor: sellerId,
        usuario: userUuid,
        manejaInventario: _manejaInventario,
        productos: null, // Always null since inventory is disabled
      );

      if (mounted) {
        if (result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result['message'] ?? 'Apertura creada exitosamente',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Error desconocido'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error creando apertura: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Widget _buildPreviousShiftSummary() {
    return Container(
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
              Icon(Icons.history, color: const Color(0xFF4A90E2), size: 24),
              const SizedBox(width: 8),
              const Text(
                'Resumen Turno Anterior',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingPreviousShift)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                ),
              ),
            )
          else if (_previousShiftSales > 0 || _previousShiftCash > 0)
            Column(
              children: [
                _buildInfoRow(
                  'Ventas Totales:',
                  '\$${_previousShiftSales.toStringAsFixed(2)}',
                ),
                _buildInfoRow(
                  'Efectivo Inicial:',
                  '\$${_previousShiftCash.toStringAsFixed(2)}',
                ),
                _buildInfoRow(
                  'Productos Vendidos:',
                  _previousShiftProducts.toString(),
                ),
                if (_previousShiftTicketAvg > 0)
                  _buildInfoRow(
                    'Ticket Promedio:',
                    '\$${_previousShiftTicketAvg.toStringAsFixed(2)}',
                  ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'No hay datos del turno anterior',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<bool> _showCashDifferenceDialog(
    double montoInicial,
    double montoEsperado,
    double diferencia,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Diferencia de Efectivo',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Se detectó una diferencia entre el monto inicial y el efectivo inicial del turno anterior:',
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
                          'Efectivo Inicial:',
                          '\$${montoEsperado.toStringAsFixed(2)}',
                        ),
                        _buildDialogInfoRow(
                          'Monto Inicial:',
                          '\$${montoInicial.toStringAsFixed(2)}',
                        ),
                        const Divider(),
                        _buildDialogInfoRow(
                          'Diferencia:',
                          '${diferencia >= 0 ? '+' : ''}\$${diferencia.toStringAsFixed(2)}',
                          isHighlight: true,
                          color: diferencia >= 0 ? Colors.green : Colors.red,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '¿Desea continuar con la apertura?',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Continuar'),
                ),
              ],
            );
          },
        ) ??
        false;
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
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? (isHighlight ? Colors.black87 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
