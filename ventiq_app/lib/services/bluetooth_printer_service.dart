import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

import '../models/order.dart';

/// Custom scrolling text widget for long text that doesn't fit
class ScrollingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration scrollDuration;
  final Duration pauseDuration;

  const ScrollingText({
    Key? key,
    required this.text,
    this.style,
    this.scrollDuration = const Duration(seconds: 3),
    this.pauseDuration = const Duration(seconds: 1),
  }) : super(key: key);

  @override
  State<ScrollingText> createState() => _ScrollingTextState();
}

class _ScrollingTextState extends State<ScrollingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late ScrollController _scrollController;
  bool _needsScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _controller = AnimationController(
      duration: widget.scrollDuration,
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfScrollingNeeded();
    });
  }

  void _checkIfScrollingNeeded() {
    if (_scrollController.hasClients) {
      final maxScrollExtent = _scrollController.position.maxScrollExtent;
      if (maxScrollExtent > 0) {
        setState(() {
          _needsScrolling = true;
        });
        _startScrolling();
      }
    }
  }

  void _startScrolling() async {
    if (!_needsScrolling || !mounted) return;
    
    await Future.delayed(widget.pauseDuration);
    if (!mounted) return;
    
    _controller.forward().then((_) async {
      if (!mounted) return;
      await Future.delayed(widget.pauseDuration);
      if (!mounted) return;
      _controller.reverse().then((_) {
        if (mounted) _startScrolling();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        if (_scrollController.hasClients && _needsScrolling) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(maxScroll * _animation.value);
        }
        
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
        );
      },
    );
  }
}

class BluetoothPrinterService {
  static final BluetoothPrinterService _instance = BluetoothPrinterService._internal();
  factory BluetoothPrinterService() => _instance;
  BluetoothPrinterService._internal();

  List<BluetoothInfo> _pairedDevices = [];
  List<BluetoothInfo> _discoveredDevices = [];
  BluetoothInfo? _selectedDevice;
  bool _isConnected = false;
  bool _isScanning = false;
  Timer? _scanTimer;

  // Getters
  List<BluetoothInfo> get pairedDevices => _pairedDevices;
  List<BluetoothInfo> get discoveredDevices => _discoveredDevices;
  BluetoothInfo? get selectedDevice => _selectedDevice;
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;

  /// Initialize Bluetooth with automatic permission handling
  Future<bool> initializeBluetooth(BuildContext context) async {
    try {
      debugPrint('Initializing Bluetooth...');
      
      // Check and request permissions
      bool permissionsGranted = await _checkAndRequestPermissions(context);
      if (!permissionsGranted) {
        debugPrint('Bluetooth permissions not granted');
        return false;
      }
      
      // Check if Bluetooth is available and enabled
      bool isAvailable = await PrintBluetoothThermal.bluetoothEnabled;
      
      if (!isAvailable) {
        debugPrint('Bluetooth not enabled - please enable Bluetooth in settings');
        _showBluetoothEnableDialog(context);
        return false;
      }
      
      debugPrint('Bluetooth initialized successfully');
      return true;
    } catch (e) {
      debugPrint('Error initializing Bluetooth: $e');
      return false;
    }
  }

