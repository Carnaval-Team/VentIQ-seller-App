import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_colors.dart';
import '../../models/caja_turno.dart';
import '../../services/caja_turno_pdf_service.dart';
import '../../services/caja_turno_service.dart';
import '../../services/store_selector_service.dart';
import '../../services/tpv_service.dart';
import '../../services/vendedor_service.dart';

/// Turnos de caja por TPV: apertura/cierre, conciliacion de efectivo y
/// reporte de faltantes/excesos de inventario, listo para auditar e imprimir.
class CajaTurnosTabView extends StatefulWidget {
  final String searchQuery;
  final VoidCallback onRefresh;

  const CajaTurnosTabView({
    Key? key,
    required this.searchQuery,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<CajaTurnosTabView> createState() => _CajaTurnosTabViewState();
}

class _CajaTurnosTabViewState extends State<CajaTurnosTabView> {
  /// Lineas de discrepancia visibles en la tarjeta antes de "ver todas".
  static const int _lineasPreview = 5;

  final StoreSelectorService _storeService = StoreSelectorService();
  final ScrollController _scrollController = ScrollController();
  final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'es_CU',
    symbol: r'$ ',
  );
  final NumberFormat _unitFormatter = NumberFormat('#,##0.##');
  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _dayFormatter = DateFormat('dd/MM/yyyy');

  Timer? _debounceTimer;
  List<CajaTurno> _turnos = [];
  List<Map<String, dynamic>> _tpvs = [];
  List<Map<String, dynamic>> _vendedores = [];

  /// Turnos con el panel de discrepancias desplegado (por id de turno).
  final Set<int> _expandidos = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  int _currentPage = 1;
  int _totalCount = 0;
  final int _itemsPerPage = 20;

  String _searchQuery = '';
  int? _selectedTpvId;
  int? _selectedVendedorId;
  int? _selectedEstado;
  bool _soloDiscrepancias = false;
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
  void didUpdateWidget(CajaTurnosTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _searchQuery = widget.searchQuery;
      _debounceSearch();
    }
  }

  // ===================================================================
  // Carga de datos
  // ===================================================================

  Future<void> _loadInitialData() async {
    final storeId = await _getStoreId();
    if (!mounted) return;

    if (storeId == null) {
      setState(() => _isLoading = false);
      return;
    }

    _currentStoreId = storeId;
    await _loadFilters(storeId);
    await _loadTurnos(reset: true, storeId: storeId);
  }

