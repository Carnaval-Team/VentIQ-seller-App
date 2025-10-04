import 'package:flutter/material.dart';
import '../../models/supplier.dart';
import '../../widgets/supplier/supplier_selector.dart';
import '../../screens/suppliers/add_edit_supplier_screen.dart';

/// Widget de integración para seleccionar proveedores en recepciones de inventario
class SupplierReceptionIntegration extends StatefulWidget {
  final Supplier? selectedSupplier;
  final Function(Supplier?) onSupplierSelected;
  final bool isRequired;
  
  const SupplierReceptionIntegration({
    super.key,
    this.selectedSupplier,
    required this.onSupplierSelected,
    this.isRequired = true,
  });
  
  @override
  State<SupplierReceptionIntegration> createState() => _SupplierReceptionIntegrationState();
}

class _SupplierReceptionIntegrationState extends State<SupplierReceptionIntegration> {
  
  Future<void> _navigateToCreateSupplier() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddEditSupplierScreen(),
      ),
    );
    
    if (result == true) {
      // Recargar la lista de proveedores en el selector
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Proveedor creado exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.business,
                  size: 20,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Información del Proveedor',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
                if (widget.isRequired)
                  const Text(
                    ' *',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            SupplierSelector(
              selectedSupplier: widget.selectedSupplier,
              onSupplierSelected: widget.onSupplierSelected,
              isRequired: widget.isRequired,
              hintText: 'Seleccionar proveedor para esta recepción',
              onCreateNew: _navigateToCreateSupplier,
            ),
            
            if (widget.selectedSupplier != null) ...[
              const SizedBox(height: 12),
              _buildSupplierInfo(),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildSupplierInfo() {
    final supplier = widget.selectedSupplier!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Información del Proveedor Seleccionado',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 8),
          
          if (supplier.fullAddress.isNotEmpty)
            _buildInfoRow('Dirección', supplier.fullAddress),
          
          if (supplier.leadTime != null)
            _buildInfoRow('Tiempo de Entrega', supplier.leadTimeDisplay),
          
          if (supplier.hasMetrics) ...[
            _buildInfoRow('Órdenes Previas', '${supplier.totalOrders}'),
            _buildInfoRow('Performance', supplier.performanceLevel),
          ],
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
