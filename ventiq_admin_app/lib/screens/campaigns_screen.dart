import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../widgets/marketing_menu_widget.dart';
import '../widgets/store_selector_widget.dart';
import '../services/marketing_service.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  final MarketingService _marketingService = MarketingService();
  List<Map<String, dynamic>> _campaigns = [];
  bool _isLoading = true;
  Map<String, dynamic> _dashboardStats = {};

  @override
  void initState() {
    super.initState();
    _loadCampaigns();
  }

  Future<void> _loadCampaigns() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final campaigns = await _marketingService.listCampaigns();
      final stats = await _marketingService.getDashboardSummary();
      
      setState(() {
        _campaigns = campaigns;
        _dashboardStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading campaigns: $e');
      setState(() {
        _campaigns = _getMockCampaigns();
        _dashboardStats = _getMockStats();
        _isLoading = false;
      });
    }
  }

  // Mock data basado en app_mkt_campanas
  List<Map<String, dynamic>> _getMockCampaigns() {
    return [
    {
      'id': 1,
      'nombre': 'Campaña Black Friday 2024',
      'descripcion': 'Promociones especiales para el Black Friday con descuentos hasta 70%',
      'fecha_inicio': DateTime(2024, 11, 25),
      'fecha_fin': DateTime(2024, 11, 30),
      'presupuesto': 150000.0,
      'presupuesto_usado': 89500.0,
      'estado': true,
      'tipo_campana': 'Descuentos',
      'alcance': 12500,
      'conversiones': 1850,
      'roi': 3.2,
    },
    {
      'id': 2,
      'nombre': 'Lanzamiento Productos Verano',
      'descripcion': 'Campaña para promocionar nueva línea de productos de verano',
      'fecha_inicio': DateTime(2024, 12, 1),
      'fecha_fin': DateTime(2024, 12, 31),
      'presupuesto': 80000.0,
      'presupuesto_usado': 45200.0,
      'estado': true,
      'tipo_campana': 'Lanzamiento',
      'alcance': 8900,
      'conversiones': 1120,
      'roi': 2.8,
    },
    {
      'id': 3,
      'nombre': 'Retención Clientes Premium',
      'descripcion': 'Campaña dirigida a mantener y fidelizar clientes premium',
      'fecha_inicio': DateTime(2024, 10, 1),
      'fecha_fin': DateTime(2024, 10, 31),
      'presupuesto': 50000.0,
      'presupuesto_usado': 50000.0,
      'estado': false,
      'tipo_campana': 'Fidelización',
      'alcance': 2340,
      'conversiones': 890,
      'roi': 4.1,
    },
    {
      'id': 4,
      'nombre': 'Navidad y Año Nuevo',
      'descripcion': 'Campaña festiva con promociones especiales para las fiestas',
      'fecha_inicio': DateTime(2024, 12, 15),
      'fecha_fin': DateTime(2025, 1, 10),
      'presupuesto': 200000.0,
      'presupuesto_usado': 0.0,
      'estado': false,
      'tipo_campana': 'Estacional',
      'alcance': 0,
      'conversiones': 0,
      'roi': 0.0,
    },
    ];
  }

  Map<String, dynamic> _getMockStats() {
    return {
      'total_campanas': 4,
      'campanas_activas': 2,
    };
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Campañas'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [
          AppBarStoreSelectorWidget(),
          MarketingMenuWidget(),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadCampaigns,
              child: Column(
                children: [
                  _buildStatsCards(),
                  Expanded(
                    child: _buildCampaignsList(),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateCampaignDialog(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatsCards() {
    final activeCampaigns = _dashboardStats['campanas_activas'] ?? _campaigns.where((c) => c['estado'] == true).length;
    final totalCampaigns = _dashboardStats['total_campanas'] ?? _campaigns.length;
    final totalBudget = _campaigns.fold<double>(0, (sum, c) => sum + (c['presupuesto'] ?? 0.0));
    final usedBudget = _campaigns.fold<double>(0, (sum, c) => sum + (c['presupuesto_usado'] ?? 0.0));
    final totalReach = _campaigns.fold<int>(0, (sum, c) => sum + ((c['alcance'] ?? 0) as int));

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total',
              totalCampaigns.toString(),
              Icons.campaign,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Activas',
              activeCampaigns.toString(),
              Icons.play_circle,
              Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Presupuesto',
              '\$${NumberFormat('#,###').format(totalBudget)}',
              Icons.attach_money,
              Colors.purple,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Usado',
              '\$${NumberFormat('#,###').format(usedBudget)}',
              Icons.money_off,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Alcance',
              NumberFormat('#,###').format(totalReach),
              Icons.people,
              Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampaignsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _campaigns.length,
      itemBuilder: (context, index) {
        final campaign = _campaigns[index];
        return _buildCampaignCard(campaign);
      },
    );
  }

  Widget _buildCampaignCard(Map<String, dynamic> campaign) {
    final isActive = campaign['estado'] as bool;
    final startDate = campaign['fecha_inicio'] as DateTime;
    final endDate = campaign['fecha_fin'] as DateTime;
    final now = DateTime.now();
    final isOngoing = now.isAfter(startDate) && now.isBefore(endDate) && isActive;
    final budgetUsedPercent = campaign['presupuesto'] > 0 
        ? (campaign['presupuesto_usado'] / campaign['presupuesto'] * 100).round()
        : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        campaign['nombre'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        campaign['descripcion'],
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(isActive, isOngoing),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip(
                  Icons.category,
                  campaign['tipo_campana'],
                  Colors.blue,
                ),
                const SizedBox(width: 8),
                _buildInfoChip(
                  Icons.calendar_today,
                  '${DateFormat('dd/MM').format(startDate)} - ${DateFormat('dd/MM').format(endDate)}',
                  Colors.grey,
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
                        'Presupuesto: \$${NumberFormat('#,###').format(campaign['presupuesto'])}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: budgetUsedPercent / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          budgetUsedPercent > 80 ? Colors.red : Colors.green,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Usado: $budgetUsedPercent% (\$${NumberFormat('#,###').format(campaign['presupuesto_usado'])})',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ROI: ${campaign['roi']}x',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: campaign['roi'] > 2 ? Colors.green : Colors.orange,
                      ),
                    ),
                    Text(
                      'Alcance: ${NumberFormat('#,###').format(campaign['alcance'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      'Conversiones: ${NumberFormat('#,###').format(campaign['conversiones'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showCampaignDetails(campaign),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Ver detalles'),
                ),
                TextButton.icon(
                  onPressed: () => _editCampaign(campaign),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Editar'),
                ),
                TextButton.icon(
                  onPressed: () => _toggleCampaignStatus(campaign),
                  icon: Icon(
                    isActive ? Icons.pause : Icons.play_arrow,
                    size: 16,
                  ),
                  label: Text(isActive ? 'Pausar' : 'Activar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isActive, bool isOngoing) {
    Color color;
    String text;

    if (isOngoing) {
      color = Colors.green;
      text = 'En curso';
    } else if (isActive) {
      color = Colors.blue;
      text = 'Programada';
    } else {
      color = Colors.grey;
      text = 'Pausada';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }

  void _showCreateCampaignDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final budgetController = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime? endDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nueva Campaña'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la campaña',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: budgetController,
                  decoration: const InputDecoration(
                    labelText: 'Presupuesto',
                    border: OutlineInputBorder(),
                    prefixText: '\$',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        title: const Text('Fecha inicio'),
                        subtitle: Text(DateFormat('dd/MM/yyyy').format(startDate)),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: startDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setDialogState(() {
                              startDate = date;
                            });
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        title: const Text('Fecha fin'),
                        subtitle: Text(endDate != null ? DateFormat('dd/MM/yyyy').format(endDate!) : 'Sin fecha'),
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: endDate ?? startDate.add(const Duration(days: 30)),
                            firstDate: startDate,
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          setDialogState(() {
                            endDate = date;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty || descriptionController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor complete todos los campos'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  final budget = double.tryParse(budgetController.text) ?? 0.0;
                  await _marketingService.createCampaign(
                    storeId: 1, // Will be replaced by StoreSelectorService
                    nombre: nameController.text,
                    descripcion: descriptionController.text,
                    idTipoCampana: 1, // Default campaign type
                    fechaInicio: startDate,
                    fechaFin: endDate,
                    presupuesto: budget,
                  );

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Campaña creada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadCampaigns();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al crear campaña: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCampaignDetails(Map<String, dynamic> campaign) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(campaign['nombre']),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Descripción: ${campaign['descripcion']}'),
              const SizedBox(height: 8),
              Text('Tipo: ${campaign['tipo_campana']}'),
              const SizedBox(height: 8),
              Text('Fecha inicio: ${DateFormat('dd/MM/yyyy').format(campaign['fecha_inicio'])}'),
              const SizedBox(height: 8),
              Text('Fecha fin: ${DateFormat('dd/MM/yyyy').format(campaign['fecha_fin'])}'),
              const SizedBox(height: 8),
              Text('Presupuesto: \$${NumberFormat('#,###').format(campaign['presupuesto'])}'),
              const SizedBox(height: 8),
              Text('Presupuesto usado: \$${NumberFormat('#,###').format(campaign['presupuesto_usado'])}'),
              const SizedBox(height: 8),
              Text('Alcance: ${NumberFormat('#,###').format(campaign['alcance'])} personas'),
              const SizedBox(height: 8),
              Text('Conversiones: ${NumberFormat('#,###').format(campaign['conversiones'])}'),
              const SizedBox(height: 8),
              Text('ROI: ${campaign['roi']}x'),
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

  void _editCampaign(Map<String, dynamic> campaign) async {
    final nameController = TextEditingController(text: campaign['nombre']);
    final descriptionController = TextEditingController(text: campaign['descripcion']);
    final budgetController = TextEditingController(text: campaign['presupuesto']?.toString() ?? '');
    DateTime startDate = campaign['fecha_inicio'] ?? DateTime.now();
    DateTime? endDate = campaign['fecha_fin'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Campaña'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la campaña',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: budgetController,
                  decoration: const InputDecoration(
                    labelText: 'Presupuesto',
                    border: OutlineInputBorder(),
                    prefixText: '\$',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final budget = double.tryParse(budgetController.text) ?? 0.0;
                  await _marketingService.updateCampaign(
                    id: campaign['id'],
                    nombre: nameController.text,
                    descripcion: descriptionController.text,
                    idTipoCampana: campaign['id_tipo_campana'] ?? 1,
                    fechaInicio: startDate,
                    fechaFin: endDate,
                    presupuesto: budget,
                  );

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Campaña actualizada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadCampaigns();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al actualizar campaña: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Actualizar'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleCampaignStatus(Map<String, dynamic> campaign) async {
    try {
      final newStatus = !(campaign['estado'] ?? false);
      await _marketingService.updateCampaign(
        id: campaign['id'],
        nombre: campaign['nombre'],
        descripcion: campaign['descripcion'],
        idTipoCampana: campaign['id_tipo_campana'] ?? 1,
        fechaInicio: campaign['fecha_inicio'] ?? DateTime.now(),
        fechaFin: campaign['fecha_fin'],
        presupuesto: campaign['presupuesto']?.toDouble(),
        estado: newStatus ? 1 : 0,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus 
              ? 'Campaña activada exitosamente'
              : 'Campaña pausada exitosamente'
          ),
          backgroundColor: Colors.green,
        ),
      );
      _loadCampaigns();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cambiar estado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
