import 'dart:async';
import 'package:flutter/material.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';

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

  // Pagination
  int _currentPage = 1;
  int _totalCount = 0;
  final int _itemsPerPage = 20;
  bool _hasNextPage = false;

  @override
  void initState() {
    super.initState();
    _loadOperations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
    _debounceSearch();
  }

  Timer? _debounceTimer;
  void _debounceSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _currentPage = 1;
      _loadOperations();
    });
  }

  Future<void> _loadOperations() async {
    try {
      setState(() => _isLoading = true);

      final result = await InventoryService.getInventoryOperations(
        busqueda: _searchQuery.isEmpty ? null : _searchQuery,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
        limite: _itemsPerPage,
        pagina: _currentPage,
      );

      setState(() {
        _operations = result['operations'] ?? [];
        _totalCount = result['totalCount'] ?? 0;
        _hasNextPage = (_currentPage * _itemsPerPage) < _totalCount;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar operaciones: $e')),
        );
      }
    }
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
            initialChildSize: 0.5,
            maxChildSize: 0.7,
            minChildSize: 0.3,
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
                            // Inline Date Range Picker
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: Theme.of(
                                    context,
                                  ).colorScheme.copyWith(
                                    primary: const Color(0xFF4A90E2),
                                    onPrimary: Colors.white,
                                  ),
                                ),
                                child: CalendarDatePicker(
                                  initialDate: _fechaDesde ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  onDateChanged: (date) async {
                                    // First date selected, now select end date
                                    final endDate = await _selectEndDate(date);
                                    if (endDate != null) {
                                      Navigator.pop(context);
                                      setState(() {
                                        _fechaDesde = date;
                                        _fechaHasta = endDate;
                                      });
                                      _currentPage = 1;
                                      _loadOperations();
                                    }
                                  },
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Current selection display
                            if (_fechaDesde != null && _fechaHasta != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF4A90E2,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF4A90E2,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Rango seleccionado:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_formatDate(_fechaDesde!)} - ${_formatDate(_fechaHasta!)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            const SizedBox(height: 12),

                            // Clear filter button
                            if (_fechaDesde != null || _fechaHasta != null)
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _clearDateFilter();
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Limpiar Filtro'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
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
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Future<DateTime?> _selectEndDate(DateTime startDate) async {
    return await showDatePicker(
      context: context,
      initialDate: startDate.add(const Duration(days: 1)),
      firstDate: startDate,
      lastDate: DateTime.now(),
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
  }

  void _clearDateFilter() {
    setState(() {
      _fechaDesde = null;
      _fechaHasta = null;
    });
    _currentPage = 1;
    _loadOperations();
  }

  void _nextPage() {
    if (_hasNextPage) {
      setState(() => _currentPage++);
      _loadOperations();
    }
  }

  void _previousPage() {
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      _loadOperations();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [_buildFilters(), _buildOperationsList(), _buildPagination()],
      ),
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

          // Clear filter button
          if (_fechaDesde != null || _fechaHasta != null) ...[
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: IconButton(
                onPressed: _clearDateFilter,
                icon: const Icon(Icons.clear, color: Colors.red),
                tooltip: 'Limpiar filtro de fecha',
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
        child: _isLoading
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
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _operations.length,
                    itemBuilder: (context, index) {
                      final operation = _operations[index];
                      return _buildOperationCard(operation);
                    },
                  ),
      ),
    );
  }

  Widget _buildOperationCard(Map<String, dynamic> operation) {
    final tipoOperacion = operation['tipo_operacion_nombre'] ?? 'Desconocido';
    final fecha = DateTime.parse(operation['created_at']);
    final total = _calculateTotalPrice(operation);
    final cantidadItems = _calculateTotalItems(operation);
    final estadoNombre = operation['estado_nombre'] ?? 'Sin estado';
    final observaciones = operation['observaciones'] ?? '';

    // Debug: Log the exact status we're getting from the database
    print(
      '📋 Operation Card - ID: ${operation['id']}, Estado: "$estadoNombre"',
    );

    // Determine operation type icon and color
    IconData operationIcon;
    Color operationColor;

    if (tipoOperacion.toLowerCase().contains('recepcion')) {
      operationIcon = Icons.input;
      operationColor = Colors.green;
    } else if (tipoOperacion.toLowerCase().contains('extraccion')) {
      operationIcon = Icons.output;
      operationColor = Colors.orange;
    } else if (tipoOperacion.toLowerCase().contains('venta')) {
      operationIcon = Icons.shopping_cart;
      operationColor = Colors.blue;
    } else if (tipoOperacion.toLowerCase().contains('apertura de caja')) {
      operationIcon = Icons.point_of_sale;
      operationColor = Colors.green;
    } else if (tipoOperacion.toLowerCase().contains('cierre de caja')) {
      operationIcon = Icons.point_of_sale;
      operationColor = Colors.orange;
    } else {
      operationIcon = Icons.swap_horiz;
      operationColor = Colors.purple;
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

  Widget _buildPagination() {
    if (_totalCount <= _itemsPerPage) return const SizedBox.shrink();

    final totalPages = (_totalCount / _itemsPerPage).ceil();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Página $_currentPage de $totalPages ($_totalCount total)',
            style: TextStyle(color: Colors.grey[600]),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _currentPage > 1 ? _previousPage : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: _hasNextPage ? _nextPage : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
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
                              child: Text(
                                'Operación #${operation['id']}',
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
                            _buildModalDetailRow(
                              'Total:',
                              '\$${_calculateTotalPrice(operation).toStringAsFixed(2)}',
                            ),
                            _buildModalDetailRow(
                              'Items:',
                              '${_calculateTotalItems(operation)}',
                            ),
                            if (operation['observaciones']?.isNotEmpty == true)
                              _buildModalDetailRow(
                                'Observaciones:',
                                operation['observaciones'],
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}';
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detalles['detalles_especificos'] != null) ...[
            const Text(
              'Información específica:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            _buildSpecificDetails(detalles['detalles_especificos']),
            const SizedBox(height: 12),
          ],
          if (detalles['items'] != null && detalles['items'] is List) ...[
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
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:
              especificos.entries.map((entry) {
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
              }).toList(),
        ),
      );
    }

    return Text(especificos.toString());
  }

  Widget _buildProductsList(List<dynamic> items) {
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
                items.asMap().entries.map((entry) {
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
                              if (item['sku'] != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'SKU: ${item['sku']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Quantity counted
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A90E2).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF4A90E2).withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            '${item['cantidad_fisica'] ?? item['cantidad'] ?? 0}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4A90E2),
                            ),
                          ),
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
    // Show complete button for reception operations that are pending
    String tipoOperacion =
        operation['tipo_operacion_nombre']?.toString().toLowerCase() ?? '';
    String estado = operation['estado_nombre']?.toString().toLowerCase() ?? '';

    // Debug logging
    print('🔍 Checking completion button for operation:');
    print('   - ID: ${operation['id']}');
    print('   - Tipo: "$tipoOperacion"');
    print('   - Estado: "$estado"');
    print('   - Contains recepción: ${tipoOperacion.contains('recepción')}');
    print('   - Contains pendiente: ${estado.contains('pendiente')}');

    // Check for different variations of the operation type
    bool isReception =
        tipoOperacion.contains('recepción') ||
        tipoOperacion.contains('recepcion') ||
        tipoOperacion.contains('entrada') ||
        tipoOperacion.contains('ingreso');
    bool isExtraction =
        tipoOperacion.contains('extracción') ||
        tipoOperacion.contains('extraccion') ||
        tipoOperacion.contains('salida');

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

    return (isReception || isExtraction) && isPending;
  }

  bool _shouldShowCancelButton(Map<String, dynamic> operation) {
    // Show cancel button only for pending operations
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

    print('   - Is pending: $isPending');
    print('   - Should show cancel button: $isPending');

    return isPending;
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
    // print('result: ${result['data']}');
      final response = result['data'];
      if (response['status'] == 'success') {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message'] ?? 'Error al completar la operación',
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

      final result = await InventoryService.cancelOperation(
        idOperacion:
            operationId is int
                ? operationId
                : int.parse(operationId.toString()),
        comentario:
            comment.isEmpty ? 'Operación cancelada desde la app' : comment,
        uuid: userUuid,
      );

      Navigator.pop(context); // Close loading dialog

      if (result['status'] == 'success') {
        // Close the detail modal
        Navigator.pop(context);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['mensaje'] ?? 'Operación cancelada exitosamente',
            ),
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
              result['message'] ?? 'Error al cancelar la operación',
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
      final adminProfile = await userPrefs.getAdminProfile();
      return adminProfile['role'] ?? 'trabajador';
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
}
