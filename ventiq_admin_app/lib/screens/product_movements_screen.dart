import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/product_movements_service.dart';
import '../config/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    // Inicializar filtros por defecto: fecha actual
    final now = DateTime.now();
    _dateFrom = DateTime(now.year, now.month, now.day, 0, 0, 0);
    _dateTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
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

    // Ordenar por fecha descendente (más recientes primero)
    _filteredMovements.sort((a, b) {
      final dateA = DateTime.tryParse(a['fecha'] as String? ?? '') ?? DateTime(2000);
      final dateB = DateTime.tryParse(b['fecha'] as String? ?? '') ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    setState(() {});
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
      _dateFrom = DateTime(now.year, now.month, now.day, 0, 0, 0);
      _dateTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
      _selectedOperationTypeId = null;
    });
    _loadData();
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filtros
                _buildFiltersSection(),
                
                // Resumen
                if (_filteredMovements.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(
                                'Total Movimientos',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${_filteredMovements.length}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                'Recepción',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${_filteredMovements.where((m) => m['tipo_movimiento'] == 'Recepción').length}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                'Extracción',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${_filteredMovements.where((m) => m['tipo_movimiento'] == 'Extracción').length}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                'Control',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${_filteredMovements.where((m) => m['tipo_movimiento'] == 'Control').length}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                // Lista de movimientos
                Expanded(
                  child: _filteredMovements.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox,
                                size: 64,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No hay movimientos',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: _filteredMovements.length + (_hasMoreData ? 1 : 0),
                          itemBuilder: (context, index) {
                            // Mostrar indicador de carga al final
                            if (index == _filteredMovements.length) {
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
                            
                            final movement = _filteredMovements[index];
                            return _buildMovementCard(movement);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFiltersSection() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Filtros',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_dateFrom != null || _dateTo != null || _selectedOperationTypeId != null)
                GestureDetector(
                  onTap: _clearFilters,
                  child: const Text(
                    'Limpiar',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
        ],
      ),
    );
  }

  Widget _buildMovementCard(Map<String, dynamic> movement) {
    final tipoMovimiento = movement['tipo_movimiento'] as String;
    final color = _getMovementTypeColor(tipoMovimiento);
    final icon = _getMovementTypeIcon(tipoMovimiento);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado con tipo de movimiento
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
                      Text(
                        tipoMovimiento,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        movement['tipo_operacion'] as String? ?? 'Desconocido',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDate(movement['fecha'] as String? ?? ''),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Detalles del movimiento
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cantidad inicial
                  if (movement['cantidad_inicial'] != null)
                    _buildDetailRow(
                      'Cantidad Inicial',
                      '${movement['cantidad_inicial']}',
                    ),
                  
                  // Cantidad
                  if (movement['cantidad'] != null)
                    _buildDetailRow(
                      'Cantidad',
                      '${movement['cantidad']}',
                    ),
                  
                  // Cantidad final
                  if (movement['cantidad_final'] != null)
                    _buildDetailRow(
                      'Cantidad Final',
                      '${movement['cantidad_final']}',
                    ),
                  
                  // Precio unitario
                  if (movement['precio_unitario'] != null)
                    _buildDetailRow(
                      'Precio Unitario',
                      '\$${(movement['precio_unitario'] as num).toStringAsFixed(2)}',
                    ),
                  
                  // Costo real
                  if (movement['costo_real'] != null)
                    _buildDetailRow(
                      'Costo Real',
                      '\$${(movement['costo_real'] as num).toStringAsFixed(2)}',
                    ),
                  
                  // Importe real
                  if (movement['importe_real'] != null)
                    _buildDetailRow(
                      'Importe Real',
                      '\$${(movement['importe_real'] as num).toStringAsFixed(2)}',
                    ),
                  
                  // Para recepciones: Entregado por y Recibido por
                  if (movement['tipo_movimiento'] == 'Recepción') ...[
                    if (movement['entregado_por'] != null)
                      _buildDetailRow(
                        'Entregado Por',
                        movement['entregado_por'] as String,
                      ),
                    if (movement['recibido_por'] != null)
                      _buildDetailRow(
                        'Recibido Por',
                        movement['recibido_por'] as String,
                      ),
                  ],
                  
                  // Para extracciones: Autorizado por
                  if (movement['tipo_movimiento'] == 'Extracción' &&
                      movement['autorizado_por'] != null)
                    _buildDetailRow(
                      'Autorizado Por',
                      movement['autorizado_por'] as String,
                    ),
                  
                  // Ubicación
                  if (movement['ubicacion'] != null)
                    _buildDetailRow(
                      'Ubicación',
                      movement['ubicacion'] as String,
                    ),
                  
                  // Proveedor
                  if (movement['proveedor'] != null)
                    _buildDetailRow(
                      'Proveedor',
                      movement['proveedor'] as String,
                    ),
                ],
              ),
            ),
            
            // Observaciones
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
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      movement['observaciones'] as String,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
