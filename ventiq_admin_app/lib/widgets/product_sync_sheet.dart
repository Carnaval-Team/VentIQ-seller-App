import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/carnaval_service.dart';
import '../services/inventory_service.dart';
import '../config/app_colors.dart';

class ProductSyncSheet extends StatefulWidget {
  final int storeId;
  final int carnavalStoreId;

  const ProductSyncSheet({
    Key? key,
    required this.storeId,
    required this.carnavalStoreId,
  }) : super(key: key);

  @override
  State<ProductSyncSheet> createState() => _ProductSyncSheetState();
}

class _ProductSyncSheetState extends State<ProductSyncSheet> {
  bool _isLoading = true;
  bool _isSyncing = false;

  // Paso 1: almacenes
  List<Map<String, dynamic>> _warehouses = [];
  Map<String, dynamic>? _selectedWarehouse;

  // Paso 2: zonas del almacén seleccionado
  List<Map<String, dynamic>> _zones = [];
  Map<String, dynamic>? _selectedZone;
  bool _loadingZones = false;

  // Paso 3: productos sin sync (todos) y los filtrados por zona
  List<Map<String, dynamic>> _allUnsyncedProducts = [];
  List<Map<String, dynamic>> _zoneProducts = [];
  bool _loadingZoneProducts = false;

  List<Map<String, dynamic>> _categories = [];

  // Búsqueda de productos
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Lista de productos pendientes por sincronizar
  // Cada item es un mapa: {'product': Map, 'category': Map, 'location': Map}
  final List<Map<String, dynamic>> _pendingProducts = [];

