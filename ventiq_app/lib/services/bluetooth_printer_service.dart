import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bluetooth_print/bluetooth_print.dart';
import 'package:bluetooth_print/bluetooth_print_model.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/order.dart';

class BluetoothPrinterService {
  static final BluetoothPrinterService _instance = BluetoothPrinterService._internal();
  factory BluetoothPrinterService() => _instance;
  BluetoothPrinterService._internal();

  BluetoothPrint bluetoothPrint = BluetoothPrint.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _isConnected = false;

  // Getters
  List<BluetoothDevice> get devices => _devices;
  BluetoothDevice? get selectedDevice => _selectedDevice;
  bool get isConnected => _isConnected;

  /// Initialize Bluetooth and request permissions
  Future<bool> initializeBluetooth() async {
    try {
      // Request Bluetooth permissions
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ].request();

      bool allGranted = statuses.values.every((status) => status.isGranted);
      if (!allGranted) {
        debugPrint('Bluetooth permissions not granted');
        return false;
      }

      // Check if Bluetooth is available and enabled
      bool isAvailable = await bluetoothPrint.isAvailable ?? false;
      if (!isAvailable) {
        debugPrint('Bluetooth not available');
        return false;
      }

      bool isEnabled = await bluetoothPrint.isOn ?? false;
      if (!isEnabled) {
        debugPrint('Bluetooth not enabled');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error initializing Bluetooth: $e');
      return false;
    }
  }

  /// Scan for available Bluetooth devices
  Future<List<BluetoothDevice>> scanDevices() async {
    try {
      // Clear previous devices
      _devices.clear();
      
      // Start scanning for devices
      await bluetoothPrint.startScan(timeout: Duration(seconds: 4));
      
      // Listen to scan results and collect all devices
      List<BluetoothDevice> allDevices = [];
      await for (List<BluetoothDevice> devices in bluetoothPrint.scanResults.take(10)) {
        // Add new devices that aren't already in the list
        for (BluetoothDevice device in devices) {
          if (!allDevices.any((d) => d.address == device.address)) {
            allDevices.add(device);
          }
        }
        
        // Break if we haven't received new devices for a while
        if (devices.isEmpty) break;
      }
      
      _devices = allDevices;
      return _devices;
    } catch (e) {
      debugPrint('Error scanning devices: $e');
      return [];
    }
  }

