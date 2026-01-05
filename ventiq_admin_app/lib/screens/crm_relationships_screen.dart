import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/store_selector_widget.dart';
import '../services/dashboard_service.dart';
import '../models/crm/crm_metrics.dart';
import '../utils/navigation_guard.dart';

class CRMRelationshipsScreen extends StatefulWidget {
  const CRMRelationshipsScreen({super.key});

  @override
  State<CRMRelationshipsScreen> createState() => _CRMRelationshipsScreenState();
}

class _CRMRelationshipsScreenState extends State<CRMRelationshipsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  CRMMetrics _crmMetrics = const CRMMetrics();

  bool _canCreateRelationship = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPermissions();
    _loadRelationshipsData();
  }

  Future<void> _loadPermissions() async {
    final canCreate = await NavigationGuard.canPerformAction(
      'crm.relationship.create',
    );
    if (!mounted) return;
    setState(() {
      _canCreateRelationship = canCreate;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRelationshipsData() async {
    setState(() => _isLoading = true);
    try {
      final metrics = await DashboardService.getCRMMetrics();
      setState(() {
        _crmMetrics = metrics;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading relationships data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relaciones Comerciales'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [AppBarStoreSelectorWidget(), SizedBox(width: 8)],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.handshake), text: 'Relaciones'),
            Tab(icon: Icon(Icons.history), text: 'Interacciones'),
            Tab(icon: Icon(Icons.trending_up), text: 'Oportunidades'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRelationshipsTab(),
          _buildInteractionsTab(),
          _buildOpportunitiesTab(),
        ],
      ),
      floatingActionButton:
          _canCreateRelationship
              ? FloatingActionButton(
                onPressed: () => _showAddRelationshipDialog(),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add, color: Colors.white),
              )
              : null,
    );
  }

  Widget _buildRelationshipsTab() {
    return RefreshIndicator(
      onRefresh: _loadRelationshipsData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRelationshipsOverview(),
            const SizedBox(height: 24),
            _buildRelationshipsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationshipsOverview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resumen de Relaciones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildOverviewCard(
                    'Total Contactos',
                    '${_crmMetrics.totalContactsCalculated}',
                    Icons.contacts,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOverviewCard(
                    'Score Relaciones',
                    '${_crmMetrics.relationshipScore.toStringAsFixed(1)}%',
                    Icons.trending_up,
                    _getScoreColor(_crmMetrics.relationshipScore),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildOverviewCard(
                    'Interacciones',
                    '${_crmMetrics.recentInteractions}',
                    Icons.chat,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOverviewCard(
                    'Oportunidades',
                    '${(_crmMetrics.totalContactsCalculated * 0.15).round()}',
                    Icons.star,
                    Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRelationshipsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Relaciones Activas',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 5, // Mock data
          itemBuilder: (context, index) => _buildRelationshipCard(index),
        ),
      ],
    );
  }

  Widget _buildRelationshipCard(int index) {
    final relationships = [
      {
        'name': 'Distribuidora Central',
        'type': 'Proveedor',
        'status': 'Activa',
        'score': 85,
        'lastInteraction': '2 días',
        'icon': Icons.factory,
        'color': Colors.orange,
      },
      {
        'name': 'Cliente Premium SA',
        'type': 'Cliente VIP',
        'status': 'Activa',
        'score': 92,
        'lastInteraction': '1 día',
        'icon': Icons.star,
        'color': Colors.amber,
      },
      {
        'name': 'Suministros del Norte',
        'type': 'Proveedor',
        'status': 'Pendiente',
        'score': 68,
        'lastInteraction': '1 semana',
        'icon': Icons.factory,
        'color': Colors.orange,
      },
      {
        'name': 'Empresa Familiar',
        'type': 'Cliente',
        'status': 'Activa',
        'score': 78,
        'lastInteraction': '3 días',
        'icon': Icons.people,
        'color': Colors.blue,
      },
      {
        'name': 'Logística Express',
        'type': 'Proveedor',
        'status': 'Activa',
        'score': 88,
        'lastInteraction': '1 día',
        'icon': Icons.local_shipping,
        'color': Colors.green,
      },
    ];

    final relationship = relationships[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (relationship['color'] as Color).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            relationship['icon'] as IconData,
            color: relationship['color'] as Color,
            size: 24,
          ),
        ),
        title: Text(
          relationship['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(relationship['type'] as String),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        relationship['status'] == 'Activa'
                            ? Colors.green.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    relationship['status'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      color:
                          relationship['status'] == 'Activa'
                              ? Colors.green
                              : Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Score: ${relationship['score']}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: _getScoreColor(relationship['score'] as int),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Última interacción',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
            Text(
              relationship['lastInteraction'] as String,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        onTap: () => _showRelationshipDetail(relationship),
      ),
    );
  }

  Widget _buildInteractionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Historial de Interacciones',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 8,
            itemBuilder: (context, index) => _buildInteractionCard(index),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionCard(int index) {
    final interactions = [
      {
        'type': 'Llamada',
        'contact': 'Distribuidora Central',
        'description': 'Negociación de precios para Q1',
        'date': 'Hoy, 14:30',
        'icon': Icons.phone,
        'color': Colors.green,
      },
      {
        'type': 'Reunión',
        'contact': 'Cliente Premium SA',
        'description': 'Presentación de nuevos productos',
        'date': 'Ayer, 10:00',
        'icon': Icons.meeting_room,
        'color': Colors.blue,
      },
      {
        'type': 'Email',
        'contact': 'Suministros del Norte',
        'description': 'Seguimiento de pedido pendiente',
        'date': 'Hace 2 días',
        'icon': Icons.email,
        'color': Colors.orange,
      },
    ];

    final interaction = interactions[index % interactions.length];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (interaction['color'] as Color).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            interaction['icon'] as IconData,
            color: interaction['color'] as Color,
            size: 20,
          ),
        ),
        title: Text(
          interaction['contact'] as String,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(interaction['description'] as String),
            const SizedBox(height: 4),
            Text(
              interaction['date'] as String,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Chip(
          label: Text(
            interaction['type'] as String,
            style: const TextStyle(fontSize: 10),
          ),
          backgroundColor: (interaction['color'] as Color).withOpacity(0.1),
        ),
      ),
    );
  }

  Widget _buildOpportunitiesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Oportunidades de Negocio',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            itemBuilder: (context, index) => _buildOpportunityCard(index),
          ),
        ],
      ),
    );
  }

  Widget _buildOpportunityCard(int index) {
    final opportunities = [
      {
        'title': 'Expansión de Catálogo',
        'contact': 'Distribuidora Central',
        'value': '\$15,000',
        'probability': 85,
        'stage': 'Negociación',
        'color': Colors.green,
      },
      {
        'title': 'Contrato Anual',
        'contact': 'Cliente Premium SA',
        'value': '\$25,000',
        'probability': 70,
        'stage': 'Propuesta',
        'color': Colors.blue,
      },
      {
        'title': 'Nuevo Proveedor',
        'contact': 'Suministros del Norte',
        'value': '\$8,000',
        'probability': 45,
        'stage': 'Prospecto',
        'color': Colors.orange,
      },
      {
        'title': 'Servicios Premium',
        'contact': 'Empresa Familiar',
        'value': '\$12,000',
        'probability': 60,
        'stage': 'Calificación',
        'color': Colors.purple,
      },
    ];

    final opportunity = opportunities[index];

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
                  child: Text(
                    opportunity['title'] as String,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (opportunity['color'] as Color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    opportunity['stage'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      color: opportunity['color'] as Color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              opportunity['contact'] as String,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Valor Estimado',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        opportunity['value'] as String,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Probabilidad',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        '${opportunity['probability']}%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: opportunity['color'] as Color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (opportunity['probability'] as int) / 100,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                opportunity['color'] as Color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getScoreColor(dynamic score) {
    final scoreValue = score is int ? score.toDouble() : score as double;
    if (scoreValue >= 80) return Colors.green;
    if (scoreValue >= 60) return Colors.orange;
    return Colors.red;
  }

  void _showRelationshipDetail(Map<String, dynamic> relationship) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(relationship['name'] as String),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tipo: ${relationship['type']}'),
                Text('Estado: ${relationship['status']}'),
                Text('Score: ${relationship['score']}%'),
                Text('Última interacción: ${relationship['lastInteraction']}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // TODO: Navegar a detalle completo
                },
                child: const Text('Ver Detalle'),
              ),
            ],
          ),
    );
  }

  void _showAddRelationshipDialog() {
    if (!_canCreateRelationship) {
      NavigationGuard.showActionDeniedMessage(
        context,
        'Agregar relación comercial',
      );
      return;
    }
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Nueva Relación'),
            content: const Text(
              'Funcionalidad para agregar nueva relación comercial.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Agregar'),
              ),
            ],
          ),
    );
  }
}
