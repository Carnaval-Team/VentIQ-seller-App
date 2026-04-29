import 'package:flutter/material.dart';
import '../services/tpv_price_service.dart';
import '../models/tpv_price.dart';
import '../config/app_colors.dart';
import '../services/tpv_service.dart';
import '../widgets/tpv_managements/add_price_tpv_product.dart';
import '../utils/navigation_guard.dart';

class TpvPricesScreen extends StatefulWidget {
  final int? tpvId;
  final int? productId;

  const TpvPricesScreen({Key? key, this.tpvId, this.productId})
    : super(key: key);

  @override
  State<TpvPricesScreen> createState() => _TpvPricesScreenState();
}

class _TpvPricesScreenState extends State<TpvPricesScreen> {
  static const double _kMaxContentWidth = 1280;

  final TextEditingController _searchController = TextEditingController();

  List<TpvPrice> _prices = [];
  List<TpvPrice> _filteredPrices = [];
  List<Map<String, dynamic>> _tpvs = [];
  List<Map<String, dynamic>> _products = [];

  bool _isLoading = true;
  String _searchQuery = '';
  int? _selectedTpv;
  int? _selectedProduct;
  bool _showDeleted = false;

  bool _canCreatePrice = false;
  bool _canEditPrice = false;
  bool _canDeletePrice = false;
  bool _canRestorePrice = false;
  bool _canImportPrices = false;

  @override
  void initState() {
    super.initState();
    _selectedTpv = widget.tpvId;
    _selectedProduct = widget.productId;
    _loadPermissions();
    _loadData();
  }

