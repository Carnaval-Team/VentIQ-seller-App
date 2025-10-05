import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/app_colors.dart';

class SupplierPerformanceWidget extends StatelessWidget {
  final Map<String, dynamic> performanceData;
  final bool isLoading;

  const SupplierPerformanceWidget({
    super.key,
    required this.performanceData,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final metricsPerformance = performanceData['metricas_performance'] ?? {};
    final performanceScore = (metricsPerformance['performance_score'] ?? 0.0).toDouble();
    final leadTimePromedio = (metricsPerformance['lead_time_prometido'] ?? 0.0).toDouble();
    final leadTimeReal = (metricsPerformance['lead_time_real'] ?? 0.0).toDouble();
    final ordenesATiempo = metricsPerformance['ordenes_a_tiempo'] ?? 0;
    final ordenesTarde = metricsPerformance['ordenes_tarde'] ?? 0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Performance del Proveedor',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Performance Score
            _buildPerformanceScore(performanceScore),
            const SizedBox(height: 20),

            // Lead Time Comparison
            _buildLeadTimeComparison(leadTimePromedio, leadTimeReal),
            const SizedBox(height: 20),

            // Puntualidad Chart
            _buildPunctualityChart(ordenesATiempo, ordenesTarde),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceScore(double score) {
    Color scoreColor = AppColors.success;
    String scoreLabel = 'Excelente';
    
    if (score < 50) {
      scoreColor = AppColors.error;
      scoreLabel = 'Crítico';
    } else if (score < 70) {
      scoreColor = Colors.orange;
      scoreLabel = 'Necesita Mejora';
    } else if (score < 85) {
      scoreColor = AppColors.warning;
      scoreLabel = 'Bueno';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scoreColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scoreColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Score de Performance',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${score.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
                Text(
                  scoreLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: scoreColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeadTimeComparison(double prometido, double real) {
    final diferencia = real - prometido;
    final isOnTime = diferencia <= 0;
    final color = isOnTime ? AppColors.success : AppColors.error;
    final icon = isOnTime ? Icons.check_circle : Icons.warning;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Análisis de Lead Time',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildLeadTimeMetric(
                  'Prometido',
                  '${prometido.toStringAsFixed(1)} días',
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildLeadTimeMetric(
                  'Real',
                  '${real.toStringAsFixed(1)} días',
                  color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                isOnTime 
                    ? 'Cumple con los tiempos prometidos'
                    : 'Retraso promedio: ${diferencia.toStringAsFixed(1)} días',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeadTimeMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildPunctualityChart(int onTime, int late) {
    final total = onTime + late;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Text(
          'No hay datos de puntualidad disponibles',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final onTimePercentage = (onTime / total) * 100;
    final latePercentage = (late / total) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Puntualidad en Entregas',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 120,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 30,
                    sections: [
                      PieChartSectionData(
                        color: AppColors.success,
                        value: onTime.toDouble(),
                        title: '${onTimePercentage.toStringAsFixed(0)}%',
                        radius: 35,
                        titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      PieChartSectionData(
                        color: AppColors.error,
                        value: late.toDouble(),
                        title: '${latePercentage.toStringAsFixed(0)}%',
                        radius: 35,
                        titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegendItem(
                    'A Tiempo',
                    '$onTime órdenes',
                    AppColors.success,
                  ),
                  const SizedBox(height: 8),
                  _buildLegendItem(
                    'Con Retraso',
                    '$late órdenes',
                    AppColors.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Total: $total órdenes',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
