import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

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
  double _promoDiscount = 0.0;
  bool _promoApplied = false;
  bool _isProcessing = false;
  
  // Discount percentages (you can make these configurable)
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
  
  double get finalTotal => totalAfterPromo;

  // Calculate payment breakdown from individual product payment methods
  Map<String, double> get paymentBreakdown {
    Map<String, double> breakdown = {};
    
    for (final item in widget.order.items) {
      if (item.paymentMethod != null) {
        final methodName = item.paymentMethod!.denominacion;
        final itemTotal = item.subtotal;
        breakdown[methodName] = (breakdown[methodName] ?? 0.0) + itemTotal;
      }
    }
    
    return breakdown;
  }

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
              _buildPaymentBreakdownSection(),
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

  Widget _buildPaymentBreakdownSection() {
    final breakdown = paymentBreakdown;
    
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
            'Desglose de Pagos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          if (breakdown.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Algunos productos no tienen método de pago asignado',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...breakdown.entries.map((entry) {
              final methodName = entry.key;
              final amount = entry.value;
              final icon = _getPaymentMethodIcon(methodName);
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(icon, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                          methodName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '\$${amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4A90E2),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total por métodos de pago:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  '\$${breakdown.values.fold(0.0, (sum, amount) => sum + amount).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _getPaymentMethodIcon(String methodName) {
    final lowerName = methodName.toLowerCase();
    if (lowerName.contains('efectivo') || lowerName.contains('cash')) return '💵';
    if (lowerName.contains('digital') || lowerName.contains('tarjeta') || lowerName.contains('card')) return '💳';
    if (lowerName.contains('transferencia') || lowerName.contains('transfer')) return '🏦';
    return '💰';
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
              labelText: 'Teléfono (opcional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            validator: (value) {
              // Phone is now optional, no validation required
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
    });
  }

  // Generar código de cliente basado en el nombre encriptado (máximo 20 caracteres)
  String _generateClientCode(String buyerName) {
    // Crear hash MD5 del nombre
    final bytes = utf8.encode(buyerName.toLowerCase().trim());
    final digest = md5.convert(bytes);
    
    // Tomar los primeros 12 caracteres del hash para mantener el código bajo 20 caracteres
    final clientCode = 'CLI${digest.toString().substring(0, 12).toUpperCase()}';
    
    print('🔐 Código generado para "$buyerName": $clientCode (${clientCode.length} caracteres)');
    return clientCode;
  }

  // Registrar cliente en Supabase y retornar el ID del cliente
  Future<int?> _registerClientInSupabase(String buyerName, String buyerPhone) async {
    try {
      print('🔄 Registrando cliente en Supabase...');
      print('  - Nombre: $buyerName');
      print('  - Teléfono: ${buyerPhone.isNotEmpty ? buyerPhone : "No proporcionado"}');
      
      // Generar código de cliente encriptado
      final clientCode = _generateClientCode(buyerName);
      
      final response = await Supabase.instance.client.rpc(
        'fn_insertar_cliente_con_contactos',
        params: {
          'p_codigo_cliente': clientCode, // Código generado desde nombre encriptado
          'p_contactos': null, // Sin contactos adicionales por ahora
          'p_direccion': null, // No tenemos dirección
          'p_documento_identidad': null, // No tenemos documento
          'p_email': null, // No tenemos email
          'p_fecha_nacimiento': null, // No tenemos fecha nacimiento
          'p_genero': null, // No tenemos género
          'p_limite_credito': 0, // Sin límite de crédito
          'p_nombre_completo': buyerName,
          'p_telefono': buyerPhone.isNotEmpty ? buyerPhone : null,
          'p_tipo_cliente': 1, // Tipo cliente por defecto
        },
      );
      
      print('✅ Respuesta fn_insertar_cliente_con_contactos:');
      print('$response');
      
      if (response != null && response['status'] == 'success') {
        final idCliente = response['id_cliente'] as int;
        print('✅ Cliente registrado exitosamente - ID: $idCliente');
        return idCliente; // Retornar el ID del cliente
      } else {
        print('⚠️ Advertencia al registrar cliente: ${response?['message'] ?? "Respuesta vacía"}');
        return null;
      }
      
    } catch (e) {
      print('❌ Error al registrar cliente en Supabase: $e');
      // No lanzamos excepción para no interrumpir el flujo de la venta
      return null;
    }
  }

  void _createOrder() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate that all products have payment methods assigned
    final breakdown = paymentBreakdown;
    if (breakdown.isEmpty) {
      _showErrorMessage('Todos los productos deben tener un método de pago asignado');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. Primero registrar el cliente en Supabase si tenemos datos
      final buyerName = _buyerNameController.text.trim();
      final buyerPhone = _buyerPhoneController.text.trim();
      int? idCliente;
      
      if (buyerName.isNotEmpty) {
        idCliente = await _registerClientInSupabase(buyerName, buyerPhone);
        print('📝 ID Cliente capturado: $idCliente');
      }
      
      // 2. Create order with all the collected information
      final orderData = {
        'buyerName': buyerName,
        'buyerPhone': buyerPhone,
        'extraContacts': _extraContactsController.text.trim(),
        'paymentMethod': 'Múltiples métodos', // Since we have individual payment methods per product
        'promoCode': _promoApplied ? _promoCodeController.text.trim() : null,
        'promoDiscount': _promoDiscount,
        'finalTotal': finalTotal,
        'originalTotal': subtotal,
        'idCliente': idCliente, // Agregar ID del cliente al orderData
        'paymentBreakdown': breakdown, // Add payment breakdown
      };

      // Update the order with final information
      final updatedOrder = widget.order.copyWith(
        total: finalTotal,
        notas: _buildOrderNotes(orderData),
        buyerName: _buyerNameController.text.trim(),
        buyerPhone: _buyerPhoneController.text.trim(),
        extraContacts: _extraContactsController.text.trim().isNotEmpty ? _extraContactsController.text.trim() : null,
        paymentMethod: 'Múltiples métodos',
      );

      // Finalize the order
      final result = await _orderService.finalizeOrderWithDetails(updatedOrder, orderData);

      if (result['success'] == true) {
        // Show success and navigate back
        if (result['paymentWarning'] != null) {
          _showErrorMessage('Orden creada con advertencia: ${result['paymentWarning']}');
        } else {
          _showSuccessMessage('¡Orden registrada exitosamente!');
        }
        
        // Navigate back to orders screen or home
        Navigator.pushNamedAndRemoveUntil(context, '/orders', (route) => false);
      } else {
        _showErrorMessage('Error al registrar la venta: ${result['error']}');
      }

    } catch (e) {
      _showErrorMessage('Error al crear la orden: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  String _buildOrderNotes(Map<String, dynamic> orderData) {
    final notes = <String>[];
    
    if (orderData['buyerName']?.isNotEmpty == true) {
      notes.add('Cliente: ${orderData['buyerName']}');
    }
    
    if (orderData['buyerPhone']?.isNotEmpty == true) {
      notes.add('Teléfono: ${orderData['buyerPhone']}');
    }
    
    if (orderData['extraContacts']?.isNotEmpty == true) {
      notes.add('Contactos adicionales: ${orderData['extraContacts']}');
    }
    
    if (orderData['paymentMethod'] != null) {
      notes.add('Método de pago: ${orderData['paymentMethod']}');
    }
    
    // Add payment breakdown details
    if (orderData['paymentBreakdown'] != null) {
      final breakdown = orderData['paymentBreakdown'] as Map<String, double>;
      notes.add('Desglose de pagos:');
      breakdown.forEach((method, amount) {
        notes.add('  - $method: \$${amount.toStringAsFixed(2)}');
      });
    }
    
    if (orderData['promoCode']?.isNotEmpty == true) {
      notes.add('Código promocional: ${orderData['promoCode']} (Descuento: \$${orderData['promoDiscount']?.toStringAsFixed(2) ?? '0.00'})');
    }
    
    notes.add('Total original: \$${orderData['originalTotal']?.toStringAsFixed(2) ?? '0.00'}');
    notes.add('Total final: \$${orderData['finalTotal']?.toStringAsFixed(2) ?? '0.00'}');
    
    return notes.join('\n');
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
