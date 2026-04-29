import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product.dart';
import '../services/product_movements_service.dart';
import '../services/user_preferences_service.dart';
import '../config/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/web_download_stub.dart'
    if (dart.library.html) '../services/web_download_web.dart'
    as web_download;

class ProductMovementsScreen extends StatefulWidget {
  final Product product;

  const ProductMovementsScreen({
    super.key,
    required this.product,
  });

  @override
  State<ProductMovementsScreen> createState() => _ProductMovementsScreenState();
}

class _ProductMovementsScreenState extends State<ProductMovementsScreen> {
  late Product _product;
  List<Map<String, dynamic>> _movements = [];
  List<Map<String, dynamic>> _filteredMovements = [];
  List<Map<String, dynamic>> _operationTypes = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  late ScrollController _scrollController;

  // Paginado
  int _currentOffset = 0;
  int _pageSize = 20;
  int _totalCount = 0;
  bool _hasMoreData = true;

  // Filtros
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int? _selectedOperationTypeId;
  int? _selectedWarehouseId;
  String _selectedWarehouse = 'Todos';
  List<Map<String, dynamic>> _warehouses = [];
  bool _isLoadingWarehouses = false;
  bool _isExportingPdf = false;
  bool _filtersExpanded = false;
  String? _selectedTipoMovimiento;
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    // Inicializar filtros por defecto: fecha actual
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, 1, 0, 0, 0);
    _dateTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadWarehouses();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
      if (_hasMoreData && !_isLoadingMore) {
        _loadMoreData();
      }
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
    } catch (e) {
      print('❌ Error loading warehouses: $e');
      setState(() {
        _warehouses = [];
        _isLoadingWarehouses = false;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _currentOffset = 0;
      _movements = [];
      _hasMoreData = true;
    });
    try {
      // Cargar tipos de operación
      final types = await ProductMovementsService.getOperationTypes();
      
      // Cargar primera página de movimientos
      final result = await ProductMovementsService.getProductMovements(
        productId: int.parse(_product.id),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        operationTypeId: _selectedOperationTypeId,
        warehouseId: _selectedWarehouseId,
        offset: 0,
        limit: _pageSize,
      );

      setState(() {
        _operationTypes = types;
        _movements = List<Map<String, dynamic>>.from(result['movements'] ?? []);
        _totalCount = result['total_count'] ?? 0;
        _currentOffset = _pageSize;
        _hasMoreData = _movements.length < _totalCount;
        _applyFilters();
      });
    } catch (e) {
      print('❌ Error al cargar datos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar movimientos: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoadingMore || !_hasMoreData) return;
    
    setState(() => _isLoadingMore = true);
    try {
      final result = await ProductMovementsService.getProductMovements(
        productId: int.parse(_product.id),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        operationTypeId: _selectedOperationTypeId,
        warehouseId: _selectedWarehouseId,
        offset: _currentOffset,
        limit: _pageSize,
      );

      setState(() {
        final newMovements = List<Map<String, dynamic>>.from(result['movements'] ?? []);
        _movements.addAll(newMovements);
        _totalCount = result['total_count'] ?? 0;
        _currentOffset += _pageSize;
        _hasMoreData = _movements.length < _totalCount;
        _applyFilters();
      });
    } catch (e) {
      print('❌ Error al cargar más movimientos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar más movimientos: $e')),
        );
      }
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  void _applyFilters() {
    // Optimización: Filtrado eficiente con validaciones tempranas
    _filteredMovements = _movements.where((movement) {
      // Filtro por tipo de operación (validación más rápida)
      if (_selectedOperationTypeId != null && 
          movement['tipo_operacion_id'] != _selectedOperationTypeId) {
        return false;
      }

      // Filtro por fecha (solo si hay filtros de fecha)
      if (_dateFrom != null || _dateTo != null) {
        final fechaStr = movement['fecha'] as String?;
        if (fechaStr == null || fechaStr.isEmpty) {
          return false;
        }
        
        final movementDate = DateTime.tryParse(fechaStr);
        if (movementDate == null) {
          return false;
        }

        // Comparación optimizada de fechas
        if (_dateFrom != null && movementDate.isBefore(_dateFrom!)) {
          return false;
        }
        if (_dateTo != null && movementDate.isAfter(_dateTo!)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Ordenar por fecha ascendente (más antiguos primero)
    _filteredMovements.sort((a, b) {
      final dateA = DateTime.tryParse(a['fecha'] as String? ?? '') ?? DateTime(2000);
      final dateB = DateTime.tryParse(b['fecha'] as String? ?? '') ?? DateTime(2000);
      return dateA.compareTo(dateB);
    });

    setState(() {});
  }

  List<Map<String, dynamic>> get _displayMovements {
    if (_selectedTipoMovimiento == null) return _filteredMovements;
    return _filteredMovements
        .where((m) => m['tipo_movimiento'] == _selectedTipoMovimiento)
        .toList();
  }

  Future<void> _selectDateFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateFrom ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _dateFrom = picked);
      _loadData();
    }
  }

  Future<void> _selectDateTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTo ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _dateTo = picked);
      _loadData();
    }
  }

  void _clearFilters() {
    // Reiniciar a filtros por defecto (fecha actual)
    final now = DateTime.now();
    setState(() {
      _dateFrom = DateTime(now.year, now.month, 1, 0, 0, 0);
      _dateTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
      _selectedOperationTypeId = null;
      _selectedWarehouseId = null;
      _selectedWarehouse = 'Todos';
      _selectedTipoMovimiento = null;
    });
    _loadData();
  }

  Color _getEstadoColor(String estado) {
    switch (estado.toLowerCase()) {
      case 'pendiente':
        return Colors.orange;
      case 'completada':
        return Colors.green;
      case 'devuelta':
        return Colors.blue;
      case 'cancelada':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }

  Color _getMovementTypeColor(String tipoMovimiento) {
    switch (tipoMovimiento) {
      case 'Recepción':
        return Colors.green;
      case 'Extracción':
        return Colors.orange;
      case 'Control':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getMovementTypeIcon(String tipoMovimiento) {
    switch (tipoMovimiento) {
      case 'Recepción':
        return Icons.arrow_downward;
      case 'Extracción':
        return Icons.arrow_upward;
      case 'Control':
        return Icons.assignment_turned_in;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Movimientos - ${_product.denominacion}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          // Botón filtros con badge si hay filtros activos
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: Icon(
                  _filtersExpanded
                      ? Icons.filter_list_off
                      : Icons.filter_list,
                ),
                tooltip: _filtersExpanded ? 'Ocultar filtros' : 'Mostrar filtros',
                onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
              ),
              if (_hasActiveFilters())
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          if (_isExportingPdf)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Exportar PDF',
              onPressed: _filteredMovements.isEmpty ? null : _exportMovementsPdf,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Panel de filtros colapsable
                _buildCollapsibleFilters(),

                // Resumen clicable
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        _buildSummaryTile(
                          label: 'Total',
                          count: _filteredMovements.length,
                          color: Colors.blueGrey,
                          isSelected: _selectedTipoMovimiento == null,
                          onTap: () => setState(() => _selectedTipoMovimiento = null),
                        ),
                        _buildSummaryDivider(),
                        _buildSummaryTile(
                          label: 'Recepción',
                          count: _filteredMovements
                              .where((m) => m['tipo_movimiento'] == 'Recepción')
                              .length,
                          color: Colors.green,
                          isSelected: _selectedTipoMovimiento == 'Recepción',
                          onTap: () => setState(() {
                            _selectedTipoMovimiento =
                                _selectedTipoMovimiento == 'Recepción'
                                    ? null
                                    : 'Recepción';
                          }),
                        ),
                        _buildSummaryDivider(),
                        _buildSummaryTile(
                          label: 'Extracción',
                          count: _filteredMovements
                              .where((m) => m['tipo_movimiento'] == 'Extracción')
                              .length,
                          color: Colors.orange,
                          isSelected: _selectedTipoMovimiento == 'Extracción',
                          onTap: () => setState(() {
                            _selectedTipoMovimiento =
                                _selectedTipoMovimiento == 'Extracción'
                                    ? null
                                    : 'Extracción';
                          }),
                        ),
                        _buildSummaryDivider(),
                        _buildSummaryTile(
                          label: 'Control',
                          count: _filteredMovements
                              .where((m) => m['tipo_movimiento'] == 'Control')
                              .length,
                          color: Colors.blue,
                          isSelected: _selectedTipoMovimiento == 'Control',
                          onTap: () => setState(() {
                            _selectedTipoMovimiento =
                                _selectedTipoMovimiento == 'Control'
                                    ? null
                                    : 'Control';
                          }),
                        ),
                      ],
                    ),
                  ),
                ),

                // Lista de movimientos en formato tabla
                Expanded(
                  child: _filteredMovements.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                'No hay movimientos',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            _buildTableHeader(),
                            Expanded(
                              child: _displayMovements.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(32),
                                        child: Text(
                                          'Sin movimientos de tipo "$_selectedTipoMovimiento"',
                                          style: TextStyle(color: Colors.grey.shade600),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      itemCount: _displayMovements.length +
                                          (_hasMoreData ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (index == _displayMovements.length) {
                                          return Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Center(
                                              child: _isLoadingMore
                                                  ? const CircularProgressIndicator()
                                                  : Text(
                                                      'Cargando más...',
                                                      style: TextStyle(
                                                        color: Colors.grey.shade600,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                            ),
                                          );
                                        }
                                        final movement = _displayMovements[index];
                                        return _buildMovementRow(movement, index);
                                      },
                                    ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  bool _hasActiveFilters() {
    final now = DateTime.now();
    final defaultFrom = DateTime(now.year, now.month, 1, 0, 0, 0);
    final defaultTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final isDefaultDateFrom = _dateFrom != null &&
        _dateFrom!.year == defaultFrom.year &&
        _dateFrom!.month == defaultFrom.month &&
        _dateFrom!.day == defaultFrom.day;
    final isDefaultDateTo = _dateTo != null &&
        _dateTo!.year == defaultTo.year &&
        _dateTo!.month == defaultTo.month &&
        _dateTo!.day == defaultTo.day;
    return _selectedOperationTypeId != null ||
        _selectedWarehouseId != null ||
        _selectedTipoMovimiento != null ||
        !isDefaultDateFrom ||
        !isDefaultDateTo;
  }

  Widget _buildCollapsibleFilters() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _filtersExpanded
          ? _buildFiltersSection()
          : const SizedBox.shrink(),
    );
  }

  Future<void> _exportMovementsPdf() async {
    setState(() => _isExportingPdf = true);
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
      final productName = _product.denominacion.replaceAll(' ', '_');
      final fileName = 'Movimientos_${productName}_$dateStr.pdf';

      final pdf = pw.Document();
      final regularFont = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      // Encabezado de filtros aplicados
      final String periodoStr = (_dateFrom != null && _dateTo != null)
          ? '${DateFormat('dd/MM/yyyy').format(_dateFrom!)} - ${DateFormat('dd/MM/yyyy').format(_dateTo!)}'
          : _dateFrom != null
              ? 'Desde ${DateFormat('dd/MM/yyyy').format(_dateFrom!)}'
              : _dateTo != null
                  ? 'Hasta ${DateFormat('dd/MM/yyyy').format(_dateTo!)}'
                  : 'Todos los períodos';

      final String almacenStr = _selectedWarehouse == 'Todos'
          ? 'Todos los almacenes'
          : _warehouses
                .firstWhere(
                  (w) => w['id'].toString() == _selectedWarehouse,
                  orElse: () => {'denominacion': _selectedWarehouse},
                )['denominacion'] as String? ??
              _selectedWarehouse;

      final String tipoMovStr = _selectedTipoMovimiento ?? 'Todos';

      final String tipoOpStr = _selectedOperationTypeId != null
          ? (_operationTypes.firstWhere(
                (t) => t['id'] == _selectedOperationTypeId,
                orElse: () => {'denominacion': 'Desconocido'},
              )['denominacion'] as String? ??
              'Desconocido')
          : 'Todos';

      // Movimientos a exportar (respetando filtro de tipo movimiento)
      final movimientosExport = _displayMovements;

      // Totales calculados sobre los datos a exportar
      final totalRecepciones = movimientosExport
          .where((m) => m['tipo_movimiento'] == 'Recepción')
          .fold<double>(
            0,
            (s, m) => s + ((m['cantidad'] as num?)?.toDouble() ?? 0),
          );
      final totalExtracciones = movimientosExport
          .where((m) => m['tipo_movimiento'] == 'Extracción')
          .fold<double>(
            0,
            (s, m) => s + ((m['cantidad'] as num?)?.toDouble() ?? 0),
          );

      // Anchos de columna: Fecha, Almacén, N° Op., Tipo, Entrada, Salida, Saldo
      final colWidths = {
        0: const pw.FixedColumnWidth(68),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FixedColumnWidth(44),
        3: const pw.FixedColumnWidth(62),
        4: const pw.FixedColumnWidth(52),
        5: const pw.FixedColumnWidth(52),
        6: const pw.FixedColumnWidth(52),
      };

      pw.Widget headerCell(String text) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            color: PdfColors.blueGrey800,
            child: pw.Text(
              text,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 8,
                color: PdfColors.white,
              ),
              textAlign: pw.TextAlign.center,
            ),
          );

      pw.Widget dataCell(String text, {bool bold = false, PdfColor? color}) =>
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: pw.Text(
              text,
              style: pw.TextStyle(
                font: bold ? boldFont : regularFont,
                fontSize: 8,
                color: color ?? PdfColors.black,
              ),
              textAlign: pw.TextAlign.center,
            ),
          );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Reporte de Movimientos de Inventario',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 14,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                  pw.Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(now),
                    style: pw.TextStyle(
                      font: regularFont,
                      fontSize: 9,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blueGrey50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  border: pw.Border.all(color: PdfColors.blueGrey200),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            _product.denominacion,
                            style: pw.TextStyle(font: boldFont, fontSize: 11),
                          ),
                          if (_product.sku.isNotEmpty)
                            pw.Text(
                              'SKU: ${_product.sku}',
                              style: pw.TextStyle(
                                font: regularFont,
                                fontSize: 9,
                                color: PdfColors.grey700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Período: $periodoStr',
                          style: pw.TextStyle(font: regularFont, fontSize: 8),
                        ),
                        pw.Text(
                          'Almacén: $almacenStr',
                          style: pw.TextStyle(font: regularFont, fontSize: 8),
                        ),
                        pw.Text(
                          'Tipo movimiento: $tipoMovStr',
                          style: pw.TextStyle(font: regularFont, fontSize: 8),
                        ),
                        pw.Text(
                          'Tipo operación: $tipoOpStr',
                          style: pw.TextStyle(font: regularFont, fontSize: 8),
                        ),
                      ],
                    ),
                    pw.SizedBox(width: 16),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Total registros: ${movimientosExport.length}',
                          style: pw.TextStyle(font: regularFont, fontSize: 8),
                        ),
                        pw.Text(
                          'Entradas: ${totalRecepciones.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 8,
                            color: PdfColors.green700,
                          ),
                        ),
                        pw.Text(
                          'Salidas: ${totalExtracciones.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 8,
                            color: PdfColors.orange700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
            ],
          ),
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'VentIQ - Reporte generado el ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
                style: pw.TextStyle(
                  font: regularFont,
                  fontSize: 7,
                  color: PdfColors.grey500,
                ),
              ),
              pw.Text(
                'Pág. ${context.pageNumber} / ${context.pagesCount}',
                style: pw.TextStyle(
                  font: regularFont,
                  fontSize: 7,
                  color: PdfColors.grey500,
                ),
              ),
            ],
          ),
          build: (context) => [
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.blueGrey200,
                width: 0.5,
              ),
              columnWidths: colWidths,
              children: [
                // Fila encabezado
                pw.TableRow(
                  children: [
                    headerCell('Fecha'),
                    headerCell('Almacén'),
                    headerCell('N° Op.'),
                    headerCell('Tipo'),
                    headerCell('Entrada'),
                    headerCell('Salida'),
                    headerCell('Saldo'),
                  ],
                ),
                // Filas de datos
                ...movimientosExport.asMap().entries.map((entry) {
                  final i = entry.key;
                  final m = entry.value;
                  final isEven = i % 2 == 0;
                  final rowBg = isEven ? PdfColors.white : PdfColors.blueGrey50;

                  final tipoMov = m['tipo_movimiento'] as String? ?? '';
                  final almacenVal = m['almacen'] as String? ?? '-';
                  final nOp = m['id_operacion']?.toString() ?? '-';
                  final cantidad = (m['cantidad'] as num?)?.toStringAsFixed(2) ?? '-';
                  final cantFinal = (m['cantidad_final'] as num?)?.toStringAsFixed(2) ?? '-';
                  final fechaStr = m['fecha'] as String? ?? '';
                  String fechaFmt = '-';
                  try {
                    fechaFmt = DateFormat('dd/MM/yy\nHH:mm').format(DateTime.parse(fechaStr));
                  } catch (_) {}

                  final isEntrada = tipoMov == 'Recepción';
                  final isControl = tipoMov == 'Control';

                  PdfColor tipoColor = PdfColors.black;
                  if (tipoMov == 'Recepción') tipoColor = PdfColors.green800;
                  if (tipoMov == 'Extracción') tipoColor = PdfColors.orange800;
                  if (isControl) tipoColor = PdfColors.blue800;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowBg),
                    children: [
                      dataCell(fechaFmt),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: pw.Text(
                          almacenVal,
                          style: pw.TextStyle(font: regularFont, fontSize: 7, color: PdfColors.grey800),
                        ),
                      ),
                      dataCell('#$nOp'),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: pw.Text(
                          tipoMov,
                          style: pw.TextStyle(font: boldFont, fontSize: 7, color: tipoColor),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      dataCell(
                        isEntrada ? cantidad : '',
                        bold: true,
                        color: isEntrada ? PdfColors.green800 : PdfColors.white,
                      ),
                      dataCell(
                        !isEntrada ? cantidad : '',
                        bold: true,
                        color: !isEntrada
                            ? (isControl ? PdfColors.blue800 : PdfColors.orange800)
                            : PdfColors.white,
                      ),
                      dataCell(cantFinal, bold: true),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      );

      final fileBytes = Uint8List.fromList(await pdf.save());
      const mimeType = 'application/pdf';

      if (kIsWeb) {
        try {
          web_download.downloadFileWeb(fileBytes, fileName, mimeType);
        } catch (webError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Problema de compatibilidad del navegador. Intenta con Edge o actualiza tu navegador.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      } else {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: mimeType)],
          subject: 'Movimientos - ${_product.denominacion}',
          text: 'Reporte generado el ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
        );
      }

      if (mounted) {
        final message = kIsWeb
            ? 'PDF descargado exitosamente'
            : 'PDF generado y compartido exitosamente';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Widget _buildFiltersSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, size: 15, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Filtros',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_hasActiveFilters())
                    TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear, size: 14),
                      label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                    tooltip: 'Cerrar filtros',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => setState(() => _filtersExpanded = false),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Filtro de fechas
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _selectDateFrom,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Desde',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          _dateFrom != null
                              ? DateFormat('dd/MM/yyyy').format(_dateFrom!)
                              : 'Seleccionar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _dateFrom != null ? Colors.black : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _selectDateTo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                      color: Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hasta',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          _dateTo != null
                              ? DateFormat('dd/MM/yyyy').format(_dateTo!)
                              : 'Seleccionar',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _dateTo != null ? Colors.black : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Filtro de tipo de operación
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              color: Colors.white,
            ),
            child: DropdownButton<int?>(
              value: _selectedOperationTypeId,
              isExpanded: true,
              underline: const SizedBox(),
              hint: const Text('Tipo de Operación'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todos los tipos'),
                ),
                ..._operationTypes.map((type) {
                  return DropdownMenuItem<int?>(
                    value: type['id'] as int,
                    child: Text(type['denominacion'] as String),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() => _selectedOperationTypeId = value);
                _loadData();
              },
            ),
          ),
          const SizedBox(height: 12),
          
          // Filtro de almacén
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6),
              color: Colors.white,
            ),
            child: DropdownButton<String>(
              value: _selectedWarehouse,
              isExpanded: true,
              underline: const SizedBox(),
              hint: const Text('Todos los almacenes'),
              items: [
                const DropdownMenuItem<String>(
                  value: 'Todos',
                  child: Text('Todos los almacenes'),
                ),
                ..._warehouses.map((warehouse) {
                  final warehouseName = warehouse['denominacion'] as String? ?? 'Sin nombre';
                  final warehouseId = warehouse['id'].toString();

                  return DropdownMenuItem<String>(
                    value: warehouseId,
                    child: Text(
                      warehouseName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                }).toList(),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedWarehouse = value!;
                  if (value == 'Todos') {
                    _selectedWarehouseId = null;
                  } else {
                    _selectedWarehouseId = int.tryParse(value);
                  }
                });
                _loadData();
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Summary widgets ───────────────────────────────────────────────────────

  Widget _buildSummaryTile({
    required String label,
    required int count,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? color : Colors.grey.shade600,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : Colors.grey.shade800,
                ),
              ),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  height: 2,
                  width: 20,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryDivider() => Container(
        height: 36,
        width: 1,
        color: Colors.grey.shade200,
      );

  // ─── Table widgets ──────────────────────────────────────────────────────────

  Widget _buildTableHeader() {
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(flex: 24, child: _headerCell('Fecha')),
          Expanded(flex: 22, child: _headerCell('Almacén')),
          Expanded(flex: 15, child: _headerCell('N° Op.')),
          Expanded(flex: 17, child: _headerCell('Entrada', right: true)),
          Expanded(flex: 17, child: _headerCell('Salida', right: true)),
          Expanded(flex: 18, child: _headerCell('Saldo', right: true)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {bool right = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: right ? TextAlign.right : TextAlign.left,
        ),
      );

  Widget _buildMovementRow(Map<String, dynamic> movement, int index) {
    final tipoMovimiento = movement['tipo_movimiento'] as String? ?? '';
    final color = _getMovementTypeColor(tipoMovimiento);
    final isEven = index % 2 == 0;

    final fechaStr = movement['fecha'] as String? ?? '';
    String fechaFmt = '';
    try {
      final dt = DateTime.parse(fechaStr);
      fechaFmt = DateFormat('dd/MM\nHH:mm').format(dt);
    } catch (_) {
      fechaFmt = fechaStr;
    }

    final nOp = movement['id_operacion']?.toString() ?? '-';
    final cantidad =
        (movement['cantidad'] as num?)?.toStringAsFixed(2) ?? '';
    final cantFinal =
        (movement['cantidad_final'] as num?)?.toStringAsFixed(2) ?? '-';

    final isEntrada = tipoMovimiento == 'Recepción';
    final isControl = tipoMovimiento == 'Control';

    final almacen = movement['almacen'] as String? ?? '-';

    return InkWell(
      onTap: () => _showMovementDetail(movement),
      child: Container(
        decoration: BoxDecoration(
          color: isEven ? Colors.white : Colors.grey.shade50,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                flex: 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 6),
                  child: Text(
                    fechaFmt,
                    style: const TextStyle(fontSize: 10, height: 1.35),
                  ),
                ),
              ),
              Expanded(
                flex: 22,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 6),
                  child: Text(
                    almacen,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade700),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ),
              Expanded(
                flex: 15,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    '#$nOp',
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade600),
                  ),
                ),
              ),
              Expanded(
                flex: 17,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    isEntrada ? cantidad : '',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              Expanded(
                flex: 17,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    !isEntrada ? cantidad : '',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isControl ? Colors.blue : Colors.orange,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              Expanded(
                flex: 18,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    cantFinal,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Detail bottom sheet ────────────────────────────────────────────────────

  void _showMovementDetail(Map<String, dynamic> movement) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: _buildMovementDetailContent(movement),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMovementDetailContent(Map<String, dynamic> movement) {
    final tipoMovimiento = movement['tipo_movimiento'] as String? ?? '';
    final color = _getMovementTypeColor(tipoMovimiento);
    final icon = _getMovementTypeIcon(tipoMovimiento);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tipoMovimiento,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(
                    movement['tipo_operacion'] as String? ?? 'Desconocido',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (movement['estado_operacion_nombre'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _getEstadoColor(
                              movement['estado_operacion_nombre'] as String)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getEstadoColor(movement[
                                    'estado_operacion_nombre'] as String)
                                .withOpacity(0.5),
                      ),
                    ),
                    child: Text(
                      movement['estado_operacion_nombre'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _getEstadoColor(
                            movement['estado_operacion_nombre'] as String),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(movement['fecha'] as String? ?? ''),
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (movement['id_operacion'] != null)
                _buildDetailRow('Operación #', '${movement['id_operacion']}'),
              if (movement['cantidad'] != null)
                _buildDetailRow('Cantidad Movida', '${movement['cantidad']}'),
              if (movement['cantidad_inicial'] != null)
                _buildDetailRow(
                    'Cantidad Inicial', '${movement['cantidad_inicial']}'),
              if (movement['cantidad_final'] != null)
                _buildDetailRow(
                    'Cantidad Final', '${movement['cantidad_final']}'),
              if (movement['precio_unitario'] != null)
                _buildDetailRow('Precio Unitario',
                    '\$${(movement['precio_unitario'] as num).toStringAsFixed(2)}'),
              if (movement['costo_real'] != null)
                _buildDetailRow('Costo Real',
                    '\$${(movement['costo_real'] as num).toStringAsFixed(2)}'),
              if (movement['importe_real'] != null)
                _buildDetailRow('Importe Real',
                    '\$${(movement['importe_real'] as num).toStringAsFixed(2)}'),
              if (tipoMovimiento == 'Recepción') ...[
                if (movement['entregado_por'] != null)
                  _buildDetailRow(
                      'Entregado Por', movement['entregado_por'] as String),
                if (movement['recibido_por'] != null)
                  _buildDetailRow(
                      'Recibido Por', movement['recibido_por'] as String),
              ],
              if (tipoMovimiento == 'Extracción' &&
                  movement['autorizado_por'] != null)
                _buildDetailRow(
                    'Autorizado Por', movement['autorizado_por'] as String),
              if (movement['almacen'] != null)
                _buildDetailRow('Almacén', movement['almacen'] as String),
              if (movement['zona'] != null)
                _buildDetailRow('Zona', movement['zona'] as String),
              if (movement['proveedor'] != null)
                _buildDetailRow('Proveedor', movement['proveedor'] as String),
            ],
          ),
        ),
        if (movement['observaciones'] != null &&
            (movement['observaciones'] as String).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Observaciones',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text(
                  movement['observaciones'] as String,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color ?? Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
