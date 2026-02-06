import 'package:flutter/material.dart';
import 'dart:html' as html;
import '../models/order.dart';
import '../services/user_preferences_service.dart';

/// Implementación web para impresión de resumen detallado
class WebSummaryPrinterServiceImpl {
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  /// Imprime el resumen detallado de productos usando la API de impresión del navegador
  Future<bool> printDetailedSummary({
    required List<OrderItem> productosVendidos,
    required double totalVentas,
    required int totalProductos,
    required double totalEgresado,
    required double totalEfectivoReal,
  }) async {
    try {
      // Generar el HTML del resumen detallado
      final summaryHtml = await _generateSummaryHtml(
        productosVendidos: productosVendidos,
        totalVentas: totalVentas,
        totalProductos: totalProductos,
        totalEgresado: totalEgresado,
        totalEfectivoReal: totalEfectivoReal,
      );

      // Crear un blob con el HTML
      final blob = html.Blob([summaryHtml], 'text/html');
      final url = html.Url.createObjectUrlFromBlob(blob);

      // Abrir en nueva ventana
      html.window.open(url, '_blank');

      // Limpiar el URL inmediatamente después de abrir
      Future.delayed(Duration(milliseconds: 100), () {
        try {
          html.Url.revokeObjectUrl(url);
        } catch (e) {
          print('❌ Error al limpiar URL: $e');
        }
      });

      print('✅ Resumen detallado enviado a impresión web');
      return true;
    } catch (e) {
      print('❌ Error imprimiendo resumen detallado web: $e');
      return false;
    }
  }

  /// Genera el HTML del resumen detallado para impresión
  Future<String> _generateSummaryHtml({
    required List<OrderItem> productosVendidos,
    required double totalVentas,
    required int totalProductos,
    required double totalEgresado,
    required double totalEfectivoReal,
  }) async {
    // Obtener información del vendedor
    final workerProfile = await _userPreferencesService.getWorkerProfile();
    final userEmail = await _userPreferencesService.getUserEmail();

    final sellerName =
        '${workerProfile['nombres'] ?? ''} ${workerProfile['apellidos'] ?? ''}'
            .trim();
    final sellerEmail = userEmail ?? 'Sin email';

    // Fecha y hora actual
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // Agrupar productos por nombre para mostrar cantidades totales
    final productosAgrupados = <String, Map<String, dynamic>>{};

    for (final item in productosVendidos) {
      final key = item.nombre;
      if (productosAgrupados.containsKey(key)) {
        productosAgrupados[key]!['cantidad'] += item.cantidad;
        productosAgrupados[key]!['subtotal'] += item.subtotal;
        productosAgrupados[key]!['costo'] +=
            (item.precioUnitario * 0.6) * item.cantidad;
        productosAgrupados[key]!['descuento'] +=
            (item.precioUnitario * 0.1) * item.cantidad;
      } else {
        productosAgrupados[key] = {
          'item': item,
          'cantidad': item.cantidad,
          'subtotal': item.subtotal,
          'costo': (item.precioUnitario * 0.6) * item.cantidad,
          'descuento': (item.precioUnitario * 0.1) * item.cantidad,
        };
      }
    }

    // Generar filas de productos detalladas
    final productRows = productosAgrupados.values
        .map((producto) {
          final item = producto['item'] as OrderItem;
          final cantidad = producto['cantidad'] as int;
          final subtotal = producto['subtotal'] as double;
          final costo = producto['costo'] as double;
          final descuento = producto['descuento'] as double;

          return '''
        <div class="product-item">
          <div class="product-name">${item.nombre}</div>
          <div class="product-details">
            <div class="detail-line">Cantidad: $cantidad</div>
            <div class="detail-line">Precio Unit: \$${item.precioUnitario.toStringAsFixed(0)}</div>
            <div class="detail-line">Costo: \$${costo.toStringAsFixed(0)}</div>
            <div class="detail-line">Descuento: \$${descuento.toStringAsFixed(0)}</div>
            <div class="detail-line total-line">Total: \$${subtotal.toStringAsFixed(0)}</div>
          </div>
          <div class="separator">- - - - - - - - - - - - - - - -</div>
        </div>
      ''';
        })
        .join('');

    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Resumen Detallado - VentIQ</title>
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
        .report-title {
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
        }
        .summary-section {
            text-align: left;
            margin: 15px 0;
        }
        .summary-header {
            font-weight: bold;
            margin-bottom: 5px;
        }
        .product-item {
            text-align: left;
            margin: 10px 0;
        }
        .product-name {
            font-weight: bold;
            margin-bottom: 3px;
        }
        .product-details {
            margin-left: 10px;
        }
        .detail-line {
            margin: 2px 0;
            font-size: 13px;
        }
        .total-line {
            font-weight: bold;
            margin-top: 3px;
        }
        .final-total {
            font-size: 18px;
            font-weight: bold;
            text-align: center;
            margin: 15px 0;
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
        <div class="report-title">RESUMEN DE VENTAS</div>
        <div class="separator">================================</div>
    </div>

    <div class="info-section">
        <div class="info-line">VENDEDOR: $sellerName</div>
        <div class="info-line">EMAIL: $sellerEmail</div>
        <div class="info-line">FECHA: $dateStr $timeStr</div>
    </div>

    <div class="summary-section">
        <div class="summary-header">RESUMEN GENERAL:</div>
        <div class="separator">--------------------------------</div>
        <div class="info-line">Total Productos: $totalProductos</div>
        <div class="info-line">Total Ventas: \$${totalVentas.toStringAsFixed(0)}</div>
        <div class="info-line">Total Egresado: \$${totalEgresado.toStringAsFixed(0)}</div>
        <div class="info-line">Efectivo Real: \$${totalEfectivoReal.toStringAsFixed(0)}</div>
    </div>

    <div class="summary-section">
        <div class="summary-header">DETALLE POR PRODUCTO:</div>
        <div class="separator">--------------------------------</div>
        $productRows
    </div>

    <div class="final-total">TOTAL GENERAL: \$${totalVentas.toStringAsFixed(0)}</div>

    <div class="footer">
        <div>INVENTTIA - Sistema de Ventas</div>
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
}
