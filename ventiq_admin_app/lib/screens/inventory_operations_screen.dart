import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';
import '../services/permissions_service.dart';
import '../services/printer_manager.dart';
import '../services/wifi_printer_service.dart';
import '../services/export_service.dart';

class InventoryOperationsScreen extends StatefulWidget {
  const InventoryOperationsScreen({super.key});

  @override
  State<InventoryOperationsScreen> createState() =>
      _InventoryOperationsScreenState();
}

class _InventoryOperationsScreenState extends State<InventoryOperationsScreen> {
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _operations = [];
  bool _isLoading = true;
  String _searchQuery = '';
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  int? _tipoOperacionId;

  // Pagination
  int _currentPage = 1;
  int _totalCount = 0;
  final int _itemsPerPage = 20;
  bool _hasNextPage = false;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    print('🚀 InventoryOperationsScreen inicializado');
    print('  • ScrollController configurado para detectar paginación');
    print('  • Threshold de carga: 200px del final');
    print('  • Items por página: $_itemsPerPage');

    _loadOperations();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
    _debounceSearch();
  }

  void _onScroll() {
    final currentPixels = _scrollController.position.pixels;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final threshold = 200;
    final distanceFromEnd = maxScrollExtent - currentPixels;

    // Log detallado del scroll
    print('📜 Scroll detectado:');
    print('  • Posición actual: ${currentPixels.toStringAsFixed(1)}px');
    print('  • Máximo scroll: ${maxScrollExtent.toStringAsFixed(1)}px');
    print('  • Distancia del final: ${distanceFromEnd.toStringAsFixed(1)}px');
    print('  • Threshold: ${threshold}px');
    print('  • ¿Debe cargar más?: ${distanceFromEnd <= threshold}');
    print('  • ¿Ya está cargando?: $_isLoadingMore');
    print('  • ¿Hay más páginas?: $_hasNextPage');

    if (currentPixels >= maxScrollExtent - threshold) {
      print('🎯 Condición cumplida - Intentando cargar más datos...');
      _loadMoreOperations();
    } else {
      print('⏳ Aún no llega al threshold para cargar más datos');
    }
  }

  Timer? _debounceTimer;
  void _debounceSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _currentPage = 1;
      _loadOperations();
    });
  }

  Future<void> _loadOperations({bool isLoadMore = false}) async {
    try {
      if (!isLoadMore) {
        setState(() => _isLoading = true);
      }

      final result = await InventoryService.getInventoryOperations(
        busqueda: _searchQuery.isEmpty ? null : _searchQuery,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
        tipoOperacionId: _tipoOperacionId,
        limite: _itemsPerPage,
        pagina: _currentPage,
      );

      final newOperations = result['operations'] ?? [];
      final newTotalCount = result['total_count'] ?? 0;

      print('📊 Resultado de _loadOperations:');
      print('  • isLoadMore: $isLoadMore');
      print('  • Nuevas operaciones recibidas: ${newOperations.length}');
      print('  • Total count del servidor: $newTotalCount');
      print('  • Página actual: $_currentPage');

      setState(() {
        if (isLoadMore) {
          // Agregar nuevos datos a la lista existente
          final oldLength = _operations.length;
          _operations.addAll(newOperations);
          print('  • Operaciones agregadas: ${newOperations.length}');
          print(
            '  • Total antes: $oldLength, Total después: ${_operations.length}',
          );
        } else {
          // Reemplazar toda la lista (primera carga o búsqueda nueva)
          _operations = newOperations;
          print(
            '  • Lista reemplazada con ${newOperations.length} operaciones',
          );
        }
        _totalCount = newTotalCount;
        // Hay más páginas si el total de operaciones mostradas es menor que el total disponible
        _hasNextPage = _operations.length < _totalCount;
        _isLoading = false;
        _isLoadingMore = false;

        print('  • _hasNextPage calculado: $_hasNextPage');
        print(
          '  • Cálculo: ${_operations.length} < $_totalCount = $_hasNextPage',
        );
        print('  • Operaciones cargadas hasta ahora: ${_operations.length}');
        print('  • Total disponible en servidor: $_totalCount');
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar operaciones: $e')),
        );
      }
    }
  }

  /// Método para cargar más operaciones (paginación)
  Future<void> _loadMoreOperations() async {
    print('🔄 _loadMoreOperations llamado');
    print('  • _isLoadingMore: $_isLoadingMore');
    print('  • _hasNextPage: $_hasNextPage');
    print('  • _currentPage: $_currentPage');
    print('  • Total operaciones actuales: ${_operations.length}');
    print('  • _totalCount: $_totalCount');

    // Verificar si ya está cargando más datos o si no hay más páginas
    if (_isLoadingMore || !_hasNextPage) {
      if (_isLoadingMore) {
        print('❌ Ya está cargando más datos, cancelando...');
      }
      if (!_hasNextPage) {
        print('❌ No hay más páginas disponibles, cancelando...');
      }
      return;
    }

    print(
      '📄 ✅ Condiciones cumplidas - Cargando página ${_currentPage + 1}...',
    );
    setState(() => _isLoadingMore = true);

    _currentPage++;
    await _loadOperations(isLoadMore: true);

    print('✅ Página ${_currentPage} cargada exitosamente');
    print('  • Total operaciones después de cargar: ${_operations.length}');
    print('  • ¿Aún hay más páginas?: $_hasNextPage');
  }

  /// Método para el pull-to-refresh
  Future<void> _refreshOperations() async {
    print('🔄 Pull-to-refresh activado - Recargando operaciones...');
    _currentPage = 1; // Reset to first page
    await _loadOperations();
    print('✅ Pull-to-refresh completado');
  }

  Future<void> _showDateRangeDialog() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Seleccionar Rango de Fechas',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Content
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Quick date options
                            const Text(
                              'Opciones rápidas:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Quick date buttons
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildQuickDateButton(
                                  'Hoy',
                                  () => _setQuickDateRange(0),
                                ),
                                _buildQuickDateButton(
                                  'Ayer',
                                  () => _setQuickDateRange(1),
                                ),
                                _buildQuickDateButton(
                                  'Últimos 7 días',
                                  () => _setQuickDateRange(7),
                                ),
                                _buildQuickDateButton(
                                  'Últimos 15 días',
                                  () => _setQuickDateRange(15),
                                ),
                                _buildQuickDateButton(
                                  'Últimos 30 días',
                                  () => _setQuickDateRange(30),
                                ),
                                _buildQuickDateButton(
                                  'Este mes',
                                  () => _setCurrentMonth(),
                                ),
                                _buildQuickDateButton(
                                  'Mes anterior',
                                  () => _setPreviousMonth(),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            // Custom date range selection
                            const Text(
                              'Selección personalizada:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Calendar button
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _showNativeDateRangePicker,
                                icon: const Icon(Icons.calendar_month),
                                label: const Text('Abrir Calendario de Rango'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4A90E2),
                                  side: const BorderSide(
                                    color: Color(0xFF4A90E2),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Current selection display
                            if (_fechaDesde != null && _fechaHasta != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF4A90E2,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF4A90E2,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.date_range,
                                          color: const Color(0xFF4A90E2),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Rango seleccionado:',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${_formatDateLong(_fechaDesde!)} - ${_formatDateLong(_fechaHasta!)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${_fechaHasta!.difference(_fechaDesde!).inDays + 1} día(s)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Action buttons
                            Row(
                              children: [
                                if (_fechaDesde != null ||
                                    _fechaHasta != null) ...[
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _clearDateFilter();
                                      },
                                      icon: const Icon(Icons.clear),
                                      label: const Text('Limpiar'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side: const BorderSide(
                                          color: Colors.red,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        _fechaDesde != null &&
                                                _fechaHasta != null
                                            ? () {
                                              print(
                                                '🔄 Aplicando filtro de fechas: $_fechaDesde - $_fechaHasta',
                                              );
                                              Navigator.pop(context);
                                              _currentPage = 1;
                                              _loadOperations();
                                            }
                                            : null,
                                    icon: const Icon(Icons.check),
                                    label: const Text('Aplicar Filtro'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          _fechaDesde != null &&
                                                  _fechaHasta != null
                                              ? const Color(0xFF4A90E2)
                                              : Colors.grey,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _buildQuickDateButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF4A90E2),
        side: const BorderSide(color: Color(0xFF4A90E2)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  void _setQuickDateRange(int daysAgo) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      if (daysAgo == 0) {
        // Hoy
        _fechaDesde = today;
        _fechaHasta = today;
      } else if (daysAgo == 1) {
        // Ayer
        final yesterday = today.subtract(const Duration(days: 1));
        _fechaDesde = yesterday;
        _fechaHasta = yesterday;
      } else {
        // Últimos X días (incluyendo hoy)
        _fechaDesde = today.subtract(Duration(days: daysAgo - 1));
        _fechaHasta = today;
      }
    });

    // Auto-aplicar el filtro para opciones rápidas
    Navigator.pop(context);
    _currentPage = 1;
    _loadOperations();
  }

  void _setCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _fechaDesde = DateTime(now.year, now.month, 1);
      _fechaHasta = DateTime(now.year, now.month + 1, 0); // Último día del mes
    });

    // Auto-aplicar el filtro
    Navigator.pop(context);
    _currentPage = 1;
    _loadOperations();
  }

  void _setPreviousMonth() {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 1);
    setState(() {
      _fechaDesde = previousMonth;
      _fechaHasta = DateTime(
        previousMonth.year,
        previousMonth.month + 1,
        0,
      ); // Último día del mes anterior
    });

    // Auto-aplicar el filtro
    Navigator.pop(context);
    _currentPage = 1;
    _loadOperations();
  }

  Future<void> _showNativeDateRangePicker() async {
    try {
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange:
            _fechaDesde != null && _fechaHasta != null
                ? DateTimeRange(start: _fechaDesde!, end: _fechaHasta!)
                : null,
        helpText: 'Seleccionar rango de fechas',
        cancelText: 'Cancelar',
        confirmText: 'Confirmar',
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: const Color(0xFF4A90E2),
                onPrimary: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null) {
        print('📅 Rango seleccionado: ${picked.start} - ${picked.end}');

        // Cerrar el modal primero
        Navigator.pop(context);

        // Luego actualizar el estado para que se vea la actualización
        setState(() {
          // Normalizar las fechas para evitar problemas de zona horaria
          _fechaDesde = DateTime(
            picked.start.year,
            picked.start.month,
            picked.start.day,
          );
          _fechaHasta = DateTime(
            picked.end.year,
            picked.end.month,
            picked.end.day,
          );
        });

        print('📅 Fechas guardadas: $_fechaDesde - $_fechaHasta');

        // Mostrar el modal actualizado con las fechas seleccionadas
        await Future.delayed(const Duration(milliseconds: 100));
        _showDateRangeDialog();
      }
    } catch (e) {
      print('❌ Error al abrir selector de fechas: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al abrir el calendario: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _clearDateFilter() {
    setState(() {
      _fechaDesde = null;
      _fechaHasta = null;
    });
    _currentPage = 1;
    _loadOperations();
  }

  void _clearAllFilters() {
    setState(() {
      _fechaDesde = null;
      _fechaHasta = null;
      _tipoOperacionId = null;
    });
    _currentPage = 1;
    _loadOperations();
  }

  Future<void> _showOperationTypeDialog() async {
    // Lista de tipos de operación comunes
    final List<Map<String, dynamic>> tiposOperacion = [
      {'id': null, 'nombre': 'Todos los tipos'},
      {'id': 1, 'nombre': 'Recepción de Productos'},
      {'id': 2, 'nombre': 'Extracción de Productos'},
      {'id': 3, 'nombre': 'Ajuste de Inventario'},
      {'id': 4, 'nombre': 'Venta'},
      {'id': 5, 'nombre': 'Apertura de Caja'},
      {'id': 6, 'nombre': 'Cierre de Caja'},
      {'id': 7, 'nombre': 'Transferencia'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.8,
            minChildSize: 0.4,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Filtrar por Tipo de Operación',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Content
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: tiposOperacion.length,
                          itemBuilder: (context, index) {
                            final tipo = tiposOperacion[index];
                            final isSelected = _tipoOperacionId == tipo['id'];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? const Color(0xFF4A90E2)
                                          : Colors.grey[300]!,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                color:
                                    isSelected
                                        ? const Color(
                                          0xFF4A90E2,
                                        ).withOpacity(0.1)
                                        : Colors.white,
                              ),
                              child: ListTile(
                                title: Text(
                                  tipo['nombre'],
                                  style: TextStyle(
                                    fontWeight:
                                        isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                    color:
                                        isSelected
                                            ? const Color(0xFF4A90E2)
                                            : const Color(0xFF1F2937),
                                  ),
                                ),
                                trailing:
                                    isSelected
                                        ? const Icon(
                                          Icons.check_circle,
                                          color: Color(0xFF4A90E2),
                                        )
                                        : null,
                                onTap: () {
                                  Navigator.pop(context);
                                  setState(() {
                                    _tipoOperacionId = tipo['id'];
                                  });
                                  _currentPage = 1;
                                  _loadOperations();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [_buildFilters(), _buildOperationsList()]),
    );
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
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Search bar
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar operaciones...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Compact date filter icon
          Container(
            decoration: BoxDecoration(
              color:
                  _fechaDesde != null && _fechaHasta != null
                      ? const Color(0xFF4A90E2).withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    _fechaDesde != null && _fechaHasta != null
                        ? const Color(0xFF4A90E2)
                        : Colors.grey.withOpacity(0.3),
              ),
            ),
            child: IconButton(
              onPressed: _showDateRangeDialog,
              icon: Icon(
                Icons.date_range,
                color:
                    _fechaDesde != null && _fechaHasta != null
                        ? const Color(0xFF4A90E2)
                        : Colors.grey[600],
              ),
              tooltip:
                  _fechaDesde != null && _fechaHasta != null
                      ? '${_formatDate(_fechaDesde!)} - ${_formatDate(_fechaHasta!)}'
                      : 'Seleccionar rango de fechas',
            ),
          ),

          // Operation type filter
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color:
                  _tipoOperacionId != null
                      ? const Color(0xFF4A90E2).withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    _tipoOperacionId != null
                        ? const Color(0xFF4A90E2)
                        : Colors.grey.withOpacity(0.3),
              ),
            ),
            child: IconButton(
              onPressed: _showOperationTypeDialog,
              icon: Icon(
                Icons.filter_list,
                color:
                    _tipoOperacionId != null
                        ? const Color(0xFF4A90E2)
                        : Colors.grey[600],
              ),
              tooltip:
                  _tipoOperacionId != null
                      ? 'Filtro de tipo aplicado'
                      : 'Filtrar por tipo de operación',
            ),
          ),

          // Clear filter button
          if (_fechaDesde != null ||
              _fechaHasta != null ||
              _tipoOperacionId != null) ...[
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: IconButton(
                onPressed: _clearAllFilters,
                icon: const Icon(Icons.clear, color: Colors.red),
                tooltip: 'Limpiar todos los filtros',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOperationsList() {
    return Expanded(
      child: RefreshIndicator(
        onRefresh: _refreshOperations,
        color: Theme.of(context).primaryColor,
        backgroundColor: Colors.white,
        displacement: 40.0,
        strokeWidth: 2.5,
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _operations.isEmpty
                ? ListView(
                  // Necesario para que el RefreshIndicator funcione con contenido vacío
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 200), // Espacio para permitir el pull
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text('No se encontraron operaciones'),
                          SizedBox(height: 8),
                          Text(
                            'Desliza hacia abajo para actualizar',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
                : _buildOperationsListContent(),
      ),
    );
  }

  /// Construye el contenido de la lista de operaciones
  /// Usa infinite scroll en ambas plataformas (móvil y web)
  Widget _buildOperationsListContent() {
    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _operations.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _operations.length) {
          // Mostrar indicador de carga al final
          return _buildLoadingMoreIndicator();
        }
        final operation = _operations[index];
        return _buildOperationCard(operation);
      },
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            'Cargando más operaciones...',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationCard(Map<String, dynamic> operation) {
    final tipoOperacion = operation['tipo_operacion_nombre'] ?? 'Desconocido';
    final accion = operation['tipo_operacion_accion']?.toString() ?? '';
    final fecha = DateTime.parse(operation['created_at']);
    final total = _calculateTotalPrice(operation);
    final cantidadItems = _calculateTotalItems(operation);
    final estadoNombre = operation['estado_nombre'] ?? 'Sin estado';
    final observaciones = operation['observaciones'] ?? '';

    // Debug: Log the exact status we're getting from the database
    print(
      '📋 Operation Card - ID: ${operation['id']}, Tipo: "$tipoOperacion", Accion: "$accion", Estado: "$estadoNombre"',
    );

    // Determine operation type icon and color using stable accion field
    IconData operationIcon;
    Color operationColor;

    if (accion == 'transferencia') {
      operationIcon = Icons.swap_horiz;
      operationColor = Colors.purple;
    } else if (accion == 'apertura_caja') {
      operationIcon = Icons.point_of_sale;
      operationColor = Colors.green;
    } else if (accion == 'cierre_caja') {
      operationIcon = Icons.point_of_sale;
      operationColor = Colors.orange;
    } else if (tipoOperacion.toLowerCase() == 'venta') {
      operationIcon = Icons.shopping_cart;
      operationColor = Colors.blue;
    } else if (tipoOperacion.toLowerCase() == 'recepcion') {
      operationIcon = Icons.input;
      operationColor = Colors.green;
    } else if (tipoOperacion.toLowerCase().contains('extrac')) {
      operationIcon = Icons.output;
      operationColor = Colors.orange;
    } else if (tipoOperacion.toLowerCase().contains('ajuste')) {
      operationIcon = Icons.tune;
      operationColor = Colors.teal;
    } else {
      operationIcon = Icons.inventory_2_outlined;
      operationColor = Colors.blueGrey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showOperationDetails(operation),
        borderRadius: BorderRadius.circular(8),
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
                      color: operationColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(operationIcon, color: operationColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tipoOperacion,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'ID: ${operation['id']}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (observaciones.toString().contains(
                    'Venta desde orden',
                  )) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.purple.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_bag,
                            size: 10,
                            color: Colors.purple,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Carnaval App',
                            style: TextStyle(
                              color: Colors.purple,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(estadoNombre).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      estadoNombre,
                      style: TextStyle(
                        color: _getStatusColor(estadoNombre),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fecha: ${_formatDateTime(fecha)}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        if (observaciones.isNotEmpty)
                          Text(
                            observaciones,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (total > 0)
                        Text(
                          '\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      Text(
                        '$cantidadItems items',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    final statusLower = status.toLowerCase().trim();

    // Debug: Print the status to see what we're getting
    print(
      '🎨 Getting color for status: "$status" (normalized: "$statusLower")',
    );

    // Pendiente/En proceso - Amber (más vibrante que orange)
    if (statusLower.contains('pendiente') ||
        statusLower.contains('pending') ||
        statusLower.contains('en proceso') ||
        statusLower.contains('proceso') ||
        statusLower.contains('esperando') ||
        statusLower.contains('waiting')) {
      print('   → Amber (Pendiente)');
      return Colors.amber[700] ?? Colors.amber;
    }

    // Completado/Aprobado - Green más vibrante
    if (statusLower.contains('completada') ||
        statusLower.contains('completed') ||
        statusLower.contains('aprobado') ||
        statusLower.contains('approved') ||
        statusLower.contains('finalizado') ||
        statusLower.contains('terminado') ||
        statusLower.contains('exitoso')) {
      print('   → Green (Completado)');
      return Colors.green[600] ?? Colors.green;
    }

    // Cancelado/Rechazado - Red más vibrante
    if (statusLower.contains('cancelada') ||
        statusLower.contains('cancelled') ||
        statusLower.contains('canceled') ||
        statusLower.contains('rechazado') ||
        statusLower.contains('rejected') ||
        statusLower.contains('anulado') ||
        statusLower.contains('eliminado')) {
      print('   → Red (Cancelado)');
      return Colors.red[600] ?? Colors.red;
    }

    // En revisión/Verificación - Blue más vibrante
    if (statusLower.contains('revision') ||
        statusLower.contains('verificacion') ||
        statusLower.contains('verificación') ||
        statusLower.contains('review') ||
        statusLower.contains('checking')) {
      print('   → Blue (En revisión)');
      return Colors.blue[600] ?? Colors.blue;
    }

    // Error/Fallido - Deep Orange más vibrante
    if (statusLower.contains('error') ||
        statusLower.contains('fallida') ||
        statusLower.contains('failed') ||
        statusLower.contains('fallo')) {
      print('   → Deep Orange (Error)');
      return Colors.deepOrange[600] ?? Colors.deepOrange;
    }

    // Iniciado/Activo - Teal
    if (statusLower.contains('iniciada') ||
        statusLower.contains('activo') ||
        statusLower.contains('active') ||
        statusLower.contains('started')) {
      print('   → Teal (Activo)');
      return Colors.teal[600] ?? Colors.teal;
    }

    // Default - Grey más oscuro para mejor contraste
    print('   → Grey (Default) - Status not recognized');
    return Colors.blueGrey[600] ?? Colors.blueGrey;
  }

  /// Detecta si la operación es una venta
  bool _isVentaOperation(Map<String, dynamic> operation) {
    final tipo =
        (operation['tipo_operacion_nombre'] ?? '').toString().toLowerCase();
    final accion =
        (operation['tipo_operacion_accion'] ?? '').toString().toLowerCase();
    return tipo.contains('venta') || accion.contains('venta');
  }

  /// Obtiene el detalle completo de los pagos de una operación de venta
  Future<List<Map<String, dynamic>>> _getPaymentDetails(int operationId) async {
    try {
      final response = await Supabase.instance.client
          .from('app_dat_pago_venta')
          .select('''
            id,
            monto,
            referencia_pago,
            fecha_pago,
            created_at,
            tipo_pago,
            importe_sin_descuento,
            app_nom_medio_pago:app_nom_medio_pago(id, denominacion, es_digital, es_efectivo)
          ''')
          .eq('id_operacion_venta', operationId)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo detalles de pagos: $e');
      return [];
    }
  }

  /// Verifica si una operación de venta ya tiene pagos registrados
  Future<bool> _checkHasPayment(int operationId) async {
    final payments = await _getPaymentDetails(operationId);
    return payments.isNotEmpty;
  }

  /// Registra un pago con monto 0 para una operación de venta.
  /// Se inserta directamente en app_dat_pago_venta porque fn_registrar_pago_venta
  /// valida que el monto sea mayor que cero.
  Future<bool> _registerZeroPayment(int operationId) async {
    try {
      print('💳 Registrando pago con monto 0 para operación $operationId');

      await Supabase.instance.client.from('app_dat_pago_venta').insert({
        'id_operacion_venta': operationId,
        'id_medio_pago': 1,
        'monto': 0,
        'tipo_pago': 1,
        'referencia_pago': 'Registro manual monto 0 - Admin',
        'creado_por': Supabase.instance.client.auth.currentUser?.id,
      });

      print('✅ Pago con monto 0 registrado directamente');
      return true;
    } catch (e) {
      print('❌ Error registrando pago con monto 0: $e');
      return false;
    }
  }

  void _showOperationDetails(Map<String, dynamic> operation) {
    // Debug: Print all operation data
    print('🔍 Operation details:');
    operation.forEach((key, value) {
      print('   $key: $value');
    });

    // Check if this is a cash register opening operation
    final tipoOperacion =
        operation['tipo_operacion_nombre']?.toString().toLowerCase() ?? '';
    if (tipoOperacion.contains('cierre de caja') ||
        tipoOperacion.contains('cierre')) {
      _showCashRegisterOpeningDialog(operation);
      return;
    }

    // Check if this is an adjustment operation
    final isAdjustment =
        tipoOperacion.contains('ajuste') ||
        tipoOperacion.contains('adjustment');

    if (isAdjustment) {
      _showAdjustmentDetails(operation);
      return;
    }

    // Show regular operation details for other types
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    'Operación #${operation['id']}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  if ((operation['observaciones'] ?? '')
                                      .toString()
                                      .contains('Venta desde orden')) ...[
                                    const SizedBox(width: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.purple.withOpacity(0.3),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.shopping_bag,
                                            size: 12,
                                            color: Colors.purple,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Carnaval App',
                                            style: TextStyle(
                                              color: Colors.purple,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Content
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Información general
                            _buildModalDetailRow(
                              'Tipo:',
                              operation['tipo_operacion_nombre'] ?? 'N/A',
                            ),
                            _buildModalDetailRow(
                              'Estado:',
                              operation['estado_nombre'] ?? 'N/A',
                            ),
                            _buildModalDetailRow(
                              'Fecha:',
                              _formatDateTime(
                                DateTime.parse(operation['created_at']),
                              ),
                            ),
                            // Mostrar almacén para operaciones de recepción y extracción
                            if (tipoOperacion.toLowerCase().contains(
                                  'recepci',
                                ) ||
                                tipoOperacion.toLowerCase().contains(
                                  'extrac',
                                ) ||
                                tipoOperacion.toLowerCase() == 'extracción' ||
                                tipoOperacion.toLowerCase().contains(
                                  'productos',
                                )) ...[
                              FutureBuilder<String>(
                                future:
                                    InventoryService.getWarehouseFromOperation(
                                      operation['id'],
                                      operation['tipo_operacion_nombre'] ?? '',
                                    ),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return _buildModalDetailRow(
                                      'Almacén:',
                                      'Cargando...',
                                    );
                                  }

                                  final almacen = snapshot.data ?? 'N/A';
                                  return _buildModalDetailRow(
                                    'Almacén:',
                                    almacen,
                                  );
                                },
                              ),
                            ],
                            // Mostrar almacenes origen y destino para transferencias
                            if ((operation['tipo_operacion_accion']
                                        ?.toString() ??
                                    '') ==
                                'transferencia') ...[
                              Builder(
                                builder: (context) {
                                  final det =
                                      operation['detalles']
                                          as Map<String, dynamic>?;
                                  final esp =
                                      det?['detalles_especificos']
                                          as Map<String, dynamic>?;
                                  final idExt = esp?['id_extraccion'];
                                  final idRec = esp?['id_recepcion'];
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (idExt != null)
                                        FutureBuilder<String>(
                                          future:
                                              InventoryService.getWarehouseFromOperation(
                                                idExt is int
                                                    ? idExt
                                                    : int.parse(
                                                      idExt.toString(),
                                                    ),
                                                'extraccion',
                                              ),
                                          builder: (context, snap) {
                                            if (snap.connectionState ==
                                                ConnectionState.waiting) {
                                              return _buildModalDetailRow(
                                                'Almacén Origen:',
                                                'Cargando...',
                                              );
                                            }
                                            return _buildModalDetailRow(
                                              'Almacén Origen:',
                                              snap.data ?? 'N/A',
                                            );
                                          },
                                        ),
                                      if (idRec != null)
                                        FutureBuilder<String>(
                                          future:
                                              InventoryService.getWarehouseFromOperation(
                                                idRec is int
                                                    ? idRec
                                                    : int.parse(
                                                      idRec.toString(),
                                                    ),
                                                'recepcion',
                                              ),
                                          builder: (context, snap) {
                                            if (snap.connectionState ==
                                                ConnectionState.waiting) {
                                              return _buildModalDetailRow(
                                                'Almacén Destino:',
                                                'Cargando...',
                                              );
                                            }
                                            return _buildModalDetailRow(
                                              'Almacén Destino:',
                                              snap.data ?? 'N/A',
                                            );
                                          },
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                            _buildModalDetailRow(
                              'Total:',
                              '\$${_calculateTotalPrice(operation).toStringAsFixed(2)}',
                            ),
                            _buildModalDetailRow(
                              'Items:',
                              '${_calculateTotalItems(operation)}',
                            ),
                            ..._buildOperationMetaSection(operation),
                            if (_isVentaOperation(operation) &&
                                operation['id'] != null)
                              _buildOperationPhotoDetail(
                                (operation['id'] as num).toInt(),
                              ),

                            // Show specific details based on operation type
                            if (operation['detalles'] != null) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'Detalles específicos:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildFormattedDetails(operation['detalles']),
                            ],

                            // Show completion button for pending reception operations
                            if (_shouldShowCompleteButton(operation)) ...[
                              const SizedBox(height: 24),
                              _buildCompleteButton(operation),
                            ],

                            // Show cancel button for pending operations
                            if (_shouldShowCancelButton(operation)) ...[
                              const SizedBox(height: 12),
                              _buildCancelButton(operation),
                            ],

                            // Show payment details section for sales
                            if (_isVentaOperation(operation) &&
                                operation['id'] != null) ...[
                              const SizedBox(height: 24),
                              _PaymentDetailsSection(
                                operationId: (operation['id'] as num).toInt(),
                                totalIsZero:
                                    _calculateTotalPrice(operation) == 0,
                                getPaymentDetails: _getPaymentDetails,
                                registerZeroPayment: _registerZeroPayment,
                              ),
                            ],

                            // Show print button for all operations
                            const SizedBox(height: 24),
                            _buildPrintButton(operation),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  /// Show adjustment operation details from app_dat_ajuste_inventario
  void _showAdjustmentDetails(Map<String, dynamic> operation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Ajuste #${operation['id']}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Content
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Información general
                            _buildModalDetailRow(
                              'Tipo:',
                              operation['tipo_operacion_nombre'] ?? 'N/A',
                            ),
                            _buildModalDetailRow(
                              'Estado:',
                              operation['estado_nombre'] ?? 'N/A',
                            ),
                            _buildModalDetailRow(
                              'Fecha:',
                              _formatDateTime(
                                DateTime.parse(operation['created_at']),
                              ),
                            ),
                            ..._buildOperationMetaSection(operation),

                            // Detalles del ajuste
                            const SizedBox(height: 16),
                            const Text(
                              'Detalles del Ajuste:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildAdjustmentDetailsSection(operation),

                            // Show print button for all operations
                            const SizedBox(height: 24),
                            _buildPrintButton(operation),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  /// Renders adjustment details.
  ///
  /// Path 1 (fast): uses pre-fetched `detalles.items` embedded in the listing
  ///   response — contains ALL products of the grouped session, no extra call.
  /// Path 2 (fallback): queries the DB using the list of ALL session op-IDs
  ///   stored in `detalles.detalles_especificos.ids_operaciones`.
  /// Path 3 (legacy): single-operation query for records before the grouping fix.
  Widget _buildAdjustmentDetailsSection(Map<String, dynamic> operation) {
    // ── Helper: safely coerce any Map to Map<String, dynamic> ──────────────
    Map<String, dynamic>? _toStringMap(dynamic raw) {
      if (raw == null) return null;
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
      return null;
    }

    final detalles = _toStringMap(operation['detalles']);

    // Path 1 ─ embedded items (all products, zero extra DB call)
    final rawItems = detalles?['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      return _buildAdjustmentDetailsList(List<dynamic>.from(rawItems));
    }

    // Path 2 ─ use ids_operaciones from det_esp for a multi-op query
    final detEsp = _toStringMap(detalles?['detalles_especificos']);
    final rawIds = detEsp?['ids_operaciones'];
    List<int>? sessionIds;
    if (rawIds is List && rawIds.isNotEmpty) {
      sessionIds =
          rawIds
              .map((e) => (e is int) ? e : int.tryParse(e.toString()))
              .whereType<int>()
              .toList();
    }

    final Future<Map<String, dynamic>> detailFuture =
        (sessionIds != null && sessionIds.isNotEmpty)
            ? InventoryService.getAdjustmentDetailsByIds(sessionIds)
            : InventoryService.getAdjustmentDetails(operation['id'] as int);

    return FutureBuilder<Map<String, dynamic>>(
      future: detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Error al cargar detalles: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        final adjustmentData = snapshot.data;
        final details = adjustmentData?['details'] as List?;
        if (details == null || details.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin detalles de ajuste'),
          );
        }
        return _buildAdjustmentDetailsList(details);
      },
    );
  }

  /// Calcula el total de los ajustes basado en los detalles
  double _calculateAdjustmentTotal(List<dynamic> details) {
    double total = 0.0;
    for (var detail in details) {
      if (detail is Map<String, dynamic>) {
        // Obtener precio unitario si está disponible
        final precioUnitario = detail['precio_unitario'];
        final diferencia = detail['diferencia'] ?? 0;

        if (precioUnitario != null) {
          final precioNum =
              (precioUnitario is double)
                  ? precioUnitario
                  : double.tryParse(precioUnitario.toString()) ?? 0.0;
          final diferenciaNum =
              (diferencia is double)
                  ? diferencia
                  : double.tryParse(diferencia.toString()) ?? 0.0;

          total += (diferenciaNum.abs() * precioNum);
        }
      }
    }
    return total;
  }

  /// Build the list of adjustment details
  Widget _buildAdjustmentDetailsList(List<dynamic> details) {
    // Ordenar detalles alfabéticamente por nombre de producto
    final sortedDetails = List<dynamic>.from(details);
    sortedDetails.sort((a, b) {
      final nameA =
          (a['producto_nombre'] ?? 'Producto').toString().toLowerCase();
      final nameB =
          (b['producto_nombre'] ?? 'Producto').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    // Calcular el total de los ajustes
    final totalAjuste = _calculateAdjustmentTotal(sortedDetails);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mostrar total de ajustes si hay valor
        if (totalAjuste > 0) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total de Ajuste:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  '\$${totalAjuste.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
        ...sortedDetails.map((detail) {
          final cantidadAnterior = detail['cantidad_anterior'] ?? 0;
          final cantidadNueva = detail['cantidad_nueva'] ?? 0;
          final diferencia = detail['diferencia'] ?? 0;
          final productoNombre = detail['producto_nombre'] ?? 'Producto';
          final ubicacion = detail['ubicacion'] ?? 'N/A';
          final almacen = detail['almacen'] ?? 'N/A';

          // Determinar color según si es aumento o disminución
          final isIncrease = (diferencia as num) >= 0;
          final differenceColor = isIncrease ? Colors.green : Colors.red;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre del producto
                Text(
                  productoNombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),

                // Almacén
                Row(
                  children: [
                    const Icon(Icons.warehouse, size: 16, color: Colors.orange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        almacen,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Ubicación
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ubicacion,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Cantidades
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cantidad Anterior:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            cantidadAnterior.toString(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cantidad Nueva:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            cantidadNueva.toString(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Diferencia:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            '${isIncrease ? '+' : ''}$diferencia',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: differenceColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildModalDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationPhotoDetail(int operationId) {
    return FutureBuilder<Map<String, dynamic>?>(
      future:
          Supabase.instance.client
              .from('app_dat_operacion_venta')
              .select('foto_operacion_url')
              .eq('id_operacion', operationId)
              .maybeSingle(),
      builder: (context, snapshot) {
        final url = snapshot.data?['foto_operacion_url'] as String?;
        if (url == null || url.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Foto de la operación',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap:
                    () => showDialog<void>(
                      context: context,
                      builder:
                          (_) => Dialog(
                            child: InteractiveViewer(child: Image.network(url)),
                          ),
                    ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) => const ListTile(
                          leading: Icon(Icons.broken_image_outlined),
                          title: Text(
                            'No se pudo cargar la foto de la operación',
                          ),
                        ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';
  }

  String _formatDateLong(DateTime date) {
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return '${date.day} de ${months[date.month - 1]} ${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getProductName(Map<String, dynamic> item) {
    // Intentar múltiples campos para obtener el nombre del producto
    final possibleNames = [
      item['denominacion'],
      item['nombre_producto'],
      item['producto_nombre'],
      item['producto'],
      item['name'],
      item['nombre'],
      item['descripcion'],
    ];

    for (final name in possibleNames) {
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
    }

    // Si no se encuentra nombre, usar ID del producto si está disponible
    final productId = item['id_producto'] ?? item['producto_id'] ?? item['id'];
    if (productId != null) {
      return 'Producto ID: $productId';
    }

    return 'Producto sin nombre';
  }

  Widget _buildFormattedDetails(dynamic detalles) {
    if (detalles == null) return const Text('Sin detalles específicos');

    if (detalles is Map<String, dynamic>) {
      final especificos = detalles['detalles_especificos'];
      final isTransfer =
          especificos is Map<String, dynamic> &&
          (especificos.containsKey('extraccion') ||
              especificos.containsKey('recepcion'));

      final extItems =
          isTransfer
              ? (especificos['extraccion']?['items'] as List<dynamic>?)
              : null;
      final recItems =
          isTransfer
              ? (especificos['recepcion']?['items'] as List<dynamic>?)
              : null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (especificos != null) ...[
            const Text(
              'Información específica:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            _buildSpecificDetails(especificos),
            const SizedBox(height: 12),
          ],
          if (isTransfer) ...[
            if (extItems != null && extItems.isNotEmpty) ...[
              const Text(
                'Productos Extraídos (Origen):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _buildProductsList(extItems),
              const SizedBox(height: 12),
            ],
            if (recItems != null && recItems.isNotEmpty) ...[
              const Text(
                'Productos Recibidos (Destino):',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _buildProductsList(recItems),
            ],
          ] else if (detalles['items'] != null &&
              detalles['items'] is List) ...[
            const Text(
              'Productos:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildProductsList(detalles['items']),
          ],
        ],
      );
    }

    return Text(detalles.toString());
  }

  Widget _buildSpecificDetails(dynamic especificos) {
    if (especificos == null) return const Text('Sin información específica');

    if (especificos is Map<String, dynamic>) {
      final clienteInfo = especificos['cliente_info'];

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...especificos.entries
                .where((e) {
                  const hiddenKeys = {
                    'cliente_info',
                    'extraccion',
                    'recepcion',
                    'entregado_por',
                    'recibido_por',
                    'autorizado_por',
                    'motivo',
                    'comentario_completado',
                    'observaciones',
                    'origen',
                    'destino',
                    'estado_extraccion',
                    'estado_recepcion',
                    'id_extraccion',
                    'id_recepcion',
                    'ids_operaciones',
                    'tipo_ajuste',
                    'monto_total',
                  };
                  return !hiddenKeys.contains(e.key);
                })
                .map((entry) {
                  String label = _formatFieldLabel(entry.key);
                  String value = _formatFieldValue(entry.value);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            '$label:',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Expanded(child: Text(value)),
                      ],
                    ),
                  );
                })
                .toList(),

            if (clienteInfo != null && clienteInfo is Map<String, dynamic>) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Divider(),
              ),
              const Row(
                children: [
                  Icon(Icons.person, size: 16, color: Color(0xFF4A90E2)),
                  SizedBox(width: 8),
                  Text(
                    'Información del Cliente:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A90E2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildClientInfoTile(clienteInfo),
            ],
          ],
        ),
      );
    }

    return Text(especificos.toString());
  }

  Widget _buildClientInfoTile(Map<String, dynamic> info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoItem(
          'Nombre:',
          info['nombre_completo'] ?? info['nombre'] ?? 'N/A',
        ),
        _buildInfoItem('Código:', info['codigo_cliente'] ?? 'N/A'),
        _buildInfoItem('Teléfono:', info['telefono'] ?? 'N/A'),
        _buildInfoItem('Email:', info['email'] ?? 'N/A'),
        if (info['documento_identidad'] != null)
          _buildInfoItem('Doc. Ident.:', info['documento_identidad']),
      ],
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList(List<dynamic> items) {
    // Ordenar productos alfabéticamente por nombre
    final sortedItems = List<dynamic>.from(items);
    sortedItems.sort((a, b) {
      final nameA = _getProductName(a as Map<String, dynamic>).toLowerCase();
      final nameB = _getProductName(b as Map<String, dynamic>).toLowerCase();
      return nameA.compareTo(nameB);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.inventory_2, color: const Color(0xFF4A90E2), size: 20),
            const SizedBox(width: 8),
            Text(
              'Productos Contados (${items.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children:
                sortedItems.asMap().entries.map((entry) {
                  int index = entry.key;
                  Map<String, dynamic> item = entry.value;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border:
                          index > 0
                              ? Border(
                                top: BorderSide(color: Colors.grey[200]!),
                              )
                              : null,
                    ),
                    child: Row(
                      children: [
                        // Product info
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getProductName(item),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item['variante'] != null ||
                                  item['opcion_variante'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${item['variante'] ?? ''}: ${item['opcion_variante'] ?? ''}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                              if (item['sku_producto'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'SKU: ${item['sku_producto']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                              if (item['precio_unitario'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Precio: \$${_formatFieldValue(item['precio_unitario'])}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Quantity and Subtotal
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4A90E2).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(
                                    0xFF4A90E2,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                'Cant: ${item['cantidad_fisica'] ?? item['cantidad'] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4A90E2),
                                ),
                              ),
                            ),
                            if (item['importe'] != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                '\$${_formatFieldValue(item['importe'])}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  bool _hasDetailText(dynamic value) {
    if (value == null) return false;
    return value.toString().trim().isNotEmpty;
  }

  Map<String, dynamic>? _extractDetallesEspecificos(
    Map<String, dynamic> operation,
  ) {
    final detalles = operation['detalles'];
    if (detalles is Map<String, dynamic>) {
      final esp = detalles['detalles_especificos'];
      if (esp is Map<String, dynamic>) return esp;
      if (esp is Map) return Map<String, dynamic>.from(esp);
    }
    return null;
  }

  List<Widget> _buildOperationMetaSection(Map<String, dynamic> operation) {
    final esp = _extractDetallesEspecificos(operation);
    final rows = <Widget>[];

    void addRow(String label, dynamic value) {
      if (!_hasDetailText(value)) return;
      rows.add(_buildModalDetailRow(label, value.toString()));
    }

    void addTextBlock(String label, dynamic value) {
      if (!_hasDetailText(value)) return;
      rows.add(const SizedBox(height: 4));
      rows.add(
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
      );
      rows.add(const SizedBox(height: 4));
      rows.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            value.toString(),
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          ),
        ),
      );
      rows.add(const SizedBox(height: 8));
    }

    addRow('Operador:', operation['usuario_nombre']);
    addRow('Entregado por:', esp?['entregado_por']);
    addRow('Recibido por:', esp?['recibido_por']);
    addRow('Autorizado por:', esp?['autorizado_por']);
    addRow('Motivo:', esp?['motivo']);
    addRow('Tipo de ajuste:', esp?['tipo_ajuste']);
    addRow('Origen:', esp?['origen']);
    addRow('Destino:', esp?['destino']);
    addRow('Estado extracción:', esp?['estado_extraccion']);
    addRow('Estado recepción:', esp?['estado_recepcion']);

    addTextBlock('Observaciones:', operation['observaciones']);

    final obsDetalle = esp?['observaciones'];
    if (_hasDetailText(obsDetalle) &&
        obsDetalle.toString().trim() !=
            (operation['observaciones']?.toString().trim() ?? '')) {
      addTextBlock('Observaciones adicionales:', obsDetalle);
    }

    addTextBlock('Comentario al completar:', esp?['comentario_completado']);

    if (rows.isEmpty) return [];

    return [
      const Text(
        'Información de la operación',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
      ),
      const SizedBox(height: 8),
      ...rows,
      const SizedBox(height: 8),
    ];
  }

  String _formatFieldLabel(String key) {
    switch (key) {
      case 'id_tpv':
        return 'TPV';
      case 'tpv_nombre':
        return 'Nombre TPV';
      case 'total':
        return 'Total';
      case 'cantidad_items':
        return 'Cantidad Items';
      case 'id_proveedor':
        return 'Proveedor';
      case 'proveedor_nombre':
        return 'Nombre Proveedor';
      case 'motivo':
        return 'Motivo';
      case 'recibido_por':
        return 'Recibido por';
      case 'autorizado_por':
        return 'Autorizado por';
      case 'entregado_por':
        return 'Entregado por';
      case 'comentario_completado':
        return 'Comentario al completar';
      case 'observaciones':
        return 'Observaciones';
      case 'estado_extraccion':
        return 'Estado extracción';
      case 'estado_recepcion':
        return 'Estado recepción';
      case 'origen':
        return 'Origen';
      case 'destino':
        return 'Destino';
      case 'tipo_ajuste':
        return 'Tipo de ajuste';
      case 'id_recepcion':
        return 'ID Recepción';
      case 'id_extraccion':
        return 'ID Extracción';
      default:
        return key.replaceAll('_', ' ').toUpperCase();
    }
  }

  String _formatFieldValue(dynamic value) {
    if (value == null) return 'N/A';
    if (value is double) return value.toStringAsFixed(2);
    if (value is num) return value.toString();
    return value.toString();
  }

  // Helper methods to calculate dynamic totals from products
  int _calculateTotalItems(Map<String, dynamic> operation) {
    try {
      if (operation['detalles'] != null &&
          operation['detalles'] is Map<String, dynamic>) {
        final detalles = operation['detalles'] as Map<String, dynamic>;
        if (detalles['items'] != null && detalles['items'] is List) {
          final items = detalles['items'] as List<dynamic>;
          int totalItems = 0;
          for (var item in items) {
            if (item is Map<String, dynamic>) {
              final cantidad = item['cantidad'];
              if (cantidad != null) {
                final cantidadNum =
                    (cantidad is int)
                        ? cantidad
                        : (cantidad is double)
                        ? cantidad.toInt()
                        : int.tryParse(cantidad.toString()) ?? 0;
                totalItems += cantidadNum;
              }
            }
          }
          return totalItems;
        }
      }
    } catch (e) {
      print('Error calculating total items: $e');
    }
    // Fallback to original value
    return operation['cantidad_items'] ?? 0;
  }

  double _calculateTotalPrice(Map<String, dynamic> operation) {
    try {
      if (operation['detalles'] != null &&
          operation['detalles'] is Map<String, dynamic>) {
        final detalles = operation['detalles'] as Map<String, dynamic>;

        // Para operaciones de ajuste, calcular el total basado en los items
        if (detalles['items'] != null && detalles['items'] is List) {
          final items = detalles['items'] as List<dynamic>;
          double totalPrice = 0.0;

          for (var item in items) {
            if (item is Map<String, dynamic>) {
              // Intentar obtener el importe (precio total del item)
              final importe = item['importe'];
              if (importe != null) {
                final importeNum =
                    (importe is double)
                        ? importe
                        : double.tryParse(importe.toString()) ?? 0.0;
                totalPrice += importeNum;
              } else {
                // Si no hay importe, intentar calcular cantidad * precio_unitario
                final cantidad =
                    item['cantidad'] ?? item['cantidad_fisica'] ?? 0;
                final precioUnitario = item['precio_unitario'] ?? 0;

                final cantidadNum =
                    (cantidad is double)
                        ? cantidad
                        : double.tryParse(cantidad.toString()) ?? 0.0;
                final precioNum =
                    (precioUnitario is double)
                        ? precioUnitario
                        : double.tryParse(precioUnitario.toString()) ?? 0.0;

                totalPrice += (cantidadNum * precioNum);
              }
            }
          }

          if (totalPrice > 0) {
            return totalPrice;
          }
        }

        // Fallback a detalles_especificos si existen
        if (detalles['detalles_especificos'] != null &&
            detalles['detalles_especificos'] is Map<String, dynamic>) {
          final especificos =
              detalles['detalles_especificos'] as Map<String, dynamic>;
          final montoTotal = especificos['monto_total'];
          if (montoTotal != null) {
            return (montoTotal is double)
                ? montoTotal
                : double.tryParse(montoTotal.toString()) ?? 0.0;
          }
        }
      }
    } catch (e) {
      print('Error calculating total price: $e');
    }
    // Fallback to original value
    return operation['total']?.toDouble() ?? 0.0;
  }

  bool _shouldShowCompleteButton(Map<String, dynamic> operation) {
    String tipoOperacion =
        operation['tipo_operacion_nombre']?.toString().toLowerCase() ?? '';
    final accion = operation['tipo_operacion_accion']?.toString() ?? '';
    String estado = operation['estado_nombre']?.toString().toLowerCase() ?? '';

    print(
      '🔍 Checking completion button - ID: ${operation['id']}, accion: "$accion", tipo: "$tipoOperacion"',
    );

    bool isReception = tipoOperacion.contains('recepci');
    bool isExtraction = tipoOperacion.contains('extrac');
    bool isAjuste = tipoOperacion.contains('ajuste');
    bool isTransfer = accion == 'transferencia';

    // Check for different variations of pending status
    bool isPending =
        estado.contains('pendiente') ||
        estado.contains('pending') ||
        estado.contains('en proceso') ||
        estado.contains('proceso');

    print('   - Is reception: $isReception');
    print('   - Is extraction: $isExtraction');
    print('   - Is pending: $isPending');
    print(
      '   - Should show button: ${(isReception || isExtraction) && isPending}',
    );

    return (isReception || isExtraction || isAjuste || isTransfer) && isPending;
  }

  bool _shouldShowCancelButton(Map<String, dynamic> operation) {
    // Show cancel button for pending operations
    // For managers: also show for completed operations
    String estado = operation['estado_nombre']?.toString().toLowerCase() ?? '';

    // Debug logging
    print('🔍 Checking cancel button for operation:');
    print('   - ID: ${operation['id']}');
    print('   - Estado: "$estado"');

    // Check for different variations of pending status
    bool isPending =
        estado.contains('pendiente') ||
        estado.contains('pending') ||
        estado.contains('en proceso') ||
        estado.contains('proceso');

    // Check for completed status
    bool isCompleted =
        estado.contains('completada') ||
        estado.contains('completed') ||
        estado.contains('finalizada') ||
        estado.contains('finalizado');

    print('   - Is pending: $isPending');
    print('   - Is completed: $isCompleted');
    print('   - Should show cancel button: ${isPending || isCompleted}');

    // Allow cancellation for pending operations always
    // For completed operations, only if user is a manager (will be checked in the dialog)
    return isPending || isCompleted;
  }

  Widget _buildCompleteButton(Map<String, dynamic> operation) {
    return Container(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _showCompleteOperationDialog(operation),
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Completar Operación'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCancelButton(Map<String, dynamic> operation) {
    return Container(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showCancelOperationDialog(operation),
        icon: const Icon(Icons.cancel_outlined),
        label: const Text('Cancelar Operación'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  void _showCompleteOperationDialog(Map<String, dynamic> operation) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Completar Operación'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Está seguro de completar la operación #${operation['id']}?',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  decoration: const InputDecoration(
                    labelText: 'Comentario (opcional)',
                    hintText: 'Ingrese un comentario sobre la operación',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed:
                    () => _completeOperation(operation, commentController.text),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Completar'),
              ),
            ],
          ),
    );
  }

  Future<void> _completeOperation(
    Map<String, dynamic> operation,
    String comment,
  ) async {
    try {
      Navigator.pop(context); // Close dialog

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Completando operación...'),
                ],
              ),
            ),
      );

      // Get user UUID from preferences
      final userUuid = await UserPreferencesService().getUserId();
      if (userUuid == null) {
        throw Exception('No se pudo obtener el UUID del usuario');
      }

      // Call the completion RPC
      final operationId = operation['id'];
      if (operationId == null) {
        throw Exception('ID de operación no válido');
      }

      final result = await InventoryService.completeOperation(
        idOperacion:
            operationId is int
                ? operationId
                : int.parse(operationId.toString()),
        comentario:
            comment.isEmpty ? 'Operación completada desde la app' : comment,
        uuid: userUuid,
      );

      Navigator.pop(context); // Close loading dialog

      // La respuesta viene directamente en result
      final response = result;

      if (response['success'] == true || response['status'] == 'success') {
        // Close the detail modal
        await Future.delayed(const Duration(milliseconds: 200));

        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message'] ?? 'Operación completada exitosamente',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Refresh the operations list
        _loadOperations();
      } else {
        await Future.delayed(const Duration(milliseconds: 200));
        Navigator.pop(context);

        // Verificar si es un error de consignación
        final errorCode = response['error'] ?? '';
        final errorType = response['error_type'] ?? '';
        if (errorCode == 'CONSIGNMENT_EXTRACTION_NOT_COMPLETED') {
          // Mostrar diálogo informativo para error de consignación
          _showConsignmentErrorDialog(
            response['message'] ?? 'Error en consignación',
            response['id_operacion_extraccion'],
          );
        } else if (errorType == 'insufficient_stock') {
          // Mostrar diálogo detallado de stock insuficiente
          _showInsufficientStockDialog(
            response['message'] ??
                'Stock insuficiente para completar la operación',
          );
        } else {
          // Mostrar SnackBar para otros errores
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                response['message'] ?? 'Error al completar la operación',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog if still open

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showCancelOperationDialog(Map<String, dynamic> operation) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.cancel_outlined, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                const Text('Cancelar Operación'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Está seguro de cancelar la operación #${operation['id']}?',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Esta acción no se puede deshacer.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: commentController,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de cancelación',
                    hintText:
                        'Ingrese el motivo por el cual cancela la operación',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('No, mantener'),
              ),
              ElevatedButton(
                onPressed:
                    () => _cancelOperation(operation, commentController.text),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Sí, cancelar'),
              ),
            ],
          ),
    );
  }

  Future<void> _cancelOperation(
    Map<String, dynamic> operation,
    String comment,
  ) async {
    try {
      Navigator.pop(context); // Close dialog

      // Check if operation is completed and verify user role
      String estado =
          operation['estado_nombre']?.toString().toLowerCase() ?? '';
      bool isCompleted =
          estado.contains('completada') ||
          estado.contains('completed') ||
          estado.contains('finalizada') ||
          estado.contains('finalizado');

      if (isCompleted) {
        // For completed operations, verify user is a manager
        final userRole = await _getUserRole();
        if (userRole != 'gerente') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Solo los gerentes pueden cancelar operaciones completadas',
              ),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Cancelando operación...'),
                ],
              ),
            ),
      );

      // Get user UUID from preferences
      final userUuid = await UserPreferencesService().getUserId();
      if (userUuid == null) {
        throw Exception('No se pudo obtener el UUID del usuario');
      }

      // Call the cancellation function
      final operationId = operation['id'];
      if (operationId == null) {
        throw Exception('ID de operación no válido');
      }

      // Use the RPC fn_registrar_cambio_estado_operacion with estado 3 (cancelada)
      final supabase = Supabase.instance.client;
      print(
        operationId is int ? operationId : int.parse(operationId.toString()),
      );
      final result = await supabase.rpc(
        'fn_registrar_cambio_estado_operacion_mejorado',
        params: {
          'p_id_operacion':
              operationId is int
                  ? operationId
                  : int.parse(operationId.toString()),
          'p_nuevo_estado': 3, // Estado cancelada
        },
      );

      Navigator.pop(context); // Close loading dialog

      print(result);

      if (result != null && result['success'] == true) {
        // Close the detail modal
        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operación cancelada exitosamente'),
            backgroundColor: Colors.orange,
          ),
        );

        // Refresh the operations list
        _loadOperations();
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result?['message'] ?? 'Error al cancelar la operación',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog if still open

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showCashRegisterOpeningDialog(
    Map<String, dynamic> operation,
  ) async {
    // Check user role for access control
    final userRole = await _getUserRole();
    final hasAccess = _hasAccessToOpeningDetails(userRole);

    if (!hasAccess) {
      _showAccessDeniedDialog();
      return;
    }

    // Debug: Print detailed operation data for cash register opening
    print('🔍 CASH REGISTER OPENING - Full Operation Details:');
    print('================================================');
    operation.forEach((key, value) {
      if (value is Map) {
        print('   $key: {');
        (value as Map).forEach((subKey, subValue) {
          print('      $subKey: $subValue');
        });
        print('   }');
      } else if (value is List) {
        print('   $key: [');
        for (int i = 0; i < (value as List).length; i++) {
          print('      [$i]: ${value[i]}');
        }
        print('   ]');
      } else {
        print('   $key: $value');
      }
    });
    print('================================================');

    // Debug: Print specific detalles structure
    if (operation['detalles'] != null) {
      print('🔍 DETALLES Structure:');
      print('----------------------');
      final detalles = operation['detalles'];
      if (detalles is Map<String, dynamic>) {
        detalles.forEach((key, value) {
          if (key == 'items' && value is List) {
            print('   items: [${value.length} items]');
            for (int i = 0; i < value.length; i++) {
              print('      Item $i: ${value[i]}');
            }
          } else if (key == 'detalles_especificos' && value is Map) {
            print('   detalles_especificos: {');
            (value as Map).forEach((subKey, subValue) {
              print('      $subKey: $subValue');
            });
            print('   }');
          } else {
            print('   $key: $value');
          }
        });
      } else {
        print('   detalles is not a Map: $detalles');
      }
      print('----------------------');
    } else {
      print('🔍 No detalles found in operation');
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
                    color: const Color(0xFF4A90E2).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.point_of_sale,
                    color: Color(0xFF4A90E2),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Detalles de Apertura de Caja',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
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
                  // Operation ID and Status
                  _buildOpeningDetailRow(
                    'ID Operación:',
                    '#${operation['id']}',
                    Icons.tag,
                  ),
                  _buildOpeningDetailRow(
                    'Estado:',
                    operation['estado_nombre'] ?? 'N/A',
                    Icons.info_outline,
                    valueColor: _getStatusColor(
                      operation['estado_nombre'] ?? '',
                    ),
                  ),
                  _buildOpeningDetailRow(
                    'Fecha y Hora:',
                    _formatDateTime(DateTime.parse(operation['created_at'])),
                    Icons.schedule,
                  ),
                  _buildOpeningDetailRow(
                    'Vendedor:',
                    operation['usuario_email'] ?? 'N/A',
                    Icons.person,
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Cash Register Details
                  const Text(
                    'Información de la Apertura',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Extract cash details from operation data
                  if (operation['detalles'] != null) ...[
                    _buildCashRegisterDetails(operation['detalles']),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.grey[600],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'No hay detalles específicos disponibles',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Show product list if available
                  if (operation['detalles'] != null &&
                      operation['detalles']['items'] != null &&
                      operation['detalles']['items'] is List &&
                      (operation['detalles']['items'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildProductsList(operation['detalles']['items']),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  Widget _buildOpeningDetailRow(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? const Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashRegisterDetails(dynamic detalles) {
    if (detalles == null) {
      return const Text('Sin detalles de apertura');
    }

    if (detalles is Map<String, dynamic>) {
      final especificos =
          detalles['detalles_especificos'] as Map<String, dynamic>?;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cash amount
            if (especificos?['efectivo_inicial'] != null) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.attach_money,
                      color: Colors.green,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Efectivo Inicial',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '\$${especificos!['efectivo_inicial'].toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // TPV and User info
            if (especificos?['id_tpv'] != null) ...[
              _buildCashDetailItem(
                'TPV ID:',
                especificos!['id_tpv'].toString(),
                Icons.point_of_sale,
              ),
            ],
            if (especificos?['usuario'] != null) ...[
              _buildCashDetailItem(
                'Usuario:',
                especificos!['usuario'].toString(),
                Icons.person,
              ),
            ],

            // Product count if available
            if (detalles['items'] != null && detalles['items'] is List) ...[
              const SizedBox(height: 8),
              _buildCashDetailItem(
                'Productos Contados:',
                '${(detalles['items'] as List).length} items',
                Icons.inventory_2,
              ),
            ],
          ],
        ),
      );
    }

    return Text(detalles.toString());
  }

  Widget _buildCashDetailItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getUserRole() async {
    try {
      final userPrefs = UserPreferencesService();
      final permissionsService = PermissionsService();

      // Obtener tienda actual
      final currentStoreId = await userPrefs.getIdTienda();
      UserRole role;

      if (currentStoreId != null) {
        // Obtener rol para la tienda actual
        role = await permissionsService.getUserRoleForStore(currentStoreId);

        // Si no se encuentra el rol en la tienda, intentar con el rol principal
        if (role == UserRole.none) {
          role = await permissionsService.getUserRole();
        }
      } else {
        // Fallback al rol principal si no hay tienda seleccionada
        role = await permissionsService.getUserRole();
      }

      return permissionsService.getRoleName(role).toLowerCase();
    } catch (e) {
      print('Error getting user role: $e');
      return 'trabajador'; // Default role
    }
  }

  bool _hasAccessToOpeningDetails(String role) {
    // Allow access for managers, supervisors, and warehouse staff
    final allowedRoles = ['gerente', 'supervisor', 'almacenero'];
    return allowedRoles.contains(role.toLowerCase());
  }

  void _showAccessDeniedDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.lock_outline, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Acceso Denegado',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No tienes permisos para ver los detalles de apertura de caja.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 8),
                Text(
                  'Solo los gerentes, supervisores y almaceneros pueden acceder a esta información.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  /// 🖨️ Construir botones de impresión y exportación
  Widget _buildPrintButton(Map<String, dynamic> operation) {
    // Obtener el estado de la operación
    final estadoNombre =
        (operation['estado_nombre'] ?? '').toString().toLowerCase().trim();

    // Validar si la operación está completada
    final isCompleted =
        estadoNombre.contains('completada') ||
        estadoNombre.contains('completed') ||
        estadoNombre.contains('finalizada');

    print(
      '🖨️ Print & PDF Buttons - Estado: "$estadoNombre", ¿Completada?: $isCompleted',
    );

    if (!isCompleted) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.print),
          label: const Text(
            'Solo se pueden imprimir o exportar operaciones completadas',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[400],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        // Botón imprimir
        Expanded(
          flex: 5,
          child: ElevatedButton.icon(
            onPressed: () => _printOperation(operation),
            icon: const Icon(Icons.print),
            label: const Text('Imprimir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Botón Exportar PDF
        Expanded(
          flex: 4,
          child: ElevatedButton.icon(
            onPressed: () => _exportToPdf(operation),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Exportar PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935), // Rojo para PDF
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 🖨️ Imprimir operación - Seleccionar tipo de impresora
  Future<void> _printOperation(Map<String, dynamic> operation) async {
    try {
      print('🖨️ Iniciando impresión de operación...');

      if (!mounted) return;

      // Mostrar diálogo de selección de tipo de impresora
      final printerType = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.print, color: Color(0xFF4A90E2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: const Text(
                      'Seleccionar Impresora',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('¿Cómo deseas imprimir la operación?'),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.wifi, color: Color(0xFF10B981)),
                    title: const Text('Impresora WiFi'),
                    subtitle: const Text('Imprimir por red WiFi'),
                    onTap: () => Navigator.pop(context, 'wifi'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.bluetooth,
                      color: Color(0xFF4A90E2),
                    ),
                    title: const Text('Impresora Bluetooth'),
                    subtitle: const Text('Imprimir por Bluetooth'),
                    onTap: () => Navigator.pop(context, 'bluetooth'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
      );

      if (printerType == null || !mounted) return;

      if (printerType == 'wifi') {
        await _printOperationWiFi(operation);
      } else {
        await _printOperationBluetooth(operation);
      }
    } catch (e) {
      print('❌ Error en _printOperation: $e');
      if (mounted) {
        _showPrintError('Error', 'Ocurrió un error al imprimir: $e');
      }
    }
  }

  /// 🖨️ Imprimir operación usando WiFi
  Future<void> _printOperationWiFi(Map<String, dynamic> operation) async {
    try {
      print('📶 Imprimiendo por WiFi...');

      if (!mounted) return;

      final wifiService = WiFiPrinterService();

      // Obtener detalles de la operación desde los datos ya cargados en la vista
      List<Map<String, dynamic>> details = [];

      if (operation['detalles'] != null && operation['detalles'] is Map) {
        final detallesMap = operation['detalles'] as Map<String, dynamic>;
        if (detallesMap['items'] != null && detallesMap['items'] is List) {
          // Convertir los items del formato de la vista al formato esperado por el servicio
          details =
              (detallesMap['items'] as List).map((item) {
                return {
                  'cantidad': item['cantidad_contada'] ?? item['cantidad'] ?? 0,
                  'producto_nombre':
                      item['producto_nombre'] ??
                      item['nombre_producto'] ??
                      'Producto',
                  'producto': {
                    'denominacion':
                        item['producto_nombre'] ??
                        item['nombre_producto'] ??
                        'Producto',
                    'codigo_barras': item['codigo_barras'],
                  },
                  'presentacion':
                      item['presentacion_nombre'] ?? item['presentacion'],
                  'ubicacion': item['ubicacion_nombre'] ?? item['ubicacion'],
                };
              }).toList();
          print(
            '📦 Detalles obtenidos de la vista: ${details.length} productos',
          );
        }
      }

      if (!mounted) return;

      // Mostrar diálogo de selección de impresora WiFi
      final selectedPrinter = await wifiService.showPrinterSelectionDialog(
        context,
      );
      if (selectedPrinter == null) {
        print('❌ No se seleccionó impresora WiFi');
        return;
      }

      if (!mounted) return;

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF10B981)),
                  SizedBox(height: 16),
                  Text('Imprimiendo por WiFi...'),
                ],
              ),
            ),
      );

      // Conectar e imprimir
      bool connected = await wifiService.connectToPrinter(
        selectedPrinter['ip'],
        port: selectedPrinter['port'] ?? 9100,
      );

      if (!connected) {
        if (mounted) {
          Navigator.pop(context);
          _showPrintError(
            'Error de Conexión',
            'No se pudo conectar a la impresora WiFi',
          );
        }
        return;
      }

      // Imprimir operación
      bool printed = await wifiService.printInventoryOperation(
        operation,
        details,
      );

      await wifiService.disconnect();

      if (!mounted) return;
      Navigator.pop(context);

      if (printed) {
        _showPrintSuccess(
          '¡Impreso!',
          'La operación se imprimió correctamente por WiFi',
        );
      } else {
        _showPrintError('Error', 'No se pudo imprimir la operación');
      }
    } catch (e) {
      print('❌ Error imprimiendo por WiFi: $e');
      if (mounted) {
        try {
          Navigator.pop(context);
        } catch (_) {}
        _showPrintError('Error WiFi', 'Error al imprimir por WiFi: $e');
      }
    }
  }

  /// 🖨️ Imprimir operación usando Bluetooth
  Future<void> _printOperationBluetooth(Map<String, dynamic> operation) async {
    try {
      print('📱 Imprimiendo por Bluetooth...');

      if (!mounted) return;

      final printerManager = PrinterManager();

      // Mostrar diálogo de confirmación
      bool shouldPrint = await printerManager.showPrintConfirmationDialog(
        context,
      );
      if (!shouldPrint || !mounted) return;

      // Seleccionar dispositivo Bluetooth
      final bluetoothService = printerManager.bluetoothService;
      var selectedDevice = await bluetoothService.showDeviceSelectionDialog(
        context,
      );
      if (selectedDevice == null || !mounted) return;

      // Mostrar diálogo de progreso - Conectando
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Conectando a impresora...'),
                ],
              ),
            ),
      );

      // Conectar
      bool connected = await bluetoothService.connectToDevice(selectedDevice);
      if (!connected) {
        if (mounted) {
          Navigator.pop(context);
          _showPrintError(
            'Conexión Fallida',
            'No se pudo conectar a la impresora',
          );
        }
        return;
      }

      if (!mounted) {
        await bluetoothService.disconnect();
        return;
      }

      // Actualizar diálogo - Imprimiendo
      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Imprimiendo ticket...'),
                ],
              ),
            ),
      );

      // Generar y enviar ticket
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = _generateOperationTicket(generator, operation);

      bool printed = await PrintBluetoothThermal.writeBytes(bytes);
      await bluetoothService.disconnect();

      if (!mounted) return;
      Navigator.pop(context);

      if (printed) {
        _showPrintSuccess(
          '¡Ticket Impreso!',
          'La operación se imprimió correctamente',
        );
      } else {
        _showPrintError('Error de Impresión', 'No se pudo imprimir el ticket');
      }
    } catch (e) {
      print('❌ Error imprimiendo por Bluetooth: $e');
      if (mounted) {
        try {
          Navigator.pop(context);
        } catch (_) {}
        _showPrintError(
          'Error Bluetooth',
          'Error al imprimir por Bluetooth: $e',
        );
      }
    }
  }

  /// 📄 Exportar operación a PDF
  Future<void> _exportToPdf(Map<String, dynamic> operation) async {
    try {
      final exportService = ExportService();

      // Extraer items de los detalles
      List<Map<String, dynamic>> items = [];
      if (operation['detalles'] != null && operation['detalles'] is Map) {
        final detallesMap = operation['detalles'] as Map<String, dynamic>;

        // Intentar obtener de 'items' directo
        if (detallesMap['items'] != null && detallesMap['items'] is List) {
          items = List<Map<String, dynamic>>.from(detallesMap['items']);
        }

        // Si no hay items, intentar de 'detalles_especificos'
        if (items.isEmpty &&
            detallesMap['detalles_especificos'] != null &&
            detallesMap['detalles_especificos'] is Map) {
          final especificos =
              detallesMap['detalles_especificos'] as Map<String, dynamic>;
          if (especificos['items'] != null && especificos['items'] is List) {
            items = List<Map<String, dynamic>>.from(especificos['items']);
          }
        }
      }

      // Obtener nombre del almacén (igual que el bottom sheet)
      String almacenNombre = 'N/A';
      final tipoOp = operation['tipo_operacion_nombre'] ?? '';
      final tipoLC = tipoOp.toLowerCase();
      if (tipoLC.contains('recepción') ||
          tipoLC.contains('recepcion') ||
          tipoLC.contains('reception') ||
          tipoLC.contains('extracción') ||
          tipoLC.contains('extraccion') ||
          tipoLC.contains('extraction') ||
          tipoLC.contains('productos')) {
        almacenNombre = await InventoryService.getWarehouseFromOperation(
          operation['id'],
          tipoOp,
        );
      }

      if (!mounted) return;

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Generando PDF...'),
                ],
              ),
            ),
      );

      await exportService.exportInventoryOperationPdf(
        context: context,
        operation: operation,
        items: items,
        almacenNombre: almacenNombre,
      );

      if (mounted) {
        Navigator.pop(context); // Cerrar diálogo de progreso
      }
    } catch (e) {
      print('❌ Error al exportar a PDF: $e');
      if (mounted) {
        try {
          Navigator.pop(context); // Intentar cerrar diálogo si existe
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar a PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Generar contenido del ticket de operación
  List<int> _generateOperationTicket(
    Generator generator,
    Map<String, dynamic> operation,
  ) {
    List<int> bytes = [];

    // Header
    bytes += generator.text(
      'INVENTTIA',
      styles: PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      'OPERACIÓN DE INVENTARIO',
      styles: PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    // Información de la operación
    bytes += generator.text(
      'ID: ${operation['id']}',
      styles: PosStyles(align: PosAlign.left, bold: true),
    );
    bytes += generator.text(
      'Tipo: ${operation['tipo_operacion_nombre'] ?? 'N/A'}',
      styles: PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      'Estado: ${operation['estado_nombre'] ?? 'N/A'}',
      styles: PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      'Fecha: ${_formatDateTime(DateTime.parse(operation['created_at']))}',
      styles: PosStyles(align: PosAlign.left),
    );

    // Observaciones
    if (operation['observaciones']?.isNotEmpty == true) {
      String obs = operation['observaciones'].toString();
      if (obs.length > 28) obs = obs.substring(0, 25) + '...';
      bytes += generator.text(
        'Obs: $obs',
        styles: PosStyles(align: PosAlign.left),
      );
    }

    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    // Productos (si existen en los detalles)
    if (operation['detalles'] != null && operation['detalles'] is Map) {
      final detallesMap = operation['detalles'] as Map<String, dynamic>;
      if (detallesMap['items'] != null && detallesMap['items'] is List) {
        final items = detallesMap['items'] as List;

        bytes += generator.text(
          'PRODUCTOS:',
          styles: PosStyles(align: PosAlign.left, bold: true),
        );

        for (var item in items) {
          final cantidad = item['cantidad_contada'] ?? item['cantidad'] ?? 0;
          String productName =
              item['producto_nombre'] ?? item['nombre_producto'] ?? 'Producto';

          // Truncar nombre si es muy largo
          if (productName.length > 24) {
            productName = productName.substring(0, 21) + '...';
          }

          bytes += generator.text(
            '${cantidad}x $productName',
            styles: PosStyles(align: PosAlign.left),
          );

          // Agregar ubicación si existe
          final ubicacion = item['ubicacion_nombre'] ?? item['ubicacion'];
          if (ubicacion != null && ubicacion.toString().isNotEmpty) {
            bytes += generator.text(
              '  Ubic: $ubicacion',
              styles: PosStyles(align: PosAlign.left),
            );
          }
        }

        bytes += generator.text(
          '----------------------------',
          styles: PosStyles(align: PosAlign.center),
        );
      }
    }

    // Totales
    final totalPrice = _calculateTotalPrice(operation);
    final totalItems = _calculateTotalItems(operation);

    bytes += generator.text(
      'Total Items: $totalItems',
      styles: PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      'Total: \$${totalPrice.toStringAsFixed(2)}',
      styles: PosStyles(align: PosAlign.left, bold: true),
    );

    // Footer
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'Gracias',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(2);
    bytes += generator.cut();

    return bytes;
  }

  /// Mostrar error de impresión
  void _showPrintError(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  /// Mostrar éxito de impresión
  void _showPrintSuccess(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('¡Genial!'),
              ),
            ],
          ),
    );
  }

  /// Mostrar diálogo de stock insuficiente al intentar completar una extracción
  void _showInsufficientStockDialog(String message) {
    // Parsear la lista de productos del mensaje
    // Formato esperado: "Stock insuficiente para: Prod A (disponible: X, solicitado: Y), Prod B ..."
    final List<Map<String, String>> productos = [];
    final bodyStart = message.indexOf(':');
    if (bodyStart != -1) {
      final body = message.substring(bodyStart + 1).trim();
      // Split por patrón "), " para separar cada producto
      final regex = RegExp(
        r'([^(]+)\(disponible:\s*([\d.]+),\s*solicitado:\s*([\d.]+)\)',
      );
      for (final match in regex.allMatches(body)) {
        productos.add({
          'nombre': match.group(1)?.trim() ?? '',
          'disponible': match.group(2) ?? '0',
          'solicitado': match.group(3) ?? '0',
        });
      }
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Stock Insuficiente',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(
                          color: Colors.red.shade300,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'No hay suficiente stock para completar esta extracción. Revisa las cantidades disponibles antes de intentar de nuevo.',
                        style: TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                    if (productos.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Productos con stock insuficiente:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...productos.map(
                        (p) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['nombre'] ?? '',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Disponible: ${p['disponible']}  •  Solicitado: ${p['solicitado']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(message, style: const TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  /// Mostrar diálogo informativo para error de consignación
  void _showConsignmentErrorDialog(
    String message,
    dynamic idOperacionExtraccion,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  color: Colors.deepOrange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Recepción de Consignación',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mensaje principal
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(
                        color: Colors.orange.shade300,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠️ Mercancía no recibida',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.deepOrange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'No puedes completar la recepción hasta que la mercancía esté físicamente en tu negocio.',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Instrucciones
                  const Text(
                    '📋 Pasos a seguir:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _buildInstructionStep(
                    '1',
                    'Verifica que la mercancía haya llegado a tu almacén',
                  ),
                  _buildInstructionStep(
                    '2',
                    'Inspecciona la mercancía (cantidad, estado, etc.)',
                  ),
                  _buildInstructionStep(
                    '4',
                    'Luego podrás completar la recepción aquí',
                  ),
                  const SizedBox(height: 16),

                  // Información técnica
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🔍 Información técnica:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Operación Extracción: #$idOperacionExtraccion',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  /// Widget para mostrar un paso de instrucción
  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.blue.shade700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sección que muestra el detalle del pago de una operación de venta.
/// Si no hay pagos y el total es 0, permite registrar uno manualmente.
class _PaymentDetailsSection extends StatefulWidget {
  final int operationId;
  final bool totalIsZero;
  final Future<List<Map<String, dynamic>>> Function(int) getPaymentDetails;
  final Future<bool> Function(int) registerZeroPayment;

  const _PaymentDetailsSection({
    required this.operationId,
    required this.totalIsZero,
    required this.getPaymentDetails,
    required this.registerZeroPayment,
  });

  @override
  State<_PaymentDetailsSection> createState() => _PaymentDetailsSectionState();
}

class _PaymentDetailsSectionState extends State<_PaymentDetailsSection> {
  bool _isRegistering = false;
  Key _futureKey = UniqueKey();

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    final dt = value is DateTime ? value : DateTime.tryParse(value.toString());
    if (dt == null) return '-';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: _futureKey,
      future: widget.getPaymentDetails(widget.operationId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 80,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final payments = snapshot.data ?? [];

        if (payments.isNotEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
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
                    Icon(Icons.payments, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Detalle del pago',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                ...payments.map((payment) {
                  final medio =
                      payment['app_nom_medio_pago'] as Map<String, dynamic>?;
                  final medioNombre = medio?['denominacion'] ?? 'Desconocido';
                  final monto = (payment['monto'] as num?) ?? 0;
                  final referencia =
                      payment['referencia_pago']?.toString() ?? '-';
                  final fecha = payment['fecha_pago'] ?? payment['created_at'];
                  final tipoPago =
                      payment['tipo_pago'] == 1 ? 'Efectivo' : 'Digital';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailRow('Medio de pago', medioNombre),
                        _buildDetailRow(
                          'Monto',
                          'CUP ${monto.toStringAsFixed(2)}',
                        ),
                        _buildDetailRow('Tipo', tipoPago),
                        _buildDetailRow('Referencia', referencia),
                        _buildDetailRow('Fecha', _formatDate(fecha)),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }

        if (widget.totalIsZero) {
          return ElevatedButton.icon(
            onPressed:
                _isRegistering
                    ? null
                    : () async {
                      setState(() => _isRegistering = true);
                      final success = await widget.registerZeroPayment(
                        widget.operationId,
                      );
                      if (!mounted) return;
                      setState(() {
                        _isRegistering = false;
                        _futureKey = UniqueKey();
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Pago registrado correctamente'
                                : 'Error al registrar el pago',
                          ),
                          backgroundColor: success ? Colors.green : Colors.red,
                        ),
                      );
                    },
            icon:
                _isRegistering
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : const Icon(Icons.payment, color: Colors.white),
            label: Text(
              _isRegistering ? 'Registrando...' : 'Registrar pago (monto 0)',
              style: const TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber,
                color: Colors.orange.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Esta venta no tiene pagos registrados.',
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
