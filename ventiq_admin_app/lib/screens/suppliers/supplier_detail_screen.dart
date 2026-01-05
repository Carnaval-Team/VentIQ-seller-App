import 'package:flutter/material.dart';
import '../../models/supplier.dart';
import '../../models/supplier_contact.dart';
import '../../services/supplier_service.dart';
import 'add_edit_supplier_screen.dart';
import '../../utils/navigation_guard.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  late Supplier _supplier;
  Map<String, dynamic>? _metrics;
  List<SupplierContact> _contacts = [];
  bool _isLoadingMetrics = true;
  bool _isLoadingContacts = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _loadSupplierData();
  }

  Future<void> _loadSupplierData() async {
    await Future.wait([_loadMetrics(), _loadContacts()]);
  }

  Future<void> _loadMetrics() async {
    try {
      setState(() => _isLoadingMetrics = true);
      final metrics = await SupplierService.getSupplierMetrics(_supplier.id);
      setState(() {
        _metrics = metrics;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMetrics = false;
        _errorMessage = 'Error al cargar métricas: $e';
      });
    }
  }

  Future<void> _loadContacts() async {
    try {
      setState(() => _isLoadingContacts = true);
      final contacts = await SupplierService.getSupplierContacts(_supplier.id);
      setState(() {
        _contacts = contacts;
        _isLoadingContacts = false;
      });
    } catch (e) {
      setState(() => _isLoadingContacts = false);
      print('Error al cargar contactos: $e');
    }
  }

  Future<void> _navigateToEdit() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditSupplierScreen(supplier: _supplier),
      ),
    );

    if (result == true) {
      // Recargar datos del proveedor
      final updatedSupplier = await SupplierService.getSupplierById(
        _supplier.id,
        includeMetrics: true,
      );
      if (updatedSupplier != null) {
        setState(() => _supplier = updatedSupplier);
        _loadSupplierData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_supplier.denominacion),
        actions: [
          FutureBuilder<bool>(
            future: NavigationGuard.canPerformAction('supplier.edit'),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _navigateToEdit,
                  tooltip: 'Editar proveedor',
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSupplierData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSupplierData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Información básica
              _buildBasicInfoCard(),

              const SizedBox(height: 16),

              // Métricas
              _buildMetricsCard(),

              const SizedBox(height: 16),

              // Contactos
              _buildContactsCard(),

              const SizedBox(height: 16),

              // Información adicional
              _buildAdditionalInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.business, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Información Básica',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _buildInfoRow('Nombre', _supplier.denominacion),
            _buildInfoRow('Código SKU', _supplier.skuCodigo),

            if (_supplier.direccion != null)
              _buildInfoRow('Dirección', _supplier.direccion!),

            if (_supplier.ubicacion != null)
              _buildInfoRow('Ubicación', _supplier.ubicacion!),

            if (_supplier.leadTime != null)
              _buildInfoRow('Tiempo de Entrega', _supplier.leadTimeDisplay),

            _buildInfoRow('Creado', _formatDate(_supplier.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  'Métricas de Performance',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_isLoadingMetrics)
              const Center(child: CircularProgressIndicator())
            else if (_metrics != null)
              _buildMetricsContent()
            else
              const Text('No se pudieron cargar las métricas'),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsContent() {
    final metrics = _metrics!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'Total Recepciones',
                '${metrics['total_recepciones'] ?? 0}',
                Icons.shopping_cart,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                'Productos Únicos',
                '${metrics['productos_unicos'] ?? 0}',
                Icons.inventory,
                Colors.orange,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                'Valor Total',
                '\$${(metrics['valor_total_compras'] ?? 0).toStringAsFixed(2)}',
                Icons.attach_money,
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricTile(
                'Promedio/Orden',
                '\$${(metrics['valor_promedio_orden'] ?? 0).toStringAsFixed(2)}',
                Icons.trending_up,
                Colors.purple,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        if (metrics['ultima_recepcion'] != null)
          _buildInfoRow(
            'Última Recepción',
            _formatDate(DateTime.parse(metrics['ultima_recepcion'])),
          ),

        _buildInfoRow(
          'Performance Score',
          metrics['performance_score'] ?? 'Sin datos',
        ),
      ],
    );
  }

  Widget _buildMetricTile(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
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
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildContactsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.contacts, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Contactos',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (_isLoadingContacts)
              const Center(child: CircularProgressIndicator())
            else if (_contacts.isEmpty)
              const Text('No hay contactos registrados')
            else
              ..._contacts.map((contact) => _buildContactTile(contact)),
          ],
        ),
      ),
    );
  }

  Widget _buildContactTile(SupplierContact contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                contact.nombre,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (contact.isPrimary) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Principal',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (contact.cargo != null) ...[
            const SizedBox(height: 4),
            Text(
              contact.cargo!,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],

          if (contact.telefono != null || contact.email != null) ...[
            const SizedBox(height: 8),
            if (contact.telefono != null)
              Row(
                children: [
                  Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(contact.telefono!, style: const TextStyle(fontSize: 12)),
                ],
              ),
            if (contact.email != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.email, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(contact.email!, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAdditionalInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(
                  'Información Adicional',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _buildInfoRow('ID', _supplier.id.toString()),
            _buildInfoRow('Estado', _supplier.isActive ? 'Activo' : 'Inactivo'),

            if (_supplier.hasMetrics)
              _buildInfoRow('Nivel de Performance', _supplier.performanceLevel),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
