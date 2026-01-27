import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/price_change.dart';
import '../../services/price_change_service.dart';
import '../../services/store_selector_service.dart';
import '../../services/tpv_service.dart';
import '../../services/vendedor_service.dart';

/// Historial de cambios de precio
class PriceAlterationsTabView extends StatefulWidget {
  final String searchQuery;
  final VoidCallback onRefresh;

  const PriceAlterationsTabView({
    Key? key,
    required this.searchQuery,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<PriceAlterationsTabView> createState() =>
      _PriceAlterationsTabViewState();
}

class _PriceAlterationsTabViewState extends State<PriceAlterationsTabView> {
  final StoreSelectorService _storeService = StoreSelectorService();
  final ScrollController _scrollController = ScrollController();
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'es_CU',
    symbol: r'$ ',
  );
  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy HH:mm');

  Timer? _debounceTimer;
  List<PriceChange> _changes = [];
  List<Map<String, dynamic>> _tpvs = [];
  List<Map<String, dynamic>> _vendedores = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  int _currentPage = 1;
  int _totalCount = 0;
  final int _itemsPerPage = 20;

  String _searchQuery = '';
  int? _selectedTpvId;
  String? _selectedUserUuid;
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  int? _currentStoreId;

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.searchQuery;
    _storeService.addListener(_onStoreChanged);
    _scrollController.addListener(_onScroll);
    _loadInitialData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _storeService.removeListener(_onStoreChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PriceAlterationsTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _searchQuery = widget.searchQuery;
      _debounceSearch();
    }
  }

  void _onStoreChanged() async {
    if (_storeService.isLoading || !_storeService.isInitialized) return;
    final storeId = _storeService.getSelectedStoreId();
    if (storeId == null || storeId == _currentStoreId) return;
    _currentStoreId = storeId;
    _resetFilters();
    await _loadFilters(storeId);
    await _loadChanges(reset: true, storeId: storeId);
  }

  Future<void> _loadInitialData() async {
    final storeId = await _getStoreId();
    if (storeId == null) {
      setState(() => _isLoading = false);
      return;
    }
    _currentStoreId = storeId;
    await _loadFilters(storeId);
    await _loadChanges(reset: true, storeId: storeId);
  }

  Future<int?> _getStoreId() async {
    if (!_storeService.isInitialized) {
      await _storeService.initialize();
    }

    await _storeService.syncSelectedStore(notify: false);

    final selectedStoreId = _storeService.getSelectedStoreId();
    if (selectedStoreId != null) return selectedStoreId;

    if (_storeService.userStores.isNotEmpty) {
      return _storeService.userStores.first.id;
    }

    return null;
  }

  Future<void> _loadFilters(int storeId) async {
    final results = await Future.wait([
      TpvService.getTpvsByStoreId(storeId),
      VendedorService.getVendedoresByStoreId(storeId),
    ]);

    if (!mounted) return;
    setState(() {
      _tpvs = results[0];
      _vendedores = results[1];
    });
  }

  Future<void> _loadChanges({required bool reset, int? storeId}) async {
    try {
      if (reset) {
        setState(() => _isLoading = true);
        _currentPage = 1;
      }

      final resolvedStoreId = storeId ?? _currentStoreId;
      if (resolvedStoreId == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        return;
      }

      final response = await PriceChangeService.listPriceChanges(
        storeId: resolvedStoreId,
        busqueda: _searchQuery.isEmpty ? null : _searchQuery,
        idTpv: _selectedTpvId,
        idUsuario: _selectedUserUuid,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
        limite: _itemsPerPage,
        pagina: _currentPage,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _changes = response.changes;
        } else {
          _changes.addAll(response.changes);
        }
        _totalCount = response.totalCount;
        _hasNextPage = _changes.length < _totalCount;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar cambios: $e')));
    }
  }

