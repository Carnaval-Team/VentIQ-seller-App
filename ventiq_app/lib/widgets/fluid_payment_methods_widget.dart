import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/order.dart';
import '../models/payment_method.dart';
import '../services/user_preferences_service.dart';
import '../services/payment_method_service.dart';
import '../utils/app_snackbar.dart';

class FluidPaymentMethodsWidget extends StatefulWidget {
  final List<OrderItem> orderItems;
  final Function(Map<String, dynamic>) onCompleted;

  const FluidPaymentMethodsWidget({
    Key? key,
    required this.orderItems,
    required this.onCompleted,
  }) : super(key: key);

  @override
  State<FluidPaymentMethodsWidget> createState() => _FluidPaymentMethodsWidgetState();
}

class _FluidPaymentMethodsWidgetState extends State<FluidPaymentMethodsWidget> {
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  // Estados de carga
  bool _isLoadingPaymentMethods = true;

  // Datos de métodos de pago
  List<PaymentMethod> _availablePaymentMethods = [];
  List<Map<String, dynamic>> _selectedPaymentMethods = [];
  
  // Cálculos
  double _totalAmount = 0.0;
  double _remainingAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _calculateTotalAmount();
    _loadPaymentMethods();
  }

  void _calculateTotalAmount() {
    _totalAmount = widget.orderItems.fold(0.0, (sum, item) => sum + item.subtotal);
    _remainingAmount = _totalAmount;
  }

  Future<void> _loadPaymentMethods() async {
    setState(() {
      _isLoadingPaymentMethods = true;
    });

    try {
      print('💳 Cargando métodos de pago...');
      
      // Verificar si está en modo offline
      final isOfflineMode = await _userPreferencesService.isOfflineModeEnabled();
      
      List<PaymentMethod> paymentMethods;
      
      if (isOfflineMode) {
        // Cargar desde cache offline
        final offlineData = await _userPreferencesService.getPaymentMethodsOffline();
        paymentMethods = offlineData.map((data) => PaymentMethod.fromJson(data)).toList();
        print('🔌 Métodos de pago cargados desde cache offline: ${paymentMethods.length}');
      } else {
        // Cargar desde servidor
        paymentMethods = await PaymentMethodService.getActivePaymentMethods();
        print('🌐 Métodos de pago cargados desde servidor: ${paymentMethods.length}');
      }

      setState(() {
        _availablePaymentMethods = paymentMethods;
      });
    } catch (e) {
      print('❌ Error cargando métodos de pago: $e');
      
      // Métodos de pago por defecto en caso de error
      setState(() {
        _availablePaymentMethods = [
          PaymentMethod(
            id: 1,
            denominacion: 'Efectivo',
            descripcion: 'Pago en efectivo',
            esDigital: false,
            esEfectivo: true,
            esActivo: true,
          ),
          PaymentMethod(
            id: 2,
            denominacion: 'Transferencia',
            descripcion: 'Transferencia bancaria',
            esDigital: true,
            esEfectivo: false,
            esActivo: true,
          ),
        ];
      });
    } finally {
      setState(() {
        _isLoadingPaymentMethods = false;
      });
    }
  }

  void _addPaymentMethod(PaymentMethod method) {
    if (_remainingAmount <= 0) {
      AppSnackBar.showPersistent(
        context,
        message: 'El total ya está cubierto',
        backgroundColor: Colors.orange,
      );
      return;
    }

    setState(() {
      _selectedPaymentMethods.add({
        'method': method,
        'amount': _remainingAmount,
        'controller': TextEditingController(text: _remainingAmount.toStringAsFixed(2)),
      });
    });
    
    _updateRemainingAmount();
  }

  void _removePaymentMethod(int index) {
    setState(() {
      final paymentData = _selectedPaymentMethods[index];
      (paymentData['controller'] as TextEditingController).dispose();
      _selectedPaymentMethods.removeAt(index);
    });
    
    _updateRemainingAmount();
  }

  void _updatePaymentAmount(int index, String value) {
    final amount = double.tryParse(value) ?? 0.0;
    
    setState(() {
      _selectedPaymentMethods[index]['amount'] = amount;
    });
    
    _updateRemainingAmount();
  }

  void _updateRemainingAmount() {
    final totalPaid = _selectedPaymentMethods.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));
    
    setState(() {
      _remainingAmount = _totalAmount - totalPaid;
    });
  }

  void _distributeEqually() {
    if (_selectedPaymentMethods.isEmpty) return;
    
    final amountPerMethod = _totalAmount / _selectedPaymentMethods.length;
    
    setState(() {
      for (int i = 0; i < _selectedPaymentMethods.length; i++) {
        _selectedPaymentMethods[i]['amount'] = amountPerMethod;
        (_selectedPaymentMethods[i]['controller'] as TextEditingController).text = amountPerMethod.toStringAsFixed(2);
      }
    });
    
    _updateRemainingAmount();
  }

  void _payRemainingWithCash() {
    if (_remainingAmount <= 0) return;
    
    final cashMethod = _availablePaymentMethods.firstWhere(
      (method) => method.denominacion.toLowerCase().contains('efectivo'),
      orElse: () => _availablePaymentMethods.first,
    );
    
    setState(() {
      _selectedPaymentMethods.add({
        'method': cashMethod,
        'amount': _remainingAmount,
        'controller': TextEditingController(text: _remainingAmount.toStringAsFixed(2)),
      });
    });
    
    _updateRemainingAmount();
  }

  void _continueToContact() {
    if (_remainingAmount > 0.01) { // Tolerancia de 1 centavo
      AppSnackBar.showPersistent(
        context,
        message: 'Falta cubrir \$${_remainingAmount.toStringAsFixed(2)}',
        backgroundColor: Colors.orange,
      );
      return;
    }

    if (_selectedPaymentMethods.isEmpty) {
      AppSnackBar.showPersistent(
        context,
        message: 'Debes seleccionar al menos un método de pago',
        backgroundColor: Colors.orange,
      );
      return;
    }

    // Preparar datos de pago
    final paymentData = {
      'methods': _selectedPaymentMethods.map((payment) => {
        'method': payment['method'],
        'amount': payment['amount'],
      }).toList(),
      'totalAmount': _totalAmount,
      'totalPaid': _totalAmount - _remainingAmount,
      'remainingAmount': _remainingAmount,
    };

    widget.onCompleted(paymentData);
  }

  @override
  void dispose() {
    // Limpiar controladores
    for (final payment in _selectedPaymentMethods) {
      (payment['controller'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPaymentMethods) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 16),
            Text('Cargando métodos de pago...'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOrderSummary(),
          const SizedBox(height: 24),
          _buildPaymentSummary(),
          const SizedBox(height: 24),
          _buildAvailablePaymentMethods(),
          const SizedBox(height: 24),
          _buildSelectedPaymentMethods(),
          const SizedBox(height: 24),
          _buildQuickActions(),
          const SizedBox(height: 32),
          _buildContinueButton(),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Resumen de la Orden',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            ...widget.orderItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.producto.denominacion,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (item.variante != null)
                          Text(
                            item.variante!.nombre,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${item.cantidad.toStringAsFixed(0)} x \$${item.precioUnitario.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '\$${item.subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            )),
            
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total a Pagar:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '\$${_totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummary() {
    final totalPaid = _totalAmount - _remainingAmount;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Estado del Pago',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total a pagar:'),
                Text(
                  '\$${_totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pagado:'),
                Text(
                  '\$${totalPaid.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: totalPaid > 0 ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Restante:'),
                Text(
                  '\$${_remainingAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _remainingAmount > 0 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
            
            if (_remainingAmount <= 0.01 && _remainingAmount >= -0.01) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Pago completo',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvailablePaymentMethods() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: Colors.purple.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Métodos de Pago Disponibles',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availablePaymentMethods.map((method) {
                return ActionChip(
                  label: Text(method.denominacion),
                  avatar: Icon(
                    _getPaymentMethodIcon(method.denominacion),
                    size: 18,
                  ),
                  onPressed: () => _addPaymentMethod(method),
                  backgroundColor: Colors.purple.withOpacity(0.1),
                  side: BorderSide(color: Colors.purple.withOpacity(0.3)),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPaymentMethods() {
    if (_selectedPaymentMethods.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                Icons.payment_outlined,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 8),
              Text(
                'No hay métodos de pago seleccionados',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Selecciona un método de pago para continuar',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Métodos de Pago Seleccionados',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            ..._selectedPaymentMethods.asMap().entries.map((entry) {
              final index = entry.key;
              final payment = entry.value;
              final method = payment['method'] as PaymentMethod;
              final controller = payment['controller'] as TextEditingController;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(_getPaymentMethodIcon(method.denominacion)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            method.denominacion,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              controller: controller,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              decoration: const InputDecoration(
                                prefixText: '\$',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                isDense: true,
                              ),
                              onChanged: (value) => _updatePaymentAmount(index, value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _removePaymentMethod(index),
                      icon: const Icon(Icons.delete, color: Colors.red),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    if (_selectedPaymentMethods.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, color: Colors.orange.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Acciones Rápidas',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_selectedPaymentMethods.length > 1)
                  ActionChip(
                    label: const Text('Distribuir Igualmente'),
                    avatar: const Icon(Icons.balance, size: 18),
                    onPressed: _distributeEqually,
                    backgroundColor: Colors.blue.withOpacity(0.1),
                  ),
                if (_remainingAmount > 0)
                  ActionChip(
                    label: Text('Pagar resto en efectivo (\$${_remainingAmount.toStringAsFixed(2)})'),
                    avatar: const Icon(Icons.money, size: 18),
                    onPressed: _payRemainingWithCash,
                    backgroundColor: Colors.green.withOpacity(0.1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    final canContinue = _remainingAmount <= 0.01 && _selectedPaymentMethods.isNotEmpty;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canContinue ? _continueToContact : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          disabledBackgroundColor: Colors.grey.shade300,
        ),
        child: Text(
          canContinue 
              ? 'Continuar a Datos del Cliente'
              : _selectedPaymentMethods.isEmpty
                  ? 'Selecciona métodos de pago'
                  : 'Completa el pago (\$${_remainingAmount.toStringAsFixed(2)} restante)',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  IconData _getPaymentMethodIcon(String methodName) {
    final name = methodName.toLowerCase();
    if (name.contains('efectivo') || name.contains('cash')) {
      return Icons.money;
    } else if (name.contains('transferencia') || name.contains('transfer')) {
      return Icons.account_balance;
    } else if (name.contains('tarjeta') || name.contains('card')) {
      return Icons.credit_card;
    } else if (name.contains('digital') || name.contains('app')) {
      return Icons.smartphone;
    } else {
      return Icons.payment;
    }
  }
}
