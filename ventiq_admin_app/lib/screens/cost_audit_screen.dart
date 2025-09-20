import 'package:flutter/material.dart';
import '../services/financial_service.dart';

class CostAuditScreen extends StatefulWidget {
  const CostAuditScreen({Key? key}) : super(key: key);

  @override
  State<CostAuditScreen> createState() => _CostAuditScreenState();
}

class _CostAuditScreenState extends State<CostAuditScreen> {
  final FinancialService _financialService = FinancialService();
  List<Map<String, dynamic>> _auditLogs = [];
  bool _isLoading = true;
  String? _selectedDateRange;
  int? _selectedAssignmentId;
  List<Map<String, dynamic>> _assignments = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final results = await Future.wait([
        _financialService.getCostAuditLogs(),
        _financialService.getCostAssignments(),
      ]);

      setState(() {
        _auditLogs = results[0];
        _assignments = results[1];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error cargando datos: $e');
    }
  }

  Future<void> _applyFilters() async {
    setState(() => _isLoading = true);
    
    try {
      String? startDate;
      String? endDate;
      
      if (_selectedDateRange != null) {
        final now = DateTime.now();
        switch (_selectedDateRange) {
          case 'today':
            startDate = DateTime(now.year, now.month, now.day).toIso8601String();
            endDate = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();
            break;
          case 'week':
            startDate = now.subtract(const Duration(days: 7)).toIso8601String();
            break;
          case 'month':
            startDate = DateTime(now.year, now.month, 1).toIso8601String();
            break;
        }
      }

      final logs = await _financialService.getCostAuditLogs(
        assignmentId: _selectedAssignmentId,
        startDate: startDate,
        endDate: endDate,
      );

      setState(() {
        _auditLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error aplicando filtros: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _formatDateTime(String dateTime) {
    final dt = DateTime.parse(dateTime);
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _getActionColor(String action) {
    switch (action.toLowerCase()) {
      case 'create':
      case 'crear':
        return Colors.green;
      case 'update':
      case 'actualizar':
        return Colors.blue;
      case 'delete':
      case 'eliminar':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getActionIcon(String action) {
    switch (action.toLowerCase()) {
      case 'create':
      case 'crear':
        return Icons.add_circle;
      case 'update':
      case 'actualizar':
        return Icons.edit;
      case 'delete':
      case 'eliminar':
        return Icons.delete;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoría de Costos'),
        backgroundColor: Colors.purple[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filtros aplicados
                if (_selectedDateRange != null || _selectedAssignmentId != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.purple[50],
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list, color: Colors.purple),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Filtros: ${_selectedDateRange ?? 'Todas las fechas'}'
                            '${_selectedAssignmentId != null ? ', Asignación específica' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedDateRange = null;
                              _selectedAssignmentId = null;
                            });
                            _loadData();
                          },
                          child: const Text('Limpiar'),
                        ),
                      ],
                    ),
                  ),

                // Lista de logs
                Expanded(
                  child: _auditLogs.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No hay registros de auditoría'),
                              SizedBox(height: 8),
                              Text('Los cambios en asignaciones aparecerán aquí'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _auditLogs.length,
                          itemBuilder: (context, index) {
                            final log = _auditLogs[index];
                            final assignment = log['app_cont_asignacion_costos'];
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: _getActionColor(log['accion'] ?? '').withOpacity(0.2),
                                  child: Icon(
                                    _getActionIcon(log['accion'] ?? ''),
                                    color: _getActionColor(log['accion'] ?? ''),
                                  ),
                                ),
                                title: Text(
                                  'Acción: ${log['accion'] ?? 'N/A'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Fecha: ${_formatDateTime(log['fecha_operacion'])}'),
                                    if (assignment != null) ...[
                                      Text('Tipo: ${assignment['app_cont_tipo_costo']?['denominacion'] ?? 'N/A'}'),
                                      Text('Centro: ${assignment['app_cont_centro_costo']?['denominacion'] ?? 'N/A'}'),
                                    ],
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (log['cambios'] != null) ...[
                                          const Text(
                                            'Detalles del Cambio:',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              log['cambios'],
                                              style: const TextStyle(fontFamily: 'monospace'),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            const Icon(Icons.person, size: 16, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Usuario: ${log['realizado_por'] ?? 'Sistema'}',
                                              style: const TextStyle(color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                        if (assignment != null) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Icon(Icons.percent, size: 16, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Porcentaje: ${assignment['porcentaje_asignacion']}%',
                                                style: const TextStyle(color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.settings, size: 16, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Método: ${assignment['metodo_asignacion']}',
                                                style: const TextStyle(color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Future<void> _showFilterDialog() async {
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filtrar Auditoría'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Filtro por fecha
              DropdownButtonFormField<String>(
                value: _selectedDateRange,
                decoration: const InputDecoration(
                  labelText: 'Rango de Fechas',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todas las fechas')),
                  DropdownMenuItem(value: 'today', child: Text('Hoy')),
                  DropdownMenuItem(value: 'week', child: Text('Última semana')),
                  DropdownMenuItem(value: 'month', child: Text('Este mes')),
                ],
                onChanged: (value) => setDialogState(() => _selectedDateRange = value),
              ),
              const SizedBox(height: 16),

              // Filtro por asignación
              DropdownButtonFormField<int>(
                value: _selectedAssignmentId,
                decoration: const InputDecoration(
                  labelText: 'Asignación Específica',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todas las asignaciones')),
                  ..._assignments.map((assignment) => DropdownMenuItem<int>(
                    value: assignment['id'],
                    child: Text('${assignment['tipo_costo_nombre']} - ${assignment['centro_costo_nombre']}'),
                  )),
                ],
                onChanged: (value) => setDialogState(() => _selectedAssignmentId = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _applyFilters();
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }
}