  void _debounceSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      _loadChanges(reset: true);
    });
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasNextPage) return;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() => _isLoadingMore = true);
    _currentPage += 1;
    await _loadChanges(reset: false);
  }

  Future<void> _refreshChanges() async {
    widget.onRefresh();
    _currentPage = 1;
    await _loadChanges(reset: true);
  }

  Future<void> _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _fechaDesde = picked.start;
        _fechaHasta = picked.end;
      });
      await _loadChanges(reset: true);
    }
  }

  void _resetFilters() {
    setState(() {
      _selectedTpvId = null;
      _selectedUserUuid = null;
      _fechaDesde = null;
      _fechaHasta = null;
    });
  }

  void _clearFilters() {
    _resetFilters();
    _loadChanges(reset: true);
  }

  bool get _hasActiveFilters {
    return _selectedTpvId != null ||
        _selectedUserUuid != null ||
        _fechaDesde != null ||
        _fechaHasta != null;
  }

  String _formatShortDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _getVendorLabel(Map<String, dynamic> vendedor) {
    final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
    if (trabajador == null) {
      return vendedor['uuid']?.toString() ?? 'Sin nombre';
    }

    final nombres = trabajador['nombres']?.toString() ?? '';
    final apellidos = trabajador['apellidos']?.toString() ?? '';
    final nombre = '$nombres $apellidos'.trim();
    return nombre.isEmpty ? 'Sin nombre' : nombre;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshChanges,
            color: AppColors.primary,
            backgroundColor: Colors.white,
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildChangesContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildTpvFilter()),
              const SizedBox(width: 8),
              Expanded(child: _buildVendorFilter()),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDateFilterButton(),
              if (_hasActiveFilters) _buildClearFiltersButton(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _totalCount == 0
                ? 'Sin cambios registrados'
                : 'Mostrando ${_changes.length} de $_totalCount cambios',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTpvFilter() {
    return DropdownButtonFormField<int?>(
      value: _selectedTpvId,
      isExpanded: true,
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'TPV',
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Todos los TPVs'),
        ),
        ..._tpvs.map(
          (tpv) => DropdownMenuItem<int?>(
            value: tpv['id'] as int?,
            child: Text(
              tpv['denominacion']?.toString() ?? 'Sin nombre',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() => _selectedTpvId = value);
        _loadChanges(reset: true);
      },
    );
  }

  Widget _buildVendorFilter() {
    return DropdownButtonFormField<String?>(
      value: _selectedUserUuid,
      isExpanded: true,
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Vendedor',
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Todos los vendedores'),
        ),
        ..._vendedores.map(
          (vendedor) => DropdownMenuItem<String?>(
            value: vendedor['uuid']?.toString(),
            child: Text(
              _getVendorLabel(vendedor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() => _selectedUserUuid = value);
        _loadChanges(reset: true);
      },
    );
  }

  Widget _buildDateFilterButton() {
    final hasRange = _fechaDesde != null && _fechaHasta != null;
    final label =
        hasRange
            ? '${_formatShortDate(_fechaDesde!)} - ${_formatShortDate(_fechaHasta!)}'
            : 'Rango de fechas';

    return OutlinedButton.icon(
      onPressed: _showDateRangePicker,
      icon: Icon(
        Icons.date_range,
        color: hasRange ? AppColors.primary : AppColors.textSecondary,
        size: 18,
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: hasRange ? AppColors.primary : AppColors.textSecondary,
        side: BorderSide(
          color: hasRange ? AppColors.primary : AppColors.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildClearFiltersButton() {
    return OutlinedButton.icon(
      onPressed: _clearFilters,
      icon: const Icon(Icons.clear, color: Colors.red, size: 18),
      label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: BorderSide(color: Colors.red.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildChangesContent() {
    if (_changes.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 48),
          Icon(Icons.price_change, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No se encontraron cambios de precio',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Intenta ajustar los filtros o recargar la lista',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      );
    }

    final totalItems = _changes.length + (_isLoadingMore ? 1 : 0) + 1;

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildResultsHeader();
        }

        final itemIndex = index - 1;
        if (itemIndex == _changes.length) {
          return _buildLoadingMoreIndicator();
        }

        return _buildChangeCard(_changes[itemIndex]);
      },
    );
  }

  Widget _buildResultsHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Cambios recientes',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildChangeCard(PriceChange change) {
    final isDiscount = change.esDescuento;
    final isIncrease = change.esAumento;
    final accentColor =
        isDiscount
            ? AppColors.success
            : (isIncrease ? AppColors.warning : AppColors.secondary);
    final accentBg = accentColor.withOpacity(0.12);
    final diffPrefix = isDiscount ? '-' : (isIncrease ? '+' : '');
    final diffValue =
        '${diffPrefix}${_currencyFormatter.format(change.diferenciaAbsoluta)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isDiscount
                        ? Icons.trending_down
                        : isIncrease
                        ? Icons.trending_up
                        : Icons.price_change,
                    color: accentColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        change.nombreProductoCompleto,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (change.skuProducto != null &&
                          change.skuProducto!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'SKU: ${change.skuProducto}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _buildInfoChip(Icons.point_of_sale, change.nombreTpv),
                          _buildInfoChip(
                            Icons.person,
                            change.nombreUsuarioDisplay,
                          ),
                          _buildInfoChip(
                            Icons.schedule,
                            _dateFormatter.format(change.fechaCambio),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _currencyFormatter.format(change.precioNuevo),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Antes ${_currencyFormatter.format(change.precioAnterior)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        diffValue,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (change.motivo != null && change.motivo!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      change.motivo!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primary.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}
