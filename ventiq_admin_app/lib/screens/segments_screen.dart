import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../widgets/marketing_menu_widget.dart';
import '../widgets/store_selector_widget.dart';

class SegmentsScreen extends StatefulWidget {
  const SegmentsScreen({super.key});

  @override
  State<SegmentsScreen> createState() => _SegmentsScreenState();
}

class _SegmentsScreenState extends State<SegmentsScreen> {
  // Mock data basado en app_mkt_segmentos y app_mkt_criterios_segmentacion
  final List<Map<String, dynamic>> _segments = [
    {
      'id': 1,
      'nombre': 'Clientes Premium',
      'descripcion': 'Clientes con compras superiores a \$500.000 en los últimos 6 meses',
      'criterios': ['Monto compras > \$500.000', 'Período: 6 meses', 'Estado: Activo'],
      'cantidad_clientes': 1250,
      'fecha_creacion': DateTime(2024, 8, 15),
      'fecha_actualizacion': DateTime(2024, 11, 20),
      'estado': true,
      'conversion_rate': 28.5,
      'valor_promedio_compra': 750000.0,
    },
    {
      'id': 2,
      'nombre': 'Nuevos Clientes',
      'descripcion': 'Clientes registrados en los últimos 30 días',
      'criterios': ['Fecha registro < 30 días', 'Primera compra realizada'],
      'cantidad_clientes': 890,
      'fecha_creacion': DateTime(2024, 10, 1),
      'fecha_actualizacion': DateTime(2024, 11, 22),
      'estado': true,
      'conversion_rate': 15.2,
      'valor_promedio_compra': 125000.0,
    },
    {
      'id': 3,
      'nombre': 'Carrito Abandonado',
      'descripcion': 'Clientes que abandonaron productos en el carrito en los últimos 7 días',
      'criterios': ['Carrito con productos', 'Sin compra en 7 días', 'Valor carrito > \$50.000'],
      'cantidad_clientes': 2340,
      'fecha_creacion': DateTime(2024, 9, 10),
      'fecha_actualizacion': DateTime(2024, 11, 23),
      'estado': true,
      'conversion_rate': 12.8,
      'valor_promedio_compra': 180000.0,
    },
    {
      'id': 4,
      'nombre': 'Clientes Inactivos',
      'descripcion': 'Clientes sin compras en los últimos 90 días',
      'criterios': ['Última compra > 90 días', 'Historial de compras previas'],
      'cantidad_clientes': 5670,
      'fecha_creacion': DateTime(2024, 7, 20),
      'fecha_actualizacion': DateTime(2024, 11, 15),
      'estado': true,
      'conversion_rate': 8.3,
      'valor_promedio_compra': 95000.0,
    },
    {
      'id': 5,
      'nombre': 'Compradores Frecuentes',
      'descripcion': 'Clientes con más de 5 compras en los últimos 3 meses',
      'criterios': ['Número compras > 5', 'Período: 3 meses', 'Compra promedio > \$100.000'],
      'cantidad_clientes': 780,
      'fecha_creacion': DateTime(2024, 8, 5),
      'fecha_actualizacion': DateTime(2024, 11, 18),
      'estado': true,
      'conversion_rate': 35.7,
      'valor_promedio_compra': 320000.0,
    },
    {
      'id': 6,
      'nombre': 'Segmento Experimental',
      'descripcion': 'Segmento de prueba para nuevas estrategias de marketing',
      'criterios': ['Criterios en definición'],
      'cantidad_clientes': 0,
      'fecha_creacion': DateTime(2024, 11, 1),
      'fecha_actualizacion': DateTime(2024, 11, 1),
      'estado': false,
      'conversion_rate': 0.0,
      'valor_promedio_compra': 0.0,
    },
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Segmentación de Clientes'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [
          AppBarStoreSelectorWidget(),
          MarketingMenuWidget(),
        ],
      ),
      body: Column(
        children: [
          _buildStatsCards(),
          Expanded(
            child: _buildSegmentsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateSegmentDialog(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatsCards() {
    final activeSegments = _segments.where((s) => s['estado'] == true).length;
    final totalClients = _segments.fold<int>(0, (sum, s) => sum + (s['cantidad_clientes'] as int));
    final avgConversion = _segments.where((s) => s['estado'] == true && s['cantidad_clientes'] > 0)
        .fold<double>(0, (sum, s) => sum + s['conversion_rate']) / 
        _segments.where((s) => s['estado'] == true && s['cantidad_clientes'] > 0).length;
    final topSegment = _segments.where((s) => s['estado'] == true)
        .reduce((a, b) => a['conversion_rate'] > b['conversion_rate'] ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Segmentos Activos',
                  activeSegments.toString(),
                  Icons.group,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Total Clientes',
                  NumberFormat('#,###').format(totalClients),
                  Icons.people,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'Conversión Prom.',
                  '${avgConversion.toStringAsFixed(1)}%',
                  Icons.trending_up,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.teal.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mejor segmento: ${topSegment['nombre']} (${topSegment['conversion_rate']}% conversión)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
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
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _segments.length,
      itemBuilder: (context, index) {
        final segment = _segments[index];
        return _buildSegmentCard(segment);
      },
    );
  }

  Widget _buildSegmentCard(Map<String, dynamic> segment) {
    final isActive = segment['estado'] as bool;
    final clientCount = segment['cantidad_clientes'] as int;
    final conversionRate = segment['conversion_rate'] as double;
    final avgPurchase = segment['valor_promedio_compra'] as double;

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
                        segment['nombre'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        segment['descripcion'],
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
                _buildStatusChip(isActive),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: (segment['criterios'] as List<String>).map((criterio) =>
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Text(
                    criterio,
                    style: const TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ),
              ).toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.people, size: 16, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            '${NumberFormat('#,###').format(clientCount)} clientes',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.trending_up, size: 16, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Conversión: ${conversionRate.toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.attach_money, size: 16, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            'Compra prom: \$${NumberFormat('#,###').format(avgPurchase)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                      'Creado: ${DateFormat('dd/MM/yyyy').format(segment['fecha_creacion'])}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    Text(
                      'Actualizado: ${DateFormat('dd/MM/yyyy').format(segment['fecha_actualizacion'])}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
                  onPressed: () => _showSegmentDetails(segment),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Ver detalles'),
                ),
                TextButton.icon(
                  onPressed: () => _editSegment(segment),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Editar'),
                ),
                TextButton.icon(
                  onPressed: () => _toggleSegmentStatus(segment),
                  icon: Icon(
                    isActive ? Icons.pause : Icons.play_arrow,
                    size: 16,
                  ),
                  label: Text(isActive ? 'Desactivar' : 'Activar'),
                ),
                if (clientCount == 0)
                  TextButton.icon(
                    onPressed: () => _deleteSegment(segment),
                    icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                    label: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? Colors.green : Colors.grey).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (isActive ? Colors.green : Colors.grey).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.pause_circle,
            size: 12,
            color: isActive ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            isActive ? 'Activo' : 'Inactivo',
            style: TextStyle(
              color: isActive ? Colors.green : Colors.grey,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateSegmentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Segmento'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Nombre del segmento',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              SizedBox(height: 16),
              Text('Criterios de segmentación:',
                style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Selecciona los criterios para definir este segmento',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Segmento creado exitosamente'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _showSegmentDetails(Map<String, dynamic> segment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(segment['nombre']),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Descripción:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(segment['descripcion']),
              const SizedBox(height: 12),
              Text('Criterios:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...(segment['criterios'] as List<String>).map((criterio) => 
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text('• $criterio'),
                ),
              ),
              const SizedBox(height: 12),
              Text('Estadísticas:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Clientes: ${NumberFormat('#,###').format(segment['cantidad_clientes'])}'),
              Text('Tasa de conversión: ${segment['conversion_rate']}%'),
              Text('Compra promedio: \$${NumberFormat('#,###').format(segment['valor_promedio_compra'])}'),
              const SizedBox(height: 8),
              Text('Fechas:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Creado: ${DateFormat('dd/MM/yyyy').format(segment['fecha_creacion'])}'),
              Text('Actualizado: ${DateFormat('dd/MM/yyyy').format(segment['fecha_actualizacion'])}'),
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

  void _editSegment(Map<String, dynamic> segment) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Función de edición en desarrollo'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _toggleSegmentStatus(Map<String, dynamic> segment) {
    setState(() {
      segment['estado'] = !segment['estado'];
      segment['fecha_actualizacion'] = DateTime.now();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          segment['estado'] 
            ? 'Segmento activado exitosamente'
            : 'Segmento desactivado exitosamente'
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _deleteSegment(Map<String, dynamic> segment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Segmento'),
        content: Text('¿Está seguro de eliminar el segmento "${segment['nombre']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _segments.remove(segment);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Segmento eliminado exitosamente'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
