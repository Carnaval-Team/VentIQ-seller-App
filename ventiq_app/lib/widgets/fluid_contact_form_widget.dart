import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/order.dart';

class FluidContactFormWidget extends StatefulWidget {
  final List<OrderItem> orderItems;
  final Map<String, dynamic> paymentData;
  final Function(Map<String, dynamic>) onCompleted;

  const FluidContactFormWidget({
    Key? key,
    required this.orderItems,
    required this.paymentData,
    required this.onCompleted,
  }) : super(key: key);

  @override
  State<FluidContactFormWidget> createState() => _FluidContactFormWidgetState();
}

class _FluidContactFormWidgetState extends State<FluidContactFormWidget> {
  final _formKey = GlobalKey<FormState>();
  
  // Controladores
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  // Estados
  bool _isRequired = true;
  bool _saveCustomer = false;
  String _orderType = 'delivery'; // delivery, pickup, dine_in

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _processOrder() {
    if (_isRequired && !_formKey.currentState!.validate()) {
      return;
    }

    final contactData = {
      'customerName': _nameController.text.trim(),
      'customerPhone': _phoneController.text.trim(),
      'customerEmail': _emailController.text.trim(),
      'customerAddress': _addressController.text.trim(),
      'orderNotes': _notesController.text.trim(),
      'orderType': _orderType,
      'saveCustomer': _saveCustomer,
      'isRequired': _isRequired,
    };

    widget.onCompleted(contactData);
  }

  void _toggleRequired() {
    setState(() {
      _isRequired = !_isRequired;
    });
  }

  void _clearForm() {
    _nameController.clear();
    _phoneController.clear();
    _emailController.clear();
    _addressController.clear();
    _notesController.clear();
    setState(() {
      _saveCustomer = false;
      _orderType = 'delivery';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderSummaryCard(),
            const SizedBox(height: 24),
            _buildOrderTypeSelector(),
            const SizedBox(height: 24),
            _buildContactFormCard(),
            const SizedBox(height: 24),
            _buildAdditionalOptionsCard(),
            const SizedBox(height: 32),
            _buildProcessOrderButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    final totalAmount = widget.orderItems.fold(0.0, (sum, item) => sum + item.subtotal);
    final paymentMethods = widget.paymentData['methods'] as List<dynamic>? ?? [];

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
                Icon(Icons.receipt_long, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Resumen Final',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Productos
            Text(
              'Productos (${widget.orderItems.length}):',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            ...widget.orderItems.take(3).map((item) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                '• ${item.producto.denominacion} x${item.cantidad.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            )),
            if (widget.orderItems.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '... y ${widget.orderItems.length - 3} más',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ),
            
            const SizedBox(height: 8),
            
            // Métodos de pago
            Text(
              'Métodos de pago (${paymentMethods.length}):',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            ...paymentMethods.map((payment) {
              final method = payment['method'];
              final amount = payment['amount'];
              return Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Text(
                  '• ${method.denominacion}: \$${amount.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              );
            }),
            
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '\$${totalAmount.toStringAsFixed(2)}',
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

  Widget _buildOrderTypeSelector() {
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
                Icon(Icons.delivery_dining, color: Colors.orange.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Tipo de Orden',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                Expanded(
                  child: _buildOrderTypeOption(
                    'delivery',
                    Icons.delivery_dining,
                    'Entrega a domicilio',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildOrderTypeOption(
                    'pickup',
                    Icons.store,
                    'Recoger en tienda',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildOrderTypeOption(
                    'dine_in',
                    Icons.restaurant,
                    'Consumir en local',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTypeOption(String type, IconData icon, String label) {
    final isSelected = _orderType == type;
    
    return InkWell(
      onTap: () => setState(() => _orderType = type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
          border: Border.all(
            color: isSelected ? Colors.purple : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.purple : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.purple : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactFormCard() {
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
                Icon(Icons.person, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Datos del Cliente',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      _isRequired ? 'Requerido' : 'Opcional',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isRequired ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Switch(
                      value: _isRequired,
                      onChanged: (_) => _toggleRequired(),
                      activeColor: Colors.red,
                      inactiveThumbColor: Colors.green,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Nombre
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nombre completo${_isRequired ? ' *' : ''}',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              validator: _isRequired ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El nombre es requerido';
                }
                return null;
              } : null,
            ),
            const SizedBox(height: 16),
            
            // Teléfono
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: InputDecoration(
                labelText: 'Teléfono${_isRequired ? ' *' : ''}',
                prefixIcon: const Icon(Icons.phone_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: '1234567890',
              ),
              validator: _isRequired ? (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El teléfono es requerido';
                }
                if (value.length < 10) {
                  return 'El teléfono debe tener 10 dígitos';
                }
                return null;
              } : null,
            ),
            const SizedBox(height: 16),
            
            // Email
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email (opcional)',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: 'cliente@ejemplo.com',
              ),
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                    return 'Email inválido';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Dirección (solo si es delivery)
            if (_orderType == 'delivery') ...[
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Dirección de entrega${_isRequired ? ' *' : ''}',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: 'Calle, número, colonia, referencias...',
                ),
                validator: _isRequired && _orderType == 'delivery' ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'La dirección es requerida para entregas';
                  }
                  return null;
                } : null,
              ),
              const SizedBox(height: 16),
            ],
            
            // Notas adicionales
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notas adicionales (opcional)',
                prefixIcon: const Icon(Icons.note_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: 'Instrucciones especiales, alergias, etc...',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdditionalOptionsCard() {
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
                Icon(Icons.settings, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Opciones Adicionales',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            CheckboxListTile(
              title: const Text('Guardar datos del cliente'),
              subtitle: const Text('Para futuras órdenes más rápidas'),
              value: _saveCustomer,
              onChanged: (value) => setState(() => _saveCustomer = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearForm,
                    icon: const Icon(Icons.clear),
                    label: const Text('Limpiar formulario'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessOrderButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _processOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_cart_checkout),
            const SizedBox(width: 8),
            Text(
              'Procesar Orden - \$${widget.orderItems.fold(0.0, (sum, item) => sum + item.subtotal).toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
