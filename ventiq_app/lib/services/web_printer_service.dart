import 'package:flutter/material.dart';
import '../models/order.dart';

// Importaciones condicionales
import 'web_printer_service_stub.dart'
    if (dart.library.html) 'web_printer_service_web.dart';

/// Servicio de impresión específico para plataforma web
/// Permite imprimir en impresoras de red o conectadas por USB en Windows
class WebPrinterService {
  final WebPrinterServiceImpl _impl = WebPrinterServiceImpl();

  /// Muestra diálogo de confirmación de impresión para web
  Future<bool> showPrintConfirmationDialog(BuildContext context, Order order) async {
    return await _impl.showPrintConfirmationDialog(context, order);
  }

  /// Imprime la factura usando la API de impresión del navegador
  Future<bool> printInvoice(Order order) async {
    return await _impl.printInvoice(order);
  }

  /// Verifica si la impresión web está disponible
  bool isWebPrintingAvailable() {
    return _impl.isWebPrintingAvailable();
  }

  /// Obtiene información sobre las capacidades de impresión web
  Map<String, dynamic> getWebPrintingInfo() {
    return _impl.getWebPrintingInfo();
  }
}
