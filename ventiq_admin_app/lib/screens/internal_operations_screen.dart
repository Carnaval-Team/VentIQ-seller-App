import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/inventory_service.dart';
import '../services/warehouse_service.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../models/warehouse.dart';
import '../models/product.dart';

class InternalOperationsScreen extends StatefulWidget {
  const InternalOperationsScreen({super.key});

  @override
  State<InternalOperationsScreen> createState() => _InternalOperationsScreenState();
}

class _InternalOperationsScreenState extends State<InternalOperationsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Operaciones Internas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(
              icon: Icon(Icons.swap_horiz),
              text: 'Transferencia de Zona',
            ),
            Tab(
              icon: Icon(Icons.transform),
              text: 'Cambio de Presentación',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ZoneTransferTab(),
          PresentationChangeTab(),
        ],
      ),
    );
  }
}

class ZoneTransferTab extends StatefulWidget {
  const ZoneTransferTab({super.key});

  @override
  State<ZoneTransferTab> createState() => _ZoneTransferTabState();
}

class _ZoneTransferTabState extends State<ZoneTransferTab> {
  final _formKey = GlobalKey<FormState>();
  final _observacionesController = TextEditingController();
  final _searchController = TextEditingController();

  List<Product> _availableProducts = [];
  List<Product> _filteredProducts = [];
  List<Map<String, dynamic>> _selectedProducts = [];
  List<Warehouse> _warehouses = [];
  WarehouseZone? _selectedSourceZone;
  WarehouseZone? _selectedDestinationZone;
  bool _isLoading = false;
  bool _isLoadingProducts = true;
  bool _isLoadingWarehouses = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
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
      _filteredProducts = _availableProducts.where((product) {
        return product.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
               product.sku.toLowerCase().contains(_searchQuery.toLowerCase());
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
    if (_selectedSourceZone == null) return;
    
    try {
      setState(() => _isLoadingProducts = true);
      
      final sourceLayoutId = _getZoneIdFromLocation(_selectedSourceZone!);
      final sourceWarehouseId = _getWarehouseIdFromLocation(_selectedSourceZone!);

      final inventoryResponse = await InventoryService.getInventoryProducts(
        idAlmacen: sourceWarehouseId,
        idUbicacion: sourceLayoutId,
        mostrarSinStock: false,
      );

      final products = inventoryResponse.products.map((inventoryProduct) {
        return Product(
          id: inventoryProduct.id.toString(),
          name: inventoryProduct.nombreProducto,
          denominacion: inventoryProduct.nombreProducto,
          description: inventoryProduct.subcategoria,
          categoryId: inventoryProduct.idCategoria.toString(),
          categoryName: inventoryProduct.categoria,
          brand: '',
          sku: inventoryProduct.skuProducto,
          barcode: '',
          basePrice: inventoryProduct.precioVenta ?? 0.0,
          imageUrl: 'https://picsum.photos/200/200?random=${inventoryProduct.id}',
          isActive: inventoryProduct.esVendible,
          createdAt: inventoryProduct.fechaUltimaActualizacion,
          updatedAt: inventoryProduct.fechaUltimaActualizacion,
          variants: [],
          nombreComercial: inventoryProduct.nombreProducto,
          um: '',
          esRefrigerado: false,
          esFragil: false,
          esPeligroso: false,
          esVendible: inventoryProduct.esVendible,
          stockDisponible: inventoryProduct.cantidadFinal.toInt(),
          tieneStock: inventoryProduct.cantidadFinal > 0,
          subcategorias: [],
          presentaciones: [],
          multimedias: [],
          etiquetas: [],
          inventario: [],
        );
      }).where((product) => product.stockDisponible > 0).toList();

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

  int _getWarehouseIdFromLocation(WarehouseZone location) {
    if (location.warehouseId != null) {
      return int.tryParse(location.warehouseId) ?? 1;
    }
    
    for (final warehouse in _warehouses) {
      if (warehouse.zones.any((zone) => zone.id == location.id)) {
        return int.tryParse(warehouse.id) ?? 1;
      }
    }
    return 1;
  }

  int _getZoneIdFromLocation(WarehouseZone location) {
    String cleanId = location.id;
    if (cleanId.startsWith('z') || cleanId.startsWith('w')) {
      cleanId = cleanId.substring(1);
    }
    return int.tryParse(cleanId) ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildZoneSelectionSection(),
                    const SizedBox(height: 24),
                    _buildProductSelectionSection(),
                    const SizedBox(height: 24),
                    _buildSelectedProductsSection(),
                    const SizedBox(height: 24),
                    _buildObservationsSection(),
                  ],
                ),
              ),
            ),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneSelectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selección de Zonas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Zona de Origen', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _buildZoneDropdown(true),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.arrow_forward, color: AppColors.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Zona de Destino', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      _buildZoneDropdown(false),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneDropdown(bool isSource) {
    return DropdownButtonFormField<WarehouseZone>(
      value: isSource ? _selectedSourceZone : _selectedDestinationZone,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      hint: Text(isSource ? 'Seleccionar origen' : 'Seleccionar destino'),
      items: _warehouses.expand((warehouse) => 
        warehouse.zones.map((zone) => DropdownMenuItem<WarehouseZone>(
          value: zone,
          child: Text('${warehouse.name} - ${zone.name}'),
        ))
      ).toList(),
      onChanged: (zone) {
        setState(() {
          if (isSource) {
            _selectedSourceZone = zone;
            _selectedProducts.clear();
            if (zone != null) _loadProducts();
          } else {
            _selectedDestinationZone = zone;
          }
        });
      },
      validator: (value) => value == null ? 'Seleccione una zona' : null,
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
              'Productos Disponibles',
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
              height: 200,
              child: _isLoadingProducts
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredProducts.isEmpty
                      ? const Center(child: Text('No hay productos disponibles'))
                      : ListView.builder(
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withOpacity(0.1),
                                child: Icon(Icons.inventory_2, color: AppColors.primary),
                              ),
                              title: Text(product.name),
                              subtitle: Text('SKU: ${product.sku} | Stock: ${product.stockDisponible}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.add_circle, color: AppColors.primary),
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
              const Center(child: Text('No hay productos seleccionados'))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _selectedProducts.length,
                itemBuilder: (context, index) {
                  final item = _selectedProducts[index];
                  return ListTile(
                    title: Text(item['nombre_producto']),
                    subtitle: Text('Cantidad: ${item['cantidad']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: AppColors.error),
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

  Widget _buildObservationsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Observaciones',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitZoneTransfer,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('Registrar Transferencia de Zona', style: TextStyle(fontSize: 16)),
      ),
    );
  }

  void _addProductToTransfer(Product product) {
    // Implementation for adding product with quantity dialog
    // Similar to existing transfer screen logic
  }

  void _removeProduct(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
    });
  }

  Future<void> _submitZoneTransfer() async {
    // Implementation for submitting zone transfer
    // Will use existing InventoryService.transferBetweenLayouts method
  }
}

class PresentationChangeTab extends StatefulWidget {
  const PresentationChangeTab({super.key});

  @override
  State<PresentationChangeTab> createState() => _PresentationChangeTabState();
}

class _PresentationChangeTabState extends State<PresentationChangeTab> {
  // Implementation for presentation change functionality
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Funcionalidad de Cambio de Presentación'),
    );
  }
}
