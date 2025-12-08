import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_mapping_service.dart';

class CarnavalStoreMappingScreen extends StatefulWidget {
  const CarnavalStoreMappingScreen({super.key});

  @override
  State<CarnavalStoreMappingScreen> createState() =>
      _CarnavalStoreMappingScreenState();
}

class _CarnavalStoreMappingScreenState
    extends State<CarnavalStoreMappingScreen> {
  final _service = CarnavalMappingService();

  // State variables for Left Panel
  List<Map<String, dynamic>> _stores = [];
  Map<String, dynamic>? _selectedStore;
  List<Map<String, dynamic>> _storeProducts = [];
  Map<String, dynamic>? _selectedLocalProduct;
  bool _isLoadingStores = false;
  bool _isLoadingProducts = false;

  // State variables for Right Panel
  bool _isLoadingDetails = false;
  Map<String, dynamic>? _linkedCarnavalProduct;
  String? _linkedProviderName;

  // Linking UI State
  List<Map<String, dynamic>> _carnavalProviders = [];
  Map<String, dynamic>? _selectedProvider;
  List<Map<String, dynamic>> _providerProducts = [];
  Map<String, dynamic>? _selectedCarnavalProductToLink;
  bool _isLoadingProviders = false;
  bool _isLoadingCarnavalProducts = false;

  // Radio button choice: 0 = Keep Carnaval Name, 1 = Keep Inventtia Name
  int _namePreference = 0;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() => _isLoadingStores = true);
    try {
      final stores = await _service.getStores();
      setState(() {
        _stores = stores;
        if (stores.isNotEmpty) {
          // Optional: Auto-select first store or wait for user
          // _selectedStore = stores.first;
          // _loadStoreProducts(_selectedStore!['id']);
        }
      });
    } catch (e) {
      _showError('Error al cargar tiendas: $e');
    } finally {
      setState(() => _isLoadingStores = false);
    }
  }

  Future<void> _loadStoreProducts(int storeId) async {
    setState(() {
      _isLoadingProducts = true;
      _storeProducts = [];
      _selectedLocalProduct = null;
      _resetRightPanel();
    });
    try {
      final products = await _service.getStoreProducts(storeId);
      setState(() => _storeProducts = products);
    } catch (e) {
      _showError('Error al cargar productos: $e');
    } finally {
      setState(() => _isLoadingProducts = false);
    }
  }

  void _onProductSelected(Map<String, dynamic> product) {
    setState(() {
      _selectedLocalProduct = product;
      _resetRightPanel();
      _isLoadingDetails = true;
    });
    _checkProductLinkStatus(product);
  }

  Future<void> _checkProductLinkStatus(Map<String, dynamic> product) async {
    final carnavalId = product['id_vendedor_app'];

    if (carnavalId != null) {
      // Already linked, fetch details
      try {
        final carnavalProduct = await _service.getCarnavalProductById(
          carnavalId,
        );
        String? providerName;
        if (carnavalProduct != null && carnavalProduct['proveedor'] != null) {
          providerName = await _service.getProviderName(
            carnavalProduct['proveedor'],
          );
        }

        setState(() {
          _linkedCarnavalProduct = carnavalProduct;
          _linkedProviderName = providerName;
        });
      } catch (e) {
        _showError('Error al obtener detalles del enlace: $e');
      }
    } else {
      // Not linked, load providers for linking
      if (_carnavalProviders.isEmpty) {
        _loadProviders();
      }
    }
    setState(() => _isLoadingDetails = false);
  }

  Future<void> _loadProviders() async {
    setState(() => _isLoadingProviders = true);
    try {
      final providers = await _service.getCarnavalProviders();
      setState(() => _carnavalProviders = providers);
    } catch (e) {
      _showError('Error al cargar proveedores: $e');
    } finally {
      setState(() => _isLoadingProviders = false);
    }
  }

  Future<void> _loadProviderProducts(int providerId) async {
    setState(() {
      _isLoadingCarnavalProducts = true;
      _providerProducts = [];
      _selectedCarnavalProductToLink = null;
    });
    try {
      final products = await _service.getCarnavalProducts(providerId);
      setState(() => _providerProducts = products);
    } catch (e) {
      _showError('Error al cargar productos de Carnaval: $e');
    } finally {
      setState(() => _isLoadingCarnavalProducts = false);
    }
  }

  Future<void> _linkProduct() async {
    if (_selectedLocalProduct == null || _selectedCarnavalProductToLink == null)
      return;

    try {
      final updateName = _namePreference == 0; // 0 = Carnaval Name
      final newName = updateName
          ? _selectedCarnavalProductToLink!['name']
          : null;
      final newImage = _selectedCarnavalProductToLink!['image'];

      await _service.linkProduct(
        localProductId: _selectedLocalProduct!['id'],
        carnavalProductId: _selectedCarnavalProductToLink!['id'],
        updateName: updateName,
        newName: newName,
        newImage: newImage,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Producto enlazado correctamente'),
          backgroundColor: AppColors.success,
        ),
      );

      // Refresh current product selection to show details
      // Ideally update local list item too to reflect change without full reload
      if (updateName) {
        _selectedLocalProduct!['denominacion'] = newName;
      }
      if (newImage != null && newImage.isNotEmpty) {
        _selectedLocalProduct!['imagen'] = newImage;
      }
      _selectedLocalProduct!['id_vendedor_app'] =
          _selectedCarnavalProductToLink!['id'];

      _onProductSelected(_selectedLocalProduct!); // Reload details view
    } catch (e) {
      _showError('Error al enlazar producto: $e');
    }
  }

  void _resetRightPanel() {
    _linkedCarnavalProduct = null;
    _linkedProviderName = null;
    // Keep provider selection to save clicks
    // _selectedProvider = null;
    // _providerProducts = [];
    _selectedCarnavalProductToLink = null;
    _namePreference = 0;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Carnaval App Tiendas - Mapeo')),
      body: Row(
        children: [
          // Left Panel: Stores & Local Products
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.divider)),
                color: AppColors.surface,
              ),
              child: Column(
                children: [
                  _buildStoreSelector(),
                  const Divider(height: 1),
                  Expanded(child: _buildLocalProductList()),
                ],
              ),
            ),
          ),

          // Right Panel: Details or Linking
          Expanded(
            flex: 3,
            child: Container(
              color: AppColors.background,
              padding: const EdgeInsets.all(24),
              child: _buildRightPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreSelector() {
    if (_isLoadingStores) return const LinearProgressIndicator();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: DropdownButtonFormField<Map<String, dynamic>>(
        decoration: const InputDecoration(
          labelText: 'Seleccionar Tienda',
          prefixIcon: Icon(Icons.store),
          border: OutlineInputBorder(),
        ),
        value: _selectedStore,
        items: _stores.map((store) {
          return DropdownMenuItem(
            value: store,
            child: Text(store['denominacion'] ?? 'Sin Nombre'),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() => _selectedStore = value);
            _loadStoreProducts(value['id']);
          }
        },
      ),
    );
  }

  Widget _buildLocalProductList() {
    if (_selectedStore == null) {
      return const Center(
        child: Text('Seleccione una tienda para ver sus productos'),
      );
    }
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_storeProducts.isEmpty) {
      return const Center(child: Text('No hay productos en esta tienda'));
    }

    return ListView.builder(
      itemCount: _storeProducts.length,
      itemBuilder: (context, index) {
        final product = _storeProducts[index];
        final isSelected = _selectedLocalProduct == product;
        final isLinked = product['id_vendedor_app'] != null;

        return ListTile(
          selected: isSelected,
          selectedTileColor: AppColors.primary.withOpacity(0.1),
          leading: CircleAvatar(
            backgroundColor: isLinked
                ? AppColors.success.withOpacity(0.2)
                : AppColors.warning.withOpacity(0.2),
            child: Icon(
              isLinked ? Icons.link : Icons.link_off,
              color: isLinked ? AppColors.success : AppColors.warning,
              size: 20,
            ),
          ),
          title: Text(
            product['denominacion'] ?? 'Sin Nombre',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            'Codigo: ${product['sku'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () => _onProductSelected(product),
        );
      },
    );
  }

  Widget _buildRightPanel() {
    if (_selectedLocalProduct == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: AppColors.textHint),
            SizedBox(height: 16),
            Text(
              'Selecciona un producto de la izquierda',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
            ),
          ],
        ),
      );
    }

    if (_isLoadingDetails) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_linkedCarnavalProduct != null) {
      return _buildLinkedDetails();
    } else {
      return _buildLinkingInterface();
    }
  }

  Widget _buildLinkedDetails() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Producto Enlazado',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'ID Local: ${_selectedLocalProduct!['id']}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _buildDetailRow('Nombre Carnaval', _linkedCarnavalProduct!['name']),
            _buildDetailRow('Proveedor', _linkedProviderName ?? 'Desconocido'),
            _buildDetailRow(
              'Precio Carnaval',
              '\$${_linkedCarnavalProduct!['price']}',
            ),
            const SizedBox(height: 24),
            // TODO: Add Unlink button if needed in future
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkingInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enlazar con Producto de Carnaval',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Producto Local: ${_selectedLocalProduct!['denominacion']}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        // Step 1: Provider Selector
        _isLoadingProviders
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              )
            : DropdownButtonFormField<Map<String, dynamic>>(
                decoration: const InputDecoration(
                  labelText: 'Seleccionar Proveedor',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.storefront),
                ),
                value: _selectedProvider,
                items: _carnavalProviders.map((provider) {
                  return DropdownMenuItem(
                    value: provider,
                    child: Text(provider['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedProvider = value);
                    _loadProviderProducts(value['id']);
                  }
                },
              ),

        const SizedBox(height: 16),

        // Step 2: Product Selector
        if (_selectedProvider != null)
          _isLoadingCarnavalProducts
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              : DropdownButtonFormField<Map<String, dynamic>>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Seleccionar Producto de Carnaval',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.shopping_bag_outlined),
                  ),
                  value: _selectedCarnavalProductToLink,
                  items: _providerProducts.map((prod) {
                    return DropdownMenuItem(
                      value: prod,
                      child: Text('${prod['name']} (\$${prod['price']})'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedCarnavalProductToLink = value);
                  },
                ),

        const SizedBox(height: 24),

        // Step 3: Name Preference & Action
        if (_selectedCarnavalProductToLink != null) ...[
          const Text(
            'Opciones de Sincronización:',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          RadioListTile<int>(
            title: const Text('Conservar el nombre de Carnaval App'),
            subtitle: Text(
              'Se actualizará a: "${_selectedCarnavalProductToLink!['name']}"',
            ),
            value: 0,
            groupValue: _namePreference,
            onChanged: (val) => setState(() => _namePreference = val!),
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<int>(
            title: const Text('Conservar el nombre de Inventtia'),
            subtitle: Text(
              'Se mantendrá: "${_selectedLocalProduct!['denominacion']}"',
            ),
            value: 1,
            groupValue: _namePreference,
            onChanged: (val) => setState(() => _namePreference = val!),
            contentPadding: EdgeInsets.zero,
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Aceptar y Enlazar'),
              onPressed: _linkProduct,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
