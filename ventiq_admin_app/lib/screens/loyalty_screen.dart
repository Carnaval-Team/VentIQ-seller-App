import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../widgets/marketing_menu_widget.dart';
import '../widgets/store_selector_widget.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  // Mock data basado en app_mkt_eventos_fidelizacion
  final List<Map<String, dynamic>> _loyaltyEvents = [
    {
      'id': 1,
      'nombre_evento': 'Compra realizada',
      'descripcion': 'Puntos otorgados por cada compra realizada',
      'puntos_otorgados': 100,
      'fecha_evento': DateTime(2024, 11, 23, 14, 30),
      'cliente_id': 'CLI001',
      'cliente_nombre': 'María González',
      'tipo_evento': 'compra',
      'valor_transaccion': 250000.0,
      'estado': 'completado',
    },
    {
      'id': 2,
      'nombre_evento': 'Registro en programa',
      'descripcion': 'Bienvenida al programa de fidelización',
      'puntos_otorgados': 500,
      'fecha_evento': DateTime(2024, 11, 22, 10, 15),
      'cliente_id': 'CLI002',
      'cliente_nombre': 'Carlos Rodríguez',
      'tipo_evento': 'registro',
      'valor_transaccion': 0.0,
      'estado': 'completado',
    },
    {
      'id': 3,
      'nombre_evento': 'Referido exitoso',
      'descripcion': 'Puntos por referir un nuevo cliente',
      'puntos_otorgados': 300,
      'fecha_evento': DateTime(2024, 11, 21, 16, 45),
      'cliente_id': 'CLI003',
      'cliente_nombre': 'Ana Martínez',
      'tipo_evento': 'referido',
      'valor_transaccion': 0.0,
      'estado': 'completado',
    },
    {
      'id': 4,
      'nombre_evento': 'Cumpleaños cliente',
      'descripcion': 'Puntos especiales por cumpleaños',
      'puntos_otorgados': 200,
      'fecha_evento': DateTime(2024, 11, 20, 9, 0),
      'cliente_id': 'CLI004',
      'cliente_nombre': 'Luis Fernández',
      'tipo_evento': 'cumpleanos',
      'valor_transaccion': 0.0,
      'estado': 'completado',
    },
    {
      'id': 5,
      'nombre_evento': 'Canje de puntos',
      'descripcion': 'Descuento aplicado por canje de puntos',
      'puntos_otorgados': -1000,
      'fecha_evento': DateTime(2024, 11, 19, 11, 30),
      'cliente_id': 'CLI001',
      'cliente_nombre': 'María González',
      'tipo_evento': 'canje',
      'valor_transaccion': 100000.0,
      'estado': 'completado',
    },
  ];

  final List<Map<String, dynamic>> _rewards = [
    {
      'id': 1,
      'nombre': 'Descuento 10%',
      'descripcion': 'Descuento del 10% en tu próxima compra',
      'puntos_requeridos': 500,
      'tipo_recompensa': 'descuento',
      'valor_descuento': 10.0,
      'disponible': true,
      'veces_canjeada': 45,
    },
    {
      'id': 2,
      'nombre': 'Envío gratis',
      'descripcion': 'Envío gratuito en tu próximo pedido',
      'puntos_requeridos': 300,
      'tipo_recompensa': 'envio',
      'valor_descuento': 0.0,
      'disponible': true,
      'veces_canjeada': 78,
    },
    {
      'id': 3,
      'nombre': 'Producto gratis',
      'descripcion': 'Producto seleccionado completamente gratis',
      'puntos_requeridos': 2000,
      'tipo_recompensa': 'producto',
      'valor_descuento': 0.0,
      'disponible': true,
      'veces_canjeada': 12,
    },
    {
      'id': 4,
      'nombre': 'Descuento 25%',
      'descripcion': 'Descuento especial del 25% en compras superiores a \$500.000',
      'puntos_requeridos': 1500,
      'tipo_recompensa': 'descuento',
      'valor_descuento': 25.0,
      'disponible': true,
      'veces_canjeada': 23,
    },
  ];

  final List<Map<String, dynamic>> _topCustomers = [
    {
      'cliente_id': 'CLI001',
      'nombre': 'María González',
      'puntos_totales': 2450,
      'puntos_canjeados': 1000,
      'puntos_disponibles': 1450,
      'nivel': 'Gold',
      'compras_totales': 15,
      'valor_total_compras': 3750000.0,
    },
    {
      'cliente_id': 'CLI005',
      'nombre': 'Roberto Silva',
      'puntos_totales': 1890,
      'puntos_canjeados': 500,
      'puntos_disponibles': 1390,
      'nivel': 'Silver',
      'compras_totales': 12,
      'valor_total_compras': 2980000.0,
    },
    {
      'cliente_id': 'CLI003',
      'nombre': 'Ana Martínez',
      'puntos_totales': 1650,
      'puntos_canjeados': 300,
      'puntos_disponibles': 1350,
      'nivel': 'Silver',
      'compras_totales': 10,
      'valor_total_compras': 2100000.0,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programa de Fidelización'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [
          AppBarStoreSelectorWidget(),
          MarketingMenuWidget(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsCards(),
            const SizedBox(height: 20),
            _buildRewardsSection(),
            const SizedBox(height: 20),
            _buildTopCustomersSection(),
            const SizedBox(height: 20),
            _buildRecentEventsSection(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateEventDialog(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalEvents = _loyaltyEvents.length;
    final totalPointsAwarded = _loyaltyEvents.fold<int>(0, (sum, event) => 
        sum + (event['puntos_otorgados'] > 0 ? event['puntos_otorgados'] as int : 0));
    final totalPointsRedeemed = _loyaltyEvents.fold<int>(0, (sum, event) => 
        sum + (event['puntos_otorgados'] < 0 ? -(event['puntos_otorgados'] as int) : 0));
    final activeCustomers = _topCustomers.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen del Programa',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Eventos',
                totalEvents.toString(),
                Icons.event,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                'Puntos +',
                NumberFormat('#,###').format(totalPointsAwarded),
                Icons.add_circle,
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                'Puntos -',
                NumberFormat('#,###').format(totalPointsRedeemed),
                Icons.remove_circle,
                Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatCard(
                'Clientes',
                activeCustomers.toString(),
                Icons.people,
                Colors.purple,
              ),
            ),
          ],
        ),
      ],
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

  Widget _buildRewardsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recompensas Disponibles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () => _showCreateRewardDialog(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Agregar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _rewards.length,
            itemBuilder: (context, index) {
              final reward = _rewards[index];
              return _buildRewardCard(reward);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRewardCard(Map<String, dynamic> reward) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_getRewardIcon(reward['tipo_recompensa']), 
                       color: _getRewardColor(reward['tipo_recompensa']), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reward['nombre'],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                reward['descripcion'],
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${reward['puntos_requeridos']} pts',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                  Text(
                    '${reward['veces_canjeada']} canjes',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopCustomersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top Clientes Fidelizados',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _topCustomers.length,
          itemBuilder: (context, index) {
            final customer = _topCustomers[index];
            return _buildCustomerCard(customer, index + 1);
          },
        ),
      ],
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer, int position) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _getPositionColor(position),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  position.toString(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        customer['nombre'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getLevelColor(customer['nivel']),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          customer['nivel'],
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${customer['puntos_disponibles']} puntos disponibles',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${customer['compras_totales']} compras',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  '\$${NumberFormat('#,###').format(customer['valor_total_compras'])}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Eventos Recientes',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _loyaltyEvents.take(5).length,
          itemBuilder: (context, index) {
            final event = _loyaltyEvents[index];
            return _buildEventCard(event);
          },
        ),
      ],
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final isPositive = event['puntos_otorgados'] > 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (isPositive ? Colors.green : Colors.red).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: (isPositive ? Colors.green : Colors.red).withOpacity(0.3),
                ),
              ),
              child: Icon(
                isPositive ? Icons.add : Icons.remove,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event['nombre_evento'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event['cliente_nombre'],
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(event['fecha_evento']),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isPositive ? '+' : ''}${event['puntos_otorgados']} pts',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
                if (event['valor_transaccion'] > 0)
                  Text(
                    '\$${NumberFormat('#,###').format(event['valor_transaccion'])}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getRewardIcon(String type) {
    switch (type) {
      case 'descuento':
        return Icons.local_offer;
      case 'envio':
        return Icons.local_shipping;
      case 'producto':
        return Icons.card_giftcard;
      default:
        return Icons.star;
    }
  }

  Color _getRewardColor(String type) {
    switch (type) {
      case 'descuento':
        return Colors.orange;
      case 'envio':
        return Colors.blue;
      case 'producto':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _getPositionColor(int position) {
    switch (position) {
      case 1:
        return Colors.amber;
      case 2:
        return Colors.grey;
      case 3:
        return Colors.brown;
      default:
        return Colors.blue;
    }
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'Gold':
        return Colors.amber;
      case 'Silver':
        return Colors.grey;
      case 'Bronze':
        return Colors.brown;
      default:
        return Colors.blue;
    }
  }

  void _showCreateEventDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Evento de Fidelización'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Nombre del evento',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Cliente ID',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Puntos a otorgar',
                  border: OutlineInputBorder(),
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
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Evento creado exitosamente'),
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

  void _showCreateRewardDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Recompensa'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: 'Nombre de la recompensa',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Puntos requeridos',
                  border: OutlineInputBorder(),
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
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Recompensa creada exitosamente'),
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
}
