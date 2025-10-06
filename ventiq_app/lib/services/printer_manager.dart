import 'package:flutter/material.dart';
import '../models/order.dart';
import '../utils/platform_utils.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/web_printer_service.dart';
import '../widgets/web_print_dialog.dart';

/// Servicio unificado de impresión que decide qué tipo de impresión usar
/// según la plataforma (móvil = Bluetooth, web = impresoras de red/USB)
class PrinterManager {
  // Servicios específicos por plataforma
  final BluetoothPrinterService _bluetoothService = BluetoothPrinterService();
  final WebPrinterService _webService = WebPrinterService();

  /// Muestra el diálogo de confirmación de impresión apropiado para la plataforma
  Future<bool> showPrintConfirmationDialog(BuildContext context, Order order) async {
    if (PlatformUtils.isWeb) {
      // En web, usar el diálogo específico para impresión web
      return await showWebPrintDialog(context, order);
    } else {
      // En móvil, usar el diálogo de Bluetooth existente
      return await _bluetoothService.showPrintConfirmationDialog(context, order);
    }
  }

  /// Imprime la factura usando el método apropiado para la plataforma
  Future<PrintResult> printInvoice(BuildContext context, Order order) async {
    try {
      if (PlatformUtils.isWeb) {
        return await _printInvoiceWeb(context, order);
      } else {
        return await _printInvoiceMobile(context, order);
      }
    } catch (e) {
      return PrintResult(
        success: false,
        message: 'Error durante la impresión: $e',
        platform: PlatformUtils.isWeb ? 'Web' : 'Mobile',
      );
    }
  }

  /// Impresión para plataforma web (impresoras de red/USB)
  Future<PrintResult> _printInvoiceWeb(BuildContext context, Order order) async {
    try {
      // Mostrar diálogo de confirmación específico para web
      bool shouldPrint = await showWebPrintDialog(context, order);
      if (!shouldPrint) {
        return PrintResult(
          success: false,
          message: 'Impresión cancelada por el usuario',
          platform: 'Web',
        );
      }

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF4A90E2)),
              SizedBox(height: 16),
              Text('Preparando impresión...'),
            ],
          ),
        ),
      );

      // Imprimir usando el servicio web
      bool printed = await _webService.printInvoice(order);

      // Cerrar diálogo de progreso
      Navigator.pop(context);

      return PrintResult(
        success: printed,
        message: printed 
          ? 'Factura enviada a impresión correctamente'
          : 'Error al enviar factura a impresión',
        platform: 'Web',
        details: printed 
          ? 'Se abrió el diálogo de impresión del navegador'
          : 'No se pudo generar la factura para impresión',
      );

    } catch (e) {
      // Cerrar diálogo de progreso si está abierto
      try {
        Navigator.pop(context);
      } catch (_) {}

      return PrintResult(
        success: false,
        message: 'Error en impresión web: $e',
        platform: 'Web',
      );
    }
  }

  /// Impresión para plataforma móvil (Bluetooth)
  Future<PrintResult> _printInvoiceMobile(BuildContext context, Order order) async {
    try {
      // Mostrar diálogo de confirmación de Bluetooth
      bool shouldPrint = await _bluetoothService.showPrintConfirmationDialog(context, order);
      if (!shouldPrint) {
        return PrintResult(
          success: false,
          message: 'Impresión cancelada por el usuario',
          platform: 'Mobile',
        );
      }

      // Mostrar diálogo de selección de dispositivo Bluetooth
      var selectedDevice = await _bluetoothService.showDeviceSelectionDialog(context);
      if (selectedDevice == null) {
        return PrintResult(
          success: false,
          message: 'No se seleccionó dispositivo Bluetooth',
          platform: 'Mobile',
        );
      }

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF4A90E2)),
              SizedBox(height: 16),
              Text('Conectando a impresora...'),
            ],
          ),
        ),
      );

      // Conectar a la impresora Bluetooth
      bool connected = await _bluetoothService.connectToDevice(selectedDevice);
      if (!connected) {
        Navigator.pop(context);
        return PrintResult(
          success: false,
          message: 'No se pudo conectar a la impresora Bluetooth',
          platform: 'Mobile',
          details: 'Verifica que la impresora esté encendida y en rango',
        );
      }

      // Actualizar mensaje de progreso
      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF4A90E2)),
              SizedBox(height: 16),
              Text('Imprimiendo factura...'),
            ],
          ),
        ),
      );

      // Imprimir la factura
      bool printed = await _bluetoothService.printInvoice(order);

      // Cerrar diálogo de progreso
      Navigator.pop(context);

      // Desconectar de la impresora
      await _bluetoothService.disconnect();

      return PrintResult(
        success: printed,
        message: printed 
          ? 'Factura impresa correctamente via Bluetooth'
          : 'Error al imprimir factura via Bluetooth',
        platform: 'Mobile',
        details: printed 
          ? 'Impresión completada en impresora Bluetooth'
          : 'Verifica la conexión con la impresora',
      );

    } catch (e) {
      // Cerrar diálogo de progreso si está abierto
      try {
        Navigator.pop(context);
      } catch (_) {}

      // Desconectar en caso de error
      try {
        await _bluetoothService.disconnect();
      } catch (_) {}

      return PrintResult(
        success: false,
        message: 'Error en impresión Bluetooth: $e',
        platform: 'Mobile',
      );
    }
  }

  /// Obtiene información sobre las capacidades de impresión disponibles
  Map<String, dynamic> getPrintingCapabilities() {
    if (PlatformUtils.isWeb) {
      return _webService.getWebPrintingInfo();
    } else {
      return {
        'available': true,
        'platform': 'Mobile',
        'method': 'Bluetooth',
        'supports_network_printers': false,
        'supports_usb_printers': false,
        'supports_bluetooth_printers': true,
        'description': 'Impresión via Bluetooth a impresoras térmicas compatibles.',
      };
    }
  }

  /// Verifica si la impresión está disponible en la plataforma actual
  bool isPrintingAvailable() {
    if (PlatformUtils.isWeb) {
      return _webService.isWebPrintingAvailable();
    } else {
      return true; // Bluetooth siempre disponible en móvil
    }
  }

  /// Obtiene el tipo de impresión disponible
  String getPrintingType() {
    return PlatformUtils.isWeb ? 'Web (Red/USB)' : 'Bluetooth';
  }
}

/// Clase para encapsular el resultado de una operación de impresión
class PrintResult {
  final bool success;
  final String message;
  final String platform;
  final String? details;

  PrintResult({
    required this.success,
    required this.message,
    required this.platform,
    this.details,
  });

  @override
  String toString() {
    return 'PrintResult(success: $success, message: $message, platform: $platform, details: $details)';
  }
}