  final Set<int> _selectedProductIds = {};
  Map<String, dynamic>? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  List<Map<String, dynamic>> get _selectedProducts {
    return _zoneProducts
        .where((p) => _selectedProductIds.contains(p['id'] as int))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        CarnavalService.getUnsyncedProducts(
          widget.storeId,
          widget.carnavalStoreId,
        ),
        CarnavalService.getCarnavalCategories(),
        _fetchWarehouses(),
      ]);

      if (mounted) {
        setState(() {
          _allUnsyncedProducts = results[0] as List<Map<String, dynamic>>;
          _categories = results[1] as List<Map<String, dynamic>>;
          _warehouses = results[2] as List<Map<String, dynamic>>;
          if (_warehouses.length == 1) {
            _selectedWarehouse = _warehouses.first;
          }
        });
        // Si ya hay almacén auto-seleccionado, cargar zonas
        if (_selectedWarehouse != null) {
          await _onWarehouseChanged(_selectedWarehouse!);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchWarehouses() async {
    try {
      final response = await Supabase.instance.client
          .from('app_dat_almacen')
          .select('id, denominacion')
          .eq('id_tienda', widget.storeId)
          .order('denominacion');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error cargando almacenes: $e');
      return [];
    }
  }

  Future<void> _onWarehouseChanged(Map<String, dynamic> warehouse) async {
    setState(() {
      _selectedWarehouse = warehouse;
      _selectedZone = null;
      _zones = [];
      _zoneProducts = [];
      _selectedProductIds.clear();
      _searchController.clear();
      _loadingZones = true;
    });
    try {
      final zones = await InventoryService.getWarehouseZones(
        warehouse['id'] as int,
      );
      if (mounted) {
        setState(() {
          _zones = zones;
          _loadingZones = false;
          if (_zones.length == 1) {
            _selectedZone = _zones.first;
          }
        });
        if (_selectedZone != null) {
          await _onZoneChanged(_selectedZone!);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingZones = false);
    }
  }

  Future<void> _onZoneChanged(Map<String, dynamic> zone) async {
    setState(() {
      _selectedZone = zone;
      _zoneProducts = [];
      _selectedProductIds.clear();
      _searchController.clear();
      _loadingZoneProducts = true;
    });
    try {
      final zoneInventory = await InventoryService.getZoneProducts(
        idAlmacen: _selectedWarehouse!['id'] as int,
        idUbicacion: zone['id'] as int,
      );
      // Cruzar con _allUnsyncedProducts para tener imagen y datos completos
      final zoneIds = zoneInventory.map((p) => p.idProducto).toSet();
      final pendingIds = _pendingProducts.map((p) => p['product']['id']).toSet();
      if (mounted) {
        setState(() {
          _zoneProducts = _allUnsyncedProducts
              .where((p) =>
                  zoneIds.contains(p['id']) && !pendingIds.contains(p['id']))
              .toList();
          _loadingZoneProducts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingZoneProducts = false);
    }
  }

  List<Map<String, dynamic>> get _filteredProducts {
    if (_searchQuery.isEmpty) return _zoneProducts;
    return _zoneProducts.where((p) {
      final nombre = (p['denominacion'] ?? '').toString().toLowerCase();
      return nombre.contains(_searchQuery);
    }).toList();
  }

  void _toggleProductSelection(Map<String, dynamic> product) {
    setState(() {
      final id = product['id'] as int;
      if (_selectedProductIds.contains(id)) {
        _selectedProductIds.remove(id);
      } else {
        _selectedProductIds.add(id);
      }
    });
  }

  void _addToPending() {
    if (_selectedProductIds.isEmpty ||
        _selectedCategory == null ||
        _selectedZone == null) return;

    final location = {
      'id_ubicacion': _selectedZone!['id'],
      'almacen': _selectedWarehouse!['denominacion'],
      'ubicacion': _selectedZone!['denominacion'],
    };

    setState(() {
      for (final product in _selectedProducts) {
        _pendingProducts.add({
          'product': product,
          'category': _selectedCategory,
          'location': location,
        });
        _zoneProducts.removeWhere((p) => p['id'] == product['id']);
        _allUnsyncedProducts.removeWhere((p) => p['id'] == product['id']);
      }
      _selectedProductIds.clear();
      _searchController.clear();
    });
  }

  void _removeFromPending(int index) {
    setState(() {
      final item = _pendingProducts[index];
      _allUnsyncedProducts.add(item['product']);
      // Si la zona del item coincide con la zona actual, devolverlo también a _zoneProducts
      final locId = item['location']['id_ubicacion'];
      if (_selectedZone != null && locId == _selectedZone!['id']) {
        _zoneProducts.add(item['product']);
      }
      _pendingProducts.removeAt(index);
    });
  }

  void _showImageZoom(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade900,
                padding: const EdgeInsets.all(32),
                child: const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _syncAll() async {
    if (_pendingProducts.isEmpty) return;

    setState(() => _isSyncing = true);

    int successCount = 0;
    int failCount = 0;
    final List<String> failures = [];

    try {
      for (final item in _pendingProducts) {
        final productName =
            item['product']['denominacion']?.toString() ?? 'Producto sin nombre';
        try {
          final success = await CarnavalService.syncProductToCarnaval(
            localProductId: item['product']['id'],
            carnavalCategoryId: item['category']['id'],
            carnavalStoreId: widget.carnavalStoreId,
            idUbicacion: item['location']['id_ubicacion'],
            storeId: widget.storeId,
          );

          if (success) {
            successCount++;
          } else {
            failCount++;
            failures.add('$productName: ya sincronizado o sin datos');
          }
        } catch (e) {
          failCount++;
          final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
          failures.add('$productName: $msg');
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);

        final buffer = StringBuffer(
          'Sincronización finalizada: $successCount exitosos, $failCount fallidos',
        );
        if (failures.isNotEmpty) {
          final shown = failures.take(3).join('\n• ');
          buffer.write('\n• $shown');
          if (failures.length > 3) {
            buffer.write('\n(+${failures.length - 3} más en consola)');
            for (final f in failures.skip(3)) {
              print('⚠️ Sync fallido: $f');
            }
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(buffer.toString()),
            backgroundColor: failCount == 0 ? Colors.green : Colors.orange,
            duration: Duration(seconds: failures.isEmpty ? 3 : 8),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error general: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sincronizar Productos',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Selector de Almacén ──────────────────────────────────
                    if (_warehouses.isNotEmpty) ...[
                      const Text(
                        'Almacén',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: InputDecoration(
                          labelText: _warehouses.length == 1
                              ? null
                              : 'Seleccionar Almacén',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.warehouse_outlined),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        value: _selectedWarehouse,
                        isExpanded: true,
                        items: _warehouses
                            .map(
                              (w) => DropdownMenuItem(
                                value: w,
                                child: Text(
                                  w['denominacion'] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) _onWarehouseChanged(value);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Selector de Zona ─────────────────────────────────────
                    if (_selectedWarehouse != null) ...[
                      const Text(
                        'Zona / Ubicación',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_loadingZones)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        DropdownButtonFormField<Map<String, dynamic>>(
                          decoration: InputDecoration(
                            labelText:
                                _zones.length == 1 ? null : 'Seleccionar Zona',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          value: _selectedZone,
                          isExpanded: true,
                          items: _zones
                              .map(
                                (z) => DropdownMenuItem(
                                  value: z,
                                  child: Text(
                                    z['denominacion'] ?? '',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) _onZoneChanged(value);
                          },
                        ),
                      const SizedBox(height: 20),
                    ],

                    // ── Sección Agregar Producto ─────────────────────────────
                    if (_allUnsyncedProducts.isEmpty && _pendingProducts.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text(
                            'No hay productos disponibles para sincronizar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else if (_selectedZone != null) ...[
                      const Text(
                        'Productos en esta Zona',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (_loadingZoneProducts)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[                      // Campo de búsqueda
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar producto por nombre…',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _selectedProductIds.clear());
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Lista de productos de la zona (selección múltiple)
                      _ProductPickerList(
                        products: _filteredProducts,
                        selectedIds: _selectedProductIds,
                        onToggle: _toggleProductSelection,
                        onImageTap: (imageUrl) => _showImageZoom(imageUrl),
                      ),
                      if (_selectedProductIds.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${_selectedProductIds.length} producto(s) seleccionado(s)',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                      const SizedBox(height: 12),

                      // Selector de Categoría
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(
                          labelText: 'Categoría en Carnaval',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        value: _selectedCategory,
                        isExpanded: true,
                        items: _categories
                            .map(
                              (category) => DropdownMenuItem(
                                value: category,
                                child: Row(
                                  children: [
                                    if (category['icon'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: Image.network(
                                          category['icon'],
                                          width: 20,
                                          height: 20,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                Icons.category,
                                                size: 20,
                                              ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        category['name'],
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedCategory = value);
                        },
                      ),

                      const SizedBox(height: 16),

                      // Botón Agregar
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_selectedProductIds.isNotEmpty &&
                                  _selectedCategory != null &&
                                  _selectedZone != null)
                              ? _addToPending
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Agregar a la lista'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      ], // end if !_loadingZoneProducts
                    ],

                    const SizedBox(height: 24),

                    // ── Lista de Pendientes ──────────────────────────────────
                    if (_pendingProducts.isNotEmpty) ...[
                      Row(
                        children: [
                          const Text(
                            'Lista para Sincronizar',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_pendingProducts.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _pendingProducts.length,
                        itemBuilder: (context, index) {
                          final item = _pendingProducts[index];
                          final product = item['product'];
                          final category = item['category'];
                          final location = item['location'];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: _ProductThumbnail(
                                imageUrl: product['imagen'],
                                size: 40,
                              ),
                              title: Text(product['denominacion']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(category['name']),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        size: 14,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          '${location['almacen']} › ${location['ubicacion']}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removeFromPending(index),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Footer
          if (_pendingProducts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSyncing ? null : _syncAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSyncing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'Sincronizar ${_pendingProducts.length} Productos',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget auxiliar: lista de selección de producto con foto
// ─────────────────────────────────────────────────────────────────────────────
class _ProductPickerList extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  final Set<int> selectedIds;
  final ValueChanged<Map<String, dynamic>> onToggle;
  final ValueChanged<String> onImageTap;

  const _ProductPickerList({
    required this.products,
    required this.selectedIds,
    required this.onToggle,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No hay productos que coincidan con la búsqueda.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: products.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 56),
          itemBuilder: (context, index) {
            final p = products[index];
            final id = p['id'] as int;
            final isSelected = selectedIds.contains(id);
            final imageUrl = p['imagen'] as String?;
            return ListTile(
              dense: true,
              selected: isSelected,
              selectedTileColor: AppColors.primary.withOpacity(0.08),
              leading: GestureDetector(
                onTap: (imageUrl != null && imageUrl.isNotEmpty)
                    ? () => onImageTap(imageUrl)
                    : null,
                child: Stack(
                  children: [
                    _ProductThumbnail(imageUrl: imageUrl, size: 36),
                    if (imageUrl != null && imageUrl.isNotEmpty)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          padding: const EdgeInsets.all(1),
                          child: const Icon(
                            Icons.zoom_in,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              title: Text(
                p['denominacion'] ?? '',
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                'ID: $id',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              trailing: isSelected
                  ? Icon(Icons.check_circle, color: AppColors.primary)
                  : const Icon(Icons.check_circle_outline,
                      color: Colors.grey, size: 20),
              onTap: () => onToggle(p),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget auxiliar: miniatura de producto
// ─────────────────────────────────────────────────────────────────────────────
class _ProductThumbnail extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const _ProductThumbnail({required this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(size),
        ),
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          size: size * 0.55,
          color: Colors.grey,
        ),
      );
}

