import 'package:flutter/material.dart';
import '../models/order.dart';

/// Implementación stub para plataformas no web
class WebPrinterServiceImpl {
  /// Muestra diálogo de confirmación de impresión para web (stub)
  Future<bool> showPrintConfirmationDialog(BuildContext context, Order order) async {
    // En plataformas no web, no se puede usar impresión web
    return false;
  }

  /// Imprime la factura usando la API de impresión del navegador (stub)
  Future<bool> printInvoice(Order order) async {
    print('❌ Impresión web no disponible en esta plataforma');
    return false;
  }

  /// Verifica si la impresión web está disponible (stub)
  bool isWebPrintingAvailable() {
    return false;
  }

  /// Obtiene información sobre las capacidades de impresión web (stub)
  Map<String, dynamic> getWebPrintingInfo() {
    return {
      'available': false,
      'platform': 'Non-Web',
      'method': 'Not Available',
      'supports_network_printers': false,
      'supports_usb_printers': false,
      'description': 'Impresión web no disponible en esta plataforma.',
    };
  }
}
