import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/financial_service.dart';

class CostAssignmentsManagementScreen extends StatefulWidget {
  const CostAssignmentsManagementScreen({super.key});

  @override
  State<CostAssignmentsManagementScreen> createState() => _CostAssignmentsManagementScreenState();
}

class _CostAssignmentsManagementScreenState extends State<CostAssignmentsManagementScreen> {
  final FinancialService _financialService = FinancialService();
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _costTypes = [];
  List<Map<String, dynamic>> _costCenters = [];
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final assignments = await _financialService.getCostAssignments();
      final costTypes = await _financialService.getCostTypes();
      final costCenters = await _financialService.getCostCenters();
      final products = await _financialService.getProducts();
      
      // Debug: Verificar datos cargados
      print('🏢 Centros de costo cargados: ${costCenters.length}');
      print('📊 Tipos de costo cargados: ${costTypes.length}');
      print('📦 Productos cargados: ${products.length}');
      
      if (costCenters.isEmpty) {
        print('⚠️ No se encontraron centros de costo');
      } else {
        print('✅ Centros de costo disponibles:');
        for (var center in costCenters) {
          print('  - ID: ${center['id']}, Nombre: ${center['denominacion']}');
        }
      }
      
      setState(() {
        _assignments = assignments;
        _costTypes = costTypes;
        _costCenters = costCenters;
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error cargando datos: $e');
      setState(() => _isLoading = false);
      _showErrorSnackBar('Error cargando datos: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Asignaciones de Costos',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.warning,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading ? _buildLoadingState() : _buildContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAssignmentDialog(),
        backgroundColor: AppColors.warning,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.warning),
          SizedBox(height: 16),
          Text(
            'Cargando asignaciones...',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_assignments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay asignaciones de costos',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toca el botón + para crear una nueva asignación',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _assignments.length,
      itemBuilder: (context, index) {
        final assignment = _assignments[index];
        return _buildAssignmentCard(assignment);
      },
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> assignment) {
    final percentage = (assignment['porcentaje_asignacion'] as num?)?.toDouble() ?? 0.0;
    final method = assignment['metodo_asignacion'] as int? ?? 1;
    final methodText = method == 1 ? 'Automático' : method == 2 ? 'Manual' : 'Proporcional';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
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
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.assignment,
                    color: AppColors.warning,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment['tipo_costo_nombre'] ?? 'Tipo de Costo',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (assignment['centro_costo_nombre'] != null)
                        Text(
                          'Centro: ${assignment['centro_costo_nombre']}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _showAssignmentDialog(assignment: assignment);
                        break;
                      case 'delete':
                        _showDeleteConfirmation(assignment);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Editar'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Eliminar', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    'Porcentaje',
                    '${percentage.toStringAsFixed(1)}%',
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    'Método',
                    methodText,
                    Colors.green,
                  ),
                ),
              ],
            ),
            if (assignment['producto_nombre'] != null) ...[
              const SizedBox(height: 8),
              _buildInfoChip(
                'Producto',
                assignment['producto_nombre'],
                Colors.orange,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _showAssignmentDialog({Map<String, dynamic>? assignment}) {
    final isEditing = assignment != null;
    final formKey = GlobalKey<FormState>();
    
    // Debug: Verificar estado de los datos al abrir el diálogo
    print('🔧 Abriendo diálogo de asignación:');
    print('  - Centros de costo disponibles: ${_costCenters.length}');
    print('  - Tipos de costo disponibles: ${_costTypes.length}');
    print('  - Productos disponibles: ${_products.length}');
    
    int? selectedCostTypeId = assignment?['id_tipo_costo'];
    int? selectedCostCenterId = assignment?['id_centro_costo'];
    int? selectedProductId = assignment?['id_producto'];
    double percentage = (assignment?['porcentaje_asignacion'] as num?)?.toDouble() ?? 100.0;
    int method = assignment?['metodo_asignacion'] ?? 1;
    
    final percentageController = TextEditingController(text: percentage.toString());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar Asignación' : 'Nueva Asignación'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Tipo de Costo
                  DropdownButtonFormField<int>(
                    value: selectedCostTypeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Costo *',
                      border: OutlineInputBorder(),
                    ),
                    items: _costTypes.map((type) {
                      return DropdownMenuItem<int>(
                        value: type['id'],
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.6,
                          child: Text(
                            type['denominacion'] ?? 'Sin nombre',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedCostTypeId = value;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Selecciona un tipo de costo';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Centro de Costo
                  DropdownButtonFormField<int>(
                    value: selectedCostCenterId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Centro de Costo',
                      border: const OutlineInputBorder(),
                      helperText: _costCenters.isEmpty ? 'No hay centros de costo disponibles' : null,
                      helperStyle: TextStyle(color: AppColors.error),
                    ),
                    items: _costCenters.isEmpty 
                      ? [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('No hay centros disponibles'),
                          ),
                        ]
                      : [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('Sin centro específico'),
                          ),
                          ..._costCenters.map((center) {
                            return DropdownMenuItem<int>(
                              value: center['id'],
                              child: SizedBox(
                                width: MediaQuery.of(context).size.width * 0.6,
                                child: Text(
                                  center['denominacion'] ?? 'Sin nombre',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                    onChanged: _costCenters.isEmpty ? null : (value) {
                      setDialogState(() {
                        selectedCostCenterId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Producto (opcional)
                  DropdownButtonFormField<int>(
                    value: selectedProductId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Producto (Opcional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('Todos los productos'),
                      ),
                      ..._products.map((product) {
                        return DropdownMenuItem<int>(
                          value: product['id'],
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.6,
                            child: Text(
                              product['denominacion'] ?? 'Sin nombre',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedProductId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Porcentaje de Asignación
                  TextFormField(
                    controller: percentageController,
                    decoration: const InputDecoration(
                      labelText: 'Porcentaje de Asignación *',
                      border: OutlineInputBorder(),
                      suffixText: '%',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingresa el porcentaje';
                      }
                      final percentage = double.tryParse(value);
                      if (percentage == null || percentage <= 0 || percentage > 100) {
                        return 'Ingresa un porcentaje válido (1-100)';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      percentage = double.tryParse(value) ?? 100.0;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Método de Asignación
                  DropdownButtonFormField<int>(
                    value: method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Método de Asignación *',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Automático')),
                      DropdownMenuItem(value: 2, child: Text('Manual')),
                      DropdownMenuItem(value: 3, child: Text('Proporcional')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        method = value ?? 1;
                      });
                    },
                  ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    final assignmentData = {
                      'id_tipo_costo': selectedCostTypeId,
                      'id_centro_costo': selectedCostCenterId,
                      'id_producto': selectedProductId,
                      'porcentaje_asignacion': percentage,
                      'metodo_asignacion': method,
                    };

                    if (isEditing) {
                      await _financialService.updateCostAssignment(
                        assignment['id'],
                        assignmentData,
                      );
                      _showSuccessSnackBar('Asignación actualizada exitosamente');
                    } else {
                      await _financialService.createCostAssignment(assignmentData);
                      _showSuccessSnackBar('Asignación creada exitosamente');
                    }

                    Navigator.of(context).pop();
                    _loadData();
                  } catch (e) {
                    _showErrorSnackBar('Error: $e');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              child: Text(isEditing ? 'Actualizar' : 'Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> assignment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la asignación del tipo "${assignment['tipo_costo_nombre']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _financialService.deleteCostAssignment(assignment['id']);
                Navigator.of(context).pop();
                _showSuccessSnackBar('Asignación eliminada exitosamente');
                _loadData();
              } catch (e) {
                Navigator.of(context).pop();
                _showErrorSnackBar('Error eliminando asignación: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
