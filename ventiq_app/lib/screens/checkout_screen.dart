import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/user_preferences_service.dart';
import '../services/store_config_service.dart';
import '../services/promotion_service.dart';
import '../utils/price_utils.dart';
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
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final PromotionService _promotionService = PromotionService();
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
  bool _configLoading = true;
  bool _noSolicitarCliente = false; // Valor por defecto mientras se carga
  Map<int, List<Map<String, dynamic>>> _productPromotions =
      {}; // productId -> promotions

  // Discount percentages (you can make these configurable)
  static const double promoDiscountPercentage = 0.10; // 10% promo discount

  // Calculate and round promo discount
  double get roundedPromoDiscount =>
      PriceUtils.roundDiscountPrice(_promoDiscount);

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
        // Primero intentar obtener del cache (debe estar disponible desde login)
        final config = await StoreConfigService.getStoreConfigFromCache();

        if (config != null) {
          // Usar configuración del cache
          _noSolicitarCliente = config['no_solicitar_cliente'] ?? false;
          print(
            '✅ Configuración cargada desde cache - No solicitar cliente: $_noSolicitarCliente',
          );
        } else {
          // Fallback: cargar desde Supabase si no está en cache
          print(
            '⚠️ Configuración no encontrada en cache, cargando desde Supabase...',
          );
          final noSolicitar = await StoreConfigService.getNoSolicitarCliente(
            storeId,
          );
          _noSolicitarCliente = noSolicitar;
          print(
            '✅ Configuración cargada desde Supabase - No solicitar cliente: $_noSolicitarCliente',
          );
        }

        // Si no se solicita cliente, establecer nombre automáticamente
        if (_noSolicitarCliente) {
          _buyerNameController.text = 'Cliente';
        }

        // Notificar al widget que se actualizó la configuración
        if (mounted) {
          setState(() {
            _configLoading = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error cargando configuración: $e');
      // Usar valor por defecto en caso de error
      _noSolicitarCliente = false;
      if (mounted) {
        setState(() {
          _configLoading = false;
        });
      }
    }
  }

  /// Cargar promociones de productos desde preferencias
  Future<void> _loadProductPromotions() async {
    try {
      // Obtener IDs únicos de los productos en la orden
      final productIds =
          widget.order.items.map((item) => item.producto.id).toSet();

      print('🎯 Cargando promociones para ${productIds.length} productos');

      for (final productId in productIds) {
        final promotions = await _userPreferencesService.getProductPromotions(
          productId,
        );

        if (promotions != null && promotions.isNotEmpty) {
          if (mounted) {
            setState(() {
              _productPromotions[productId] = promotions;
            });
          }
          print(
            '  ✅ Producto $productId: ${promotions.length} promocion(es) cargada(s)',
          );
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

  /// Calcula el subtotal de la orden aplicando promociones según método de pago
  /// Las promociones se aplican solo si coincide el método de pago requerido
  double get subtotal {
    double total = 0.0;

    for (final item in widget.order.items) {
      total += _calculateItemPrice(item);
    }

    return total;
  }

  ///Calcula el precio de un item aplicando promoción si corresponde según método de pago
  double _calculateItemPrice(OrderItem item) {
    final productId = item.producto.id;
    final paymentMethodId = item.paymentMethod?.id;

    // Si no hay promociones para este producto, usar precio sin descuento
    final productPromotions = _productPromotions[productId];
    if (productPromotions == null || productPromotions.isEmpty) {
      return item.subtotal;
    }

    // Buscar promoción aplicable según método de pago
    Map<String, dynamic>? applicablePromotion;

    for (final promo in productPromotions) {
      // Nota: shouldApplyPromotion maneja internamente la conversión de 999 a 4
      if (_promotionService.shouldApplyPromotion(promo, paymentMethodId)) {
        applicablePromotion = promo;
        break; // Tomar primera promoción aplicable
      }
    }

    // Definir tipo de pago explícitamente (Lógica espejo de OrderService)
    // ID 1 -> Tipo 1 (Efectivo Oferta)
    // ID 999 -> Tipo 2 (Efectivo Regular)
    // Otro -> Tipo 2 (Regular)
    int tipoPago = 1;
    if (paymentMethodId == 999 ||
        (paymentMethodId != null && paymentMethodId != 1)) {
      tipoPago = 2; // Pago Regular o Tarjeta/Otros
    }

    // Si no hay promoción aplicable, es un caso de precio base
    // Pero debemos asegurar que si es "Pago Regular" (999), se mantenga esa intención
    if (applicablePromotion == null) {
      return item.subtotal;
    }

    // Aplicar promoción
    final promoBase = (applicablePromotion['precio_base'] as num?)?.toDouble();
    final precioBase = item.precioBase ?? promoBase ?? item.precioUnitario;
    final valorDescuento =
        applicablePromotion['valor_descuento'] as double? ?? 0.0;
    final esRecargo = applicablePromotion['es_recargo'] as bool? ?? false;
    final tipoDescuento = applicablePromotion['tipo_descuento'] as int? ?? 1;

    final prices = PriceUtils.calculatePromotionPrices(
      precioBase,
      valorDescuento,
      tipoDescuento,
    );

    // FIX: Seleccionar precio final basado explícitamente en el TIPO DE PAGO
    // Tipo 1 -> Aplica Oferta (Descuento o Precio Base según sea el recargo)
    // Tipo 2 -> Aplica Precio Venta (Base o Recargo)
    final double precioFinal;

    if (tipoPago == 1) {
      // Tipo 1: Efectivo Oferta -> Usar precio_oferta (siempre el más favorable/base para efectivo)
      precioFinal = prices['precio_oferta']!;
    } else {
      // Tipo 2: Regular (Tarjeta u Otros) -> Usar precio_venta (Standard o Recargado)
      precioFinal = prices['precio_venta']!;
    }

    final itemTotal = precioFinal * item.cantidad;

    print('  💰 ${item.producto.denominacion}:');
    print('     - Método Pago ID: $paymentMethodId -> Tipo Pago: $tipoPago');
    print('     - Precio base: \$${precioBase.toStringAsFixed(2)}');
    print(
      '     - Precio calculado: \$${precioFinal.toStringAsFixed(2)} ${esRecargo ? "(recargo)" : "(promoción)"}',
    );
    print('     - Cantidad: ${item.cantidad}');
    print('     - Total item: \$${itemTotal.toStringAsFixed(2)}');

    return itemTotal;
  }

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
    if (lowerName.contains('efectivo') || lowerName.contains('cash'))
      return '💵';
    if (lowerName.contains('digital') ||
        lowerName.contains('tarjeta') ||
        lowerName.contains('card'))
      return '💳';
    if (lowerName.contains('transferencia') || lowerName.contains('transfer'))
      return '🏦';
    return '💰';
  }

  Widget _buildBuyerInfoSection() {
    // Si no se solicita cliente, ocultar esta sección
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
          TextFormField(
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
          const SizedBox(height: 12),
          TextFormField(
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
    // Si no se solicita cliente, ocultar esta sección también
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
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
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
              const Text('Subtotal:', style: TextStyle(fontSize: 14)),
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
                  '-\$${PriceUtils.formatDiscountPrice(_promoDiscount)}',
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

  Widget _buildCreateOrderButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _createOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4A90E2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child:
            _isProcessing
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
    if (promoCode.toUpperCase() == 'DESCUENTO10' ||
        promoCode.toUpperCase() == 'PROMO10') {
      setState(() {
        _promoDiscount = PriceUtils.roundDiscountPrice(
          totalAfterPromo * promoDiscountPercentage,
        );
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

    print(
      '🔐 Código generado para "$buyerName": $clientCode (${clientCode.length} caracteres)',
    );
    return clientCode;
  }

  // Registrar cliente en Supabase y retornar el ID del cliente
  Future<int?> _registerClientInSupabase(
    String buyerName,
    String buyerPhone,
  ) async {
    try {
      print('🔄 Registrando cliente en Supabase...');
      print('  - Nombre: $buyerName');
      print(
        '  - Teléfono: ${buyerPhone.isNotEmpty ? buyerPhone : "No proporcionado"}',
      );

      // Generar código de cliente encriptado
      final clientCode = _generateClientCode(buyerName);

      final response = await Supabase.instance.client.rpc(
        'fn_insertar_cliente_con_contactos',
        params: {
          'p_codigo_cliente':
              clientCode, // Código generado desde nombre encriptado
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
        print(
          '⚠️ Advertencia al registrar cliente: ${response?['message'] ?? "Respuesta vacía"}',
        );
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
      _showErrorMessage(
        'Todos los productos deben tener un método de pago asignado',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final buyerName = _buyerNameController.text.trim();
      final buyerPhone = _buyerPhoneController.text.trim();

      // Detectar si es una orden offline
      if (widget.order.isOfflineOrder) {
        print(
          '🔌 Procesando orden offline - Capturando datos del cliente y creando orden offline',
        );
        await _processOfflineOrder(buyerName, buyerPhone, breakdown);
      } else {
        print('🌐 Procesando orden online - Flujo normal');
        await _processOnlineOrder(buyerName, buyerPhone, breakdown);
      }
    } catch (e) {
      _showErrorMessage('Error al crear la orden: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// Procesar orden en modo offline
  Future<void> _processOfflineOrder(
    String buyerName,
    String buyerPhone,
    Map<String, double> breakdown,
  ) async {
    try {
      // Obtener datos del usuario
      final userData = await _userPreferencesService.getUserData();
      final idTienda = await _userPreferencesService.getIdTienda();
      final idTpv = await _userPreferencesService.getIdTpv();
      final idSeller = await _userPreferencesService.getIdSeller();

      // Generar ID único para la orden offline
      final offlineOrderId = '${DateTime.now().millisecondsSinceEpoch}';

      // Calcular totales
      double subtotal = 0.0;
      double totalDescuentos = _promoDiscount;

      // Preparar desglose de pagos por método
      Map<String, Map<String, dynamic>> paymentBreakdown = {};

      for (final item in widget.order.items) {
        // ✅ CORREGIDO: Usar item.subtotal que ya tiene el precio correcto según método de pago
        final itemTotal = item.subtotal;
        subtotal += itemTotal;

        print('🔌 OFFLINE - Producto: ${item.producto.denominacion}');
        print('  - Precio unitario base: \$${item.precioUnitario}');
        print('  - Subtotal con método de pago: \$${item.subtotal}');
        print(
          '  - Método de pago: ${item.paymentMethod?.denominacion ?? "Sin método"}',
        );

        // Agrupar por método de pago
        final paymentMethodId =
            item.paymentMethod?.id.toString() ?? 'sin_metodo';
        if (!paymentBreakdown.containsKey(paymentMethodId)) {
          paymentBreakdown[paymentMethodId] = {
            'id_medio_pago': item.paymentMethod?.id,
            'denominacion': item.paymentMethod?.denominacion ?? 'Sin método',
            'monto': 0.0,
            'es_digital': item.paymentMethod?.esDigital ?? false,
            'es_efectivo': item.paymentMethod?.esEfectivo ?? false,
          };
        }
        paymentBreakdown[paymentMethodId]!['monto'] =
            (paymentBreakdown[paymentMethodId]!['monto'] as double) + itemTotal;
      }

      final total = subtotal - totalDescuentos;

      // Crear estructura de orden virtual con datos del cliente
      final orderData = {
        'id': offlineOrderId,
        'id_tienda': idTienda,
        'id_tpv': idTpv,
        'id_vendedor': idSeller,
        'id_usuario': userData['userId'],
        'fecha_creacion': DateTime.now().toIso8601String(),
        'subtotal': subtotal,
        'total_descuentos': totalDescuentos,
        'total': total,
        'estado': 'pendiente_sincronizacion',
        'is_pending_sync': true,
        'created_offline_at': DateTime.now().toIso8601String(),
        // DATOS DEL CLIENTE CAPTURADOS
        'buyer_name': buyerName,
        'buyer_phone': buyerPhone,
        'extra_contacts': _extraContactsController.text.trim(),
        'promo_code': _promoApplied ? _promoCodeController.text.trim() : null,
        'promo_discount': _promoDiscount,
        'items':
            widget.order.items.map((item) {
              // ✅ CORREGIDO: Usar el precio unitario correcto calculado desde el subtotal
              final precioUnitarioCorrect =
                  item.cantidad > 0
                      ? (item.subtotal / item.cantidad)
                      : item.precioUnitario;

              print(
                '💾 GUARDANDO OFFLINE - Producto: ${item.producto.denominacion}',
              );
              print('  - Precio unitario base: \$${item.precioUnitario}');
              print('  - Subtotal con método de pago: \$${item.subtotal}');
              print(
                '  - Precio unitario correcto guardado: \$${precioUnitarioCorrect}',
              );
              print(
                '  - Método de pago: ${item.paymentMethod?.denominacion ?? "Sin método"}',
              );

              return {
                'id_producto': item.producto.id,
                'denominacion': item.producto.denominacion,
                'cantidad': item.cantidad,
                'precio_unitario':
                    precioUnitarioCorrect, // ✅ Precio correcto según método de pago
                'subtotal': item.subtotal, // ✅ Subtotal con precio correcto
                'id_medio_pago': item.paymentMethod?.id,
                'metodo_pago': item.paymentMethod?.denominacion,
                'inventory_metadata': item.inventoryData,
              };
            }).toList(),
        'desglose_pagos': paymentBreakdown.values.toList(),
      };

      // Guardar orden pendiente
      await _userPreferencesService.savePendingOrder(orderData);

      // Actualizar inventario en cache
      for (final item in widget.order.items) {
        final inventoryMetadata = item.inventoryData;

        if (inventoryMetadata != null) {
          final variantId = (inventoryMetadata['id_variante'] as num?)?.toInt();
          final inventoryId =
              (inventoryMetadata['id_inventario'] as num?)?.toInt();
          final locationId =
              (inventoryMetadata['id_ubicacion'] as num?)?.toInt();

          await _userPreferencesService.updateProductInventoryInCache(
            item.producto.id,
            variantId,
            item.cantidad.toInt(),
            inventoryId: inventoryId,
            locationId: locationId,
          );
        } else {
          await _userPreferencesService.updateProductInventoryInCache(
            item.producto.id,
            null,
            item.cantidad.toInt(),
          );
        }
      }

      // Limpiar orden actual
      _orderService.cancelCurrentOrder();

      // Mostrar mensaje de éxito
      _showSuccessMessage(
        '¡Orden offline creada exitosamente!\nSe sincronizará cuando tengas conexión.',
      );

      print('✅ Orden offline creada con datos del cliente: $offlineOrderId');
      print(
        '👤 Cliente: $buyerName${buyerPhone.isNotEmpty ? " - $buyerPhone" : ""}',
      );
      print('💰 Resumen de orden offline:');
      print('  - Subtotal: \$${subtotal.toStringAsFixed(2)}');
      print('  - Descuentos: \$${totalDescuentos.toStringAsFixed(2)}');
      print('  - Total final: \$${total.toStringAsFixed(2)}');
      print('💳 Desglose de pagos offline:');
      paymentBreakdown.forEach((key, value) {
        print(
          '  - ${value['denominacion']}: \$${value['monto'].toStringAsFixed(2)}',
        );
      });
      print('📦 Inventario actualizado en cache');

      // Navegar a órdenes
      Navigator.pushNamedAndRemoveUntil(context, '/orders', (route) => false);
    } catch (e) {
      print('❌ Error creando orden offline: $e');
      _showErrorMessage('Error al crear la orden offline: $e');
    }
  }

  /// Procesar orden en modo online (flujo original)
  Future<void> _processOnlineOrder(
    String buyerName,
    String buyerPhone,
    Map<String, double> breakdown,
  ) async {
    try {
      // 1. Primero registrar el cliente en Supabase si tenemos datos
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
        'paymentMethod':
            'Múltiples métodos', // Since we have individual payment methods per product
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
        extraContacts:
            _extraContactsController.text.trim().isNotEmpty
                ? _extraContactsController.text.trim()
                : null,
        paymentMethod: 'Múltiples métodos',
      );

      // Finalize the order
      final result = await _orderService.finalizeOrderWithDetails(
        updatedOrder,
        orderData,
      );

      if (result['success'] == true) {
        // Show success and navigate back
        if (result['paymentWarning'] != null) {
          _showErrorMessage(
            'Orden creada con advertencia: ${result['paymentWarning']}',
          );
        } else {
          _showSuccessMessage('¡Orden registrada exitosamente!');
        }

        // Navigate back to orders screen or home
        Navigator.pushNamedAndRemoveUntil(context, '/orders', (route) => false);
      } else {
        _showErrorMessage('Error al registrar la venta: ${result['error']}');
      }
    } catch (e) {
      print('❌ Error procesando orden online: $e');
      _showErrorMessage('Error al procesar la orden: $e');
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
      notes.add(
        'Código promocional: ${orderData['promoCode']} (Descuento: \$${orderData['promoDiscount']?.toStringAsFixed(2) ?? '0.00'})',
      );
    }

    notes.add(
      'Total original: \$${orderData['originalTotal']?.toStringAsFixed(2) ?? '0.00'}',
    );
    notes.add(
      'Total final: \$${orderData['finalTotal']?.toStringAsFixed(2) ?? '0.00'}',
    );

    return notes.join('\n');
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
