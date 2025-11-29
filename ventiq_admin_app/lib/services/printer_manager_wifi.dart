import 'package:flutter/material.dart';
import '../models/order.dart';
import '../utils/platform_utils.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/wifi_printer_service.dart';
import '../services/web_printer_service.dart';
import '../widgets/web_print_dialog.dart';

/// Servicio unificado de impresión que decide qué tipo de impresión usar
/// según la plataforma (móvil = Bluetooth/WiFi, web = impresoras de red/USB)
class PrinterManager {
  // Servicios específicos por plataforma
  final BluetoothPrinterService _bluetoothService = BluetoothPrinterService();
  final WiFiPrinterService _wifiService = WiFiPrinterService();
  final WebPrinterService _webService = WebPrinterService();
  
  // Tipo de impresora seleccionada en móvil
  String _mobileprinterType = 'bluetooth'; // 'bluetooth' o 'wifi'

  /// Muestra el diálogo de confirmación de impresión apropiado para la plataforma
  Future<bool> showPrintConfirmationDialog(BuildContext context, Order order) async {
    if (PlatformUtils.isWeb) {
      // En web, usar el diálogo específico para impresión web
      return await ñ(context, order);
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

  /// Impresión para plataforma móvil (Bluetooth o WiFi)
  Future<PrintResult> _printInvoiceMobile(BuildContext context, Order order) async {
    try {
      // Mostrar diálogo de selección de tipo de impresora
      final printerType = await _showPrinterTypeDialog(context);
      if (printerType == null) {
        return PrintResult(
          success: false,
          message: 'Impresión cancelada por el usuario',
          platform: 'Mobile',
        );
      }

      _mobileprinterType = printerType;

      if (printerType == 'bluetooth') {
        return await _printViaBluetoothMobile(context, order);
      } else {
        return await _printViaWiFiMobile(context, order);
      }
    } catch (e) {
      // Cerrar diálogo de progreso si está abierto
      try {
        Navigator.pop(context);
      } catch (_) {}

      return PrintResult(
        success: false,
        message: 'Error en impresión móvil: $e',
        platform: 'Mobile',
      );
    }
  }

  /// Mostrar diálogo de selección de tipo de impresora
  Future<String?> _showPrinterTypeDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.print, color: const Color(0xFF4A90E2)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tipo de Impresora',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('¿Qué tipo de impresora deseas usar?'),
            SizedBox(height: 16),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'bluetooth'),
            icon: Icon(Icons.bluetooth),
            label: Text('Bluetooth'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'wifi'),
            icon: Icon(Icons.router),
            label: Text('WiFi'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Impresión via Bluetooth en móvil
  Future<PrintResult> _printViaBluetoothMobile(BuildContext context, Order order) async {
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
              Text('Conectando a impresora Bluetooth...'),
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

  /// Impresión via WiFi en móvil
  Future<PrintResult> _printViaWiFiMobile(BuildContext context, Order order) async {
    try {
      // Mostrar diálogo de confirmación de WiFi
      bool shouldPrint = await _wifiService.showPrintConfirmationDialog(context, order);
      if (!shouldPrint) {
        return PrintResult(
          success: false,
          message: 'Impresión cancelada por el usuario',
          platform: 'Mobile',
        );
      }

      // Mostrar diálogo de selección/entrada de impresora WiFi
      // El diálogo maneja la búsqueda automática internamente
      final selectedPrinter = await _wifiService.showPrinterSelectionDialog(context);
      if (selectedPrinter == null) {
        return PrintResult(
          success: false,
          message: 'No se seleccionó impresora WiFi',
          platform: 'Mobile',
        );
      }

      debugPrint('✅ Impresora WiFi seleccionada: ${selectedPrinter['ip']}:${selectedPrinter['port']}');

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF10B981)),
              SizedBox(height: 16),
              Text('Conectando a impresora WiFi...'),
            ],
          ),
        ),
      );

      // Conectar a la impresora WiFi
      bool connected = await _wifiService.connectToPrinter(
        selectedPrinter['ip'],
        port: selectedPrinter['port'] ?? 9100,
      );
      if (!connected) {
        Navigator.pop(context);
        return PrintResult(
          success: false,
          message: 'No se pudo conectar a la impresora WiFi',
          platform: 'Mobile',
          details: 'Verifica la dirección IP y que la impresora esté encendida',
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
              CircularProgressIndicator(color: Color(0xFF10B981)),
              SizedBox(height: 16),
              Text('Imprimiendo factura...'),
            ],
          ),
        ),
      );

      // Imprimir la factura
      bool printed = await _wifiService.printInvoice(order);

      // Cerrar diálogo de progreso
      Navigator.pop(context);

      // Desconectar de la impresora
      await _wifiService.disconnect();

      return PrintResult(
        success: printed,
        message: printed 
          ? 'Factura impresa correctamente via WiFi'
          : 'Error al imprimir factura via WiFi',
        platform: 'Mobile',
        details: printed 
          ? 'Impresión completada en impresora WiFi'
          : 'Verifica la conexión con la impresora',
      );

    } catch (e) {
      // Cerrar diálogo de progreso si está abierto
      try {
        Navigator.pop(context);
      } catch (_) {}

      // Desconectar en caso de error
      try {
        await _wifiService.disconnect();
      } catch (_) {}

      return PrintResult(
        success: false,
        message: 'Error en impresión WiFi: $e',
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
        'methods': ['Bluetooth', 'WiFi'],
        'supports_network_printers': true,
        'supports_usb_printers': false,
        'supports_bluetooth_printers': true,
        'supports_wifi_printers': true,
        'description': 'Impresión via Bluetooth o WiFi a impresoras térmicas compatibles.',
      };
    }
  }

  /// Verifica si la impresión está disponible en la plataforma actual
  bool isPrintingAvailable() {
    if (PlatformUtils.isWeb) {
      return _webService.isWebPrintingAvailable();
    } else {
      return true; // Bluetooth y WiFi siempre disponibles en móvil
    }
  }

  /// Obtiene el tipo de impresión disponible
  String getPrintingType() {
    if (PlatformUtils.isWeb) {
      return 'Web (Red/USB)';
    } else {
      return _mobileprinterType == 'wifi' ? 'WiFi' : 'Bluetooth';
    }
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