  /// Connect to a specific Bluetooth device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await bluetoothPrint.connect(device);
      _selectedDevice = device;
      _isConnected = await bluetoothPrint.isConnected ?? false;
      return _isConnected;
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    try {
      await bluetoothPrint.disconnect();
      _isConnected = false;
      _selectedDevice = null;
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  /// Print invoice for an order
  Future<bool> printInvoice(Order order) async {
    if (!_isConnected || _selectedDevice == null) {
      debugPrint('Printer not connected');
      return false;
    }

    try {
      List<LineText> printData = [];
      
      // Add header
      _addHeader(printData);
      
      // Add order information
      _addOrderInfo(printData, order);
      
      // Add products
      _addProducts(printData, order);
      
      // Add total and footer
      _addFooter(printData, order);
      
      // Print all data
      Map<String, dynamic> config = {};
      await bluetoothPrint.printReceipt(config, printData);
      
      return true;
    } catch (e) {
      debugPrint('Error printing invoice: $e');
      return false;
    }
  }

  /// Add header with logo and company info to print data
  void _addHeader(List<LineText> printData) {
    try {
      // Add company header
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: 'VENTIQ',
        size: 2,
        align: LineText.ALIGN_CENTER,
        weight: 1,
        linefeed: 1,
      ));
      
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: 'Sistema de Ventas',
        size: 0,
        align: LineText.ALIGN_CENTER,
        linefeed: 1,
      ));
      
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: '================================',
        size: 0,
        align: LineText.ALIGN_CENTER,
        linefeed: 1,
      ));
      
      printData.add(LineText(linefeed: 1));
    } catch (e) {
      debugPrint('Error adding header: $e');
      // Add simple header if there's an error
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: 'VENTIQ - FACTURA',
        size: 1,
        align: LineText.ALIGN_CENTER,
        weight: 1,
        linefeed: 2,
      ));
    }
  }

  /// Add order information to print data
  void _addOrderInfo(List<LineText> printData, Order order) {
    // Order number
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: 'ORDEN: ${order.id}',
      size: 0,
      align: LineText.ALIGN_LEFT,
      linefeed: 1,
    ));
    
    // Customer info
    if (order.buyerName != null && order.buyerName!.isNotEmpty) {
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: 'CLIENTE: ${order.buyerName}',
        size: 0,
        align: LineText.ALIGN_LEFT,
        linefeed: 1,
      ));
    }
    
    if (order.buyerPhone != null && order.buyerPhone!.isNotEmpty) {
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: 'TELEFONO: ${order.buyerPhone}',
        size: 0,
        align: LineText.ALIGN_LEFT,
        linefeed: 1,
      ));
    }
    
    // Date
    String formattedDate = _formatDateForPrint(order.fechaCreacion);
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: 'FECHA: $formattedDate',
      size: 0,
      align: LineText.ALIGN_LEFT,
      linefeed: 1,
    ));
    
    // Payment method
    if (order.paymentMethod != null && order.paymentMethod!.isNotEmpty) {
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: 'PAGO: ${order.paymentMethod}',
        size: 0,
        align: LineText.ALIGN_LEFT,
        linefeed: 1,
      ));
    }
    
    printData.add(LineText(linefeed: 1));
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: '================================',
      size: 0,
      align: LineText.ALIGN_CENTER,
      linefeed: 1,
    ));
    printData.add(LineText(linefeed: 1));
  }

  /// Add products list to print data
  void _addProducts(List<LineText> printData, Order order) {
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: 'PRODUCTOS:',
      size: 0,
      align: LineText.ALIGN_LEFT,
      weight: 1,
      linefeed: 1,
    ));
    
    printData.add(LineText(linefeed: 1));
    
    // Header
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: 'CANT  PRODUCTO           PRECIO',
      size: 0,
      align: LineText.ALIGN_LEFT,
      linefeed: 1,
    ));
    
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: '--------------------------------',
      size: 0,
      align: LineText.ALIGN_LEFT,
      linefeed: 1,
    ));
    
    for (var item in order.items) {
      // Format product line
      String quantity = item.cantidad.toString().padLeft(4);
      String productName = item.nombre.length > 15 
          ? item.nombre.substring(0, 15) 
          : item.nombre.padRight(15);
      String price = '\$${item.precioUnitario.toStringAsFixed(0)}';
      
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: '$quantity $productName $price',
        size: 0,
        align: LineText.ALIGN_LEFT,
        linefeed: 1,
      ));
    }
    
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: '--------------------------------',
      size: 0,
      align: LineText.ALIGN_LEFT,
      linefeed: 1,
    ));
    
    printData.add(LineText(linefeed: 1));
  }

  /// Add total and footer to print data
  void _addFooter(List<LineText> printData, Order order) {
    // Calculate subtotal from items
    double subtotal = order.items.fold(0, (sum, item) => sum + (item.precioUnitario * item.cantidad));
    
    // Add totals
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: 'SUBTOTAL: \$${subtotal.toStringAsFixed(0)}',
      size: 0,
      align: LineText.ALIGN_RIGHT,
      weight: 1,
      linefeed: 1,
    ));
    
    printData.add(LineText(linefeed: 1));
    
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: 'TOTAL: \$${order.total.toStringAsFixed(0)}',
      size: 1,
      align: LineText.ALIGN_RIGHT,
      weight: 1,
      linefeed: 1,
    ));
    
    printData.add(LineText(linefeed: 1));
    
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: '================================',
      size: 0,
      align: LineText.ALIGN_CENTER,
      linefeed: 1,
    ));
    
    printData.add(LineText(linefeed: 1));
    
    // Thank you message
    printData.add(LineText(
      type: LineText.TYPE_TEXT,
      content: '¡GRACIAS POR SU COMPRA!',
      size: 0,
      align: LineText.ALIGN_CENTER,
      weight: 1,
      linefeed: 1,
    ));
    
    printData.add(LineText(linefeed: 1));
    
    // Additional info (notes)
    if (order.notas != null && order.notas!.isNotEmpty) {
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: 'Notas:',
        size: 0,
        align: LineText.ALIGN_LEFT,
        linefeed: 1,
      ));
      
      printData.add(LineText(
        type: LineText.TYPE_TEXT,
        content: order.notas!,
        size: 0,
        align: LineText.ALIGN_LEFT,
        linefeed: 1,
      ));
      
      printData.add(LineText(linefeed: 1));
    }
    
    // Add extra line feeds for paper cutting
    printData.add(LineText(linefeed: 1));
    printData.add(LineText(linefeed: 1));
    printData.add(LineText(linefeed: 1));
  }

  /// Format date for printing
  String _formatDateForPrint(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/"
           "${date.month.toString().padLeft(2, '0')}/"
           "${date.year} "
           "${date.hour.toString().padLeft(2, '0')}:"
           "${date.minute.toString().padLeft(2, '0')}";
  }

  /// Show device selection dialog
  Future<BluetoothDevice?> showDeviceSelectionDialog(BuildContext context) async {
    bool initialized = await initializeBluetooth();
    if (!initialized) {
      _showErrorDialog(context, 'Error', 'No se pudo inicializar Bluetooth. Verifica que esté habilitado y los permisos otorgados.');
      return null;
    }

    List<BluetoothDevice> devices = await scanDevices();
    if (devices.isEmpty) {
      _showErrorDialog(context, 'Sin dispositivos', 'No se encontraron impresoras Bluetooth emparejadas.');
      return null;
    }

    return showDialog<BluetoothDevice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar Impresora'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return ListTile(
                leading: const Icon(Icons.print, color: Color(0xFF4A90E2)),
                title: Text(device.name ?? 'Dispositivo desconocido'),
                subtitle: Text(device.address ?? ''),
                onTap: () => Navigator.pop(context, device),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  /// Show error dialog
  void _showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show print confirmation dialog
  Future<bool> showPrintConfirmationDialog(BuildContext context, Order order) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.print, color: Color(0xFF4A90E2)),
            SizedBox(width: 8),
            Text('Imprimir Factura'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Deseas imprimir la factura para la orden ${order.id}?'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (order.buyerName != null) 
                    Text('Cliente: ${order.buyerName}', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text('Total: \$${order.total.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w500)),
                  Text('Productos: ${order.items.length}'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No imprimir'),
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
    ) ?? false;
  }
}
