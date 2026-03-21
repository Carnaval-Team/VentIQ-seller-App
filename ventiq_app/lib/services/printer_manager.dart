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

  // ── Selección guardada durante el turno ─────────────────────────────────
  // Una vez que el trabajador elige tipo + dispositivo, se reutiliza
  // automáticamente hasta que llame a clearSavedPrinter().
  String? _savedPrinterType;           // 'bluetooth' | 'wifi'
  dynamic _savedBluetoothDevice;       // BluetoothInfo
  Map<String, dynamic>? _savedWifiPrinter; // {'ip': ..., 'port': ...}

  /// Devuelve true si ya hay una selección guardada para la sesión
  bool get hasSavedPrinter => _savedPrinterType != null;

  /// Nombre descriptivo de la impresora guardada (para mostrar en UI)
  String get savedPrinterDescription {
    if (_savedPrinterType == 'bluetooth' && _savedBluetoothDevice != null) {
      final name = _savedBluetoothDevice.name as String? ?? 'Dispositivo BT';
      return 'Bluetooth · $name';
    } else if (_savedPrinterType == 'wifi' && _savedWifiPrinter != null) {
      return 'WiFi · ${_savedWifiPrinter!['ip']}:${_savedWifiPrinter!['port'] ?? 9100}';
    }
    return '';
  }

  /// Limpia la selección guardada (usar al cerrar turno)
  void clearSavedPrinter() {
    _savedPrinterType = null;
    _savedBluetoothDevice = null;
    _savedWifiPrinter = null;
  }

  /// Muestra el diálogo de confirmación de impresión apropiado para la plataforma
  Future<bool> showPrintConfirmationDialog(
    BuildContext context,
    Order order,
  ) async {
    if (PlatformUtils.isWeb) {
      // En web, usar el diálogo específico para impresión web
      return await showWebPrintDialog(context, order);
    } else {
      // En móvil, usar el diálogo de Bluetooth existente
      return await _bluetoothService.showPrintConfirmationDialog(
        context,
        order,
      );
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

  /// Imprime múltiples órdenes en una sola impresión (solo ticket cliente)
  Future<PrintResult> printCustomerReceiptsBatch(
    BuildContext context,
    List<Order> orders,
  ) async {
    if (orders.isEmpty) {
      return PrintResult(
        success: false,
        message: 'No hay órdenes para imprimir',
        platform: PlatformUtils.isWeb ? 'Web' : 'Mobile',
      );
    }

    final shouldPrint = await _showBulkPrintConfirmationDialog(
      context,
      orders.length,
    );
    if (!shouldPrint) {
      return PrintResult(
        success: false,
        message: 'Impresión cancelada por el usuario',
        platform: PlatformUtils.isWeb ? 'Web' : 'Mobile',
      );
    }

    try {
      if (PlatformUtils.isWeb) {
        return await _printCustomerReceiptsWeb(context, orders);
      } else {
        return await _printCustomerReceiptsMobile(context, orders);
      }
    } catch (e) {
      return PrintResult(
        success: false,
        message: 'Error durante la impresión: $e',
        platform: PlatformUtils.isWeb ? 'Web' : 'Mobile',
      );
    }
  }

  Future<bool> _showBulkPrintConfirmationDialog(
    BuildContext context,
    int orderCount,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.print, color: const Color(0xFF4A90E2)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Imprimir todas las órdenes',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Se imprimirán $orderCount órdenes en una sola impresión.',
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Solo se imprimirá el ticket del cliente (no se incluye guía de almacén).',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.print),
                    label: const Text('Imprimir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90E2),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<PrintResult> _printCustomerReceiptsWeb(
    BuildContext context,
    List<Order> orders,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
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

      final printed = await _webService.printCustomerReceiptsBatch(orders);

      Navigator.pop(context);

      return PrintResult(
        success: printed,
        message:
            printed
                ? 'Órdenes enviadas a impresión correctamente'
                : 'Error al enviar órdenes a impresión',
        platform: 'Web',
        details:
            printed
                ? 'Se abrió el diálogo de impresión del navegador'
                : 'No se pudo generar la impresión',
      );
    } catch (e) {
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

  Future<PrintResult> _printCustomerReceiptsMobile(
    BuildContext context,
    List<Order> orders,
  ) async {
    try {
      // Si ya hay una selección guardada, usar directamente
      if (_savedPrinterType != null) {
        if (_savedPrinterType == 'bluetooth') {
          return await _printCustomerReceiptsViaBluetoothMobileWithDevice(
            context, orders, _savedBluetoothDevice);
        } else {
          return await _printCustomerReceiptsViaWiFiMobileWithPrinter(
            context, orders, _savedWifiPrinter!);
        }
      }

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
        return await _printCustomerReceiptsViaBluetoothMobile(context, orders);
      } else {
        return await _printCustomerReceiptsViaWiFiMobile(context, orders);
      }
    } catch (e) {
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

  Future<PrintResult> _printCustomerReceiptsViaBluetoothMobile(
    BuildContext context,
    List<Order> orders,
  ) async {
    try {
      final selectedDevice = await _bluetoothService.showDeviceSelectionDialog(
        context,
      );
      if (selectedDevice == null) {
        return PrintResult(
          success: false,
          message: 'No se seleccionó dispositivo Bluetooth',
          platform: 'Mobile',
        );
      }

      // Guardar selección para el resto del turno
      _savedPrinterType = 'bluetooth';
      _savedBluetoothDevice = selectedDevice;

      return await _printCustomerReceiptsViaBluetoothMobileWithDevice(context, orders, selectedDevice);
    } catch (e) {
      try { Navigator.pop(context); } catch (_) {}
      try { await _bluetoothService.disconnect(); } catch (_) {}
      return PrintResult(success: false, message: 'Error en impresión Bluetooth: $e', platform: 'Mobile');
    }
  }

  Future<PrintResult> _printCustomerReceiptsViaBluetoothMobileWithDevice(
    BuildContext context,
    List<Order> orders,
    dynamic selectedDevice,
  ) async {
    try {

      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
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

      final connected = await _bluetoothService.connectToDevice(selectedDevice);
      if (!connected) {
        Navigator.pop(context);
        return PrintResult(
          success: false,
          message: 'No se pudo conectar a la impresora Bluetooth',
          platform: 'Mobile',
          details: 'Verifica que la impresora esté encendida y en rango',
        );
      }

      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Imprimiendo ${orders.length} órdenes...'),
                ],
              ),
            ),
      );

      final printed = await _bluetoothService.printCustomerReceiptsBatch(
        orders,
      );

      Navigator.pop(context);
      await _bluetoothService.disconnect();

      return PrintResult(
        success: printed,
        message:
            printed
                ? 'Órdenes impresas correctamente via Bluetooth'
                : 'Error al imprimir órdenes via Bluetooth',
        platform: 'Mobile',
        details:
            printed
                ? 'Impresión completada en impresora Bluetooth'
                : 'Verifica la conexión con la impresora',
      );
    } catch (e) {
      try { Navigator.pop(context); } catch (_) {}
      try { await _bluetoothService.disconnect(); } catch (_) {}

      return PrintResult(
        success: false,
        message: 'Error en impresión Bluetooth: $e',
        platform: 'Mobile',
      );
    }
  }

  Future<PrintResult> _printCustomerReceiptsViaWiFiMobile(
    BuildContext context,
    List<Order> orders,
  ) async {
    try {
      final selectedPrinter = await _wifiService.showPrinterSelectionDialog(
        context,
      );
      if (selectedPrinter == null) {
        return PrintResult(
          success: false,
          message: 'No se seleccionó impresora WiFi',
          platform: 'Mobile',
        );
      }

      // Guardar selección para el resto del turno
      _savedPrinterType = 'wifi';
      _savedWifiPrinter = Map<String, dynamic>.from(selectedPrinter);

      return await _printCustomerReceiptsViaWiFiMobileWithPrinter(
        context, orders, selectedPrinter);
    } catch (e) {
      try { Navigator.pop(context); } catch (_) {}
      try { await _wifiService.disconnect(); } catch (_) {}
      return PrintResult(success: false, message: 'Error en impresión WiFi: $e', platform: 'Mobile');
    }
  }

  Future<PrintResult> _printCustomerReceiptsViaWiFiMobileWithPrinter(
    BuildContext context,
    List<Order> orders,
    Map<String, dynamic> selectedPrinter,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
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

      final connected = await _wifiService.connectToPrinter(
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

      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF10B981)),
                  SizedBox(height: 16),
                  Text('Imprimiendo ${orders.length} órdenes...'),
                ],
              ),
            ),
      );

      final printed = await _wifiService.printCustomerReceiptsBatch(orders);

      Navigator.pop(context);
      await _wifiService.disconnect();

      return PrintResult(
        success: printed,
        message:
            printed
                ? 'Órdenes impresas correctamente via WiFi'
                : 'Error al imprimir órdenes via WiFi',
        platform: 'Mobile',
        details:
            printed
                ? 'Impresión completada en impresora WiFi'
                : 'Verifica la conexión con la impresora',
      );
    } catch (e) {
      try { Navigator.pop(context); } catch (_) {}
      try { await _wifiService.disconnect(); } catch (_) {}

      return PrintResult(
        success: false,
        message: 'Error en impresión WiFi: $e',
        platform: 'Mobile',
      );
    }
  }

  /// Impresión para plataforma web (impresoras de red/USB)
  Future<PrintResult> _printInvoiceWeb(
    BuildContext context,
    Order order,
  ) async {
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
        builder:
            (context) => AlertDialog(
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
        message:
            printed
                ? 'Factura enviada a impresión correctamente'
                : 'Error al enviar factura a impresión',
        platform: 'Web',
        details:
            printed
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
  Future<PrintResult> _printInvoiceMobile(
    BuildContext context,
    Order order,
  ) async {
    try {
      // Si ya hay una selección guardada, solo pedir confirmación
      if (_savedPrinterType != null) {
        final confirmed = await _showQuickPrintConfirmDialog(context, order);
        if (confirmed == null) return PrintResult(success: false, message: 'Impresión cancelada', platform: 'Mobile');
        if (!confirmed) {
          // El usuario quiere cambiar de impresora
          clearSavedPrinter();
          return await _printInvoiceMobile(context, order);
        }
        // Imprimir con la selección guardada
        if (_savedPrinterType == 'bluetooth') {
          return await _printViaBluetoothMobileWithDevice(context, order, _savedBluetoothDevice);
        } else {
          return await _printViaWiFiMobileWithPrinter(context, order, _savedWifiPrinter!);
        }
      }

      // Primera vez: pedir tipo de impresora
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
      builder:
          (context) => AlertDialog(
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
                Text(
                  '¿Qué tipo de impresora deseas usar?',
                  style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                ),
                SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, 'bluetooth'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4A90E2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bluetooth, size: 36),
                            SizedBox(height: 8),
                            Text(
                              'Bluetooth',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, 'wifi'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi, size: 36),
                            SizedBox(height: 8),
                            Text(
                              'WiFi',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancelar'),
                  ),
                ),
              ],
            ),
            // Sin actions — los botones están en el content
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            actionsPadding: EdgeInsets.zero,
          ),
    );
  }

  /// Diálogo rápido cuando ya hay impresora guardada:
  /// true = confirmar con impresora guardada
  /// false = cambiar impresora
  /// null = cancelar
  Future<bool?> _showQuickPrintConfirmDialog(
    BuildContext context,
    Order order,
  ) async {
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.print, color: const Color(0xFF4A90E2)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Imprimir factura',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Orden: ${order.id}'),
                SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _savedPrinterType == 'bluetooth'
                            ? Icons.bluetooth
                            : Icons.wifi,
                        size: 18,
                        color: const Color(0xFF4A90E2),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          savedPrinterDescription,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1D4ED8),
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
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cambiar impresora',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: Icon(Icons.print, size: 18),
                label: Text('Imprimir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
    );
  }

  /// Impresión via Bluetooth en móvil
  Future<PrintResult> _printViaBluetoothMobile(
    BuildContext context,
    Order order,
  ) async {
    try {
      // Mostrar diálogo de selección de dispositivo Bluetooth
      var selectedDevice = await _bluetoothService.showDeviceSelectionDialog(
        context,
      );
      if (selectedDevice == null) {
        return PrintResult(
          success: false,
          message: 'No se seleccionó dispositivo Bluetooth',
          platform: 'Mobile',
        );
      }

      // Guardar selección para el resto del turno
      _savedPrinterType = 'bluetooth';
      _savedBluetoothDevice = selectedDevice;

      return await _printViaBluetoothMobileWithDevice(context, order, selectedDevice);
    } catch (e) {
      try { Navigator.pop(context); } catch (_) {}
      try { await _bluetoothService.disconnect(); } catch (_) {}
      return PrintResult(success: false, message: 'Error en impresión Bluetooth: $e', platform: 'Mobile');
    }
  }

  /// Impresión via Bluetooth con dispositivo ya conocido
  Future<PrintResult> _printViaBluetoothMobileWithDevice(
    BuildContext context,
    Order order,
    dynamic selectedDevice,
  ) async {
    try {

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
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
        builder:
            (context) => AlertDialog(
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

      Navigator.pop(context);
      await _bluetoothService.disconnect();

      return PrintResult(
        success: printed,
        message:
            printed
                ? 'Factura impresa correctamente via Bluetooth'
                : 'Error al imprimir factura via Bluetooth',
        platform: 'Mobile',
        details:
            printed
                ? 'Impresión completada en impresora Bluetooth'
                : 'Verifica la conexión con la impresora',
      );
    } catch (e) {
      try { Navigator.pop(context); } catch (_) {}
      try { await _bluetoothService.disconnect(); } catch (_) {}

      return PrintResult(
        success: false,
        message: 'Error en impresión Bluetooth: $e',
        platform: 'Mobile',
      );
    }
  }

  /// Impresión via WiFi en móvil
  Future<PrintResult> _printViaWiFiMobile(
    BuildContext context,
    Order order,
  ) async {
    try {
      // Mostrar diálogo de selección/entrada de impresora WiFi
      final selectedPrinter = await _wifiService.showPrinterSelectionDialog(
        context,
      );
      if (selectedPrinter == null) {
        return PrintResult(
          success: false,
          message: 'No se seleccionó impresora WiFi',
          platform: 'Mobile',
        );
      }

      // Guardar selección para el resto del turno
      _savedPrinterType = 'wifi';
      _savedWifiPrinter = Map<String, dynamic>.from(selectedPrinter);

      debugPrint(
        '✅ Impresora WiFi seleccionada: ${selectedPrinter['ip']}:${selectedPrinter['port']}',
      );

      return await _printViaWiFiMobileWithPrinter(context, order, selectedPrinter);
    } catch (e) {
      try { Navigator.pop(context); } catch (_) {}
      try { await _wifiService.disconnect(); } catch (_) {}
      return PrintResult(success: false, message: 'Error en impresión WiFi: $e', platform: 'Mobile');
    }
  }

  /// Impresión via WiFi con impresora ya conocida
  Future<PrintResult> _printViaWiFiMobileWithPrinter(
    BuildContext context,
    Order order,
    Map<String, dynamic> selectedPrinter,
  ) async {
    try {
      debugPrint('🖨️ Imprimiendo via WiFi: ${selectedPrinter['ip']}');

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
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

      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
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

      bool printed = await _wifiService.printInvoice(order);

      Navigator.pop(context);
      await _wifiService.disconnect();

      return PrintResult(
        success: printed,
        message:
            printed
                ? 'Factura impresa correctamente via WiFi'
                : 'Error al imprimir factura via WiFi',
        platform: 'Mobile',
        details:
            printed
                ? 'Impresión completada en impresora WiFi'
                : 'Verifica la conexión con la impresora',
      );
    } catch (e) {
      try { Navigator.pop(context); } catch (_) {}
      try { await _wifiService.disconnect(); } catch (_) {}

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
        'description':
            'Impresión via Bluetooth o WiFi a impresoras térmicas compatibles.',
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
