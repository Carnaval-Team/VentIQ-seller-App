import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/user_preferences_service.dart';
import '../services/store_config_service.dart';
import '../services/promotion_service.dart';
import '../utils/price_utils.dart';

class CheckoutWebScreen extends StatefulWidget {
  final Order order;
  final Function(String buyerName, String buyerPhone, Map<String, double> breakdown, String extraContacts, String? promoCode, double promoDiscount) onCreateOrder;
  final bool isProcessing;

  const CheckoutWebScreen({
    Key? key,
    required this.order,
    required this.onCreateOrder,
    required this.isProcessing,
  }) : super(key: key);

  @override
  State<CheckoutWebScreen> createState() => _CheckoutWebScreenState();
}

class _CheckoutWebScreenState extends State<CheckoutWebScreen> {
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  final PromotionService _promotionService = PromotionService();
  final _formKey = GlobalKey<FormState>();

  final _promoCodeController = TextEditingController();
  final _buyerNameController = TextEditingController();
  final _buyerPhoneController = TextEditingController();
  final _extraContactsController = TextEditingController();

  double _promoDiscount = 0.0;
  bool _promoApplied = false;
  bool _noSolicitarCliente = false;
  Map<int, List<Map<String, dynamic>>> _productPromotions = {};

  static const double promoDiscountPercentage = 0.10;

  @override
  void initState() {
    super.initState();
    _loadStoreConfig();
    _loadProductPromotions();
  }

