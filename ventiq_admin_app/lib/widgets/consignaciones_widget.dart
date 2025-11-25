import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../screens/consignaciones_consignataria_screen.dart';
import '../screens/confirmar_recepcion_consignacion_screen.dart';

class ConsignacionesWidget extends StatefulWidget {
  final int idTienda;

  const ConsignacionesWidget({
    Key? key,
    required this.idTienda,
  }) : super(key: key);

  @override
  State<ConsignacionesWidget> createState() => _ConsignacionesWidgetState();
}

class _ConsignacionesWidgetState extends State<ConsignacionesWidget> {
  Map<String, dynamic>? _estadisticas;
  bool _isLoading = true;
  bool _hasConsignaciones = false;

  @override
  void initState() {
    super.initState();
    _loadEstadisticas();
  }

  Future<void> _loadEstadisticas() async {
    try {
      final stats =
          await ConsignacionService.getEstadisticasConsignataria(widget.idTienda);

      if (!mounted) return;

      final tieneConsignaciones = (stats['total_contratos'] as int) > 0;

      setState(() {
        _estadisticas = stats;
        _hasConsignaciones = tieneConsignaciones;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando estadísticas: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_hasConsignaciones) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              Colors.red.shade50,
              Colors.orange.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.orange.shade300,
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.local_shipping,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '⚠️ Consignaciones Pendientes',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        Text(
                          'Tienes ${_estadisticas?['total_contratos'] ?? 0} contrato(s) activo(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Estadísticas rápidas
              Row(
                children: [
                  Expanded(
                    child: _buildQuickStat(
                      'Vendido',
                      '${_estadisticas?['total_vendido']?.toStringAsFixed(0) ?? 0}',
                      Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickStat(
                      'A Pagar',
                      '\$${_estadisticas?['a_pagar']?.toStringAsFixed(2) ?? '0.00'}',
                      Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Botones de acción
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ConfirmarRecepcionConsignacionScreen(idTienda: widget.idTienda),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Confirmar Recepción'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ConsignacionesConsignataiaScreen(idTienda: widget.idTienda),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Ver Detalles'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
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

  Widget _buildQuickStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
