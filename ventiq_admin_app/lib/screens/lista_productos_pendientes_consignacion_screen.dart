import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import 'confirmar_recepcion_consignacion_screen.dart';

class ListaProductosPendientesConsignacionScreen extends StatefulWidget {
  final int idTienda;

  const ListaProductosPendientesConsignacionScreen({
    Key? key,
    required this.idTienda,
  }) : super(key: key);

  @override
  State<ListaProductosPendientesConsignacionScreen> createState() =>
      _ListaProductosPendientesConsignacionScreenState();
}

class _ListaProductosPendientesConsignacionScreenState
    extends State<ListaProductosPendientesConsignacionScreen> {
  List<Map<String, dynamic>> _contratos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContratos();
  }

  Future<void> _loadContratos() async {
    setState(() => _isLoading = true);

    try {
      final contratos = await ConsignacionService.getActiveContratos(widget.idTienda);

      // Filtrar solo contratos donde esta tienda es consignataria
      final contratosConsignataria = contratos
          .where((c) => c['id_tienda_consignataria'] == widget.idTienda)
          .toList();

      setState(() {
        _contratos = contratosConsignataria;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando contratos: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos Pendientes de Confirmación'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadContratos,
              child: _contratos.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _contratos.length,
                      itemBuilder: (context, index) {
                        final contrato = _contratos[index];
                        return _buildContratoCard(contrato);
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            const Text(
              'No hay contratos pendientes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Todos los productos han sido confirmados',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContratoCard(Map<String, dynamic> contrato) {
    final tiendaConsignadora = contrato['tienda_consignadora']['denominacion'] ?? 'Tienda';
    final idContrato = contrato['id'];
    final idTiendaOrigen = contrato['id_tienda_consignadora'];
    final idTiendaDestino = contrato['id_tienda_consignataria'];
    final idAlmacenDestino = contrato['id_almacen_destino'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Información del contrato
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.business,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contrato #$idContrato',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'De: $tiendaConsignadora',
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

            // Estado
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'Tiene productos pendientes',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Botón de acción
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConfirmarRecepcionConsignacionScreen(
                        idContrato: idContrato,
                        idTiendaOrigen: idTiendaOrigen,
                        idTiendaDestino: idTiendaDestino,
                        idAlmacenOrigen: 0, // Se obtiene del contrato si es necesario
                        idAlmacenDestino: idAlmacenDestino ?? 0,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle),
                label: const Text('Ver Productos Pendientes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
