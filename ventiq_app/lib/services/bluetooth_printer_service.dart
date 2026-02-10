import 'dart:async';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order.dart';
import '../services/currency_service.dart';
import '../services/user_preferences_service.dart';

class _StorePrintInfo {
  final String name;
  final Uint8List? logoBytes;

  const _StorePrintInfo({required this.name, this.logoBytes});
}

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
  static final BluetoothPrinterService _instance =
      BluetoothPrinterService._internal();
  factory BluetoothPrinterService() => _instance;
  BluetoothPrinterService._internal();

  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  _StorePrintInfo? _storePrintInfoCache;
  Future<_StorePrintInfo>? _storePrintInfoFuture;

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
        debugPrint(
          'Bluetooth not enabled - please enable Bluetooth in settings',
        );
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

  /// Print multiple customer receipts in a single job (no warehouse slip)
  Future<bool> printCustomerReceiptsBatch(List<Order> orders) async {
    if (!_isConnected || _selectedDevice == null) {
      debugPrint('❌ Printer not connected');
      return false;
    }
    if (orders.isEmpty) {
      debugPrint('⚠️ No orders provided for batch print');
      return false;
    }

    try {
      debugPrint(
        '🖨️ Starting batch customer print (${orders.length} orders)...',
      );

      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      final storeInfo = await _getStorePrintInfo();
      List<int> bytes = [];

      bytes += _addStoreHeader(generator, storeInfo);
      bytes += generator.text(
        'FACTURAS POR LOTE',
        styles: PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '----------------------------',
        styles: PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);

      final usdRate = await _getUsdRateForPrint();

      for (int i = 0; i < orders.length; i++) {
        bytes += _addCustomerReceipt(
          generator,
          orders[i],
          storeInfo,
          includeHeader: false,
          usdRate: usdRate,
        );
        if (i < orders.length - 1) {
          bytes += _addDottedLineSeparator(generator);
        }
      }

      bytes += generator.cut();

      debugPrint('📤 Sending batch customer receipts (${bytes.length} bytes)');
      return await _sendToPrinterWithRetry(bytes, 'Batch Customer Receipts');
    } catch (e) {
      debugPrint('❌ Error printing batch receipts: $e');
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
      Map<Permission, PermissionStatus> statuses = await requiredPermissions
          .asMap()
          .map(
            (index, permission) =>
                MapEntry(permission, PermissionStatus.denied),
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
      bool userAccepted = await _showPermissionDialog(
        context,
        permissionsToRequest,
      );
      if (!userAccepted) {
        return false;
      }

      // Request permissions
      Map<Permission, PermissionStatus> results = {};
      for (Permission permission in permissionsToRequest) {
        results[permission] = await permission.request();
      }

      // Check if all permissions were granted
      bool allGranted = results.values.every(
        (status) => status == PermissionStatus.granted,
      );

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
  Future<bool> _showPermissionDialog(
    BuildContext context,
    List<Permission> permissions,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
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
                      text:
                          'Para usar la impresora Bluetooth necesitamos los siguientes permisos:',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                    SizedBox(height: 16),
                    ...permissions.map(
                      (permission) => Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: const Color(0xFF10B981),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: ScrollingText(
                                text: _getPermissionDescription(permission),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
        ) ??
        false;
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
      builder:
          (context) => AlertDialog(
            title: ScrollingText(
              text: 'Permisos Denegados',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            content: ScrollingText(
              text:
                  'No se pueden usar las funciones de impresora Bluetooth sin los permisos necesarios. '
                  'Puedes habilitarlos manualmente en Configuración > Aplicaciones > VentIQ > Permisos.',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
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
      builder:
          (context) => AlertDialog(
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
              text:
                  'Para usar la impresora necesitas habilitar Bluetooth en tu dispositivo.',
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
      List<BluetoothInfo> pairedDevices =
          await PrintBluetoothThermal.pairedBluetooths;
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
      bool connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: device.macAdress,
      );
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
      debugPrint('❌ Printer not connected');
      return false;
    }

    try {
      debugPrint('🖨️ Starting split print job for order: ${order.id}');
      debugPrint('📦 Order has ${order.items.length} items');

      // Create ESC/POS profile
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      final storeInfo = await _getStorePrintInfo();

      // ========== PRINT CUSTOMER RECEIPT FIRST ==========
      debugPrint('📄 Printing customer receipt...');
      bool customerResult = await _printCustomerReceipt(
        generator,
        order,
        storeInfo,
      );

      if (!customerResult) {
        debugPrint('❌ Customer receipt failed to print');
        return false;
      }

      // Wait between prints to avoid buffer issues
      debugPrint('⏳ Waiting 3 seconds before warehouse slip...');
      await Future.delayed(const Duration(seconds: 3));

      // ========== PRINT WAREHOUSE PICKING SLIP SEPARATELY ==========
      debugPrint('🏭 Printing warehouse picking slip...');
      bool warehouseResult = await _printWarehouseSlip(
        generator,
        order,
        storeInfo,
      );

      if (!warehouseResult) {
        debugPrint('❌ Warehouse slip failed to print');
        return false;
      }

      debugPrint('✅ Both receipts printed successfully');

      // Wait between prints
      debugPrint('⏳ Waiting 3 seconds before seller receipt...');
      await Future.delayed(const Duration(seconds: 3));

      // ========== PRINT SELLER RECEIPT ==========
      debugPrint('👤 Printing seller receipt...');
      bool sellerResult = await _printCustomerReceipt(
        generator,
        order,
        storeInfo,
        title: 'RECIBO VENDEDOR',
      );

      if (!sellerResult) {
        debugPrint('❌ Seller receipt failed to print');
        // We don't return false here as the main receipts were printed
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error printing invoice: $e');
      return false;
    }
  }

  /// Print customer receipt as separate job
  Future<bool> _printCustomerReceipt(
    Generator generator,
    Order order,
    _StorePrintInfo storeInfo, {
    String title = 'FACTURA',
  }) async {
    try {
      final usdRate = await _getUsdRateForPrint();
      List<int> bytes = [];

      bytes += _addCustomerReceipt(
        generator,
        order,
        storeInfo,
        usdRate: usdRate,
        title: title,
      );
      bytes += generator.emptyLines(1);
      bytes += generator.cut();

      debugPrint('📤 Sending $title (${bytes.length} bytes)...');

      return await _sendToPrinterWithRetry(bytes, title);
    } catch (e) {
      debugPrint('❌ Error creating $title: $e');
      return false;
    }
  }

  /// Print warehouse slip as separate job
  Future<bool> _printWarehouseSlip(
    Generator generator,
    Order order,
    _StorePrintInfo storeInfo,
  ) async {
    try {
      final usdRate = await _getUsdRateForPrint();
      List<int> bytes = [];

      bytes += _addWarehousePickingSlip(
        generator,
        order,
        storeInfo,
        usdRate: usdRate,
      );
      bytes += generator.emptyLines(1);
      bytes += generator.cut();

      debugPrint('📤 Sending warehouse slip (${bytes.length} bytes)...');

      return await _sendToPrinterWithRetry(bytes, 'Warehouse Slip');
    } catch (e) {
      debugPrint('❌ Error creating warehouse slip: $e');
      return false;
    }
  }

  /// Send bytes to printer with retry logic
  Future<bool> _sendToPrinterWithRetry(List<int> bytes, String jobName) async {
    bool result = false;
    int attempts = 0;
    const maxAttempts = 3;

    while (!result && attempts < maxAttempts) {
      attempts++;
      debugPrint('🔄 $jobName - Print attempt $attempts of $maxAttempts');

      try {
        result = await PrintBluetoothThermal.writeBytes(bytes);
        if (result) {
          debugPrint('✅ $jobName - Print successful on attempt $attempts');
        } else {
          debugPrint('❌ $jobName - Print failed on attempt $attempts');
          if (attempts < maxAttempts) {
            debugPrint('⏳ Waiting 2 seconds before retry...');
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      } catch (printError) {
        debugPrint(
          '❌ $jobName - Print error on attempt $attempts: $printError',
        );
        if (attempts < maxAttempts) {
          debugPrint('⏳ Waiting 3 seconds before retry...');
          await Future.delayed(const Duration(seconds: 3));
        }
      }
    }

    if (!result) {
      debugPrint('❌ $jobName - All print attempts failed');
    }

    return result;
  }

  Future<_StorePrintInfo> _getStorePrintInfo() async {
    if (_storePrintInfoCache != null) {
      return _storePrintInfoCache!;
    }

    _storePrintInfoFuture ??= _loadStorePrintInfo();
    _storePrintInfoCache = await _storePrintInfoFuture!;
    return _storePrintInfoCache!;
  }

  Future<double?> _getUsdRateForPrint() async {
    final showUsd = await _userPreferencesService.isPrintUsdEnabled();
    if (!showUsd) {
      return null;
    }

    final usdRate = await CurrencyService.getUsdRate();
    if (usdRate <= 0) {
      return null;
    }
    return usdRate;
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
      final logoBytes = await _downloadImageBytes(storeLogoUrl);

      return _StorePrintInfo(name: storeName, logoBytes: logoBytes);
    } catch (e) {
      debugPrint(
        '⚠️ No se pudo cargar datos de tienda para impresión Bluetooth: $e',
      );
      return const _StorePrintInfo(name: 'VentIQ');
    }
  }

  Future<Uint8List?> _downloadImageBytes(String? url) async {
    if (url == null || url.isEmpty) return null;

    const objectPrefix =
        'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/';
    const renderPrefix =
        'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/render/image/public/images_back/';

    final renderUrl =
        url.contains(objectPrefix)
            ? '${url.replaceFirst(objectPrefix, renderPrefix)}?width=32&height=32'
            : url;

    try {
      final response = await http.get(Uri.parse(renderUrl));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ No se pudo descargar imagen de tienda: $e');
      return null;
    }
  }

  img.Image? _decodeLogoImage(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return img.decodeImage(bytes);
  }

  img.Image _resizeLogoForPrinter(img.Image image) {
    const targetWidth = 240;
    if (image.width <= targetWidth) {
      return image;
    }
    return img.copyResize(image, width: targetWidth);
  }

  img.Image _normalizeLogoForEscPos(img.Image image) {
    final normalizedWidth = (image.width ~/ 8) * 8;
    final byteAligned =
        (normalizedWidth > 0 && normalizedWidth != image.width)
            ? img.copyResize(image, width: normalizedWidth)
            : image;

    return img.grayscale(byteAligned);
  }

  List<int> _escPosInit() {
    return const <int>[0x1B, 0x40];
  }

  List<int> _addStoreHeader(Generator generator, _StorePrintInfo storeInfo) {
    List<int> bytes = [];
    final logoImage = _decodeLogoImage(storeInfo.logoBytes);

    if (logoImage != null) {
      try {
        final resized = _resizeLogoForPrinter(logoImage);
        final normalized = _normalizeLogoForEscPos(resized);

        bytes += generator.imageRaster(normalized, align: PosAlign.center);
        bytes += _escPosInit();
        bytes += generator.emptyLines(1);
        bytes += generator.text(
          storeInfo.name,
          styles: const PosStyles(align: PosAlign.center),
        );
      } catch (e) {
        debugPrint('⚠️ Error imprimiendo logo, usando header solo texto: $e');
        bytes += generator.text(
          storeInfo.name,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
      }
    } else {
      bytes += generator.text(
        storeInfo.name,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }

    bytes += generator.emptyLines(1);
    return bytes;
  }

  /// Add customer receipt section
  List<int> _addCustomerReceipt(
    Generator generator,
    Order order,
    _StorePrintInfo storeInfo, {
    bool includeHeader = true,
    double? usdRate,
    String title = 'FACTURA',
  }) {
    List<int> bytes = [];

    // Header compacto
    if (includeHeader) {
      bytes += _addStoreHeader(generator, storeInfo);
    }
    bytes += generator.text(
      title,
      styles: PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    // Order information compacta
    bytes += generator.text(
      'ORD: ${order.id.length > 20 ? order.id.substring(0, 20) : order.id}',
      styles: PosStyles(align: PosAlign.left, bold: true),
    );

    final sellerName = order.sellerName;
    if (sellerName != null && sellerName.isNotEmpty) {
      final displayName =
          sellerName.length > 26
              ? '${sellerName.substring(0, 23)}...'
              : sellerName;
      bytes += generator.text(
        'VEND: $displayName',
        styles: PosStyles(align: PosAlign.left),
      );
    }

    final tpvName = order.tpvName;
    if (tpvName != null && tpvName.isNotEmpty) {
      final displayName =
          tpvName.length > 26 ? '${tpvName.substring(0, 23)}...' : tpvName;
      bytes += generator.text(
        'TPV: $displayName',
        styles: PosStyles(align: PosAlign.left),
      );
    }

    if (order.buyerName != null && order.buyerName!.isNotEmpty) {
      bytes += generator.text(
        'CLI: ${order.buyerName}',
        styles: PosStyles(align: PosAlign.left),
      );
    }

    if (order.buyerPhone != null && order.buyerPhone!.isNotEmpty) {
      bytes += generator.text(
        'TEL: ${order.buyerPhone}',
        styles: PosStyles(align: PosAlign.left),
      );
    }

    bytes += generator.text(
      '${_formatDateForPrint(order.fechaCreacion)}',
      styles: PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    // Products compactos
    double subtotal = 0;
    for (var item in order.items) {
      double itemTotal = item.cantidad * item.precioUnitario;
      subtotal += itemTotal;

      // Nombre del producto en una línea
      String prodName = item.producto.denominacion;
      if (prodName.length > 28) prodName = prodName.substring(0, 25) + '...';
      bytes += generator.text(
        '${item.cantidad}x $prodName',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        '  \$${item.precioUnitario.toStringAsFixed(0)} = \$${itemTotal.toStringAsFixed(0)}',
        styles: PosStyles(align: PosAlign.right),
      );
    }

    // Totals compactos
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'TOTAL: \$${order.total.toStringAsFixed(0)}',
      styles: PosStyles(align: PosAlign.right, bold: true),
    );
    if (usdRate != null && usdRate > 0) {
      final usdTotal = order.total / usdRate;
      bytes += generator.text(
        'USD (${usdRate.toStringAsFixed(0)}): \$${usdTotal.toStringAsFixed(2)}',
        styles: PosStyles(align: PosAlign.right, bold: true),
      );
    }

    // Footer compacto
    bytes += generator.text(
      'Gracias por su compra',
      styles: PosStyles(align: PosAlign.center),
    );

    if (order.notas != null && order.notas!.isNotEmpty) {
      bytes += generator.text(
        'Nota: ${order.notas}',
        styles: PosStyles(align: PosAlign.left),
      );
    }

    bytes += generator.emptyLines(1);

    return bytes;
  }

  /// Add dotted line separator
  List<int> _addDottedLineSeparator(Generator generator) {
    List<int> bytes = [];

    bytes += generator.text(
      '................................',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      '................................',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      '................................',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(1);

    return bytes;
  }

  /// Add warehouse picking slip section
  List<int> _addWarehousePickingSlip(
    Generator generator,
    Order order,
    _StorePrintInfo storeInfo, {
    double? usdRate,
  }) {
    List<int> bytes = [];

    debugPrint('🏭 Creating warehouse picking slip for order ${order.id}');

    // Header compacto
    bytes += _addStoreHeader(generator, storeInfo);
    bytes += generator.text(
      'GUIA ALMACEN',
      styles: PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    debugPrint('📋 Warehouse header added');

    // Order information compacta
    bytes += generator.text(
      'ORD: ${order.id.length > 20 ? order.id.substring(0, 20) : order.id}',
      styles: PosStyles(align: PosAlign.left, bold: true),
    );
    bytes += generator.text(
      '${_formatDateForPrint(order.fechaCreacion)}',
      styles: PosStyles(align: PosAlign.left),
    );

    if (order.buyerName != null && order.buyerName!.isNotEmpty) {
      bytes += generator.text(
        'CLI: ${order.buyerName}',
        styles: PosStyles(align: PosAlign.left),
      );
    }

    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    // Products compactos
    debugPrint('📦 Adding ${order.items.length} products to warehouse slip');
    for (int i = 0; i < order.items.length; i++) {
      var item = order.items[i];
      String ubicacion = item.ubicacionAlmacen ?? 'N/A';
      String productName = item.producto.denominacion;

      debugPrint(
        '📋 Product ${i + 1}: ${item.cantidad}x $productName @ $ubicacion',
      );

      // Truncar nombre si es muy largo
      if (productName.length > 22) {
        productName = productName.substring(0, 19) + '...';
      }

      bytes += generator.text(
        '${item.cantidad}x $productName',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        '  Ubic: $ubicacion',
        styles: PosStyles(align: PosAlign.left),
      );
    }
    debugPrint('✅ All warehouse products added');

    // Summary compacto
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'TOT: ${order.totalItems} prod - \$${order.total.toStringAsFixed(0)}',
      styles: PosStyles(align: PosAlign.left, bold: true),
    );
    if (usdRate != null && usdRate > 0) {
      final usdTotal = order.total / usdRate;
      bytes += generator.text(
        'USD (${usdRate.toStringAsFixed(0)}): \$${usdTotal.toStringAsFixed(2)}',
        styles: PosStyles(align: PosAlign.left, bold: true),
      );
    }

    // Footer compacto
    bytes += generator.text(
      '${storeInfo.name} Almacen',
      styles: const PosStyles(align: PosAlign.center),
    );

    debugPrint('🏭 Warehouse picking slip completed (${bytes.length} bytes)');
    return bytes;
  }

  /// Format date for printing
  String _formatDateForPrint(DateTime date) {
    // Convert to local time if it's not already
    final localDate = date.toLocal();
    return "${localDate.day.toString().padLeft(2, '0')}/"
        "${localDate.month.toString().padLeft(2, '0')}/"
        "${localDate.year} "
        "${localDate.hour.toString().padLeft(2, '0')}:"
        "${localDate.minute.toString().padLeft(2, '0')}";
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
      _showErrorDialog(
        context,
        'Sin dispositivos',
        'No se encontraron impresoras Bluetooth.',
      );
      return null;
    }

    return showDialog<BluetoothInfo>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        color: const Color(0xFF4A90E2),
                      ),
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
                              padding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(
                                    0xFF10B981,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bluetooth_connected,
                                    color: const Color(0xFF10B981),
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: ScrollingText(
                                      text:
                                          'Dispositivos Emparejados (${_pairedDevices.length})',
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
                            ..._pairedDevices.map(
                              (device) =>
                                  _buildDeviceCard(device, true, context),
                            ),
                            SizedBox(height: 16),
                          ],

                          // Discovered devices section
                          if (_discoveredDevices.isNotEmpty) ...[
                            Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4A90E2).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(
                                    0xFF4A90E2,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.bluetooth,
                                    color: const Color(0xFF4A90E2),
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: ScrollingText(
                                      text:
                                          'Dispositivos Encontrados (${_discoveredDevices.length})',
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
                            ..._discoveredDevices.map(
                              (device) =>
                                  _buildDeviceCard(device, false, context),
                            ),
                          ],

                          // No devices found message
                          if (_pairedDevices.isEmpty &&
                              _discoveredDevices.isEmpty)
                            Container(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.bluetooth_disabled,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
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
                      label: Text(
                        'Buscar de Nuevo',
                        style: TextStyle(color: const Color(0xFF4A90E2)),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  /// Build device card widget
  Widget _buildDeviceCard(
    BluetoothInfo device,
    bool isPaired,
    BuildContext context,
  ) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4),
      elevation: 2,
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                isPaired
                    ? const Color(0xFF10B981).withOpacity(0.1)
                    : const Color(0xFF4A90E2).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isPaired ? Icons.print : Icons.print_outlined,
            color: isPaired ? const Color(0xFF10B981) : const Color(0xFF4A90E2),
            size: 24,
          ),
        ),
        title: ScrollingText(
          text:
              device.name.isNotEmpty ? device.name : 'Dispositivo Desconocido',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.settings_ethernet,
                  size: 14,
                  color: Colors.grey[600],
                ),
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
                color:
                    isPaired
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : const Color(0xFF4A90E2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isPaired ? 'Emparejado' : 'Disponible',
                style: TextStyle(
                  fontSize: 11,
                  color:
                      isPaired
                          ? const Color(0xFF10B981)
                          : const Color(0xFF4A90E2),
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
      builder:
          (context) => AlertDialog(
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
  Future<bool> showPrintConfirmationDialog(
    BuildContext context,
    Order order,
  ) async {
    debugPrint('Iniciando showPrintConfirmationDialog');
    final result =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
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
                    Text(
                      '¿Deseas imprimir la factura para la orden ${order.id}?',
                    ),
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
                            Text(
                              'Cliente: ${order.buyerName}',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          Text(
                            'Total: \$${order.total.toStringAsFixed(0)}',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
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
        ) ??
        false;

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
