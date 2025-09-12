import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../models/product.dart';
import '../services/warehouse_service.dart';
import '../services/product_service.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';

class InventoryTransferScreen extends StatefulWidget {
  const InventoryTransferScreen({super.key});

  @override
  State<InventoryTransferScreen> createState() =>
      _InventoryTransferScreenState();
}

class _InventoryTransferScreenState extends State<InventoryTransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _autorizadoPorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _searchController = TextEditingController();

  // Static variables to persist field values across screen instances
  static String _lastAutorizadoPor = '';
  static String _lastObservaciones = '';

  List<Product> _availableProducts = [];
  List<Product> _filteredProducts = [];
  List<Map<String, dynamic>> _selectedProducts = [];
  List<Warehouse> _warehouses = [];
  WarehouseZone? _selectedSourceLocation;
  WarehouseZone? _selectedDestinationLocation;
  bool _isLoading = false;
  bool _isLoadingProducts = true;
  bool _isLoadingWarehouses = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
    _searchController.addListener(_onSearchChanged);

    // Load persisted values from previous entries
    _loadPersistedValues();
  }

  void _loadPersistedValues() {
    _autorizadoPorController.text = _lastAutorizadoPor;
    _observacionesController.text = _lastObservaciones;
  }

  void _savePersistedValues() {
    _lastAutorizadoPor = _autorizadoPorController.text;
    _lastObservaciones = _observacionesController.text;
  }

  @override
  void dispose() {
    _autorizadoPorController.dispose();
    _observacionesController.dispose();
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

  Future<void> _loadWarehouses() async {
    try {
      setState(() => _isLoadingWarehouses = true);
      final warehouseService = WarehouseService();
      final warehouses = await warehouseService.listWarehouses();

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

      // If source location is selected, filter products by that location
      if (_selectedSourceLocation != null) {
        final sourceLayoutId = _getZoneIdFromLocation(_selectedSourceLocation!);
        final sourceWarehouseId = _getWarehouseIdFromLocation(
          _selectedSourceLocation!,
        );

        print('🔍 Cargando productos filtrados por ubicación origen...');
        print('📍 Layout ID: $sourceLayoutId');
        print('🏭 Warehouse ID: $sourceWarehouseId');

        // Use InventoryService to get products filtered by location
        final inventoryResponse = await InventoryService.getInventoryProducts(
          idAlmacen: sourceWarehouseId,
          idUbicacion: sourceLayoutId,
          mostrarSinStock: false, // Only show products with stock
        );

        // Convert InventoryProduct to Product for UI compatibility
        final products =
            inventoryResponse.products
                .map((inventoryProduct) {
                  return Product(
                    id: inventoryProduct.id.toString(),
                    name: inventoryProduct.nombreProducto,
                    denominacion: inventoryProduct.nombreProducto,
                    description: inventoryProduct.subcategoria,
                    categoryId: inventoryProduct.idCategoria.toString(),
                    categoryName: inventoryProduct.categoria,
                    brand: '', // No disponible en InventoryProduct
                    sku: inventoryProduct.skuProducto,
                    barcode: '', // No disponible en InventoryProduct
                    basePrice: inventoryProduct.precioVenta ?? 0.0,
                    imageUrl:
                        'https://picsum.photos/200/200?random=${inventoryProduct.id}',
                    isActive: inventoryProduct.esVendible,
                    createdAt: inventoryProduct.fechaUltimaActualizacion,
                    updatedAt: inventoryProduct.fechaUltimaActualizacion,
                    variants: [], // No disponible en InventoryProduct
                    nombreComercial: inventoryProduct.nombreProducto,
                    um: '', // No disponible en InventoryProduct
                    esRefrigerado: false, // No disponible en InventoryProduct
                    esFragil: false, // No disponible en InventoryProduct
                    esPeligroso: false, // No disponible en InventoryProduct
                    esVendible: inventoryProduct.esVendible,
                    stockDisponible: inventoryProduct.cantidadFinal.toInt(),
                    tieneStock: inventoryProduct.cantidadFinal > 0,
                    subcategorias: [], // No disponible en InventoryProduct
                    presentaciones: [], // No disponible en InventoryProduct
                    multimedias: [], // No disponible en InventoryProduct
                    etiquetas: [], // No disponible en InventoryProduct
                    inventario: [], // No disponible en InventoryProduct
                  );
                })
                .where((product) => product.stockDisponible > 0)
                .toList(); // Solo productos con stock

        setState(() {
          _availableProducts = products;
          _filteredProducts = products;
          _isLoadingProducts = false;
        });

        print('✅ Productos cargados: ${products.length} con stock disponible');
      } else {
        // No source location selected, load all products
        final products = await ProductService.getProductsByTienda();
        setState(() {
          _availableProducts = products;
          _filteredProducts = products;
          _isLoadingProducts = false;
        });

        print('✅ Productos generales cargados: ${products.length}');
      }
    } catch (e) {
      setState(() => _isLoadingProducts = false);
      print('❌ Error al cargar productos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar productos: $e')),
        );
      }
    }
  }

  void _addProductToTransfer(Product product) {
    showDialog(
      context: context,
      builder:
          (context) => _ProductQuantityDialog(
            product: product,
            sourceLayoutId: _getZoneIdFromLocation(_selectedSourceLocation!),
            onAdd: (productData) {
              setState(() {
                _selectedProducts.add(productData);
              });
              Navigator.pop(context);
            },
          ),
    );
  }

  void _removeProduct(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
    });
  }

  Future<void> _submitTransfer() async {
    if (!_formKey.currentState!.validate() || _selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete todos los campos y agregue al menos un producto',
          ),
        ),
      );
      return;
    }

    if (_selectedSourceLocation == null ||
        _selectedDestinationLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar ubicaciones de origen y destino'),
        ),
      );
      return;
    }

    // Validate that source and destination are different
    if (_selectedSourceLocation!.id == _selectedDestinationLocation!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Las ubicaciones de origen y destino no pueden ser las mismas',
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

      // ========== LOGGING DE DATOS DEL FORMULARIO ==========
      print('🔍 ===== DATOS DEL FORMULARIO DE TRANSFERENCIA =====');
      print('👤 Usuario UUID: $userUuid');
      print('🏪 ID Tienda: $idTienda');
      print('📝 Autorizado por: ${_autorizadoPorController.text}');
      print('📋 Observaciones: ${_observacionesController.text}');
      print(
        '📍 Ubicación origen: ${_selectedSourceLocation!.displayName} (ID: ${_selectedSourceLocation!.id})',
      );
      print(
        '📍 Ubicación destino: ${_selectedDestinationLocation!.displayName} (ID: ${_selectedDestinationLocation!.id})',
      );
      print('📦 Productos seleccionados (${_selectedProducts.length}):');

      for (int i = 0; i < _selectedProducts.length; i++) {
        final product = _selectedProducts[i];
        print('   [$i] Producto:');
        print('       - ID Producto: ${product['id_producto']}');
        print('       - Nombre: ${product['nombre_producto']}');
        print('       - Cantidad: ${product['cantidad']}');
        print('       - Precio Unitario: ${product['precio_unitario']}');
        print('       - ID Variante: ${product['id_variante']}');
        print('       - Variante: ${product['variante_nombre']}');
        print('       - ID Opción Variante: ${product['id_opcion_variante']}');
        print('       - Opción: ${product['opcion_variante_nombre']}');
        print('       - ID Presentación: ${product['id_presentacion']}');
        print('       - Presentación: ${product['presentacion_nombre']}');
      }
      print('================================================');

      // Prepare products list for transfer
      final productosParaEnviar =
          _selectedProducts.map((product) {
            return {
              'id_producto': product['id_producto'],
              'cantidad': product['cantidad'],
              'precio_unitario': product['precio_unitario'] ?? 0.0,
              'id_variante': product['id_variante'],
              'id_presentacion': product['id_presentacion'],
            };
          }).toList();

      print('📤 Productos preparados para envío:');
      for (int i = 0; i < productosParaEnviar.length; i++) {
        print('   [$i] ${productosParaEnviar[i]}');
      }

      // Extract warehouse IDs from location IDs
      final sourceWarehouseId = _getWarehouseIdFromLocation(
        _selectedSourceLocation!,
      );
      final destinationWarehouseId = _getWarehouseIdFromLocation(
        _selectedDestinationLocation!,
      );

      print('🏭 ID Almacén Origen: $sourceWarehouseId');
      print('🏭 ID Almacén Destino: $destinationWarehouseId');

      // Extract layout IDs from location objects
      final sourceLayoutId = _getZoneIdFromLocation(_selectedSourceLocation!);
      final destinationLayoutId = _getZoneIdFromLocation(
        _selectedDestinationLocation!,
      );

      print('🔄 Iniciando transferencia unificada entre layouts...');
      print('📞 Llamando a: InventoryService.transferBetweenLayouts');
      print('📋 Parámetros:');
      print('   - idLayoutOrigen: $sourceLayoutId');
      print('   - idLayoutDestino: $destinationLayoutId');
      print('   - productos: $productosParaEnviar');
      print('   - autorizadoPor: ${_autorizadoPorController.text}');
      print('   - observaciones: ${_observacionesController.text}');

      // Use unified transfer function for all scenarios
      final result = await InventoryService.transferBetweenLayouts(
        idLayoutOrigen: sourceLayoutId,
        idLayoutDestino: destinationLayoutId,
        productos: productosParaEnviar,
        autorizadoPor: _autorizadoPorController.text,
        observaciones: _observacionesController.text,
        estadoInicial: 1, // Pendiente - can be confirmed later
      );

      print('📥 Resultado de la transferencia: $result');

      // Complete both operations automatically if transfer was successful
      if (result['status'] == 'success') {
        final idExtraccion = result['id_extraccion'];
        final idRecepcion = result['id_recepcion'];

        if (idExtraccion != null && idRecepcion != null) {
          try {
            print('🔄 Completando operación de extracción...');
            print('📊 ID Extracción: $idExtraccion');

            final completeExtractionResult =
                await InventoryService.completeOperation(
                  idOperacion: idExtraccion,
                  comentario:
                      'Extracción de transferencia completada automáticamente - ${_observacionesController.text.trim()}',
                  uuid: userUuid,
                );

            print(
              '📋 Resultado completeOperation (extracción): $completeExtractionResult',
            );

            if (completeExtractionResult['status'] == 'success') {
              print('✅ Extracción completada exitosamente');
              print(
                '📊 Productos afectados (extracción): ${completeExtractionResult['productos_afectados']}',
              );
            } else {
              print(
                '⚠️ Advertencia al completar extracción: ${completeExtractionResult['message']}',
              );
            }

            print('🔄 Completando operación de recepción...');
            print('📊 ID Recepción: $idRecepcion');

            final completeReceptionResult =
                await InventoryService.completeOperation(
                  idOperacion: idRecepcion,
                  comentario:
                      'Recepción de transferencia completada automáticamente - ${_observacionesController.text.trim()}',
                  uuid: userUuid,
                );

            print(
              '📋 Resultado completeOperation (recepción): $completeReceptionResult',
            );

            if (completeReceptionResult['status'] == 'success') {
              print('✅ Recepción completada exitosamente');
              print(
                '📊 Productos afectados (recepción): ${completeReceptionResult['productos_afectados']}',
              );
            } else {
              print(
                '⚠️ Advertencia al completar recepción: ${completeReceptionResult['message']}',
              );
            }
          } catch (completeError, stackTrace) {
            print(
              '❌ Error al completar operaciones de transferencia: $completeError',
            );
            print('📍 StackTrace completo: $stackTrace');
            // Don't throw here - transfer was successful, completion is secondary
          }
        } else {
          print('⚠️ No se obtuvieron IDs de operaciones para completar');
        }

        // Save the values for future use before showing success message
        _savePersistedValues();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ?? 'Transferencia registrada exitosamente',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      } else {
        throw Exception(
          result['message'] ?? 'Error desconocido en la transferencia',
        );
      }
    } catch (e) {
      print('❌ Error en _submitTransfer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar transferencia: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Extract warehouse ID from location object
  int _getWarehouseIdFromLocation(WarehouseZone location) {
    // Try to get warehouse ID from the location's warehouse property
    if (location.warehouseId != null) {
      return int.tryParse(location.warehouseId) ?? 1;
    }

    // Fallback: find warehouse by looking through all warehouses
    for (final warehouse in _warehouses) {
      if (warehouse.zones.any((zone) => zone.id == location.id)) {
        return int.tryParse(warehouse.id) ?? 1;
      }
    }

    // Default fallback
    return 1;
  }

  /// Extract zone ID from location object
  int _getZoneIdFromLocation(WarehouseZone location) {
    // Clean the location ID if it has prefixes
    String cleanId = location.id;
    if (cleanId.startsWith('z') || cleanId.startsWith('w')) {
      cleanId = cleanId.substring(1);
    }
    return int.tryParse(cleanId) ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Transferencia de Inventario',
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
                    _buildTransferInfoSection(),
                    const SizedBox(height: 24),
                    _buildSourceLocationSection(),
                    const SizedBox(height: 24),
                    _buildDestinationLocationSection(),
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

  Widget _buildTransferInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información de Transferencia',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _autorizadoPorController,
              decoration: const InputDecoration(
                labelText: 'Autorizado por',
                border: OutlineInputBorder(),
              ),
              validator:
                  (value) => value?.isEmpty == true ? 'Campo requerido' : null,
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
          ],
        ),
      ),
    );
  }

  Widget _buildSourceLocationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ubicación de Origen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _isLoadingWarehouses
                ? const Center(child: CircularProgressIndicator())
                : _buildWarehouseTree(isSource: true),
            if (_selectedSourceLocation != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.output, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Origen:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _selectedSourceLocation?.name ?? 'No seleccionado',
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

  Widget _buildDestinationLocationSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ubicación de Destino',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _isLoadingWarehouses
                ? const Center(child: CircularProgressIndicator())
                : _buildWarehouseTree(isSource: false),
            if (_selectedDestinationLocation != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.input, color: AppColors.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Destino:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            _selectedDestinationLocation?.name ??
                                'No seleccionado',
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
                              onPressed: () => _addProductToTransfer(product),
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
                itemCount: _selectedProducts.length,
                itemBuilder: (context, index) {
                  final item = _selectedProducts[index];
                  return ListTile(
                    title: Text(item['nombre_producto']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cantidad: ${item['cantidad']}'),
                        if (_buildVariantInfo(item).isNotEmpty)
                          Text(
                            _buildVariantInfo(item),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.remove_circle,
                        color: AppColors.error,
                      ),
                      onPressed: () => _removeProduct(index),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
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
                'Total productos:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${_selectedProducts.length}',
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
              onPressed: _isLoading ? null : _submitTransfer,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child:
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                        'Registrar Transferencia',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseTree({required bool isSource}) {
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
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${warehouse.zones.length} zonas'),
                children:
                    warehouse.zones.map((zone) {
                      final isSelected =
                          isSource
                              ? _selectedSourceLocation?.id == zone.id
                              : _selectedDestinationLocation?.id == zone.id;

                      return ListTile(
                        leading: Icon(
                          Icons.layers,
                          color: isSelected ? AppColors.primary : Colors.grey,
                        ),
                        title: Text(zone.name),
                        subtitle:
                            zone.code.isNotEmpty
                                ? Text('Código: ${zone.code}')
                                : null,
                        selected: isSelected,
                        onTap: () {
                          setState(() {
                            if (isSource) {
                              _selectedSourceLocation = zone;
                              _loadProducts();
                            } else {
                              _selectedDestinationLocation = zone;
                            }
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
            id: warehouseId,
            name: 'Almacén desconocido',
            description: 'Almacén no encontrado',
            address: '',
            city: '',
            country: 'Chile',
            type: 'principal',
            createdAt: DateTime.now(),
            zones: [],
            denominacion: 'Almacén desconocido',
            direccion: '',
          ),
    );
    return warehouse.name;
  }

  String _buildVariantInfo(Map<String, dynamic> item) {
    List<String> info = [];

    if (item['variante_nombre'] != null &&
        item['variante_nombre'].toString().isNotEmpty) {
      info.add('Variante: ${item['variante_nombre']}');
    }

    if (item['opcion_variante_nombre'] != null &&
        item['opcion_variante_nombre'].toString().isNotEmpty) {
      info.add('Opción: ${item['opcion_variante_nombre']}');
    }

    if (item['presentacion_nombre'] != null &&
        item['presentacion_nombre'].toString().isNotEmpty) {
      info.add('Presentación: ${item['presentacion_nombre']}');
    }

    return info.join(' | ');
  }
}

// Product Quantity Dialog - Enhanced with location-specific variants
class _ProductQuantityDialog extends StatefulWidget {
  final Product product;
  final Function(Map<String, dynamic>) onAdd;
  final int? sourceLayoutId; // ID de la ubicación origen para filtrar variantes

  const _ProductQuantityDialog({
    required this.product,
    required this.onAdd,
    this.sourceLayoutId,
  });

  @override
  State<_ProductQuantityDialog> createState() => _ProductQuantityDialogState();
}

class _ProductQuantityDialogState extends State<_ProductQuantityDialog> {
  final _quantityController = TextEditingController(text: '1');
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _selectedVariant;
  List<Map<String, dynamic>> _availableVariants = [];
  bool _isLoadingVariants = false;
  double _maxAvailableStock = 0.0;

  @override
  void initState() {
    super.initState();
    _loadLocationSpecificVariants();
  }

  Future<void> _loadLocationSpecificVariants() async {
    if (widget.sourceLayoutId == null) {
      print('⚠️ No se especificó ubicación origen, usando datos genéricos');
      _initializeFallbackVariants();
      return;
    }

    setState(() => _isLoadingVariants = true);

    try {
      print('🔍 Cargando variantes específicas de la ubicación...');
      final variants = await InventoryService.getProductVariantsInLocation(
        idProducto: int.parse(widget.product.id),
        idLayout: widget.sourceLayoutId!,
      );

      if (variants.isEmpty) {
        print('⚠️ No se encontraron variantes con stock en esta ubicación');
        _initializeFallbackVariants();
        return;
      }

      setState(() {
        _availableVariants = variants;
        _selectedVariant = variants.first;
        _maxAvailableStock = _selectedVariant!['stock_disponible'];
        _isLoadingVariants = false;
      });

      print('✅ Cargadas ${variants.length} variantes con stock');
    } catch (e) {
      print('❌ Error cargando variantes: $e');
      _initializeFallbackVariants();
    }
  }

  void _initializeFallbackVariants() {
    // Fallback usando datos del producto base
    setState(() {
      _availableVariants = [
        {
          'id_producto': int.parse(widget.product.id),
          'nombre_producto': widget.product.name,
          'sku_producto': widget.product.sku,
          'id_variante': null,
          'variante_nombre': 'Sin variante',
          'id_opcion_variante': null,
          'opcion_variante_nombre': 'Única',
          'id_presentacion': null,
          'presentacion_nombre': 'Unidad',
          'presentacion_codigo': 'UN',
          'stock_disponible': widget.product.stockDisponible.toDouble(),
          'stock_reservado': 0.0,
          'stock_actual': widget.product.stockDisponible.toDouble(),
          'precio_unitario': widget.product.basePrice,
          'variant_key': 'null_null_null',
        },
      ];
      _selectedVariant = _availableVariants.first;
      _maxAvailableStock = _selectedVariant!['stock_disponible'];
      _isLoadingVariants = false;
    });
  }

  void _onVariantChanged(Map<String, dynamic>? variant) {
    if (variant != null) {
      setState(() {
        _selectedVariant = variant;
        _maxAvailableStock = variant['stock_disponible'];
        // Reset quantity if it exceeds new max
        final currentQuantity = double.tryParse(_quantityController.text) ?? 1;
        if (currentQuantity > _maxAvailableStock) {
          _quantityController.text = _maxAvailableStock.toInt().toString();
        }
      });
    }
  }

  String _buildVariantDisplayName(Map<String, dynamic> variant) {
    List<String> parts = [];

    if (variant['variante_nombre'] != null &&
        variant['variante_nombre'] != 'Sin variante') {
      parts.add(variant['variante_nombre']);
    }

    if (variant['opcion_variante_nombre'] != null &&
        variant['opcion_variante_nombre'] != 'Única') {
      parts.add(variant['opcion_variante_nombre']);
    }

    if (variant['presentacion_nombre'] != null) {
      parts.add(variant['presentacion_nombre']);
    }

    final displayName = parts.isEmpty ? 'Estándar' : parts.join(' - ');
    final stock = variant['stock_disponible'].toInt();

    return '$displayName (Stock: $stock)';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Agregar ${widget.product.name}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Información del producto
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (widget.product.sku.isNotEmpty)
                            Text(
                              'SKU: ${widget.product.sku}',
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
              const SizedBox(height: 16),

              // Selector de variantes/presentaciones
              if (_isLoadingVariants)
                const CircularProgressIndicator()
              else if (_availableVariants.isNotEmpty) ...[
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedVariant,
                  decoration: const InputDecoration(
                    labelText: 'Variante / Presentación',
                    border: OutlineInputBorder(),
                    helperText:
                        'Seleccione la variante específica a transferir',
                  ),
                  items:
                      _availableVariants.map((variant) {
                        return DropdownMenuItem(
                          value: variant,
                          child: Text(_buildVariantDisplayName(variant)),
                        );
                      }).toList(),
                  onChanged: _onVariantChanged,
                  validator:
                      (value) =>
                          value == null ? 'Seleccione una variante' : null,
                ),
                const SizedBox(height: 16),
              ],

              // Campo de cantidad con validación
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  border: const OutlineInputBorder(),
                  helperText:
                      _maxAvailableStock > 0
                          ? 'Máximo disponible: ${_maxAvailableStock.toInt()}'
                          : 'Sin stock disponible',
                  helperStyle: TextStyle(
                    color: _maxAvailableStock > 0 ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty == true) return 'Campo requerido';
                  final quantity = double.tryParse(value!);
                  if (quantity == null || quantity <= 0) {
                    return 'Ingrese una cantidad válida';
                  }
                  if (quantity > _maxAvailableStock) {
                    return 'Cantidad excede el stock disponible (${_maxAvailableStock.toInt()})';
                  }
                  return null;
                },
              ),

              // Información adicional del stock
              if (_selectedVariant != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Stock disponible:',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${_selectedVariant!['stock_disponible'].toInt()}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      if (_selectedVariant!['stock_reservado'] > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Stock reservado:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${_selectedVariant!['stock_reservado'].toInt()}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _maxAvailableStock <= 0
                  ? null
                  : () {
                    if (_formKey.currentState!.validate() &&
                        _selectedVariant != null) {
                      final productData = {
                        'id_producto': _selectedVariant!['id_producto'],
                        'nombre_producto': _selectedVariant!['nombre_producto'],
                        'cantidad': double.parse(_quantityController.text),
                        'precio_unitario': _selectedVariant!['precio_unitario'],
                        'id_variante': _selectedVariant!['id_variante'],
                        'variante_nombre': _selectedVariant!['variante_nombre'],
                        'id_opcion_variante':
                            _selectedVariant!['id_opcion_variante'],
                        'opcion_variante_nombre':
                            _selectedVariant!['opcion_variante_nombre'],
                        'id_presentacion': _selectedVariant!['id_presentacion'],
                        'presentacion_nombre':
                            _selectedVariant!['presentacion_nombre'],
                        'stock_disponible':
                            _selectedVariant!['stock_disponible'],
                        'variant_key': _selectedVariant!['variant_key'],
                      };
                      widget.onAdd(productData);
                    }
                  },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
