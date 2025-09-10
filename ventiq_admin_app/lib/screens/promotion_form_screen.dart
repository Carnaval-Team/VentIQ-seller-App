import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/promotion.dart' as promo;
import '../models/product.dart';
import '../services/promotion_service.dart';
import '../services/product_service.dart';
import '../widgets/marketing_menu_widget.dart';
import '../models/payment_method.dart';

class PromotionFormScreen extends StatefulWidget {
  final promo.Promotion? promotion;
  final List<promo.PromotionType> promotionTypes;
  final Product? prefilledProduct;
  final Function(promo.Promotion)? onPromotionCreated;

  const PromotionFormScreen({
    super.key,
    this.promotion,
    required this.promotionTypes,
    this.prefilledProduct,
    this.onPromotionCreated,
  });

  @override
  State<PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends State<PromotionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final PromotionService _promotionService = PromotionService();
  final ProductService _productService = ProductService();

  // Form controllers
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _codigoController = TextEditingController();
  final _valorDescuentoController = TextEditingController();
  final _minCompraController = TextEditingController();
  final _limiteUsosController = TextEditingController();

  // Form state
  String? _selectedTipoPromocion;
  DateTime? _fechaInicio;
  DateTime? _fechaFin;
  bool _estado = true;
  bool _aplicaTodo = true;
  bool _isLoading = false;
  bool _isEditing = false;
  bool _isLoadingTypes = false;
  
  // Payment method state
  bool _requiereMedioPago = false;
  String? _selectedMedioPago;
  List<PaymentMethod> _paymentMethods = [];
  bool _isLoadingPaymentMethods = false;

  // Menu data
  List<promo.PromotionType> _promotionTypes = [];
  String? _loadingError;

  // Product selection state
  List<Product> _availableProducts = [];
  List<Product> _selectedProducts = [];
  bool _isLoadingProducts = false;
  String? _productSearchQuery;
  final _productSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isEditing = widget.promotion != null;
    _promotionTypes = widget.promotionTypes;
    
    if (_isEditing) {
      _populateForm();
    } else {
      _fechaInicio = DateTime.now();
      _fechaFin = DateTime.now().add(const Duration(days: 30));
      
      // Pre-fill form if product is provided
      if (widget.prefilledProduct != null) {
        _prefilledProductForm();
      }
    }
    
    // Load promotion types if not provided or if we need fresh data
    if (_promotionTypes.isEmpty || _isEditing) {
      _loadPromotionTypes();
    }
    
    // Load available products
    _loadAvailableProducts();
    
    // Load payment methods
    _loadPaymentMethods();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    _codigoController.dispose();
    _valorDescuentoController.dispose();
    _minCompraController.dispose();
    _limiteUsosController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  void _populateForm() {
    final promotion = widget.promotion!;
    _nombreController.text = promotion.nombre;
    _descripcionController.text = promotion.descripcion ?? '';
    _codigoController.text = promotion.codigoPromocion;
    _valorDescuentoController.text = promotion.valorDescuento.toString();
    _minCompraController.text = promotion.minCompra?.toString() ?? '';
    _limiteUsosController.text = promotion.limiteUsos?.toString() ?? '';
    _selectedTipoPromocion = promotion.idTipoPromocion;
    _fechaInicio = promotion.fechaInicio;
    _fechaFin = promotion.fechaFin;
    _estado = promotion.estado ?? false;
    _aplicaTodo = promotion.aplicaTodo ?? false;
    _requiereMedioPago = promotion.requiereMedioPago ?? false;
    _selectedMedioPago = promotion.idMedioPagoRequerido?.toString();
    
    print('📝 Formulario poblado con datos de promoción: ${promotion.nombre}');
    print('📝 Tipo de promoción seleccionado: $_selectedTipoPromocion');
  }

