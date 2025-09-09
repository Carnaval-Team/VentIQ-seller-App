import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/inventory_product.dart';
import '../models/expense.dart';
import '../services/order_service.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';
import '../services/inventory_service.dart';

class CierreScreen extends StatefulWidget {
  const CierreScreen({Key? key}) : super(key: key);

  @override
  State<CierreScreen> createState() => _CierreScreenState();
}

class _CierreScreenState extends State<CierreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montoFinalController = TextEditingController();
  final _observacionesController = TextEditingController();
  final OrderService _orderService = OrderService();
  final UserPreferencesService _userPrefs = UserPreferencesService();

  bool _isProcessing = false;
  bool _isLoadingData = true;
  bool _isLoadingInventory = true;
  bool _isLoadingExpenses = true;

  // Inventory data
  List<InventoryProduct> _inventoryProducts = [];
  Map<String, TextEditingController> _quantityControllers = {};

  // Expenses data
  List<Expense> _expenses = [];
  double _totalEgresos = 0.0; // Total de todos los egresos
  double _egresosEfectivo = 0.0; // Solo egresos en efectivo (no digitales)
  double _egresosTransferencias =
      0.0; // Solo egresos por transferencias/digitales

  // Data from RPC
  double _ventasTotales = 0.0;
  double _montoInicialCaja = 0.0;
  double _totalEfectivo = 0.0;
  double _totalTransferencias = 0.0;
  double _efectivoEsperado = 0.0;
  int _productosVendidos = 0;
  double _ticketPromedio = 0.0;
  double _porcentajeEfectivo = 0.0;
  double _porcentajeOtros = 0.0;

  // New fields from updated RPC
  int _operacionesTotales = 0;
  double _operacionesPorHora = 0.0;
  String _conciliacionEstado = '';
  double _efectivoRealAjustado = 0.0;
  double _diferenciaAjustada = 0.0;

  // Orders data
  int _ordenesAbiertas = 0;
  List<Order> _ordenesPendientes = [];
  String _userName = 'Cargando...';
  bool _manejaInventario =
      false; // Nueva variable para controlar si mostrar inventario

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadDailySummary();
    _calcularDatosCierre();
    _loadInventory();
    _loadExpenses();
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

  Future<void> _loadDailySummary() async {
    try {
      setState(() {
        _isLoadingData = true;
      });

      // Get current open shift first
      final turnoAbierto = await TurnoService.getTurnoAbierto();

      if (turnoAbierto == null) {
        print('⚠️ No open shift found');
        setState(() {
          _isLoadingData = false;
        });

        // Show alert and navigate back
        if (mounted) {
          _showNoOpenShiftAlert();
        }
        return;
      }

      // Use the new fn_resumen_diario_cierre function
      final userPrefs = UserPreferencesService();
      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();

      if (idTpv != null) {
        print('🧪 Loading daily summary with fn_resumen_diario_cierre - TPV: $idTpv');
        
        final resumenCierre = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );
        
        print('📈 Resumen Cierre Response: $resumenCierre');
        
        if (resumenCierre != null && resumenCierre is List && resumenCierre.isNotEmpty) {
          final data = resumenCierre[0];
          
          setState(() {
            // Map fields according to your specifications
            _montoInicialCaja = (data['efectivo_inicial'] ?? 0.0).toDouble();
            _ventasTotales = (data['ventas_totales'] ?? 0.0).toDouble();
            _productosVendidos = (data['productos_vendidos'] ?? 0).toInt();
            _ticketPromedio = (data['ticket_promedio'] ?? 0.0).toDouble();
            _operacionesTotales = (data['operaciones_totales'] ?? 0).toInt();
            _operacionesPorHora = (data['operaciones_por_hora'] ?? 0.0).toDouble();
            
            // Payment methods mapping
            _totalEfectivo = (data['efectivo_real'] ?? 0.0).toDouble();
            _totalTransferencias = _ventasTotales - _totalEfectivo;
            _porcentajeEfectivo = (data['porcentaje_efectivo'] ?? 0.0).toDouble();
            _porcentajeOtros = (data['porcentaje_otros'] ?? 0.0).toDouble();
            
            // Expected cash amounts
            _efectivoEsperado = (data['efectivo_esperado'] ?? 0.0).toDouble();
            
            // Additional fields
            _conciliacionEstado = data['conciliacion_estado'] ?? '';
            _efectivoRealAjustado = (data['efectivo_real_ajustado'] ?? 0.0).toDouble();
            _diferenciaAjustada = (data['diferencia_ajustada'] ?? 0.0).toDouble();
            
            _isLoadingData = false;
            _manejaInventario = turnoAbierto['maneja_inventario'] ?? false;
          });
          
          print('💰 Mapped Data:');
          print('  - Monto inicial: $_montoInicialCaja');
          print('  - Ventas totales: $_ventasTotales');
          print('  - Productos vendidos: $_productosVendidos');
          print('  - Ticket promedio: $_ticketPromedio');
          print('  - Operaciones totales: $_operacionesTotales');
          print('  - Operaciones por hora: $_operacionesPorHora');
          print('  - Total efectivo: $_totalEfectivo');
          print('  - Transferencias/otros: $_totalTransferencias');
          print('  - Estado conciliación: $_conciliacionEstado');
          
        } else {
          // Fallback to default values if no data
          setState(() {
            _montoInicialCaja = 500.0; // Default fallback
            _isLoadingData = false;
          });
        }
      } else {
        // Fallback if no TPV ID
        setState(() {
          _montoInicialCaja = 500.0; // Default fallback
          _isLoadingData = false;
        });
      }
    } catch (e) {
      print('Error loading daily summary: $e');
      setState(() {
        _montoInicialCaja = 500.0; // Default fallback
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
                  backgroundColor: const Color(0xFF4A90E2),
                ),
                child: const Text('Volver'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _montoFinalController.dispose();
    _observacionesController.dispose();
    // Dispose quantity controllers
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInventory() async {
    try {
      setState(() {
        _isLoadingInventory = true;
      });

      final products = await InventoryService.getInventoryProducts();

      // Initialize quantity controllers for each product
      _quantityControllers.clear();
      for (final product in products) {
        _quantityControllers[product.id.toString()] = TextEditingController();
      }

      setState(() {
        _inventoryProducts = products;
        _isLoadingInventory = false;
      });
    } catch (e) {
      print('Error loading inventory: $e');
      setState(() {
        _isLoadingInventory = false;
      });
    }
  }

  Future<void> _loadExpenses() async {
    try {
      setState(() {
        _isLoadingExpenses = true;
      });

      final expenses = await TurnoService.getEgresosEnriquecidos();

      // Calculate total expenses and separate by payment type
      double total = 0.0;
      double efectivo = 0.0;
      double transferencias = 0.0;

      for (final expense in expenses) {
        total += expense.montoEntrega;
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
        _totalEgresos = total;
        _egresosEfectivo = efectivo;
        _egresosTransferencias = transferencias;
        _isLoadingExpenses = false;
      });
    } catch (e) {
      print('Error loading expenses: $e');
      setState(() {
        _isLoadingExpenses = false;
      });
    }
  }

  void _calcularDatosCierre() {
    final orders = _orderService.orders;

    // Calcular ventas totales (órdenes completadas y con pago confirmado)
    final ordersVendidas =
        orders
            .where(
              (order) =>
                  order.status == OrderStatus.completada ||
                  order.status == OrderStatus.pagoConfirmado,
            )
            .toList();

    double ventas = 0.0;
    for (final order in ordersVendidas) {
      ventas += order.total;
    }

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

    setState(() {
      _ventasTotales = ventas;
      _ordenesAbiertas = pendientes.length;
      _ordenesPendientes = pendientes;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calcular efectivo esperado final (efectivo_esperado - egresos en efectivo)
    final montoEsperado = _efectivoEsperado - _egresosEfectivo;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Crear Cierre',
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
              // Información del cierre
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
                        Icon(Icons.lock, color: Colors.orange[700], size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          'Cierre de Caja',
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

              // Resumen de ventas
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
                      'Resumen del Turno',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_isLoadingData) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: Color(0xFF4A90E2),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Ventas y productos
                      _buildInfoRow(
                        'Monto inicial:',
                        '\$${_montoInicialCaja.toStringAsFixed(2)}',
                      ),
                      _buildInfoRow(
                        'Ventas totales:',
                        '\$${_ventasTotales.toStringAsFixed(2)}',
                      ),
                      _buildInfoRow(
                        'Productos vendidos:',
                        '$_productosVendidos unidades',
                      ),
                      _buildInfoRow(
                        'Ticket promedio:',
                        '\$${_ticketPromedio.toStringAsFixed(2)}',
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Total efectivo:',
                        '\$${_totalEfectivo.toStringAsFixed(2)} (${_porcentajeEfectivo.toStringAsFixed(1)}%)',
                      ),
                      _buildInfoRow(
                        'Transferencias/Otros:',
                        '\$${_totalTransferencias.toStringAsFixed(2)} (${_porcentajeOtros.toStringAsFixed(1)}%)',
                      ),
                      _buildInfoRow(
                        'Efectivo esperado inicial:',
                        '\$${_efectivoEsperado.toStringAsFixed(2)}',
                      ),
                      _buildInfoRow(
                        'Efectivo esperado final:',
                        '\$${montoEsperado.toStringAsFixed(2)}',
                      ),

                      // Show expenses breakdown if there are any
                      if (_totalEgresos > 0) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          'Egresos del Turno',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          'Egresos en efectivo:',
                          '-\$${_egresosEfectivo.toStringAsFixed(2)}',
                          isNegative: true,
                        ),
                        _buildInfoRow(
                          'Egresos digitales:',
                          '-\$${_egresosTransferencias.toStringAsFixed(2)}',
                          isNegative: true,
                        ),
                        _buildInfoRow(
                          'Total egresos:',
                          '-\$${_totalEgresos.toStringAsFixed(2)}',
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
                                      ? Colors.green[600]
                                      : Colors.orange[600],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Estado: $_conciliacionEstado',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color:
                                    _conciliacionEstado == 'Conciliado'
                                        ? Colors.green[700]
                                        : Colors.orange[700],
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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning,
                              color: Colors.orange[700],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$_ordenesAbiertas órdenes pendientes de cerrar',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                                fontWeight: FontWeight.w500,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.money_off, color: Colors.red[600], size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Egresos del Turno',
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
                      'Salidas de dinero registradas durante el turno',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          Text(
                            '\$${_totalEgresos.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Inventario de productos
              if (_manejaInventario) ...[
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
              ],

              const SizedBox(height: 20),

              // Monto final en caja
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
                      'Monto Final en Caja',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ingrese el monto real contado en caja',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _montoFinalController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Monto final (\$)',
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
                          return 'El monto final es requerido';
                        }
                        final monto = double.tryParse(value);
                        if (monto == null || monto < 0) {
                          return 'Ingrese un monto válido';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        setState(() {}); // Para actualizar la diferencia
                      },
                    ),

                    // Mostrar diferencia si hay monto ingresado
                    if (_montoFinalController.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDiferencia(montoEsperado),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Órdenes Pendientes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Estas órdenes se marcarán como completadas al cerrar',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),
                      ..._ordenesPendientes
                          .take(3)
                          .map((order) => _buildOrderItem(order)),
                      if (_ordenesPendientes.length > 3)
                        Text(
                          'Y ${_ordenesPendientes.length - 3} órdenes más...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
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
                      'Opcional - Notas sobre el cierre del día',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _observacionesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Ej: Cierre normal, inventario cuadrado...',
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

              // Botón crear cierre
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _crearCierre,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
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
                            'Crear Cierre',
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

  Widget _buildInfoRow(String label, String value, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isNegative ? Colors.red : Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiferencia(double montoEsperado) {
    final montoFinal = double.tryParse(_montoFinalController.text) ?? 0.0;
    final diferencia = montoFinal - montoEsperado;
    final isPositive = diferencia >= 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPositive ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPositive ? Colors.green[300]! : Colors.red[300]!,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Diferencia:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}\$${diferencia.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isPositive ? Colors.green[700] : Colors.red[700],
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
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              order.id,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '\$${order.total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A90E2),
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

  Widget _buildExpensesList() {
    if (_isLoadingExpenses) {
      return Container(
        height: 200,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF4A90E2)),
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
              Icon(Icons.money_off_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No hay egresos registrados en este turno',
                style: TextStyle(color: Colors.grey, fontSize: 14),
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
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
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
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      expense.formattedAmount,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      expense.formattedTime,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.payment, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      expense.medioPago ?? 'N/A',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            expense.medioPago == 'Efectivo'
                                ? Colors.green[700]
                                : Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Recibe: ${expense.nombreRecibe}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Autoriza: ${expense.nombreAutoriza}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
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

  void _crearCierre() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final montoFinal = double.parse(_montoFinalController.text.trim());
    final montoEsperado = _montoInicialCaja + _totalEfectivo - _egresosEfectivo;
    final diferencia = montoFinal - montoEsperado;

    // Mostrar confirmación si hay diferencia significativa
    if (diferencia.abs() > 0.01) {
      final confirmar = await _showDiferenciaDialog(diferencia);
      if (!confirmar) return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Prepare inventory products data
      final productos = <Map<String, dynamic>>[];
      for (final product in _inventoryProducts) {
        final controller = _quantityControllers[product.id.toString()];
        final cantidad = int.tryParse(controller?.text ?? '0') ?? 0;

        if (cantidad > 0) {
          productos.add({
            'id_producto': product.id,
            'id_ubicacion': product.idUbicacion,
            'cantidad': cantidad,
          });
        }
      }

      print('📦 Productos para cierre: $productos'); // Debug log
      print('📊 Total productos: ${productos.length}'); // Debug log

      // Call TurnoService to close the shift
      final success = await TurnoService.cerrarTurno(
        efectivoReal: montoFinal,
        productos: productos,
        observaciones:
            _observacionesController.text.trim().isEmpty
                ? null
                : _observacionesController.text.trim(),
      );

      if (success) {
        // Close all pending orders locally
        for (final order in _ordenesPendientes) {
          _orderService.updateOrderStatus(order.id, OrderStatus.completada);
        }

        _showSuccessDialog(montoFinal, diferencia);
      } else {
        _showErrorMessage('Error al procesar el cierre de turno');
      }
    } catch (e) {
      _showErrorMessage('Error al crear el cierre: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<bool> _showDiferenciaDialog(double diferencia) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Diferencia en Caja'),
            content: Text(
              'Hay una diferencia de \$${diferencia.toStringAsFixed(2)} entre el monto esperado y el contado.\n\n¿Desea continuar con el cierre?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  void _showSuccessDialog(double montoFinal, double diferencia) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 24),
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
                Text('Monto final: \$${montoFinal.toStringAsFixed(2)}'),
                Text('Ventas del día: \$${_ventasTotales.toStringAsFixed(2)}'),
                if (diferencia.abs() > 0.01)
                  Text('Diferencia: \$${diferencia.toStringAsFixed(2)}'),
                Text('Órdenes cerradas: ${_ordenesPendientes.length}'),
                Text('Fecha: ${_formatDate(DateTime.now())}'),
                Text('Hora: ${_formatTime(DateTime.now())}'),
              ],
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
                child: const Text('Continuar'),
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
