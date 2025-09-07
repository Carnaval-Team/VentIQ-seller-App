import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/inventory.dart';
import '../services/inventory_service.dart';
import 'inventory_reception_screen.dart';

class InventoryStockScreen extends StatefulWidget {
  const InventoryStockScreen({super.key});

  @override
  State<InventoryStockScreen> createState() => _InventoryStockScreenState();
}

class _InventoryStockScreenState extends State<InventoryStockScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<InventoryProduct> _inventoryProducts = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _selectedWarehouse = 'Todos';
  int? _selectedWarehouseId;
  String _stockFilter = 'Todos';
  String _errorMessage = '';

  // Pagination and summary data
  int _currentPage = 1;
  bool _hasNextPage = false;
  InventorySummary? _inventorySummary;
  PaginationInfo? _paginationInfo;
  final ScrollController _scrollController = ScrollController();

  // Selection mode for extraction
  bool _isSelectionMode = false;
  Set<String> _selectedProducts = <String>{};
  List<Map<String, dynamic>> _motivoExtraccionOptions = [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadInventoryData();
    _loadMotivoExtraccionOptions();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadInventoryData({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _currentPage = 1;
        _inventoryProducts.clear();
      });
    }

    try {
      // Load inventory products with pagination
      final response = await InventoryService.getInventoryProducts(
        idAlmacen: _selectedWarehouseId,
        busqueda: _searchQuery.isEmpty ? null : _searchQuery,
        mostrarSinStock: _stockFilter != 'Sin Stock',
        conStockMinimo: _stockFilter == 'Stock Bajo' ? true : null,
        pagina: _currentPage,
      );

      setState(() {
        if (reset) {
          _inventoryProducts = response.products;
        } else {
          _inventoryProducts.addAll(response.products);
        }
        _inventorySummary = response.summary;
        _paginationInfo = response.pagination;
        _hasNextPage = response.pagination?.tieneSiguiente ?? false;
        _isLoading = false;
        _isLoadingMore = false;
      });

      print(
        '✅ Loaded ${response.products.length} products (page $_currentPage)',
      );
      print(
        '📊 Summary: ${_inventorySummary?.totalInventario} total, ${_inventorySummary?.totalSinStock} sin stock',
      );
    } catch (e) {
      print('❌ Error loading inventory data: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = 'Error al cargar inventario: $e';
      });
    }
  }

  void _loadNextPage() async {
    if (_isLoadingMore || !_hasNextPage) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    _loadInventoryData(reset: false);
  }

  Future<void> _loadMotivoExtraccionOptions() async {
    try {
      final options = await InventoryService.getMotivoExtraccionOptions();
      setState(() {
        _motivoExtraccionOptions = options;
      });
    } catch (e) {
      print('Error loading motivo extracción options: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_errorMessage.isNotEmpty) {
      return _buildErrorState();
    }

    final filteredItems = _getFilteredInventoryItems();

    return Column(
      children: [
        _buildSearchAndFilters(),
        _buildInventorySummary(),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: filteredItems.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == filteredItems.length) {
                return _buildLoadingMoreIndicator();
              }
              return _buildInventoryCard(filteredItems[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando inventario...',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadInventoryData,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar productos...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
              // Debounce search
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_searchQuery == value) {
                  _loadInventoryData();
                }
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _selectedWarehouse,
                  decoration: const InputDecoration(
                    labelText: 'Almacén',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'Todos',
                      child: Text('Todos', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedWarehouse = value!;
                      if (value == 'Todos') {
                        _selectedWarehouseId = null;
                      }
                    });
                    _loadInventoryData();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _stockFilter,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  isExpanded: true,
                  items:
                      ['Todos', 'Sin Stock', 'Stock Bajo', 'Stock OK'].map((
                        String value,
                      ) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() => _stockFilter = value!);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInventorySummary() {
    if (_inventorySummary == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.background,
      child: Column(
        children: [
          Row(
            children: [
              _buildSummaryCard(
                'Total Inventario',
                _inventorySummary!.totalInventario.toString(),
                AppColors.info,
              ),
              const SizedBox(width: 8),
              _buildSummaryCard(
                'Sin Stock',
                _inventorySummary!.totalSinStock.toString(),
                AppColors.error,
              ),
              const SizedBox(width: 8),
              _buildSummaryCard(
                'Stock Bajo',
                _inventorySummary!.totalConCantidadBaja.toString(),
                AppColors.warning,
              ),
            ],
          ),
          if (_paginationInfo != null) ...[
            const SizedBox(height: 8),
            Text(
              'Página ${_paginationInfo!.paginaActual} de ${_paginationInfo!.totalPaginas} • ${_paginationInfo!.totalRegistros} productos total',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryCard(InventoryProduct item) {
    final stockStatus = _getStockStatus(item.stockDisponible.toInt());
    final isSelected = _selectedProducts.contains(item.id.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        leading:
            _isSelectionMode
                ? Checkbox(
                  value: isSelected,
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedProducts.add(item.id.toString());
                      } else {
                        _selectedProducts.remove(item.id.toString());
                      }
                    });
                  },
                )
                : CircleAvatar(
                  backgroundColor: stockStatus.color.withOpacity(0.1),
                  child: Icon(Icons.inventory_2, color: stockStatus.color),
                ),
        title: Text(
          item.nombreProducto,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.variante} ${item.opcionVariante}'),
            Text('Almacén: ${item.almacen}'),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${item.stockDisponible}'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: stockStatus.color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                stockStatus.label,
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ],
        ),
        onTap: () {
          if (_isSelectionMode) {
            setState(() {
              if (isSelected) {
                _selectedProducts.remove(item.id.toString());
              } else {
                _selectedProducts.add(item.id.toString());
              }
            });
          } else {
            _showInventoryProductDetails(item);
          }
        },
        onLongPress: () {
          if (!_isSelectionMode) {
            setState(() {
              _isSelectionMode = true;
              _selectedProducts.add(item.id.toString());
            });
          }
        },
      ),
    );
  }

  List<InventoryProduct> _getFilteredInventoryItems() {
    List<InventoryProduct> filtered = List.from(_inventoryProducts);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered =
          filtered.where((item) {
            return item.nombreProducto.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                item.skuProducto.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
          }).toList();
    }

    // Apply warehouse filter
    if (_selectedWarehouse != 'Todos') {
      filtered =
          filtered.where((item) => item.almacen == _selectedWarehouse).toList();
    }

    // Apply stock filter based on stock_disponible field
    switch (_stockFilter) {
      case 'Sin Stock':
        filtered = filtered.where((item) => item.stockDisponible <= 0).toList();
        break;
      case 'Stock Bajo':
        filtered =
            filtered
                .where(
                  (item) =>
                      item.stockDisponible > 0 && item.stockDisponible <= 10,
                )
                .toList();
        break;
      case 'Stock OK':
        filtered =
            filtered.where((item) => item.stockDisponible >= 10).toList();
        break;
      case 'Todos':
      default:
        break;
    }

    return filtered;
  }

  ({Color color, String label}) _getStockStatus(int stock) {
    if (stock <= 0) {
      return (color: AppColors.error, label: 'Sin Stock');
    } else if (stock < 10) {
      return (color: AppColors.warning, label: 'Stock Bajo');
    } else {
      return (color: AppColors.success, label: 'Stock OK');
    }
  }

  void _showInventoryProductDetails(InventoryProduct item) {
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.inventory_2,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.nombreProducto,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'SKU: ${item.skuProducto}',
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
                  SizedBox(height: 24),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Stock Status Card
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: item.stockLevelColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: item.stockLevelColor.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.inventory,
                                      color: item.stockLevelColor,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Estado de Stock',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Stock Actual',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          '${item.cantidadFinal.toStringAsFixed(0)} unidades',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: item.stockLevelColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.stockLevelColor,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        item.stockLevel,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 16),

                          // Product Information
                          _buildDetailSection(
                            'Información del Producto',
                            Icons.info_outline,
                            [
                              _buildDetailRow('Categoría', item.categoria),
                              _buildDetailRow(
                                'Subcategoría',
                                item.subcategoria,
                              ),
                              _buildDetailRow('Variante', item.variante),
                              _buildDetailRow(
                                'Opción Variante',
                                item.opcionVariante,
                              ),
                              _buildDetailRow(
                                'Presentación',
                                item.presentacion,
                              ),
                              _buildDetailRow(
                                'Vendible',
                                item.esVendible ? 'Sí' : 'No',
                              ),
                              _buildDetailRow(
                                'Inventariable',
                                item.esInventariable ? 'Sí' : 'No',
                              ),
                            ],
                          ),
                          SizedBox(height: 16),

                          // Location Information
                          _buildDetailSection(
                            'Ubicación',
                            Icons.location_on_outlined,
                            [
                              _buildDetailRow('Tienda', item.tienda),
                              _buildDetailRow('Almacén', item.almacen),
                              _buildDetailRow('Ubicación', item.ubicacion),
                            ],
                          ),
                          SizedBox(height: 16),

                          // Stock Details
                          _buildDetailSection(
                            'Detalles de Stock',
                            Icons.inventory_2_outlined,
                            [
                              _buildDetailRow(
                                'Cantidad Inicial',
                                '${item.cantidadInicial.toStringAsFixed(2)} unidades',
                              ),
                              _buildDetailRow(
                                'Stock Disponible',
                                '${item.stockDisponible.toStringAsFixed(2)} unidades',
                              ),
                              _buildDetailRow(
                                'Stock Reservado',
                                '${item.stockReservado.toStringAsFixed(2)} unidades',
                              ),
                              _buildDetailRow(
                                'Stock Ajustado',
                                '${item.stockDisponibleAjustado.toStringAsFixed(2)} unidades',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.swap_horiz, size: 18),
                          label: Text('Transferir'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary),
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, size: 18),
                          label: Text('Cerrar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildDetailSection(
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // Métodos para exponer funcionalidad al padre
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedProducts => _selectedProducts;

  void exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedProducts.clear();
    });
  }

  void refreshData() {
    _loadInventoryData();
  }

  void showMultiExtractionDialog() {
    // Implementar diálogo de extracción múltiple
    // Por ahora, solo mostrar un mensaje
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Extracción múltiple: ${_selectedProducts.length} productos seleccionados',
        ),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void showInventoryReceptionDialog() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => InventoryReceptionScreen(),
            fullscreenDialog: true,
          ),
        )
        .then((_) {
          // Refresh inventory after reception
          _loadInventoryData();
        });
  }
}
