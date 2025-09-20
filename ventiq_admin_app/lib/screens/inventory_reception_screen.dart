import 'package:flutter/material.dart';
// import 'dart:convert';
// import 'dart:io';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';
import '../services/warehouse_service.dart';
import '../models/warehouse.dart';
import '../widgets/conversion_info_widget.dart';
import '../utils/presentation_converter.dart';

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

  List<Product> _availableProducts = [];
  List<Product> _filteredProducts = [];
  List<Map<String, dynamic>> _selectedProducts = [];
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  List<Warehouse> _warehouses = [];
  WarehouseZone? _selectedLocation;
  bool _isLoading = false;
  bool _isLoadingProducts = true;
  bool _isLoadingMotivos = true;
  bool _isLoadingWarehouses = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadMotivoOptions();
    _loadWarehouses();
    _searchController.addListener(_onSearchChanged);
    
    // Load persisted values from previous entries
    _loadPersistedValues();
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
      _filterProducts();
    });
  }

  void _filterProducts() {
    // Apply search filter to available products (no location filtering here)
    if (_searchQuery.isEmpty) {
      _filteredProducts = List.from(_availableProducts);
    } else {
      _filteredProducts =
          _availableProducts.where((product) {
            return product.name.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                product.sku.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                product.brand.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
          }).toList();
    }
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

  Future<void> _loadWarehouses() async {
    try {
      setState(() => _isLoadingWarehouses = true);
      final warehouseService = WarehouseService();
      final warehouses = await warehouseService.listWarehouses();

      // Keep warehouses with their zones for tree structure
      List<WarehouseZone> allLocations = [];
      for (final warehouse in warehouses) {
        for (final zone in warehouse.zones) {
          // Add warehouse info to zone for display
          final zoneWithWarehouse = WarehouseZone(
            id: zone.id,
            warehouseId: warehouse.id,
            name: zone.name,
            code: zone.code,
            type: zone.type,
            conditions: zone.conditions,
            capacity: zone.capacity,
            currentOccupancy: zone.currentOccupancy,
            locations: zone.locations,
            conditionCodes: zone.conditionCodes,
          );
          allLocations.add(zoneWithWarehouse);
        }
      }

      setState(() {
        _warehouses = warehouses;
        _isLoadingWarehouses = false;
      });
    } catch (e) {
      setState(() => _isLoadingWarehouses = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar almacenes: $e')),
        );
      }
    }
  }

  Future<void> _loadProducts() async {
    try {
      setState(() => _isLoadingProducts = true);
      final products = await ProductService.getProductsByTienda();
      setState(() {
        _availableProducts = products;
        _filteredProducts = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() => _isLoadingProducts = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar productos: $e')),
        );
      }
    }
  }

  void _addProductToReception(Product product) {
    showDialog(
      context: context,
      builder:
          (context) => _ProductQuantityDialog(
            product: product,
            onProductAdded: (productData) {
              setState(() {
                _selectedProducts.add(productData);
              });
              // ❌ Removido Navigator.pop(context) - el diálogo se cierra desde adentro
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

  Future<void> _submitReception() async {
    if (!_formKey.currentState!.validate() || _selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Complete todos los campos y agregue al menos un producto',
          ),
        ),
      );
      return;
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
                String cleanId = _selectedLocation!.id;
                // Remove 'z' or 'w' prefix if present
                if (cleanId.startsWith('z') || cleanId.startsWith('w')) {
                  cleanId = cleanId.substring(1);
                }
                print("location: ${_selectedLocation!.toJson()}");
                print("Clean ID after removing prefix: $cleanId");
                productWithLocation['id_ubicacion'] = int.parse(cleanId);
              } catch (e) {
                print(
                  'Warning: Could not parse location ID "${_selectedLocation!.id}" as integer: $e',
                );
                // If the ID is not a valid integer, we might need to handle it differently
                // For now, we'll skip adding the id_ubicacion or use a default value
                productWithLocation['id_ubicacion'] = null;
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
        uuid: userUuid,
      );

      if (mounted) {
        if (result['status'] == 'success') {
          // Save the values for future use before showing success message
          _savePersistedValues();
          
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
              validator:
                  (value) => value?.isEmpty == true ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _recibidoPorController,
              decoration: const InputDecoration(
                labelText: 'Recibido por',
                border: OutlineInputBorder(),
              ),
              validator:
                  (value) => value?.isEmpty == true ? 'Campo requerido' : null,
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
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar productos',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child:
                  _isLoadingProducts
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withOpacity(
                                0.1,
                              ),
                              child: Icon(
                                Icons.inventory_2,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(product.name),
                            subtitle: Text(
                              'SKU: ${product.sku} | Marca: ${product.brand}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.add_circle,
                                color: AppColors.primary,
                              ),
                              onPressed: () => _addProductToReception(product),
                            ),
                          );
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
                itemCount: _getFilteredSelectedProducts().length,
                itemBuilder: (context, index) {
                  final item = _getFilteredSelectedProducts()[index];
                  final originalIndex = _selectedProducts.indexOf(item);
                  return ListTile(
                    title: Text(item['denominacion'] ?? item['nombre_producto'] ?? 'Producto sin nombre'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SKU: ${item['sku'] ?? 'N/A'}',
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
                        if (item['precio_referencia'] != null && item['precio_referencia'] > 0)
                          Text(
                            'Precio Ref: \$${item['precio_referencia']?.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        if ((item['descuento_porcentaje'] ?? 0) > 0 || (item['descuento_monto'] ?? 0) > 0)
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
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    
    if (presentacionOriginal != null && presentacionOriginal['denominacion'] != null) {
      presentacionOriginalText = presentacionOriginal['denominacion'];
    }
    
    if (presentacionFinal != null && presentacionFinal['denominacion'] != null) {
      presentacionFinalText = presentacionFinal['denominacion'];
    }
    
    // Mostrar conversión con nombres de presentaciones
    quantityText = 'Cantidad: ${cantidadOriginal.toInt()} $presentacionOriginalText → ${cantidad.toInt()} $presentacionFinalText';
  } else {
    // Mostrar cantidad normal
    quantityText = 'Cantidad: ${cantidad.toInt()}';
  }
  
  return '$quantityText | Precio: \$${precio.toStringAsFixed(2)}';
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '\$${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
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
            _isLoadingWarehouses
                ? const Center(child: CircularProgressIndicator())
                : _buildWarehouseTree(),
            if (_selectedLocation != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ubicación seleccionada: ${_getWarehouseName(_selectedLocation!.warehouseId)} - ${_selectedLocation!.name}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          if (_selectedLocation!.code.isNotEmpty)
                            Text(
                              'Código: ${_selectedLocation!.code}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
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

  Widget _buildWarehouseTree() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children:
            _warehouses.map((warehouse) {
              return ExpansionTile(
                leading: Icon(Icons.warehouse, color: AppColors.primary),
                title: Text(
                  warehouse.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                subtitle: Text(
                  warehouse.address,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                children:
                    warehouse.zones.map((zone) {
                      final isSelected = _selectedLocation?.id == zone.id;
                      return ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 56,
                          right: 16,
                        ),
                        leading: Icon(
                          Icons.location_on,
                          color: isSelected ? AppColors.primary : Colors.grey,
                          size: 20,
                        ),
                        title: Text(
                          zone.name,
                          style: TextStyle(
                            color: isSelected ? AppColors.primary : null,
                            fontWeight: isSelected ? FontWeight.w600 : null,
                          ),
                        ),
                        subtitle:
                            zone.code.isNotEmpty
                                ? Text(
                                  'Código: ${zone.code}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 11,
                                  ),
                                )
                                : null,
                        trailing:
                            isSelected
                                ? Icon(
                                  Icons.check_circle,
                                  color: AppColors.primary,
                                  size: 20,
                                )
                                : null,
                        onTap: () {
                          setState(() {
                            _selectedLocation = zone;
                          });
                        },
                      );
                    }).toList(),
              );
            }).toList(),
      ),
    );
  }

  String _getWarehouseName(String warehouseId) {
    final warehouse = _warehouses.firstWhere(
      (w) => w.id == warehouseId,
      orElse:
          () => Warehouse(
            id: '',
            name: 'Almacén',
            description: '',
            address: '',
            city: '',
            country: '',
            type: '',
            isActive: true,
            createdAt: DateTime.now(),
            denominacion: 'Almacén',
            direccion: '',
          ),
    );
    return warehouse.name;
  }

  List<Map<String, dynamic>> _getFilteredSelectedProducts() {
    // Always show all selected products - don't filter by location here
    // The location filtering will be applied when sending to backend
    return _selectedProducts;
  }

  String _buildVariantInfo(Map<String, dynamic> item) {
    List<String> variantParts = [];

    // Priority 1: Use stored variant_info and presentation_info (from dialog selection)
    if (item['variant_info'] != null) {
      final variantInfo = item['variant_info'];
      final atributo = variantInfo['atributo']?['denominacion'] ?? variantInfo['atributo']?['label'] ?? '';
      final opcion = variantInfo['opcion']?['valor'] ?? '';
      
      if (atributo.isNotEmpty && opcion.isNotEmpty) {
        variantParts.add('$atributo: $opcion');
      } else if (atributo.isNotEmpty) {
        variantParts.add(atributo);
      }
    }
    
    if (item['presentation_info'] != null) {
      final presentationInfo = item['presentation_info'];
      final denominacion = presentationInfo['denominacion'] ?? 
                          presentationInfo['presentacion'] ?? 
                          presentationInfo['nombre'] ?? 
                          presentationInfo['tipo'] ?? '';
      final cantidad = presentationInfo['cantidad'] ?? 1;
      
      if (denominacion.isNotEmpty) {
        variantParts.add('Presentación: $denominacion (${cantidad}x)');
      }
    }

    // Priority 2: Fallback to searching in product data (only if stored info not available)
    if (variantParts.isEmpty) {
      // Add variant information if available
      if (item['id_variante'] != null) {
        final productId = item['id_producto']?.toString();
        if (productId != null) {
          try {
            final product = _availableProducts.firstWhere(
              (p) => p.id == productId,
            );

            // Search in variantesDisponibles first
            bool found = false;
            for (final varianteDisponible in product.variantesDisponibles) {
              if (varianteDisponible['variante'] != null &&
                  varianteDisponible['variante']['id']?.toString() == item['id_variante']?.toString()) {
                final atributo = varianteDisponible['variante']['atributo']?['denominacion'] ?? 
                               varianteDisponible['variante']['atributo']?['label'] ?? '';
                
                // Check if there's a matching option
                if (item['id_opcion_variante'] != null && 
                    varianteDisponible['variante']['opciones'] != null) {
                  final opciones = varianteDisponible['variante']['opciones'] as List<dynamic>;
                  for (final opcion in opciones) {
                    if (opcion['id']?.toString() == item['id_opcion_variante']?.toString()) {
                      final opcionValor = opcion['valor'] ?? '';
                      if (atributo.isNotEmpty && opcionValor.isNotEmpty) {
                        variantParts.add('$atributo: $opcionValor');
                      }
                      found = true;
                      break;
                    }
                  }
                } else if (atributo.isNotEmpty) {
                  variantParts.add(atributo);
                  found = true;
                }
                
                if (found) break;
              }
            }

            // Fallback to inventario if not found in variantesDisponibles
            if (!found) {
              for (final inv in product.inventario) {
                if (inv['variante'] != null &&
                    inv['variante']['id']?.toString() == item['id_variante']?.toString()) {
                  final atributo = inv['variante']['atributo']?['label'] ?? '';
                  final opcion = inv['variante']['opcion']?['valor'] ?? '';
                  if (atributo.isNotEmpty && opcion.isNotEmpty) {
                    variantParts.add('$atributo: $opcion');
                  }
                  break;
                }
              }
            }
          } catch (e) {
            print('Error finding product for variant info: $e');
          }
        }
      }

      // Add presentation information if available
      if (item['id_presentacion'] != null) {
        final productId = item['id_producto']?.toString();
        if (productId != null) {
          try {
            final product = _availableProducts.firstWhere(
              (p) => p.id == productId,
            );

            // Search in presentaciones first
            bool found = false;
            for (final presentation in product.presentaciones) {
              if (presentation['id']?.toString() == item['id_presentacion']?.toString()) {
                final denominacion = presentation['denominacion'] ?? 
                                   presentation['presentacion'] ?? 
                                   presentation['nombre'] ?? 
                                   presentation['tipo'] ?? '';
                final cantidad = presentation['cantidad'] ?? 1;
                if (denominacion.isNotEmpty) {
                  variantParts.add('Presentación: $denominacion (${cantidad}x)');
                }
                found = true;
                break;
              }
            }

            // Fallback to inventario if not found in presentaciones
            if (!found) {
              for (final inv in product.inventario) {
                if (inv['presentacion'] != null &&
                    inv['presentacion']['id']?.toString() == item['id_presentacion']?.toString()) {
                  final denominacion = inv['presentacion']['denominacion'] ?? '';
                  final cantidad = inv['presentacion']['cantidad'] ?? 1;
                  if (denominacion.isNotEmpty) {
                    variantParts.add('Presentación: $denominacion (${cantidad}x)');
                  }
                  break;
                }
              }
            }
          } catch (e) {
            print('Error finding product for presentation info: $e');
          }
        }
      }
    }

    return variantParts.join(' | ');
  }
}

class _ProductQuantityDialog extends StatefulWidget {
  final Product product;
  final Function(Map<String, dynamic>) onProductAdded;

  const _ProductQuantityDialog({required this.product, required this.onProductAdded});

  @override
  State<_ProductQuantityDialog> createState() => _ProductQuantityDialogState();
}

class _ProductQuantityDialogState extends State<_ProductQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _precioUnitarioController = TextEditingController();
  final _precioReferenciaController = TextEditingController();
  final _descuentoPorcentajeController = TextEditingController();
  final _descuentoMontoController = TextEditingController();
  final _bonificacionCantidadController = TextEditingController();
  Map<String, dynamic>? _selectedVariant;
  Map<String, dynamic>? _selectedPresentation;
  List<Map<String, dynamic>> _availableVariants = [];
  List<Map<String, dynamic>> _availablePresentations = [];
  bool _advancedOptionsExpanded = false;

  void _initializeVariantsAndPresentations() {
    final variantMap = <String, Map<String, dynamic>>{};
    final presentationMap = <String, Map<String, dynamic>>{};

    print('🔍 Inicializando variantes y presentaciones para producto: ${widget.product.id}');

    // Process variants from variantesDisponibles
    if (widget.product.variantesDisponibles.isNotEmpty) {
      for (final varianteDisponible in widget.product.variantesDisponibles) {
        // Process variant
        if (varianteDisponible['variante'] != null) {
          final variant = varianteDisponible['variante'];
          
          if (variant['opciones'] != null && variant['opciones'] is List) {
            final opciones = variant['opciones'] as List<dynamic>;
            
            for (final opcion in opciones) {
              final variantKey = '${variant['id']}_${opcion['id']}';
              if (!variantMap.containsKey(variantKey)) {
                variantMap[variantKey] = {
                  'id': variant['id'],
                  'atributo': variant['atributo'],
                  'opcion': opcion,
                };
              }
            }
          } else {
            // Handle variants without specific options
            final variantKey = '${variant['id']}_no_option';
            if (!variantMap.containsKey(variantKey)) {
              variantMap[variantKey] = {
                'id': variant['id'],
                'atributo': variant['atributo'],
                'opcion': null,
              };
            }
          }
        }

        // Process presentations from variantesDisponibles
        if (varianteDisponible['presentaciones'] != null) {
          final presentaciones = varianteDisponible['presentaciones'] as List<dynamic>;
          
          for (final presentation in presentaciones) {
            final presentationKey = presentation['id'].toString();
            if (!presentationMap.containsKey(presentationKey)) {
              presentationMap[presentationKey] = presentation;
            }
          }
        }
      }
    }

    // Add direct presentations from product
    for (int i = 0; i < widget.product.presentaciones.length; i++) {
      final presentation = widget.product.presentaciones[i];
      final presentationKey = presentation['id']?.toString() ?? i.toString();
      
      if (!presentationMap.containsKey(presentationKey)) {
        presentationMap[presentationKey] = presentation;
      }
    }

    _availableVariants = variantMap.values.toList();
    _availablePresentations = presentationMap.values.toList();

    // Set defaults
    _selectedVariant = null;
    _selectedPresentation = null;
    
    // Auto-select base presentation if available
    if (_availablePresentations.isNotEmpty) {
      final basePresentation = _availablePresentations.firstWhere(
        (p) {
          final name = _getPresentationName(p).toLowerCase();
          return name.contains('base') || name.contains('unidad') || name.contains('individual');
        },
        orElse: () => _availablePresentations.first,
      );
      _selectedPresentation = basePresentation;
    }

    print('✅ Inicialización completa: ${_availableVariants.length} variantes, ${_availablePresentations.length} presentaciones');
  }

  String _getPresentationName(Map<String, dynamic> presentation) {
    return presentation['denominacion'] ?? 
           presentation['presentacion'] ?? 
           presentation['nombre'] ?? 
           presentation['tipo'] ?? 
           'Sin nombre';
  }

  Map<String, dynamic>? _findMatchingInventoryItem() {
    // Find inventory item that matches both selected variant and presentation
    for (final inventoryItem in widget.product.inventario) {
      bool variantMatches = true;
      bool presentationMatches = true;

      // Check variant match
      if (_selectedVariant != null && inventoryItem['variante'] != null) {
        final itemVariant = inventoryItem['variante'];
        
        if (variantMatches && itemVariant['id'] == _selectedVariant!['id'] &&
            itemVariant['opcion']?['id'] == _selectedVariant!['opcion']?['id']) {
          variantMatches = true;
        } else {
          variantMatches = false;
        }
      } else if (_selectedVariant != null ||
          inventoryItem['variante'] != null) {
        variantMatches = false;
      }

      // Check presentation match
      if (_selectedPresentation != null &&
          inventoryItem['presentacion'] != null) {
        presentationMatches =
            inventoryItem['presentacion']['id'] == _selectedPresentation!['id'];
      } else if (_selectedPresentation != null ||
          inventoryItem['presentacion'] != null) {
        presentationMatches = false;
      }

      if (variantMatches && presentationMatches) {
        return inventoryItem;
      }
    }

    // If no exact match, return first item as fallback
    return widget.product.inventario.isNotEmpty
        ? widget.product.inventario.first
        : null;
  }

  @override
  void initState() {
    super.initState();
    _initializeVariantsAndPresentations();
    _precioUnitarioController.text = widget.product.basePrice.toString();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _precioUnitarioController.dispose();
    _precioReferenciaController.dispose();
    _descuentoPorcentajeController.dispose();
    _descuentoMontoController.dispose();
    _bonificacionCantidadController.dispose();
    super.dispose();
  }

  void _submitForm() async {
  if (_formKey.currentState!.validate()) {
    final cantidad = double.tryParse(_quantityController.text) ?? 0;
    final precioUnitario = double.tryParse(_precioUnitarioController.text) ?? 0;
    final precioReferencia = double.tryParse(_precioReferenciaController.text) ?? 0;
    final descuentoPorcentaje = double.tryParse(_descuentoPorcentajeController.text) ?? 0;
    final descuentoMonto = double.tryParse(_descuentoMontoController.text) ?? 0;
    final bonificacionCantidad = double.tryParse(_bonificacionCantidadController.text) ?? 0;

    try {
      print('🔍 DEBUG: Presentación seleccionada: $_selectedPresentation');
      print('🔍 DEBUG: Variante seleccionada: $_selectedVariant');
      print('🔍 DEBUG: Denominación presentación: ${_selectedPresentation?['denominacion']}');
      print('🔍 DEBUG: Otros campos presentación: ${_selectedPresentation?.keys.toList()}');
      
      // Datos base del producto
      final baseProductData = {
        'id_producto': widget.product.id,
        'precio_referencia': precioReferencia,
        'descuento_porcentaje': descuentoPorcentaje,
        'descuento_monto': descuentoMonto,
        'bonificacion_cantidad': bonificacionCantidad,
        'denominacion': widget.product.name,
        'sku': widget.product.sku,
      };

      // AGREGAR INFORMACIÓN DE VARIANTES
      if (_selectedVariant != null) {
        baseProductData['id_variante'] = _selectedVariant!['id'];
        if (_selectedVariant!['opcion'] != null) {
          baseProductData['id_opcion_variante'] = _selectedVariant!['opcion']['id'];
        }
        baseProductData['variant_info'] = _selectedVariant!;
      }

      // Procesar producto con conversión automática
      final productData = await PresentationConverter.processProductForReception(
        productId: widget.product.id,
        selectedPresentation: _selectedPresentation,
        cantidad: cantidad,
        precioUnitario: precioUnitario,
        baseProductData: baseProductData,
      );

      print('🔍 DEBUG: Producto procesado: $productData');

      widget.onProductAdded(productData);
      Navigator.of(context).pop();
    } catch (e) {
      print('Error al agregar producto: $e');
    }
  }
}
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add_shopping_cart, color: AppColors.primary, size: 24),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Agregar Producto',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          widget.product.name,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product Information Section
                      _buildSection(
                        title: 'Información del Producto',
                        icon: Icons.info_outline,
                        child: Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.inventory_2,
                                  color: AppColors.primary,
                                  size: 30,
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.product.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (widget.product.sku.isNotEmpty)
                                      Text(
                                        'SKU: ${widget.product.sku}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    Text(
                                      'Stock actual: ${widget.product.stockDisponible}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      SizedBox(height: 24),
                      
                      // Datos de Entrada Section
                      _buildSection(
                        title: 'Datos de Entrada',
                        icon: Icons.input,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Presentation Selection
                            if (_availablePresentations.isNotEmpty) ...[
                              DropdownButtonFormField<Map<String, dynamic>>(
                                value: _selectedPresentation,
                                decoration: InputDecoration(
                                  labelText: 'Presentación',
                                  border: OutlineInputBorder(
                                    borderSide: BorderSide(color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: AppColors.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem<Map<String, dynamic>>(
                                    value: null,
                                    child: Text(
                                      'Sin presentación específica', 
                                      style: TextStyle(color: AppColors.textSecondary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  ..._availablePresentations.map((presentation) {
                                    return DropdownMenuItem<Map<String, dynamic>>(
                                      value: presentation,
                                      child: Text(
                                        _getPresentationName(presentation),
                                        style: TextStyle(color: AppColors.textPrimary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedPresentation = value;
                                  });
                                },
                              ),
                              SizedBox(height: 16),
                            ],
                            
                            // Variant Selection
                            if (_availableVariants.isNotEmpty) ...[
                              DropdownButtonFormField<Map<String, dynamic>>(
                                value: _selectedVariant,
                                decoration: InputDecoration(
                                  labelText: 'Variante',
                                  border: OutlineInputBorder(
                                    borderSide: BorderSide(color: AppColors.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: AppColors.border),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                isExpanded: true,
                                items: [
                                  DropdownMenuItem<Map<String, dynamic>>(
                                    value: null,
                                    child: Text(
                                      'Sin variante', 
                                      style: TextStyle(color: AppColors.textSecondary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  ..._availableVariants.map((variant) {
                                    final atributo = variant['atributo']?['denominacion'] ?? variant['atributo']?['label'] ?? '';
                                    final opcion = variant['opcion']?['valor'] ?? '';
                                    return DropdownMenuItem<Map<String, dynamic>>(
                                      value: variant,
                                      child: Text(
                                        '$atributo - $opcion', 
                                        style: TextStyle(color: AppColors.textPrimary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedVariant = value;
                                  });
                                },
                              ),
                              SizedBox(height: 16),
                            ],
                            
                            // Quantity
                            TextFormField(
                              controller: _quantityController,
                              decoration: InputDecoration(
                                labelText: 'Cantidad',
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                                ),
                                prefixIcon: Icon(Icons.inventory, color: AppColors.primary),
                              ),
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'La cantidad es obligatoria';
                                }
                                if (double.tryParse(value) == null || double.parse(value) <= 0) {
                                  return 'Ingrese una cantidad válida';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: 16),
                            
                            // Purchase Price
                            TextFormField(
                              controller: _precioUnitarioController,
                              decoration: InputDecoration(
                                labelText: 'Precio de Compra (por presentación seleccionada)',
                                hintText: 'Se convertirá automáticamente a precio base',
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                                ),
                                prefixIcon: Icon(Icons.attach_money, color: AppColors.primary),
                              ),
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'El precio de compra es obligatorio';
                                }
                                return null;
                              },
                            ),
                            
                            SizedBox(height: 24),
                            
                            // Advanced Reception Data Subsection
                            ExpansionTile(
                              title: Text(
                                'Datos Avanzados de Recepción',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              children: [
                                ListTile(
                                  title: Text(
                                    'Expandir para ver opciones avanzadas',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 12),
                                // Reference Price
                                TextFormField(
                                  controller: _precioReferenciaController,
                                  decoration: InputDecoration(
                                    labelText: 'Precio de Referencia (Opcional)',
                                    prefixText: '\$ ',
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.primary, width: 2),
                                    ),
                                    prefixIcon: Icon(Icons.price_check, color: AppColors.textSecondary),
                                  ),
                                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                                ),
                                SizedBox(height: 16),
                                
                                // Discounts Row
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _descuentoPorcentajeController,
                                        decoration: InputDecoration(
                                          labelText: 'Descuento %',
                                          border: OutlineInputBorder(
                                            borderSide: BorderSide(color: AppColors.warning),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderSide: BorderSide(color: AppColors.warning),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderSide: BorderSide(color: AppColors.warning, width: 2),
                                          ),
                                          prefixIcon: Icon(Icons.percent, color: AppColors.warning),
                                        ),
                                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _descuentoMontoController,
                                        decoration: InputDecoration(
                                          labelText: 'Descuento \$',
                                          prefixText: '\$ ',
                                          border: OutlineInputBorder(
                                            borderSide: BorderSide(color: AppColors.warning),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderSide: BorderSide(color: AppColors.warning),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderSide: BorderSide(color: AppColors.warning, width: 2),
                                          ),
                                          prefixIcon: Icon(Icons.money_off, color: AppColors.warning),
                                        ),
                                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),
                                
                                // Bonification
                                TextFormField(
                                  controller: _bonificacionCantidadController,
                                  decoration: InputDecoration(
                                    labelText: 'Bonificación (Cantidad Extra)',
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.success),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.success),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.success, width: 2),
                                    ),
                                    prefixIcon: Icon(Icons.add_circle_outline, color: AppColors.success),
                                  ),
                                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Actions
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                    ),
                  ),
                  SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Agregar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
    bool isCollapsible = false,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withOpacity(0.3)),
      ),
      child: isCollapsible
          ? ExpansionTile(
            leading: Icon(icon, color: AppColors.primary),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: child,
              ),
            ],
          )
          : Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                child,
              ],
            ),
          ),
    );
  }
}
