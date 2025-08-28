import 'dart:async';
import 'package:flutter/material.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';

class InventoryOperationsScreen extends StatefulWidget {
  const InventoryOperationsScreen({super.key});

  @override
  State<InventoryOperationsScreen> createState() => _InventoryOperationsScreenState();
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
        _operations = result['operations'] ??[];
        _totalCount = result['totalCount'] ??0;
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

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _fechaDesde != null && _fechaHasta != null
          ? DateTimeRange(start: _fechaDesde!, end: _fechaHasta!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _fechaDesde = picked.start;
        _fechaHasta = picked.end;
      });
      _currentPage = 1;
      _loadOperations();
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
        children: [
          _buildFilters(),
          _buildOperationsList(),
          _buildPagination(),
        ],
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
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar operaciones...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          
          // Date filters
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectDateRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _fechaDesde != null && _fechaHasta != null
                        ? '${_formatDate(_fechaDesde!)} - ${_formatDate(_fechaHasta!)}'
                        : 'Seleccionar fechas',
                  ),
                ),
              ),
              if (_fechaDesde != null || _fechaHasta != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _clearDateFilter,
                  icon: const Icon(Icons.clear),
                  tooltip: 'Limpiar filtro de fecha',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsList() {
    return Expanded(
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _operations.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No se encontraron operaciones'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _operations.length,
                  itemBuilder: (context, index) {
                    final operation = _operations[index];
                    return _buildOperationCard(operation);
                  },
                ),
    );
  }

  Widget _buildOperationCard(Map<String, dynamic> operation) {
    final tipoOperacion = operation['tipo_operacion_nombre'] ?? 'Desconocido';
    final fecha = DateTime.parse(operation['created_at']);
    final total = operation['total']?.toDouble() ?? 0.0;
    final cantidadItems = operation['cantidad_items'] ?? 0;
    final estadoNombre = operation['estado_nombre'] ?? 'Sin estado';
    final observaciones = operation['observaciones'] ?? '';

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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                        if (observaciones.isNotEmpty)
                          Text(
                            observaciones,
                            style: TextStyle(color: Colors.grey[600], fontSize: 14),
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
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
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
    switch (status.toLowerCase()) {
      case 'pendiente':
        return Colors.orange;
      case 'completado':
      case 'aprobado':
        return Colors.green;
      case 'cancelado':
      case 'rechazado':
        return Colors.red;
      default:
        return Colors.grey;
    }
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
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Operación #${operation['id']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Tipo', operation['tipo_operacion_nombre']),
              _buildDetailRow('Estado', operation['estado_nombre']),
              _buildDetailRow('Fecha', _formatDateTime(DateTime.parse(operation['created_at']))),
              _buildDetailRow('Total', '\$${(operation['total']?.toDouble() ?? 0.0).toStringAsFixed(2)}'),
              _buildDetailRow('Items', '${operation['cantidad_items'] ?? 0}'),
              if (operation['observaciones']?.isNotEmpty == true)
                _buildDetailRow('Observaciones', operation['observaciones']),
              
              // Show specific details based on operation type
              if (operation['detalles'] != null) ...[
                const SizedBox(height: 16),
                const Text('Detalles específicos:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildFormattedDetails(operation['detalles']),
              ],
              
              // Show completion button for pending reception operations
              if (_shouldShowCompleteButton(operation)) ...[
                const SizedBox(height: 16),
                _buildCompleteButton(operation),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
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

  Widget _buildFormattedDetails(dynamic detalles) {
    if (detalles == null) return const Text('Sin detalles específicos');
    
    if (detalles is Map<String, dynamic>) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (detalles['detalles_especificos'] != null) ...[
            const Text('Información específica:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            _buildSpecificDetails(detalles['detalles_especificos']),
            const SizedBox(height: 12),
          ],
          if (detalles['items'] != null && detalles['items'] is List) ...[
            const Text('Productos:', style: TextStyle(fontWeight: FontWeight.w600)),
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
          children: especificos.entries.map((entry) {
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          int index = entry.key;
          Map<String, dynamic> item = entry.value;
          
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: index > 0 ? Border(top: BorderSide(color: Colors.grey[200]!)) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['producto_nombre'] ?? 'Producto sin nombre',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text('Cantidad: ${item['cantidad'] ?? 0}'),
                    ),
                    Expanded(
                      child: Text('Precio: \$${(item['precio_unitario']?.toDouble() ?? 0.0).toStringAsFixed(2)}'),
                    ),
                  ],
                ),
                if (item['presentacion'] != null || item['variante'] != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item['presentacion'] != null)
                        Expanded(child: Text('Presentación: ${item['presentacion']}')),
                      if (item['variante'] != null)
                        Expanded(child: Text('Variante: ${item['variante']}')),
                    ],
                  ),
                ],
                if (item['opcion_variante'] != null) ...[
                  const SizedBox(height: 4),
                  Text('Opción: ${item['opcion_variante']}'),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatFieldLabel(String key) {
    switch (key) {
      case 'id_tpv': return 'TPV';
      case 'tpv_nombre': return 'Nombre TPV';
      case 'total': return 'Total';
      case 'cantidad_items': return 'Cantidad Items';
      case 'id_proveedor': return 'Proveedor';
      case 'proveedor_nombre': return 'Nombre Proveedor';
      case 'motivo': return 'Motivo';
      case 'recibido_por': return 'Recibido por';
      default: return key.replaceAll('_', ' ').toUpperCase();
    }
  }

  String _formatFieldValue(dynamic value) {
    if (value == null) return 'N/A';
    if (value is double) return value.toStringAsFixed(2);
    if (value is num) return value.toString();
    return value.toString();
  }

  bool _shouldShowCompleteButton(Map<String, dynamic> operation) {
    // Show complete button for reception operations that are pending
    String tipoOperacion = operation['tipo_operacion_nombre']?.toString().toLowerCase() ?? '';
    String estado = operation['estado_nombre']?.toString().toLowerCase() ?? '';
    
    // Debug logging
    print('🔍 Checking completion button for operation:');
    print('   - ID: ${operation['id']}');
    print('   - Tipo: "$tipoOperacion"');
    print('   - Estado: "$estado"');
    print('   - Contains recepción: ${tipoOperacion.contains('recepción')}');
    print('   - Contains pendiente: ${estado.contains('pendiente')}');
    
    // Check for different variations of the operation type
    bool isReception = tipoOperacion.contains('recepción') || 
                      tipoOperacion.contains('recepcion') ||
                      tipoOperacion.contains('entrada') ||
                      tipoOperacion.contains('ingreso');
    
    // Check for different variations of pending status
    bool isPending = estado.contains('pendiente') || 
                    estado.contains('pending') ||
                    estado.contains('en proceso') ||
                    estado.contains('proceso');
    
    print('   - Is reception: $isReception');
    print('   - Is pending: $isPending');
    print('   - Should show button: ${isReception && isPending}');
    
    return isReception && isPending;
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

  void _showCompleteOperationDialog(Map<String, dynamic> operation) {
    final commentController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Completar Operación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Está seguro de completar la operación #${operation['id']}?'),
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
            onPressed: () => _completeOperation(operation, commentController.text),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Completar'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeOperation(Map<String, dynamic> operation, String comment) async {
    try {
      Navigator.pop(context); // Close dialog
      
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
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
        idOperacion: operationId is int ? operationId : int.parse(operationId.toString()),
        comentario: comment.isEmpty ? 'Operación completada desde la app' : comment,
        uuid: userUuid,
      );

      Navigator.pop(context); // Close loading dialog

      if (result['status'] == 'success') {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['mensaje'] ?? 'Operación completada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Refresh the operations list
        _loadOperations();
      } else {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Error al completar la operación'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close loading dialog if still open
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
