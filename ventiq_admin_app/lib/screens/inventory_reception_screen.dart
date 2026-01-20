import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/reception_total_widget.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';
import '../services/currency_display_service.dart';
import '../models/warehouse.dart';
import '../models/supplier.dart';
import '../widgets/conversion_info_widget.dart';
import '../widgets/product_quantity_dialog.dart';
import '../widgets/location_selector_widget.dart';
import '../widgets/currency_info_widget.dart';
import '../widgets/product_selector_widget.dart';
import '../widgets/supplier/supplier_reception_integration.dart';
import '../services/product_search_service.dart';

class InventoryReceptionScreen extends StatefulWidget {
  const InventoryReceptionScreen({super.key});

  @override
  State<InventoryReceptionScreen> createState() =>
      _InventoryReceptionScreenState();
}

class _InventoryReceptionScreenState extends State<InventoryReceptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _entregadoPorController = TextEditingController();
  final _recibidoPorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _montoTotalController = TextEditingController();
  final _searchController = TextEditingController();

  // Static variables to persist field values across screen instances
  static String _lastEntregadoPor = '';
  static String _lastRecibidoPor = '';
  static String _lastObservaciones = '';
  String _selectedCurrency = 'USD'; // Moneda seleccionada para la factura
  double? _currentExchangeRate; // Tasa de cambio actual
  double? _totalAmountInCUP; // Monto total convertido a CUP
  List<Map<String, dynamic>> _selectedProducts = [];
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  WarehouseZone? _selectedLocation;
  bool _isLoading = false;
  bool _isLoadingProducts = true;
  bool _isLoadingMotivos = true;
  String _searchQuery = '';
  Supplier? _selectedSupplier;
  List<Map<String, dynamic>> _proveedores = [];
  Map<String, dynamic>? _selectedProveedor;
  bool _isLoadingProveedores = false;

  @override
  void initState() {
    super.initState();
    _loadMotivoOptions();
    _loadExchangeRate();
    _loadProveedores();
    _searchController.addListener(_onSearchChanged);
    _montoTotalController.addListener(_updateTotalAmountInCUP);

    // Load persisted values from previous entries
    _loadPersistedValues();
  }

  // ← NUEVOS MÉTODOS PARA MONEDAS
  Future<void> _loadExchangeRate() async {
    if (_selectedCurrency == 'CUP') return;

    try {
      final rate = await CurrencyDisplayService.getExchangeRateForDisplay(
        _selectedCurrency,
        'CUP',
      );
      setState(() {
        _currentExchangeRate = rate;
        _updateTotalAmountInCUP();
      });
    } catch (e) {
      print('Error loading exchange rate: $e');
    }
  }

  void _updateTotalAmountInCUP() {
    final totalAmount = double.tryParse(_montoTotalController.text);
    if (totalAmount != null &&
        _currentExchangeRate != null &&
        _selectedCurrency != 'CUP') {
      setState(() {
        _totalAmountInCUP = totalAmount * _currentExchangeRate!;
      });
    } else {
      setState(() {
        _totalAmountInCUP = null;
      });
    }
  }

  void _onCurrencyChanged(String newCurrency) {
    setState(() {
      _selectedCurrency = newCurrency;
      _currentExchangeRate = null;
      _totalAmountInCUP = null;
    });
    _loadExchangeRate();
  }

  void _loadPersistedValues() {
    _entregadoPorController.text = _lastEntregadoPor;
    _recibidoPorController.text = _lastRecibidoPor;
    _observacionesController.text = _lastObservaciones;
  }

  void _savePersistedValues() {
    _lastEntregadoPor = _entregadoPorController.text;
    _lastRecibidoPor = _recibidoPorController.text;
    _lastObservaciones = _observacionesController.text;
  }

  @override
  void dispose() {
    _entregadoPorController.dispose();
    _recibidoPorController.dispose();
    _observacionesController.dispose();
    _montoTotalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  Future<void> _loadMotivoOptions() async {
    try {
      setState(() => _isLoadingMotivos = true);
      final motivos = await InventoryService.getMotivoRecepcionOptions();
      setState(() {
        _motivoOptions = motivos;
        if (motivos.isNotEmpty) {
          _selectedMotivo = motivos.first;
        }
        _isLoadingMotivos = false;
      });
    } catch (e) {
      setState(() => _isLoadingMotivos = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar motivos: $e')));
      }
    }
  }

  Future<void> _loadProveedores() async {
    try {
      setState(() => _isLoadingProveedores = true);
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Obtener proveedores de la tienda del usuario
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_dat_proveedor')
          .select('id, denominacion, sku_codigo')
          .eq('idtienda', idTienda)
          .order('denominacion', ascending: true);
      
      final proveedores = List<Map<String, dynamic>>.from(response);
      
      setState(() {
        _proveedores = proveedores;
        _selectedProveedor = null; // Sin filtro por defecto
        _isLoadingProveedores = false;
      });
      
      print('✅ Proveedores cargados de tienda $idTienda: ${_proveedores.length}');
    } catch (e) {
      setState(() => _isLoadingProveedores = false);
      print('❌ Error al cargar proveedores: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar proveedores: $e')),
        );
      }
    }
  }

  void _addProductToReception(Product product) {
    showDialog(
      context: context,
      builder:
          (context) => ProductQuantityDialog(
            product: product,
            selectedLocation: _selectedLocation,
            invoiceCurrency: _selectedCurrency, // ← Moneda de factura
            exchangeRate: _currentExchangeRate, // ← Tasa actual
            onProductAdded: (productData) {
              setState(() {
                _selectedProducts.add(productData);
              });
            },
          ),
    );
  }

  void _removeProduct(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
    });
  }

  double get _totalAmount {
    return _selectedProducts.fold(0.0, (sum, item) {
      final cantidad = item['cantidad'] as double;
      final precio = item['precio_unitario'] as double? ?? 0.0;
      return sum + (cantidad * precio);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _submitReception() async {
    // Validaciones mejoradas
    if (!_formKey.currentState!.validate()) {
      _showError('Complete todos los campos requeridos');
      return;
    }
    if (_selectedProducts.isEmpty) {
      _showError('Debe agregar al menos un producto');
      return;
    }
    if (_selectedLocation == null) {
      _showError('Debe seleccionar una ubicación de destino');
      return;
    }
    if (_selectedCurrency.isEmpty) {
      _showError('Debe seleccionar una moneda para la factura');
      return;
    }
    if (_selectedCurrency != 'CUP' && _currentExchangeRate == null) {
      _showError('No se pudo cargar la tasa de cambio para $_selectedCurrency');
      return;
    }
    // Validar que todos los productos tengan datos válidos
    for (final product in _selectedProducts) {
      final precio = product['precio_unitario'] as double?;
      final cantidad = product['cantidad'] as double?;

      if (precio == null || precio < 0) {
        _showError(
          'Producto "${product['denominacion']}" tiene precio inválido',
        );
        return;
      }
      if (cantidad == null || cantidad <= 0) {
        _showError(
          'Producto "${product['denominacion']}" tiene cantidad inválida',
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      final userUuid = await userPrefs.getUserId();

      if (idTienda == null || userUuid == null) {
        throw Exception('No se encontró información del usuario');
      }

      // Prepare products list with location IDs
      final productosParaEnviar =
          _selectedProducts.map((product) {
            // Add selected location ID to each product
            final productWithLocation = Map<String, dynamic>.from(product);
            if (_selectedLocation != null) {
              // Remove prefix ('z' for zones, 'w' for warehouses) before parsing as int
              try {
                // El LocationSelectorWidget ahora devuelve directamente el ID de la zona
                final locationId = int.parse(_selectedLocation!.id);
                print("Location ID: $locationId");
                productWithLocation['id_ubicacion'] = locationId;
              } catch (e) {
                throw Exception(
                  'Error: ID de ubicación inválido "${_selectedLocation!.id}"',
                );
              }
            }
            return productWithLocation;
          }).toList();

      // Debug: Print products list before sending to Supabase
      print("=== PRODUCTOS PARA ENVIAR A SUPABASE ===");
      print("Total productos: ${productosParaEnviar.length}");
      for (int i = 0; i < productosParaEnviar.length; i++) {
        print("Producto ${i + 1}: ${productosParaEnviar[i]}");
      }
      print("==========================================");

      final result = await InventoryService.insertInventoryReception(
        entregadoPor: _entregadoPorController.text,
        idTienda: idTienda,
        montoTotal:
            _montoTotalController.text.isNotEmpty
                ? double.parse(_montoTotalController.text)
                : _totalAmount,
        motivo: _selectedMotivo?['id'] ?? '',
        observaciones: _observacionesController.text,
        productos: productosParaEnviar,
        recibidoPor: _recibidoPorController.text,
        idProveedor: _selectedSupplier?.id,
        uuid: userUuid,
        monedaFactura: _selectedCurrency
      );

      if (mounted) {
        if (result['status'] == 'success') {
          // Save the values for future use before showing success message
          _savePersistedValues();

          // ← GUARDAR TASA HISTÓRICA CON VALIDACIÓN
          if (_currentExchangeRate != null && result['id_operacion'] != null) {
            try {
              final success =
                  await CurrencyDisplayService.saveHistoricalExchangeRate(
                    result['id_operacion'],
                    _currentExchangeRate!,
                    _selectedCurrency,
                    'CUP',
                  );
              if (!success) {
                print('⚠️ Advertencia: No se pudo guardar la tasa histórica');
              }
            } catch (e) {
              print('❌ Error guardando tasa histórica: $e');
            }
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Recepción registrada exitosamente. ID: ${result['id_operacion']}',
              ),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context);
        } else {
          throw Exception(result['message'] ?? 'Error desconocido');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar recepción: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Recepción de Inventario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReceptionInfoSection(),
                    const SizedBox(height: 24),
                    _buildLocationSelectionSection(),
                    const SizedBox(height: 24),
                    _buildProductSelectionSection(),
                    const SizedBox(height: 24),
                    _buildSelectedProductsSection(),
                    
                  ],
                ),
              ),
            ),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildReceptionInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información de Recepción',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _entregadoPorController,
              decoration: const InputDecoration(
                labelText: 'Entregado por',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _recibidoPorController,
              decoration: const InputDecoration(
                labelText: 'Recibido por',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _isLoadingMotivos
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedMotivo,
                  decoration: const InputDecoration(
                    labelText: 'Motivo',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      _motivoOptions.map((motivo) {
                        return DropdownMenuItem(
                          value: motivo,
                          child: Text(
                            motivo['denominacion'] ?? 'Sin denominación',
                          ),
                        );
                      }).toList(),
                  onChanged: (motivo) {
                    setState(() {
                      _selectedMotivo = motivo;
                    });
                  },
                  validator: (value) {
                    if (value == null) return 'Campo requerido';
                    return null;
                  },
                ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montoTotalController,
              decoration: InputDecoration(
                labelText: 'Monto Total (Opcional)',
                hintText:
                    'Calculado automáticamente: \$${_totalAmount.toStringAsFixed(2)}',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),

            // ← NUEVOS WIDGETS DE MONEDA
            const SizedBox(height: 16),
            CurrencyInfoWidget(
              selectedCurrency: _selectedCurrency,
              amount: double.tryParse(_montoTotalController.text),
              onCurrencyChanged: _onCurrencyChanged,
            ),

            // Mostrar conversión si hay monto y tasa
            if (_totalAmountInCUP != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.currency_exchange, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Total en CUP: \$${_totalAmountInCUP!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
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

  Widget _buildProductSelectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccionar Productos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Sección de filtro por proveedor
            _buildProveedorFilterSection(),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: ProductSelectorWidget(
                key: ValueKey(_selectedProveedor?['id']),
                searchType: ProductSearchType.all,
                requireInventory: false,
                searchHint: 'Buscar productos para recibir...',
                supplierId: _selectedProveedor?['id'] as int?,
                onProductSelected: (productData) {                  
                  // Convertir Map a Product para mantener compatibilidad
                  final product = Product(
                    id: productData['id']?.toString() ?? '',
                    name:
                        productData['denominacion'] ??
                        productData['nombre_producto'] ??
                        'Sin nombre',
                    denominacion:
                        productData['denominacion'] ??
                        productData['nombre_producto'] ??
                        'Sin nombre',
                    description: productData['descripcion'] ?? '',
                    categoryId: productData['id_categoria']?.toString() ?? '',
                    categoryName: productData['categoria_nombre'] ?? '',
                    brand: '', // No disponible en nueva estructura
                    sku: productData['sku_producto'] ?? productData['sku'] ?? '',
                    barcode: productData['codigo_barras'] ?? '',
                    basePrice:
                        (productData['precio_venta_cup'] as num?)?.toDouble() ??
                        0.0,
                    imageUrl: '', // No disponible en nueva estructura
                    createdAt: DateTime.now(), // Valor por defecto
                    updatedAt: DateTime.now(), // Valor por defecto
                    // Campos específicos de la nueva estructura
                    um: productData['um'],
                    precioVenta:
                        (productData['precio_venta_cup'] as num?)?.toDouble() ??
                        0.0,
                    esVendible: productData['es_vendible'] ?? true,
                    esElaborado: productData['es_elaborado'] ?? false,
                    esServicio: productData['es_servicio'] ?? false,
                    stockDisponible: productData['stock_disponible'] ?? false,
                    presentaciones:
                        (productData['presentaciones'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [],
                    variantesDisponibles:
                        (productData['variantes_disponibles'] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [],
                  );
                  
                  // Debug: Verificar el objeto Product creado
                  print('✅ Product creado:');
                  print('  - name: ${product.name}');
                  print('  - sku: "${product.sku}"');
                  print('  - sku.isEmpty: ${product.sku.isEmpty}');
                  
                  _addProductToReception(product);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedProductsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productos Seleccionados (${_selectedProducts.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_selectedProducts.isEmpty)
              const Center(
                child: Text(
                  'No hay productos seleccionados',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _selectedProducts.length,
                itemBuilder: (context, index) {
                  final item = _selectedProducts[index];
                  final originalIndex = _selectedProducts.indexOf(item);
                  return ListTile(
                    title: Text(
                      item['denominacion'] ??
                          item['nombre_producto'] ??
                          'Producto sin nombre',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SKU: ${item['sku_producto'] ?? item['sku'] ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          _buildQuantityDisplay(item),
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          _buildPriceDisplay(item),
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (item['precio_referencia'] != null &&
                            item['precio_referencia'] > 0)
                          Text(
                            'Precio Ref: \$${item['precio_referencia']?.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        if ((item['descuento_porcentaje'] ?? 0) > 0 ||
                            (item['descuento_monto'] ?? 0) > 0)
                          Text(
                            'Descuento: ${item['descuento_porcentaje'] ?? 0}% + \$${item['descuento_monto']?.toStringAsFixed(2) ?? '0.00'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                        if ((item['bonificacion_cantidad'] ?? 0) > 0)
                          Text(
                            'Bonificación: +${item['bonificacion_cantidad']} unidades',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                            ),
                          ),
                        if (_buildVariantInfo(item).isNotEmpty)
                          Container(
                            margin: EdgeInsets.only(top: 4),
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _buildVariantInfo(item),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.remove_circle,
                        color: AppColors.error,
                      ),
                      onPressed: () => _removeProduct(originalIndex),
                    ),
                  );
                },
              ),
            // NUEVO: Agregar widget de conversiones después de la lista de productos
            ConversionInfoWidget(
              conversions: _selectedProducts,
              showDetails: true,
            ),
          ],
        ),
      ),
    );
  }

  String _buildQuantityDisplay(Map<String, dynamic> item) {
    final cantidad = item['cantidad'] as double;
    final precio = item['precio_unitario'] as double? ?? 0.0;

    // Verificar si se aplicó conversión
    final conversionApplied = item['conversion_applied'] == true;
    final cantidadOriginal = item['cantidad_original'] as double?;

    String quantityText;
    if (conversionApplied && cantidadOriginal != null) {
      // Obtener nombres de presentaciones
      final presentacionOriginal = item['presentacion_original_info'];
      final presentacionFinal = item['presentation_info'];

      String presentacionOriginalText = 'unidades';
      String presentacionFinalText = 'unidades base';

      if (presentacionOriginal != null &&
          presentacionOriginal['denominacion'] != null) {
        presentacionOriginalText = presentacionOriginal['denominacion'];
      }

      if (presentacionFinal != null &&
          presentacionFinal['denominacion'] != null) {
        presentacionFinalText = presentacionFinal['denominacion'];
      }

      // Mostrar conversión con nombres de presentaciones
      quantityText =
          'Cantidad: ${cantidadOriginal.toInt()} $presentacionOriginalText → ${cantidad.toInt()} $presentacionFinalText';
    } else {
      // Mostrar cantidad normal
      quantityText = 'Cantidad: ${cantidad.toInt()}';
    }

    return quantityText;
  }

  String _buildPriceDisplay(Map<String, dynamic> item) {
    final precio = item['precio_unitario'] as double? ?? 0.0;
    String precioText;
    if (_selectedCurrency == 'CUP') {
      precioText = 'Precio: ${precio.toStringAsFixed(3)} CUP';
      if (_currentExchangeRate != null && _currentExchangeRate! > 0) {
        final precioUSD = precio / _currentExchangeRate!;
        precioText += ' (≈ ${precioUSD.toStringAsFixed(2)} USD)';
      }
    } else {
      final currencySymbol = _getCurrencySymbol(_selectedCurrency);
      precioText =
          'Precio: $currencySymbol${precio.toStringAsFixed(2)} $_selectedCurrency';
      if (_currentExchangeRate != null && _currentExchangeRate! > 0) {
        final precioCUP = precio * _currentExchangeRate!;
        precioText += ' (≈ ${precioCUP.toStringAsFixed(2)} CUP)';
      }
    }
    return precioText;
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Widget de total con conversión de monedas
          ReceptionTotalWidget(
            totalAmount: _totalAmount,
            invoiceCurrency: _selectedCurrency,
            selectedProducts: _selectedProducts,
            onTotalConverted: (convertedAmount, currency) {
              print('Total convertido: $convertedAmount $currency');
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitReception,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child:
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                        'Registrar Recepción',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSelectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccionar Ubicación',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            LocationSelectorWidget(
              type: LocationSelectorType.single,
              title: 'Seleccionar Ubicación de Destino',
              subtitle: 'Zona donde se almacenarán los productos recibidos',
              selectedLocation: _selectedLocation,
              onLocationChanged: (location) {
                setState(() {
                  _selectedLocation = location;
                });
              },
              validationMessage:
                  _selectedLocation == null
                      ? 'Debe seleccionar una ubicación'
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProveedorFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Filtrar por Proveedor',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (_selectedProveedor != null)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedProveedor = null;
                  });
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Limpiar'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _isLoadingProveedores
            ? const Padding(
                padding: EdgeInsets.all(8.0),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedProveedor,
                decoration: InputDecoration(
                  labelText: 'Seleccionar proveedor',
                  border: const OutlineInputBorder(),
                  hintText: _proveedores.isEmpty
                      ? 'No hay proveedores disponibles'
                      : 'Todos los proveedores',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  DropdownMenuItem<Map<String, dynamic>>(
                    value: null,
                    child: const Text('Todos los proveedores'),
                  ),
                  ..._proveedores.map((proveedor) {
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: proveedor,
                      child: Text(
                        proveedor['denominacion'] ?? 'Sin nombre',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ],
                onChanged: (proveedor) {
                  setState(() {
                    _selectedProveedor = proveedor;
                  });
                  print(
                    '✅ Proveedor seleccionado: ${proveedor?['denominacion'] ?? "Todos"}',
                  );
                },
              ),
      ],
    );
  }

  String _buildVariantInfo(Map<String, dynamic> item) {
    List<String> variantParts = [];

    // Priority 1: Use stored variant_info and presentation_info (from dialog selection)
    if (item['variant_info'] != null) {
      final variantInfo = item['variant_info'];
      final atributo =
          variantInfo['atributo']?['denominacion'] ??
          variantInfo['atributo']?['label'] ??
          '';
      final opcion = variantInfo['opcion']?['valor'] ?? '';

      if (atributo.isNotEmpty && opcion.isNotEmpty) {
        variantParts.add('$atributo: $opcion');
      } else if (atributo.isNotEmpty) {
        variantParts.add(atributo);
      }
    }

    if (item['presentation_info'] != null) {
      final presentationInfo = item['presentation_info'];
      final denominacion =
          presentationInfo['denominacion'] ??
          presentationInfo['presentacion'] ??
          presentationInfo['nombre'] ??
          presentationInfo['tipo'] ??
          '';
      final cantidad = presentationInfo['cantidad'] ?? 1;

      if (denominacion.isNotEmpty) {
        variantParts.add('Presentación: $denominacion (${cantidad}x)');
      }
    }

    // Priority 2: Fallback to searching in product data (only if stored info not available)
    if (variantParts.isEmpty) {
      // Add variant information if available
      if (item['id_variante'] != null) {
        // Since we no longer have _availableProducts loaded, we'll skip this fallback
        // The variant info should come from the ProductSelectorWidget data
        // If needed, we can make an individual product query here
        print(
          '⚠️ Variant info fallback skipped - data should come from ProductSelectorWidget',
        );
      }
    }

    return variantParts.join(' | ');
  }

  /// Obtiene el símbolo de la moneda
  String _getCurrencySymbol(String currencyCode) {
    switch (currencyCode) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'CUP':
        return '\$';
      default:
        return '';
    }
  }
}
