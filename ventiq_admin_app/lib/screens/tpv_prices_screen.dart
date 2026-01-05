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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getScreenTitle()),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showDeleted ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() => _showDeleted = !_showDeleted);
              _loadData();
            },
            tooltip: _showDeleted ? 'Ocultar eliminados' : 'Mostrar eliminados',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  _buildFilters(),
                  _buildStats(),
                  Expanded(child: _buildPricesList()),
                ],
              ),
      floatingActionButton:
          _canCreatePrice
              ? FloatingActionButton(
                onPressed: _showAddPriceDialog,
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add, color: Colors.white),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por producto, TPV o SKU...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: DropdownButtonFormField<int>(
                  decoration: InputDecoration(
                    labelText: 'TPV',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  value: _selectedTpv,
                  isExpanded: true, // Importante para evitar overflow
                  items: [
                    const DropdownMenuItem<int>(
                      value: null,
                      child: Text(
                        'Todos los TPVs',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ..._tpvs
                        .map(
                          (tpv) => DropdownMenuItem<int>(
                            value: tpv['id'],
                            child: Text(
                              tpv['denominacion'] ?? 'TPV',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        )
                        .toList(),
                  ],
                  onChanged:
                      widget.tpvId == null
                          ? (value) {
                            setState(() => _selectedTpv = value);
                            _applyFilters();
                          }
                          : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Mostrar eliminados'),
                  value: _showDeleted,
                  onChanged: (value) {
                    setState(() => _showDeleted = value ?? false);
                    _loadData();
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ),
              if (_canImportPrices)
                ElevatedButton.icon(
                  onPressed: _showImportDialog,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Importar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final totalPrices = _filteredPrices.length;
    final activePrices =
        _filteredPrices.where((p) => p.esActivo && !p.isDeleted).length;
    final deletedPrices = _filteredPrices.where((p) => p.isDeleted).length;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total',
              totalPrices.toString(),
              Icons.list,
              AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Activos',
              activePrices.toString(),
              Icons.check_circle,
              AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Eliminados',
              deletedPrices.toString(),
              Icons.delete,
              AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