  Future<void> _loadPermissions() async {
    final permissions = await Future.wait([
      NavigationGuard.canPerformAction('tpv_price.create'),
      NavigationGuard.canPerformAction('tpv_price.edit'),
      NavigationGuard.canPerformAction('tpv_price.delete'),
      NavigationGuard.canPerformAction('tpv_price.restore'),
      NavigationGuard.canPerformAction('tpv_price.import'),
    ]);

    if (!mounted) return;
    setState(() {
      _canCreatePrice = permissions[0];
      _canEditPrice = permissions[1];
      _canDeletePrice = permissions[2];
      _canRestorePrice = permissions[3];
      _canImportPrices = permissions[4];
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([_loadPrices(), _loadTpvs(), _loadProducts()]);
      _applyFilters();
    } catch (e) {
      print('Error cargando datos: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPrices() async {
    List<TpvPrice> prices = [];

    if (widget.tpvId != null) {
      prices = await TpvPriceService.getTpvPrices(
        widget.tpvId!,
        includeDeleted: _showDeleted,
        activeOnly: false,
      );
    } else if (widget.productId != null) {
      prices = await TpvPriceService.getProductPrices(
        widget.productId!,
        includeDeleted: _showDeleted,
      );
    } else {
      // Cargar todos los precios (limitado)
      final stats = await TpvPriceService.getPriceStatistics();
      // Por ahora lista vacía, implementar paginación después
      prices = [];
    }

    setState(() {
      _prices = prices;
    });
  }

  Future<void> _loadTpvs() async {
    final tpvs = await TpvPriceService.getAvailableTpvs(null);
    setState(() {
      _tpvs = tpvs;
    });
  }

  Future<void> _loadProducts() async {
    // Por ahora lista vacía, implementar después
    setState(() {
      _products = [];
    });
  }

  void _applyFilters() {
    List<TpvPrice> filtered = List.from(_prices);

    // Filtro por búsqueda
    if (_searchQuery.isNotEmpty) {
      filtered =
          filtered.where((price) {
            final productName = price.productoNombre?.toLowerCase() ?? '';
            final tpvName = price.tpvNombre?.toLowerCase() ?? '';
            final sku = price.productoSku?.toLowerCase() ?? '';
            final query = _searchQuery.toLowerCase();

            return productName.contains(query) ||
                tpvName.contains(query) ||
                sku.contains(query);
          }).toList();
    }

    // Filtro por TPV
    if (_selectedTpv != null) {
      filtered =
          filtered.where((price) => price.idTpv == _selectedTpv).toList();
    }

    // Filtro por producto
    if (_selectedProduct != null) {
      filtered =
          filtered
              .where((price) => price.idProducto == _selectedProduct)
              .toList();
    }

    setState(() {
      _filteredPrices = filtered;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _getScreenTitle(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _showDeleted ? Icons.visibility_off : Icons.visibility,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() => _showDeleted = !_showDeleted);
              _loadData();
            },
            tooltip: _showDeleted ? 'Ocultar eliminados' : 'Mostrar eliminados',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildFilters(),
                Container(height: 1, color: AppColors.border),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _kMaxContentWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                        child: Column(
                          children: [
                            _buildStats(),
                            const SizedBox(height: 12),
                            Expanded(child: _buildPricesList()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _canCreatePrice
          ? FloatingActionButton.extended(
              onPressed: _showAddPriceDialog,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Nuevo Precio',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            )
          : null,
    );
  }

  String _getScreenTitle() {
    if (widget.tpvId != null) {
      final tpv = _tpvs.firstWhere(
        (t) => t['id'] == widget.tpvId,
        orElse: () => {'denominacion': 'TPV'},
      );
      return 'Precios - ${tpv['denominacion']}';
    }
    if (widget.productId != null) {
      return 'Precios por TPV - Producto';
    }
    return 'Precios Diferenciados';
  }

  Widget _buildFilters() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 760;
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSearchField(),
                    const SizedBox(height: 10),
                    _buildTpvDropdown(),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildShowDeletedChip()),
                        if (_canImportPrices) ...[
                          const SizedBox(width: 10),
                          _buildImportButton(),
                        ],
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 3, child: _buildSearchField()),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: _buildTpvDropdown()),
                  const SizedBox(width: 12),
                  _buildShowDeletedChip(),
                  if (_canImportPrices) ...[
                    const SizedBox(width: 10),
                    _buildImportButton(),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final hasQuery = _searchQuery.isNotEmpty;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasQuery ? AppColors.primary : AppColors.border,
          width: hasQuery ? 1.5 : 1,
        ),
        boxShadow: hasQuery
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            Icons.search_rounded,
            size: 18,
            color: hasQuery ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'Buscar por producto, TPV o SKU...',
                hintStyle: TextStyle(
                  color: AppColors.textLight,
                  fontSize: 13,
                ),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _applyFilters();
              },
            ),
          ),
          if (hasQuery)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                  _applyFilters();
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _buildTpvDropdown() {
    final disabled = widget.tpvId != null;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: disabled ? AppColors.surfaceVariant : AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _selectedTpv != null
              ? AppColors.primary
              : AppColors.border,
          width: _selectedTpv != null ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.point_of_sale_outlined,
            size: 18,
            color: _selectedTpv != null
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedTpv,
                isExpanded: true,
                isDense: true,
                hint: const Text(
                  'Todos los TPVs',
                  style: TextStyle(fontSize: 13, color: AppColors.textLight),
                ),
                icon: const Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                borderRadius: BorderRadius.circular(10),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text(
                      'Todos los TPVs',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ..._tpvs.map(
                    (tpv) => DropdownMenuItem<int>(
                      value: tpv['id'],
                      child: Text(
                        tpv['denominacion'] ?? 'TPV',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
                onChanged: disabled
                    ? null
                    : (value) {
                        setState(() => _selectedTpv = value);
                        _applyFilters();
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowDeletedChip() {
    final active = _showDeleted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          setState(() => _showDeleted = !_showDeleted);
          _loadData();
        },
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active
                ? AppColors.error.withOpacity(0.08)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: active
                  ? AppColors.error.withOpacity(0.45)
                  : AppColors.border,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 16,
                color: active ? AppColors.error : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Eliminados',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? AppColors.error : AppColors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: _showImportDialog,
        icon: const Icon(Icons.upload_file_rounded, size: 16),
        label: const Text(
          'Importar',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    final totalPrices = _filteredPrices.length;
    final activePrices =
        _filteredPrices.where((p) => p.esActivo && !p.isDeleted).length;
    final deletedPrices = _filteredPrices.where((p) => p.isDeleted).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        if (isNarrow) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatItem(
                label: 'Total Precios',
                value: totalPrices.toString(),
                icon: Icons.attach_money_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(height: 10),
              _buildStatItem(
                label: 'Activos',
                value: activePrices.toString(),
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.success,
              ),
              const SizedBox(height: 10),
              _buildStatItem(
                label: 'Eliminados',
                value: deletedPrices.toString(),
                icon: Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildStatItem(
                  label: 'Total Precios',
                  value: totalPrices.toString(),
                  icon: Icons.attach_money_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  label: 'Activos',
                  value: activePrices.toString(),
                  icon: Icons.check_circle_outline_rounded,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  label: 'Eliminados',
                  value: deletedPrices.toString(),
                  icon: Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricesList() {
    if (_filteredPrices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.attach_money, size: 64, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No hay precios específicos',
              style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega precios diferenciados por TPV',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredPrices.length,
      itemBuilder: (context, index) {
        final price = _filteredPrices[index];
        return _buildPriceCard(price);
      },
    );
  }

  Widget _buildPriceCard(TpvPrice price) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        price.productoNombre ?? 'Producto sin nombre',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (price.productoSku != null)
                        Text(
                          'SKU: ${price.productoSku}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      Text(
                        '${price.tpvNombre} - ${price.tiendaNombre}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${price.precioVentaCup.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    _buildStatusChip(price),
                  ],
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => _handlePriceAction(value, price),
                  itemBuilder:
                      (context) => [
                        if (!price.isDeleted) ...[
                          if (_canEditPrice)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Editar'),
                            ),
                          if (_canEditPrice)
                            const PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicar'),
                            ),
                          if (_canDeletePrice)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Eliminar'),
                            ),
                        ] else ...[
                          if (_canRestorePrice)
                            const PopupMenuItem(
                              value: 'restore',
                              child: Text('Restaurar'),
                            ),
                        ],
                        const PopupMenuItem(
                          value: 'details',
                          child: Text('Ver Detalles'),
                        ),
                      ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip(
                  'Desde: ${_formatDate(price.fechaDesde)}',
                  Icons.calendar_today,
                ),
                const SizedBox(width: 8),
                if (price.fechaHasta != null)
                  _buildInfoChip(
                    'Hasta: ${_formatDate(price.fechaHasta!)}',
                    Icons.event,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(TpvPrice price) {
    Color color;
    if (price.isDeleted) {
      color = AppColors.error;
    } else if (!price.esActivo) {
      color = AppColors.warning;
    } else if (price.isCurrentlyActive) {
      color = AppColors.success;
    } else {
      color = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        price.statusText,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _handlePriceAction(String action, TpvPrice price) {
    switch (action) {
      case 'edit':
        if (!_canEditPrice) {
          NavigationGuard.showActionDeniedMessage(context, 'Editar precio');
          return;
        }
        _showEditPriceDialog(price);
        break;
      case 'duplicate':
        if (!_canEditPrice) {
          NavigationGuard.showActionDeniedMessage(context, 'Duplicar precio');
          return;
        }
        _showDuplicatePriceDialog(price);
        break;
      case 'delete':
        if (!_canDeletePrice) {
          NavigationGuard.showActionDeniedMessage(context, 'Eliminar precio');
          return;
        }
        _showDeleteConfirmation(price);
        break;
      case 'restore':
        if (!_canRestorePrice) {
          NavigationGuard.showActionDeniedMessage(context, 'Restaurar precio');
          return;
        }
        _restorePrice(price);
        break;
      case 'details':
        _showPriceDetails(price);
        break;
    }
  }

  void _showAddPriceDialog() {
    if (!_canCreatePrice) {
      NavigationGuard.showActionDeniedMessage(context, 'Crear precio');
      return;
    }
    showDialog(
      context: context,
      builder:
          (context) => AddPriceTpvProductDialog(
            tpvId: widget.tpvId,
            productId: widget.productId,
            onSuccess: _loadData,
          ),
    );
  }

  void _showEditPriceDialog(TpvPrice price) {
    if (!_canEditPrice) {
      NavigationGuard.showActionDeniedMessage(context, 'Editar precio');
      return;
    }
    showDialog(
      context: context,
      builder:
          (context) => AddPriceTpvProductDialog(
            tpvId: widget.tpvId,
            productId: widget.productId,
            existingPrice: price,
            onSuccess: _loadData,
          ),
    );
  }

  void _showDuplicatePriceDialog(TpvPrice price) {
    // Implementar duplicación
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Duplicar precio ID: ${price.id}')));
  }

  void _showDeleteConfirmation(TpvPrice price) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirmar Eliminación'),
            content: Text(
              '¿Eliminar el precio de ${price.productoNombre} para ${price.tpvNombre}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deletePrice(price);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
  }

  void _deletePrice(TpvPrice price) async {
    if (!_canDeletePrice) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Eliminar precio');
      }
      return;
    }
    final success = await TpvPriceService.deleteTpvPrice(price.id);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Precio eliminado exitosamente')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error al eliminar precio')));
    }
  }

  void _restorePrice(TpvPrice price) async {
    if (!_canRestorePrice) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Restaurar precio');
      }
      return;
    }
    final success = await TpvPriceService.restoreTpvPrice(price.id);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Precio restaurado exitosamente')),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al restaurar precio')),
      );
    }
  }

  void _showPriceDetails(TpvPrice price) {
    // Implementar detalles del precio
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Detalles del precio ID: ${price.id}')),
    );
  }

  void _showImportDialog() {
    if (!_canImportPrices) {
      NavigationGuard.showActionDeniedMessage(context, 'Importar precios');
      return;
    }
    // Implementar importación masiva
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Importación masiva - Por implementar')),
    );
  }
}