  void _prefilledProductForm() {
    final product = widget.prefilledProduct!;
    
    // Pre-fill form with product-specific data
    _nombreController.text = 'Promoción Especial - ${product.name}';
    _descripcionController.text = 'Promoción especial para el producto ${product.name} (SKU: ${product.sku})';
    _codigoController.text = 'PROMO_${product.sku}_${DateTime.now().millisecondsSinceEpoch}';
    
    // Set default values for product-specific promotion
    _aplicaTodo = false; // This promotion applies to specific product, not all
    _valorDescuentoController.text = '10.0'; // Default 10% discount
    _minCompraController.text = '1'; // Minimum purchase of 1 unit
    
    print('📝 Formulario pre-llenado para producto: ${product.name}');
    print('📝 SKU del producto: ${product.sku}');
  }

  Future<void> _loadPromotionTypes() async {
    setState(() {
      _isLoadingTypes = true;
      _loadingError = null;
    });

    try {
      final types = await _promotionService.getPromotionTypes();
      setState(() {
        _promotionTypes = types;
        _isLoadingTypes = false;
      });
      
      // Si estamos editando, volver a poblar el formulario después de cargar los tipos
      if (_isEditing && widget.promotion != null) {
        _populateForm();
      }
      
      print('✅ Cargados ${types.length} tipos de promoción');
    } catch (e) {
      setState(() {
        _isLoadingTypes = false;
        _loadingError = 'Error al cargar tipos de promoción: $e';
      });
      print('❌ Error cargando tipos de promoción: $e');
      _showErrorSnackBar('Error al cargar tipos de promoción: $e');
    }
  }

  Future<void> _loadAvailableProducts() async {
    setState(() {
      _isLoadingProducts = true;
    });

    try {
      final products = await ProductService.getProductsByTienda();
      setState(() {
        _availableProducts = products;
        _isLoadingProducts = false;
      });
      print('✅ Cargados ${products.length} productos disponibles');
    } catch (e) {
      setState(() {
        _isLoadingProducts = false;
      });
      print('❌ Error cargando productos disponibles: $e');
      _showErrorSnackBar('Error cargando productos disponibles: $e');
    }
  }

  Future<void> _loadPaymentMethods() async {
    setState(() {
      _isLoadingPaymentMethods = true;
    });

    try {
      final paymentMethods = await _promotionService.getPaymentMethods();
      setState(() {
        _paymentMethods = paymentMethods;
        _isLoadingPaymentMethods = false;
      });
      print('✅ Cargados ${paymentMethods.length} métodos de pago');
    } catch (e) {
      setState(() {
        _isLoadingPaymentMethods = false;
      });
      print('❌ Error cargando métodos de pago: $e');
      _showErrorSnackBar('Error cargando métodos de pago: $e');
    }
  }

  Future<void> _savePromotion() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validaciones adicionales
    if (_selectedTipoPromocion == null) {
      _showErrorSnackBar('Debe seleccionar un tipo de promoción');
      return;
    }

    if (_fechaInicio == null) {
      _showErrorSnackBar('Debe seleccionar la fecha de inicio');
      return;
    }

    if (_fechaFin != null && _fechaFin!.isBefore(_fechaInicio!)) {
      _showErrorSnackBar(
        'La fecha de fin debe ser posterior a la fecha de inicio',
      );
      return;
    }