  Future<void> _loadStoreConfig() async {
    try {
      final storeId = await _userPreferencesService.getIdTienda();
      if (storeId != null) {
        final config = await StoreConfigService.getStoreConfigFromCache();
        if (config != null) {
          _noSolicitarCliente = config['no_solicitar_cliente'] ?? false;
        } else {
          final noSolicitar = await StoreConfigService.getNoSolicitarCliente(storeId);
          _noSolicitarCliente = noSolicitar;
        }
        if (_noSolicitarCliente) {
          _buyerNameController.text = 'Cliente';
        }
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      _noSolicitarCliente = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadProductPromotions() async {
    try {
      final productIds = widget.order.items.map((item) => item.producto.id).toSet();
      for (final productId in productIds) {
        final promotions = await _userPreferencesService.getProductPromotions(productId);
        if (promotions != null && promotions.isNotEmpty) {
          if (mounted) {
            setState(() {
              _productPromotions[productId] = promotions;
            });
          }
        }
      }
    } catch (e) {
      print('❌ Error cargando promociones de productos: $e');
    }
  }

  @override
  void dispose() {
    _promoCodeController.dispose();
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _extraContactsController.dispose();
    super.dispose();
  }

  double get subtotal {
    double total = 0.0;
    for (final item in widget.order.items) {
      total += _calculateItemPrice(item);
    }
    return total;
  }

  double _calculateItemPrice(OrderItem item) {
    final productId = item.producto.id;
    final paymentMethodId = item.paymentMethod?.id;
    final productPromotions = _productPromotions[productId];
    if (productPromotions == null || productPromotions.isEmpty) {
      return item.subtotal;
    }
    Map<String, dynamic>? applicablePromotion;
    for (final promo in productPromotions) {
      if (_promotionService.shouldApplyPromotion(promo, paymentMethodId)) {
        applicablePromotion = promo;
        break;
      }
    }
    if (applicablePromotion == null) {
      return item.subtotal;
    }
    int tipoPago = (paymentMethodId == 999 || (paymentMethodId != null && paymentMethodId != 1)) ? 2 : 1;
    final promoBase = (applicablePromotion['precio_base'] as num?)?.toDouble();
    final precioBase = item.precioBase ?? promoBase ?? item.precioUnitario;
    final valorDescuento = applicablePromotion['valor_descuento'] as double? ?? 0.0;
    final tipoDescuento = applicablePromotion['tipo_descuento'] as int? ?? 1;
    final prices = PriceUtils.calculatePromotionPrices(precioBase, valorDescuento, tipoDescuento);
    final double precioFinal = (tipoPago == 1) ? prices['precio_oferta']! : prices['precio_venta']!;
    return precioFinal * item.cantidad;
  }

  double get totalAfterPromo => subtotal - _promoDiscount;
  double get finalTotal => totalAfterPromo;

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

  void _applyPromo() {
    final promoCode = _promoCodeController.text.trim();
    if (promoCode.isEmpty) return;
    if (promoCode.toUpperCase() == 'DESCUENTO10' || promoCode.toUpperCase() == 'PROMO10') {
      setState(() {
        _promoDiscount = PriceUtils.roundDiscountPrice(totalAfterPromo * promoDiscountPercentage);
        _promoApplied = true;
      });
    }
  }

  void _removePromo() {
    setState(() {
      _promoDiscount = 0.0;
      _promoApplied = false;
      _promoCodeController.clear();
    });
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
              _buildBuyerInfoSection(),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildPaymentBreakdownSection(),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildPromoSection(),
                  ),
                ],
              ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Resumen de la Orden',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              _buildCreateOrderButton(isCompact: true),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal (${widget.order.totalItems} productos)',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
          if (_promoDiscount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Descuento:',
                  style: TextStyle(fontSize: 14, color: Colors.green),
                ),
                Text(
                  '-\$${PriceUtils.formatDiscountPrice(_promoDiscount)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 24),
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
                '\$${PriceUtils.formatDiscountPrice(finalTotal)}',
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

  Widget _buildCreateOrderButton({bool isCompact = false}) {
    return SizedBox(
      width: isCompact ? 150 : double.infinity,
      child: ElevatedButton(
        onPressed: widget.isProcessing ? null : () {
          // Validar métodos de pago antes de continuar
          final breakdown = paymentBreakdown;
          if (breakdown.isEmpty) {
            _showErrorMessage(
              'Todos los productos deben tener un método de pago asignado',
            );
            return;
          }

          // Validar el formulario local antes de llamar al callback
          if (_formKey.currentState!.validate()) {
            widget.onCreateOrder(
              _buyerNameController.text.trim(),
              _buyerPhoneController.text.trim(),
              breakdown,
              _extraContactsController.text.trim(),
              _promoApplied ? _promoCodeController.text.trim() : null,
              _promoDiscount,
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4A90E2),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: isCompact ? 10 : 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: widget.isProcessing
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Crear Orden',
                style: TextStyle(
                  fontSize: isCompact ? 13 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _promoApplied ? _removePromo : _applyPromo,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _promoApplied ? Colors.red : const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _promoApplied ? 'Quitar' : 'Aplicar',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
                  '-\$${PriceUtils.formatDiscountPrice(_promoDiscount)}',
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
            'Desglose por Métodos de Pago',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 12),
          if (breakdown.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Sin métodos de pago asignados',
                    style: TextStyle(color: Colors.orange, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: breakdown.entries.map((entry) {
                final methodName = entry.key;
                final amount = entry.value;
                final icon = _getPaymentMethodIcon(methodName);
                
                // Determinar si es oferta o regular basado en el nombre del método
                final isOferta = methodName.toLowerCase().contains('efectivo');
                final isTransferencia = methodName.toLowerCase().contains('transferencia');
                final label = isOferta ? 'Pago oferta' : 'Pago regular';
                
                // Color del monto basado en el tipo de pago
                Color amountColor = const Color(0xFF1E293B); // Color por defecto
                if (isOferta) {
                  amountColor = Colors.green[700]!;
                } else if (isTransferencia) {
                  amountColor = Colors.blue[700]!;
                }
                
                // Limpiar el methodName si ya contiene el label para evitar repeticiones
                String cleanMethodName = methodName;
                if (cleanMethodName.startsWith('Pago regular(') || cleanMethodName.startsWith('Pago oferta(')) {
                  // Extraer solo el contenido entre paréntesis: "Pago regular(Efectivo)" -> "Efectivo"
                  final startIndex = cleanMethodName.indexOf('(');
                  final endIndex = cleanMethodName.lastIndexOf(')');
                  if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
                    cleanMethodName = cleanMethodName.substring(startIndex + 1, endIndex);
                  }
                }
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(icon, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Text(
                        '$label ($cleanMethodName)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '\$${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: amountColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
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
    if (_noSolicitarCliente) {
      return const SizedBox.shrink();
    }
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
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _buyerNameController,
                  decoration: InputDecoration(
                    labelText: 'Nombre completo *',
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
                      return 'El nombre es requerido';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: _buyerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Teléfono (opcional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ],
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
