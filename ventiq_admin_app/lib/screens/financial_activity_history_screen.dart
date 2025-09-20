import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/financial_service.dart';

class FinancialActivityHistoryScreen extends StatefulWidget {
  const FinancialActivityHistoryScreen({super.key});

  @override
  State<FinancialActivityHistoryScreen> createState() => _FinancialActivityHistoryScreenState();
}

class _FinancialActivityHistoryScreenState extends State<FinancialActivityHistoryScreen> {
  final FinancialService _financialService = FinancialService();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _activities = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _selectedFilter;
  
  final List<Map<String, String?>> _filterOptions = [
    {'value': null, 'label': 'Todas las actividades'},
    {'value': 'gasto_registrado', 'label': 'Gastos registrados'},
    {'value': 'gasto_eliminado', 'label': 'Gastos eliminados'},
    {'value': 'operacion_procesada', 'label': 'Operaciones procesadas'},
  ];

  @override
  void initState() {
    super.initState();
    _loadActivities();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreActivities();
      }
    }
  }

  Future<void> _loadActivities() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _activities.clear();
    });

    try {
      final result = await _financialService.getActivityHistory(
        page: _currentPage,
        tipoActividad: _selectedFilter,
      );
      
      setState(() {
        _activities = List<Map<String, dynamic>>.from(result['data']);
        _hasMore = result['hasMore'] ?? false;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error cargando actividades: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreActivities() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final result = await _financialService.getActivityHistory(
        page: _currentPage + 1,
        tipoActividad: _selectedFilter,
      );
      
      setState(() {
        _activities.addAll(List<Map<String, dynamic>>.from(result['data']));
        _hasMore = result['hasMore'] ?? false;
        _currentPage++;
        _isLoadingMore = false;
      });
    } catch (e) {
      print('❌ Error cargando más actividades: $e');
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Actividades'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildFilterSection(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _activities.isEmpty
                    ? _buildEmptyState()
                    : _buildActivitiesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list, color: Colors.grey),
          const SizedBox(width: 8),
          const Text('Filtrar por: '),
          Expanded(
            child: DropdownButton<String?>(
              value: _selectedFilter,
              isExpanded: true,
              underline: const SizedBox(),
              items: _filterOptions.map((option) {
                return DropdownMenuItem<String?>(
                  value: option['value'],
                  child: Text(option['label']!),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedFilter = value;
                });
                _loadActivities();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No hay actividades registradas',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Las actividades aparecerán aquí cuando realices acciones en el módulo financiero',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _activities.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _activities.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final activity = _activities[index];
        return _buildActivityCard(activity);
      },
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final tipoActividad = activity['tipo_actividad'] as String;
    final descripcion = activity['descripcion'] as String;
    final fechaActividad = DateTime.parse(activity['fecha_actividad']);
    final monto = activity['monto'];
    final metadata = activity['metadata'] as Map<String, dynamic>?;

    IconData icon;
    Color color;

    switch (tipoActividad) {
      case 'gasto_registrado':
        icon = Icons.add_circle;
        color = Colors.green;
        break;
      case 'gasto_eliminado':
        icon = Icons.remove_circle;
        color = Colors.red;
        break;
      case 'operacion_procesada':
        icon = Icons.check_circle;
        color = Colors.blue;
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        descripcion,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTime(fechaActividad),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (monto != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '\$${monto}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
            if (metadata != null && metadata.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detalles:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...metadata.entries.map((entry) => Text(
                      '${entry.key}: ${entry.value}',
                      style: const TextStyle(fontSize: 12),
                    )),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
