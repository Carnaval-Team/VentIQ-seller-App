import 'package:flutter/material.dart';
import '../services/bluetooth_printer_service.dart';

/// Servicio unificado de impresión para operaciones de venta por acuerdo
/// Maneja el flujo completo de impresión Bluetooth
class PrinterManager {
  // Servicio de Bluetooth
  final BluetoothPrinterService _bluetoothService = BluetoothPrinterService();

  // Getter para acceder al servicio de Bluetooth
  BluetoothPrinterService get bluetoothService => _bluetoothService;

  /// Muestra el diálogo de confirmación de impresión
  Future<bool> showPrintConfirmationDialog(BuildContext context) async {
    return await _bluetoothService.showPrintConfirmationDialog(context);
  }

  /// Obtiene información sobre las capacidades de impresión disponibles
  Map<String, dynamic> getPrintingCapabilities() {
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

  /// Verifica si la impresión está disponible
  bool isPrintingAvailable() {
    return true; // Bluetooth siempre disponible en móvil
  }

  /// Obtiene el tipo de impresión disponible
  String getPrintingType() {
    return 'Bluetooth';
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