    // Validar que el tipo de promoción existe en la lista cargada
    final tipoExists = _promotionTypes.any((type) => type.id == _selectedTipoPromocion);
    if (!tipoExists) {
      _showErrorSnackBar('El tipo de promoción seleccionado no es válido');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final promotionData = {
        'nombre': _nombreController.text.trim(),
        'descripcion':
            _descripcionController.text.trim().isEmpty
                ? null
                : _descripcionController.text.trim(),
        'codigo_promocion': _codigoController.text.trim(),
        'id_tipo_promocion': int.parse(_selectedTipoPromocion!),
        'valor_descuento': double.parse(_valorDescuentoController.text),
        'min_compra':
            _minCompraController.text.isEmpty
                ? null
                : double.parse(_minCompraController.text),
        'fecha_inicio': _fechaInicio!.toIso8601String(),
        'fecha_fin': _fechaFin?.toIso8601String(),
        'estado': _estado,
        'aplica_todo': _aplicaTodo,
        'limite_usos':
            _limiteUsosController.text.isEmpty
                ? null
                : int.parse(_limiteUsosController.text),
        'requiere_medio_pago': _requiereMedioPago,
        'id_medio_pago_requerido': _selectedMedioPago != null ? int.tryParse(_selectedMedioPago!) : null,
      };

      print('💾 Guardando promoción con datos: $promotionData');

      late promo.Promotion createdPromotion;

      if (_isEditing) {
        await _promotionService.updatePromotion(
          widget.promotion!.id,
          promotionData,
        );
        createdPromotion = await _promotionService.getPromotionById(widget.promotion!.id);
        _showSuccessSnackBar('Promoción actualizada exitosamente');
      } else {
        // Determinar qué productos usar para la relación
        List<Product> productsToLink = [];
        
        // Si hay un producto pre-llenado, usarlo
        if (widget.prefilledProduct != null) {
          productsToLink = [widget.prefilledProduct!];
          print('📦 Usando producto pre-llenado: ${widget.prefilledProduct!.name}');
        }
        // Si no aplica a todo y hay productos seleccionados, usarlos
        else if (!_aplicaTodo && _selectedProducts.isNotEmpty) {
          productsToLink = _selectedProducts;
          print('📦 Usando productos seleccionados: ${_selectedProducts.length}');
        }

        // Crear promoción con productos específicos si hay productos para vincular
        if (productsToLink.isNotEmpty) {
          print('📦 Creando promoción con ${productsToLink.length} productos específicos');
          createdPromotion = await _promotionService.createPromotionWithProducts(
            promotionData,
            productsToLink,
          );
        } else {
          print('📦 Creando promoción general (aplica a todos los productos)');
          createdPromotion = await _promotionService.createPromotion(promotionData);
        }
        
        _showSuccessSnackBar('Promoción creada exitosamente');
      }

      // Llamar callback si existe
      if (widget.onPromotionCreated != null) {
        widget.onPromotionCreated!(createdPromotion);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      print('❌ Error al guardar promoción: $e');
      _showErrorSnackBar('Error al guardar promoción: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Promoción' : 'Nueva Promoción'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          const MarketingMenuWidget(),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _savePromotion,
              child: const Text(
                'Guardar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBasicInfoSection(),
              const SizedBox(height: 24),
              _buildDiscountSection(),
              const SizedBox(height: 24),
              _buildDateSection(),
              const SizedBox(height: 24),
              _buildLimitsSection(),
              const SizedBox(height: 24),
              _buildStatusSection(),
              const SizedBox(height: 24),
              _buildPaymentMethodSection(),
              const SizedBox(height: 24),
              _buildProductSelectionSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Información Básica',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la promoción *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El nombre es obligatorio';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descripcionController,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _codigoController,
                    decoration: const InputDecoration(
                      labelText: 'Código de promoción *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'El código es obligatorio';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _generateCode,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPromotionTypeDropdown(),
            _buildChargePromotionWarning(),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotionTypeDropdown() {
    if (_isLoadingTypes) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Cargando tipos de promoción...'),
            ],
          ),
        ),
      );
    }

    if (_loadingError != null) {
      return Column(
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _loadingError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _loadPromotionTypes,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedTipoPromocion,
      decoration: const InputDecoration(
        labelText: 'Tipo de promoción *',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.category),
      ),
      items: _promotionTypes
          .map(
            (type) => DropdownMenuItem<String>(
              value: type.id,
              child: Text(type.denominacion),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedTipoPromocion = value;
        });
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Debe seleccionar un tipo de promoción';
        }
        return null;
      },
    );
  }

  Widget _buildChargePromotionWarning() {
    if (_selectedTipoPromocion == null || !_isChargePromotionType(_selectedTipoPromocion!)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        border: Border.all(color: Colors.orange, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '⚠️ Esta promoción aumentará el precio de venta de los productos afectados',
              style: TextStyle(
                color: Colors.orange[800],
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Método helper para detectar tipos de promoción con recargo
  bool _isChargePromotionType(String tipoPromocionId) {
    // Verificar por ID
    if (tipoPromocionId == '8' || tipoPromocionId == '9') {
      return true;
    }

    // Verificar por denominación
    final tipoPromocion = _promotionTypes.firstWhere(
      (type) => type.id == tipoPromocionId,
      orElse: () => promo.PromotionType(
        id: '',
        denominacion: '',
        createdAt: DateTime.now(),
      ),
    );

    return tipoPromocion.denominacion.toLowerCase().contains('recargo');
  }

  Widget _buildDiscountSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_offer, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Configuración de Descuento',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _valorDescuentoController,
              decoration: const InputDecoration(
                labelText: 'Valor del descuento (%) *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.percent),
                suffixText: '%',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'El valor del descuento es requerido';
                }
                final double? discount = double.tryParse(value);
                if (discount == null) {
                  return 'Ingrese un valor válido';
                }
                if (discount <= 0 || discount > 100) {
                  return 'El descuento debe estar entre 1% y 100%';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _minCompraController,
              decoration: const InputDecoration(
                labelText: 'Compra mínima',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
                prefixText: '\$ ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final double? minPurchase = double.tryParse(value);
                  if (minPurchase == null || minPurchase < 0) {
                    return 'Ingrese un valor válido';
                  }
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSection() {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.date_range, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Vigencia',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return Column(
                    children: [
                      InkWell(
                        onTap: () => _selectDate(context, true),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Fecha de inicio *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.event),
                          ),
                          child: Text(
                            _fechaInicio != null
                                ? dateFormat.format(_fechaInicio!)
                                : 'Seleccionar fecha',
                            style: TextStyle(
                              color: _fechaInicio != null
                                  ? Colors.black87
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Column(
                        children: [
                          InkWell(
                            onTap: () => _selectDate(context, false),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Fecha de fin (opcional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.event),
                              ),
                              child: Text(
                                _fechaFin != null
                                    ? dateFormat.format(_fechaFin!)
                                    : 'Sin vencimiento',
                                style: TextStyle(
                                  color: _fechaFin != null
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                          if (_fechaFin != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _fechaFin = null;
                                  });
                                },
                                icon: const Icon(Icons.clear, size: 16),
                                label: const Text('Sin vencimiento', style: TextStyle(fontSize: 12)),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.grey[600],
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                } else {
                  return Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: InkWell(
                          onTap: () => _selectDate(context, true),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Fecha de inicio *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.event),
                            ),
                            child: Text(
                              _fechaInicio != null
                                  ? dateFormat.format(_fechaInicio!)
                                  : 'Seleccionar fecha',
                              style: TextStyle(
                                color: _fechaInicio != null
                                    ? Colors.black87
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () => _selectDate(context, false),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Fecha de fin (opcional)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.event),
                                ),
                                child: Text(
                                  _fechaFin != null
                                      ? dateFormat.format(_fechaFin!)
                                      : 'Sin vencimiento',
                                  style: TextStyle(
                                    color: _fechaFin != null
                                        ? Colors.black87
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                            ),
                            if (_fechaFin != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _fechaFin = null;
                                    });
                                  },
                                  icon: const Icon(Icons.clear, size: 16),
                                  label: const Text('Sin vencimiento', style: TextStyle(fontSize: 12)),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.grey[600],
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }
              },
            ),
            if (_fechaInicio != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _fechaFin != null 
                          ? 'Duración: ${_fechaFin!.difference(_fechaInicio!).inDays} días'
                          : 'Promoción sin fecha de vencimiento',
                      style: const TextStyle(
                        color: AppColors.primary,
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
    );
  }

  Widget _buildLimitsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Límites y Restricciones',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _limiteUsosController,
              decoration: const InputDecoration(
                labelText: 'Límite de usos',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.trending_up),
                helperText: 'Dejar vacío para usos ilimitados',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final int? limit = int.tryParse(value);
                  if (limit == null || limit <= 0) {
                    return 'Ingrese un número válido mayor a 0';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Aplica a todos los productos'),
              subtitle: const Text(
                'Si está desactivado, debe seleccionar productos específicos',
              ),
              value: _aplicaTodo,
              onChanged: (value) {
                setState(() {
                  _aplicaTodo = value;
                });
              },
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.toggle_on, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Estado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Promoción activa'),
              subtitle: Text(
                _estado
                    ? 'La promoción estará disponible para uso'
                    : 'La promoción estará desactivada',
              ),
              value: _estado,
              onChanged: (value) {
                setState(() {
                  _estado = value;
                });
              },
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payment, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Método de Pago',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Requiere método de pago'),
              subtitle: const Text(
                'Si está activado, debe seleccionar un método de pago',
              ),
              value: _requiereMedioPago,
              onChanged: (value) {
                setState(() {
                  _requiereMedioPago = value;
                });
              },
              activeColor: AppColors.primary,
            ),
            if (_requiereMedioPago) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedMedioPago,
                decoration: const InputDecoration(
                  labelText: 'Método de pago *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.credit_card),
                ),
                items: _paymentMethods
                    .map(
                      (method) => DropdownMenuItem<String>(
                        value: method.id.toString(),
                        child: Row(
                          children: [
                            Icon(method.typeIcon, size: 16),
                            const SizedBox(width: 8),
                            Text(method.denominacion),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedMedioPago = value;
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Debe seleccionar un método de pago';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProductSelectionSection() {
    if (_aplicaTodo) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Selección de Productos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Show selected product card if prefilledProduct exists
            if (widget.prefilledProduct != null) ...[
              _buildSelectedProductCard(),
              const SizedBox(height: 16),
            ],
            
            TextFormField(
              controller: _productSearchController,
              decoration: const InputDecoration(
                labelText: 'Buscar productos',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _productSearchQuery = value;
                });
              },
            ),
            const SizedBox(height: 16),
            if (_selectedProducts.isNotEmpty) ...[
              Text(
                'Productos seleccionados: ${_selectedProducts.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _selectedProducts.map((product) {
                  return Chip(
                    label: Text(product.name),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedProducts.remove(product);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              height: 300,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _isLoadingProducts
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _availableProducts.isEmpty
                      ? const Center(
                          child: Text('No se encontraron productos'),
                        )
                      : ListView.builder(
                          itemCount: _availableProducts.length,
                          itemBuilder: (context, index) {
                            final product = _availableProducts[index];
                            final isSelected = _selectedProducts.contains(product);

                            return ListTile(
                              title: Text(product.name),
                              subtitle: Text('SKU: ${product.sku}'),
                              trailing: isSelected
                                  ? const Icon(Icons.check_circle, color: AppColors.primary)
                                  : const Icon(Icons.radio_button_unchecked),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedProducts.remove(product);
                                  } else {
                                    _selectedProducts.add(product);
                                  }
                                });
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedProductCard() {
    final product = widget.prefilledProduct!;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        border: Border.all(color: AppColors.primary, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.inventory_2,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Producto Seleccionado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _buildProductInfoRow('SKU', product.sku),
                const Divider(height: 16),
                _buildProductInfoRow('Precio Base', '\$${product.basePrice?.toStringAsFixed(0) ?? 'N/A'}'),
                if (product.stockDisponible > 0) ...[
                  const Divider(height: 16),
                  _buildProductInfoRow('Stock', '${product.stockDisponible} unidades'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esta promoción se aplicará específicamente a este producto',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _generateCode() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    final code = widget.prefilledProduct != null 
        ? 'PROMO_${widget.prefilledProduct!.sku}_$timestamp'
        : 'PROMO_$timestamp';
    
    setState(() {
      _codigoController.text = code;
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate 
          ? (_fechaInicio ?? DateTime.now())
          : (_fechaFin ?? DateTime.now().add(const Duration(days: 30))),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );

    if (picked != null) {
      final TimeOfDay? timePicked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );

      if (timePicked != null) {
        final DateTime finalDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          timePicked.hour,
          timePicked.minute,
        );

        setState(() {
          if (isStartDate) {
            _fechaInicio = finalDateTime;
          } else {
            _fechaFin = finalDateTime;
          }
        });
      }
    }
  }
}
