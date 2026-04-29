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
    final DateTimeRange? picked = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => _DateRangePickerDialog(
        initialStart: _fechaDesde,
        initialEnd: _fechaHasta,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      ),
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      margin: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 720;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                _buildTpvFilter(),
                const SizedBox(height: 10),
                _buildVendorFilter(),
              ] else
                Row(
                  children: [
                    Expanded(child: _buildTpvFilter()),
                    const SizedBox(width: 10),
                    Expanded(child: _buildVendorFilter()),
                    const SizedBox(width: 10),
                    _buildDateFilterButton(),
                    if (_hasActiveFilters) ...[
                      const SizedBox(width: 8),
                      _buildClearFiltersButton(),
                    ],
                  ],
                ),
              if (isNarrow) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildDateFilterButton(),
                    if (_hasActiveFilters) _buildClearFiltersButton(),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Container(height: 1, color: AppColors.border.withOpacity(0.6)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _totalCount == 0
                          ? 'Sin cambios registrados'
                          : 'Mostrando ${_changes.length} de $_totalCount cambios',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (_hasActiveFilters)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Filtros activos',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPillDropdown<T>({
    required IconData icon,
    required String hint,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    final hasValue = value != null;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasValue ? AppColors.primary : AppColors.border,
          width: hasValue ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: hasValue ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                hint: Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                icon: const Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
                borderRadius: BorderRadius.circular(10),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTpvFilter() {
    return _buildPillDropdown<int?>(
      icon: Icons.point_of_sale_outlined,
      hint: 'Todos los TPVs',
      value: _selectedTpvId,
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
    return _buildPillDropdown<String?>(
      icon: Icons.person_outline_rounded,
      hint: 'Todos los vendedores',
      value: _selectedUserUuid,
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
    final label = hasRange
        ? '${_formatShortDate(_fechaDesde!)} → ${_formatShortDate(_fechaHasta!)}'
        : 'Rango de fechas';
    final accent = hasRange ? AppColors.primary : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showDateRangePicker,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: hasRange
                ? AppColors.primary.withOpacity(0.06)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: hasRange ? AppColors.primary : AppColors.border,
              width: hasRange ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.date_range_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasRange ? FontWeight.w700 : FontWeight.w600,
                  color: accent,
                  letterSpacing: 0.2,
                ),
              ),
              if (hasRange) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.expand_more_rounded,
                  size: 16,
                  color: accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClearFiltersButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _clearFilters,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.error.withOpacity(0.45),
              width: 1.5,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.close_rounded, size: 16, color: AppColors.error),
              SizedBox(width: 6),
              Text(
                'Limpiar',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Cambios recientes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          if (_totalCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_totalCount total',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChangeCard(PriceChange change) {
    final isDiscount = change.esDescuento;
    final isIncrease = change.esAumento;
    final accentColor = isDiscount
        ? AppColors.success
        : (isIncrease ? AppColors.warning : AppColors.secondary);
    final diffPrefix = isDiscount ? '-' : (isIncrease ? '+' : '');
    final diffValue =
        '$diffPrefix${_currencyFormatter.format(change.diferenciaAbsoluta)}';
    final iconData = isDiscount
        ? Icons.trending_down_rounded
        : (isIncrease ? Icons.trending_up_rounded : Icons.price_change_rounded);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        Icon(iconData, color: accentColor, size: 20),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            change.nombreProductoCompleto,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              height: 1.2,
                            ),
                          ),
                          if (change.skuProducto != null &&
                              change.skuProducto!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                'SKU · ${change.skuProducto}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _currencyFormatter.format(change.precioNuevo),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currencyFormatter.format(change.precioAnterior),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textLight,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: AppColors.textLight,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: accentColor.withOpacity(0.25),
                                ),
                              ),
                              child: Text(
                                diffValue,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: accentColor,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: AppColors.border.withOpacity(0.6)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildInfoChip(
                      Icons.point_of_sale_outlined,
                      change.nombreTpv,
                      AppColors.primary,
                    ),
                    _buildInfoChip(
                      Icons.person_outline_rounded,
                      change.nombreUsuarioDisplay,
                      AppColors.info,
                    ),
                    _buildInfoChip(
                      Icons.schedule_rounded,
                      _dateFormatter.format(change.fechaCambio),
                      AppColors.textSecondary,
                    ),
                  ],
                ),
                if (change.motivo != null &&
                    change.motivo!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.border.withOpacity(0.6),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            change.motivo!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              height: 1.3,
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
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.1,
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

class _DateRangePickerDialog extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final DateTime firstDate;
  final DateTime lastDate;

  const _DateRangePickerDialog({
    this.initialStart,
    this.initialEnd,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
  static const List<String> _monthNames = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];
  static const List<String> _weekdayLabels = [
    'L', 'M', 'X', 'J', 'V', 'S', 'D',
  ];

  late DateTime _displayMonth;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    final base = _start ?? DateTime.now();
    _displayMonth = DateTime(base.year, base.month);
  }

  bool _isInRange(DateTime day) {
    if (_start == null || _end == null) return false;
    return !day.isBefore(_start!) && !day.isAfter(_end!);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _onDayTap(DateTime day) {
    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _start = day;
      } else {
        _end = day;
      }
    });
  }

  void _previousMonth() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1);
    });
  }

  void _applyPreset(int days) {
    final now = DateTime.now();
    setState(() {
      _start = DateTime(now.year, now.month, now.day - days);
      _end = DateTime(now.year, now.month, now.day);
      _displayMonth = DateTime(_start!.year, _start!.month);
    });
  }

  String _formatDayLabel(DateTime? d) {
    if (d == null) return '—';
    final m = _monthNames[d.month - 1];
    return '${d.day} $m ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppColors.surface,
      elevation: 8,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Container(height: 1, color: AppColors.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPresets(),
                    const SizedBox(height: 14),
                    _buildMonthNavigator(),
                    const SizedBox(height: 8),
                    _buildWeekdayHeader(),
                    const SizedBox(height: 4),
                    _buildCalendarGrid(),
                    const SizedBox(height: 14),
                    _buildSelectionSummary(),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: AppColors.border),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.date_range_rounded,
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
                  'Rango de fechas',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Selecciona inicio y fin del periodo',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.close_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresets() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildPresetChip('Hoy', () => _applyPreset(0)),
        _buildPresetChip('7 días', () => _applyPreset(7)),
        _buildPresetChip('30 días', () => _applyPreset(30)),
        _buildPresetChip('90 días', () => _applyPreset(90)),
      ],
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.20)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthNavigator() {
    final monthLabel =
        '${_monthNames[_displayMonth.month - 1]} ${_displayMonth.year}';
    return Row(
      children: [
        _buildNavButton(Icons.chevron_left_rounded, _previousMonth),
        Expanded(
          child: Center(
            child: Text(
              monthLabel,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
        _buildNavButton(Icons.chevron_right_rounded, _nextMonth),
      ],
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    return Row(
      children: _weekdayLabels
          .map(
            (d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildCalendarGrid() {
    final firstOfMonth =
        DateTime(_displayMonth.year, _displayMonth.month, 1);
    final daysInMonth =
        DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    // weekday: 1=Mon..7=Sun. We want Monday-first columns.
    final leadingBlank = (firstOfMonth.weekday - 1) % 7;
    final totalCells = leadingBlank + daysInMonth;
    final rows = ((totalCells + 6) ~/ 7);

    return Column(
      children: List.generate(rows, (rowIndex) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: List.generate(7, (colIndex) {
              final cellIndex = rowIndex * 7 + colIndex;
              final dayNumber = cellIndex - leadingBlank + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const Expanded(child: SizedBox(height: 36));
              }
              final day = DateTime(
                _displayMonth.year,
                _displayMonth.month,
                dayNumber,
              );
              return Expanded(child: _buildDayCell(day));
            }),
          ),
        );
      }),
    );
  }

  Widget _buildDayCell(DateTime day) {
    final outOfRange =
        day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate);
    final isStart = _start != null && _isSameDay(day, _start!);
    final isEnd = _end != null && _isSameDay(day, _end!);
    final inRange = _isInRange(day) && !isStart && !isEnd;
    final isToday = _isSameDay(day, DateTime.now());

    BoxDecoration? bgDecoration;
    Color textColor = AppColors.textPrimary;
    FontWeight weight = FontWeight.w500;

    if (isStart || isEnd) {
      bgDecoration = BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
      );
      textColor = Colors.white;
      weight = FontWeight.w700;
    } else if (inRange) {
      bgDecoration = BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      );
      textColor = AppColors.primary;
      weight = FontWeight.w600;
    } else if (isToday) {
      bgDecoration = BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.5)),
      );
      textColor = AppColors.primary;
      weight = FontWeight.w700;
    }

    if (outOfRange) {
      textColor = AppColors.textLight;
      weight = FontWeight.w400;
    }

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: outOfRange ? null : () => _onDayTap(day),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: bgDecoration,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: weight,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryColumn('Inicio', _formatDayLabel(_start)),
          ),
          Container(
            width: 1,
            height: 28,
            color: AppColors.border,
          ),
          Expanded(
            child: _buildSummaryColumn('Fin', _formatDayLabel(_end)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final canApply = _start != null && _end != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () {
              setState(() {
                _start = null;
                _end = null;
              });
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Limpiar',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: canApply
                ? () => Navigator.pop(
                      context,
                      DateTimeRange(start: _start!, end: _end!),
                    )
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.border,
              disabledForegroundColor: AppColors.textLight,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Aplicar',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
