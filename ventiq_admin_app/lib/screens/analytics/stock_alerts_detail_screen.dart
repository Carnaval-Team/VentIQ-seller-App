import 'package:flutter/material.dart';
import '../../models/analytics/inventory_metrics.dart';
import '../../services/analytics_service.dart';
import '../../widgets/analytics/metric_card.dart';

class StockAlertsDetailScreen extends StatefulWidget {
  final String? initialFilter; // 'critical', 'warning', 'all'

  const StockAlertsDetailScreen({super.key, this.initialFilter});

  @override
  State<StockAlertsDetailScreen> createState() =>
      _StockAlertsDetailScreenState();
}

class _StockAlertsDetailScreenState extends State<StockAlertsDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<StockAlert> _allAlerts = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';
  Map<String, int> _alertCounts = {
    'critical': 0,
    'warning': 0,
    'info': 0,
    'all': 0,
  };

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter ?? 'all';
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: _getInitialTabIndex(),
    );
    _loadAlerts();
  }

  int _getInitialTabIndex() {
    switch (_selectedFilter) {
      case 'critical':
        return 0;
      case 'warning':
        return 1;
      case 'info':
        return 2;
      default:
        return 3;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);

    try {
      final stockAlerts = await AnalyticsService.getStockAlerts();
      // Calcular conteos por severidad
      final counts = <String, int>{
        'critical': stockAlerts.where((a) => a.severity == 'critical').length,
        'warning': stockAlerts.where((a) => a.severity == 'warning').length,
        'info': stockAlerts.where((a) => a.severity == 'info').length,
        'all': stockAlerts.length,
      };

      setState(() {
        _allAlerts = stockAlerts;
        _alertCounts = counts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando alertas: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas de Stock'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        bottom:
            _isLoading
                ? null
                : TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.white,
                  tabs: [
                    Tab(
                      text: 'Críticas',
                      icon: Badge(
                        label: Text('${_alertCounts['critical']}'),
                        child: const Icon(Icons.error),
                      ),
                    ),
                    Tab(
                      text: 'Advertencias',
                      icon: Badge(
                        label: Text('${_alertCounts['warning']}'),
                        child: const Icon(Icons.warning),
                      ),
                    ),
                    Tab(
                      text: 'Información',
                      icon: Badge(
                        label: Text('${_alertCounts['info']}'),
                        child: const Icon(Icons.info),
                      ),
                    ),
                    Tab(
                      text: 'Todas',
                      icon: Badge(
                        label: Text('${_alertCounts['all']}'),
                        child: const Icon(Icons.list),
                      ),
                    ),
                  ],
                ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAlerts),
        ],
      ),
      body: _isLoading ? _buildLoadingState() : _buildContent(),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Cargando alertas de stock...'),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_allAlerts.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        _buildSummaryCards(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildAlertsList('critical'),
              _buildAlertsList('warning'),
              _buildAlertsList('info'),
              _buildAlertsList('all'),
            ],
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
          Icon(Icons.check_circle, size: 64, color: Colors.green[300]),
          const SizedBox(height: 16),
          Text(
            'No hay alertas de stock',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Todo está funcionando correctamente',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: MetricCard(
              title: 'Total Alertas',
              value: _alertCounts['all'].toString(),
              icon: Icons.notifications,
              color: Colors.blue,
              subtitle: 'activas',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Críticas',
              value: _alertCounts['critical'].toString(),
              icon: Icons.error,
              color: Colors.red,
              subtitle: 'urgentes',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Advertencias',
              value: _alertCounts['warning'].toString(),
              icon: Icons.warning,
              color: Colors.orange,
              subtitle: 'revisar',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsList(String severity) {
    List<StockAlert> filteredAlerts;

    if (severity == 'all') {
      filteredAlerts = _allAlerts;
    } else {
      filteredAlerts =
          _allAlerts.where((alert) => alert.severity == severity).toList();
    }

    if (filteredAlerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 48, color: Colors.green[300]),
            const SizedBox(height: 16),
            Text(
              'No hay alertas ${_getSeverityLabel(severity).toLowerCase()}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredAlerts.length,
        itemBuilder: (context, index) {
          final alert = filteredAlerts[index];
          return _buildAlertCard(alert);
        },
      ),
    );
  }

  Widget _buildAlertCard(StockAlert alert) {
    final alertColor = _getAlertColor(alert.severity);
    final alertIcon = _getAlertIcon(alert.alertType);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _showAlertDetails(alert),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: alertColor, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: alertColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(alertIcon, color: alertColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.productName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: alertColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                alert.severityLabel,
                                style: TextStyle(
                                  color: alertColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              alert.alertTypeLabel,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Stock: ${alert.currentStock.toInt()}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: alertColor,
                        ),
                      ),
                      if (alert.minStock != null)
                        Text(
                          'Mín: ${alert.minStock!.toInt()}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                alert.message,
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(alert.createdAt),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _resolveAlert(alert),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Resolver'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _showAlertDetails(alert),
                        icon: const Icon(Icons.info, size: 16),
                        label: const Text('Detalles'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
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

  void _showAlertDetails(StockAlert alert) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            builder:
                (context, scrollController) => Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _getAlertColor(
                                alert.severity,
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getAlertIcon(alert.alertType),
                              color: _getAlertColor(alert.severity),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  alert.productName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'ID: ${alert.productId}',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      _buildDetailRow('Tipo de Alerta', alert.alertTypeLabel),
                      _buildDetailRow('Severidad', alert.severityLabel),
                      _buildDetailRow(
                        'Stock Actual',
                        '${alert.currentStock.toInt()} unidades',
                      ),
                      if (alert.minStock != null)
                        _buildDetailRow(
                          'Stock Mínimo',
                          '${alert.minStock!.toInt()} unidades',
                        ),
                      if (alert.maxStock != null)
                        _buildDetailRow(
                          'Stock Máximo',
                          '${alert.maxStock!.toInt()} unidades',
                        ),
                      _buildDetailRow(
                        'Fecha de Creación',
                        _formatDate(alert.createdAt),
                      ),
                      _buildDetailRow(
                        'Estado',
                        alert.isActive ? 'Activa' : 'Resuelta',
                      ),

                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mensaje:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(alert.message),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _resolveAlert(alert);
                              },
                              icon: const Icon(Icons.check),
                              label: const Text('Resolver Alerta'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                              label: const Text('Cerrar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _resolveAlert(StockAlert alert) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Resolver Alerta'),
            content: Text(
              '¿Estás seguro de que quieres marcar como resuelta la alerta para "${alert.productName}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // TODO: Implementar resolución de alerta
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Alerta marcada como resuelta'),
                    ),
                  );
                  _loadAlerts(); // Recargar alertas
                },
                child: const Text('Resolver'),
              ),
            ],
          ),
    );
  }

  Color _getAlertColor(String severity) {
    switch (severity) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'info':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getAlertIcon(String alertType) {
    switch (alertType) {
      case 'out_of_stock':
        return Icons.remove_circle;
      case 'low_stock':
        return Icons.warning;
      case 'overstock':
        return Icons.add_circle;
      case 'expiring':
        return Icons.schedule;
      default:
        return Icons.info;
    }
  }

  String _getSeverityLabel(String severity) {
    switch (severity) {
      case 'critical':
        return 'Críticas';
      case 'warning':
        return 'Advertencias';
      case 'info':
        return 'Información';
      default:
        return 'Todas';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return 'Hace ${difference.inDays} día${difference.inDays > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return 'Hace ${difference.inHours} hora${difference.inHours > 1 ? 's' : ''}';
    } else if (difference.inMinutes > 0) {
      return 'Hace ${difference.inMinutes} minuto${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'Hace un momento';
    }
  }
}
