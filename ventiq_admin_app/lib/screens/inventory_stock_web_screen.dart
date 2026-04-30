import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/inventory.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/inventory_summary_card_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryStockWebScreen extends StatefulWidget {
  final bool isAlmacenero;
  final int? assignedWarehouseId;

  const InventoryStockWebScreen({
    super.key,
    this.isAlmacenero = false,
    this.assignedWarehouseId,
  });

  @override
  State<InventoryStockWebScreen> createState() => _InventoryStockWebScreenState();
}

class _InventoryStockWebScreenState extends State<InventoryStockWebScreen> {
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
  bool _showDescriptionInSelectors = false; // Configuration for showing product descriptions

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
    _loadShowDescriptionConfig();
    _loadWarehouses();
    
    // Si es almacenero, establecer filtro por defecto
    if (widget.isAlmacenero && widget.assignedWarehouseId != null) {
      _selectedWarehouseId = widget.assignedWarehouseId;
    }
    
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

  Future<void> _loadShowDescriptionConfig() async {
    try {
      final showDescription = await _userPreferencesService.getShowDescriptionInSelectors();
      setState(() {
        _showDescriptionInSelectors = showDescription;
      });
      print('📋 Configuración "Mostrar descripción en selectores" cargada: $showDescription');
    } catch (e) {
      print('❌ Error al cargar configuración de mostrar descripción: $e');
      // Mantener valor por defecto (false)
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
          _stockFilter,
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

  Future<void> _showWarehouseMenu(BuildContext anchorContext) async {
    if (widget.isAlmacenero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Filtro bloqueado: solo puedes ver tu almacén asignado',
          ),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(
          Offset(0, box.size.height + 4),
          ancestor: overlay,
        ),
        box.localToGlobal(
          box.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final items = <PopupMenuEntry<String>>[
      _buildMenuItem(
        value: 'Todos',
        label: 'Todos los almacenes',
        icon: Icons.all_inclusive_rounded,
        color: AppColors.textSecondary,
        selected: _selectedWarehouseId == null,
      ),
      const PopupMenuDivider(height: 1),
      ..._warehouses.map((warehouse) {
        final id = warehouse['id'].toString();
        final name = warehouse['denominacion'] as String? ?? 'Sin nombre';
        return _buildMenuItem(
          value: id,
          label: name,
          icon: Icons.warehouse_rounded,
          color: const Color(0xFF4A90E2),
          selected: _selectedWarehouseId?.toString() == id,
        );
      }),
    ];

    final selected = await showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(
        minWidth: box.size.width,
        maxWidth: box.size.width < 240 ? 280 : box.size.width,
        maxHeight: 360,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      color: Colors.white,
      elevation: 8,
      items: items,
    );

    if (selected == null) return;
    setState(() {
      _selectedWarehouse = selected;
      _selectedWarehouseId = selected == 'Todos' ? null : int.tryParse(selected);
    });
    _loadInventoryData();
  }

  Future<void> _showStockMenu(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(
          Offset(0, box.size.height + 4),
          ancestor: overlay,
        ),
        box.localToGlobal(
          box.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final options = const [
      ('Todos', Icons.all_inclusive_rounded, AppColors.textSecondary),
      ('Sin Stock', Icons.remove_circle_outline_rounded, AppColors.error),
      ('Stock Bajo', Icons.warning_amber_rounded, AppColors.warning),
      ('Stock OK', Icons.check_circle_outline_rounded, AppColors.success),
    ];

    final selected = await showMenu<String>(
      context: context,
      position: position,
      constraints: BoxConstraints(
        minWidth: box.size.width,
        maxWidth: box.size.width < 220 ? 240 : box.size.width,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      color: Colors.white,
      elevation: 8,
      items: options
          .map(
            (o) => _buildMenuItem(
              value: o.$1,
              label: o.$1,
              icon: o.$2,
              color: o.$3,
              selected: _stockFilter == o.$1,
            ),
          )
          .toList(),
    );

    if (selected == null) return;
    setState(() => _stockFilter = selected);
    _loadInventoryData();
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.primary,
            ),
        ],
      ),
    );
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
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildSearchAndFilters(),
          if (_isDetailedView) ...[
            _buildInventorySummary(),
            Expanded(child: _buildDetailedInventoryList()),
          ] else ...[
            Expanded(child: _buildSummaryInventoryList()),
          ],
        ],
      ),
    );
  }


  Widget _buildSummaryInventoryList() {
    final filteredSummaries = _getFilteredInventorySummaries();

    // Debug information
    print('🔍 _buildSummaryInventoryList called');
    print('📊 _inventorySummaries.length: ${_inventorySummaries.length}');
    print('📊 filteredSummaries.length: ${filteredSummaries.length}');
    print('📊 _isLoading: $_isLoading');
    print('📊 _errorMessage: $_errorMessage');
    
    if (_inventorySummaries.isNotEmpty) {
      print('📋 First summary: ${_inventorySummaries[0].productoNombre} - ${_inventorySummaries[0].cantidadTotalEnAlmacen} units');
    }

    return InventorySummaryListWeb(
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
    // ✅ Todos los filtros ahora se manejan en el servidor
    // Solo devolvemos los datos tal como vienen del servidor
    print('🔍 _getFilteredInventorySummaries called');
    print('📊 Summaries count (server-filtered): ${_inventorySummaries.length}');
    print('📊 Search query: "$_searchQuery"');
    print('📊 Stock filter: "$_stockFilter"');
    print('📊 All filtering is now done on the server side');
    
    return _inventorySummaries;
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
    final selectedWarehouseLabel = _selectedWarehouseId == null
        ? 'Todos'
        : (_warehouses.firstWhere(
              (w) => w['id'].toString() == _selectedWarehouseId.toString(),
              orElse: () => {'denominacion': 'Almacén'},
            )['denominacion'] as String? ??
            'Almacén');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          final searchField = _buildSearchField();
          final warehouseSelect = Builder(
            builder: (ctx) => _buildFilterSelect(
              icon: Icons.warehouse_rounded,
              label: 'Almacén',
              value: selectedWarehouseLabel,
              color: const Color(0xFF4A90E2),
              onTap: () => _showWarehouseMenu(ctx),
            ),
          );
          final stockSelect = Builder(
            builder: (ctx) => _buildFilterSelect(
              icon: Icons.inventory_2_rounded,
              label: 'Stock',
              value: _stockFilter,
              color: const Color(0xFF10B981),
              onTap: () => _showStockMenu(ctx),
            ),
          );

          if (isWide) {
            return Row(
              children: [
                Expanded(flex: 5, child: searchField),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: warehouseSelect),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: stockSelect),
                const SizedBox(width: 8),
                _buildViewToggle(),
              ],
            );
          }
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 8),
                  _buildViewToggle(),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: warehouseSelect),
                  const SizedBox(width: 8),
                  Expanded(child: stockSelect),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o SKU...',
          hintStyle: const TextStyle(
            fontSize: 13,
            color: AppColors.textLight,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.textSecondary,
            size: 19,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _loadInventoryData();
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: AppColors.primary,
              width: 1.4,
            ),
          ),
        ),
        style: const TextStyle(fontSize: 13.5),
        onChanged: (value) {
          setState(() => _searchQuery = value);
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_searchQuery == value) {
              _loadInventoryData();
            }
          });
        },
      ),
    );
  }

  Widget _buildFilterSelect({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              color: AppColors.textLight,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            icon: Icons.view_agenda_rounded,
            tooltip: 'Resumen',
            active: !_isDetailedView,
            onTap: () {
              if (_isDetailedView) _toggleView();
            },
          ),
          _buildToggleButton(
            icon: Icons.view_list_rounded,
            tooltip: 'Detalle',
            active: _isDetailedView,
            onTap: () {
              if (!_isDetailedView) _toggleView();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 36,
          height: 32,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 16,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildInventorySummary() {
    if (_inventorySummary == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 600;
          final cards = [
            _buildSummaryCard(
              'Total Inventario',
              _inventorySummary!.totalInventario.toString(),
              Icons.inventory_rounded,
              AppColors.info,
            ),
            _buildSummaryCard(
              'Sin Stock',
              _inventorySummary!.totalSinStock.toString(),
              Icons.remove_circle_outline_rounded,
              AppColors.error,
            ),
            _buildSummaryCard(
              'Stock Bajo',
              _inventorySummary!.totalConCantidadBaja.toString(),
              Icons.warning_amber_rounded,
              AppColors.warning,
            ),
          ];
          if (isWide) {
            return Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 10),
                Expanded(child: cards[1]),
                const SizedBox(width: 10),
                Expanded(child: cards[2]),
              ],
            );
          }
          return Row(
            children: cards
                .map((c) => Expanded(child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: c,
                    )))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: color,
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

  Widget _buildInventoryCard(InventoryProduct item) {
    final stockStatus = _getStockStatus(item.stockDisponible.toInt());
    final description = (item.descripcion?.isNotEmpty ?? false)
        ? item.descripcion
        : ((item.descripcionCorta?.isNotEmpty ?? false)
            ? item.descripcionCorta
            : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showInventoryProductDetails(item),
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: stockStatus.color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: stockStatus.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.inventory_2_rounded,
                          color: stockStatus.color,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.nombreProducto,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.1,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_showDescriptionInSelectors &&
                                description != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                description,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontStyle: FontStyle.italic,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if ('${item.variante} ${item.opcionVariante}'
                                    .trim()
                                    .isNotEmpty)
                                  _buildMetaChip(
                                    Icons.label_outline_rounded,
                                    '${item.variante} ${item.opcionVariante}'
                                        .trim(),
                                    AppColors.textSecondary,
                                  ),
                                _buildMetaChip(
                                  Icons.warehouse_rounded,
                                  item.almacen,
                                  const Color(0xFF4A90E2),
                                ),
                                if (item.ubicacion.isNotEmpty)
                                  _buildMetaChip(
                                    Icons.location_on_outlined,
                                    item.ubicacion,
                                    const Color(0xFF8B5CF6),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.stockDisponible.toStringAsFixed(0),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: stockStatus.color,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: stockStatus.color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              stockStatus.label,
                              style: TextStyle(
                                color: stockStatus.color,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
                            // Mostrar descripción si está habilitado y existe
                            if (_showDescriptionInSelectors)
                              if (item.descripcion != null && item.descripcion!.isNotEmpty)
                                Text(
                                  item.descripcion!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              else if (item.descripcionCorta != null && item.descripcionCorta!.isNotEmpty)
                                Text(
                                  item.descripcionCorta!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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

}
