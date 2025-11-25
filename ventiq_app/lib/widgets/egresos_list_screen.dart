import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';
import '../utils/app_snackbar.dart';

class EgresosListScreen extends StatefulWidget {
  final List<Expense> expenses;
  final double totalEgresos;
  final double egresosEfectivo;
  final double egresosTransferencias;

  const EgresosListScreen({
    Key? key,
    required this.expenses,
    required this.totalEgresos,
    required this.egresosEfectivo,
    required this.egresosTransferencias,
  }) : super(key: key);

  @override
  State<EgresosListScreen> createState() => _EgresosListScreenState();
}

class _EgresosListScreenState extends State<EgresosListScreen> {
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  List<Expense> _filteredExpenses = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _filteredExpenses = widget.expenses;
  }

  Future<void> _refreshExpenses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
      
      List<Expense> expenses = [];
      
      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado, cargando egresos desde cache...');
        expenses = await _loadExpensesOffline();
      } else {
        print('🌐 Modo online, obteniendo egresos desde servidor...');
        expenses = await TurnoService.getEgresosEnriquecidos();
      }

      setState(() {
        _filteredExpenses = expenses;
        _isLoading = false;
      });

      print('✅ Egresos actualizados: ${expenses.length}');
    } catch (e) {
      print('❌ Error actualizando egresos: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        AppSnackBar.showPersistent(
          context,
          message: 'Error al actualizar egresos: $e',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<List<Expense>> _loadExpensesOffline() async {
    try {
      print('📱 Cargando egresos desde cache offline...');
      
      // Obtener egresos desde cache específico
      final egresosData = await _userPreferencesService.getEgresosCache();
      
      if (egresosData.isNotEmpty) {
        final expenses = egresosData.map((expenseJson) {
          return Expense(
            idEgreso: expenseJson['id_egreso'] ?? 0,
            montoEntrega: (expenseJson['monto_entrega'] ?? 0.0).toDouble(),
            motivoEntrega: expenseJson['motivo_entrega'] ?? 'Sin motivo',
            nombreRecibe: expenseJson['nombre_recibe'] ?? 'Sin nombre',
            nombreAutoriza: expenseJson['nombre_autoriza'] ?? 'Sin autorización',
            fechaEntrega: expenseJson['fecha_entrega'] != null
                ? DateTime.parse(expenseJson['fecha_entrega'])
                : DateTime.now(),
            idMedioPago: expenseJson['id_medio_pago'],
            turnoEstado: expenseJson['turno_estado'] ?? 1,
            medioPago: expenseJson['medio_pago'],
            esDigital: expenseJson['es_digital'] ?? false,
          );
        }).toList();
        
        print('✅ Egresos cargados desde cache offline: ${expenses.length}');
        return expenses;
      } else {
        print('ℹ️ No hay egresos en cache offline');
        return [];
      }
    } catch (e) {
      print('❌ Error cargando egresos offline: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Lista de Egresos',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshExpenses,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          // Resumen de egresos
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey, width: 0.2),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.money_off,
                      color: Colors.red[600],
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Egresos del Turno',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Salidas de dinero registradas durante el turno',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                // Resumen simple
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSimpleStat(
                      'Total',
                      '\$${widget.totalEgresos.toStringAsFixed(0)}',
                      Colors.red[600]!,
                    ),
                    _buildSimpleStat(
                      'Efectivo',
                      '\$${widget.egresosEfectivo.toStringAsFixed(0)}',
                      Colors.orange[600]!,
                    ),
                    _buildSimpleStat(
                      'Digital',
                      '\$${widget.egresosTransferencias.toStringAsFixed(0)}',
                      Colors.blue[600]!,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista de egresos
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Cargando egresos...'),
                      ],
                    ),
                  )
                : _filteredExpenses.isEmpty
                    ? _buildEmptyState()
                    : _buildSimpleExpensesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.money_off_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay egresos registrados',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Los egresos aparecerán aquí cuando se registren',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleExpensesList() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _filteredExpenses.length,
        itemBuilder: (context, index) {
          final expense = _filteredExpenses[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: InkWell(
              onTap: () => _showExpenseDetails(expense),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          expense.motivoEntrega,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1F2937),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '\$${expense.montoEntrega.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        _formatTime(expense.fechaEntrega),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.payment, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        expense.medioPago ?? 'N/A',
                        style: TextStyle(
                          fontSize: 12,
                          color: expense.esDigital == false
                              ? Colors.green[700]
                              : Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person, size: 12, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Recibe: ${expense.nombreRecibe}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (expense.nombreAutoriza.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.verified_user,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Autoriza: ${expense.nombreAutoriza}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  void _showExpenseDetails(Expense expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.8,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
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
                        'Detalles del Egreso #${expense.idEgreso}',
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
                    _buildDetailRow('ID Egreso:', '${expense.idEgreso}'),
                    _buildDetailRow('Fecha:', _formatDate(expense.fechaEntrega)),
                    _buildDetailRow('Hora:', _formatTime(expense.fechaEntrega)),
                    _buildDetailRow('Monto:', '\$${expense.montoEntrega.toStringAsFixed(2)}'),
                    _buildDetailRow('Método de pago:', expense.medioPago ?? 'N/A'),
                    _buildDetailRow(
                      'Tipo:',
                      expense.esDigital == true ? 'Digital/Transferencia' : 'Efectivo',
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'Detalles del Egreso:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow('Motivo:', expense.motivoEntrega),
                    _buildDetailRow('Quien autoriza:', expense.nombreAutoriza),
                    _buildDetailRow('Quien recibe:', expense.nombreRecibe),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDate);

    if (difference.inDays == 0) {
      return 'Hoy ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Ayer ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} días atrás';
    } else {
      return '${localDate.day.toString().padLeft(2, '0')}/${localDate.month.toString().padLeft(2, '0')}/${localDate.year}';
    }
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }
}