  void _onStoreChanged() async {
    if (_storeService.isLoading || !_storeService.isInitialized) return;
    final storeId = _storeService.getSelectedStoreId();
    if (storeId == null || storeId == _currentStoreId) return;

    _currentStoreId = storeId;
    _resetFilters();
    await _loadFilters(storeId);
    await _loadTurnos(reset: true, storeId: storeId);
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

  void _resetFilters() {
    _selectedTpvId = null;
    _selectedVendedorId = null;
    _selectedEstado = null;
    _soloDiscrepancias = false;
    _fechaDesde = null;
    _fechaHasta = null;
    _expandidos.clear();
  }

  Future<void> _loadFilters(int storeId) async {
    try {
      final results = await Future.wait([
        TpvService.getTpvsByStoreId(storeId),
        VendedorService.getVendedoresByStoreId(storeId),
      ]);
      if (!mounted) return;
      setState(() {
        _tpvs = results[0];
        _vendedores = results[1];
      });
    } catch (e) {
      print('❌ Error cargando filtros de turnos: $e');
    }
  }

  Future<void> _loadTurnos({required bool reset, int? storeId}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _expandidos.clear();
      });
    }

    final resolvedStoreId = storeId ?? _currentStoreId ?? await _getStoreId();
    if (!mounted) return;

    if (resolvedStoreId == null) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _turnos = [];
        _totalCount = 0;
        _hasNextPage = false;
      });
      return;
    }
    _currentStoreId = resolvedStoreId;

    try {
      final response = await CajaTurnoService.listTurnos(
        storeId: resolvedStoreId,
        idTpv: _selectedTpvId,
        idVendedor: _selectedVendedorId,
        estado: _selectedEstado,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
        soloDiscrepancias: _soloDiscrepancias,
        busqueda: _searchQuery.trim().isEmpty ? null : _searchQuery.trim(),
        limite: _itemsPerPage,
        pagina: _currentPage,
      );

      if (!mounted) return;
      setState(() {
        if (reset) {
          _turnos = response.turnos;
        } else {
          _turnos.addAll(response.turnos);
        }
        _totalCount = response.totalCount;
        _hasNextPage = _turnos.length < _totalCount;
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
      ).showSnackBar(SnackBar(content: Text('Error al cargar turnos: $e')));
    }
  }

  void _debounceSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      _loadTurnos(reset: true);
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNextPage || _isLoading) return;
    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });
    await _loadTurnos(reset: false);
  }

  Future<void> _refreshTurnos() async {
    widget.onRefresh();
    await _loadTurnos(reset: true);
  }

  // ===================================================================
  // Filtros
  // ===================================================================

  bool get _hasActiveFilters =>
      _selectedTpvId != null ||
      _selectedVendedorId != null ||
      _selectedEstado != null ||
      _soloDiscrepancias ||
      _fechaDesde != null ||
      _fechaHasta != null;

  Future<void> _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: (_fechaDesde != null && _fechaHasta != null)
          ? DateTimeRange(start: _fechaDesde!, end: _fechaHasta!)
          : null,
    );
    if (picked == null) return;
    setState(() {
      _fechaDesde = picked.start;
      _fechaHasta = picked.end;
    });
    _loadTurnos(reset: true);
  }

  String _describirFiltros() {
    final partes = <String>[];
    if (_selectedTpvId != null) {
      final tpv = _tpvs.firstWhere(
        (t) => t['id'] == _selectedTpvId,
        orElse: () => <String, dynamic>{},
      );
      if (tpv.isNotEmpty) partes.add('TPV: ${tpv['denominacion']}');
    }
    if (_selectedVendedorId != null) {
      partes.add('Vendedor: ${_nombreVendedor(_selectedVendedorId!)}');
    }
    if (_selectedEstado != null) {
      partes.add(_selectedEstado == 1 ? 'Solo abiertos' : 'Solo cerrados');
    }
    if (_soloDiscrepancias) partes.add('Solo con discrepancias');
    if (_searchQuery.trim().isNotEmpty) partes.add('Búsqueda: $_searchQuery');
    return partes.join(' · ');
  }

  String _nombreVendedor(int idVendedor) {
    final vendedor = _vendedores.firstWhere(
      (v) => v['id'] == idVendedor,
      orElse: () => <String, dynamic>{},
    );
    if (vendedor.isEmpty) return 'Vendedor #$idVendedor';
    final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
    if (trabajador == null) return 'Vendedor #$idVendedor';
    final nombre =
        '${trabajador['nombres'] ?? ''} ${trabajador['apellidos'] ?? ''}'.trim();
    return nombre.isEmpty ? 'Vendedor #$idVendedor' : nombre;
  }

  // ===================================================================
  // Impresion
  // ===================================================================

  String get _storeName =>
      _storeService.selectedStore?.denominacion ?? 'Tienda';

  Future<void> _imprimirActa(CajaTurno turno) async {
    try {
      await CajaTurnoPdfService.imprimirActaTurno(
        turno: turno,
        storeName: _storeName,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al generar el acta: $e')));
    }
  }

  Future<void> _imprimirListado() async {
    if (_turnos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay turnos para imprimir')),
      );
      return;
    }
    try {
      await CajaTurnoPdfService.imprimirListadoTurnos(
        turnos: _turnos,
        storeName: _storeName,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
        filtroDescripcion: _describirFiltros(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar el listado: $e')),
      );
    }
  }

  // ===================================================================
  // Build
  // ===================================================================

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshTurnos,
            color: AppColors.primary,
            backgroundColor: Colors.white,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildTurnosContent(),
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
              Expanded(child: _buildTpvDropdown()),
              const SizedBox(width: 8),
              Expanded(child: _buildVendedorDropdown()),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildEstadoChips(),
              _buildDateFilterButton(),
              FilterChip(
                selected: _soloDiscrepancias,
                showCheckmark: false,
                avatar: Icon(
                  Icons.rule,
                  size: 15,
                  color: _soloDiscrepancias
                      ? Colors.white
                      : AppColors.textSecondary,
                ),
                label: const Text('Con discrepancias'),
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: _soloDiscrepancias
                      ? Colors.white
                      : AppColors.textSecondary,
                ),
                selectedColor: AppColors.warning,
                backgroundColor: AppColors.surfaceVariant,
                side: BorderSide(color: AppColors.border),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (value) {
                  setState(() => _soloDiscrepancias = value);
                  _loadTurnos(reset: true);
                },
              ),
              OutlinedButton.icon(
                onPressed: _imprimirListado,
                icon: const Icon(Icons.print_outlined, size: 15),
                label: const Text('Imprimir', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (_hasActiveFilters) _buildClearFiltersButton(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Mostrando ${_turnos.length} de $_totalCount turnos',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTpvDropdown() {
    return DropdownButtonFormField<int?>(
      value: _selectedTpvId,
      isExpanded: true,
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'TPV',
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Todos los TPVs', style: TextStyle(fontSize: 12)),
        ),
        ..._tpvs.map(
          (tpv) => DropdownMenuItem<int?>(
            value: tpv['id'] as int,
            child: Text(
              tpv['denominacion']?.toString() ?? 'TPV ${tpv['id']}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() => _selectedTpvId = value);
        _loadTurnos(reset: true);
      },
    );
  }

  Widget _buildVendedorDropdown() {
    return DropdownButtonFormField<int?>(
      value: _selectedVendedorId,
      isExpanded: true,
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Vendedor',
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 8,
        ),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Todos los vendedores', style: TextStyle(fontSize: 12)),
        ),
        ..._vendedores
            .where((v) => v['id'] is int)
            .map(
              (vendedor) => DropdownMenuItem<int?>(
                value: vendedor['id'] as int,
                child: Text(
                  _nombreVendedor(vendedor['id'] as int),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
      ],
      onChanged: (value) {
        setState(() => _selectedVendedorId = value);
        _loadTurnos(reset: true);
      },
    );
  }

  Widget _buildEstadoChips() {
    Widget chip(String label, int? valor, IconData icono) {
      final selected = _selectedEstado == valor;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          selected: selected,
          showCheckmark: false,
          avatar: Icon(
            icono,
            size: 15,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
          label: Text(label),
          labelStyle: TextStyle(
            fontSize: 11,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surfaceVariant,
          side: BorderSide(color: AppColors.border),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) {
            setState(() => _selectedEstado = selected ? null : valor);
            _loadTurnos(reset: true);
          },
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('Abiertos', 1, Icons.lock_open),
        chip('Cerrados', 2, Icons.lock_outline),
      ],
    );
  }

  Widget _buildDateFilterButton() {
    final tieneRango = _fechaDesde != null && _fechaHasta != null;
    final label = tieneRango
        ? '${_dayFormatter.format(_fechaDesde!)} - ${_dayFormatter.format(_fechaHasta!)}'
        : 'Fechas';

    return OutlinedButton.icon(
      onPressed: _showDateRangePicker,
      icon: const Icon(Icons.date_range, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: tieneRango ? AppColors.primary : AppColors.secondary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildClearFiltersButton() {
    return OutlinedButton.icon(
      onPressed: () {
        setState(_resetFilters);
        _loadTurnos(reset: true);
      },
      icon: const Icon(Icons.clear, size: 15),
      label: const Text('Limpiar', style: TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.error,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ===================================================================
  // Listado
  // ===================================================================

  Widget _buildTurnosContent() {
    if (_turnos.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 60),
          Icon(Icons.point_of_sale, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay turnos registrados',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 6),
          Text(
            _hasActiveFilters || _searchQuery.trim().isNotEmpty
                ? 'Prueba a ajustar los filtros o el rango de fechas'
                : 'Los turnos aparecerán aquí cuando se abran cajas en los TPVs',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      );
    }

    final totalItems = _turnos.length + (_isLoadingMore ? 1 : 0) + 1;
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index == 0) return _buildResultsHeader();
        final itemIndex = index - 1;
        if (itemIndex == _turnos.length) return _buildLoadingMoreIndicator();
        return _buildTurnoCard(_turnos[itemIndex]);
      },
    );
  }

  Widget _buildResultsHeader() {
    final resumen = CajaTurnoResponse(turnos: _turnos, totalCount: _totalCount);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Resumen de ${_turnos.length} turno${_turnos.length == 1 ? '' : 's'} cargado${_turnos.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildKpi(
                'Ventas',
                _currencyFormatter.format(resumen.ventasTotales),
              ),
              _buildKpi(
                'Efectivo',
                _currencyFormatter.format(resumen.efectivoCobrado),
              ),
              _buildKpi(
                'Digital',
                _currencyFormatter.format(resumen.digitalCobrado),
              ),
              _buildKpi('Egresos', _currencyFormatter.format(resumen.egresos)),
              _buildKpi('Abiertos', '${resumen.turnosAbiertos}'),
              _buildKpi(
                'Descuadres',
                '${resumen.turnosConDescuadre}',
                alerta: resumen.turnosConDescuadre > 0,
              ),
              _buildKpi(
                'Discrepancias',
                '${resumen.turnosConDiscrepancias}',
                alerta: resumen.turnosConDiscrepancias > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpi(String label, String value, {bool alerta = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(alerta ? 0.28 : 0.15),
        borderRadius: BorderRadius.circular(8),
        border: alerta
            ? Border.all(color: Colors.white.withOpacity(0.6))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
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

  // ===================================================================
  // Tarjeta de turno
  // ===================================================================

  Color _conciliacionColor(CajaTurno turno) {
    switch (turno.conciliacionEstado) {
      case 'Abierto':
        return AppColors.info;
      case 'Sin conteo':
        return AppColors.textLight;
      case 'Conciliado':
      case 'Casi exacto':
        return AppColors.success;
      case 'Sobrante':
        return AppColors.warning;
      case 'Faltante':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _conciliacionIcono(CajaTurno turno) {
    switch (turno.conciliacionEstado) {
      case 'Abierto':
        return Icons.lock_open;
      case 'Sin conteo':
        return Icons.help_outline;
      case 'Conciliado':
      case 'Casi exacto':
        return Icons.verified_outlined;
      case 'Sobrante':
        return Icons.trending_up;
      case 'Faltante':
        return Icons.trending_down;
      default:
        return Icons.point_of_sale;
    }
  }

  Widget _buildTurnoCard(CajaTurno turno) {
    final color = _conciliacionColor(turno);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTurnoDetalle(turno),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCardHeader(turno, color),
              const SizedBox(height: 12),
              _buildConciliacion(turno, color),
              if (turno.operacionesVenta > 0 || turno.ventasTotales > 0) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildInfoChip(
                      Icons.attach_money,
                      'Ventas ${_currencyFormatter.format(turno.ventasTotales)}',
                    ),
                    _buildInfoChip(
                      Icons.receipt_long,
                      '${turno.operacionesVenta} ops',
                    ),
                    _buildInfoChip(
                      Icons.confirmation_number_outlined,
                      'Ticket ${_currencyFormatter.format(turno.ticketPromedio)}',
                    ),
                    if (turno.productosVendidos > 0)
                      _buildInfoChip(
                        Icons.inventory_2_outlined,
                        '${_unitFormatter.format(turno.productosVendidos)} uds',
                      ),
                    if (turno.tieneEgresos)
                      _buildInfoChip(
                        Icons.call_made,
                        '${turno.egresosCantidad} egresos',
                      ),
                  ],
                ),
              ],
              if (turno.tieneDiscrepanciasInventario) ...[
                const SizedBox(height: 12),
                _buildDiscrepanciasPanel(turno),
              ] else if (turno.tieneObservaciones) ...[
                const SizedBox(height: 12),
                _buildNotasPanel(turno),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showTurnoDetalle(turno),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text(
                      'Detalle',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: () => _imprimirActa(turno),
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('Acta', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      visualDensity: VisualDensity.compact,
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

  Widget _buildCardHeader(CajaTurno turno, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_conciliacionIcono(turno), color: color, size: 20),
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
                      turno.tpvDenominacion,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '#${turno.id}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                turno.vendedorDisplay,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildEstadoBadge(turno, color),
                  _buildInfoChip(
                    Icons.login,
                    _dateFormatter.format(turno.fechaApertura),
                  ),
                  _buildInfoChip(
                    Icons.logout,
                    turno.fechaCierre == null
                        ? 'En curso'
                        : _dateFormatter.format(turno.fechaCierre!),
                  ),
                  _buildInfoChip(Icons.timer_outlined, turno.duracionDisplay),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEstadoBadge(CajaTurno turno, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        '${turno.estadoLabel} · ${turno.conciliacionEstado}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// Libro de caja compacto: cada linea es un paso del arqueo, para que el
  /// auditor pueda seguir el calculo sin abrir el detalle.
  Widget _buildConciliacion(CajaTurno turno, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _buildLedgerRow('Fondo inicial', turno.efectivoInicial),
          _buildLedgerRow(
            '(+) Efectivo cobrado',
            turno.totalEfectivo,
            color: AppColors.success,
          ),
          _buildLedgerRow(
            '(-) Egresos parciales',
            turno.totalEgresos,
            color: turno.tieneEgresos ? AppColors.warning : null,
          ),
          const Divider(height: 14, thickness: 0.6),
          _buildLedgerRow(
            '(=) Esperado en caja',
            turno.efectivoEsperadoCalculado,
            bold: true,
          ),
          _buildLedgerRow(
            'Contado al cierre',
            turno.efectivoReal,
            bold: true,
            placeholder: 'Sin conteo',
          ),
          _buildLedgerRow(
            'Diferencia',
            turno.diferenciaCalculada,
            bold: true,
            color: color,
            placeholder: '—',
            signo: true,
          ),
          if (turno.esperadoRegistradoDudoso) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: AppColors.textLight,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'El TPV registró esperado ${_currencyFormatter.format(turno.efectivoEsperadoRegistrado ?? 0)} '
                    'y diferencia ${_currencyFormatter.format(turno.diferenciaRegistrada ?? 0)}. '
                    'Arriba se muestra el recálculo.',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textLight,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLedgerRow(
    String label,
    double? value, {
    bool bold = false,
    Color? color,
    String placeholder = '—',
    bool signo = false,
  }) {
    final texto = value == null
        ? placeholder
        : signo && value > 0
        ? '+${_currencyFormatter.format(value)}'
        : _currencyFormatter.format(value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: bold ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================================
  // Panel de discrepancias (FALTANTES / EXCESOS)
  // ===================================================================

  Widget _buildDiscrepanciasPanel(CajaTurno turno) {
    final reporte = turno.reporte;
    final expandido = _expandidos.contains(turno.id);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Discrepancias de inventario',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${reporte.totalLineas} línea${reporte.totalLineas == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (reporte.faltantes.isNotEmpty)
                  Expanded(
                    child: _buildResumenDiscrepancia(
                      'FALTANTES',
                      reporte.faltantes.length,
                      reporte.unidadesFaltantes,
                      AppColors.error,
                      Icons.arrow_downward,
                    ),
                  ),
                if (reporte.faltantes.isNotEmpty && reporte.excesos.isNotEmpty)
                  const SizedBox(width: 8),
                if (reporte.excesos.isNotEmpty)
                  Expanded(
                    child: _buildResumenDiscrepancia(
                      'EXCESOS',
                      reporte.excesos.length,
                      reporte.unidadesExcedentes,
                      AppColors.warning,
                      Icons.arrow_upward,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (reporte.faltantes.isNotEmpty)
            _buildBloqueLineas(
              'FALTANTES',
              reporte.faltantes,
              AppColors.error,
              expandido,
            ),
          if (reporte.excesos.isNotEmpty)
            _buildBloqueLineas(
              'EXCESOS',
              reporte.excesos,
              AppColors.warning,
              expandido,
            ),
          if (reporte.totalLineas > _lineasPreview * 2 ||
              reporte.faltantes.length > _lineasPreview ||
              reporte.excesos.length > _lineasPreview)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    if (expandido) {
                      _expandidos.remove(turno.id);
                    } else {
                      _expandidos.add(turno.id);
                    }
                  });
                },
                icon: Icon(
                  expandido ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                ),
                label: Text(
                  expandido
                      ? 'Ver menos'
                      : 'Ver las ${reporte.totalLineas} líneas',
                  style: const TextStyle(fontSize: 11.5),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildResumenDiscrepancia(
    String titulo,
    int productos,
    double unidades,
    Color color,
    IconData icono,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icono, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '$productos producto${productos == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            '${_unitFormatter.format(unidades)} uds',
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBloqueLineas(
    String titulo,
    List<DiscrepanciaInventario> lineas,
    Color color,
    bool expandido,
  ) {
    final visibles = expandido
        ? lineas
        : lineas.take(_lineasPreview).toList();
    final ocultas = lineas.length - visibles.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          ...visibles.map((d) => _buildLineaDiscrepancia(d, color)),
          if (ocultas > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 18),
              child: Text(
                '+ $ocultas más',
                style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: AppColors.textLight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLineaDiscrepancia(DiscrepanciaInventario d, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              d.producto,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _unitFormatter.format(d.cantidad),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotasPanel(CajaTurno turno) {
    final notas = turno.reporte.notas;
    final texto = notas.isNotEmpty
        ? notas.join('\n')
        : (turno.observaciones ?? '');
    if (texto.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sticky_note_2_outlined,
            size: 15,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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

  // ===================================================================
  // Detalle
  // ===================================================================

  void _showTurnoDetalle(CajaTurno turno) {
    final color = _conciliacionColor(turno);
    final reporte = turno.reporte;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _conciliacionIcono(turno),
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Turno #${turno.id} · ${turno.tpvDenominacion}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${turno.estadoLabel} · ${turno.conciliacionEstado}',
                            style: TextStyle(fontSize: 12, color: color),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Imprimir acta',
                      icon: const Icon(Icons.print_outlined),
                      color: AppColors.primary,
                      onPressed: () => _imprimirActa(turno),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildDetalleSeccion('Datos del turno'),
                    _buildDetalleFila('Vendedor', turno.vendedorDisplay),
                    _buildDetalleFila(
                      'Apertura',
                      _dateFormatter.format(turno.fechaApertura),
                    ),
                    _buildDetalleFila(
                      'Cierre',
                      turno.fechaCierre == null
                          ? 'En curso'
                          : _dateFormatter.format(turno.fechaCierre!),
                    ),
                    _buildDetalleFila('Duración', turno.duracionDisplay),
                    _buildDetalleFila('Cerrado por', turno.cerradoPorDisplay),
                    _buildDetalleFila(
                      'Maneja inventario',
                      turno.manejaInventario ? 'Sí' : 'No',
                    ),
                    _buildDetalleFila(
                      'Operaciones',
                      'Apertura #${turno.idOperacionApertura ?? '-'} / Cierre #${turno.idOperacionCierre ?? '-'}',
                    ),
                    const SizedBox(height: 16),
                    _buildDetalleSeccion('Conciliación de efectivo'),
                    _buildConciliacion(turno, color),
                    const SizedBox(height: 16),
                    _buildDetalleSeccion('Ventas'),
                    _buildDetalleFila(
                      'Total vendido',
                      _currencyFormatter.format(turno.ventasTotales),
                    ),
                    _buildDetalleFila(
                      'Operaciones',
                      '${turno.operacionesVenta} (${turno.ventasPagadas} pagadas)',
                    ),
                    _buildDetalleFila(
                      'Ticket promedio',
                      _currencyFormatter.format(turno.ticketPromedio),
                    ),
                    _buildDetalleFila(
                      'Unidades vendidas',
                      _unitFormatter.format(turno.productosVendidos),
                    ),
                    _buildDetalleFila(
                      'Cobros digitales',
                      _currencyFormatter.format(turno.totalDigital),
                    ),
                    _buildDetalleFila(
                      '% efectivo',
                      '${turno.porcentajeEfectivo.toStringAsFixed(1)}%',
                    ),
                    if (turno.desglosePagos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetalleSeccion('Desglose de cobros'),
                      ...turno.desglosePagos.map(
                        (p) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(
                                p.esEfectivo
                                    ? Icons.payments_outlined
                                    : Icons.credit_card,
                                size: 14,
                                color: p.esEfectivo
                                    ? AppColors.success
                                    : AppColors.info,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.medio,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '${p.cantidad}x',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textLight,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _currencyFormatter.format(p.monto),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (reporte.faltantes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetalleSeccion(
                        'Faltantes (${reporte.faltantes.length} productos · '
                        '${_unitFormatter.format(reporte.unidadesFaltantes)} uds)',
                        color: AppColors.error,
                      ),
                      ...reporte.faltantes.map(
                        (d) => _buildLineaDiscrepancia(d, AppColors.error),
                      ),
                    ],
                    if (reporte.excesos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetalleSeccion(
                        'Excesos (${reporte.excesos.length} productos · '
                        '${_unitFormatter.format(reporte.unidadesExcedentes)} uds)',
                        color: AppColors.warning,
                      ),
                      ...reporte.excesos.map(
                        (d) => _buildLineaDiscrepancia(d, AppColors.warning),
                      ),
                    ],
                    if (reporte.notas.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDetalleSeccion('Otras observaciones'),
                      ...reporte.notas.map(
                        (n) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '• $n',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetalleSeccion(String titulo, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color ?? AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetalleFila(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
