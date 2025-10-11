import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/inventory.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/inventory_summary_card.dart';
import '../widgets/inventory_export_dialog.dart';
import 'inventory_reception_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryStockScreen extends StatefulWidget {
  const InventoryStockScreen({super.key});

  @override
  State<InventoryStockScreen> createState() => _InventoryStockScreenState();
}

class _InventoryStockScreenState extends State<InventoryStockScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<InventoryProduct> _inventoryProducts = [];
  List<InventorySummaryByUser> _inventorySummaries = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _selectedWarehouse = 'Todos';
  int? _selectedWarehouseId;
  String _stockFilter = 'Todos';
  String _errorMessage = '';
  bool _isDetailedView = false; // Toggle between summary and detailed view

  // Pagination and summary data
  int _currentPage = 1;
  bool _hasNextPage = false;
  InventorySummary? _inventorySummary;
  PaginationInfo? _paginationInfo;
  final ScrollController _scrollController = ScrollController();

  // Warehouses data
  List<Map<String, dynamic>> _warehouses = [];
  bool _isLoadingWarehouses = false;
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _loadWarehouses();
    _loadInventoryData();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_isDetailedView) {
        _loadNextPage();
      }
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
        _inventorySummaries.clear();
      });
    }

    try {
      if (_isDetailedView) {
        print('🔍 Loading detailed inventory view...');
        // Load detailed inventory products with pagination
        final response = await InventoryService.getInventoryProducts(
          idAlmacen: _selectedWarehouseId,
          busqueda: _searchQuery.isEmpty ? null : _searchQuery,
          mostrarSinStock: _stockFilter != 'Sin Stock',
          conStockMinimo: _stockFilter == 'Stock Bajo' ? true : null,
          pagina: _currentPage,
        );

        print('response.products');
        print(response.products);

        // Group products to eliminate duplicates
        List<InventoryProduct> groupedProducts = _groupProducts2(
          response.products,
        );

        setState(() {
          if (reset) {
            _inventoryProducts = groupedProducts;
          } else {
            _inventoryProducts.addAll(groupedProducts);
          }
          _inventorySummary = response.summary;
          _paginationInfo = response.pagination;
          _hasNextPage = response.pagination?.tieneSiguiente ?? false;
          _isLoading = false;
          _isLoadingMore = false;
        });

        print(
          '✅ Loaded ${response.products.length} raw products, grouped to ${groupedProducts.length} unique products (page $_currentPage)',
        );
      } else {
        print('🔍 Loading inventory summary view...');
        // Load inventory summary by user
        final summaries = await InventoryService.getInventorySummaryByUser(
          _selectedWarehouseId,
          _searchQuery,
        );

        print('📦 Received ${summaries.length} summaries from service');
        for (int i = 0; i < summaries.length && i < 3; i++) {
          final summary = summaries[i];
          print(
            '📋 Summary $i: ${summary.productoNombre} (ID: ${summary.idProducto}) - ${summary.cantidadTotalEnAlmacen} units',
          );
        }

        setState(() {
          _inventorySummaries = summaries;
          _isLoading = false;
          _isLoadingMore = false;
        });

        print('✅ Loaded ${summaries.length} inventory summaries');
        print(
          '🔍 State updated - _inventorySummaries length: ${_inventorySummaries.length}',
        );
      }
    } catch (e) {
      print('❌ Error loading inventory data: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _isLoadingWarehouses = true;
    });

    try {
      print('🏪 Loading warehouses from Supabase...');

      // Obtener el ID de tienda del usuario
      final idTienda = await _userPreferencesService.getIdTienda();
      if (idTienda == null) {
        print('❌ No store ID found for user');
        setState(() {
          _isLoadingWarehouses = false;
        });
        return;
      }

      print('🔍 Fetching warehouses for store ID: $idTienda');

      // Consultar almacenes de la tienda
      final response = await _supabase
          .from('app_dat_almacen')
          .select('id, denominacion, direccion, ubicacion')
          .eq('id_tienda', idTienda)
          .order('denominacion');

      print('📦 Received ${response.length} warehouses from Supabase');

      setState(() {
        _warehouses = List<Map<String, dynamic>>.from(response);
        _isLoadingWarehouses = false;
      });

      // Log warehouses for debugging
      for (final warehouse in _warehouses) {
        print('   - ${warehouse['denominacion']} (ID: ${warehouse['id']})');
      }
    } catch (e) {
      print('❌ Error loading warehouses: $e');
      setState(() {
        _warehouses = [];
        _isLoadingWarehouses = false;
      });
    }
  }

  List<InventoryProduct> _groupProducts(List<InventoryProduct> products) {
    print('🔄 Grouping ${products.length} products to eliminate duplicates...');

    Map<String, InventoryProduct> groupedMap = {};

    for (final product in products) {
      // Crear clave única que incluya TODOS los campos relevantes para evitar agrupamiento incorrecto
      final uniqueKey =
          '${product.id}_${product.idUbicacion}_${product.idVariante ?? 'null'}_${product.idOpcionVariante ?? 'null'}_${product.idPresentacion ?? 'null'}';

      print('🔍 Processing product: ${product.nombreProducto}');
      print('   - ID: ${product.id}');
      print('   - Ubicación: ${product.idUbicacion} (${product.ubicacion})');
      print('   - Variante: ${product.idVariante} (${product.variante})');
      print(
        '   - Opción Variante: ${product.idOpcionVariante} (${product.opcionVariante})',
      );
      print(
        '   - Presentación: ${product.idPresentacion} (${product.presentacion})',
      );
      print('   - Unique Key: $uniqueKey');
      print('   - Stock Disponible: ${product.stockDisponible}');

      if (groupedMap.containsKey(uniqueKey)) {
        final existing = groupedMap[uniqueKey]!;

        print('   ⚠️  DUPLICADO ENCONTRADO - Sumando cantidades:');
        print('      - Stock anterior: ${existing.stockDisponible}');
        print('      - Stock actual: ${product.stockDisponible}');

        // Sum quantities solo si es realmente el mismo producto con misma variante/presentación
        final newStockDisponible =
            existing.stockDisponible + product.stockDisponible;
        final newStockReservado =
            existing.stockReservado + product.stockReservado;
        final newCantidadFinal = existing.cantidadFinal + product.cantidadFinal;

        print('      - Stock sumado: $newStockDisponible');

        // Update existing product with summed quantities
        groupedMap[uniqueKey] = InventoryProduct(
          id: existing.id,
          nombreProducto: existing.nombreProducto,
          skuProducto: existing.skuProducto,
          idCategoria: existing.idCategoria,
          categoria: existing.categoria,
          idSubcategoria: existing.idSubcategoria,
          subcategoria: existing.subcategoria,
          idTienda: existing.idTienda,
          tienda: existing.tienda,
          idAlmacen: existing.idAlmacen,
          almacen: existing.almacen,
          idUbicacion: existing.idUbicacion,
          ubicacion: existing.ubicacion,
          idVariante: existing.idVariante,
          variante: existing.variante,
          idOpcionVariante: existing.idOpcionVariante,
          opcionVariante: existing.opcionVariante,
          idPresentacion: existing.idPresentacion,
          presentacion: existing.presentacion,
          cantidadInicial: existing.cantidadInicial + product.cantidadInicial,
          cantidadFinal: newCantidadFinal,
          stockDisponible: newStockDisponible,
          stockReservado: newStockReservado,
          stockDisponibleAjustado:
              existing.stockDisponibleAjustado +
              product.stockDisponibleAjustado,
          esVendible: existing.esVendible,
          esInventariable: existing.esInventariable,
          esElaborado: existing.esElaborado,
          precioVenta: existing.precioVenta,
          costoPromedio: existing.costoPromedio,
          margenActual: existing.margenActual,
          clasificacionAbc: existing.clasificacionAbc,
          abcDescripcion: existing.abcDescripcion,
          fechaUltimaActualizacion: existing.fechaUltimaActualizacion,
          totalCount: existing.totalCount,
          resumenInventario: existing.resumenInventario,
          infoPaginacion: existing.infoPaginacion,
        );
      } else {
        print('   ✅ Producto único - Agregando al mapa');
        groupedMap[uniqueKey] = product;
      }
    }

    final result = groupedMap.values.toList();
    print(
      '✅ Grouped ${products.length} products into ${result.length} unique items',
    );

    // Log final de productos agrupados
    print('📋 Productos finales después del agrupamiento:');
    for (int i = 0; i < result.length && i < 5; i++) {
      final item = result[i];
      print(
        '   ${i + 1}. ${item.nombreProducto} - ${item.variante} ${item.opcionVariante} - Stock: ${item.stockDisponible}',
      );
    }

    return result;
  }

  List<InventoryProduct> _groupProducts2(List<InventoryProduct> products) {
    print('🔄 Grouping ${products.length} products to eliminate duplicates...');

    Map<String, InventoryProduct> groupedMap = {};

    for (final product in products) {
      // Crear clave única que incluya TODOS los campos relevantes para evitar agrupamiento incorrecto
      final uniqueKey =
          '${product.id}_${product.idUbicacion}_${product.idVariante ?? 'null'}_${product.idOpcionVariante ?? 'null'}_${product.idPresentacion ?? 'null'}';

      print('🔍 Processing product: ${product.nombreProducto}');
      print('   - ID: ${product.id}');
      print('   - Ubicación: ${product.idUbicacion} (${product.ubicacion})');
      print('   - Variante: ${product.idVariante} (${product.variante})');
      print(
        '   - Opción Variante: ${product.idOpcionVariante} (${product.opcionVariante})',
      );
      print(
        '   - Presentación: ${product.idPresentacion} (${product.presentacion})',
      );
      print('   - Unique Key: $uniqueKey');
      print('   - Stock Disponible: ${product.stockDisponible}');

      if (groupedMap.containsKey(uniqueKey)) {
        print('   ⚠️  DUPLICADO ENCONTRADO - Conservando el primero y descartando este');
        print('      - Stock del primero: ${groupedMap[uniqueKey]!.stockDisponible}');
        print('      - Stock del duplicado: ${product.stockDisponible}');
        // No hacemos nada, conservamos el primer producto que ya está en el mapa
      } else {
        print('   ✅ Producto único - Agregando al mapa');
        groupedMap[uniqueKey] = product;
      }
    }

    final result = groupedMap.values.toList();
    print(
      '✅ Grouped ${products.length} products into ${result.length} unique items',
    );

    // Log final de productos agrupados
    print('📋 Productos finales después del agrupamiento:');
    for (int i = 0; i < result.length && i < 5; i++) {
      final item = result[i];
      print(
        '   ${i + 1}. ${item.nombreProducto} - ${item.variante} ${item.opcionVariante} - Stock: ${item.stockDisponible}',
      );
    }

    return result;
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasNextPage) return;

    setState(() => _isLoadingMore = true);
    _currentPage++;
    _loadInventoryData(reset: false);
  }

  void _toggleView() {
    setState(() {
      _isDetailedView = !_isDetailedView;
    });
    _loadInventoryData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_errorMessage.isNotEmpty) {
      return _buildErrorState();
    }

    return Scaffold(
      body: Column(
        children: [
          _buildSearchAndFilters(),
          _buildViewToggle(),
          if (_isDetailedView) ...[
            _buildInventorySummary(),
            Expanded(child: _buildDetailedInventoryList()),
          ] else ...[
            Expanded(child: _buildSummaryInventoryList()),
          ],
        ],
      ),
      floatingActionButton: _buildExportFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }

  Widget _buildViewToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Text(
            'Vista:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Resumen'),
                  icon: Icon(Icons.view_list, size: 18),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Detallado'),
                  icon: Icon(Icons.view_module, size: 18),
                  enabled: false,
                ),
              ],
              selected: {_isDetailedView},
              onSelectionChanged: (Set<bool> newSelection) {
                _toggleView();
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: AppColors.background,
                foregroundColor: AppColors.textSecondary,
                selectedBackgroundColor: AppColors.primary,
                selectedForegroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryInventoryList() {
    final filteredSummaries = _getFilteredInventorySummaries();

    return InventorySummaryList(
      summaries: filteredSummaries,
      isLoading: _isLoading,
      errorMessage: _errorMessage.isNotEmpty ? _errorMessage : null,
      onRetry: () => _loadInventoryData(),
      onItemTap: (summary) => _showInventorySummaryDetails(summary),
    );
  }

  Widget _buildDetailedInventoryList() {
    final filteredItems = _getFilteredInventoryItems();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: filteredItems.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == filteredItems.length) {
          return _buildLoadingMoreIndicator();
        }
        return _buildInventoryCard(filteredItems[index]);
      },
    );
  }

  List<InventorySummaryByUser> _getFilteredInventorySummaries() {
    List<InventorySummaryByUser> filtered = List.from(_inventorySummaries);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered =
          filtered.where((summary) {
            return summary.productoNombre.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                summary.variantDisplay.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
          }).toList();
    }

    // Apply stock filter
    switch (_stockFilter) {
      case 'Sin Stock':
        filtered =
            filtered
                .where((summary) => summary.cantidadTotalEnAlmacen <= 0)
                .toList();
        break;
      case 'Stock Bajo':
        filtered =
            filtered
                .where(
                  (summary) =>
                      summary.cantidadTotalEnAlmacen > 0 &&
                      summary.cantidadTotalEnAlmacen <= 10,
                )
                .toList();
        break;
      case 'Stock OK':
        filtered =
            filtered
                .where((summary) => summary.cantidadTotalEnAlmacen > 10)
                .toList();
        break;
      case 'Todos':
      default:
        break;
    }

    return filtered;
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
              // Debounce search - increased delay to prevent loading while typing
              Future.delayed(const Duration(milliseconds: 1500), () {
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
                  decoration: InputDecoration(
                    labelText: 'Almacén',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    suffixIcon:
                        _isLoadingWarehouses
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                            : null,
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'Todos',
                      child: Text(
                        'Todos',
                        style: TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ..._warehouses.map((warehouse) {
                      final warehouseName =
                          warehouse['denominacion'] as String? ?? 'Sin nombre';
                      final warehouseId = warehouse['id'].toString();

                      return DropdownMenuItem<String>(
                        value: warehouseId,
                        child: Tooltip(
                          message: warehouseName,
                          child: Text(
                            warehouseName,
                            style: const TextStyle(fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                  onChanged:
                      _isLoadingWarehouses
                          ? null
                          : (value) {
                            setState(() {
                              _selectedWarehouse = value!;
                              if (value == 'Todos') {
                                _selectedWarehouseId = null;
                              } else {
                                _selectedWarehouseId = int.tryParse(value);
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
                    _loadInventoryData();
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: ListTile(
        leading: CircleAvatar(
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
        onTap: () => _showInventoryProductDetails(item),
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
    if (_selectedWarehouse != 'Todos' && _selectedWarehouseId != null) {
      filtered =
          filtered
              .where((item) => item.idAlmacen == _selectedWarehouseId)
              .toList();
      print('🔍 Filtering by warehouse ID: $_selectedWarehouseId');
      print('📋 Filtered to ${filtered.length} items for selected warehouse');
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

  Widget _buildDetailSection(
      String title,
      IconData icon,
      List<Widget> children,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
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
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.inventory_2,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                              '${item.variante} ${item.opcionVariante}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Stock Status Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
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
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Estado de Stock',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.stockLevelColor,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        item.stockLevel,
                                        style: const TextStyle(
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
                          const SizedBox(height: 16),

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
                          const SizedBox(height: 16),

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
                          const SizedBox(height: 16),

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
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          label: const Text('Transferir'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Cerrar'),
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

  void _showInventorySummaryDetails(InventorySummaryByUser summary) {
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
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.inventory_2,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              summary.productoNombre,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (summary.variantDisplay.isNotEmpty)
                              Text(
                                summary.variantDisplay,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Stock Status Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: summary.stockLevelColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: summary.stockLevelColor.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.inventory,
                                      color: summary.stockLevelColor,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Resumen de Stock',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Total en Almacén',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          '${summary.cantidadTotalEnAlmacen.toStringAsFixed(0)} unidades',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: summary.stockLevelColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: summary.stockLevelColor,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        summary.stockLevel,
                                        style: const TextStyle(
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
                          const SizedBox(height: 16),

                          // Distribution Information
                          _buildDetailSection(
                            'Distribución',
                            Icons.location_on_outlined,
                            [
                              _buildDetailRow(
                                'Zonas diferentes',
                                '${summary.zonasDiferentes}',
                              ),
                              _buildDetailRow(
                                'Presentaciones diferentes',
                                '${summary.presentacionesDiferentes}',
                              ),
                              _buildDetailRow(
                                'Unidades base totales',
                                '${summary.cantidadTotalEnUnidadesBase.toStringAsFixed(1)}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            setState(() {
                              _isDetailedView = true;
                              _searchQuery = summary.productoNombre;
                              _searchController.text = summary.productoNombre;
                            });
                            _loadInventoryData();
                          },
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text('Ver Detalles'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Cerrar'),
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

  /// Construye el FAB de exportación en la parte izquierda
  Widget _buildExportFAB() {
    return FloatingActionButton.extended(
      onPressed: () => showInventoryExportDialog(context),
      backgroundColor: AppColors.success,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.file_download_outlined),
      label: const Text('Exportar'),
      tooltip: 'Exportar inventario',
    );
  }
}
