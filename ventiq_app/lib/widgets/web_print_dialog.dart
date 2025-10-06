import 'package:flutter/material.dart';
import '../models/order.dart';

/// Widget de diálogo específico para impresión web
/// Muestra información sobre la impresión web y opciones disponibles
class WebPrintDialog extends StatelessWidget {
  final Order order;
  final VoidCallback? onPrint;
  final VoidCallback? onCancel;

  const WebPrintDialog({
    Key? key,
    required this.order,
    this.onPrint,
    this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.print, color: Colors.blue),
          SizedBox(width: 8),
          Text('Impresión Web'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Información de la orden
            _buildOrderInfo(),
            SizedBox(height: 16),
            
            // Información sobre impresión web
            _buildWebPrintInfo(),
            SizedBox(height: 16),
            
            // Instrucciones
            _buildInstructions(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel ?? () => Navigator.of(context).pop(false),
          child: Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: onPrint ?? () => Navigator.of(context).pop(true),
          icon: Icon(Icons.print),
          label: Text('Imprimir'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildOrderInfo() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Información de la Orden',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue[800],
            ),
          ),
          SizedBox(height: 8),
          _buildInfoRow('Orden:', order.id),
          _buildInfoRow('Cliente:', order.buyerName ?? 'Cliente General'),
          _buildInfoRow('Total:', '\$${order.total.toStringAsFixed(2)}'),
          _buildInfoRow('Productos:', '${order.totalItems}'),
          _buildInfoRow('Estado:', order.status.displayName),
        ],
      ),
    );
  }

  Widget _buildWebPrintInfo() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.computer, color: Colors.green[700], size: 20),
              SizedBox(width: 8),
              Text(
                'Impresión Web Disponible',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• Impresoras de red (WiFi/Ethernet)',
            style: TextStyle(color: Colors.green[700]),
          ),
          Text(
            '• Impresoras USB conectadas a la PC',
            style: TextStyle(color: Colors.green[700]),
          ),
          Text(
            '• Impresoras predeterminadas del sistema',
            style: TextStyle(color: Colors.green[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber[700], size: 20),
              SizedBox(width: 8),
              Text(
                'Instrucciones',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber[800],
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '1. Se abrirá el diálogo de impresión del navegador',
            style: TextStyle(color: Colors.amber[700], fontSize: 13),
          ),
          Text(
            '2. Selecciona tu impresora (red o USB)',
            style: TextStyle(color: Colors.amber[700], fontSize: 13),
          ),
          Text(
            '3. Ajusta la configuración si es necesario',
            style: TextStyle(color: Colors.amber[700], fontSize: 13),
          ),
          Text(
            '4. Haz clic en "Imprimir" en el diálogo',
            style: TextStyle(color: Colors.amber[700], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.blue[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.blue[800]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Función helper para mostrar el diálogo de impresión web
Future<bool> showWebPrintDialog(BuildContext context, Order order) async {
  return await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return WebPrintDialog(order: order);
    },
  ) ?? false;
}
