import 'package:flutter/material.dart';
import '../../models/analytics/inventory_metrics.dart';
import '../../services/analytics_service.dart';
import '../../widgets/analytics/metric_card.dart';

class StockHealthDetailScreen extends StatefulWidget {
  const StockHealthDetailScreen({super.key});

  @override
  State<StockHealthDetailScreen> createState() =>
      _StockHealthDetailScreenState();
}

class _StockHealthDetailScreenState extends State<StockHealthDetailScreen> {
  InventoryMetrics? _metrics;
  bool _isLoading = true;
  List<Map<String, dynamic>> _stockDetails = [];

  @override
  void initState() {
    super.initState();
    _loadStockHealthData();
  }

  Future<void> _loadStockHealthData() async {
    setState(() => _isLoading = true);

    try {
      final metrics = await AnalyticsService.getInventoryMetrics();
      final stockAlerts = await AnalyticsService.getStockAlerts();

      // Agrupar productos por estado de stock
      final stockDetails = _categorizeStockLevels(metrics, stockAlerts);

      setState(() {
        _metrics = metrics;
        _stockDetails = stockDetails;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando datos: $e')));
    }
  }

  List<Map<String, dynamic>> _categorizeStockLevels(
    InventoryMetrics metrics,
    List stockAlerts,
  ) {
    // ✅ USAR ALERTAS REALES de fn_analytics_stock_alerts
    // Contar productos por severidad desde las alertas
    int criticalCount = 0; // Sin stock (current_stock = 0)
    int warningCount = 0; // Stock bajo (current_stock <= min_stock)

    for (final alert in stockAlerts) {
      final severity = alert.severity?.toLowerCase() ?? '';
      if (severity == 'critical') {
        criticalCount++;
      } else if (severity == 'warning') {
        warningCount++;
      }
    }

    // Total de productos con alertas
    final totalWithAlerts = criticalCount + warningCount;

    // Productos saludables = Total - Productos con alertas
    final healthyCount = metrics.totalProducts - totalWithAlerts;

    print('📊 Distribución de stock:');
    print('  Total productos: ${metrics.totalProducts}');
    print('  Críticos (sin stock): $criticalCount');
    print('  Advertencia (stock bajo): $warningCount');
    print('  Saludables: $healthyCount');
    print('  Total alertas: ${stockAlerts.length}');

    return [
      {
        'category': 'Sin Stock',
        'count': criticalCount,
        'percentage':
            metrics.totalProducts > 0
                ? (criticalCount / metrics.totalProducts * 100)
                : 0.0,
        'color': Colors.red,
        'icon': Icons.error,
        'severity': 'Crítico',
        'description': 'Productos completamente agotados (stock = 0)',
      },
      {
        'category': 'Stock Bajo',
        'count': warningCount,
        'percentage':
            metrics.totalProducts > 0
                ? (warningCount / metrics.totalProducts * 100)
                : 0.0,
        'color': Colors.orange,
        'icon': Icons.warning,
        'severity': 'Alerta',
        'description': 'Productos con stock ≤ stock mínimo',
      },
      {
        'category': 'Stock Saludable',
        'count': healthyCount,
        'percentage':
            metrics.totalProducts > 0
                ? (healthyCount / metrics.totalProducts * 100)
                : 0.0,
        'color': Colors.green,
        'icon': Icons.check_circle,
        'severity': 'Bueno',
        'description': 'Productos con stock > stock mínimo',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estado de Stock - Análisis Detallado'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
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
          Text('Analizando estado de stock...'),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_metrics == null) {
      return const Center(child: Text('No se pudieron cargar los datos'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewCard(),
          const SizedBox(height: 24),
          _buildHealthLevelsExplanation(),
          const SizedBox(height: 24),
          _buildStockDistribution(),
          const SizedBox(height: 24),
          _buildImprovementSteps(),
          const SizedBox(height: 24),
          _buildCalculationMethod(),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    // ✅ USAR DATOS DESDE _stockDetails (calculados desde alertas reales)
    final criticalData = _stockDetails.firstWhere(
      (d) => d['category'] == 'Sin Stock',
      orElse: () => {'count': 0, 'color': Colors.red, 'severity': 'Crítico'},
    );
    final warningData = _stockDetails.firstWhere(
      (d) => d['category'] == 'Stock Bajo',
      orElse: () => {'count': 0},
    );

    final criticalCount = criticalData['count'] as int;
    final warningCount = warningData['count'] as int;
    final totalAlerts = criticalCount + warningCount;

    // Determinar nivel de salud desde alertas reales
    String healthLevel;
    Color healthColor;
    IconData healthIcon;

    if (criticalCount > 0) {
      healthLevel = 'Crítico';
      healthColor = Colors.red;
      healthIcon = Icons.error;
    } else if (totalAlerts > _metrics!.totalProducts * 0.2) {
      healthLevel = 'Crítico';
      healthColor = Colors.red;
      healthIcon = Icons.error;
    } else if (totalAlerts > _metrics!.totalProducts * 0.1) {
      healthLevel = 'Alerta';
      healthColor = Colors.orange;
      healthIcon = Icons.warning;
    } else if (totalAlerts > _metrics!.totalProducts * 0.05) {
      healthLevel = 'Precaución';
      healthColor = Colors.yellow.shade700;
      healthIcon = Icons.warning_amber;
    } else {
      healthLevel = 'Saludable';
      healthColor = Colors.green;
      healthIcon = Icons.check_circle;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: healthColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(healthIcon, color: healthColor, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estado Actual: $healthLevel',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: healthColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$criticalCount de ${_metrics!.totalProducts} productos sin stock',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value:
                  _metrics!.totalProducts > 0
                      ? 1 - (criticalCount / _metrics!.totalProducts)
                      : 0,
              backgroundColor: Colors.red.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(healthColor),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Text(
              '${((1 - (_metrics!.outOfStockProducts / _metrics!.totalProducts)) * 100).toStringAsFixed(1)}% de productos con stock disponible',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthLevelsExplanation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Niveles de Salud del Stock',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildHealthLevelItem(
              'Saludable',
              '0-5% sin stock',
              Colors.green,
              Icons.check_circle,
              'Excelente gestión de inventario',
            ),
            _buildHealthLevelItem(
              'Precaución',
              '5-10% sin stock',
              Colors.yellow[700]!,
              Icons.warning_amber,
              'Requiere atención preventiva',
            ),
            _buildHealthLevelItem(
              'Alerta',
              '10-20% sin stock',
              Colors.orange,
              Icons.warning,
              'Necesita acción inmediata',
            ),
            _buildHealthLevelItem(
              'Crítico',
              '+20% sin stock',
              Colors.red,
              Icons.error,
              'Situación crítica que afecta ventas',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthLevelItem(
    String level,
    String range,
    Color color,
    IconData icon,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
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
                Row(
                  children: [
                    Text(
                      level,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      range,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockDistribution() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Distribución Actual del Stock',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._stockDetails.map((detail) => _buildStockCategoryCard(detail)),
          ],
        ),
      ),
    );
  }

  Widget _buildStockCategoryCard(Map<String, dynamic> detail) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: detail['color'], width: 4)),
        color: detail['color'].withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(detail['icon'], color: detail['color'], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      detail['category'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${detail['count']} productos',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: detail['color'],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detail['description'],
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: detail['percentage'] / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(detail['color']),
                  minHeight: 4,
                ),
                const SizedBox(height: 4),
                Text(
                  '${detail['percentage'].toStringAsFixed(1)}% del total',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImprovementSteps() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pasos para Mejorar el Estado de Stock',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildImprovementStep(
              1,
              'Identificar Productos Críticos',
              'Revisar productos sin stock y con mayor demanda',
              Icons.search,
              Colors.blue,
            ),
            _buildImprovementStep(
              2,
              'Establecer Puntos de Reorden',
              'Definir niveles mínimos para cada producto',
              Icons.settings,
              Colors.orange,
            ),
            _buildImprovementStep(
              3,
              'Mejorar Pronósticos',
              'Usar datos históricos para predecir demanda',
              Icons.analytics,
              Colors.purple,
            ),
            _buildImprovementStep(
              4,
              'Optimizar Proveedores',
              'Negociar tiempos de entrega más cortos',
              Icons.business,
              Colors.green,
            ),
            _buildImprovementStep(
              5,
              'Monitoreo Continuo',
              'Revisar indicadores semanalmente',
              Icons.monitor,
              Colors.teal,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImprovementStep(
    int step,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                step.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculationMethod() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cómo se Calcula este Indicador',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fórmula:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '% Sin Stock = (Productos Sin Stock / Total Productos) × 100',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fuente de Datos:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Productos sin stock: ${_metrics!.outOfStockProducts}\n'
                    '• Total de productos: ${_metrics!.totalProducts}\n'
                    '• Porcentaje actual: ${(_metrics!.outOfStockProducts / _metrics!.totalProducts * 100).toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getHealthColor(String healthLevel) {
    switch (healthLevel.toLowerCase()) {
      case 'saludable':
        return Colors.green;
      case 'precaución':
        return Colors.yellow[700]!;
      case 'alerta':
        return Colors.orange;
      case 'crítico':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getHealthIcon(String healthLevel) {
    switch (healthLevel.toLowerCase()) {
      case 'saludable':
        return Icons.check_circle;
      case 'precaución':
        return Icons.warning_amber;
      case 'alerta':
        return Icons.warning;
      case 'crítico':
        return Icons.error;
      default:
        return Icons.help;
    }
  }
}
