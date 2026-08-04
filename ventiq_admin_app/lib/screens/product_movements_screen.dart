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
  bool _isAuditing = false;
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

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  void _applyFilters() {
    // Red de seguridad en cliente: el RPC ya filtra, pero normalizamos IDs
    // (bigint/json) y almacén para evitar filas inconsistentes en la UI.
    _filteredMovements = _movements.where((movement) {
      if (_selectedOperationTypeId != null &&
          _asInt(movement['tipo_operacion_id']) != _selectedOperationTypeId) {
        return false;
      }

      if (_selectedWarehouseId != null) {
        final movWarehouseId = _asInt(
          movement['almacen_id'] ?? movement['id_almacen'],
        );
        if (movWarehouseId != _selectedWarehouseId) {
          return false;
        }
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

        // Comparar por día local para no desalinear por timezone UTC del RPC
        final movementDay = DateTime(
          movementDate.year,
          movementDate.month,
          movementDate.day,
        );
        if (_dateFrom != null) {
          final fromDay = DateTime(
            _dateFrom!.year,
            _dateFrom!.month,
            _dateFrom!.day,
          );
          if (movementDay.isBefore(fromDay)) return false;
        }
        if (_dateTo != null) {
          final toDay = DateTime(
            _dateTo!.year,
            _dateTo!.month,
            _dateTo!.day,
          );
          if (movementDay.isAfter(toDay)) return false;
        }
      }

      return true;
    }).toList();

    // Ordenar por fecha ascendente (más antiguos primero).
    // No usar id: apertura/cierre usan id de control_productos y sesgan el paginado.
    _filteredMovements.sort((a, b) {
      final fa = DateTime.tryParse('${a['fecha'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final fb = DateTime.tryParse('${b['fecha'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final byFecha = fa.compareTo(fb);
      if (byFecha != 0) return byFecha;
      final idA = (a['id'] as num?)?.toInt() ?? 0;
      final idB = (b['id'] as num?)?.toInt() ?? 0;
      return idA.compareTo(idB);
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
      setState(() => _dateTo = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
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
      case 'Reajuste':
        return Colors.purple;
      case 'Ajuste':
        return Colors.teal;
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
      case 'Reajuste':
        return Icons.swap_horiz;
      case 'Ajuste':
        return Icons.tune;
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
          if (_selectedWarehouseId != null)
            _isAuditing
                ? const Padding(
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
                : IconButton(
                    icon: const Icon(Icons.fact_check_outlined),
                    tooltip: 'Auditar continuidad de stock',
                    onPressed: (_isLoading || _isExportingPdf)
                        ? null
                        : _auditMovementsContinuity,
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
              onPressed: (_isLoading || _isAuditing) ? null : _exportMovementsPdf,
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

  /// Aplica los mismos filtros de UI a una lista ya obtenida del RPC
  /// (tipo de movimiento local + orden por id).
  List<Map<String, dynamic>> _prepareMovementsForExport(
    List<Map<String, dynamic>> source,
  ) {
    var list = List<Map<String, dynamic>>.from(source);
    if (_selectedTipoMovimiento != null) {
      list = list
          .where((m) => m['tipo_movimiento'] == _selectedTipoMovimiento)
          .toList();
    }
    list.sort((a, b) {
      final fa = DateTime.tryParse('${a['fecha'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final fb = DateTime.tryParse('${b['fecha'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final byFecha = fa.compareTo(fb);
      if (byFecha != 0) return byFecha;
      final idA = (a['id'] as num?)?.toInt() ?? 0;
      final idB = (b['id'] as num?)?.toInt() ?? 0;
      return idA.compareTo(idB);
    });
    return list;
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Apertura (16) / Cierre (17) de caja — excluidos de la auditoría por ahora.
  bool _isAperturaOCierreCaja(Map<String, dynamic> m) {
    final tipoId = _asInt(m['tipo_operacion_id']);
    if (tipoId == 16 || tipoId == 17) return true;

    final tipoOp = (m['tipo_operacion'] as String?)?.toLowerCase() ?? '';
    if (tipoOp.contains('apertura') || tipoOp.contains('cierre')) {
      return true;
    }
    return false;
  }

  bool _looksLikeTransfer(Map<String, dynamic> m) {
    final motivo = (m['motivo'] as String?)?.toLowerCase() ?? '';
    if (motivo.contains('transfer')) return true;
    final obs = (m['observaciones'] as String?)?.toLowerCase() ?? '';
    if (obs.contains('transfer')) return true;
    final obsExt =
        (m['observaciones_extraccion'] as String?)?.toLowerCase() ?? '';
    if (obsExt.contains('transfer')) return true;
    final tipoOp = (m['tipo_operacion'] as String?)?.toLowerCase() ?? '';
    return tipoOp.contains('transfer');
  }

  String _fmtAuditMov(Map<String, dynamic> mov) {
    final op = mov['id_operacion']?.toString() ?? '-';
    final tipo = mov['tipo_operacion'] as String? ??
        mov['tipo_movimiento'] as String? ??
        '-';
    final alm = mov['almacen'] as String? ??
        mov['almacen_nombre'] as String? ??
        '-';
    String fecha = mov['fecha']?.toString() ?? '';
    try {
      fecha = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(fecha));
    } catch (_) {}
    return '#$op · $tipo · $alm · $fecha';
  }

  /// Audita continuidad de stock + emparejado de transferencias.
  Future<void> _auditMovementsContinuity() async {
    if (_selectedWarehouseId == null) return;

    setState(() => _isAuditing = true);
    try {
      // Sin filtro de almacén: hace falta el otro lado de cada transferencia.
      final allRaw = await ProductMovementsService.getAllProductMovements(
        productId: int.parse(_product.id),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        operationTypeId: _selectedOperationTypeId,
        warehouseId: null,
      );

      final allPrepared = _prepareMovementsForExport(allRaw)
          .where((m) => !_isAperturaOCierreCaja(m))
          .toList();

      final movements = allPrepared.where((m) {
        final wid = _asInt(m['almacen_id'] ?? m['id_almacen']);
        return wid == null || wid == _selectedWarehouseId;
      }).toList();

      if (movements.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay movimientos para auditar con estos filtros'),
          ),
        );
        return;
      }

      // Continuidad de stock por ubicación dentro del almacén.
      final byUbicacion = <String, List<Map<String, dynamic>>>{};
      for (final m in movements) {
        final ubiId = _asInt(m['ubicacion_id'] ?? m['id_ubicacion']);
        final ubiNombre =
            (m['ubicacion'] as String?)?.trim().isNotEmpty == true
                ? m['ubicacion'] as String
                : (m['ubicacion_nombre'] as String?)?.trim().isNotEmpty == true
                    ? m['ubicacion_nombre'] as String
                    : 'Sin ubicación';
        final key = ubiId != null ? 'id:$ubiId|$ubiNombre' : 'name:$ubiNombre';
        byUbicacion.putIfAbsent(key, () => []).add(m);
      }

      const epsilon = 0.0001;
      final mismatches = <_StockContinuityMismatch>[];
      var comparedPairs = 0;

      byUbicacion.forEach((key, list) {
        list.sort((a, b) {
          final fa = DateTime.tryParse('${a['fecha'] ?? ''}') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final fb = DateTime.tryParse('${b['fecha'] ?? ''}') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final byFecha = fa.compareTo(fb);
          if (byFecha != 0) return byFecha;
          return ((_asInt(a['id']) ?? 0).compareTo(_asInt(b['id']) ?? 0));
        });

        final ubiLabel = key.contains('|')
            ? key.substring(key.indexOf('|') + 1)
            : key.replaceFirst('name:', '');

        Map<String, dynamic>? prev;
        double? prevFinal;
        for (final curr in list) {
          final inicial = _asDouble(curr['cantidad_inicial']);
          final finalQty = _asDouble(curr['cantidad_final']);

          if (prev != null && prevFinal != null && inicial != null) {
            comparedPairs++;
            final diff = inicial - prevFinal;
            if (diff.abs() > epsilon) {
              mismatches.add(
                _StockContinuityMismatch(
                  ubicacion: ubiLabel,
                  anterior: prev,
                  actual: curr,
                  cantidadFinalAnterior: prevFinal,
                  cantidadInicialActual: inicial,
                  diferencia: diff,
                ),
              );
            }
          }

          if (finalQty != null) {
            prev = curr;
            prevFinal = finalQty;
          } else if (inicial != null) {
            final cant = _asDouble(curr['cantidad']) ?? 0;
            final tipo = curr['tipo_movimiento'] as String? ?? '';
            double estimado = inicial;
            if (tipo == 'Recepción' ||
                ((tipo == 'Reajuste' || tipo == 'Ajuste') && cant > 0)) {
              estimado = inicial + cant.abs();
            } else if (tipo == 'Extracción' ||
                ((tipo == 'Reajuste' || tipo == 'Ajuste') && cant < 0)) {
              estimado = inicial - cant.abs();
            }
            prev = curr;
            prevFinal = estimado;
          }
        }
      });

      final transferResult = await _auditTransfers(
        warehouseId: _selectedWarehouseId!,
        warehouseMovements: movements,
        allMovements: allPrepared,
      );

      final carnivalResult = await _auditCarnivalOrders(
        productId: int.parse(_product.id),
        warehouseId: _selectedWarehouseId!,
        warehouseMovements: movements,
      );

      if (!mounted) return;
      await _showAuditReport(
        totalMovimientos: movements.length,
        comparedPairs: comparedPairs,
        mismatches: mismatches,
        transferPairsChecked: transferResult.pairsChecked,
        transferIssues: transferResult.issues,
        carnivalOrdersChecked: carnivalResult.ordersChecked,
        carnivalIssues: carnivalResult.issues,
        carnivalSkippedReason: carnivalResult.skippedReason,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al auditar movimientos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAuditing = false);
    }
  }

  Future<({int pairsChecked, List<_TransferAuditIssue> issues})>
      _auditTransfers({
    required int warehouseId,
    required List<Map<String, dynamic>> warehouseMovements,
    required List<Map<String, dynamic>> allMovements,
  }) async {
    const epsilon = 0.0001;
    final issues = <_TransferAuditIssue>[];

    final byOp = <int, List<Map<String, dynamic>>>{};
    for (final m in allMovements) {
      final opId = _asInt(m['id_operacion']);
      if (opId == null) continue;
      byOp.putIfAbsent(opId, () => []).add(m);
    }

    final warehouseOpIds = <int>{};
    for (final m in warehouseMovements) {
      final opId = _asInt(m['id_operacion']);
      if (opId != null) warehouseOpIds.add(opId);
    }

    if (warehouseOpIds.isEmpty) {
      return (pairsChecked: 0, issues: issues);
    }

    // Vínculos oficiales extracción ↔ recepción.
    final opList = warehouseOpIds.toList();
    final linksByKey = <String, Map<String, dynamic>>{};
    Future<void> fetchLinks(String column) async {
      for (var i = 0; i < opList.length; i += 80) {
        final chunk = opList.sublist(
          i,
          i + 80 > opList.length ? opList.length : i + 80,
        );
        final rows = await _supabase
            .from('app_dat_operacion_transferencia')
            .select('id_operacion, id_extraccion, id_recepcion')
            .inFilter(column, chunk);
        for (final raw in rows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final ext = _asInt(row['id_extraccion']);
          final rec = _asInt(row['id_recepcion']);
          if (ext == null || rec == null) continue;
          linksByKey['$ext->$rec'] = row;
        }
      }
    }

    await fetchLinks('id_extraccion');
    await fetchLinks('id_recepcion');

    final linkedExt = <int>{};
    final linkedRec = <int>{};
    var pairsChecked = 0;

    for (final link in linksByKey.values) {
      final idExt = _asInt(link['id_extraccion'])!;
      final idRec = _asInt(link['id_recepcion'])!;
      linkedExt.add(idExt);
      linkedRec.add(idRec);

      final touchesWarehouse =
          warehouseOpIds.contains(idExt) || warehouseOpIds.contains(idRec);
      if (!touchesWarehouse) continue;

      pairsChecked++;
      final salidas = byOp[idExt] ?? const <Map<String, dynamic>>[];
      final llegadas = byOp[idRec] ?? const <Map<String, dynamic>>[];

      final qtyOut = salidas.fold<double>(
        0,
        (s, m) => s + (_asDouble(m['cantidad'])?.abs() ?? 0),
      );
      final qtyIn = llegadas.fold<double>(
        0,
        (s, m) => s + (_asDouble(m['cantidad'])?.abs() ?? 0),
      );

      final almOut = salidas.isNotEmpty
          ? (salidas.first['almacen'] as String? ??
              salidas.first['almacen_nombre'] as String? ??
              'Origen')
          : 'Origen #$idExt';
      final almIn = llegadas.isNotEmpty
          ? (llegadas.first['almacen'] as String? ??
              llegadas.first['almacen_nombre'] as String? ??
              'Destino')
          : 'Destino #$idRec';

      if (salidas.isEmpty && llegadas.isEmpty) {
        issues.add(
          _TransferAuditIssue(
            kind: _TransferIssueKind.missingBoth,
            title: 'Transferencia sin movimientos del producto',
            detail:
                'Vínculo #$idExt → #$idRec sin filas de este producto en extracción ni recepción.',
            idExtraccion: idExt,
            idRecepcion: idRec,
            cantidadSalida: 0,
            cantidadLlegada: 0,
          ),
        );
        continue;
      }

      if (salidas.isEmpty) {
        issues.add(
          _TransferAuditIssue(
            kind: _TransferIssueKind.missingSalida,
            title: 'Falta la salida de la transferencia',
            detail:
                'Hay llegada en $almIn (op #$idRec, qty ${qtyIn.toStringAsFixed(2)}) '
                'pero no hay extracción emparejada #$idExt en el rango.',
            idExtraccion: idExt,
            idRecepcion: idRec,
            cantidadSalida: 0,
            cantidadLlegada: qtyIn,
            llegada: llegadas.isNotEmpty ? llegadas.first : null,
          ),
        );
      } else if (llegadas.isEmpty) {
        issues.add(
          _TransferAuditIssue(
            kind: _TransferIssueKind.missingLlegada,
            title: 'Falta la llegada de la transferencia',
            detail:
                'Hay salida desde $almOut (op #$idExt, qty ${qtyOut.toStringAsFixed(2)}) '
                'pero no hay recepción emparejada #$idRec en el rango.',
            idExtraccion: idExt,
            idRecepcion: idRec,
            cantidadSalida: qtyOut,
            cantidadLlegada: 0,
            salida: salidas.first,
          ),
        );
      }

      if (salidas.length > 1) {
        issues.add(
          _TransferAuditIssue(
            kind: _TransferIssueKind.duplicateSalida,
            title: 'Salida duplicada (resta de más)',
            detail:
                'La extracción #$idExt tiene ${salidas.length} movimientos de este '
                'producto (qty total ${qtyOut.toStringAsFixed(2)}) en $almOut.',
            idExtraccion: idExt,
            idRecepcion: idRec,
            cantidadSalida: qtyOut,
            cantidadLlegada: qtyIn,
            salida: salidas.first,
            llegada: llegadas.isNotEmpty ? llegadas.first : null,
          ),
        );
      }

      if (llegadas.length > 1) {
        issues.add(
          _TransferAuditIssue(
            kind: _TransferIssueKind.duplicateLlegada,
            title: 'Llegada duplicada (suma de más)',
            detail:
                'La recepción #$idRec tiene ${llegadas.length} movimientos de este '
                'producto (qty total ${qtyIn.toStringAsFixed(2)}) en $almIn. '
                'Eso puede haber inflado el stock.',
            idExtraccion: idExt,
            idRecepcion: idRec,
            cantidadSalida: qtyOut,
            cantidadLlegada: qtyIn,
            salida: salidas.isNotEmpty ? salidas.first : null,
            llegada: llegadas.first,
          ),
        );
      }

      if (salidas.isNotEmpty &&
          llegadas.isNotEmpty &&
          (qtyOut - qtyIn).abs() > epsilon) {
        issues.add(
          _TransferAuditIssue(
            kind: _TransferIssueKind.qtyMismatch,
            title: 'Cantidad salida ≠ llegada',
            detail:
                'Salió ${qtyOut.toStringAsFixed(2)} desde $almOut (op #$idExt) '
                'y llegó ${qtyIn.toStringAsFixed(2)} a $almIn (op #$idRec). '
                'Diferencia: ${(qtyIn - qtyOut).toStringAsFixed(2)}.',
            idExtraccion: idExt,
            idRecepcion: idRec,
            cantidadSalida: qtyOut,
            cantidadLlegada: qtyIn,
            salida: salidas.first,
            llegada: llegadas.first,
          ),
        );
      }
    }

    // Movimientos con aspecto de transferencia en el almacén sin vínculo oficial.
    for (final m in warehouseMovements) {
      if (!_looksLikeTransfer(m)) continue;
      final opId = _asInt(m['id_operacion']);
      if (opId == null) continue;
      final tipo = m['tipo_movimiento'] as String? ?? '';
      if (tipo == 'Extracción' && linkedExt.contains(opId)) continue;
      if (tipo == 'Recepción' && linkedRec.contains(opId)) continue;
      if (tipo != 'Extracción' && tipo != 'Recepción') continue;

      issues.add(
        _TransferAuditIssue(
          kind: _TransferIssueKind.unlinked,
          title: 'Transferencia sin vínculo oficial',
          detail:
              '${_fmtAuditMov(m)} parece transferencia pero no está en '
              'app_dat_operacion_transferencia (no se puede emparejar salida/llegada).',
          idExtraccion: tipo == 'Extracción' ? opId : null,
          idRecepcion: tipo == 'Recepción' ? opId : null,
          cantidadSalida: tipo == 'Extracción'
              ? (_asDouble(m['cantidad'])?.abs() ?? 0)
              : 0,
          cantidadLlegada: tipo == 'Recepción'
              ? (_asDouble(m['cantidad'])?.abs() ?? 0)
              : 0,
          salida: tipo == 'Extracción' ? m : null,
          llegada: tipo == 'Recepción' ? m : null,
        ),
      );
    }

    return (pairsChecked: pairsChecked, issues: issues);
  }

  Future<
      ({
        int ordersChecked,
        List<_CarnivalAuditIssue> issues,
        String? skippedReason,
      })> _auditCarnivalOrders({
    required int productId,
    required int warehouseId,
    required List<Map<String, dynamic>> warehouseMovements,
  }) async {
    const epsilon = 0.0001;
    final issues = <_CarnivalAuditIssue>[];

    // Resolver producto Carnaval + ubicación de venta.
    final prodRow = await _supabase
        .from('app_dat_producto')
        .select('id, id_vendedor_app')
        .eq('id', productId)
        .maybeSingle();
    final relation = await _supabase
        .from('relation_products_carnaval')
        .select('id_producto_carnaval, id_ubicacion')
        .eq('id_producto', productId)
        .maybeSingle();

    final carnavalProductId = _asInt(prodRow?['id_vendedor_app']) ??
        _asInt(relation?['id_producto_carnaval']);
    if (carnavalProductId == null) {
      return (
        ordersChecked: 0,
        issues: issues,
        skippedReason: 'Producto no sincronizado con Carnaval',
      );
    }

    final layoutRows = await _supabase
        .from('app_dat_layout_almacen')
        .select('id')
        .eq('id_almacen', warehouseId);
    final warehouseUbicaciones = <int>{
      for (final r in layoutRows as List)
        if (_asInt((r as Map)['id']) != null) _asInt(r['id'])!,
    };

    // Órdenes Carnaval del producto en el rango de fechas del filtro.
    var detailsQuery = _supabase.schema('carnavalapp').from('OrderDetails').select(
          'id, order_id, quantity, price, completada, '
          'Orders!inner(id, status, created_at)',
        ).eq('product_id', carnavalProductId);

    if (_dateFrom != null) {
      detailsQuery = detailsQuery.gte(
        'Orders.created_at',
        DateFormat('yyyy-MM-dd').format(_dateFrom!),
      );
    }
    if (_dateTo != null) {
      detailsQuery = detailsQuery.lte(
        'Orders.created_at',
        DateFormat('yyyy-MM-dd').format(_dateTo!),
      );
    }

    final detailsRaw = await detailsQuery;
    final details = List<Map<String, dynamic>>.from(detailsRaw as List);

    final carnavalByOrder = <int, _CarnivalOrderAgg>{};
    for (final d in details) {
      final orderId = _asInt(d['order_id']);
      if (orderId == null) continue;
      final orders = d['Orders'];
      final orderMap = orders is Map
          ? Map<String, dynamic>.from(orders)
          : <String, dynamic>{};
      final status = orderMap['status'] as String? ?? '';
      final qty = _asDouble(d['quantity']) ?? 0;
      final agg = carnavalByOrder.putIfAbsent(
        orderId,
        () => _CarnivalOrderAgg(orderId: orderId, status: status),
      );
      agg.status = status;
      agg.lineCount++;
      agg.quantity += qty;
      if (status.toLowerCase() == 'cancelado') {
        agg.isCancelled = true;
      }
    }

    final orderIds = carnavalByOrder.keys.toList()..sort();
    final opsByOrder = <int, List<Map<String, dynamic>>>{};
    final allOpIds = <int>[];
    final ventaDesdeOrdenRe =
        RegExp(r'Venta desde orden\s+(\d+)', caseSensitive: false);

    void addOp(int orderId, Map<String, dynamic> op) {
      final opId = _asInt(op['id']);
      if (opId == null) return;
      final list = opsByOrder.putIfAbsent(orderId, () => []);
      if (list.any((o) => _asInt(o['id']) == opId)) return;
      list.add(op);
      allOpIds.add(opId);
    }

    // Criterio de vínculo: observaciones = "Venta desde orden #####"
    if (orderIds.isNotEmpty) {
      final prodTienda = await _supabase
          .from('app_dat_producto')
          .select('id_tienda')
          .eq('id', productId)
          .maybeSingle();
      final idTienda = _asInt(prodTienda?['id_tienda']);

      var opsQuery = _supabase
          .from('app_dat_operaciones')
          .select('id, id_carnaval_order, observaciones, created_at, id_tienda')
          .ilike('observaciones', '%Venta desde orden%');

      if (idTienda != null) {
        opsQuery = opsQuery.eq('id_tienda', idTienda);
      }
      if (_dateFrom != null) {
        opsQuery = opsQuery.gte(
          'created_at',
          DateFormat('yyyy-MM-dd').format(_dateFrom!),
        );
      }
      if (_dateTo != null) {
        final end = DateTime(
          _dateTo!.year,
          _dateTo!.month,
          _dateTo!.day,
          23,
          59,
          59,
        );
        opsQuery = opsQuery.lte('created_at', end.toIso8601String());
      }

      final opsRaw = await opsQuery;
      final orderIdSet = orderIds.toSet();
      for (final raw in opsRaw as List) {
        final op = Map<String, dynamic>.from(raw as Map);
        final obs = (op['observaciones'] as String?) ?? '';
        final match = ventaDesdeOrdenRe.firstMatch(obs);
        if (match == null) continue;
        final oid = int.tryParse(match.group(1)!);
        if (oid == null || !orderIdSet.contains(oid)) continue;
        // Evitar falso positivo: "orden 12" no debe tomar "orden 123".
        final exact = RegExp(
          'Venta desde orden\\s+$oid(?!\\d)',
          caseSensitive: false,
        );
        if (!exact.hasMatch(obs)) continue;
        addOp(oid, op);
      }

      // Refuerzo puntual para órdenes sin match en el lote (p.ej. fechas
      // de operación fuera del filtro de created_at de la venta).
      final stillMissing =
          orderIds.where((id) => !opsByOrder.containsKey(id)).toList();
      for (final oid in stillMissing) {
        final rows = await _supabase
            .from('app_dat_operaciones')
            .select(
              'id, id_carnaval_order, observaciones, created_at, id_tienda',
            )
            .ilike('observaciones', '%Venta desde orden $oid%');
        for (final raw in rows as List) {
          final op = Map<String, dynamic>.from(raw as Map);
          final obs = (op['observaciones'] as String?) ?? '';
          final exact = RegExp(
            'Venta desde orden\\s+$oid(?!\\d)',
            caseSensitive: false,
          );
          if (!exact.hasMatch(obs)) continue;
          if (idTienda != null && _asInt(op['id_tienda']) != idTienda) {
            continue;
          }
          addOp(oid, op);
        }
      }
    }

    // Extracciones Inventtia de este producto (todas + las del almacén).
    final extByOpAll = <int, List<Map<String, dynamic>>>{};
    final extByOpWarehouse = <int, List<Map<String, dynamic>>>{};
    if (allOpIds.isNotEmpty) {
      for (var i = 0; i < allOpIds.length; i += 80) {
        final chunk = allOpIds.sublist(
          i,
          i + 80 > allOpIds.length ? allOpIds.length : i + 80,
        );
        final exts = await _supabase
            .from('app_dat_extraccion_productos')
            .select('id, id_operacion, id_producto, cantidad, id_ubicacion')
            .eq('id_producto', productId)
            .inFilter('id_operacion', chunk);
        for (final raw in exts as List) {
          final e = Map<String, dynamic>.from(raw as Map);
          final opId = _asInt(e['id_operacion']);
          if (opId == null) continue;
          extByOpAll.putIfAbsent(opId, () => []).add(e);
          final ubi = _asInt(e['id_ubicacion']);
          if (ubi == null ||
              warehouseUbicaciones.isEmpty ||
              warehouseUbicaciones.contains(ubi)) {
            extByOpWarehouse.putIfAbsent(opId, () => []).add(e);
          }
        }
      }
    }

    // Movimientos de venta carnaval en el almacén (backup / huérfanos).
    final movOrderIdsFromWarehouse = <int>{};
    final movQtyByOrder = <int, double>{};
    for (final m in warehouseMovements) {
      final obs = (m['observaciones'] as String?) ?? '';
      final match = ventaDesdeOrdenRe.firstMatch(obs);
      if (match == null) continue;
      final oid = int.tryParse(match.group(1)!);
      if (oid == null) continue;
      movOrderIdsFromWarehouse.add(oid);
      movQtyByOrder[oid] =
          (movQtyByOrder[oid] ?? 0) + (_asDouble(m['cantidad'])?.abs() ?? 0);
    }

    var ordersChecked = 0;

    for (final orderId in orderIds) {
      final agg = carnavalByOrder[orderId]!;
      ordersChecked++;
      final carnavalQty = agg.quantity;
      final ops = opsByOrder[orderId] ?? const <Map<String, dynamic>>[];
      final opIdsLabel = ops
          .map((o) => _asInt(o['id']))
          .whereType<int>()
          .join(', ');

      final extAll = <Map<String, dynamic>>[];
      final extWh = <Map<String, dynamic>>[];
      for (final op in ops) {
        final opId = _asInt(op['id']);
        if (opId == null) continue;
        extAll.addAll(extByOpAll[opId] ?? const []);
        extWh.addAll(extByOpWarehouse[opId] ?? const []);
      }

      final inventtiaQtyAll = extAll.fold<double>(
        0,
        (s, e) => s + (_asDouble(e['cantidad'])?.abs() ?? 0),
      );
      final inventtiaQtyWh = extWh.fold<double>(
        0,
        (s, e) => s + (_asDouble(e['cantidad'])?.abs() ?? 0),
      );
      final movQty = movQtyByOrder[orderId] ?? 0;

      // Regla principal: observaciones deben decir "Venta desde orden #####".
      final hasInventtiaOp = ops.isNotEmpty;
      final hasInventtiaSignal =
          hasInventtiaOp || movQty > epsilon || inventtiaQtyAll > epsilon;

      if (agg.isCancelled) {
        if (hasInventtiaSignal) {
          issues.add(
            _CarnivalAuditIssue(
              kind: _CarnivalIssueKind.cancelledWithOp,
              title: 'Orden Carnaval cancelada con operación Inventtia',
              detail:
                  'Orden #$orderId está Cancelado en Carnaval '
                  '(qty ${carnavalQty.toStringAsFixed(2)}) pero existe '
                  'operación con observaciones "Venta desde orden $orderId"'
                  '${opIdsLabel.isNotEmpty ? ' (op #$opIdsLabel)' : ''}.',
              orderId: orderId,
              carnavalQty: carnavalQty,
              inventtiaQty: inventtiaQtyAll > epsilon ? inventtiaQtyAll : movQty,
              orderStatus: agg.status,
            ),
          );
        }
        continue;
      }

      if (!hasInventtiaOp) {
        issues.add(
          _CarnivalAuditIssue(
            kind: _CarnivalIssueKind.missingOperacion,
            title: 'Orden Carnaval sin operación Inventtia',
            detail:
                'Orden #$orderId (${agg.status}) tiene '
                '${carnavalQty.toStringAsFixed(2)} u. en Carnaval y no hay '
                'operación Inventtia cuya observación diga exactamente '
                '"Venta desde orden $orderId".',
            orderId: orderId,
            carnavalQty: carnavalQty,
            inventtiaQty: movQty,
            orderStatus: agg.status,
          ),
        );
        continue;
      }

      // Comparar cantidades (prioriza extracción del almacén filtrado).
      final inventtiaQty =
          inventtiaQtyWh > epsilon ? inventtiaQtyWh : inventtiaQtyAll;
      final compareQty =
          inventtiaQty > epsilon ? inventtiaQty : movQty;

      if (hasInventtiaOp && extAll.isEmpty && movQty <= epsilon) {
        issues.add(
          _CarnivalAuditIssue(
            kind: _CarnivalIssueKind.qtyMismatch,
            title: 'Operación Inventtia sin extracción del producto',
            detail:
                'Orden #$orderId tiene operación Inventtia #$opIdsLabel '
                'pero no hay extracción de este producto '
                '(Carnaval qty ${carnavalQty.toStringAsFixed(2)}).',
            orderId: orderId,
            carnavalQty: carnavalQty,
            inventtiaQty: 0,
            orderStatus: agg.status,
          ),
        );
        continue;
      }

      final extForDup = extWh.isNotEmpty ? extWh : extAll;
      if (extForDup.length > 1) {
        issues.add(
          _CarnivalAuditIssue(
            kind: _CarnivalIssueKind.duplicateExtraccion,
            title: 'Extracciones duplicadas en Inventtia',
            detail:
                'Orden #$orderId (ops #$opIdsLabel) tiene '
                '${extForDup.length} extracciones del producto '
                '(qty total ${compareQty.toStringAsFixed(2)}).',
            orderId: orderId,
            carnavalQty: carnavalQty,
            inventtiaQty: compareQty,
            orderStatus: agg.status,
          ),
        );
      }

      if (compareQty > epsilon &&
          (carnavalQty - compareQty).abs() > epsilon) {
        issues.add(
          _CarnivalAuditIssue(
            kind: _CarnivalIssueKind.qtyMismatch,
            title: 'Cantidad Carnaval ≠ Inventtia',
            detail:
                'Orden #$orderId (${agg.status}'
                '${opIdsLabel.isNotEmpty ? ', op #$opIdsLabel' : ''}): '
                'Carnaval ${carnavalQty.toStringAsFixed(2)} vs Inventtia '
                '${compareQty.toStringAsFixed(2)} '
                '(diff ${(compareQty - carnavalQty).toStringAsFixed(2)}).',
            orderId: orderId,
            carnavalQty: carnavalQty,
            inventtiaQty: compareQty,
            orderStatus: agg.status,
          ),
        );
      }
    }

    // Ventas Inventtia en el almacén sin línea Carnaval del producto en rango.
    for (final oid in movOrderIdsFromWarehouse) {
      if (carnavalByOrder.containsKey(oid)) continue;
      final movQty = movQtyByOrder[oid] ?? 0;
      if (movQty <= epsilon) continue;
      issues.add(
        _CarnivalAuditIssue(
          kind: _CarnivalIssueKind.orphanInventtia,
          title: 'Venta Inventtia sin línea Carnaval en rango',
          detail:
              'Hay movimiento "Venta desde orden $oid" '
              '(qty ${movQty.toStringAsFixed(2)}) en este almacén, pero no '
              'hay OrderDetail del producto en Carnaval con los filtros de fecha.',
          orderId: oid,
          carnavalQty: 0,
          inventtiaQty: movQty,
        ),
      );
    }

    return (
      ordersChecked: ordersChecked,
      issues: issues,
      skippedReason: null,
    );
  }

  Future<void> _showAuditReport({
    required int totalMovimientos,
    required int comparedPairs,
    required List<_StockContinuityMismatch> mismatches,
    required int transferPairsChecked,
    required List<_TransferAuditIssue> transferIssues,
    required int carnivalOrdersChecked,
    required List<_CarnivalAuditIssue> carnivalIssues,
    String? carnivalSkippedReason,
  }) {
    final almacenNombre = _selectedWarehouse == 'Todos'
        ? 'Todos'
        : _warehouses
            .firstWhere(
              (w) => w['id'].toString() == _selectedWarehouse,
              orElse: () => {'denominacion': _selectedWarehouse},
            )['denominacion']
            ?.toString() ??
            _selectedWarehouse;

    final issueCount =
        mismatches.length + transferIssues.length + carnivalIssues.length;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final ok = issueCount == 0;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: ok ? 0.52 : 0.85,
          minChildSize: 0.35,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(
                        ok
                            ? Icons.verified_outlined
                            : Icons.warning_amber_rounded,
                        color: ok ? Colors.green : Colors.orange.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ok
                              ? 'Auditoría OK'
                              : 'Inconsistencias encontradas ($issueCount)',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Producto: ${_product.denominacion}\n'
                      'Almacén: $almacenNombre\n'
                      'Stock: $totalMovimientos mov. · $comparedPairs pares · '
                      '${mismatches.length} roturas\n'
                      'Transferencias: $transferPairsChecked emparejadas · '
                      '${transferIssues.length} problemas\n'
                      'Carnaval: $carnivalOrdersChecked órdenes · '
                      '${carnivalIssues.length} problemas'
                      '${carnivalSkippedReason != null ? '\n($carnivalSkippedReason)' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: ok
                      ? ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(24),
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 56, color: Colors.green.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'Continuidad de stock, transferencias y '
                              'órdenes Carnaval vs Inventtia cuadran '
                              'con los filtros actuales.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          children: [
                            if (mismatches.isNotEmpty) ...[
                              _buildAuditSectionHeader(
                                'Continuidad de stock',
                                mismatches.length,
                              ),
                              ...mismatches.map(_buildMismatchCard),
                              const SizedBox(height: 12),
                            ],
                            if (transferIssues.isNotEmpty) ...[
                              _buildAuditSectionHeader(
                                'Transferencias',
                                transferIssues.length,
                              ),
                              ...transferIssues.map(_buildTransferIssueCard),
                              const SizedBox(height: 12),
                            ],
                            if (carnivalIssues.isNotEmpty) ...[
                              _buildAuditSectionHeader(
                                'Carnaval vs Inventtia',
                                carnivalIssues.length,
                              ),
                              ...carnivalIssues.map(_buildCarnivalIssueCard),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAuditSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Text(
        '$title ($count)',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildMismatchCard(_StockContinuityMismatch m) {
    final diffAbs = m.diferencia.abs();
    final signo = m.diferencia > 0 ? '+' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.orange.shade200),
        ),
        color: Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.link_off, size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Ubicación: ${m.ubicacion}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Anterior (final ${m.cantidadFinalAnterior.toStringAsFixed(2)})',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Text(_fmtAuditMov(m.anterior), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                'Actual (inicial ${m.cantidadInicialActual.toStringAsFixed(2)})',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Text(_fmtAuditMov(m.actual), style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'Diferencia: $signo${m.diferencia.toStringAsFixed(2)} '
                  '(desfase de ${diffAbs.toStringAsFixed(2)})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransferIssueCard(_TransferAuditIssue issue) {
    final color = issue.kind == _TransferIssueKind.duplicateLlegada ||
            issue.kind == _TransferIssueKind.duplicateSalida
        ? Colors.purple
        : Colors.indigo;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.shade200),
        ),
        color: color.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.swap_horiz, size: 18, color: color.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      issue.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(issue.detail, style: const TextStyle(fontSize: 12)),
              if (issue.salida != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Salida: ${_fmtAuditMov(issue.salida!)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
              if (issue.llegada != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Llegada: ${_fmtAuditMov(issue.llegada!)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Qty salida ${issue.cantidadSalida.toStringAsFixed(2)} → '
                'llegada ${issue.cantidadLlegada.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCarnivalIssueCard(_CarnivalAuditIssue issue) {
    final color = issue.kind == _CarnivalIssueKind.cancelledWithOp
        ? Colors.red
        : Colors.teal;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.shade200),
        ),
        color: color.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storefront_outlined,
                      size: 18, color: color.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      issue.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(issue.detail, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Text(
                'Orden #${issue.orderId}'
                '${issue.orderStatus != null ? ' · ${issue.orderStatus}' : ''} · '
                'Carnaval ${issue.carnavalQty.toStringAsFixed(2)} → '
                'Inventtia ${issue.inventtiaQty.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color.shade800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportMovementsPdf() async {
    setState(() => _isExportingPdf = true);
    try {
      // Traer todas las operaciones del filtro (no solo la página en memoria).
      final allMovements =
          await ProductMovementsService.getAllProductMovements(
        productId: int.parse(_product.id),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        operationTypeId: _selectedOperationTypeId,
        warehouseId: _selectedWarehouseId,
      );
      final movimientosExport = _prepareMovementsForExport(allMovements);

      if (movimientosExport.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay movimientos para exportar con los filtros actuales'),
            ),
          );
        }
        return;
      }

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

      // Totales calculados sobre los datos a exportar
      // Reajuste y Ajuste con cantidad positiva son entradas, con negativa son salidas
      final totalRecepciones = movimientosExport
          .where((m) {
            final tipo = m['tipo_movimiento'] as String? ?? '';
            final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
            return tipo == 'Recepción' ||
                ((tipo == 'Reajuste' || tipo == 'Ajuste') && cant > 0);
          })
          .fold<double>(
            0,
            (s, m) => s + ((m['cantidad'] as num?)?.toDouble().abs() ?? 0),
          );
      final totalExtracciones = movimientosExport
          .where((m) {
            final tipo = m['tipo_movimiento'] as String? ?? '';
            final cant = (m['cantidad'] as num?)?.toDouble() ?? 0;
            return tipo == 'Extracción' ||
                ((tipo == 'Reajuste' || tipo == 'Ajuste') && cant < 0);
          })
          .fold<double>(
            0,
            (s, m) => s + ((m['cantidad'] as num?)?.toDouble().abs() ?? 0),
          );

      // Anchos de columna: Fecha, Almacén, N° Op., Tipo Mov., Tipo Op., Estado, Entrada, Salida, Saldo, Observaciones
      final colWidths = {
        0: const pw.FixedColumnWidth(58),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FixedColumnWidth(36),
        3: const pw.FixedColumnWidth(48),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FixedColumnWidth(54),
        6: const pw.FixedColumnWidth(44),
        7: const pw.FixedColumnWidth(44),
        8: const pw.FixedColumnWidth(44),
        9: const pw.FlexColumnWidth(1.5),
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
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _product.denominacion,
                      style: pw.TextStyle(font: boldFont, fontSize: 11),
                    ),
                    if (_product.sku.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: pw.Text(
                          'SKU: ${_product.sku}',
                          style: pw.TextStyle(
                            font: regularFont,
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Período: $periodoStr',
                                style: pw.TextStyle(
                                    font: regularFont, fontSize: 8),
                              ),
                              pw.Text(
                                'Almacén: $almacenStr',
                                style: pw.TextStyle(
                                    font: regularFont, fontSize: 8),
                              ),
                              pw.Text(
                                'Tipo movimiento: $tipoMovStr',
                                style: pw.TextStyle(
                                    font: regularFont, fontSize: 8),
                              ),
                              pw.Text(
                                'Tipo operación: $tipoOpStr',
                                style: pw.TextStyle(
                                    font: regularFont, fontSize: 8),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Total registros: ${movimientosExport.length}',
                              style:
                                  pw.TextStyle(font: regularFont, fontSize: 8),
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
                'Inventtia - Reporte generado el ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
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
                    headerCell('Tipo Mov.'),
                    headerCell('Tipo Operación'),
                    headerCell('Estado'),
                    headerCell('Entrada'),
                    headerCell('Salida'),
                    headerCell('Saldo'),
                    headerCell('Observaciones'),
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
                  final tipoOpVal = m['tipo_operacion'] as String? ?? '-';
                  final estadoVal = m['estado_operacion_nombre'] as String? ?? 'Completada';
                  final cantFinal = (m['cantidad_final'] as num?)?.toStringAsFixed(2) ?? '-';
                  final observaciones = (m['observaciones'] as String?)?.trim() ?? '';
                  final fechaStr = m['fecha'] as String? ?? '';
                  String fechaFmt = '-';
                  try {
                    fechaFmt = DateFormat('dd/MM/yy\nHH:mm').format(DateTime.parse(fechaStr));
                  } catch (_) {}

                  final cantidadNum = (m['cantidad'] as num?)?.toDouble() ?? 0;
                  final isReajuste = tipoMov == 'Reajuste' || tipoMov == 'Ajuste';
                  final isEntrada = tipoMov == 'Recepción' || (isReajuste && cantidadNum > 0);
                  final isControl = tipoMov == 'Control';

                  PdfColor tipoColor = PdfColors.black;
                  if (tipoMov == 'Recepción') tipoColor = PdfColors.green800;
                  if (tipoMov == 'Extracción') tipoColor = PdfColors.orange800;
                  if (isControl) tipoColor = PdfColors.blue800;
                  if (tipoMov == 'Reajuste') tipoColor = cantidadNum > 0 ? PdfColors.green700 : PdfColors.red700;
                  if (tipoMov == 'Ajuste') tipoColor = cantidadNum > 0 ? PdfColors.teal : PdfColors.deepOrange800;

                  PdfColor estadoColor = PdfColors.grey700;
                  PdfColor estadoBgPdf = PdfColors.grey100;
                  switch (estadoVal.toLowerCase()) {
                    case 'completada':
                      estadoColor = PdfColors.green800;
                      estadoBgPdf = PdfColors.green50;
                      break;
                    case 'pendiente':
                      estadoColor = PdfColors.orange800;
                      estadoBgPdf = PdfColors.orange50;
                      break;
                    case 'devuelta':
                      estadoColor = PdfColors.blue800;
                      estadoBgPdf = PdfColors.lightBlue50;
                      break;
                    case 'cancelada':
                      estadoColor = PdfColors.red800;
                      estadoBgPdf = PdfColors.red50;
                      break;
                  }

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
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: pw.Text(
                          tipoOpVal,
                          style: pw.TextStyle(font: regularFont, fontSize: 7, color: PdfColors.grey800),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                        child: pw.Center(
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                            decoration: pw.BoxDecoration(
                              color: estadoBgPdf,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                            ),
                            child: pw.Text(
                              estadoVal,
                              style: pw.TextStyle(font: boldFont, fontSize: 6, color: estadoColor),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      dataCell(
                        isEntrada ? cantidadNum.abs().toStringAsFixed(2) : '',
                        bold: true,
                        color: isEntrada ? PdfColors.green800 : PdfColors.white,
                      ),
                      dataCell(
                        !isEntrada ? cantidadNum.abs().toStringAsFixed(2) : '',
                        bold: true,
                        color: !isEntrada
                            ? (isControl ? PdfColors.blue800 : (isReajuste ? PdfColors.red700 : PdfColors.orange800))
                            : PdfColors.white,
                      ),
                      dataCell(cantFinal, bold: true),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        child: pw.Text(
                          observaciones,
                          style: pw.TextStyle(font: regularFont, fontSize: 7, color: PdfColors.grey800),
                        ),
                      ),
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
                  _selectedWarehouse = value ?? 'Todos';
                  if (value == null || value == 'Todos') {
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
          Expanded(flex: 18, child: _headerCell('Fecha')),
          Expanded(flex: 20, child: _headerCell('Almacén')),
          Expanded(flex: 12, child: _headerCell('N° Op.')),
          Expanded(flex: 20, child: _headerCell('Tipo Op.')),
          Expanded(flex: 15, child: _headerCell('Estado')),
          Expanded(flex: 14, child: _headerCell('Entrada', right: true)),
          Expanded(flex: 14, child: _headerCell('Salida', right: true)),
          Expanded(flex: 14, child: _headerCell('Saldo', right: true)),
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
    final cantFinal =
        (movement['cantidad_final'] as num?)?.toStringAsFixed(2) ?? '-';

    final cantidadNum = (movement['cantidad'] as num?)?.toDouble() ?? 0;
    final isReajuste = tipoMovimiento == 'Reajuste' || tipoMovimiento == 'Ajuste';
    final isEntrada = tipoMovimiento == 'Recepción' || (isReajuste && cantidadNum > 0);
    final isControl = tipoMovimiento == 'Control';

    final almacen = movement['almacen'] as String? ?? '-';
    final tipoOperacion = movement['tipo_operacion'] as String? ?? '-';
    final estadoNombre = movement['estado_operacion_nombre'] as String? ?? 'Completada';

    Color estadoColor;
    Color estadoBg;
    switch (estadoNombre.toLowerCase()) {
      case 'completada':
        estadoColor = Colors.green.shade700;
        estadoBg = Colors.green.shade50;
        break;
      case 'pendiente':
        estadoColor = Colors.orange.shade700;
        estadoBg = Colors.orange.shade50;
        break;
      case 'devuelta':
        estadoColor = Colors.blue.shade700;
        estadoBg = Colors.blue.shade50;
        break;
      case 'cancelada':
        estadoColor = Colors.red.shade700;
        estadoBg = Colors.red.shade50;
        break;
      default:
        estadoColor = Colors.grey.shade600;
        estadoBg = Colors.grey.shade100;
    }

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
                flex: 18,
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
                flex: 20,
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
                flex: 12,
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
                flex: 20,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 6),
                  child: Text(
                    tipoOperacion,
                    style: TextStyle(
                        fontSize: 9, color: Colors.grey.shade800),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ),
              Expanded(
                flex: 15,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: estadoBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      estadoNombre,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                        color: estadoColor,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 14,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    isEntrada ? cantidadNum.abs().toStringAsFixed(2) : '',
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
                flex: 14,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 8),
                  child: Text(
                    !isEntrada ? cantidadNum.abs().toStringAsFixed(2) : '',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isControl ? Colors.blue : (isReajuste ? Colors.red : Colors.orange),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              Expanded(
                flex: 14,
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
                _buildDetailRow(
                  tipoMovimiento == 'Control'
                      ? 'Cantidad Contada'
                      : 'Cantidad Movida',
                  '${movement['cantidad']}',
                ),
              if (movement['cantidad_inicial'] != null)
                _buildDetailRow(
                    'Cantidad Inicial', '${movement['cantidad_inicial']}'),
              if (movement['cantidad_final'] != null &&
                  tipoMovimiento != 'Control')
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
              if (_hasText(movement['entregado_por']))
                _buildDetailRow(
                    'Entregado por', movement['entregado_por'] as String),
              if (_hasText(movement['recibido_por']))
                _buildDetailRow(
                    'Recibido por', movement['recibido_por'] as String),
              if (_hasText(movement['autorizado_por']))
                _buildDetailRow(
                    'Autorizado por', movement['autorizado_por'] as String),
              if (_hasText(movement['motivo']))
                _buildDetailRow('Motivo', movement['motivo'] as String),
              if (movement['almacen'] != null)
                _buildDetailRow('Almacén', movement['almacen'] as String),
              if (movement['zona'] != null)
                _buildDetailRow('Zona', movement['zona'] as String),
              if (movement['proveedor'] != null)
                _buildDetailRow('Proveedor', movement['proveedor'] as String),
              if (_hasText(movement['observaciones']))
                _buildDetailTextBlock(
                    'Observaciones', movement['observaciones'] as String),
              if (_hasText(movement['observaciones_extraccion']))
                _buildDetailTextBlock(
                    'Observaciones de extracción',
                    movement['observaciones_extraccion'] as String),
              if (_hasText(movement['comentario_completado']))
                _buildDetailTextBlock(
                    'Comentario al completar',
                    movement['comentario_completado'] as String),
            ],
          ),
        ),
      ],
    );
  }

  bool _hasText(dynamic value) {
    if (value == null) return false;
    return value.toString().trim().isNotEmpty;
  }

  Widget _buildDetailTextBlock(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color ?? Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockContinuityMismatch {
  final String ubicacion;
  final Map<String, dynamic> anterior;
  final Map<String, dynamic> actual;
  final double cantidadFinalAnterior;
  final double cantidadInicialActual;
  final double diferencia;

  const _StockContinuityMismatch({
    required this.ubicacion,
    required this.anterior,
    required this.actual,
    required this.cantidadFinalAnterior,
    required this.cantidadInicialActual,
    required this.diferencia,
  });
}

enum _TransferIssueKind {
  qtyMismatch,
  duplicateSalida,
  duplicateLlegada,
  missingSalida,
  missingLlegada,
  missingBoth,
  unlinked,
}

class _TransferAuditIssue {
  final _TransferIssueKind kind;
  final String title;
  final String detail;
  final int? idExtraccion;
  final int? idRecepcion;
  final double cantidadSalida;
  final double cantidadLlegada;
  final Map<String, dynamic>? salida;
  final Map<String, dynamic>? llegada;

  const _TransferAuditIssue({
    required this.kind,
    required this.title,
    required this.detail,
    this.idExtraccion,
    this.idRecepcion,
    required this.cantidadSalida,
    required this.cantidadLlegada,
    this.salida,
    this.llegada,
  });
}

class _CarnivalOrderAgg {
  final int orderId;
  String status;
  double quantity = 0;
  int lineCount = 0;
  bool isCancelled = false;

  _CarnivalOrderAgg({required this.orderId, required this.status});
}

enum _CarnivalIssueKind {
  qtyMismatch,
  missingOperacion,
  duplicateExtraccion,
  cancelledWithOp,
  orphanInventtia,
}

class _CarnivalAuditIssue {
  final _CarnivalIssueKind kind;
  final String title;
  final String detail;
  final int orderId;
  final double carnavalQty;
  final double inventtiaQty;
  final String? orderStatus;

  const _CarnivalAuditIssue({
    required this.kind,
    required this.title,
    required this.detail,
    required this.orderId,
    required this.carnavalQty,
    required this.inventtiaQty,
    this.orderStatus,
  });
}
