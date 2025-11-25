import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';

class ConsignacionesConsignataiaScreen extends StatefulWidget {
  final int idTienda;

  const ConsignacionesConsignataiaScreen({
    Key? key,
    required this.idTienda,
  }) : super(key: key);

  @override
  State<ConsignacionesConsignataiaScreen> createState() =>
      _ConsignacionesConsignataiaScreenState();
}

class _ConsignacionesConsignataiaScreenState
    extends State<ConsignacionesConsignataiaScreen> {
  List<Map<String, dynamic>> _contratos = [];
  Map<String, dynamic> _estadisticas = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final contratos =
          await ConsignacionService.getContratosComoConsignataria(widget.idTienda);
      final estadisticas =
          await ConsignacionService.getEstadisticasConsignataria(widget.idTienda);

      setState(() {
        _contratos = contratos;
        _estadisticas = estadisticas;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando datos: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consignaciones Recibidas'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Estadísticas
                    _buildEstadisticas(),

                    // Contratos
                    _buildContratos(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEstadisticas() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de Consignaciones',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.2,
            children: [
              _buildStatCard(
                'Contratos Activos',
                '${_estadisticas['total_contratos'] ?? 0}',
                Icons.handshake,
                Colors.blue,
              ),
              _buildStatCard(
                'Total Enviado',
                '${_estadisticas['total_enviado']?.toStringAsFixed(0) ?? 0} unid.',
                Icons.inventory_2,
                Colors.green,
              ),
              _buildStatCard(
                'Total Vendido',
                '${_estadisticas['total_vendido']?.toStringAsFixed(0) ?? 0} unid.',
                Icons.shopping_cart,
                Colors.orange,
              ),
              _buildStatCard(
                'A Pagar (Comisión)',
                '\$${_estadisticas['a_pagar']?.toStringAsFixed(2) ?? '0.00'}',
                Icons.attach_money,
                Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContratos() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Contratos de Consignación',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_contratos.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_contratos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.inbox,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No hay consignaciones recibidas',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _contratos.length,
              itemBuilder: (context, index) {
                final contrato = _contratos[index];
                return _buildContratoCard(contrato);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildContratoCard(Map<String, dynamic> contrato) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_shipping,
                    color: Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'De: ${contrato['tienda_consignadora']['denominacion']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Contrato #${contrato['id']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Comisión y plazo
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'Comisión',
                    '${contrato['porcentaje_comision']}%',
                    Icons.percent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoBox(
                    'Plazo',
                    contrato['plazo_dias'] != null
                        ? '${contrato['plazo_dias']} días'
                        : 'Sin límite',
                    Icons.calendar_today,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Fechas
            Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    'Inicio',
                    contrato['fecha_inicio'] ?? 'N/A',
                    Icons.event_available,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoBox(
                    'Fin',
                    contrato['fecha_fin'] ?? 'Sin fecha',
                    Icons.event,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Botón para ver detalle
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: Navegar a detalle del contrato
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Abriendo detalle del contrato...'),
                    ),
                  );
                },
                icon: const Icon(Icons.info),
                label: const Text('Ver Detalle y Productos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBox(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