  /// Check and request Bluetooth permissions automatically
  Future<bool> _checkAndRequestPermissions(BuildContext context) async {
    try {
      // List of required permissions
      List<Permission> requiredPermissions = [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ];

      // Check current permission status
      Map<Permission, PermissionStatus> statuses = await requiredPermissions.asMap().map(
        (index, permission) => MapEntry(permission, PermissionStatus.denied),
      );

      // Get actual statuses
      for (Permission permission in requiredPermissions) {
        statuses[permission] = await permission.status;
      }

      // Filter permissions that need to be requested
      List<Permission> permissionsToRequest = [];
      for (Permission permission in requiredPermissions) {
        if (statuses[permission] != PermissionStatus.granted) {
          permissionsToRequest.add(permission);
        }
      }

      if (permissionsToRequest.isEmpty) {
        return true; // All permissions already granted
      }

      // Show permission dialog and request
      bool userAccepted = await _showPermissionDialog(context, permissionsToRequest);
      if (!userAccepted) {
        return false;
      }

      // Request permissions
      Map<Permission, PermissionStatus> results = {};
      for (Permission permission in permissionsToRequest) {
        results[permission] = await permission.request();
      }
      
      // Check if all permissions were granted
      bool allGranted = results.values.every((status) => status == PermissionStatus.granted);
      
      if (!allGranted) {
        _showPermissionDeniedDialog(context);
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return false;
    }
  }

  /// Show permission request dialog
  Future<bool> _showPermissionDialog(BuildContext context, List<Permission> permissions) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.bluetooth, color: const Color(0xFF4A90E2)),
            SizedBox(width: 8),
            Expanded(
              child: ScrollingText(
                text: 'Permisos Requeridos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScrollingText(
              text: 'Para usar la impresora Bluetooth necesitamos los siguientes permisos:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: 16),
            ...permissions.map((permission) => Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: const Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Expanded(
                    child: ScrollingText(
                      text: _getPermissionDescription(permission),
                    ),
                  ),
                ],
              ),
            )),
            SizedBox(height: 16),
            ScrollingText(
              text: 'Los permisos se solicitarán automáticamente.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
            ),
            child: Text('Conceder Permisos'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Get user-friendly permission description
  String _getPermissionDescription(Permission permission) {
    switch (permission) {
      case Permission.bluetooth:
        return 'Acceso a Bluetooth';
      case Permission.bluetoothConnect:
        return 'Conectar dispositivos Bluetooth';
      case Permission.bluetoothScan:
        return 'Escanear dispositivos Bluetooth';
      case Permission.location:
        return 'Ubicación (requerida para Bluetooth)';
      default:
        return 'Permiso desconocido';
    }
  }

  /// Show permission denied dialog
  void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: ScrollingText(
          text: 'Permisos Denegados',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: ScrollingText(
          text: 'No se pueden usar las funciones de impresora Bluetooth sin los permisos necesarios. '
              'Puedes habilitarlos manualmente en Configuración > Aplicaciones > VentIQ > Permisos.',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
            ),
            child: Text('Ir a Configuración'),
          ),
        ],
      ),
    );
  }

  /// Show Bluetooth enable dialog
  void _showBluetoothEnableDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: ScrollingText(
                text: 'Bluetooth Deshabilitado',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        content: ScrollingText(
          text: 'Para usar la impresora necesitas habilitar Bluetooth en tu dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido'),
          ),
        ],
      ),
    );
  }



  /// Scan for available Bluetooth devices (both paired and discoverable)
  Future<void> scanDevices({int scanDurationSeconds = 10}) async {
    if (_isScanning) return;
    
    try {
      _isScanning = true;
      
      // Clear previous devices
      _pairedDevices.clear();
      _discoveredDevices.clear();
      
      // Get paired devices first
      List<BluetoothInfo> pairedDevices = await PrintBluetoothThermal.pairedBluetooths;
      _pairedDevices = pairedDevices;
      
      debugPrint('Found ${_pairedDevices.length} paired devices');
      
      // Start discovery scan for new devices
      await _startDeviceDiscovery(scanDurationSeconds);
      
    } catch (e) {
      debugPrint('Error scanning devices: $e');
    } finally {
      _isScanning = false;
    }
  }

  /// Start device discovery for new devices
  Future<void> _startDeviceDiscovery(int durationSeconds) async {
    try {
      // Check if Bluetooth is enabled
      bool discoveryStarted = await PrintBluetoothThermal.bluetoothEnabled;
      
      if (!discoveryStarted) {
        debugPrint('Bluetooth is not enabled for discovery');
        return;
      }

      // Set up timer for discovery duration
      _scanTimer = Timer(Duration(seconds: durationSeconds), () {
        _stopDeviceDiscovery();
      });

      debugPrint('Started Bluetooth discovery for $durationSeconds seconds');
      
      // Note: print_bluetooth_thermal doesn't have built-in discovery
      // We'll rely on paired devices for now, but this structure allows
      // for future enhancement with a different Bluetooth package
      
    } catch (e) {
      debugPrint('Error starting device discovery: $e');
    }
  }

  /// Stop device discovery
  void _stopDeviceDiscovery() {
    _scanTimer?.cancel();
    _scanTimer = null;
    debugPrint('Stopped Bluetooth discovery');
  }

  /// Connect to a specific Bluetooth device
  Future<bool> connectToDevice(BluetoothInfo device) async {
    try {
      bool connected = await PrintBluetoothThermal.connect(macPrinterAddress: device.macAdress);
      _selectedDevice = device;
      _isConnected = connected;
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
      await PrintBluetoothThermal.disconnect;
      _isConnected = false;
      _selectedDevice = null;
      _stopDeviceDiscovery(); // Stop any ongoing discovery
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  /// Print invoice for an order with customer receipt and warehouse picking slip
  Future<bool> printInvoice(Order order) async {
    if (!_isConnected || _selectedDevice == null) {
      debugPrint('Printer not connected');
      return false;
    }

    try {
      // Create ESC/POS profile
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      // ========== CUSTOMER RECEIPT ==========
      bytes += _addCustomerReceipt(generator, order);
      
      // ========== DOTTED LINE SEPARATOR ==========
      bytes += _addDottedLineSeparator(generator);
      
      // ========== WAREHOUSE PICKING SLIP ==========
      bytes += _addWarehousePickingSlip(generator, order);
      
      bytes += generator.emptyLines(3);
      bytes += generator.cut();

      // Send to printer
      bool result = await PrintBluetoothThermal.writeBytes(bytes);
      return result;
    } catch (e) {
      debugPrint('Error printing invoice: $e');
      return false;
    }
  }

  /// Add customer receipt section
  List<int> _addCustomerReceipt(Generator generator, Order order) {
    List<int> bytes = [];

    // Header
    bytes += generator.text('VENTIQ', styles: PosStyles(align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text('Sistema de Ventas', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('FACTURA DE VENTA', styles: PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('================================', styles: PosStyles(align: PosAlign.center));
    bytes += generator.emptyLines(1);

    // Order information
    bytes += generator.text('ORDEN: ${order.id}', styles: PosStyles(align: PosAlign.left, bold: true));
    
    if (order.buyerName != null && order.buyerName!.isNotEmpty) {
      bytes += generator.text('CLIENTE: ${order.buyerName}', styles: PosStyles(align: PosAlign.left));
    }
    
    if (order.buyerPhone != null && order.buyerPhone!.isNotEmpty) {
      bytes += generator.text('TELEFONO: ${order.buyerPhone}', styles: PosStyles(align: PosAlign.left));
    }
    
    bytes += generator.text('FECHA: ${_formatDateForPrint(order.fechaCreacion)}', styles: PosStyles(align: PosAlign.left));
    bytes += generator.text('PAGO: ${order.paymentMethod ?? 'Efectivo'}', styles: PosStyles(align: PosAlign.left));
    bytes += generator.emptyLines(1);

    // Products header
    bytes += generator.text('PRODUCTOS:', styles: PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.text('--------------------------------', styles: PosStyles(align: PosAlign.center));

    // Products
    double subtotal = 0;
    for (var item in order.items) {
      double itemTotal = item.cantidad * item.precioUnitario;
      subtotal += itemTotal;
      
      bytes += generator.text('${item.cantidad}x ${item.producto.denominacion}', styles: PosStyles(align: PosAlign.left));
      bytes += generator.text('\$${item.precioUnitario.toStringAsFixed(0)} c/u = \$${itemTotal.toStringAsFixed(0)}', 
                             styles: PosStyles(align: PosAlign.right));
    }

    // Totals
    bytes += generator.text('--------------------------------', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('SUBTOTAL: \$${subtotal.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.right, bold: true));
    bytes += generator.text('TOTAL: \$${order.total.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2));
    bytes += generator.emptyLines(1);

    // Footer
    bytes += generator.text('¡Gracias por su compra!', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('VENTIQ - Sistema de Ventas', styles: PosStyles(align: PosAlign.center));
    
    if (order.notas != null && order.notas!.isNotEmpty) {
      bytes += generator.emptyLines(1);
      bytes += generator.text('Notas: ${order.notas}', styles: PosStyles(align: PosAlign.left));
    }
    
    bytes += generator.emptyLines(2);
    
    return bytes;
  }

  /// Add dotted line separator
  List<int> _addDottedLineSeparator(Generator generator) {
    List<int> bytes = [];
    
    bytes += generator.text('................................', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('................................', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('................................', styles: PosStyles(align: PosAlign.center));
    bytes += generator.emptyLines(1);
    
    return bytes;
  }

  /// Add warehouse picking slip section
  List<int> _addWarehousePickingSlip(Generator generator, Order order) {
    List<int> bytes = [];

    // Header
    bytes += generator.text('VENTIQ', styles: PosStyles(align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2));
    bytes += generator.text('COMPROBANTE DE ALMACEN', styles: PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('GUIA DE PICKING', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('================================', styles: PosStyles(align: PosAlign.center));
    bytes += generator.emptyLines(1);

    // Order information
    bytes += generator.text('ORDEN: ${order.id}', styles: PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.text('FECHA: ${_formatDateForPrint(order.fechaCreacion)}', styles: PosStyles(align: PosAlign.left));
    
    if (order.buyerName != null && order.buyerName!.isNotEmpty) {
      bytes += generator.text('CLIENTE: ${order.buyerName}', styles: PosStyles(align: PosAlign.left));
    }
    
    bytes += generator.text('ESTADO: ${order.status.displayName.toUpperCase()}', styles: PosStyles(align: PosAlign.left));
    bytes += generator.emptyLines(1);

    // Products header for picking
    bytes += generator.text('PRODUCTOS A RECOGER:', styles: PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.text('--------------------------------', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('CANT | PRODUCTO | UBICACION', styles: PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.text('--------------------------------', styles: PosStyles(align: PosAlign.center));

    // Products with warehouse locations
    for (var item in order.items) {
      String ubicacion = item.ubicacionAlmacen ?? 'N/A';
      String productName = item.producto.denominacion;
      
      // Truncate product name if too long
      if (productName.length > 15) {
        productName = productName.substring(0, 15) + '...';
      }
      
      bytes += generator.text('${item.cantidad.toString().padLeft(3)} | $productName', styles: PosStyles(align: PosAlign.left));
      bytes += generator.text('    | Ubic: $ubicacion', styles: PosStyles(align: PosAlign.left));
      bytes += generator.text('    | \$${item.precioUnitario.toStringAsFixed(0)} c/u', styles: PosStyles(align: PosAlign.left));
      bytes += generator.emptyLines(1);
    }

    // Summary
    bytes += generator.text('--------------------------------', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('TOTAL PRODUCTOS: ${order.totalItems}', styles: PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.text('VALOR TOTAL: \$${order.total.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.emptyLines(1);

    // Instructions
    bytes += generator.text('INSTRUCCIONES:', styles: PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.text('1. Verificar cantidad y producto', styles: PosStyles(align: PosAlign.left));
    bytes += generator.text('2. Confirmar ubicacion en almacen', styles: PosStyles(align: PosAlign.left));
    bytes += generator.text('3. Marcar como completado', styles: PosStyles(align: PosAlign.left));
    bytes += generator.emptyLines(1);

    // Signature section
    bytes += generator.text('--------------------------------', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('FIRMA ALMACENERO:', styles: PosStyles(align: PosAlign.left, bold: true));
    bytes += generator.emptyLines(3);
    bytes += generator.text('_________________________', styles: PosStyles(align: PosAlign.left));
    bytes += generator.text('Nombre y Firma', styles: PosStyles(align: PosAlign.left));
    bytes += generator.emptyLines(1);
    
    bytes += generator.text('HORA COMPLETADO: ___________', styles: PosStyles(align: PosAlign.left));
    bytes += generator.emptyLines(1);

    // Footer
    bytes += generator.text('VENTIQ - Sistema de Almacen', styles: PosStyles(align: PosAlign.center));
    
    return bytes;
  }





  /// Format date for printing
  String _formatDateForPrint(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/"
           "${date.month.toString().padLeft(2, '0')}/"
           "${date.year} "
           "${date.hour.toString().padLeft(2, '0')}:"
           "${date.minute.toString().padLeft(2, '0')}";
  }

  /// Show enhanced device selection dialog with scanning
  Future<BluetoothInfo?> showDeviceSelectionDialog(BuildContext context) async {
    bool initialized = await initializeBluetooth(context);
    if (!initialized) {
      return null;
    }

    // Start scanning
    await scanDevices(scanDurationSeconds: 10);

    if (_pairedDevices.isEmpty && _discoveredDevices.isEmpty) {
      _showErrorDialog(context, 'Sin dispositivos', 'No se encontraron impresoras Bluetooth.');
      return null;
    }

    return showDialog<BluetoothInfo>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.bluetooth_searching, color: const Color(0xFF4A90E2)),
              SizedBox(width: 8),
              Expanded(
                child: ScrollingText(
                  text: 'Seleccionar Impresora',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_isScanning) ...[
                SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Paired devices section
                  if (_pairedDevices.isNotEmpty) ...[
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth_connected, color: const Color(0xFF10B981), size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: ScrollingText(
                              text: 'Dispositivos Emparejados (${_pairedDevices.length})',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 8),
                    ..._pairedDevices.map((device) => _buildDeviceCard(device, true, context)),
                    SizedBox(height: 16),
                  ],
                  
                  // Discovered devices section
                  if (_discoveredDevices.isNotEmpty) ...[
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth, color: const Color(0xFF4A90E2), size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: ScrollingText(
                              text: 'Dispositivos Encontrados (${_discoveredDevices.length})',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF4A90E2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 8),
                    ..._discoveredDevices.map((device) => _buildDeviceCard(device, false, context)),
                  ],
                  
                  // No devices found message
                  if (_pairedDevices.isEmpty && _discoveredDevices.isEmpty)
                    Container(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.bluetooth_disabled, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          ScrollingText(
                            text: 'No se encontraron dispositivos',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                setState(() {});
                await scanDevices(scanDurationSeconds: 10);
                setState(() {});
              },
              icon: Icon(Icons.refresh, color: const Color(0xFF4A90E2)),
              label: Text('Buscar de Nuevo', style: TextStyle(color: const Color(0xFF4A90E2))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar', style: TextStyle(color: Colors.grey[600])),
            ),
          ],
        ),
      ),
    );
  }

  /// Build device card widget
  Widget _buildDeviceCard(BluetoothInfo device, bool isPaired, BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isPaired ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFF4A90E2).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isPaired ? Icons.print : Icons.print_outlined,
            color: isPaired ? const Color(0xFF10B981) : const Color(0xFF4A90E2),
            size: 24,
          ),
        ),
        title: ScrollingText(
          text: device.name.isNotEmpty ? device.name : 'Dispositivo Desconocido',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.settings_ethernet, size: 14, color: Colors.grey[600]),
                SizedBox(width: 4),
                Expanded(
                  child: ScrollingText(
                    text: device.macAdress,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 2),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isPaired ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFF4A90E2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isPaired ? 'Emparejado' : 'Disponible',
                style: TextStyle(
                  fontSize: 11,
                  color: isPaired ? const Color(0xFF10B981) : const Color(0xFF4A90E2),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey[400],
        ),
        onTap: () => Navigator.pop(context, device),
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
    debugPrint('Iniciando showPrintConfirmationDialog');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.print, color: const Color(0xFF4A90E2)),
            SizedBox(width: 8),
            Expanded(
              child: ScrollingText(
                text: 'Imprimir Factura',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
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
            onPressed: () {
              debugPrint('Usuario presionó "No imprimir"');
              Navigator.pop(context, false);
            },
            child: const Text('No imprimir'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              debugPrint('Usuario presionó "Imprimir"');
              Navigator.pop(context, true);
            },
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
    
    debugPrint('Resultado del showDialog: $result');
    return result;
  }

  /// Dispose resources
  void dispose() {
    _scanTimer?.cancel();
  }

  /// App color constants for consistency
  static const Color primaryBlue = Color(0xFF4A90E2);
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningOrange = Colors.orange;
  static const Color errorRed = Colors.red;
}
