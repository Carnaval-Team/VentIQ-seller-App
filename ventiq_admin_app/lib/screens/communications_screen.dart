import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../widgets/marketing_menu_widget.dart';
import '../widgets/store_selector_widget.dart';

class CommunicationsScreen extends StatefulWidget {
  const CommunicationsScreen({super.key});

  @override
  State<CommunicationsScreen> createState() => _CommunicationsScreenState();
}

class _CommunicationsScreenState extends State<CommunicationsScreen> {
  // Mock data basado en app_mkt_comunicaciones
  final List<Map<String, dynamic>> _communications = [
    {
      'id': 1,
      'asunto': 'Oferta especial Black Friday',
      'mensaje': 'No te pierdas nuestras increíbles ofertas del Black Friday. Descuentos de hasta 70% en productos seleccionados.',
      'fecha_programada': DateTime(2024, 11, 24, 9, 0),
      'fecha_enviada': DateTime(2024, 11, 24, 9, 15),
      'estado': 'enviada',
      'tipo_comunicacion': 'email',
      'destinatarios': 12500,
      'aperturas': 4275,
      'clicks': 1089,
      'segmento_objetivo': 'Todos los clientes',
    },
    {
      'id': 2,
      'asunto': 'Bienvenida nuevos productos',
      'mensaje': 'Te presentamos nuestra nueva colección de verano. Productos frescos y modernos para esta temporada.',
      'fecha_programada': DateTime(2024, 12, 1, 10, 0),
      'fecha_enviada': null,
      'estado': 'programada',
      'tipo_comunicacion': 'email',
      'destinatarios': 8900,
      'aperturas': 0,
      'clicks': 0,
      'segmento_objetivo': 'Clientes activos',
    },
    {
      'id': 3,
      'asunto': 'Recordatorio carrito abandonado',
      'mensaje': 'Tienes productos esperándote en tu carrito. Completa tu compra y recibe envío gratis.',
      'fecha_programada': DateTime(2024, 11, 20, 15, 30),
      'fecha_enviada': DateTime(2024, 11, 20, 15, 35),
      'estado': 'enviada',
      'tipo_comunicacion': 'email',
      'destinatarios': 2340,
      'aperturas': 892,
      'clicks': 234,
      'segmento_objetivo': 'Carrito abandonado',
    },
    {
      'id': 4,
      'asunto': 'Felicitaciones navideñas',
      'mensaje': 'Te deseamos una feliz navidad y un próspero año nuevo. Gracias por ser parte de nuestra familia.',
      'fecha_programada': DateTime(2024, 12, 24, 8, 0),
      'fecha_enviada': null,
      'estado': 'borrador',
      'tipo_comunicacion': 'email',
      'destinatarios': 15600,
      'aperturas': 0,
      'clicks': 0,
      'segmento_objetivo': 'Todos los clientes',
    },
    {
      'id': 5,
      'asunto': 'Promoción flash - 24 horas',
      'mensaje': 'Solo por 24 horas: 50% de descuento en productos seleccionados. ¡No te lo pierdas!',
      'fecha_programada': DateTime(2024, 11, 15, 12, 0),
      'fecha_enviada': DateTime(2024, 11, 15, 12, 5),
      'estado': 'enviada',
      'tipo_comunicacion': 'sms',
      'destinatarios': 5600,
      'aperturas': 4200,
      'clicks': 1680,
      'segmento_objetivo': 'Clientes premium',
    },
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comunicaciones'),
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
            child: _buildCommunicationsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateCommunicationDialog(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalSent = _communications.where((c) => c['estado'] == 'enviada').length;
    final totalScheduled = _communications.where((c) => c['estado'] == 'programada').length;
    final totalRecipients = _communications.fold<int>(0, (sum, c) => sum + (c['destinatarios'] as int));
    final totalOpens = _communications.fold<int>(0, (sum, c) => sum + (c['aperturas'] as int));
    final openRate = totalRecipients > 0 ? (totalOpens / totalRecipients * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Enviadas',
              totalSent.toString(),
              Icons.send,
              Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Programadas',
              totalScheduled.toString(),
              Icons.schedule,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Destinatarios',
              NumberFormat('#,###').format(totalRecipients),
              Icons.people,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              'Tasa Apertura',
              '$openRate%',
              Icons.open_in_new,
              Colors.purple,
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

  Widget _buildCommunicationsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _communications.length,
      itemBuilder: (context, index) {
        final communication = _communications[index];
        return _buildCommunicationCard(communication);
      },
    );
  }

  Widget _buildCommunicationCard(Map<String, dynamic> communication) {
    final estado = communication['estado'] as String;
    final tipo = communication['tipo_comunicacion'] as String;
    final fechaProgramada = communication['fecha_programada'] as DateTime;
    final fechaEnviada = communication['fecha_enviada'] as DateTime?;

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
                        communication['asunto'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        communication['mensaje'],
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
                _buildStatusChip(estado),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip(
                  _getTypeIcon(tipo),
                  tipo.toUpperCase(),
                  _getTypeColor(tipo),
                ),
                const SizedBox(width: 8),
                _buildInfoChip(
                  Icons.group,
                  communication['segmento_objetivo'],
                  Colors.blue,
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
                        'Programada: ${DateFormat('dd/MM/yyyy HH:mm').format(fechaProgramada)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      if (fechaEnviada != null)
                        Text(
                          'Enviada: ${DateFormat('dd/MM/yyyy HH:mm').format(fechaEnviada)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Destinatarios: ${NumberFormat('#,###').format(communication['destinatarios'])}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (estado == 'enviada')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Aperturas: ${NumberFormat('#,###').format(communication['aperturas'])}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        'Clicks: ${NumberFormat('#,###').format(communication['clicks'])}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        'CTR: ${communication['destinatarios'] > 0 ? (communication['clicks'] / communication['destinatarios'] * 100).toStringAsFixed(1) : '0'}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (estado == 'borrador')
                  TextButton.icon(
                    onPressed: () => _editCommunication(communication),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Editar'),
                  ),
                if (estado == 'programada')
                  TextButton.icon(
                    onPressed: () => _cancelCommunication(communication),
                    icon: const Icon(Icons.cancel, size: 16),
                    label: const Text('Cancelar'),
                  ),
                TextButton.icon(
                  onPressed: () => _showCommunicationDetails(communication),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Ver detalles'),
                ),
                if (estado == 'enviada')
                  TextButton.icon(
                    onPressed: () => _showAnalytics(communication),
                    icon: const Icon(Icons.analytics, size: 16),
                    label: const Text('Analíticas'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String estado) {
    Color color;
    String text;
    IconData icon;

    switch (estado) {
      case 'enviada':
        color = Colors.green;
        text = 'Enviada';
        icon = Icons.check_circle;
        break;
      case 'programada':
        color = Colors.orange;
        text = 'Programada';
        icon = Icons.schedule;
        break;
      case 'borrador':
        color = Colors.grey;
        text = 'Borrador';
        icon = Icons.edit;
        break;
      default:
        color = Colors.grey;
        text = 'Desconocido';
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'email':
        return Icons.email;
      case 'sms':
        return Icons.sms;
      case 'push':
        return Icons.notifications;
      case 'whatsapp':
        return Icons.chat;
      default:
        return Icons.message;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'email':
        return Colors.blue;
      case 'sms':
        return Colors.green;
      case 'push':
        return Colors.orange;
      case 'whatsapp':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  void _showCreateCommunicationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Comunicación'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Asunto',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Mensaje',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Fecha y hora programada',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
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
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Comunicación creada exitosamente'),
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

  void _showCommunicationDetails(Map<String, dynamic> communication) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(communication['asunto']),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mensaje:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(communication['mensaje']),
              const SizedBox(height: 12),
              Text('Tipo: ${communication['tipo_comunicacion'].toString().toUpperCase()}'),
              const SizedBox(height: 8),
              Text('Segmento: ${communication['segmento_objetivo']}'),
              const SizedBox(height: 8),
              Text('Estado: ${communication['estado']}'),
              const SizedBox(height: 8),
              Text('Programada: ${DateFormat('dd/MM/yyyy HH:mm').format(communication['fecha_programada'])}'),
              if (communication['fecha_enviada'] != null) ...[
                const SizedBox(height: 8),
                Text('Enviada: ${DateFormat('dd/MM/yyyy HH:mm').format(communication['fecha_enviada'])}'),
              ],
              const SizedBox(height: 8),
              Text('Destinatarios: ${NumberFormat('#,###').format(communication['destinatarios'])}'),
              if (communication['estado'] == 'enviada') ...[
                const SizedBox(height: 8),
                Text('Aperturas: ${NumberFormat('#,###').format(communication['aperturas'])}'),
                const SizedBox(height: 8),
                Text('Clicks: ${NumberFormat('#,###').format(communication['clicks'])}'),
              ],
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

  void _editCommunication(Map<String, dynamic> communication) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Función de edición en desarrollo'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _cancelCommunication(Map<String, dynamic> communication) {
    setState(() {
      communication['estado'] = 'borrador';
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Comunicación cancelada exitosamente'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showAnalytics(Map<String, dynamic> communication) {
    final openRate = communication['destinatarios'] > 0 
        ? (communication['aperturas'] / communication['destinatarios'] * 100).toStringAsFixed(1)
        : '0';
    final clickRate = communication['destinatarios'] > 0 
        ? (communication['clicks'] / communication['destinatarios'] * 100).toStringAsFixed(1)
        : '0';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analíticas de Comunicación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAnalyticRow('Destinatarios', NumberFormat('#,###').format(communication['destinatarios'])),
            _buildAnalyticRow('Aperturas', NumberFormat('#,###').format(communication['aperturas'])),
            _buildAnalyticRow('Tasa de apertura', '$openRate%'),
            _buildAnalyticRow('Clicks', NumberFormat('#,###').format(communication['clicks'])),
            _buildAnalyticRow('Tasa de click', '$clickRate%'),
          ],
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

  Widget _buildAnalyticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
