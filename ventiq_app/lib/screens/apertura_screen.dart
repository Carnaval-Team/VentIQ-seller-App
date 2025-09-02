import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_product.dart';
import '../services/inventory_service.dart';
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
  bool _isLoadingInventory = true;
  bool _isLoadingPreviousShift = true;
  String _userName = 'Cargando...';
  List<InventoryProduct> _inventoryProducts = [];
  Map<String, TextEditingController> _quantityControllers = {};

  // Previous shift data
  double _previousShiftSales = 0.0;
  double _previousShiftCash = 0.0;
  double _expectedCashFromPrevious = 0.0;
  int _previousShiftProducts = 0;
  double _previousShiftTicketAvg = 0.0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadInventoryProducts();
    _loadPreviousShiftSummary();
  }

  @override
  void dispose() {
    _montoInicialController.dispose();
    _observacionesController.dispose();
    // Dispose quantity controllers
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
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

  Future<void> _loadInventoryProducts() async {
    try {
      setState(() {
        _isLoadingInventory = true;
      });

      final products = await InventoryService.getInventoryProducts(
        limite: 100, // Get more products for opening inventory
      );

      setState(() {
        _inventoryProducts = products;
        _isLoadingInventory = false;

        // Initialize quantity controllers
        _quantityControllers.clear();
        for (var product in products) {
          _quantityControllers[product.id.toString()] = TextEditingController();
        }
      });
    } catch (e) {
      print('Error loading inventory: $e');
      setState(() {
        _isLoadingInventory = false;
      });
    }
  }

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
              (resumenTurno['efectivo_real'] ?? 0.0).toDouble();
          _expectedCashFromPrevious =
              (resumenTurno['efectivo_esperado'] ?? 0.0).toDouble();
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
              // Información de apertura
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
                    _buildInfoRow('Fecha:', _formatDate(DateTime.now())),
                    _buildInfoRow('Hora:', _formatTime(DateTime.now())),
                    _buildInfoRow('Usuario:', _userName),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Previous shift summary
              _buildPreviousShiftSummary(),

              const SizedBox(height: 20),

              // Monto inicial
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

              // Inventario de productos
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
                          Icons.inventory_2,
                          color: const Color(0xFF4A90E2),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Conteo Físico de Inventario',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ingrese la cantidad física contada para cada producto',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    _buildInventoryList(),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Observaciones
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

              // Botón crear apertura
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
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildInventoryList() {
    if (_isLoadingInventory) {
      return Container(
        height: 200,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF4A90E2)),
              SizedBox(height: 16),
              Text('Cargando inventario...'),
            ],
          ),
        ),
      );
    }

    if (_inventoryProducts.isEmpty) {
      return Container(
        height: 200,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No hay productos en inventario',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 300,
      child: ListView.builder(
        itemCount: _inventoryProducts.length,
        itemBuilder: (context, index) {
          final product = _inventoryProducts[index];
          final controller = _quantityControllers[product.id.toString()]!;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                // Product info with current stock
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.nombreProducto,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${product.variante}: ${product.opcionVariante}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Text(
                              'Stock: ${product.stockDisponible.toInt()}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4A90E2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${product.ubicacion}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Quantity input (restored to original size)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Conteo Físico',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: '0',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _crearApertura() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check for cash difference and show confirmation dialog
    final montoInicial = double.parse(_montoInicialController.text);
    if (_expectedCashFromPrevious > 0) {
      final diferencia = montoInicial - _expectedCashFromPrevious;
      if (diferencia.abs() > 0) {
        final shouldContinue = await _showCashDifferenceDialog(
          montoInicial,
          _expectedCashFromPrevious,
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
      // Get user data
      final workerProfile = await _userPrefs.getWorkerProfile();
      final userData = await _userPrefs.getUserData();
      final sellerId = await _userPrefs.getIdSeller();
      final tpvId = await _userPrefs.getIdTpv() ?? 1;
      // Use seller ID from app_dat_vendedor
      final userUuid = userData['userId']; // Get UUID from stored user data
      // final tpvId =
      //     1; // Use TPV ID from app_dat_vendedor as indicated in debug output

      print('🔍 Debug - Worker Profile: $workerProfile');
      print('🔍 Debug - TPV ID: $tpvId');
      print('🔍 Debug - Seller ID: $sellerId');
      print('🔍 Debug - User UUID: $userUuid');

      // Validate required fields
      if (sellerId == null) {
        throw Exception(
          'ID de vendedor no encontrado en el perfil del trabajador',
        );
      }
      if (userUuid == null) {
        throw Exception('UUID de usuario no encontrado');
      }

      // Prepare product counts
      List<Map<String, dynamic>> productCounts = [];
      for (var product in _inventoryProducts) {
        final controller = _quantityControllers[product.id.toString()]!;
        final countText = controller.text.trim();

        if (countText.isNotEmpty) {
          final count = int.tryParse(countText) ?? 0;
          productCounts.add({
            'id_producto': product.id,
            'cantidad_fisica': count,
          });
        }
      }

      // Call Supabase RPC
      final supabase = Supabase.instance.client;
      await supabase.rpc(
        'fn_abrir_turno_tpv',
        params: {
          'p_efectivo_inicial': double.parse(_montoInicialController.text),
          'p_id_tpv': tpvId, // Use TPV ID from app_dat_vendedor
          'p_id_vendedor': sellerId,
          'p_productos': productCounts,
          'p_usuario': userUuid,
        },
      );

      // Success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Apertura creada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back or to main screen
        Navigator.of(context).pop(true);
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
                  'Efectivo Final:',
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
                    'Se detectó una diferencia entre el monto inicial y el efectivo esperado del turno anterior:',
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
                          'Efectivo Esperado:',
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
