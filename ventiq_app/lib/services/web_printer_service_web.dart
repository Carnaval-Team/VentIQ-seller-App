import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/user_preferences_service.dart';

/// Implementación web del servicio de impresión
class WebPrinterServiceImpl {
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  /// Muestra diálogo de confirmación de impresión para web
  Future<bool> showPrintConfirmationDialog(
    BuildContext context,
    Order order,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.print, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Imprimir Factura'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Deseas imprimir la factura de la orden?'),
                  SizedBox(height: 12),
                  Container(
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
                          'Orden: ${order.id}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('Cliente: ${order.buyerName ?? 'Sin nombre'}'),
                        Text('Total: \$${order.total.toStringAsFixed(2)}'),
                        Text('Productos: ${order.totalItems}'),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.amber[700],
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Se abrirá el diálogo de impresión del navegador',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: Icon(Icons.print),
                  label: Text('Imprimir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  /// Imprime la factura usando la API de impresión del navegador
  /// Imprime ticket del cliente, copia del vendedor y guía de picking para el almacenero
  Future<bool> printInvoice(Order order) async {
    try {
      print('🖨️ Iniciando impresión web completa para orden ${order.id}');

      // ========== IMPRIMIR TICKET DEL CLIENTE PRIMERO ==========
      print('📄 Imprimiendo ticket del cliente...');
      final customerResult = await _printCustomerTicket(order);

      if (!customerResult) {
        print('❌ Ticket del cliente falló al imprimir');
        return false;
      }

      // Esperar entre impresiones para evitar problemas
      print('⏳ Esperando 2 segundos antes de la copia del vendedor...');
      await Future.delayed(const Duration(seconds: 2));

      // ========== IMPRIMIR COPIA DEL VENDEDOR ==========
      print('🧾 Imprimiendo copia del vendedor...');
      final sellerResult = await _printCustomerTicket(
        order,
        copyLabel: 'COPIA VENDEDOR',
      );

      if (!sellerResult) {
        print('❌ Copia del vendedor falló al imprimir');
        return false;
      }

      // Esperar entre impresiones para evitar problemas
      print('⏳ Esperando 2 segundos antes de la guía de almacén...');
      await Future.delayed(const Duration(seconds: 2));

      // ========== IMPRIMIR GUÍA DE PICKING PARA ALMACENERO ==========
      print('🏭 Imprimiendo guía de picking para almacenero...');
      final warehouseResult = await _printWarehousePickingSlip(order);

      if (!warehouseResult) {
        print('❌ Guía de picking falló al imprimir');
        return false;
      }

      print(
        '✅ Ticket cliente, copia vendedor y guía de picking enviados a impresión web',
      );
      return true;
    } catch (e) {
      print('❌ Error imprimiendo factura web: $e');
      return false;
    }
  }

  /// Imprime el ticket del cliente (o copia del vendedor)
  Future<bool> _printCustomerTicket(Order order, {String? copyLabel}) async {
    try {
      // Generar el HTML del ticket del cliente
      final customerHtml = await _generateCustomerTicketHtml(
        order,
        copyLabel: copyLabel,
      );

      // Crear un blob con el HTML
      final blob = html.Blob([customerHtml], 'text/html');
      final url = html.Url.createObjectUrlFromBlob(blob);

      // Abrir en nueva ventana
      html.window.open(url, '_blank');

      // Limpiar el URL inmediatamente después de abrir
      Future.delayed(Duration(milliseconds: 100), () {
        try {
          html.Url.revokeObjectUrl(url);
        } catch (e) {
          print('❌ Error al limpiar URL del ticket: $e');
        }
      });

      final label =
          (copyLabel != null && copyLabel.isNotEmpty)
              ? copyLabel.toLowerCase()
              : 'cliente';
      print('✅ Ticket $label enviado a impresión web');
      return true;
    } catch (e) {
      final label =
          (copyLabel != null && copyLabel.isNotEmpty)
              ? copyLabel.toLowerCase()
              : 'cliente';
      print('❌ Error imprimiendo ticket $label: $e');
      return false;
    }
  }

  /// Imprime la guía de picking para el almacenero
  Future<bool> _printWarehousePickingSlip(Order order) async {
    try {
      // Generar el HTML de la guía de picking
      final warehouseHtml = await _generateWarehousePickingSlipHtml(order);

      // Crear un blob con el HTML
      final blob = html.Blob([warehouseHtml], 'text/html');
      final url = html.Url.createObjectUrlFromBlob(blob);

      // Abrir en nueva ventana
      html.window.open(url, '_blank');

      // Limpiar el URL inmediatamente después de abrir
      Future.delayed(Duration(milliseconds: 100), () {
        try {
          html.Url.revokeObjectUrl(url);
        } catch (e) {
          print('❌ Error al limpiar URL de picking: $e');
        }
      });

      print('✅ Guía de picking enviada a impresión web');
      return true;
    } catch (e) {
      print('❌ Error imprimiendo guía de picking: $e');
      return false;
    }
  }

  /// Genera el HTML del ticket del cliente para impresión
  Future<String> _generateCustomerTicketHtml(
    Order order, {
    String? copyLabel,
  }) async {
    // Obtener datos del usuario y tienda (no necesarios para este formato simplificado)

    // Fecha y hora actual
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // Generar filas de productos (formato igual al Bluetooth)
    final productRows = order.items
        .where((item) => item.subtotal > 0)
        .map((item) {
          final itemTotal = item.cantidad * item.precioUnitario;
          return '''
        <div class="product-line">${item.cantidad}x ${item.nombre}</div>
        <div class="product-price">\$${item.precioUnitario.toStringAsFixed(0)} c/u = \$${itemTotal.toStringAsFixed(0)}</div>
          ''';
        })
        .join('');

    final copyLabelHtml =
        copyLabel != null && copyLabel.isNotEmpty
            ? '<div class="copy-label">$copyLabel</div>'
            : '';

    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Factura - ${order.id}</title>
    <style>
        @media print {
            body { margin: 0; }
            .no-print { display: none; }
        }
        body {
            font-family: 'Courier New', monospace;
            font-size: 14px;
            line-height: 1.2;
            margin: 20px auto;
            color: #000;
            max-width: 400px;
            text-align: center;
        }
        .header {
            text-align: center;
            margin-bottom: 20px;
        }
        .store-name {
            font-size: 24px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .system-name {
            font-size: 14px;
            margin-bottom: 5px;
        }
        .invoice-title {
            font-size: 16px;
            font-weight: bold;
            margin-bottom: 10px;
        }
        .copy-label {
            font-size: 13px;
            font-weight: bold;
            letter-spacing: 1px;
            margin-bottom: 8px;
        }
        .separator {
            text-align: center;
            margin: 10px 0;
            font-weight: bold;
        }
        .info-section {
            text-align: left;
            margin: 15px 0;
        }
        .info-line {
            margin: 3px 0;
            font-weight: bold;
        }
        .products-header {
            text-align: left;
            font-weight: bold;
            margin: 15px 0 5px 0;
        }
        .product-line {
            text-align: left;
            margin: 2px 0;
        }
        .product-price {
            text-align: right;
            margin: 2px 0;
        }
        .totals-section {
            margin: 15px 0;
        }
        .total-line {
            text-align: right;
            margin: 3px 0;
            font-weight: bold;
        }
        .final-total {
            font-size: 18px;
            font-weight: bold;
            text-align: right;
            margin: 5px 0;
        }
        .footer {
            text-align: center;
            margin-top: 20px;
        }
        .notes {
            text-align: left;
            margin: 15px 0;
        }
        @media print {
            body { margin: 0; font-size: 12px; }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="store-name">INVENTTIA</div>
        <div class="system-name">Sistema de Ventas</div>
        <div class="invoice-title">FACTURA DE VENTA</div>
        $copyLabelHtml
        <div class="separator">================================</div>
    </div>

    <div class="info-section">
        <div class="info-line">ORDEN: ${order.id}</div>
        ${order.buyerName != null && order.buyerName!.isNotEmpty ? '<div class="info-line">CLIENTE: ${order.buyerName}</div>' : ''}
        ${order.buyerPhone != null && order.buyerPhone!.isNotEmpty ? '<div class="info-line">TELEFONO: ${order.buyerPhone}</div>' : ''}
        <div class="info-line">FECHA: $dateStr $timeStr</div>
        <div class="info-line">PAGO: ${order.paymentMethod ?? 'Completado'}</div>
    </div>

    <div class="products-header">PRODUCTOS:</div>
    <div class="separator">--------------------------------</div>
    
    $productRows

    <div class="totals-section">
        <div class="separator">--------------------------------</div>
        <div class="total-line">SUBTOTAL: \$${order.total.toStringAsFixed(0)}</div>
        <div class="final-total">TOTAL: \$${order.total.toStringAsFixed(0)}</div>
    </div>

    <div class="footer">
        <div>¡Gracias por su compra!</div>
        <div>INVENTTIA - Sistema de Ventas</div>
    </div>

    ${order.notas != null && order.notas!.isNotEmpty ? '<div class="notes">Notas: ${order.notas}</div>' : ''}

    <script>
        // Auto-imprimir cuando se carga la página
        window.onload = function() {
            setTimeout(function() {
                window.print();
                
                // Cerrar la ventana después de imprimir
                setTimeout(function() {
                    window.close();
                }, 1000);
            }, 800);
        };
        
        // También manejar el evento afterprint para cerrar
        window.onafterprint = function() {
            setTimeout(function() {
                window.close();
            }, 500);
        };
    </script>
</body>
</html>
    ''';
  }

  /// Genera el HTML de la guía de picking para el almacenero
  Future<String> _generateWarehousePickingSlipHtml(Order order) async {
    // Fecha y hora actual
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // Generar filas de productos con ubicaciones de almacén
    final productRows = order.items
        .where((item) => item.subtotal > 0)
        .map((item) {
          final ubicacion = item.ubicacionAlmacen ?? 'N/A';
          String productName = item.nombre;

          // Truncar nombre si es muy largo
          if (productName.length > 15) {
            productName = productName.substring(0, 15) + '...';
          }

          return '''
        <div class="product-item">
          <div class="product-line">${item.cantidad.toString().padLeft(3, ' ')} | $productName</div>
          <div class="location-line">    | Ubic: $ubicacion</div>
          <div class="price-line">    | \$${item.precioUnitario.toStringAsFixed(0)} c/u</div>
        </div>
          ''';
        })
        .join('');

    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Guía de Picking - ${order.id}</title>
    <style>
        @media print {
            body { margin: 0; }
            .no-print { display: none; }
        }
        body {
            font-family: 'Courier New', monospace;
            font-size: 14px;
            line-height: 1.2;
            margin: 20px auto;
            color: #000;
            max-width: 400px;
            text-align: center;
        }
        .header {
            text-align: center;
            margin-bottom: 20px;
        }
        .store-name {
            font-size: 24px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .warehouse-title {
            font-size: 16px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .picking-title {
            font-size: 14px;
            margin-bottom: 10px;
        }
        .separator {
            text-align: center;
            margin: 10px 0;
            font-weight: bold;
        }
        .info-section {
            text-align: left;
            margin: 15px 0;
        }
        .info-line {
            margin: 3px 0;
            font-weight: bold;
        }
        .products-header {
            text-align: left;
            font-weight: bold;
            margin: 15px 0 5px 0;
        }
        .table-header {
            text-align: left;
            font-weight: bold;
            margin: 5px 0;
        }
        .product-item {
            text-align: left;
            margin: 8px 0;
        }
        .product-line {
            margin: 2px 0;
            font-weight: bold;
        }
        .location-line {
            margin: 2px 0;
        }
        .price-line {
            margin: 2px 0;
        }
        .totals-section {
            margin: 15px 0;
        }
        .total-line {
            text-align: left;
            margin: 3px 0;
            font-weight: bold;
        }
        .footer {
            text-align: center;
            margin-top: 20px;
        }
        @media print {
            body { margin: 0; font-size: 12px; }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="store-name">INVENTTIA</div>
        <div class="warehouse-title">COMPROBANTE DE ALMACEN</div>
        <div class="picking-title">GUIA DE PICKING</div>
        <div class="separator">================================</div>
    </div>

    <div class="info-section">
        <div class="info-line">ORDEN: ${order.id}</div>
        <div class="info-line">FECHA: $dateStr $timeStr</div>
        ${order.buyerName != null && order.buyerName!.isNotEmpty ? '<div class="info-line">CLIENTE: ${order.buyerName}</div>' : ''}
        <div class="info-line">ESTADO: ${order.status.displayName.toUpperCase()}</div>
    </div>

    <div class="products-header">PRODUCTOS A RECOGER:</div>
    <div class="separator">--------------------------------</div>
    <div class="table-header">CANT | PRODUCTO | UBICACION</div>
    <div class="separator">--------------------------------</div>
    
    $productRows

    <div class="totals-section">
        <div class="separator">--------------------------------</div>
        <div class="total-line">TOTAL PRODUCTOS: ${order.totalItems}</div>
        <div class="total-line">VALOR TOTAL: \$${order.total.toStringAsFixed(0)}</div>
    </div>

    <div class="footer">
        <div>INVENTTIA - Sistema de Almacen</div>
    </div>

    <script>
        // Auto-imprimir cuando se carga la página
        window.onload = function() {
            setTimeout(function() {
                window.print();
                
                // Cerrar la ventana después de imprimir
                setTimeout(function() {
                    window.close();
                }, 1000);
            }, 800);
        };
        
        // También manejar el evento afterprint para cerrar
        window.onafterprint = function() {
            setTimeout(function() {
                window.close();
            }, 500);
        };
    </script>
</body>
</html>
    ''';
  }

  /// Verifica si la impresión web está disponible
  bool isWebPrintingAvailable() {
    try {
      return html.window.navigator.userAgent.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Obtiene información sobre las capacidades de impresión web
  Map<String, dynamic> getWebPrintingInfo() {
    return {
      'available': isWebPrintingAvailable(),
      'platform': 'Web',
      'method': 'Browser Print API',
      'supports_network_printers': true,
      'supports_usb_printers': true,
      'description':
          'Impresión a través del navegador web. Soporta impresoras de red y USB conectadas al sistema.',
    };
  }
}
