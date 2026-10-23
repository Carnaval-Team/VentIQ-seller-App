import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/inventory.dart';
import '../models/lote_stock.dart';
import '../services/inventory_service.dart';
import '../utils/stock_mixto_formatter.dart';
import '../services/user_preferences_service.dart';
import '../widgets/inventory_summary_card.dart';
import '../widgets/inventory_export_dialog.dart';
import '../widgets/lote_expiry_widgets.dart';
import '../widgets/asignar_lote_dialog.dart';
import '../services/permissions_service.dart';
import 'caducidades_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryStockScreen extends StatefulWidget {
  final bool isAlmacenero;
  final int? assignedWarehouseId;

  const InventoryStockScreen({
    super.key,
    this.isAlmacenero = false,
    this.assignedWarehouseId,
  });

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
  bool _isLoadingBreakdowns = false;
  Map<String, StockBreakdown> _breakdownsByLocation = {};
  Map<int, StockBreakdown> _breakdownsByProduct = {};
  /// Clave: `${idProducto}_${idUbicacion}` → lotes con saldo
  Map<String, List<LoteStockInfo>> _lotesByLocation = {};
  /// Clave: idProducto → lotes en todas las ubicaciones cargadas
  Map<int, List<LoteStockInfo>> _lotesByProduct = {};
  String _selectedWarehouse = 'Todos';
  int? _selectedWarehouseId;
  String _stockFilter = 'Todos';
  String _errorMessage = '';
  bool _isDetailedView = false; // Toggle between summary and detailed view
  bool _showDescriptionInSelectors =
      false; // Configuration for showing product descriptions
  bool _canAssignLote = false;

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
    _loadCanAssignLote();
    _loadWarehouses();

    // Si es almacenero, establecer filtro por defecto
    if (widget.isAlmacenero && widget.assignedWarehouseId != null) {
      _selectedWarehouseId = widget.assignedWarehouseId;
    }

    _loadInventoryData();
  }

  Future<void> _loadCanAssignLote() async {
    final can = await PermissionsService().canPerformAction(
      'inventory.assign_lote',
    );
    if (!mounted) return;
    setState(() => _canAssignLote = can);
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
      final showDescription = await _userPreferencesService
          .getShowDescriptionInSelectors();
      setState(() {
        _showDescriptionInSelectors = showDescription;
      });
      print(
        '📋 Configuración "Mostrar descripción en selectores" cargada: $showDescription',
      );
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

  Future<void> _refreshInventoryData() async {
    await _loadInventoryData(reset: true, showFullScreenLoading: false);
  }

  Future<void> _loadInventoryData({
    bool reset = true,
    bool showFullScreenLoading = true,
  }) async {
    if (reset) {
      setState(() {
        if (showFullScreenLoading) {
          _isLoading = true;
          _inventoryProducts = <InventoryProduct>[];
          _inventorySummaries = <InventorySummaryByUser>[];
        }
        _errorMessage = '';
        _currentPage = 1;
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

        await Future.wait([
          _loadBreakdowns(),
          _loadLotesForDetailedProducts(),
        ]);

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

        await Future.wait([
          _loadSummaryBreakdowns(),
          _loadLotesForSummaries(),
        ]);

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
    // Agrupa por producto+ubicación+variante+presentación (no por id de snapshot).
    // Con varios lotes el ledger tiene varias filas: hay que SUMAR cantidades.
    final Map<String, InventoryProduct> groupedMap = {};

    for (final product in products) {
      final uniqueKey =
          '${product.idProducto}_${product.idUbicacion}_${product.idVariante ?? 'null'}_${product.idOpcionVariante ?? 'null'}_${product.idPresentacion ?? 'null'}';

      final existing = groupedMap[uniqueKey];
      if (existing == null) {
        groupedMap[uniqueKey] = product;
        continue;
      }

      groupedMap[uniqueKey] = existing.copyWithSums(
        cantidadInicial: existing.cantidadInicial + product.cantidadInicial,
        cantidadFinal: existing.cantidadFinal + product.cantidadFinal,
        stockDisponible: existing.stockDisponible + product.stockDisponible,
        stockReservado: existing.stockReservado + product.stockReservado,
        stockDisponibleAjustado:
            existing.stockDisponibleAjustado + product.stockDisponibleAjustado,
        fechaUltimaActualizacion:
            product.fechaUltimaActualizacion.isAfter(existing.fechaUltimaActualizacion)
                ? product.fechaUltimaActualizacion
                : existing.fechaUltimaActualizacion,
      );
    }

    return groupedMap.values.toList();
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasNextPage) return;

    setState(() => _isLoadingMore = true);
    _currentPage++;
    _loadInventoryData(reset: false);
  }

  Future<void> _loadBreakdowns() async {
    if (_inventoryProducts.isEmpty) return;
    setState(() => _isLoadingBreakdowns = true);
    try {
      final breakdowns = await InventoryService.getStockBreakdownsByLocation(
        _inventoryProducts,
      );
      if (mounted) {
        setState(() => _breakdownsByLocation = breakdowns);
      }
    } catch (e) {
      print('❌ Error loading stock breakdowns: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingBreakdowns = false);
      }
    }
  }

  Future<void> _loadSummaryBreakdowns() async {
    if (_inventorySummaries.isEmpty) return;
    setState(() => _isLoadingBreakdowns = true);
    try {
      final breakdowns = await InventoryService.getStockBreakdownsByProduct(
        _inventorySummaries,
        warehouseId: _selectedWarehouseId,
      );
      if (mounted) {
        setState(() => _breakdownsByProduct = breakdowns);
      }
    } catch (e) {
      print('❌ Error loading summary stock breakdowns: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingBreakdowns = false);
      }
    }
  }

  Future<void> _loadLotesForDetailedProducts() async {
    if (_inventoryProducts.isEmpty) return;
    try {
      final ubicaciones = _inventoryProducts
          .map((p) => p.idUbicacion)
          .where((id) => id > 0)
          .toSet()
          .toList();
      final byUbicacion = <int, List<LoteStockInfo>>{};
      await Future.wait(
        ubicaciones.map((id) async {
          byUbicacion[id] = await InventoryService.getLotesEnUbicacion(id);
        }),
      );

      final byLoc = <String, List<LoteStockInfo>>{};
      final byProd = <int, List<LoteStockInfo>>{};
      String loteIdentity(LoteStockInfo l) =>
          '${l.idProducto}|${l.idUbicacion}|${l.idVariante}|${l.idOpcionVariante}|${l.idPresentacion}|${l.idLote}';

      for (final p in _inventoryProducts) {
        final lotes = (byUbicacion[p.idUbicacion] ?? [])
            .where((l) => l.idProducto == p.idProducto)
            .toList();
        final key = '${p.idProducto}_${p.idUbicacion}';
        // Una sola lista por producto+ubicación (no addAll por cada presentación).
        byLoc.putIfAbsent(key, () => lotes);
      }
      for (final lotes in byLoc.values) {
        for (final l in lotes) {
          final list = byProd.putIfAbsent(l.idProducto, () => []);
          if (list.any((x) => loteIdentity(x) == loteIdentity(l))) continue;
          list.add(l);
        }
      }
      if (mounted) {
        setState(() {
          _lotesByLocation = byLoc;
          _lotesByProduct = byProd;
        });
      }
    } catch (e) {
      print('⚠️ Error cargando lotes stock: $e');
    }
  }

  Future<void> _loadLotesForSummaries() async {
    if (_inventorySummaries.isEmpty) return;
    try {
      // En vista resumen no hay id_ubicacion por fila; usamos ubicaciones
      // del inventario detallado filtrado por almacén si hace falta.
      final products = await InventoryService.getInventoryProducts(
        idAlmacen: _selectedWarehouseId,
        pagina: 1,
        limite: 200,
      );
      final ubicaciones = products.products
          .map((p) => p.idUbicacion)
          .where((id) => id > 0)
          .toSet()
          .toList();
      final byUbicacion = <int, List<LoteStockInfo>>{};
      await Future.wait(
        ubicaciones.map((id) async {
          byUbicacion[id] = await InventoryService.getLotesEnUbicacion(id);
        }),
      );

      final productIds = _inventorySummaries.map((s) => s.idProducto).toSet();
      final byProd = <int, List<LoteStockInfo>>{};
      String loteIdentity(LoteStockInfo l) =>
          '${l.idProducto}|${l.idUbicacion}|${l.idVariante}|${l.idOpcionVariante}|${l.idPresentacion}|${l.idLote}';
      for (final entry in byUbicacion.entries) {
        for (final lote in entry.value) {
          if (!productIds.contains(lote.idProducto)) continue;
          final list = byProd.putIfAbsent(lote.idProducto, () => []);
          if (list.any((x) => loteIdentity(x) == loteIdentity(lote))) {
            continue;
          }
          list.add(lote);
        }
      }
      if (mounted) {
        // Total = suma de todos los saldos (con y sin lote), no solo lotes etiquetados.
        final saldosByProduct = <int, double>{};
        for (final idUbi in ubicaciones) {
          final saldos = await InventoryService.getSaldosAgregadosPorClave(
            idUbicacion: idUbi,
          );
          for (final entry in saldos.entries) {
            final idProd = int.tryParse(entry.key.split('|').first) ?? 0;
            if (idProd <= 0 || !productIds.contains(idProd)) continue;
            saldosByProduct[idProd] =
                (saldosByProduct[idProd] ?? 0) + entry.value;
          }
        }
        setState(() {
          _lotesByProduct = byProd;
          if (saldosByProduct.isNotEmpty) {
            _inventorySummaries = _inventorySummaries.map((s) {
              final sum = saldosByProduct[s.idProducto];
              if (sum == null || sum <= 0) return s;
              if ((sum - s.cantidadTotalEnAlmacen).abs() < 0.0001) return s;
              return InventorySummaryByUser(
                idProducto: s.idProducto,
                productoNombre: s.productoNombre,
                productoSku: s.productoSku,
                productoDescripcion: s.productoDescripcion,
                idVariante: s.idVariante,
                varianteValor: s.varianteValor,
                idOpcionVariante: s.idOpcionVariante,
                opcionVarianteValor: s.opcionVarianteValor,
                cantidadTotalEnUnidadesBase: sum,
                cantidadTotalEnAlmacen: sum,
                zonasDiferentes: s.zonasDiferentes,
                presentacionesDiferentes: s.presentacionesDiferentes,
              );
            }).toList();
          }
        });
      }
    } catch (e) {
      print('⚠️ Error cargando lotes resumen: $e');
    }
  }

  void _showWarehouseFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Almacén'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isAlmacenero) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Filtro bloqueado - Solo puedes ver tu almacén asignado',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              ..._warehouses.map((warehouse) {
                final warehouseName =
                    warehouse['denominacion'] as String? ?? 'Sin nombre';
                final warehouseId = warehouse['id'].toString();
                final isSelected = _selectedWarehouse == warehouseId;

                return RadioListTile<String>(
                  value: warehouseId,
                  groupValue: _selectedWarehouse,
                  onChanged: widget.isAlmacenero
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
                          Navigator.of(context).pop();
                          _loadInventoryData();
                        },
                  title: Text(
                    warehouseName,
                    style: TextStyle(
                      fontSize: 14,
                      color: widget.isAlmacenero
                          ? Colors.grey.shade600
                          : Colors.black,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    'ID: ${warehouse['id']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  void _showStockFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filtrar por Stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              [
                'Todos',
                'Con stock',
                'Sin Stock',
                'Stock Bajo',
                'Stock OK',
                'Por vencer',
                'Vencidos',
              ].map(
                (value) {
                  final isSelected = _stockFilter == value;
                  return RadioListTile<String>(
                    value: value,
                    groupValue: _stockFilter,
                    onChanged: (value) {
                      setState(() => _stockFilter = value!);
                      Navigator.of(context).pop();
                      _loadInventoryData();
                    },
                    title: Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
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
      floatingActionButton: _buildActionsFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
      print(
        '📋 First summary: ${_inventorySummaries[0].productoNombre} - ${_inventorySummaries[0].cantidadTotalEnAlmacen} units',
      );
    }

    return InventorySummaryList(
      summaries: filteredSummaries,
      isLoading: _isLoading,
      errorMessage: _errorMessage.isNotEmpty ? _errorMessage : null,
      onRetry: () => _loadInventoryData(),
      onRefresh: _refreshInventoryData,
      onItemTap: (summary) => _showInventorySummaryDetails(summary),
      breakdowns: _breakdownsByProduct,
      lotesByProduct: _lotesByProduct,
    );
  }

  Widget _buildDetailedInventoryList() {
    final groups = _getFilteredStockGroups();

    return RefreshIndicator(
      onRefresh: _refreshInventoryData,
      color: AppColors.primary,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: groups.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == groups.length) {
            return _buildLoadingMoreIndicator();
          }
          return _buildInventoryGroupCard(groups[index]);
        },
      ),
    );
  }

  /// Una card por producto+ubicación+variante (todas las presentaciones juntas).
  List<_StockCardGroup> _groupRowsForDisplay(List<InventoryProduct> rows) {
    final map = <String, List<InventoryProduct>>{};
    for (final p in rows) {
      final key =
          '${p.idProducto}_${p.idUbicacion}_${p.idVariante ?? 'null'}_${p.idOpcionVariante ?? 'null'}';
      map.putIfAbsent(key, () => []).add(p);
    }
    return map.values.map(_StockCardGroup.new).toList();
  }

  List<InventorySummaryByUser> _getFilteredInventorySummaries() {
    // ✅ Los filtros principales se manejan en el servidor, pero se refina
    // el filtro de stock usando el desglose real (enAlmacen).
    print('🔍 _getFilteredInventorySummaries called');
    print(
      '📊 Summaries count (server-filtered): ${_inventorySummaries.length}',
    );
    print('📊 Search query: "$_searchQuery"');
    print('📊 Stock filter: "$_stockFilter"');

    var filtered = List<InventorySummaryByUser>.from(_inventorySummaries);

    switch (_stockFilter) {
      case 'Con stock':
        filtered = filtered.where((s) {
          return s.stock.equivalenteBase > 0;
        }).toList();
        break;
      case 'Sin Stock':
        filtered = filtered.where((s) {
          return s.stock.equivalenteBase <= 0;
        }).toList();
        break;
      case 'Stock Bajo':
        filtered = filtered.where((s) {
          final stock = s.stock.equivalenteBase;
          return stock > 0 && stock <= 10;
        }).toList();
        break;
      case 'Stock OK':
        filtered = filtered.where((s) {
          return s.stock.equivalenteBase > 10;
        }).toList();
        break;
      case 'Por vencer':
        filtered = filtered.where((s) {
          final lotes = _lotesByProduct[s.idProducto] ?? const <LoteStockInfo>[];
          return lotes.any((l) => l.estadoCaducidad == 'expiring');
        }).toList();
        break;
      case 'Vencidos':
        filtered = filtered.where((s) {
          final lotes = _lotesByProduct[s.idProducto] ?? const <LoteStockInfo>[];
          return lotes.any((l) => l.estadoCaducidad == 'expired');
        }).toList();
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
          Row(
            children: [
              Expanded(
                child: TextField(
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
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: Icon(Icons.filter_list, color: AppColors.primary),
                tooltip: 'Filtros',
                onSelected: (value) {
                  if (value == 'warehouse') {
                    _showWarehouseFilterDialog();
                  } else if (value == 'stock') {
                    _showStockFilterDialog();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'warehouse',
                    child: Row(
                      children: [
                        Icon(
                          Icons.warehouse,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text('Almacén'),
                        const Spacer(),
                        Text(
                          _selectedWarehouse,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'stock',
                    child: Row(
                      children: [
                        Icon(
                          Icons.inventory_2,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text('Stock'),
                        const Spacer(),
                        Text(
                          _stockFilter,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.background,
      child: Row(
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
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

  Widget _buildInventoryGroupCard(_StockCardGroup group) {
    final item = group.primary;
    final key = '${item.idProducto}_${item.idUbicacion}';
    final breakdown = _breakdownsByLocation[key];
    // No sumar unidades de distintas presentaciones; el mixto es la verdad.
    final hasStock = group.rows.any((r) => r.cantidadFinal > 0) ||
        (breakdown?.enAlmacen ?? 0) > 0;
    final stockStatus = hasStock
        ? _getStockStatus(
            breakdown?.enAlmacen.toInt() ??
                group.rows
                    .map((r) => r.cantidadFinal)
                    .fold<double>(0, (a, b) => a > b ? a : b)
                    .toInt(),
          )
        : _getStockStatus(0);
    final lotes = (_lotesByLocation[key] ?? const <LoteStockInfo>[])
        .where(
          (l) =>
              l.idVariante == item.idVariante &&
              l.idOpcionVariante == item.idOpcionVariante,
        )
        .toList();

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
            if (_showDescriptionInSelectors)
              if (item.descripcion != null && item.descripcion!.isNotEmpty)
                Text(
                  item.descripcion!,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              else if (item.descripcionCorta != null &&
                  item.descripcionCorta!.isNotEmpty)
                Text(
                  item.descripcionCorta!,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            Text('${item.variante} ${item.opcionVariante}'),
            Text('Almacén: ${item.almacen}'),
            if (item.ubicacion.isNotEmpty)
              Text(
                'Zona: ${item.ubicacion}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary.withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            LoteExpirySubtitle(lotes: lotes),
          ],
        ),
        isThreeLine: true,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                group.stockMixtoTexto,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                textAlign: TextAlign.end,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
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
        ),
        onTap: () => _showInventoryGroupDetails(group),
      ),
    );
  }

  List<_StockCardGroup> _getFilteredStockGroups() {
    List<InventoryProduct> filtered = List.from(_inventoryProducts);

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        return item.nombreProducto.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ) ||
            item.skuProducto.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    if (_selectedWarehouse != 'Todos' && _selectedWarehouseId != null) {
      filtered = filtered
          .where((item) => item.idAlmacen == _selectedWarehouseId)
          .toList();
    }

    var groups = _groupRowsForDisplay(filtered);

    bool groupHasStock(_StockCardGroup g) =>
        g.rows.any((r) => r.cantidadFinal > 0);

    /// Mayor cantidad en una sola presentación (no sumar UOMs distintas).
    double groupMaxQty(_StockCardGroup g) => g.rows
        .map((r) => r.cantidadFinal)
        .fold<double>(0, (a, b) => a > b ? a : b);

    switch (_stockFilter) {
      case 'Con stock':
        groups = groups.where(groupHasStock).toList();
        break;
      case 'Sin Stock':
        groups = groups.where((g) => !groupHasStock(g)).toList();
        break;
      case 'Stock Bajo':
        groups = groups.where((g) {
          final maxQ = groupMaxQty(g);
          return maxQ > 0 && maxQ <= 10;
        }).toList();
        break;
      case 'Stock OK':
        groups = groups.where((g) => groupMaxQty(g) > 10).toList();
        break;
      case 'Por vencer':
        groups = groups.where((g) {
          final key = '${g.primary.idProducto}_${g.primary.idUbicacion}';
          final lotes = _lotesByLocation[key] ?? const <LoteStockInfo>[];
          return lotes.any((l) => l.estadoCaducidad == 'expiring');
        }).toList();
        break;
      case 'Vencidos':
        groups = groups.where((g) {
          final key = '${g.primary.idProducto}_${g.primary.idUbicacion}';
          final lotes = _lotesByLocation[key] ?? const <LoteStockInfo>[];
          return lotes.any((l) => l.estadoCaducidad == 'expired');
        }).toList();
        break;
      case 'Todos':
      default:
        break;
    }

    return groups;
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

  Widget _buildStockBreakdownSection(
    InventoryProduct item, {
    String? enAlmacenLabel,
  }) {
    final key = '${item.idProducto}_${item.idUbicacion}';
    final breakdown = _breakdownsByLocation[key];

    if (breakdown == null) {
      return _buildDetailSection('Stock Real', Icons.inventory_2_outlined, [
        _buildDetailRow(
          'En almacén',
          enAlmacenLabel ?? item.cantidadConPresentacion,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Calculando desglose de pedidos...',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ]);
    }

    return _buildDetailSection('Stock Real', Icons.inventory_2_outlined, [
      if (enAlmacenLabel != null)
        _buildDetailRow('En almacén (mixto)', enAlmacenLabel)
      else
        _buildBreakdownRow(
          'En almacén',
          breakdown.enAlmacen,
          AppColors.success,
          Icons.warehouse_outlined,
        ),
      _buildBreakdownRow(
        'En pedidos',
        breakdown.enPedidos,
        AppColors.warning,
        Icons.shopping_bag_outlined,
      ),
      _buildBreakdownRow(
        'Entregando',
        breakdown.entregando,
        AppColors.info,
        Icons.local_shipping_outlined,
      ),
    ]);
  }

  Widget _buildBreakdownRow(
    String label,
    double value,
    Color color,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${value.toStringAsFixed(2)} unidades',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStockBreakdownSection(InventorySummaryByUser summary) {
    final breakdown = _breakdownsByProduct[summary.idProducto];
    final logistics = breakdown?.logisticsStatus;

    return _buildDetailSection('Existencia física', Icons.inventory_2_outlined, [
      _buildDetailRow('Stock', summary.stock.texto),
      _buildDetailRow(
        'Equivalente',
        '${StockMixtoFormatter.cantidad(summary.stock.equivalenteBase)} '
            '${StockMixtoFormatter.plural(summary.stock.nombrePresentacionBase, summary.stock.equivalenteBase)} base',
      ),
      if (logistics != null &&
          (logistics.tienePedidos || logistics.tieneEntregas)) ...[
        const SizedBox(height: 8),
        _buildDetailRow(
          'Logística',
          [
            if (logistics.tienePedidos) 'Pedidos pendientes',
            if (logistics.tieneEntregas) 'Entregas en curso',
          ].join(' · '),
        ),
      ],
    ]);
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 280;
          final labelWidget = Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          );
          final valueWidget = Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
            softWrap: true,
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelWidget,
                const SizedBox(height: 2),
                valueWidget,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 100, child: labelWidget),
              const SizedBox(width: 8),
              Expanded(child: valueWidget),
            ],
          );
        },
      ),
    );
  }

  void _showInventoryGroupDetails(_StockCardGroup group) {
    final item = group.primary;
    final allLotes =
        _lotesByLocation['${item.idProducto}_${item.idUbicacion}'] ??
            const <LoteStockInfo>[];
    final lotes = allLotes
        .where(
          (l) =>
              l.idVariante == item.idVariante &&
              l.idOpcionVariante == item.idOpcionVariante,
        )
        .toList();
    final presentacionLabels = <int, String>{
      for (final r in group.rows)
        if (r.idPresentacion != null) r.idPresentacion!: r.presentacion,
    };
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final narrow = screenW < 420;
    final pad = narrow ? 12.0 : 20.0;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 12 : 24,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: screenH * 0.85,
            minWidth: 0,
          ),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nombreProducto,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_showDescriptionInSelectors &&
                              ((item.descripcion?.isNotEmpty ?? false) ||
                                  (item.descripcionCorta?.isNotEmpty ??
                                      false)))
                            Text(
                              (item.descripcion?.isNotEmpty ?? false)
                                  ? item.descripcion!
                                  : item.descripcionCorta!,
                              style: const TextStyle(
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
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
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
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  const Flexible(
                                    child: Text(
                                      'Estado de Stock',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 220,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Stock Actual (mixto)',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          group.stockMixtoTexto,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: item.stockLevelColor,
                                          ),
                                          softWrap: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getStockStatus(
                                        group.cantidadTotal.toInt(),
                                      ).color,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      _getStockStatus(
                                        group.cantidadTotal.toInt(),
                                      ).label,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailSection(
                          'Por presentación',
                          Icons.layers_outlined,
                          [
                            for (final r in group.rows)
                              _buildDetailRow(
                                r.presentacion,
                                r.cantidadConPresentacion,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildStockBreakdownSection(
                          item,
                          enAlmacenLabel: group.stockMixtoTexto,
                        ),
                        const SizedBox(height: 12),
                        if (lotes.isNotEmpty) ...[
                          LoteExpirySection(
                            title: 'Stock por lote y presentación',
                            lotes: lotes,
                            showPresentacion: true,
                            presentacionLabels: presentacionLabels,
                            onAssignSinLote: _canAssignLote
                                ? (lote) async {
                                    Navigator.of(context).pop();
                                    final ok = await showAsignarLoteDialog(
                                      context: context,
                                      loteSinLote: lote,
                                      productName: item.nombreProducto,
                                      presentacionLabel:
                                          presentacionLabels[
                                              lote.idPresentacion],
                                    );
                                    if (!ok || !mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Lote asignado correctamente',
                                        ),
                                      ),
                                    );
                                    await _loadLotesForDetailedProducts();
                                  }
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                        _buildDetailSection(
                          'Información del Producto',
                          Icons.info_outline,
                          [
                            _buildDetailRow('Categoría', item.categoria),
                            _buildDetailRow('Subcategoría', item.subcategoria),
                            _buildDetailRow('Variante', item.variante),
                            _buildDetailRow(
                              'Opción Variante',
                              item.opcionVariante,
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
                        const SizedBox(height: 12),
                        _buildDetailSection(
                          'Ubicación',
                          Icons.location_on_outlined,
                          [
                            _buildDetailRow('Tienda', item.tienda),
                            _buildDetailRow('Almacén', item.almacen),
                            _buildDetailRow('Ubicación', item.ubicacion),
                          ],
                        ),
                        if (item.stockReservado > 0) ...[
                          const SizedBox(height: 12),
                          _buildDetailSection(
                            'Reservado / ajustado',
                            Icons.lock_outline,
                            [
                              _buildDetailRow(
                                'Stock Reservado',
                                item.cantidadEnPresentacion(
                                  item.stockReservado,
                                ),
                              ),
                              _buildDetailRow(
                                'Stock Ajustado',
                                item.cantidadEnPresentacion(
                                  item.stockDisponibleAjustado,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (narrow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Transferir'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Transferir'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Cerrar'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showInventorySummaryDetails(InventorySummaryByUser summary) {
    final lotes = _lotesByProduct[summary.idProducto] ?? const <LoteStockInfo>[];
    final narrow = MediaQuery.of(context).size.width < 420;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 12 : 24,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Padding(
          padding: EdgeInsets.all(narrow ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            Builder(
                              builder: (context) {
                                final stockStatus = _getStockStatus(
                                  summary.stock.equivalenteBase.toInt(),
                                );
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 240,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Existencia física',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                          Text(
                                            summary.stock.texto,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: stockStatus.color,
                                            ),
                                            softWrap: true,
                                          ),
                                          Text(
                                            'Equivalente: ${StockMixtoFormatter.cantidad(summary.stock.equivalenteBase)} '
                                            '${StockMixtoFormatter.plural(summary.stock.nombrePresentacionBase, summary.stock.equivalenteBase)} base',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: stockStatus.color,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        stockStatus.label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSummaryStockBreakdownSection(summary),
                      const SizedBox(height: 12),
                      if (lotes.isNotEmpty) ...[
                        LoteExpirySection(
                          title: 'Stock por lote y presentación',
                          lotes: lotes,
                          showUbicacion: true,
                          showPresentacion: true,
                          onAssignSinLote: _canAssignLote
                              ? (lote) async {
                                  Navigator.of(context).pop();
                                  final ok = await showAsignarLoteDialog(
                                    context: context,
                                    loteSinLote: lote,
                                    productName: summary.productoNombre,
                                  );
                                  if (!ok || !mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Lote asignado correctamente',
                                      ),
                                    ),
                                  );
                                  await _loadLotesForSummaries();
                                  await _loadLotesForDetailedProducts();
                                }
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
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
                            'Equivalente base',
                            StockMixtoFormatter.cantidad(
                              summary.stock.equivalenteBase,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (narrow)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {
                          _isDetailedView = true;
                          _searchQuery = summary.productoNombre;
                          _searchController.text = summary.productoNombre;
                        });
                        _loadInventoryData();
                      },
                      child: const Text('Ver Detalles'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Cerrar'),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _isDetailedView = true;
                            _searchQuery = summary.productoNombre;
                            _searchController.text = summary.productoNombre;
                          });
                          _loadInventoryData();
                        },
                        child: const Text('Ver Detalles'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Cerrar'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  /// Construye el FAB de acciones del tab Stock
  Widget _buildActionsFAB() {
    return FloatingActionButton.extended(
      onPressed: () => _showActionsMenu(),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.menu),
      label: const Text('Acciones'),
      tooltip: 'Acciones',
    );
  }

  void _showActionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.file_download_outlined,
                  color: AppColors.success,
                ),
                title: const Text('Exportar inventario'),
                onTap: () {
                  Navigator.pop(context);
                  showInventoryExportDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.list_alt, color: AppColors.info),
                title: const Text('Mostrar listado'),
                subtitle: const Text('Resumen de stock real por almacén'),
                onTap: () {
                  Navigator.pop(context);
                  _showWarehousePickerForStockList();
                },
              ),
              ListTile(
                leading: Icon(Icons.event_busy, color: Colors.amber.shade800),
                title: const Text('Caducidades'),
                subtitle: const Text('Por vencer y vencidos'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CaducidadesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showWarehousePickerForStockList() async {
    final selectableWarehouses =
        (widget.isAlmacenero && widget.assignedWarehouseId != null)
        ? _warehouses.where((w) {
            final id = int.tryParse(w['id'].toString());
            return id == widget.assignedWarehouseId;
          }).toList()
        : List<Map<String, dynamic>>.from(_warehouses);

    if (selectableWarehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay almacenes disponibles')),
      );
      return;
    }

    final selected = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Almacén'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: selectableWarehouses.length,
            itemBuilder: (context, index) {
              final w = selectableWarehouses[index];
              final id = int.tryParse(w['id'].toString());
              final name = w['denominacion']?.toString() ?? 'Sin nombre';
              final isSelected = id == _selectedWarehouseId;
              return ListTile(
                title: Text(name),
                subtitle: Text('ID: ${w['id']}'),
                trailing: isSelected
                    ? const Icon(Icons.check, color: AppColors.success)
                    : null,
                onTap: () => Navigator.pop(context, id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selected != null) {
      _showStockListDialog(selected);
    }
  }

  Future<void> _showStockListDialog(int warehouseId) async {
    final warehouseName =
        _warehouses
            .firstWhere(
              (w) => int.tryParse(w['id'].toString()) == warehouseId,
              orElse: () => {'denominacion': 'Almacén $warehouseId'},
            )['denominacion']
            ?.toString() ??
        'Almacén $warehouseId';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final summaries = await InventoryService.getInventorySummaryByUser(
        warehouseId,
        null,
        'Todos',
      );
      final breakdowns = await InventoryService.getStockBreakdownsByProduct(
        summaries,
        warehouseId: warehouseId,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      final items = summaries
          .map((s) {
            final b = breakdowns[s.idProducto];
            final realStock = b?.enAlmacen ?? s.cantidadTotalEnAlmacen;
            return (summary: s, breakdown: b, realStock: realStock);
          })
          .where((item) => item.realStock > 0)
          .toList();
      items.sort(
        (a, b) => a.summary.productoNombre.toLowerCase().compareTo(
          b.summary.productoNombre.toLowerCase(),
        ),
      );
      final totalStock = items.fold<double>(0, (s, i) => s + i.realStock);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.list_alt, color: AppColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Stock en $warehouseName',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: items.isEmpty
                ? const Text('No hay productos con stock en este almacén')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${items.length} productos · ${totalStock.toStringAsFixed(0)} unidades en almacén',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final s = items[index].summary;
                            final b = items[index].breakdown;
                            final realStock = items[index].realStock;
                            final color = realStock <= 0
                                ? AppColors.error
                                : realStock <= 10
                                ? AppColors.warning
                                : AppColors.success;
                            return ListTile(
                              dense: true,
                              title: Text(
                                s.productoNombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                b != null
                                    ? 'En almacén: ${realStock.toStringAsFixed(0)}  |  En pedidos: ${b.enPedidos.toStringAsFixed(0)}  |  Entregando: ${b.entregando.toStringAsFixed(0)}'
                                    : 'En almacén: ${realStock.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Text(
                                realStock.toStringAsFixed(0),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando listado: $e')));
    }
  }
}

/// Filas de inventario de un mismo producto/ubicación/variante
/// (una por presentación) para mostrar una sola card.
class _StockCardGroup {
  final List<InventoryProduct> rows;

  _StockCardGroup(List<InventoryProduct> rows)
      : rows = List<InventoryProduct>.unmodifiable(
          (List<InventoryProduct>.from(rows)
            ..sort((a, b) => b.cantidadFinal.compareTo(a.cantidadFinal))),
        );

  InventoryProduct get primary => rows.first;

  double get cantidadTotal =>
      rows.fold<double>(0, (s, r) => s + r.cantidadFinal);

  /// Incluye presentaciones en 0 cuando hay varias (p. ej. "0 Cajas + 5.750 Blísteres").
  String get stockMixtoTexto {
    if (rows.length <= 1) {
      return StockMixtoFormatter.mixto([
        for (final r in rows)
          {'nombre': r.presentacion, 'cantidad': r.cantidadFinal},
      ]);
    }
    return rows
        .map(
          (r) =>
              '${StockMixtoFormatter.cantidad(r.cantidadFinal)} '
              '${StockMixtoFormatter.plural(r.presentacion, r.cantidadFinal)}',
        )
        .join(' + ');
  }
}
