import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order.dart';
import '../services/user_preferences_service.dart';

class _StorePrintInfo {
  final String name;
  final String? logoDataUrl;

  const _StorePrintInfo({required this.name, this.logoDataUrl});
}

/// Implementación web del servicio de impresión
class WebPrinterServiceImpl {
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  _StorePrintInfo? _storePrintInfoCache;
  Future<_StorePrintInfo>? _storePrintInfoFuture;

  Future<_StorePrintInfo> _getStorePrintInfo() async {
    if (_storePrintInfoCache != null) {
      return _storePrintInfoCache!;
    }

    _storePrintInfoFuture ??= _loadStorePrintInfo();
    _storePrintInfoCache = await _storePrintInfoFuture!;
    return _storePrintInfoCache!;
  }

  Future<_StorePrintInfo> _loadStorePrintInfo() async {
    try {
      final storeId = await _userPreferencesService.getIdTienda();
      Map<String, dynamic>? storeData;

      if (storeId != null) {
        storeData =
            await Supabase.instance.client
                .from('app_dat_tienda')
                .select('denominacion, imagen_url')
                .eq('id', storeId)
                .maybeSingle();
      }

      final storeName = storeData?['denominacion'] as String? ?? 'VentIQ';
      final storeLogoUrl = storeData?['imagen_url'] as String?;
      final logoDataUrl = await _loadLogoDataUrl(storeLogoUrl);

      return _StorePrintInfo(name: storeName, logoDataUrl: logoDataUrl);
    } catch (e) {
      print('⚠️ No se pudo cargar datos de tienda para impresión web: $e');
      return const _StorePrintInfo(name: 'VentIQ');
    }
  }

  Future<String?> _loadLogoDataUrl(String? logoUrl) async {
    final bytes = await _downloadImageBytes(logoUrl);
    if (bytes == null) {
      return null;
    }

    final mimeType = _resolveLogoMimeType(logoUrl);
    final base64Logo = base64Encode(bytes);
    return 'data:$mimeType;base64,$base64Logo';
  }

  String _resolveLogoMimeType(String? logoUrl) {
    final uri = logoUrl != null ? Uri.tryParse(logoUrl) : null;
    final path = uri?.path.toLowerCase() ?? '';

    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (path.endsWith('.webp')) {
      return 'image/webp';
    }
    if (path.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/png';
  }

  Future<Uint8List?> _downloadImageBytes(String? url) async {
    if (url == null || url.isEmpty) return null;

    const objectPrefix =
        'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/';
    const renderPrefix =
        'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/render/image/public/images_back/';

    final renderUrl =
        url.contains(objectPrefix)
            ? '${url.replaceFirst(objectPrefix, renderPrefix)}?width=500&height=600'
            : url;

    try {
      final response = await http.get(Uri.parse(renderUrl));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('⚠️ No se pudo descargar imagen de tienda: $e');
      return null;
    }
  }

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

  /// Imprime múltiples recibos del cliente en una sola impresión
  Future<bool> printCustomerReceiptsBatch(List<Order> orders) async {
    if (orders.isEmpty) {
      print('⚠️ No hay órdenes para impresión por lote');
      return false;
    }

    try {
      print('🖨️ Iniciando impresión web por lote (${orders.length} órdenes)');

      final batchHtml = await _generateCustomerTicketsBatchHtml(orders);
      final blob = html.Blob([batchHtml], 'text/html');
      final url = html.Url.createObjectUrlFromBlob(blob);

      html.window.open(url, '_blank');

      Future.delayed(Duration(milliseconds: 100), () {
        try {
          html.Url.revokeObjectUrl(url);
        } catch (e) {
          print('❌ Error al limpiar URL del lote: $e');
        }
      });

      print('✅ Recibos de cliente por lote enviados a impresión web');
      return true;
    } catch (e) {
      print('❌ Error imprimiendo recibos por lote: $e');
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
    final storeInfo = await _getStorePrintInfo();
    final storeName = storeInfo.name;
    final headerLogoHtml =
        storeInfo.logoDataUrl != null
            ? '<img class="store-logo" src="${storeInfo.logoDataUrl}" alt="Logo $storeName" />'
            : storeName;
    final footerLogoHtml =
        storeInfo.logoDataUrl != null
            ? '<img class="footer-logo" src="${storeInfo.logoDataUrl}" alt="Logo $storeName" />'
            : '';

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
        .store-logo {
            max-width: 160px;
            max-height: 80px;
            object-fit: contain;
            display: block;
            margin: 0 auto 6px;
        }
        .footer-logo {
            max-width: 120px;
            max-height: 60px;
            object-fit: contain;
            display: block;
            margin: 0 auto 6px;
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
        <div class="store-name">$headerLogoHtml</div>
        <div class="system-name">$storeName</div>
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
        <div>$storeName</div>
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

  Future<String> _generateCustomerTicketsBatchHtml(List<Order> orders) async {
    final storeInfo = await _getStorePrintInfo();
    final storeName = storeInfo.name;
    final headerLogoHtml =
        storeInfo.logoDataUrl != null
            ? '<img class="store-logo" src="${storeInfo.logoDataUrl}" alt="Logo $storeName" />'
            : storeName;

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final ticketsHtml = orders
        .map((order) {
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

          final notesHtml =
              order.notas != null && order.notas!.isNotEmpty
                  ? '<div class="notes">Notas: ${order.notas}</div>'
                  : '';

          return '''
    <section class="ticket">
      <div class="header">
        <div class="store-name">$headerLogoHtml</div>
        <div class="system-name">$storeName</div>
        <div class="invoice-title">FACTURA DE VENTA</div>
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
        <div>$storeName</div>
      </div>

      $notesHtml
    </section>
      ''';
        })
        .join('<div class="ticket-divider"></div>');

    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Facturas por lote</title>
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
        .ticket {
            margin-bottom: 18px;
        }
        .ticket-divider {
            border-top: 2px dashed #000;
            margin: 16px 0;
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
        .store-logo {
            max-width: 160px;
            max-height: 80px;
            object-fit: contain;
            display: block;
            margin: 0 auto 6px;
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
    $ticketsHtml

    <script>
        window.onload = function() {
            setTimeout(function() {
                window.print();
                setTimeout(function() {
                    window.close();
                }, 1000);
            }, 800);
        };

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
    final storeInfo = await _getStorePrintInfo();
    final storeName = storeInfo.name;
    final headerLogoHtml =
        storeInfo.logoDataUrl != null
            ? '<img class="store-logo" src="${storeInfo.logoDataUrl}" alt="Logo $storeName" />'
            : storeName;
    final footerLogoHtml =
        storeInfo.logoDataUrl != null
            ? '<img class="footer-logo" src="${storeInfo.logoDataUrl}" alt="Logo $storeName" />'
            : '';

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
        .store-logo {
            max-width: 160px;
            max-height: 80px;
            object-fit: contain;
            display: block;
            margin: 0 auto 6px;
        }
        .footer-logo {
            max-width: 120px;
            max-height: 60px;
            object-fit: contain;
            display: block;
            margin: 0 auto 6px;
        }
        .system-name {
            font-size: 14px;
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
        <div class="store-name">$headerLogoHtml</div>
        <div class="system-name">$storeName</div>
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
        $footerLogoHtml
        <div>$storeName</div>
        <div>Sistema de Almacen</div>
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
