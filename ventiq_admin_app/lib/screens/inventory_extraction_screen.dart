import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../models/inventory.dart';
import '../services/warehouse_service.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';

class InventoryExtractionScreen extends StatefulWidget {
  const InventoryExtractionScreen({super.key});

  @override
  State<InventoryExtractionScreen> createState() =>
      _InventoryExtractionScreenState();
}

class _InventoryExtractionScreenState extends State<InventoryExtractionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _autorizadoPorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _searchController = TextEditingController();

  // Static variables to persist field values
  static String _lastAutorizadoPor = '';
  static String _lastObservaciones = '';

  List<InventoryProduct> _availableProducts = [];
  List<InventoryProduct> _filteredProducts = [];
  List<Map<String, dynamic>> _selectedProducts = [];
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  List<Warehouse> _warehouses = [];
  WarehouseZone? _selectedSourceLocation;
  String? _selectedWarehouseName; // Store warehouse name for display
  bool _isLoading = false;
  bool _isLoadingProducts = true;
  bool _isLoadingMotivos = true;
  bool _isLoadingWarehouses = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
    _loadMotivoOptions();
    _searchController.addListener(_onSearchChanged);
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

  void _addProductToExtraction(InventoryProduct product) {
    showDialog(
      context: context,
      builder:
          (context) => _ProductQuantityDialog(
            product: product,
            sourceLayoutId:
                _selectedSourceLocation?.id != null
                    ? int.tryParse(_selectedSourceLocation!.id)
                    : null,
            warehouseName: _selectedWarehouseName,
            onAdd: (productData) {
              setState(() {
                _selectedProducts.add(productData);
              });
              Navigator.pop(context);
            },
          ),
    );
  }

  void _removeProductFromExtraction(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
    });
  }

  void _showExtractionConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              'Confirmar Extracción',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ubicación origen
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: AppColors.warning.withOpacity(0.7),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Zona de Origen:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _selectedWarehouseName ?? 'No seleccionada',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                _selectedSourceLocation?.name ??
                                    'No seleccionada',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Lista de productos
                  const Text(
                    'Productos a Extraer:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ..._selectedProducts.map((productData) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productData['nombreProducto'],
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (productData['variante'] != null &&
                              productData['variante'].toString().isNotEmpty)
                            Text(
                              'Variante: ${productData['variante']}',
                              style: TextStyle(
                                color: AppColors.warning.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          if (productData['presentacion'] != null &&
                              productData['presentacion'].toString().isNotEmpty)
                            Text(
                              'Presentación: ${productData['presentacion']}',
                              style: TextStyle(
                                color: AppColors.warning.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          Text(
                            'Cantidad: ${productData['cantidad']}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Zona: ${productData['zona_nombre']}',
                            style: TextStyle(
                              color: AppColors.warning.withOpacity(0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 16),

                  // Motivo y autorizado por
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.warning.withOpacity(0.7),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Información Adicional:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Motivo: ${_selectedMotivo?['denominacion'] ?? 'No seleccionado'}',
                        ),
                        Text(
                          'Autorizado por: ${_autorizadoPorController.text.isEmpty ? 'No especificado' : _autorizadoPorController.text}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _submitExtraction();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                ),
                child: const Text('Confirmar Extracción'),
              ),
            ],
          ),
    );
  }

  Future<void> _submitExtraction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar al menos un producto')),
      );
      return;
    }
    if (_selectedSourceLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar una zona de origen')),
      );
      return;
    }
    if (_selectedMotivo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un motivo de extracción'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _savePersistedValues();

    try {
      final userPrefs = UserPreferencesService();
      final userUuid = await userPrefs.getUserId();
      final userData = await userPrefs.getUserData();
      final idTienda = userData['idTienda'] as int?;

      if (userUuid == null || idTienda == null) {
        throw Exception('No se encontró información del usuario o tienda');
      }

      // Prepare products list for the RPC
      final productos =
          _selectedProducts
              .map(
                (product) => {
                  'id_producto': product['id_producto'],
                  'id_variante': product['id_variante'],
                  'id_opcion_variante': product['id_opcion_variante'],
                  'id_ubicacion': product['id_ubicacion'],
                  'id_presentacion': product['id_presentacion'],
                  'cantidad': product['cantidad'],
                  'precio_unitario': product['precio_unitario'],
                  'sku_producto': product['sku_producto'],
                  'sku_ubicacion': product['sku_ubicacion'],
                },
              )
              .toList();

      final result = await InventoryService.insertCompleteExtraction(
        autorizadoPor: _autorizadoPorController.text.trim(),
        estadoInicial: 1, // 2 = Confirmado (completed immediately)
        idMotivoOperacion: _selectedMotivo!['id'],
        idTienda: idTienda,
        observaciones: _observacionesController.text.trim(),
        productos: productos,
        uuid: userUuid,
      );

      if (result['status'] != 'success') {
        throw Exception(result['message'] ?? 'Error desconocido');
      }

      final operationId = result['id_operacion'];
      print('✅ Extracción registrada con ID: $operationId');

      // Complete the operation after successful extraction
      if (operationId != null) {
        try {
          print('🔄 Iniciando completar operación...');
          print('📊 ID Operación: $operationId');
          print('👤 UUID Usuario: $userUuid');

          final completeResult = await InventoryService.completeOperation(
            idOperacion: operationId,
            comentario:
                'Extracción completada automáticamente - ${_observacionesController.text.trim()}',
            uuid: userUuid,
          );

          print('📋 Resultado completeOperation: $completeResult');

          if (completeResult['status'] == 'success') {
            print('✅ Operación completada exitosamente');
            print(
              '📊 Productos afectados: ${completeResult['productos_afectados']}',
            );
          } else {
            print(
              '⚠️ Advertencia al completar operación: ${completeResult['message']}',
            );
            print('🔍 Detalles del error: $completeResult');
          }
        } catch (completeError, stackTrace) {
          print('❌ Error al completar operación: $completeError');
          print('📍 StackTrace completo: $stackTrace');
          // Don't throw here - extraction was successful, completion is secondary
        }
      } else {
        print('⚠️ No se obtuvo ID de operación para completar');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Extracción registrada exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar extracción: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMotivoOptions() async {
    setState(() => _isLoadingMotivos = true);

    try {
      // Load extraction motives from Supabase database
      _motivoOptions = await InventoryService.getMotivoExtraccionOptions();

      setState(() => _isLoadingMotivos = false);
    } catch (e) {
      print('Error loading motivo options: $e');
      setState(() => _isLoadingMotivos = false);
    }
  }

  Future<void> _loadWarehouses() async {
    setState(() => _isLoadingWarehouses = true);

    try {
      final warehouseService = WarehouseService();
      final warehouses = await warehouseService.listWarehouses();

      setState(() {
        _warehouses = warehouses;
        _isLoadingWarehouses = false;
      });
    } catch (e) {
      print('Error loading warehouses: $e');
      setState(() => _isLoadingWarehouses = false);
    }
  }

  Future<void> _loadProductsForLocation() async {
    if (_selectedSourceLocation == null) return;

    setState(() => _isLoadingProducts = true);

    try {
      final response = await InventoryService.getInventoryProducts(
        idUbicacion: int.tryParse(_selectedSourceLocation!.id),
        mostrarSinStock: false, // Only show products with stock for extraction
      );

      // Group products to eliminate duplicates - take first occurrence only
      final Map<int, InventoryProduct> groupedProducts = {};
      
      for (final product in response.products) {
        final productId = product.id;
        
        if (!groupedProducts.containsKey(productId)) {
          // First occurrence of this product - take it as is
          groupedProducts[productId] = product;
          print('📦 Producto agregado: ${product.nombreProducto} - Stock: ${product.stockDisponible}');
        } else {
          // Product already exists - ignore duplicate
          print('📦 Producto duplicado ignorado: ${product.nombreProducto}');
        }
      }

      // Convert grouped products back to list
      final uniqueProducts = groupedProducts.values.toList();
      
      print('📊 Productos antes de agrupar: ${response.products.length}');
      print('📊 Productos después de agrupar: ${uniqueProducts.length}');

      setState(() {
        _availableProducts = uniqueProducts;
        _filteredProducts = uniqueProducts;
        _isLoadingProducts = false;
      });

      // Apply current search filter if any
      if (_searchQuery.isNotEmpty) {
        _filterProducts();
      }
    } catch (e) {
      print('Error loading products for location: $e');
      setState(() => _isLoadingProducts = false);

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando productos: $e')));
      }
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
    _filterProducts();
  }

  void _filterProducts() {
    if (_searchQuery.isEmpty) {
      setState(() {
        _filteredProducts = _availableProducts;
      });
    } else {
      setState(() {
        _filteredProducts =
            _availableProducts.where((product) {
              return product.skuProducto.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ||
                  product.nombreProducto.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  );
            }).toList();
      });
    }
  }

  Widget _buildWarehouseTree() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
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
                  style: TextStyle(
                    color: AppColors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                children:
                    warehouse.zones.map((zone) {
                      final isSelected = _selectedSourceLocation?.id == zone.id;
                      return ListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 56,
                          right: 16,
                        ),
                        leading: Icon(
                          Icons.location_on,
                          color:
                              isSelected ? AppColors.primary : AppColors.grey,
                          size: 20,
                        ),
                        title: Text(
                          '${warehouse.name} - ${zone.name}',
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
                                    color: AppColors.grey.shade600,
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
                            _selectedSourceLocation = zone;
                            _selectedWarehouseName = warehouse.name;
                          });
                          _loadProductsForLocation();
                        },
                      );
                    }).toList(),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildProductsList() {
    if (_filteredProducts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.grey),
            SizedBox(height: 16),
            Text(
              'No hay productos disponibles\nen esta ubicación',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.inventory_2,
                color: AppColors.warning.withOpacity(0.6),
                size: 24,
              ),
            ),
            title: Text(
              product.nombreProducto,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SKU: ${product.skuProducto}'),
                Text('Categoría: ${product.categoria}'),
              ],
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.add_circle,
                color: AppColors.warning.withOpacity(0.6),
              ),
              onPressed: () => _addProductToExtraction(product),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: AppColors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected products summary with improved design
          if (_selectedProducts.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Productos Seleccionados: ${_selectedProducts.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                      if (_selectedProducts.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedProducts.clear();
                            });
                          },
                          icon: Icon(
                            Icons.clear_all,
                            size: 16,
                            color: AppColors.warning.withOpacity(0.6),
                          ),
                          label: Text(
                            'Limpiar',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.warning.withOpacity(0.6),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Lista expandible de productos
                  ...(_selectedProducts.length <= 3
                          ? _selectedProducts
                          : _selectedProducts.take(2).toList())
                      .asMap()
                      .entries
                      .map((entry) {
                        final index = entry.key;
                        final product = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.warning.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${product['nombreProducto']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.warning.withOpacity(
                                          0.7,
                                        ),
                                      ),
                                    ),
                                    if (product['nombreAlmacen'] != null &&
                                        product['nombreZona'] != null)
                                      Text(
                                        '${product['nombreAlmacen']} - ${product['nombreZona']}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.warning.withOpacity(
                                            0.5,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      'Cant: ${product['cantidad']} • N/A',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.warning.withOpacity(
                                          0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed:
                                    () => _removeProductFromExtraction(index),
                                icon: Icon(
                                  Icons.remove_circle,
                                  color: AppColors.warning.withOpacity(0.4),
                                  size: 18,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  if (_selectedProducts.length > 3) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        // Mostrar diálogo con todos los productos
                        _showAllSelectedProducts();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.expand_more,
                              size: 16,
                              color: AppColors.warning.withOpacity(0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ver ${_selectedProducts.length - 2} productos más',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.warning.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Form fields
          Row(
            children: [
              // Motivo dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Motivo de Extracción',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      value: _selectedMotivo,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      hint: const Text('Seleccionar motivo'),
                      items:
                          _motivoOptions.map((motivo) {
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: motivo,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  '${motivo['denominacion']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            );
                          }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedMotivo = value;
                        });
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'Requerido';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Autorizado por field
          TextFormField(
            controller: _autorizadoPorController,
            decoration: InputDecoration(
              labelText: 'Autorizado por',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Este campo es requerido';
              }
              return null;
            },
          ),

          const SizedBox(height: 12),

          // Observaciones field
          TextFormField(
            controller: _observacionesController,
            decoration: InputDecoration(
              labelText: 'Observaciones (opcional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 16),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _selectedProducts.isEmpty
                      ? null
                      : _showExtractionConfirmation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _selectedProducts.isEmpty
                    ? 'Seleccione productos para extraer'
                    : 'Procesar Extracción (${_selectedProducts.length} productos)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllSelectedProducts() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Productos Seleccionados (${_selectedProducts.length})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.warning.withOpacity(0.7),
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _selectedProducts.length,
                itemBuilder: (context, index) {
                  final product = _selectedProducts[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['denominacion'] ??
                                    'Producto sin nombre',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'Cantidad: ${product['cantidad']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.warning.withOpacity(0.6),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    ' • ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.warning.withOpacity(0.6),
                                    ),
                                  ),
                                  Text(
                                    '${product['zona_nombre'] ?? 'N/A'}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.warning.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            _removeProductFromExtraction(index);
                            Navigator.pop(context);
                            if (_selectedProducts.length <= 3) {
                              // If we're back to 3 or fewer products, close the dialog
                              return;
                            }
                            // Refresh the dialog if there are still more than 3 products
                            _showAllSelectedProducts();
                          },
                          icon: Icon(
                            Icons.remove_circle,
                            color: AppColors.warning.withOpacity(0.4),
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cerrar',
                  style: TextStyle(color: AppColors.warning.withOpacity(0.6)),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Extracción de Productos',
          style: TextStyle(
            color: AppColors.background,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.warning,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.background),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Header compacto con zona seleccionada
                    if (_selectedSourceLocation != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          border: Border(
                            bottom: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Zona: $_selectedWarehouseName - ${_selectedSourceLocation!.name}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedSourceLocation = null;
                                  _selectedWarehouseName = null;
                                });
                              },
                              icon: const Icon(Icons.change_circle, size: 16),
                              label: const Text(
                                'Cambiar',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Selector de zona O lista de productos
                    Expanded(
                      child:
                          _selectedSourceLocation == null
                              ? Column(
                                children: [
                                  // Header para selección de zona
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.grey.withOpacity(
                                            0.1,
                                          ),
                                          spreadRadius: 1,
                                          blurRadius: 3,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          size: 20,
                                          color: AppColors.grey.shade600,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Seleccione la zona de origen',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Árbol de zonas con expansión completa
                                  Expanded(
                                    child:
                                        _isLoadingWarehouses
                                            ? const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            )
                                            : SingleChildScrollView(
                                              padding: const EdgeInsets.all(16),
                                              child: _buildWarehouseTree(),
                                            ),
                                  ),
                                ],
                              )
                              : Column(
                                children: [
                                  // Search bar
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    color: AppColors.background,
                                    child: TextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        hintText: 'Buscar productos...',
                                        prefixIcon: const Icon(
                                          Icons.search,
                                          size: 20,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide(
                                            color: AppColors.border,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                      ),
                                    ),
                                  ),

                                  // Products list con espacio completo
                                  Expanded(
                                    child:
                                        _isLoadingProducts
                                            ? const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            )
                                            : _buildProductsList(),
                                  ),
                                ],
                              ),
                    ),
                  ],
                ),
              ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }
}

class _ProductQuantityDialog extends StatefulWidget {
  final InventoryProduct product;
  final int? sourceLayoutId;
  final String? warehouseName;
  final Function(Map<String, dynamic>) onAdd;

  const _ProductQuantityDialog({
    required this.product,
    required this.sourceLayoutId,
    required this.onAdd,
    this.warehouseName,
  });

  @override
  State<_ProductQuantityDialog> createState() => _ProductQuantityDialogState();
}

class _ProductQuantityDialogState extends State<_ProductQuantityDialog> {
  final _quantityController = TextEditingController();
  Map<String, dynamic>? _selectedVariant;
  List<Map<String, dynamic>> _availableVariants = [];
  bool _isLoadingVariants = false;
  double _maxAvailableStock = 0.0;

  @override
  void initState() {
    super.initState();
    // Usar el stock del producto directamente
    _maxAvailableStock = widget.product.cantidadFinal;
    print('🔍 DEBUG: Stock inicial del producto: $_maxAvailableStock');
    _loadLocationSpecificVariants();
  }

  Future<void> _loadLocationSpecificVariants() async {
    if (widget.sourceLayoutId == null) return;

    setState(() => _isLoadingVariants = true);

    try {
      final variants = await InventoryService.getProductVariantsInLocation(
        idProducto: widget.product.id,
        idLayout: widget.sourceLayoutId!,
      );

      setState(() {
        _availableVariants = variants;
        if (variants.isNotEmpty) {
          _selectedVariant = variants.first;
          print('🔍 DEBUG: Selected variant data: $_selectedVariant');
          print(
            '🔍 DEBUG: Stock disponible: ${_selectedVariant!['stock_disponible']}',
          );
          _maxAvailableStock =
              _selectedVariant!['stock_disponible']?.toDouble() ?? 0.0;
          print('🔍 DEBUG: Max available stock set to: $_maxAvailableStock');
        }
        _isLoadingVariants = false;
      });
    } catch (e) {
      setState(() => _isLoadingVariants = false);
      // Fallback data if service fails
      _availableVariants = [
        {
          'id_variante': null,
          'variante': 'Estándar',
          'id_presentacion': null,
          'presentacion': 'Unidad',
          'stock_disponible': 100.0,
        },
      ];
      _selectedVariant = _availableVariants.first;
      _maxAvailableStock = 100.0;
    }
  }

  void _onVariantChanged(Map<String, dynamic>? variant) {
    setState(() {
      _selectedVariant = variant;
      _maxAvailableStock = variant?['stock_disponible']?.toDouble() ?? 0.0;
      _quantityController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Extraer Producto',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Info Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Información del Producto',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow('SKU', widget.product.skuProducto),
                          _buildInfoRow(
                            'Stock Total', 
                            widget.product.stockDisponible.toInt().toString(),
                            valueColor: widget.product.stockDisponible > 0 
                                ? AppColors.success 
                                : AppColors.error,
                          ),
                          if (widget.product.presentacion.isNotEmpty)
                            _buildInfoRow('Presentación', widget.product.presentacion),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Presentation Selection
                    if (_isLoadingVariants)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_availableVariants.isNotEmpty) ...[
                      Text(
                        'Seleccionar Presentación',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppColors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Presentation Cards
                      ..._availableVariants.map((variant) {
                        final isSelected = _selectedVariant == variant;
                        return GestureDetector(
                          onTap: () => _onVariantChanged(variant),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? AppColors.primary.withOpacity(0.1)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected 
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected 
                                        ? AppColors.primary
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: isSelected 
                                          ? AppColors.primary
                                          : AppColors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 12,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        variant['presentacion_nombre'] ?? 'Sin presentación',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: isSelected 
                                              ? AppColors.primary
                                              : AppColors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Stock disponible: ${variant['stock_disponible']?.toStringAsFixed(1) ?? '0.0'}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),

                      const SizedBox(height: 20),

                      // Stock Info
                      if (_selectedVariant != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.success.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: AppColors.success,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Stock disponible: ${_maxAvailableStock.toStringAsFixed(1)} unidades',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),
                    ],

                    // Quantity Input
                    Text(
                      'Cantidad a Extraer',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppColors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ingrese la cantidad',
                        hintStyle: TextStyle(
                          color: AppColors.grey.shade500,
                          fontWeight: FontWeight.normal,
                        ),
                        prefixIcon: Icon(
                          Icons.inventory,
                          color: AppColors.primary,
                        ),
                        suffixText: _selectedVariant?['presentacion_nombre'] ?? '',
                        suffixStyle: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.primary, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingrese una cantidad';
                        }
                        final quantity = double.tryParse(value);
                        if (quantity == null || quantity <= 0) {
                          return 'La cantidad debe ser mayor a 0';
                        }
                        if (quantity > _maxAvailableStock) {
                          return 'Cantidad excede stock disponible (Max: ${_maxAvailableStock.toStringAsFixed(1)})';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Action Buttons
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.grey.shade300),
                        ),
                      ),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _selectedVariant == null ? null : () {
                        final quantity = double.tryParse(_quantityController.text);
                        if (quantity == null || quantity <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ingrese una cantidad válida')),
                          );
                          return;
                        }
                        if (quantity > _maxAvailableStock) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cantidad excede stock disponible'),
                            ),
                          );
                          return;
                        }

                        final productData = {
                          'id_producto': widget.product.id,
                          'id_variante': widget.product.idVariante,
                          'id_opcion_variante': widget.product.idOpcionVariante,
                          'id_ubicacion': widget.sourceLayoutId,
                          'id_presentacion': widget.product.idPresentacion,
                          'cantidad': quantity,
                          'precio_unitario': widget.product.precioVenta ?? 0.0,
                          'sku_producto': widget.product.skuProducto,
                          'sku_ubicacion': widget.product.ubicacion,
                          'nombreProducto': widget.product.nombreProducto,
                          'variante': widget.product.variante,
                          'opcionVariante': widget.product.opcionVariante,
                          'presentacion': widget.product.presentacion,
                          'nombreZona': widget.product.ubicacion,
                          'nombreAlmacen': widget.warehouseName ?? 'Almacén',
                        };

                        widget.onAdd(productData);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Agregar Producto',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
