import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/order_service.dart';

enum PaymentMethod { efectivo, transferencia }

class CheckoutScreen extends StatefulWidget {
  final Order order;

  const CheckoutScreen({Key? key, required this.order}) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final OrderService _orderService = OrderService();
  final _formKey = GlobalKey<FormState>();
  
  // Controllers for form fields
  final _promoCodeController = TextEditingController();
  final _buyerNameController = TextEditingController();
  final _buyerPhoneController = TextEditingController();
  final _extraContactsController = TextEditingController();
  
  // State variables
  PaymentMethod? _selectedPaymentMethod;
  double _promoDiscount = 0.0;
  double _cashDiscount = 0.0;
  bool _promoApplied = false;
  bool _isProcessing = false;
  
  // Discount percentages (you can make these configurable)
  static const double cashDiscountPercentage = 0.05; // 5% discount for cash
  static const double promoDiscountPercentage = 0.10; // 10% promo discount

  @override
  void dispose() {
    _promoCodeController.dispose();
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _extraContactsController.dispose();
    super.dispose();
  }

  double get subtotal => widget.order.total;
  
  double get totalAfterPromo => subtotal - _promoDiscount;
  
  double get finalTotal => totalAfterPromo - _cashDiscount;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Finalizar Orden',
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
              _buildOrderSummary(),
              const SizedBox(height: 20),
              _buildPromoSection(),
              const SizedBox(height: 20),
              _buildPaymentMethodSection(),
              const SizedBox(height: 20),
              _buildBuyerInfoSection(),
              const SizedBox(height: 20),
              _buildExtraContactsSection(),
              const SizedBox(height: 30),
              _buildFinalTotalSection(),
              const SizedBox(height: 20),
              _buildCreateOrderButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
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
          const Text(
            'Resumen de la Orden',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.order.totalItems} producto${widget.order.totalItems == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                '\$${subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromoSection() {
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
          const Text(
            'Código de Promoción',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _promoCodeController,
                  enabled: !_promoApplied,
                  decoration: InputDecoration(
                    hintText: 'Ingresa código promocional',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _promoApplied ? _removePromo : _applyPromo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _promoApplied ? Colors.red : const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: Text(_promoApplied ? 'Quitar' : 'Aplicar'),
              ),
            ],
          ),
          if (_promoApplied) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Descuento promocional:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '-\$${_promoDiscount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
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
          const Text(
            'Método de Pago',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          RadioListTile<PaymentMethod>(
            title: const Text('Efectivo'),
            subtitle: const Text('5% de descuento adicional'),
            value: PaymentMethod.efectivo,
            groupValue: _selectedPaymentMethod,
            onChanged: (PaymentMethod? value) {
              setState(() {
                _selectedPaymentMethod = value;
                _updateCashDiscount();
              });
            },
          ),
          RadioListTile<PaymentMethod>(
            title: const Text('Transferencia'),
            subtitle: const Text('Sin descuento adicional'),
            value: PaymentMethod.transferencia,
            groupValue: _selectedPaymentMethod,
            onChanged: (PaymentMethod? value) {
              setState(() {
                _selectedPaymentMethod = value;
                _updateCashDiscount();
              });
            },
          ),
          if (_cashDiscount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Descuento por efectivo:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '-\$${_cashDiscount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBuyerInfoSection() {
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
          const Text(
            'Datos del Comprador',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _buyerNameController,
            decoration: InputDecoration(
              labelText: 'Nombre completo *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El nombre es requerido';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _buyerPhoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Teléfono *',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El teléfono es requerido';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildExtraContactsSection() {
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
          const Text(
            'Contactos Adicionales',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Opcional - Contactos extras del cliente',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _extraContactsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Ej: María - 555-1234, Juan - 555-5678',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalTotalSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90E2).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Subtotal:',
                style: TextStyle(fontSize: 14),
              ),
              Text(
                '\$${subtotal.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          if (_promoDiscount > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Descuento promocional:',
                  style: TextStyle(fontSize: 14, color: Colors.green),
                ),
                Text(
                  '-\$${_promoDiscount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14, color: Colors.green),
                ),
              ],
            ),
          ],
          if (_cashDiscount > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Descuento por efectivo:',
                  style: TextStyle(fontSize: 14, color: Colors.green),
                ),
                Text(
                  '-\$${_cashDiscount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 14, color: Colors.green),
                ),
              ],
            ),
          ],
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Final:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              Text(
                '\$${finalTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4A90E2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreateOrderButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _createOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4A90E2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isProcessing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Crear Orden',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  void _applyPromo() {
    final promoCode = _promoCodeController.text.trim();
    if (promoCode.isEmpty) {
      _showErrorMessage('Ingresa un código promocional');
      return;
    }

    // Simple promo validation (you can make this more sophisticated)
    if (promoCode.toUpperCase() == 'DESCUENTO10' || promoCode.toUpperCase() == 'PROMO10') {
      setState(() {
        _promoDiscount = totalAfterPromo * promoDiscountPercentage;
        _promoApplied = true;
        _updateCashDiscount(); // Recalculate cash discount based on new total
      });
      _showSuccessMessage('¡Código promocional aplicado!');
    } else {
      _showErrorMessage('Código promocional inválido');
    }
  }

  void _removePromo() {
    setState(() {
      _promoDiscount = 0.0;
      _promoApplied = false;
      _promoCodeController.clear();
      _updateCashDiscount(); // Recalculate cash discount
    });
  }

  void _updateCashDiscount() {
    setState(() {
      if (_selectedPaymentMethod == PaymentMethod.efectivo) {
        _cashDiscount = totalAfterPromo * cashDiscountPercentage;
      } else {
        _cashDiscount = 0.0;
      }
    });
  }

  void _createOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedPaymentMethod == null) {
      _showErrorMessage('Selecciona un método de pago');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Create order with all the collected information
      final orderData = {
        'buyerName': _buyerNameController.text.trim(),
        'buyerPhone': _buyerPhoneController.text.trim(),
        'extraContacts': _extraContactsController.text.trim(),
        'paymentMethod': _selectedPaymentMethod == PaymentMethod.efectivo ? 'efectivo' : 'transferencia',
        'promoCode': _promoApplied ? _promoCodeController.text.trim() : null,
        'promoDiscount': _promoDiscount,
        'cashDiscount': _cashDiscount,
        'finalTotal': finalTotal,
        'originalTotal': subtotal,
      };

      // Update the order with final information
      final updatedOrder = widget.order.copyWith(
        total: finalTotal,
        notas: _buildOrderNotes(orderData),
        buyerName: _buyerNameController.text.trim(),
        buyerPhone: _buyerPhoneController.text.trim(),
        extraContacts: _extraContactsController.text.trim().isNotEmpty ? _extraContactsController.text.trim() : null,
        paymentMethod: _selectedPaymentMethod == PaymentMethod.efectivo ? 'Efectivo' : 'Transferencia',
      );

      // Finalize the order
      _orderService.finalizeOrderWithDetails(updatedOrder, orderData);

      // Show success and navigate back
      _showSuccessMessage('¡Orden creada exitosamente!');
      
      // Navigate back to orders screen or home
      Navigator.pushNamedAndRemoveUntil(context, '/orders', (route) => false);

    } catch (e) {
      _showErrorMessage('Error al crear la orden: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  String _buildOrderNotes(Map<String, dynamic> orderData) {
    final notes = StringBuffer();
    notes.writeln('DATOS DEL COMPRADOR:');
    notes.writeln('Nombre: ${orderData['buyerName']}');
    notes.writeln('Teléfono: ${orderData['buyerPhone']}');
    
    if (orderData['extraContacts'] != null && orderData['extraContacts'].isNotEmpty) {
      notes.writeln('Contactos adicionales: ${orderData['extraContacts']}');
    }
    
    notes.writeln('\nDETALLES DE PAGO:');
    notes.writeln('Método: ${orderData['paymentMethod']}');
    notes.writeln('Total original: \$${orderData['originalTotal'].toStringAsFixed(2)}');
    
    if (orderData['promoDiscount'] > 0) {
      notes.writeln('Descuento promocional: -\$${orderData['promoDiscount'].toStringAsFixed(2)}');
      notes.writeln('Código usado: ${orderData['promoCode']}');
    }
    
    if (orderData['cashDiscount'] > 0) {
      notes.writeln('Descuento por efectivo: -\$${orderData['cashDiscount'].toStringAsFixed(2)}');
    }
    
    notes.writeln('Total final: \$${orderData['finalTotal'].toStringAsFixed(2)}');
    
    return notes.toString();
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
