import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/warehouse_service.dart';
import '../models/warehouse.dart';
import '../utils/navigation_guard.dart';

class WarehouseDetailScreen extends StatefulWidget {
  final String warehouseId;
  const WarehouseDetailScreen({super.key, required this.warehouseId});

  @override
  State<WarehouseDetailScreen> createState() => _WarehouseDetailScreenState();
}

class _WarehouseDetailScreenState extends State<WarehouseDetailScreen> {
  final _service = WarehouseService();
  Warehouse? _warehouse;
  bool _loading = true;
  int? _sort; // abc | type | utilization

  bool _canEditWarehouse = false;
  bool _canDeleteWarehouse = false;

  // Track expanded layouts and their products
  final Map<String, bool> _expandedLayouts = {};
  final Map<String, List<Map<String, dynamic>>> _layoutProducts = {};
  final Map<String, bool> _loadingProducts = {};

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _load();
  }

  Future<void> _loadPermissions() async {
    final permissions = await Future.wait([
      NavigationGuard.canPerformAction('warehouse.edit'),
      NavigationGuard.canPerformAction('warehouse.delete'),
    ]);

    if (!mounted) return;
    setState(() {
      _canEditWarehouse = permissions[0];
      _canDeleteWarehouse = permissions[1];
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final w = await _service.getWarehouseDetail(widget.warehouseId);
    setState(() {
      _warehouse = w;
      _loading = false;
    });
    // No cargar automáticamente todos los productos
    // Los productos se cargarán solo cuando el usuario expanda una zona específica
  }

  /// Carga solo la información básica del warehouse sin productos
  Future<void> _loadBasicInfo() async {
    setState(() => _loading = true);
    final w = await _service.getWarehouseDetail(widget.warehouseId);
    setState(() {
      _warehouse = w;
      _loading = false;
    });
    // Limpiar datos de productos para forzar recarga cuando se expandan
    _layoutProducts.clear();
    _loadingProducts.clear();
    _expandedLayouts.clear();
  }

  Future<void> _loadAllLayoutProducts() async {
    if (_warehouse == null) return;

    print('🔍 Loading products for ${_warehouse!.zones.length} zones');

    // Create a list of futures to wait for all product loading to complete
    List<Future<void>> loadingFutures = [];

    // Load products for all zones
    for (final zone in _warehouse!.zones) {
      print('🔍 Zone: ${zone.id} - ${zone.name}');
      if (_layoutProducts[zone.id] == null &&
          !(_loadingProducts[zone.id] ?? false)) {
        print('🔍 Loading products for zone: ${zone.id}');
        loadingFutures.add(_loadLayoutProducts(zone.id));
      } else {
        print('🔍 Zone ${zone.id} already has products or is loading');
      }
    }

    // Wait for all product loading to complete
    if (loadingFutures.isNotEmpty) {
      await Future.wait(loadingFutures);
      print('🔍 All product loading completed');
    }
  }

  Future<void> _loadLayoutProducts(String layoutId) async {
    print('🔍 _loadLayoutProducts called for layoutId: $layoutId');

    setState(() {
      _loadingProducts[layoutId] = true;
    });

    try {
      // Call warehouse service to get products for this layout/zone
      print('🔍 Calling getProductosByLayout for layoutId: $layoutId');
      final products = await _service.getProductosByLayout(layoutId);
      print('🔍 Received ${products.length} products for layout $layoutId');

      setState(() {
        _layoutProducts[layoutId] = products;
        _loadingProducts[layoutId] = false;
      });

      print(
        '🔍 Products stored in _layoutProducts[$layoutId]: ${_layoutProducts[layoutId]?.length}',
      );
    } catch (e) {
      print('❌ Error loading products for layout $layoutId: $e');
      setState(() {
        _loadingProducts[layoutId] = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando productos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Almacén'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.background,
      body:
          _loading || _warehouse == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(_warehouse!),
                      const SizedBox(height: 12),
                      _buildBasicInfo(_warehouse!),
                      const SizedBox(height: 12),
                      _buildLayouts(_warehouse!),
                      const SizedBox(height: 12),
                      _buildStockLimits(_warehouse!),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildHeader(Warehouse w) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.warehouse, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.denominacion ?? w.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        w.direccion ?? w.address,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _canEditWarehouse ? () => _onEditBasic(w) : null,
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            tooltip: 'Editar información básica',
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo(Warehouse w) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Información básica',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Nombre, dirección y tipo',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _modernKv('Nombre', w.denominacion ?? w.name, Icons.warehouse),
            _modernKv('Dirección', w.direccion ?? w.address, Icons.location_on),
            _modernKv('Ubicación', w.ubicacion ?? w.city, Icons.place),
            _modernKv('Tipo', w.type, Icons.category),
            if (w.tienda != null) ...[
              _modernKv('Tienda', w.tienda!.denominacion, Icons.store),
            ],
            const SizedBox(height: 16),
            // Botón para inicializar inventario
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    _canEditWarehouse
                        ? () => _showInitializeInventoryDialog(w)
                        : null,
                icon: const Icon(Icons.inventory_2),
                label: const Text('Inicializar Inventario Faltante'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayouts(Warehouse w) {
    // sort zones based on selected criteria
    final zones = [...w.zones];
    zones.sort((a, b) {
      switch (_sort) {
        case 1:
          return (a.type).compareTo(b.type);
        case 2:
          return (b.utilization).compareTo(a.utilization);
        case 3:
        default:
          int rank(String? v) {
            switch (v) {
              case 'A':
                return 0;
              case 'B':
                return 1;
              case 'C':
                return 2;
              default:
                return 3;
            }
          }
          final r = rank(a.abc) - rank(b.abc);
          return r != 0 ? r : (a.name).compareTo(b.name);
      }
    });

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.layers,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Layouts/Zonas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Define zonas, clasificación ABC y condiciones',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<int>(
                      tooltip: 'Ordenar',
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder:
                          (ctx) => const [
                            PopupMenuItem(
                              value: 3,
                              child: Text('Ordenar por ABC'),
                            ),
                            PopupMenuItem(
                              value: 1,
                              child: Text('Ordenar por tipo'),
                            ),
                            PopupMenuItem(
                              value: 2,
                              child: Text('Ordenar por utilización'),
                            ),
                          ],
                      child: const Icon(
                        Icons.sort,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _canEditWarehouse ? () => _onAddLayout(w) : null,
                      icon: const Icon(Icons.add, color: AppColors.primary),
                      tooltip: 'Agregar layout',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (w.zones.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Sin layouts aún',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              Column(children: _buildHierarchicalZones(w, zones)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildHierarchicalZones(Warehouse w, List<WarehouseZone> zones) {
    // Build hierarchy from flat list using parentId
    final Map<String, List<WarehouseZone>> childrenMap = {};
    final List<WarehouseZone> rootZones = [];

    // Initialize children map
    for (final zone in zones) {
      childrenMap[zone.id] = [];
    }

    // Organize zones by parent-child relationships
    for (final zone in zones) {
      if (zone.parentId == null || zone.parentId!.isEmpty) {
        // Root zone (no parent)
        rootZones.add(zone);
      } else {
        // Find parent by name or ID
        final parent = zones.firstWhere(
          (z) => z.id == zone.parentId || z.name == zone.parentId,
          orElse:
              () => zones.first, // Fallback to first zone if parent not found
        );
        childrenMap[parent.id]?.add(zone);
      }
    }

    // Build widgets recursively
    return _buildZoneWidgets(w, rootZones, childrenMap, 0);
  }

  List<Widget> _buildZoneWidgets(
    Warehouse w,
    List<WarehouseZone> zones,
    Map<String, List<WarehouseZone>> childrenMap,
    int level,
  ) {
    final widgets = <Widget>[];

    for (final zone in zones) {
      // Add the zone card with proper indentation
      widgets.add(_buildZoneCard(w, zone, level));

      // Add children recursively
      final children = childrenMap[zone.id] ?? [];
      if (children.isNotEmpty) {
        widgets.add(const SizedBox(height: 4));
        widgets.addAll(_buildZoneWidgets(w, children, childrenMap, level + 1));
        widgets.add(const SizedBox(height: 8));
      }
    }

    return widgets;
  }

  Widget _buildZoneCard(Warehouse w, WarehouseZone z, int level) {
    // Get real product count from loaded data
    final products = _layoutProducts[z.id] ?? [];
    final realProductCount = products.length;
    final isLoadingProducts = _loadingProducts[z.id] ?? false;

    print(
      '🔍 _buildZoneCard for zone ${z.id} (${z.name}) with ${realProductCount} products',
    );
    print('🔍 _layoutProducts keys: ${_layoutProducts.keys.toList()}');
    print('🔍 _loadingProducts[${z.id}]: ${_loadingProducts[z.id]}');

    return Container(
      margin: EdgeInsets.only(
        left: level * 20.0, // Indent based on hierarchy level
        bottom: 8,
      ),
      child: Card(
        elevation: level == 0 ? 2 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:
              level > 0
                  ? BorderSide(
                    color: AppColors.primary.withOpacity(0.3),
                    width: 1,
                  )
                  : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Hierarchy indicator
                  if (level > 0) ...[
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: AppColors.primary.withOpacity(0.7),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Zone icon based on level
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color:
                          level == 0
                              ? AppColors.primary.withOpacity(0.1)
                              : AppColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      level == 0 ? Icons.warehouse : Icons.inventory_2,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                z.name,
                                style: TextStyle(
                                  fontSize: level == 0 ? 16 : 14,
                                  fontWeight:
                                      level == 0
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (z.abc != null) _abcChip(z.abc!),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              z.code,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                z.type,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'edit':
                          _openLayoutForm(w, initial: z);
                          break;
                        case 'duplicate':
                          _openLayoutForm(w, initial: z, isDuplicate: true);
                          break;
                        case 'delete':
                          _onDeleteLayout(w, z.id);
                          break;
                      }
                    },
                    itemBuilder: (ctx) {
                      final items = <PopupMenuEntry<String>>[];
                      if (_canEditWarehouse) {
                        items.add(
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16),
                                SizedBox(width: 8),
                                Text('Editar'),
                              ],
                            ),
                          ),
                        );
                        items.add(
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 16),
                                SizedBox(width: 8),
                                Text('Duplicar'),
                              ],
                            ),
                          ),
                        );
                      }
                      if (_canDeleteWarehouse) {
                        items.add(
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 16, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Eliminar',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return items;
                    },
                    child:
                        _canEditWarehouse || _canDeleteWarehouse
                            ? const Icon(
                              Icons.more_vert,
                              color: AppColors.textSecondary,
                            )
                            : const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Metrics row
              Row(
                children: [
                  isLoadingProducts
                      ? _metricChip(Icons.hourglass_empty, 'Cargando...')
                      : _metricChip(
                        Icons.inventory,
                        '$realProductCount productos',
                      ),
                  const SizedBox(width: 8),
                  _metricChip(
                    Icons.pie_chart,
                    '${(z.utilization * 100).toInt()}% uso',
                  ),
                  const SizedBox(width: 8),
                  if (_conditionIcons(z).isNotEmpty) ...[
                    Row(children: _conditionIcons(z)),
                  ],
                ],
              ),
              // Expandable products section
              if (realProductCount > 0 || isLoadingProducts) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap:
                      isLoadingProducts
                          ? null
                          : () => _toggleLayoutExpansion(z.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isLoadingProducts
                              ? 'Cargando productos...'
                              : 'Ver productos ($realProductCount)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color:
                                isLoadingProducts
                                    ? AppColors.textSecondary
                                    : AppColors.primary,
                          ),
                        ),
                        isLoadingProducts
                            ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                              ),
                            )
                            : Icon(
                              _expandedLayouts[z.id] == true
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: AppColors.primary,
                            ),
                      ],
                    ),
                  ),
                ),
                if (_expandedLayouts[z.id] == true && !isLoadingProducts) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Productos en esta zona:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Usar Container con altura fija para evitar problemas de layout
                        Container(
                          constraints: BoxConstraints(
                            maxHeight:
                                products.length > 5
                                    ? 200
                                    : products.length * 40.0,
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics:
                                products.length > 5
                                    ? const AlwaysScrollableScrollPhysics()
                                    : const NeverScrollableScrollPhysics(),
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              final product = products[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        product['denominacion'] ??
                                            'Producto sin nombre',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Stock: ${product['stock_actual'] ?? 0}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProducts(WarehouseZone z) {
    if (_loadingProducts[z.id] ?? false) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_layoutProducts[z.id] == null) {
      _loadLayoutProducts(z.id);
      return const Center(child: CircularProgressIndicator());
    }

    final products = _layoutProducts[z.id] ?? [];

    if (products.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text(
            'No hay productos en este layout',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Productos (${products.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          ...products.map((product) => _buildProductItem(product)).toList(),
        ],
      ),
    );
  }

  Widget _buildProductItem(Map<String, dynamic> product) {
    final stockActual = product['stock_actual'] ?? 0;
    final stockMinimo = product['stock_minimo'] ?? 0;
    final stockMaximo = product['stock_maximo'] ?? 0;

    // Determine stock status color
    Color stockColor = Colors.green;
    String stockStatus = 'Normal';

    if (stockActual <= stockMinimo) {
      stockColor = Colors.red;
      stockStatus = 'Bajo';
    } else if (stockActual <= stockMinimo * 1.2) {
      stockColor = Colors.orange;
      stockStatus = 'Crítico';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['denominacion'] ?? 'Producto sin nombre',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'SKU: ${product['sku'] ?? 'N/A'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: stockColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: stockColor.withOpacity(0.3)),
                ),
                child: Text(
                  stockStatus,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: stockColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _productInfoChip(Icons.inventory, 'Stock: $stockActual'),
              const SizedBox(width: 8),
              _productInfoChip(
                Icons.location_on,
                product['ubicacion'] ?? 'Sin ubicación',
              ),
            ],
          ),
          if (product['lote'] != null ||
              product['fecha_vencimiento'] != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (product['lote'] != null) ...[
                  _productInfoChip(Icons.qr_code, 'Lote: ${product['lote']}'),
                  const SizedBox(width: 8),
                ],
                if (product['fecha_vencimiento'] != null)
                  _productInfoChip(
                    Icons.schedule,
                    'Vence: ${product['fecha_vencimiento']}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _productInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildStockLimits(Warehouse w) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Límites de stock',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Mínimos y máximos por producto',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      _canEditWarehouse ? () => _onEditStockLimits(w) : null,
                  icon: const Icon(Icons.tune, color: AppColors.primary),
                  tooltip: 'Gestionar límites',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Interfaz de gestión de límites por producto estará aquí (pendiente).',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modernKv(String key, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              key,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
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

  void _onEditBasic(Warehouse w) {
    if (!_canEditWarehouse) {
      NavigationGuard.showActionDeniedMessage(context, 'Editar almacén');
      return;
    }
    _showSnack('Editar información básica (pendiente)');
  }

  void _onAddLayout(Warehouse w) {
    if (!_canEditWarehouse) {
      NavigationGuard.showActionDeniedMessage(context, 'Editar almacén');
      return;
    }
    _openLayoutForm(w);
  }

  void _openLayoutForm(
    Warehouse w, {
    WarehouseZone? initial,
    bool isDuplicate = false,
  }) {
    if (!_canEditWarehouse) {
      NavigationGuard.showActionDeniedMessage(context, 'Editar almacén');
      return;
    }
    print(
      '🔧 Opening layout form - initial: ${initial?.name}, isDuplicate: $isDuplicate',
    );

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(
      text:
          initial != null
              ? (isDuplicate ? '${initial.name} (copia)' : initial.name)
              : '',
    );
    final codeCtrl = TextEditingController(text: initial?.code ?? '');
    final capacityCtrl = TextEditingController(
      text: initial?.capacity.toString() ?? '',
    );
    int? type = null; // Will be set from layoutTypes when loaded
    String? abc = initial?.abc ?? 'B';
    String? parentId = initial?.parentId;
    List<Map<String, dynamic>> layoutTypes = [];
    List<Map<String, dynamic>> condiciones = [];
    bool loadingTypes = true;
    bool loadingCondiciones = true;
    Set<int> selectedConditionIds = {
      ...(initial?.conditionCodes
              ?.map((code) => int.tryParse(code) ?? 0)
              .where((id) => id > 0) ??
          <int>[]),
    };

    // Debug initial values
    if (initial != null) {
      print('🔧 Initial zone data:');
      print('  - Name: ${initial.name}');
      print('  - Code: ${initial.code}');
      print('  - Type: ${initial.type}');
      print('  - ABC: ${initial.abc}');
      print('  - Capacity: ${initial.capacity}');
      print('  - ParentId: ${initial.parentId}');
      print('  - ConditionCodes: ${initial.conditionCodes}');
    }

    // Unique code validation context
    Set<String> takenCodes = {for (final z in w.zones) z.code};
    if (initial != null && !isDuplicate) {
      takenCodes.remove(initial.code);
    }
    if (isDuplicate && (initial?.code ?? '').isNotEmpty) {
      final base = initial!.code;
      var candidate = base;
      var i = 1;
      while (takenCodes.contains(candidate)) {
        candidate = '$base-$i';
        i++;
      }
      codeCtrl.text = candidate;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              // Load layout types when dialog opens
              if (loadingTypes) {
                _service
                    .getTiposLayout()
                    .then((types) {
                      setSheet(() {
                        layoutTypes.clear();
                        layoutTypes.addAll(types);
                        loadingTypes = false;

                        // Set type from initial zone data if editing
                        if (initial != null && type == null) {
                          print('🔧 Mapping initial type: ${initial.type}');
                          // Try to find matching type by denominacion
                          final matchingType = layoutTypes.firstWhere(
                            (t) =>
                                t['denominacion'].toString().toLowerCase() ==
                                initial.type.toLowerCase(),
                            orElse: () => <String, dynamic>{},
                          );
                          if (matchingType.isNotEmpty) {
                            type = matchingType['id'];
                            print(
                              '🔧 Found matching type ID: $type for ${initial.type}',
                            );
                          } else {
                            print(
                              '🔧 No matching type found for ${initial.type}, using first available',
                            );
                            type =
                                layoutTypes.isNotEmpty
                                    ? layoutTypes.first['id']
                                    : null;
                          }
                        } else if (layoutTypes.isNotEmpty && type == null) {
                          // Set default type if no initial data
                          type = layoutTypes.first['id'];
                          print('🔧 Set default type: $type');
                        }
                      });
                    })
                    .catchError((e) {
                      print('Error loading layout types: $e');
                      setSheet(() {
                        loadingTypes = false;
                        // Fallback to hardcoded types
                        layoutTypes.addAll([
                          {
                            'id': 1,
                            'denominacion': 'Recepción',
                            'sku_codigo': 'REC',
                          },
                          {
                            'id': 2,
                            'denominacion': 'Almacenamiento',
                            'sku_codigo': 'ALM',
                          },
                          {
                            'id': 3,
                            'denominacion': 'Picking',
                            'sku_codigo': 'PICK',
                          },
                          {
                            'id': 4,
                            'denominacion': 'Expedición',
                            'sku_codigo': 'EXP',
                          },
                        ]);
                        // Set type from initial zone data if editing
                        if (initial != null && type == null) {
                          print(
                            '🔧 Mapping initial type (fallback): ${initial.type}',
                          );
                          // Try to find matching type by denominacion
                          final matchingType = layoutTypes.firstWhere(
                            (t) =>
                                t['denominacion'].toString().toLowerCase() ==
                                initial.type.toLowerCase(),
                            orElse: () => <String, dynamic>{},
                          );
                          if (matchingType.isNotEmpty) {
                            type = matchingType['id'];
                            print(
                              '🔧 Found matching type ID (fallback): $type for ${initial.type}',
                            );
                          } else {
                            print(
                              '🔧 No matching type found (fallback) for ${initial.type}, using first available',
                            );
                            type =
                                layoutTypes.isNotEmpty
                                    ? layoutTypes.first['id']
                                    : null;
                          }
                        } else if (layoutTypes.isNotEmpty && type == null) {
                          // Set default type if no initial data
                          type = layoutTypes.first['id'];
                          print('🔧 Set default type (fallback): $type');
                        }
                      });
                    });
              }

              // Load conditions when dialog opens
              if (loadingCondiciones) {
                _service
                    .getCondiciones()
                    .then((conds) {
                      setSheet(() {
                        condiciones.clear();
                        condiciones.addAll(conds);
                        loadingCondiciones = false;
                      });
                    })
                    .catchError((e) {
                      print('Error loading conditions: $e');
                      setSheet(() {
                        loadingCondiciones = false;
                        // Fallback to hardcoded conditions
                        condiciones.addAll([
                          {
                            'id': 1,
                            'denominacion': 'Refrigerado',
                            'descripcion': 'Requiere refrigeración',
                          },
                          {
                            'id': 2,
                            'denominacion': 'Frágil',
                            'descripcion': 'Productos frágiles',
                          },
                          {
                            'id': 3,
                            'denominacion': 'Peligroso',
                            'descripcion': 'Materiales peligrosos',
                          },
                        ]);
                      });
                    });
              }

              return Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        initial == null
                            ? 'Nuevo layout'
                            : isDuplicate
                            ? 'Duplicar layout'
                            : 'Editar layout',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre',
                          border: OutlineInputBorder(),
                        ),
                        validator:
                            (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Requerido'
                                    : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Código',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Requerido';
                          final code = v.trim();
                          if (takenCodes.contains(code))
                            return 'Código ya existe';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      if (loadingTypes)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('Cargando tipos de layout...'),
                              ],
                            ),
                          ),
                        )
                      else
                        DropdownButtonFormField<int?>(
                          value: type,
                          items:
                              layoutTypes
                                  .map<DropdownMenuItem<int?>>(
                                    (t) => DropdownMenuItem<int?>(
                                      value: t['id'],
                                      child: Text(
                                        _truncateText(
                                          t['denominacion'] ?? '',
                                          50,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setSheet(() => type = v),
                          decoration: const InputDecoration(
                            labelText: 'Tipo de Layout',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(
                              Icons.category,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: capacityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Capacidad',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Requerido';
                          final n = int.tryParse(v);
                          if (n == null || n <= 0)
                            return 'Debe ser un entero > 0';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        value: abc,
                        items: const [
                          DropdownMenuItem(value: 'A', child: Text('ABC A')),
                          DropdownMenuItem(value: 'B', child: Text('ABC B')),
                          DropdownMenuItem(value: 'C', child: Text('ABC C')),
                        ],
                        onChanged: (v) => setSheet(() => abc = v),
                        decoration: const InputDecoration(
                          labelText: 'Clasificación ABC',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Condiciones especiales:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (loadingCondiciones)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text('Cargando condiciones...'),
                              ],
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              condiciones.map((condicion) {
                                final id = condicion['id'];
                                final isSelected = selectedConditionIds
                                    .contains(id);
                                return FilterChip(
                                  label: Text(
                                    _truncateText(
                                      condicion['denominacion'] ?? '',
                                      50,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setSheet(() {
                                      if (selected) {
                                        selectedConditionIds.add(id);
                                      } else {
                                        selectedConditionIds.remove(id);
                                      }
                                    });
                                  },
                                  selectedColor: AppColors.primary.withOpacity(
                                    0.2,
                                  ),
                                  checkmarkColor: AppColors.primary,
                                );
                              }).toList(),
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        value:
                            parentId != null &&
                                    w.zones.any(
                                      (z) =>
                                          z.id == parentId ||
                                          z.name == parentId,
                                    )
                                ? (w.zones
                                    .firstWhere(
                                      (z) =>
                                          z.id == parentId ||
                                          z.name == parentId,
                                      orElse: () => w.zones.first,
                                    )
                                    .id)
                                : null,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Sin padre'),
                          ),
                          ...w.zones
                              .where((z) => z.id != initial?.id)
                              .map(
                                (z) => DropdownMenuItem<String?>(
                                  value: z.id,
                                  child: Text(z.name),
                                ),
                              ),
                        ],
                        onChanged: (v) => setSheet(() => parentId = v),
                        decoration: const InputDecoration(
                          labelText: 'Layout padre (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                if (!(formKey.currentState?.validate() ??
                                    false))
                                  return;

                                print('🔄 Starting layout operation...');

                                // Show loading indicator
                                showDialog(
                                  context: ctx,
                                  barrierDismissible: false,
                                  builder:
                                      (context) => const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                );

                                if (initial == null || isDuplicate) {
                                  // Create or Duplicate -> create new layout
                                  print('🔄 Creating/duplicating layout...');
                                  final layoutData = {
                                    'name': nameCtrl.text.trim(),
                                    'code': codeCtrl.text.trim(),
                                    'typeId': type,
                                    'capacity': int.parse(
                                      capacityCtrl.text.trim(),
                                    ),
                                    'abc': abc,
                                    'conditionCodes':
                                        selectedConditionIds
                                            .map((id) => id.toString())
                                            .toList(),
                                    'parentId': parentId,
                                  };

                                  if (isDuplicate) {
                                    // For duplication, create new layout with modified data
                                    // Don't use duplicateLayout() as it ignores form changes
                                    await _service.addLayout(w.id, layoutData);
                                  } else {
                                    await _service.addLayout(w.id, layoutData);
                                  }

                                  print(
                                    '🔄 Layout operation completed, reloading data...',
                                  );
                                  // Reload warehouse data to get updated layouts (basic info only)
                                  await _loadBasicInfo();

                                  print('🔄 Data reloaded, closing dialogs...');
                                  if (mounted) {
                                    Navigator.of(ctx).pop(); // Close loading
                                  }
                                  if (mounted) {
                                    Navigator.of(
                                      context,
                                    ).pop(); // Close form using original context
                                  }
                                  print('🔄 Showing success message...');
                                  _showSnack(
                                    isDuplicate
                                        ? 'Layout duplicado exitosamente'
                                        : 'Layout creado exitosamente',
                                  );
                                } else {
                                  // Edit existing layout
                                  print('🔄 Updating layout...');
                                  final layoutData = {
                                    'name': nameCtrl.text.trim(),
                                    'code': codeCtrl.text.trim(),
                                    'typeId': type,
                                    'capacity': int.parse(
                                      capacityCtrl.text.trim(),
                                    ),
                                    'abc': abc,
                                    'conditionCodes':
                                        selectedConditionIds
                                            .map((id) => id.toString())
                                            .toList(),
                                    'parentId': parentId,
                                  };

                                  await _service.updateLayout(
                                    w.id,
                                    initial.id,
                                    layoutData,
                                  );

                                  print('🔄 Layout updated, reloading data...');
                                  // Reload warehouse data to get updated layouts (basic info only)
                                  await _loadBasicInfo();

                                  print('🔄 Data reloaded, closing dialogs...');
                                  if (mounted) {
                                    Navigator.of(ctx).pop(); // Close loading
                                  }
                                  if (mounted) {
                                    Navigator.of(
                                      context,
                                    ).pop(); // Close form using original context
                                  }
                                  print('🔄 Showing success message...');
                                  _showSnack('Layout actualizado exitosamente');
                                }
                              } catch (e) {
                                if (mounted) {
                                  Navigator.of(ctx).pop(); // Close loading
                                }
                                print('Error en operación de layout: $e');
                                _showSnack('Error: ${e.toString()}');
                              }
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _onEditLayout(Warehouse w, String layoutId) async {
    final z = w.zones.firstWhere(
      (e) => e.id == layoutId,
      orElse: () => w.zones.first,
    );
    _openLayoutForm(w, initial: z);
  }

  void _onDuplicateLayout(Warehouse warehouse, String layoutId) async {
    if (!_canEditWarehouse) {
      NavigationGuard.showActionDeniedMessage(context, 'Editar almacén');
      return;
    }
    try {
      // Get the original layout data
      final originalZone = warehouse.zones.firstWhere((z) => z.id == layoutId);

      // Generate new SKU code for duplicate
      final newSkuCode =
          '${originalZone.code}-COPY-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
      final newName = '${originalZone.name} (Copia)';

      _showSnack('Duplicando layout...', isLoading: true);

      final result = await _service.registerOrUpdateLayout(
        warehouseId: warehouse.id,
        layoutId: null, // null para crear nuevo
        tipoLayoutId:
            1, // Usar tipo por defecto o mapear desde originalZone.type
        denominacion: newName,
        skuCodigo: newSkuCode,
        layoutPadreId: null, // o usar originalZone.parentId si existe
      );

      if (result != null && result['success'] == true) {
        _showSnack(result['message'] ?? 'Layout duplicado correctamente');
        // Refresh warehouse data (basic info only)
        await _loadBasicInfo();
      } else {
        _showSnack(result?['message'] ?? 'Error al duplicar layout');
      }
    } catch (e) {
      _showSnack('Error al duplicar layout: $e');
    }
  }

  void _onDeleteLayout(Warehouse w, String layoutId) {
    if (!_canDeleteWarehouse) {
      NavigationGuard.showActionDeniedMessage(context, 'Eliminar layout');
      return;
    }
    _showDeleteLayoutDialog(w, layoutId);
  }

  /// Muestra diálogo de confirmación para eliminar zona
  Future<void> _showDeleteLayoutDialog(Warehouse w, String layoutId) async {
    // Obtener la zona a eliminar
    final zone = w.zones.firstWhere(
      (z) => z.id == layoutId,
      orElse:
          () => WarehouseZone(
            id: layoutId,
            warehouseId: w.id,
            name: 'Zona desconocida',
            code: '',
            type: '',
            conditions: '',
            capacity: 0,
            currentOccupancy: 0,
            locations: [],
          ),
    );

    // Obtener productos en la zona
    final products = _layoutProducts[layoutId] ?? [];

    // Calcular stock total en la zona
    int totalStock = 0;
    for (final product in products) {
      final stock = (product['stock_actual'] ?? 0) as int;
      totalStock += stock;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Eliminar Zona',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Información de la zona
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.layers,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    zone.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Código: ${zone.code}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Información de stock
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          totalStock > 0
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            totalStock > 0
                                ? Colors.red.shade200
                                : Colors.green.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              totalStock > 0
                                  ? Icons.warning
                                  : Icons.check_circle,
                              size: 16,
                              color: totalStock > 0 ? Colors.red : Colors.green,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              totalStock > 0
                                  ? 'Stock disponible detectado'
                                  : 'Sin stock disponible',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    totalStock > 0 ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Productos en zona: ${products.length}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Stock total: $totalStock unidades',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mensaje de validación
                  if (totalStock > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No se puede eliminar una zona con stock disponible. Transfiere o vende los productos primero.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'La zona puede ser eliminada. No contiene stock disponible.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              if (totalStock == 0)
                ElevatedButton.icon(
                  onPressed: () => _executeDeleteLayout(w, layoutId),
                  icon: const Icon(Icons.delete),
                  label: const Text('Eliminar Zona'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                )
              else
                ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                  ),
                  child: const Text('Eliminar Zona (Deshabilitado)'),
                ),
            ],
          ),
    );
  }

  /// Ejecuta la eliminación de la zona
  Future<void> _executeDeleteLayout(Warehouse w, String layoutId) async {
    Navigator.pop(context); // Cerrar diálogo
    _showSnack('Eliminando zona...', isLoading: true);

    try {
      await _service.deleteLayout(w.id, layoutId);

      if (!mounted) return;

      _showSnack('✅ Zona eliminada exitosamente');

      // Recargar datos del almacén
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack('❌ Error al eliminar zona: $e');
      print('❌ Error en _executeDeleteLayout: $e');
    }
  }

  void _onEditStockLimits(Warehouse w) {
    if (!_canEditWarehouse) {
      NavigationGuard.showActionDeniedMessage(context, 'Editar almacén');
      return;
    }
    _showSnack('Gestionar límites de stock (pendiente)');
  }

  void _showSnack(String msg, {bool isLoading = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            isLoading
                ? Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 16),
                    Text(msg),
                  ],
                )
                : Text(msg),
      ),
    );
  }

  /// Mostrar diálogo de inicialización de inventario
  Future<void> _showInitializeInventoryDialog(Warehouse w) async {
    if (!_canEditWarehouse) {
      NavigationGuard.showActionDeniedMessage(
        context,
        'Inicializar inventario',
      );
      return;
    }
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
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
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Inicializar Inventario',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Esta acción buscará todos los productos de la tienda "${w.tienda?.denominacion ?? 'N/A'}" que no tienen registros de inventario en la primera ubicación del almacén "${w.denominacion ?? w.name}".',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Lo que hará esta función:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• Buscar productos sin operaciones de inventario\n'
                        '• Crear operación inicial con cantidad 0\n'
                        '• Establecer origen de cambio como "Inventario Inicial"\n'
                        '• Mostrar detalle de productos procesados',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_outlined,
                        size: 16,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Esta acción no se puede deshacer. Solo afectará productos que no tengan registros previos.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _executeInitializeInventory(w);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Inicializar'),
              ),
            ],
          ),
    );
  }

  /// Ejecutar la inicialización de inventario
  Future<void> _executeInitializeInventory(Warehouse w) async {
    // Mostrar diálogo de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Inicializando inventario...'),
                SizedBox(height: 8),
                Text(
                  'Por favor espere mientras se procesan los productos',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
    );

    try {
      final result = await _service.initializeInventoryMissingProducts(
        warehouseId: w.id,
      );

      // Cerrar diálogo de progreso
      Navigator.of(context).pop();

      // Mostrar resultado
      _showInitializationResult(result);

      // Recargar solo información básica sin productos
      await _loadBasicInfo();
    } catch (e) {
      // Cerrar diálogo de progreso
      Navigator.of(context).pop();

      // Mostrar error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al inicializar inventario: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Mostrar resultado de la inicialización
  void _showInitializationResult(Map<String, dynamic> result) {
    final success = result['success'] ?? false;
    final productosProcessados = result['productos_procesados'] ?? 0;
    final productosInsertados = result['productos_insertados'] ?? 0;
    final detalles = result['detalles'] ?? [];
    final message = result['message'] ?? '';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        success
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    success ? Icons.check_circle : Icons.error,
                    color: success ? Colors.green : Colors.red,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    success
                        ? 'Inicialización Completada'
                        : 'Error en Inicialización',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resumen
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          success ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            success
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color:
                                success
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (success) ...[
                          Text('• Productos evaluados: $productosProcessados'),
                          Text(
                            '• Productos inicializados: $productosInsertados',
                          ),
                          Text(
                            '• Productos ya existentes: ${productosProcessados - productosInsertados}',
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(message, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  void _toggleLayoutExpansion(String layoutId) {
    setState(() {
      _expandedLayouts[layoutId] = !(_expandedLayouts[layoutId] ?? false);
    });

    // Load products when expanding for the first time
    if (_expandedLayouts[layoutId] == true &&
        _layoutProducts[layoutId] == null) {
      _loadLayoutProducts(layoutId);
    }
  }

  List<Widget> _conditionIcons(WarehouseZone z) {
    if (z.conditions.isEmpty) return [];

    // Split conditions by comma if multiple, otherwise use single condition
    final codes =
        z.conditions.contains(',')
            ? z.conditions.split(',').map((e) => e.trim()).toList()
            : [z.conditions];

    Widget iconFor(String code) {
      switch (code.toLowerCase()) {
        case 'refrigerado':
          return const Icon(Icons.ac_unit, size: 14, color: Colors.blue);
        case 'fragil':
          return const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: Colors.orange,
          );
        case 'peligroso':
          return const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: Colors.red,
          );
        default:
          return const Icon(
            Icons.label_important_outline,
            size: 14,
            color: Colors.grey,
          );
      }
    }

    final limitedCodes = codes.length > 4 ? codes.sublist(0, 4) : codes;
    return limitedCodes
        .map(
          (c) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: iconFor(c),
          ),
        )
        .toList();
  }
}

String _truncateText(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

Widget _abcChip(String abc) {
  Color color;
  switch (abc) {
    case 'A':
      color = Colors.red;
      break;
    case 'B':
      color = Colors.orange;
      break;
    case 'C':
      color = Colors.green;
      break;
    default:
      color = Colors.grey;
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      abc,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
}

Widget _metricChip(IconData icon, String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    ),
  );
}

class _EditLayoutDialog extends StatefulWidget {
  final String currentName;
  final String currentCode;

  const _EditLayoutDialog({
    Key? key,
    required this.currentName,
    required this.currentCode,
  }) : super(key: key);

  @override
  State<_EditLayoutDialog> createState() => _EditLayoutDialogState();
}

class _EditLayoutDialogState extends State<_EditLayoutDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.currentName;
    _codeCtrl.text = widget.currentCode;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Editar layout',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código',
                  border: OutlineInputBorder(),
                ),
                validator:
                    (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      if (!(_formKey.currentState?.validate() ?? false)) return;

                      final result = {
                        'name': _nameCtrl.text.trim(),
                        'code': _codeCtrl.text.trim(),
                      };
                      Navigator.of(context).pop(result);
                    },
                    child: const Text('Guardar'),
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
