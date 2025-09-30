import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/products_analytics_service.dart';

class ProductsCategoryChart extends StatelessWidget {
  final List<Map<String, dynamic>> categoryData;
  final bool isLoading;

  const ProductsCategoryChart({
    super.key,
    required this.categoryData,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Distribución por Categorías',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isLoading)
            const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (categoryData.isEmpty || categoryData.first['cantidad'] == 0)
            const SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pie_chart_outline, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'No hay datos de categorías',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sections: _buildPieChartSections(),
                        centerSpaceRadius: 40,
                        sectionsSpace: 2,
                        startDegreeOffset: -90,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(flex: 2, child: _buildLegend()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections() {
    final colors = [
      AppColors.primary,
      AppColors.success,
      AppColors.warning,
      AppColors.error,
      AppColors.info,
      Colors.purple,
      Colors.orange,
      Colors.teal,
    ];

    return categoryData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final porcentaje = (data['porcentaje'] ?? 0.0) as double;

      return PieChartSectionData(
        color: colors[index % colors.length],
        value: porcentaje,
        title: '${porcentaje.toStringAsFixed(1)}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildLegend() {
    final colors = [
      AppColors.primary,
      AppColors.success,
      AppColors.warning,
      AppColors.error,
      AppColors.info,
      Colors.purple,
      Colors.orange,
      Colors.teal,
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children:
            categoryData.asMap().entries.map((entry) {
              final index = entry.key;
              final data = entry.value;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: colors[index % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['categoria'] ?? 'Sin categoría',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${data['cantidad']} productos',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }
}

class ProductsBCGChart extends StatelessWidget {
  final Map<String, dynamic> bcgData;
  final bool isLoading;

  const ProductsBCGChart({
    super.key,
    required this.bcgData,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Matriz BCG - Análisis de Portafolio',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isLoading)
            const SizedBox(
              height: 300,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (bcgData.isEmpty ||
              bcgData['productos'] == null ||
              (bcgData['productos'] is! List) ||
              (bcgData['productos'] as List).isEmpty)
            const SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.grid_off, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'No hay datos de análisis BCG',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                SizedBox(height: 300, child: _buildBCGMatrix(context)),
                const SizedBox(height: 20),
                _buildBCGLegend(),
                const SizedBox(height: 16),
                _buildBCGSummary(),
                const SizedBox(height: 24),
                _buildStrategicAnalysis(), // NUEVO
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBCGMatrix(BuildContext context) {
    try {
      final productos = bcgData['productos'] as List? ?? [];
      final umbrales = bcgData['umbrales'] as Map<String, dynamic>? ?? {};

      return Stack(
        children: [
          // Cuadrantes de fondo
          _buildQuadrants(umbrales),
          // Productos como puntos
          if (productos.isNotEmpty)
            CustomPaint(
              size: Size.infinite,
              painter: BCGScatterPainter(
                productos: productos,
                umbrales: umbrales,
              ),
            ),
        ],
      );
    } catch (e) {
      print('❌ Error construyendo matriz BCG: $e');
      return const Center(
        child: Text(
          'Error al cargar matriz BCG',
          style: TextStyle(color: Colors.red, fontSize: 14),
        ),
      );
    }
  }

  Widget _buildQuadrants(Map<String, dynamic> umbrales) {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.yellow[100],
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Center(
                    child: Text(
                      'Interrogantes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Center(
                    child: Text(
                      'Perros',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Center(
                    child: Text(
                      'Estrellas',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: const Center(
                    child: Text(
                      'Vacas Lecheras',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBCGLegend() {
    final resumen = bcgData['resumen'] as Map<String, dynamic>? ?? {};

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildLegendItem('Estrellas', Colors.green, resumen['estrellas'] ?? 0),
        _buildLegendItem(
          'Vacas Lecheras',
          Colors.blue,
          resumen['vacas_lecheras'] ?? 0,
        ),
        _buildLegendItem(
          'Interrogantes',
          Colors.orange,
          resumen['interrogantes'] ?? 0,
        ),
        _buildLegendItem('Perros', Colors.red, resumen['perros'] ?? 0),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ($count)',
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildBCGSummary() {
    final resumen = bcgData['resumen'] as Map<String, dynamic>? ?? {};
    final distribucion =
        resumen['distribucion_por_categoria'] as Map<String, dynamic>? ?? {};

    // Obtener ventas totales (el campo correcto es 'ventas_totales_cup')
    final ventasTotales =
        (resumen['ventas_totales_cup'] ?? resumen['ventas_totales'] ?? 0.0)
            as num;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título
          Row(
            children: [
              Icon(Icons.analytics, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Resumen del Portafolio',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Métricas principales
          _buildSummaryRow(
            'Total de productos',
            '${resumen['total_productos'] ?? 0}',
            Icons.inventory_2,
            AppColors.primary,
          ),
          const SizedBox(height: 8),
          _buildSummaryRow(
            'Ventas totales',
            _formatCurrency(ventasTotales.toDouble()),
            Icons.attach_money,
            Colors.green,
          ),

          const SizedBox(height: 16),
          Divider(color: Colors.grey[300]),
          const SizedBox(height: 16),

          // Distribución por categoría BCG
          Text(
            'Distribución por Categoría',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),

          // Estrellas
          if (distribucion.containsKey('Estrella'))
            _buildCategoryDistribution(
              'Estrellas',
              distribucion['Estrella'],
              Colors.green,
              Icons.star,
            ),

          // Vacas Lecheras
          if (distribucion.containsKey('Vaca lechera'))
            _buildCategoryDistribution(
              'Vacas Lecheras',
              distribucion['Vaca lechera'],
              Colors.blue,
              Icons.water_drop,
            ),

          // Interrogantes
          if (distribucion.containsKey('Interrogante'))
            _buildCategoryDistribution(
              'Interrogantes',
              distribucion['Interrogante'],
              Colors.orange,
              Icons.help,
            ),

          // Perros
          if (distribucion.containsKey('Perro'))
            _buildCategoryDistribution(
              'Perros',
              distribucion['Perro'],
              Colors.red,
              Icons.pets,
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDistribution(
    String nombre,
    Map<String, dynamic> datos,
    Color color,
    IconData icon,
  ) {
    final total = datos['total'] ?? 0;
    final porcentajeVentas = (datos['porcentaje_ventas'] ?? 0.0) as num;
    final margenPromedio = (datos['margen_promedio'] ?? 0.0) as num;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                nombre,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$total productos',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '% Ventas: ${porcentajeVentas.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              Text(
                'Margen: ${margenPromedio.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: margenPromedio >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStrategicAnalysis() {
    final resumen = bcgData['resumen'] as Map<String, dynamic>? ?? {};
    final productos = bcgData['productos'] as List? ?? [];

    final estrellas = resumen['estrellas'] ?? 0;
    final vacasLecheras = resumen['vacas_lecheras'] ?? 0;
    final interrogantes = resumen['interrogantes'] ?? 0;
    final perros = resumen['perros'] ?? 0;
    final totalProductos = resumen['total_productos'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue[50]!, Colors.purple[50]!],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.blue[700], size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Análisis Estratégico del Portafolio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[900],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Análisis general
          Builder(
            builder:
                (context) => _buildAnalysisSection(
                  'Diagnóstico General',
                  Icons.assessment,
                  Colors.blue,
                  _getGeneralDiagnosis(
                    estrellas,
                    vacasLecheras,
                    interrogantes,
                    perros,
                    totalProductos,
                  ),
                  null, // Sin clasificación para diagnóstico general
                  null,
                ),
          ),
          const SizedBox(height: 16),

          // Recomendaciones por cuadrante
          if (estrellas > 0) ...[
            Builder(
              builder:
                  (context) => _buildAnalysisSection(
                    'Estrellas ($estrellas productos)',
                    Icons.star,
                    Colors.green,
                    '✓ Productos con alto crecimiento y alta cuota de mercado\n'
                        '✓ Estrategia: INVERTIR para mantener liderazgo\n'
                        '✓ Acción: Aumentar producción y marketing\n'
                        '✓ Objetivo: Convertirlos en Vacas Lecheras cuando el mercado madure',
                    'Estrella', // Clasificación
                    context, // Contexto
                  ),
            ),
            const SizedBox(height: 12),
          ],

          if (vacasLecheras > 0) ...[
            Builder(
              builder:
                  (context) => _buildAnalysisSection(
                    'Vacas Lecheras ($vacasLecheras productos)',
                    Icons.monetization_on,
                    Colors.blue,
                    '✓ Productos con alta cuota en mercados maduros\n'
                        '✓ Estrategia: COSECHAR beneficios\n'
                        '✓ Acción: Minimizar inversión, maximizar rentabilidad\n'
                        '✓ Objetivo: Usar ganancias para financiar Estrellas e Interrogantes',
                    'Vaca lechera', // Clasificación
                    context,
                  ),
            ),
            const SizedBox(height: 12),
          ],

          if (interrogantes > 0) ...[
            Builder(
              builder:
                  (context) => _buildAnalysisSection(
                    'Interrogantes ($interrogantes productos)',
                    Icons.help_outline,
                    Colors.orange,
                    '⚠ Productos con alto crecimiento pero baja cuota\n'
                        '⚠ Estrategia: ANALIZAR Y DECIDIR\n'
                        '⚠ Acción: Invertir selectivamente en los más prometedores\n'
                        '⚠ Objetivo: Convertir en Estrellas o desinvertir',
                    'Interrogante', // Clasificación
                    context,
                  ),
            ),
            const SizedBox(height: 12),
          ],

          if (perros > 0) ...[
            Builder(
              builder:
                  (context) => _buildAnalysisSection(
                    'Perros ($perros productos)',
                    Icons.warning_amber,
                    Colors.red,
                    '✗ Productos con baja cuota y bajo crecimiento\n'
                        '✗ Estrategia: DESINVERTIR o ELIMINAR\n'
                        '✗ Acción: Reducir inventario, considerar descontinuar\n'
                        '✗ Objetivo: Liberar recursos para productos más rentables',
                    'Perro', // Clasificación
                    context,
                  ),
            ),
            const SizedBox(height: 12),
          ],

          // Balance del portafolio
          const Divider(height: 32),
          _buildPortfolioBalance(
            estrellas,
            vacasLecheras,
            interrogantes,
            perros,
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisSection(
    String title,
    IconData icon,
    Color color,
    String content,
    String? clasificacion, // NUEVO: clasificación BCG
    BuildContext? context, // NUEVO: contexto para mostrar diálogo
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              // NUEVO: Botón para ver listado
              if (clasificacion != null && context != null)
                TextButton.icon(
                  onPressed:
                      () => _showProductsList(
                        context,
                        clasificacion,
                        title,
                        color,
                      ),
                  icon: Icon(Icons.list, size: 16, color: color),
                  label: Text(
                    'Ver lista',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  // NUEVO: Método para mostrar el diálogo con productos
  void _showProductsList(
    BuildContext context,
    String clasificacion,
    String title,
    Color color,
  ) {
    final productos = bcgData['productos'] as List? ?? [];
    final productosFiltrados =
        productos
            .where((p) => p['clasificacion_tradicional'] == clasificacion)
            .toList();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.list, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 18, color: color),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child:
                  productosFiltrados.isEmpty
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No hay productos en esta clasificación'),
                        ),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: productosFiltrados.length,
                        itemBuilder: (context, index) {
                          final producto = productosFiltrados[index];
                          // Intenta diferentes campos para el ID
                          final productId =
                              (producto['id_producto'] ?? producto['id'] ?? 0)
                                  as int;

                          print(
                            '🔍 Producto: ${producto['denominacion']}, ID: $productId',
                          );
                          print(
                            '📋 Campos disponibles: ${producto.keys.toList()}',
                          );

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: color.withOpacity(0.2),
                                child: Icon(
                                  Icons.inventory_2,
                                  color: color,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                producto['denominacion'] ?? 'Producto',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SKU: ${producto['sku'] ?? 'N/A'}',
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          'Cuota: ${(producto['cuota_mercado'] ?? 0.0).toStringAsFixed(1)}%',
                                          style: const TextStyle(fontSize: 10),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Crec: ${(producto['tasa_crecimiento'] ?? 0.0).toStringAsFixed(1)}%',
                                          style: const TextStyle(fontSize: 10),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              children: [
                                FutureBuilder<Map<String, dynamic>>(
                                  future:
                                      ProductsAnalyticsService.getProductDetails(
                                        productId,
                                      ),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }

                                    if (snapshot.hasError ||
                                        !snapshot.hasData) {
                                      return Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          'Error al cargar detalles: ${snapshot.error ?? "Desconocido"}',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontSize: 12,
                                          ),
                                        ),
                                      );
                                    }

                                    final detalles = snapshot.data!;
                                    final precioVenta =
                                        detalles['precio_venta'] as double;
                                    final costoPromedio =
                                        detalles['costo_promedio'] as double;
                                    final costoPromedioCUP =
                                        detalles['costo_promedio_cup']
                                            as double;
                                    final monedaCosto =
                                        detalles['moneda_costo'] as String;
                                    final tasaCambio =
                                        detalles['tasa_cambio'] as double;
                                    final ventasTotales =
                                        detalles['ventas_totales'] as double;
                                    final porcentajeUtilidad =
                                        detalles['porcentaje_utilidad']
                                            as double;

                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.05),
                                        border: Border(
                                          top: BorderSide(
                                            color: color.withOpacity(0.2),
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          _buildDetailRow(
                                            'Precio de Venta',
                                            '\$${precioVenta.toStringAsFixed(2)} CUP',
                                            Icons.attach_money,
                                            Colors.green,
                                          ),
                                          const SizedBox(height: 8),
                                          _buildDetailRow(
                                            'Costo Unitario Promedio',
                                            monedaCosto == 'USD'
                                                ? '\$${costoPromedio.toStringAsFixed(2)} USD (\$${costoPromedioCUP.toStringAsFixed(2)} CUP)'
                                                : '\$${costoPromedio.toStringAsFixed(2)} CUP',
                                            Icons.shopping_cart,
                                            Colors.orange,
                                          ),
                                          const SizedBox(height: 8),
                                          _buildDetailRow(
                                            'Ventas Totales (30 días)',
                                            '${_formatCurrency(ventasTotales)} CUP',
                                            Icons.trending_up,
                                            Colors.blue,
                                          ),
                                          const SizedBox(height: 8),
                                          _buildDetailRow(
                                            'Porcentaje de Utilidad',
                                            '${porcentajeUtilidad.toStringAsFixed(1)}%',
                                            Icons.percent,
                                            porcentajeUtilidad >= 25
                                                ? Colors.green
                                                : porcentajeUtilidad >= 10
                                                ? Colors.orange
                                                : Colors.red,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  String _formatCurrency(double value) {
    final formatter = NumberFormat.currency(
      locale: 'es_CU',
      symbol: '\$',
      decimalDigits: 0,
    );
    return formatter.format(value);
  }

  String _getGeneralDiagnosis(
    int estrellas,
    int vacasLecheras,
    int interrogantes,
    int perros,
    int total,
  ) {
    if (total == 0) {
      return 'No hay productos para analizar.';
    }

    final porcentajeEstrellas = (estrellas / total * 100).round();
    final porcentajeVacas = (vacasLecheras / total * 100).round();
    final porcentajeInterrogantes = (interrogantes / total * 100).round();
    final porcentajePerros = (perros / total * 100).round();

    String diagnosis = '';

    // Portafolio saludable
    if (porcentajeEstrellas + porcentajeVacas >= 60) {
      diagnosis =
          '✅ PORTAFOLIO SALUDABLE: ${porcentajeEstrellas + porcentajeVacas}% de productos en categorías rentables.\n\n';
    }
    // Portafolio en riesgo
    else if (porcentajePerros >= 40) {
      diagnosis =
          '⚠️ PORTAFOLIO EN RIESGO: $porcentajePerros% de productos en categoría "Perros".\n\n';
    }
    // Portafolio en transición
    else if (porcentajeInterrogantes >= 40) {
      diagnosis =
          '🔄 PORTAFOLIO EN TRANSICIÓN: $porcentajeInterrogantes% de productos requieren decisión estratégica.\n\n';
    }
    // Portafolio balanceado
    else {
      diagnosis =
          '⚖️ PORTAFOLIO BALANCEADO: Distribución equilibrada entre categorías.\n\n';
    }

    diagnosis += 'Distribución actual:\n';
    diagnosis += '• Estrellas: $porcentajeEstrellas% ($estrellas productos)\n';
    diagnosis +=
        '• Vacas Lecheras: $porcentajeVacas% ($vacasLecheras productos)\n';
    diagnosis +=
        '• Interrogantes: $porcentajeInterrogantes% ($interrogantes productos)\n';
    diagnosis += '• Perros: $porcentajePerros% ($perros productos)';

    return diagnosis;
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.grey[900],
          ),
        ),
      ],
    );
  }

  Widget _buildPortfolioBalance(
    int estrellas,
    int vacasLecheras,
    int interrogantes,
    int perros,
  ) {
    final total = estrellas + vacasLecheras + interrogantes + perros;

    if (total == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Balance del Portafolio',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 12),
        _buildBalanceIndicator(
          'Generadores de Efectivo',
          vacasLecheras,
          total,
          Colors.blue,
          'Ideal: 30-40%',
        ),
        const SizedBox(height: 8),
        _buildBalanceIndicator(
          'Inversión en Crecimiento',
          estrellas + interrogantes,
          total,
          Colors.green,
          'Ideal: 40-50%',
        ),
        const SizedBox(height: 8),
        _buildBalanceIndicator(
          'Productos a Revisar',
          perros,
          total,
          Colors.red,
          'Ideal: <20%',
        ),
      ],
    );
  }

  Widget _buildBalanceIndicator(
    String label,
    int count,
    int total,
    Color color,
    String ideal,
  ) {
    final percentage = (count / total * 100).round();

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              Text(
                ideal,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$percentage%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BCGScatterPainter extends CustomPainter {
  final List productos;
  final Map<String, dynamic> umbrales;

  BCGScatterPainter({required this.productos, required this.umbrales});

  @override
  void paint(Canvas canvas, Size size) {
    if (productos.isEmpty || size.width <= 0 || size.height <= 0) {
      return; // No dibujar si no hay datos o tamaño inválido
    }

    final umbralCuota = (umbrales['umbral_cuota'] ?? 0.0) as double;
    final umbralCrecimiento = (umbrales['umbral_crecimiento'] ?? 0.0) as double;

    // Encontrar rangos para escalar
    double maxCuota = umbralCuota * 2;
    double maxCrecimiento = umbralCrecimiento * 2;
    double minCrecimiento = -50.0;

    for (final producto in productos) {
      final cuota = (producto['cuota_mercado'] ?? 0.0) as double;
      final crecimiento = (producto['tasa_crecimiento'] ?? 0.0) as double;

      if (cuota > maxCuota) maxCuota = cuota;
      if (crecimiento > maxCrecimiento) maxCrecimiento = crecimiento;
      if (crecimiento < minCrecimiento) minCrecimiento = crecimiento;
    }

    // Dibujar productos
    for (final producto in productos) {
      final cuota = (producto['cuota_mercado'] ?? 0.0) as double;
      final crecimiento = (producto['tasa_crecimiento'] ?? 0.0) as double;
      final tamanio = (producto['tamanio_relativo'] ?? 1.0) as double;
      final clasificacion = producto['clasificacion_tradicional'] as String?;

      // Escalar coordenadas
      final x = (cuota / maxCuota) * size.width;
      final y =
          size.height -
          ((crecimiento - minCrecimiento) / (maxCrecimiento - minCrecimiento)) *
              size.height;

      // Color según clasificación
      Color color;
      switch (clasificacion) {
        case 'Estrella':
          color = Colors.green;
          break;
        case 'Vaca lechera':
          color = Colors.blue;
          break;
        case 'Interrogante':
          color = Colors.orange;
          break;
        default:
          color = Colors.red;
      }

      // Dibujar círculo (tamaño basado en ventas)
      final paint =
          Paint()
            ..color = color.withOpacity(0.6)
            ..style = PaintingStyle.fill;

      final radius = (tamanio / 10).clamp(3.0, 15.0);
      canvas.drawCircle(Offset(x, y), radius, paint);

      // Borde
      final borderPaint =
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;

      canvas.drawCircle(Offset(x, y), radius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ProductsStockTrendsChart extends StatelessWidget {
  final List<Map<String, dynamic>> trendsData;
  final bool isLoading;

  const ProductsStockTrendsChart({
    super.key,
    required this.trendsData,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Tendencias de Stock (7 días)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isLoading)
            const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (trendsData.isEmpty || trendsData.length < 2)
            const SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.show_chart, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'No hay datos de tendencias',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else if (trendsData.isNotEmpty)
            Builder(
              builder: (context) {
                try {
                  return SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 1,
                          getDrawingHorizontalLine: (value) {
                            return FlLine(
                              color: Colors.grey[300]!,
                              strokeWidth: 1,
                            );
                          },
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: 1,
                              getTitlesWidget: (double value, TitleMeta meta) {
                                if (value.toInt() >= 0 &&
                                    value.toInt() < trendsData.length) {
                                  try {
                                    final fechaStr =
                                        trendsData[value.toInt()]['fecha'];
                                    if (fechaStr != null &&
                                        fechaStr.toString().isNotEmpty) {
                                      final date = DateTime.parse(
                                        fechaStr.toString(),
                                      );
                                      return SideTitleWidget(
                                        axisSide: meta.axisSide,
                                        child: Text(
                                          DateFormat('dd/MM').format(date),
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 10,
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    print(
                                      '❌ Error parseando fecha en gráfico: $e',
                                    );
                                  }
                                }
                                return Container();
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (double value, TitleMeta meta) {
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  child: Text(
                                    _formatNumber(value),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        minX: 0,
                        maxX: (trendsData.length - 1).toDouble(),
                        minY: 0,
                        maxY: _getMaxValue(),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _buildStockSpots(),
                            isCurved: true,
                            color: AppColors.primary,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter:
                                  (spot, percent, barData, index) =>
                                      FlDotCirclePainter(
                                        radius: 4,
                                        color: AppColors.primary,
                                        strokeWidth: 2,
                                        strokeColor: Colors.white,
                                      ),
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.primary.withOpacity(0.1),
                            ),
                          ),
                          LineChartBarData(
                            spots: _buildMovimientosSpots(),
                            isCurved: true,
                            color: AppColors.success,
                            barWidth: 2,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter:
                                  (spot, percent, barData, index) =>
                                      FlDotCirclePainter(
                                        radius: 3,
                                        color: AppColors.success,
                                        strokeWidth: 1,
                                        strokeColor: Colors.white,
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } catch (e) {
                  print(
                    '❌ Error crítico renderizando gráfico de tendencias: $e',
                  );
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red[700],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Error al renderizar el gráfico',
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              },
            )
          else
            const SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'No hay suficientes datos para mostrar',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ),
            ),
          const SizedBox(height: 16),
          _buildChartLegend(),
        ],
      ),
    );
  }

  List<FlSpot> _buildStockSpots() {
    return trendsData.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        (entry.value['stockTotal'] ?? 0).toDouble(),
      );
    }).toList();
  }

  List<FlSpot> _buildMovimientosSpots() {
    return trendsData.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        (entry.value['movimientos'] ?? 0).toDouble(),
      );
    }).toList();
  }

  double _getMaxValue() {
    double maxStock = 0;
    double maxMovimientos = 0;

    for (final data in trendsData) {
      final stock = (data['stockTotal'] ?? 0).toDouble();
      final movimientos = (data['movimientos'] ?? 0).toDouble();

      if (stock > maxStock) maxStock = stock;
      if (movimientos > maxMovimientos) maxMovimientos = movimientos;
    }

    final maxValue = maxStock > maxMovimientos ? maxStock : maxMovimientos;
    return maxValue > 0
        ? maxValue * 1.1
        : 10.0; // Valor mínimo de 10 si todo es 0
  }

  Widget _buildChartLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem('Stock Total', AppColors.primary),
        const SizedBox(width: 20),
        _buildLegendItem('Movimientos', AppColors.success),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  String _formatNumber(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else {
      return value.toInt().toString();
    }
  }
}

class ProductsABCChart extends StatelessWidget {
  final Map<String, dynamic> abcData;
  final bool isLoading;

  const ProductsABCChart({
    super.key,
    required this.abcData,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Análisis ABC',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isLoading)
            const SizedBox(
              height: 150,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (abcData['totalAnalizado'] == 0)
            const SizedBox(
              height: 150,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No hay datos de análisis ABC',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                _buildABCBar('A', abcData['clasificacionA'], AppColors.success),
                const SizedBox(height: 12),
                _buildABCBar('B', abcData['clasificacionB'], AppColors.warning),
                const SizedBox(height: 12),
                _buildABCBar('C', abcData['clasificacionC'], AppColors.error),
                const SizedBox(height: 16),
                Text(
                  'Total analizado: ${abcData['totalAnalizado']} productos',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildABCBar(
    String classification,
    Map<String, dynamic> data,
    Color color,
  ) {
    final cantidad = data['cantidad'] ?? 0;
    final porcentaje = data['porcentaje'] ?? 0.0;
    final valor = data['valorInventario'] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Clasificación $classification',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Text(
              '$cantidad productos (${porcentaje.toStringAsFixed(1)}%)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: porcentaje / 100,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Valor: ${_formatCurrency(valor)}',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      ],
    );
  }

  String _formatCurrency(double value) {
    final formatter = NumberFormat.currency(
      locale: 'es_CU',
      symbol: '\$',
      decimalDigits: 0,
    );
    return formatter.format(value);
  }
}
