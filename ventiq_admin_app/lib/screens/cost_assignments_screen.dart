import 'package:flutter/material.dart';
import '../services/financial_service.dart';

class CostAssignmentsScreen extends StatefulWidget {
  const CostAssignmentsScreen({Key? key}) : super(key: key);

  @override
  State<CostAssignmentsScreen> createState() => _CostAssignmentsScreenState();
}

class _CostAssignmentsScreenState extends State<CostAssignmentsScreen> {
  final FinancialService _financialService = FinancialService();
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _costTypes = [];
  List<Map<String, dynamic>> _costCenters = [];
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;

  // Constantes para métodos de asignación (deben coincidir con FinancialService)
  static const int METODO_AUTOMATICO = 1;
  static const int METODO_MANUAL = 2;
  static const int METODO_PROPORCIONAL = 3;

  // Método para convertir int a String para mostrar en UI
  String _getMethodDisplayName(int? method) {
    switch (method) {
      case METODO_AUTOMATICO:
        return 'Automático';
      case METODO_MANUAL:
        return 'Manual';
      case METODO_PROPORCIONAL:
        return 'Proporcional';
      default:
        return 'Desconocido';
    }
  }

  // Método para obtener el valor int desde el assignment
  int _getMethodValue(Map<String, dynamic>? assignment) {
    if (assignment == null) return METODO_PROPORCIONAL;
    
    final method = assignment['metodo_asignacion'];
    if (method is int) {
      return method;
    } else if (method is String) {
      // Conversión de legacy strings a int
      switch (method.toUpperCase()) {
        case 'AUTOMATICO':
          return METODO_AUTOMATICO;
        case 'MANUAL':
          return METODO_MANUAL;
        case 'PROPORCIONAL':
        default:
          return METODO_PROPORCIONAL;
      }
    }
    return METODO_PROPORCIONAL;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final results = await Future.wait([
        _financialService.getCostAssignments(),
        _financialService.getCostTypes(),
        _financialService.getCostCenters(),
        _financialService.getProducts(),
      ]);

      setState(() {
        _assignments = results[0];
        _costTypes = results[1];
        _costCenters = results[2];
        _products = results[3];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error cargando datos: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _showAssignmentDialog({Map<String, dynamic>? assignment}) async {
    int? selectedCostType = assignment?['id_tipo_costo'];
    int? selectedCostCenter = assignment?['id_centro_costo'];
    int? selectedProduct = assignment?['id_producto'];
    double percentage = assignment?['porcentaje_asignacion']?.toDouble() ?? 100.0;
    int method = _getMethodValue(assignment); // Usar int en lugar de String

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(assignment == null ? 'Nueva Asignación' : 'Editar Asignación'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tipo de Costo
                DropdownButtonFormField<int>(
                  value: selectedCostType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Costo',
                    border: OutlineInputBorder(),
                  ),
                  items: _costTypes.map((type) => DropdownMenuItem<int>(
                    value: type['id'],
                    child: Text(type['denominacion']),
                  )).toList(),
                  onChanged: (value) => setDialogState(() => selectedCostType = value),
                ),
                const SizedBox(height: 16),

                // Centro de Costo
                DropdownButtonFormField<int>(
                  value: selectedCostCenter,
                  decoration: const InputDecoration(
                    labelText: 'Centro de Costo',
                    border: OutlineInputBorder(),
                  ),
                  items: _costCenters.map((center) => DropdownMenuItem<int>(
                    value: center['id'],
                    child: Text(center['denominacion']),
                  )).toList(),
                  onChanged: (value) => setDialogState(() => selectedCostCenter = value),
                ),
                const SizedBox(height: 16),

                // Producto (Opcional)
                DropdownButtonFormField<int>(
                  value: selectedProduct,
                  decoration: const InputDecoration(
                    labelText: 'Producto (Opcional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int>(value: null, child: Text('Todos los productos')),
                    ..._products.map((product) => DropdownMenuItem<int>(
                      value: product['id'],
                      child: Text(product['denominacion']),
                    )),
                  ],
                  onChanged: (value) => setDialogState(() => selectedProduct = value),
                ),
                const SizedBox(height: 16),

                // Porcentaje
                TextFormField(
                  initialValue: percentage.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Porcentaje de Asignación (%)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => percentage = double.tryParse(value) ?? 100.0,
                ),
                const SizedBox(height: 16),

                // Método - Cambiado a usar int en lugar de String
                DropdownButtonFormField<int>(
                  value: method,
                  decoration: const InputDecoration(
                    labelText: 'Método de Asignación',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: METODO_PROPORCIONAL, child: Text('Proporcional')),
                    DropdownMenuItem(value: METODO_MANUAL, child: Text('Manual')),
                    DropdownMenuItem(value: METODO_AUTOMATICO, child: Text('Automático')),
                  ],
                  onChanged: (value) => setDialogState(() => method = value ?? METODO_PROPORCIONAL),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selectedCostType != null && selectedCostCenter != null
                  ? () => Navigator.pop(context, true)
                  : null,
              child: Text(assignment == null ? 'Crear' : 'Actualizar'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final assignmentData = {
        'id_tipo_costo': selectedCostType!,
        'id_centro_costo': selectedCostCenter!,
        'id_producto': selectedProduct,
        'porcentaje_asignacion': percentage,
        'metodo_asignacion': method, // Ahora es int
      };

      bool success;
      if (assignment == null) {
        success = await _financialService.createCostAssignment(assignmentData);
      } else {
        success = await _financialService.updateCostAssignment(assignment['id'], assignmentData);
      }

      if (success) {
        _showSuccess(assignment == null ? 'Asignación creada exitosamente' : 'Asignación actualizada exitosamente');
        _loadData();
      } else {
        _showError('Error ${assignment == null ? 'creando' : 'actualizando'} la asignación');
      }
    }
  }

  Future<void> _deleteAssignment(Map<String, dynamic> assignment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Está seguro de eliminar esta asignación de costo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _financialService.deleteCostAssignment(assignment['id']);
      if (success) {
        _showSuccess('Asignación eliminada exitosamente');
        _loadData();
      } else {
        _showError('Error eliminando la asignación');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Asignaciones de Costos'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header con estadísticas
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Total Asignaciones',
                          value: _assignments.length.toString(),
                          icon: Icons.assignment,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          title: 'Tipos de Costo',
                          value: _costTypes.length.toString(),
                          icon: Icons.category,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _StatCard(
                          title: 'Centros de Costo',
                          value: _costCenters.length.toString(),
                          icon: Icons.business,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de asignaciones
                Expanded(
                  child: _assignments.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No hay asignaciones configuradas'),
                              SizedBox(height: 8),
                              Text('Presiona + para crear la primera asignación'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _assignments.length,
                          itemBuilder: (context, index) {
                            final assignment = _assignments[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue[100],
                                  child: Text('${assignment['porcentaje_asignacion']?.toInt()}%'),
                                ),
                                title: Text(assignment['tipo_costo_nombre'] ?? 'Tipo de costo'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Centro: ${assignment['centro_costo_nombre'] ?? 'N/A'}'),
                                    if (assignment['producto_nombre'] != null)
                                      Text('Producto: ${assignment['producto_nombre']}'),
                                    Text('Método: ${_getMethodDisplayName(assignment['metodo_asignacion'])}'),
                                  ],
                                ),
                                trailing: PopupMenuButton(
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: ListTile(
                                        leading: Icon(Icons.edit),
                                        title: Text('Editar'),
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        leading: Icon(Icons.delete, color: Colors.red),
                                        title: Text('Eliminar'),
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showAssignmentDialog(assignment: assignment);
                                    } else if (value == 'delete') {
                                      _deleteAssignment(assignment);
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAssignmentDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
