import 'package:flutter/material.dart';
import '../../models/analytics/inventory_metrics.dart';
import '../../services/analytics_service.dart';

class RotationDetailScreen extends StatefulWidget {
  const RotationDetailScreen({super.key});

  @override
  State<RotationDetailScreen> createState() => _RotationDetailScreenState();
}

class _RotationDetailScreenState extends State<RotationDetailScreen> {
  InventoryMetrics? _metrics;
  bool _isLoading = true;
  List<Map<String, dynamic>> _rotationCategories = [];

  @override
  void initState() {
    super.initState();
    _loadRotationData();
  }

  Future<void> _loadRotationData() async {
    setState(() => _isLoading = true);

    try {
      final metrics = await AnalyticsService.getInventoryMetrics();
      final topProducts = await AnalyticsService.getTopRotationProducts(
        limit: 10,
      );
      //final slowProducts = await AnalyticsService.getSlowMovingProducts(limit: 10);

      final rotationCategories = _categorizeRotationLevels(metrics);

      setState(() {
        _metrics = metrics;
        _rotationCategories = rotationCategories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cargando datos: $e')));
    }
  }

  List<Map<String, dynamic>> _categorizeRotationLevels(
    InventoryMetrics metrics,
  ) {
    // Simulamos distribución de productos por nivel de rotación
    final totalProducts = metrics.totalProducts;
    final avgRotation = metrics.averageRotation;

    return [
      {
        'category': 'Rotación Alta',
        'range': '12+ veces/año',
        'count': (totalProducts * 0.2).round(), // 20% aproximadamente
        'percentage': 20.0,
        'color': Colors.green,
        'icon': Icons.trending_up,
        'description': 'Productos con excelente movimiento',
        'benchmark': 'Ideal: >12 rotaciones anuales',
      },
      {
        'category': 'Rotación Buena',
        'range': '6-12 veces/año',
        'count': (totalProducts * 0.4).round(), // 40% aproximadamente
        'percentage': 40.0,
        'color': Colors.blue,
        'icon': Icons.trending_up,
        'description': 'Productos con buen movimiento',
        'benchmark': 'Aceptable: 6-12 rotaciones anuales',
      },
      {
        'category': 'Rotación Regular',
        'range': '3-6 veces/año',
        'count': (totalProducts * 0.25).round(), // 25% aproximadamente
        'percentage': 25.0,
        'color': Colors.orange,
        'icon': Icons.trending_flat,
        'description': 'Productos con movimiento moderado',
        'benchmark': 'Mejorable: 3-6 rotaciones anuales',
      },
      {
        'category': 'Rotación Lenta',
        'range': '<3 veces/año',
        'count': (totalProducts * 0.15).round(), // 15% aproximadamente
        'percentage': 15.0,
        'color': Colors.red,
        'icon': Icons.trending_down,
        'description': 'Productos con movimiento lento',
        'benchmark': 'Crítico: <3 rotaciones anuales',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotación de Inventario - Análisis Detallado'),
        backgroundColor: Colors.purple,
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
          Text('Analizando rotación de inventario...'),
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
          _buildRotationLevelsExplanation(),
          const SizedBox(height: 24),
          _buildRotationDistribution(),
          const SizedBox(height: 24),
          _buildImprovementStrategies(),
          const SizedBox(height: 24),
          _buildCalculationMethod(),
          const SizedBox(height: 24),
          _buildBenchmarks(),
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    final rotationColor = _getRotationColor(_metrics!.rotationLevel);
    final rotationValue = _metrics!.averageRotation;

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
                    color: rotationColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getRotationIcon(_metrics!.rotationLevel),
                    color: rotationColor,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rotación: ${_metrics!.rotationLevel}',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: rotationColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${rotationValue.toStringAsFixed(1)} veces por año',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cada ${(365 / rotationValue).round()} días en promedio',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: (rotationValue / 12).clamp(
                0.0,
                1.0,
              ), // Normalizado a 12 como máximo ideal
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(rotationColor),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '0 veces/año',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                Text(
                  '12+ veces/año (Ideal)',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotationLevelsExplanation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Niveles de Rotación de Inventario',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildRotationLevelItem(
              'Excelente',
              '12+ veces/año',
              Colors.green,
              Icons.trending_up,
              'Inventario se renueva cada mes',
              'Capital optimizado, alta eficiencia',
            ),
            _buildRotationLevelItem(
              'Buena',
              '6-12 veces/año',
              Colors.blue,
              Icons.trending_up,
              'Inventario se renueva cada 1-2 meses',
              'Buen equilibrio entre stock y ventas',
            ),
            _buildRotationLevelItem(
              'Regular',
              '3-6 veces/año',
              Colors.orange,
              Icons.trending_flat,
              'Inventario se renueva cada 2-4 meses',
              'Hay oportunidades de mejora',
            ),
            _buildRotationLevelItem(
              'Lenta',
              '<3 veces/año',
              Colors.red,
              Icons.trending_down,
              'Inventario se renueva más de 4 meses',
              'Capital inmovilizado, riesgo de obsolescencia',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotationLevelItem(
    String level,
    String range,
    Color color,
    IconData icon,
    String frequency,
    String impact,
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
                  frequency,
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
                Text(
                  impact,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRotationDistribution() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Distribución de Productos por Rotación',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._rotationCategories.map(
              (category) => _buildRotationCategoryCard(category),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRotationCategoryCard(Map<String, dynamic> category) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: category['color'], width: 4)),
        color: category['color'].withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(category['icon'], color: category['color'], size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          category['category'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${category['count']} productos',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: category['color'],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category['range'],
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            category['description'],
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: category['percentage'] / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(category['color']),
            minHeight: 4,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${category['percentage'].toStringAsFixed(1)}% del inventario',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                category['benchmark'],
                style: TextStyle(
                  color: category['color'],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImprovementStrategies() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estrategias para Mejorar la Rotación',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStrategyItem(
              1,
              'Análisis ABC de Productos',
              'Clasificar productos por importancia y ajustar stock',
              Icons.analytics,
              Colors.blue,
              [
                'Identificar productos A (alta rotación)',
                'Reducir stock de productos C (baja rotación)',
              ],
            ),
            _buildStrategyItem(
              2,
              'Optimizar Pronósticos',
              'Mejorar predicción de demanda para ajustar compras',
              Icons.trending_up,
              Colors.green,
              [
                'Usar datos históricos de ventas',
                'Considerar estacionalidad y tendencias',
              ],
            ),
            _buildStrategyItem(
              3,
              'Promociones Estratégicas',
              'Impulsar venta de productos de lenta rotación',
              Icons.local_offer,
              Colors.orange,
              [
                'Descuentos en productos lentos',
                'Combos con productos rápidos',
              ],
            ),
            _buildStrategyItem(
              4,
              'Gestión de Proveedores',
              'Negociar entregas más frecuentes y menores',
              Icons.business,
              Colors.purple,
              ['Entregas JIT (Just In Time)', 'Acuerdos de consignación'],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategyItem(
    int step,
    String title,
    String description,
    IconData icon,
    Color color,
    List<String> actions,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 8),
                ...actions.map(
                  (action) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            action,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
              'Cómo se Calcula la Rotación',
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
                    'Fórmula Básica:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Rotación = Costo de Ventas / Inventario Promedio',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Interpretación:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Rotación actual: ${_metrics!.averageRotation.toStringAsFixed(1)} veces/año\n'
                    '• Días para rotar: ${(365 / _metrics!.averageRotation).round()} días\n'
                    '• Nivel: ${_metrics!.rotationLevel}',
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Factores que Influyen:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Demanda del producto\n'
                    '• Política de inventarios\n'
                    '• Estacionalidad\n'
                    '• Eficiencia de compras\n'
                    '• Gestión de proveedores',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenchmarks() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Benchmarks por Industria',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildBenchmarkItem(
              'Supermercados',
              '12-24 veces/año',
              Colors.green,
            ),
            _buildBenchmarkItem('Restaurantes', '24-52 veces/año', Colors.blue),
            _buildBenchmarkItem('Farmacias', '8-12 veces/año', Colors.orange),
            _buildBenchmarkItem('Ropa/Moda', '4-6 veces/año', Colors.purple),
            _buildBenchmarkItem('Electrónicos', '6-8 veces/año', Colors.teal),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tu rotación actual (${_metrics!.averageRotation.toStringAsFixed(1)}) se considera ${_metrics!.rotationLevel.toLowerCase()}',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildBenchmarkItem(String industry, String rotation, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              industry,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            rotation,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Color _getRotationColor(String rotationLevel) {
    switch (rotationLevel.toLowerCase()) {
      case 'excelente':
        return Colors.green;
      case 'buena':
        return Colors.blue;
      case 'regular':
        return Colors.orange;
      case 'lenta':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getRotationIcon(String rotationLevel) {
    switch (rotationLevel.toLowerCase()) {
      case 'excelente':
        return Icons.trending_up;
      case 'buena':
        return Icons.trending_up;
      case 'regular':
        return Icons.trending_flat;
      case 'lenta':
        return Icons.trending_down;
      default:
        return Icons.help;
    }
  }
}
