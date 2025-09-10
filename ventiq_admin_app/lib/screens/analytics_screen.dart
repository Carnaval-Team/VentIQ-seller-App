import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../widgets/marketing_menu_widget.dart';
import '../widgets/store_selector_widget.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedPeriod = '30d';
  
  // Mock data basado en el esquema de base de datos
  final Map<String, dynamic> _promotionStats = {
    'total_promociones': 45,
    'promociones_activas': 12,
    'promociones_vencidas': 8,
    'total_usos': 1247,
    'descuento_total_aplicado': 125430.50,
    'roi_promociones': 3.2,
    'conversion_rate': 18.5,
  };

  final Map<String, dynamic> _campaignStats = {
    'total_campanas': 8,
    'campanas_activas': 3,
    'presupuesto_total': 450000.0,
    'presupuesto_usado': 287500.0,
    'alcance_total': 15420,
    'engagement_rate': 12.3,
  };

  final Map<String, dynamic> _communicationStats = {
    'total_comunicaciones': 156,
    'comunicaciones_enviadas': 142,
    'tasa_apertura': 34.2,
    'tasa_click': 8.7,
    'comunicaciones_programadas': 14,
  };

  final Map<String, dynamic> _segmentStats = {
    'total_segmentos': 12,
    'segmentos_activos': 9,
    'clientes_segmentados': 3420,
    'segmento_mas_activo': 'Clientes Premium',
    'conversion_promedio': 22.1,
  };

  final Map<String, dynamic> _loyaltyStats = {
    'eventos_fidelizacion': 89,
    'puntos_otorgados': 45670,
    'puntos_canjeados': 12340,
    'clientes_activos': 567,
    'recompensas_disponibles': 23,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Análisis y Métricas'),
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
            _buildPeriodSelector(),
            const SizedBox(height: 20),
            _buildPromotionAnalytics(),
            const SizedBox(height: 20),
            _buildCampaignAnalytics(),
            const SizedBox(height: 20),
            _buildCommunicationAnalytics(),
            const SizedBox(height: 20),
            _buildSegmentAnalytics(),
            const SizedBox(height: 20),
            _buildLoyaltyAnalytics(),
            const SizedBox(height: 20),
            _buildPerformanceChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.date_range, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Período:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedPeriod,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: '7d', child: Text('Últimos 7 días')),
                  DropdownMenuItem(value: '30d', child: Text('Últimos 30 días')),
                  DropdownMenuItem(value: '90d', child: Text('Últimos 90 días')),
                  DropdownMenuItem(value: '1y', child: Text('Último año')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedPeriod = value!;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotionAnalytics() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_offer, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Análisis de Promociones', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard('Total', _promotionStats['total_promociones'].toString(), Icons.campaign, Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Activas', _promotionStats['promociones_activas'].toString(), Icons.check_circle, Colors.green)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Vencidas', _promotionStats['promociones_vencidas'].toString(), Icons.schedule, Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('Usos', NumberFormat('#,###').format(_promotionStats['total_usos']), Icons.trending_up, Colors.purple)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Descuento', '\$${NumberFormat('#,###').format(_promotionStats['descuento_total_aplicado'])}', Icons.money_off, Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('ROI', '${_promotionStats['roi_promociones']}x', Icons.analytics, Colors.indigo)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Conversión', '${_promotionStats['conversion_rate']}%', Icons.trending_up, Colors.teal)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampaignAnalytics() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign, color: Colors.purple),
                const SizedBox(width: 8),
                const Text('Análisis de Campañas', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard('Total', _campaignStats['total_campanas'].toString(), Icons.campaign, Colors.purple)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Activas', _campaignStats['campanas_activas'].toString(), Icons.play_circle, Colors.green)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('Presupuesto', '\$${NumberFormat('#,###').format(_campaignStats['presupuesto_total'])}', Icons.attach_money, Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Usado', '\$${NumberFormat('#,###').format(_campaignStats['presupuesto_usado'])}', Icons.money_off, Colors.orange)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('Alcance', NumberFormat('#,###').format(_campaignStats['alcance_total']), Icons.people, Colors.indigo)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Engagement', '${_campaignStats['engagement_rate']}%', Icons.favorite, Colors.red)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommunicationAnalytics() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.email, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Análisis de Comunicaciones', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard('Total', _communicationStats['total_comunicaciones'].toString(), Icons.email, Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Enviadas', _communicationStats['comunicaciones_enviadas'].toString(), Icons.send, Colors.green)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Programadas', _communicationStats['comunicaciones_programadas'].toString(), Icons.schedule, Colors.orange)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('Apertura', '${_communicationStats['tasa_apertura']}%', Icons.open_in_new, Colors.purple)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Click', '${_communicationStats['tasa_click']}%', Icons.touch_app, Colors.teal)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentAnalytics() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group, color: Colors.teal),
                const SizedBox(width: 8),
                const Text('Análisis de Segmentos', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard('Segmentos', _segmentStats['total_segmentos'].toString(), Icons.group, Colors.teal)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Activos', _segmentStats['segmentos_activos'].toString(), Icons.check_circle, Colors.green)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('Clientes', NumberFormat('#,###').format(_segmentStats['clientes_segmentados']), Icons.people, Colors.blue)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Conversión', '${_segmentStats['conversion_promedio']}%', Icons.trending_up, Colors.purple)),
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
                    child: Text('Segmento más activo: ${_segmentStats['segmento_mas_activo']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoyaltyAnalytics() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.loyalty, color: Colors.amber),
                const SizedBox(width: 8),
                const Text('Análisis de Fidelización', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStatCard('Eventos', _loyaltyStats['eventos_fidelizacion'].toString(), Icons.event, Colors.amber)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Clientes', _loyaltyStats['clientes_activos'].toString(), Icons.people, Colors.blue)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard('Puntos +', NumberFormat('#,###').format(_loyaltyStats['puntos_otorgados']), Icons.add_circle, Colors.green)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('Puntos -', NumberFormat('#,###').format(_loyaltyStats['puntos_canjeados']), Icons.remove_circle, Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text('${_loyaltyStats['recompensas_disponibles']} recompensas disponibles',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('Rendimiento General', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bar_chart, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Gráfico de rendimiento',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                    Text('(Implementación pendiente)',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
