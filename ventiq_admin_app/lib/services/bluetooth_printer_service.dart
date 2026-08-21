import 'dart:async';

import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/ticket_text_utils.dart';
import '../services/printer_preferences_service.dart';

enum _SavedPrinterChoice { use, forget, chooseAnother }

/// Servicio para manejar impresión Bluetooth térmica
class BluetoothPrinterService {
  static final BluetoothPrinterService _instance = BluetoothPrinterService._internal();

  factory BluetoothPrinterService() {
    return _instance;
  }

  BluetoothPrinterService._internal();

  // Estado de conexión
  bool _isConnected = false;
  BluetoothInfo? _selectedDevice;
  List<BluetoothInfo> _pairedDevices = [];
  List<BluetoothInfo> _discoveredDevices = [];
  bool _isScanning = false;
  Timer? _scanTimer;

  // Getters
  bool get isConnected => _isConnected;
  BluetoothInfo? get selectedDevice => _selectedDevice;
  List<BluetoothInfo> get pairedDevices => _pairedDevices;
  List<BluetoothInfo> get discoveredDevices => _discoveredDevices;
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
              child: Text('Permisos Requeridos', style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Para usar la impresora Bluetooth necesitamos los siguientes permisos:',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            SizedBox(height: 16),
            ...permissions.map((permission) => Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: const Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(_getPermissionDescription(permission)),
                  ),
                ],
              ),
            )),
            SizedBox(height: 16),
            Text(
              'Los permisos se solicitarán automáticamente.',
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
        title: Text('Permisos Denegados', style: Theme.of(context).textTheme.titleLarge),
        content: Text(
          'No se pueden usar las funciones de impresora Bluetooth sin los permisos necesarios. '
          'Puedes habilitarlos manualmente en Configuración > Aplicaciones > Inventtia Gestión > Permisos.',
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
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text('Bluetooth Deshabilitado', style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        content: Text('Para usar la impresora necesitas habilitar Bluetooth en tu dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido'),
          ),
        ],
      ),
    );
  }

  /// Scan for available Bluetooth devices (paired + discovery in background).
  ///
  /// Loads paired devices immediately and starts a background discovery timer
  /// without blocking the caller, matching the behavior in ventiq_app.
  Future<void> scanDevices({int scanDurationSeconds = 5}) async {
    if (_isScanning) return;

    try {
      _isScanning = true;

      // Clear previous devices
      _pairedDevices.clear();
      _discoveredDevices.clear();

      debugPrint('🔍 Scanning for Bluetooth devices...');

      // Get paired devices first (fast)
      _pairedDevices = await PrintBluetoothThermal.pairedBluetooths;
      debugPrint('✅ Found ${_pairedDevices.length} paired devices');

      // Start discovery scan in the background; do not block here.
      await _startDeviceDiscovery(scanDurationSeconds);
    } catch (e) {
      debugPrint('❌ Error scanning devices: $e');
    } finally {
      _isScanning = false;
      debugPrint('✅ Scan completed (paired devices ready)');
    }
  }

  /// Start device discovery for new devices in the background.
  Future<void> _startDeviceDiscovery(int durationSeconds) async {
    try {
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) {
        debugPrint('Bluetooth is not enabled for discovery');
        return;
      }

      _scanTimer?.cancel();
      _scanTimer = Timer(Duration(seconds: durationSeconds), () {
        _isScanning = false;
        _scanTimer?.cancel();
        _scanTimer = null;
        debugPrint('✅ Bluetooth discovery finished');
      });

      debugPrint(
        'Started Bluetooth background discovery for $durationSeconds seconds',
      );
    } catch (e) {
      debugPrint('Error starting Bluetooth discovery: $e');
    }
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
      _scanTimer?.cancel();
      _scanTimer = null;
      await PrintBluetoothThermal.disconnect;
      _isConnected = false;
      _selectedDevice = null;
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  /// Show enhanced device selection dialog with scanning.
  /// If [allowSaveDefault] is true, after selecting a device the user is asked
  /// whether to save it as the default printer for this device.
  Future<BluetoothInfo?> showDeviceSelectionDialog(
    BuildContext context, {
    bool allowSaveDefault = true,
  }) async {
    bool initialized = await initializeBluetooth(context);
    if (!initialized) {
      return null;
    }

    // Load paired devices immediately (discovery runs in the background).
    // We await so the list is populated before opening the dialog.
    await scanDevices(scanDurationSeconds: 1);

    // Si hay una impresora Bluetooth guardada, ofrecer usarla primero.
    final savedPrinter = await PrinterPreferencesService().getDefaultBluetoothPrinter();
    if (savedPrinter != null && context.mounted) {
      final choice = await _showSavedBluetoothPrinterDialog(context, savedPrinter);
      if (choice == _SavedPrinterChoice.use) {
        final savedMac = savedPrinter['mac'] as String;
        BluetoothInfo? savedDevice;
        for (final d in _pairedDevices) {
          if (d.macAdress == savedMac) {
            savedDevice = d;
            break;
          }
        }
        if (savedDevice == null) {
          for (final d in _discoveredDevices) {
            if (d.macAdress == savedMac) {
              savedDevice = d;
              break;
            }
          }
        }
        if (savedDevice != null) {
          debugPrint('✅ Usando impresora Bluetooth guardada: ${savedDevice.name}');
          return savedDevice;
        }
        debugPrint('⚠️ Impresora guardada no encontrada entre dispositivos visibles');
      } else if (choice == _SavedPrinterChoice.forget) {
        await PrinterPreferencesService().clearDefaultBluetoothPrinter();
      }
      // chooseAnother: continuar con el diálogo normal
    }

    final selected = await showDialog<BluetoothInfo>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.bluetooth_searching, color: const Color(0xFF4A90E2)),
              SizedBox(width: 8),
              Expanded(
                child: Text('Seleccionar Impresora', style: Theme.of(context).textTheme.titleLarge),
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
                            child: Text(
                              'Dispositivos Emparejados (${_pairedDevices.length})',
                              style: TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
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
                            child: Text(
                              'Dispositivos Encontrados (${_discoveredDevices.length})',
                              style: TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFF4A90E2)),
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
                          Text('No se encontraron dispositivos', style: TextStyle(color: Colors.grey[600])),
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

    if (selected == null || !allowSaveDefault) return selected;

    final shouldSave = await _showSavePrinterDialog(context, selected.name);
    if (shouldSave) {
      await PrinterPreferencesService().saveDefaultBluetoothPrinter(
        selected.name.isNotEmpty ? selected.name : 'Dispositivo BT',
        selected.macAdress,
      );
      debugPrint('💾 Impresora Bluetooth por defecto guardada: ${selected.macAdress}');
    }
    return selected;
  }

  Future<_SavedPrinterChoice> _showSavedBluetoothPrinterDialog(
    BuildContext context,
    Map<String, dynamic> savedPrinter,
  ) async {
    final name = savedPrinter['name']?.toString() ?? 'Impresora guardada';
    final mac = savedPrinter['mac']?.toString() ?? '';
    return await showDialog<_SavedPrinterChoice>(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.bluetooth, color: const Color(0xFF4A90E2)),
                SizedBox(width: 8),
                Expanded(child: Text('Impresora guardada')),
              ],
            ),
            content: Text(
              '¿Usar la impresora Bluetooth guardada por defecto?\n\n'
              'Nombre: $name\n'
              'MAC: $mac',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, _SavedPrinterChoice.forget),
                child: Text('Olvidar', style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _SavedPrinterChoice.chooseAnother),
                child: Text('Elegir otra'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, _SavedPrinterChoice.use),
                child: Text('Usar'),
              ),
            ],
          ),
        ) ??
        _SavedPrinterChoice.chooseAnother;
  }

  Future<bool> _showSavePrinterDialog(BuildContext context, String printerName) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Guardar impresora'),
            content: Text(
              '¿Deseas guardar "$printerName" como impresora por defecto para futuras impresiones?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('No'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Guardar'),
              ),
            ],
          ),
        ) ??
        false;
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
        title: Text(
          device.name.isNotEmpty ? device.name : 'Dispositivo Desconocido',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                  child: Text(
                    device.macAdress,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.grey[700]),
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
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
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
  Future<bool> showPrintConfirmationDialog(BuildContext context) async {
    debugPrint('Iniciando showPrintConfirmationDialog');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.print, color: const Color(0xFF4A90E2)),
            SizedBox(width: 8),
            Expanded(
              child: Text('¿Deseas imprimir?', style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        content: Text('Se enviará el documento a la impresora Bluetooth.'),
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

  /// Print operation ticket
  Future<bool> printOperationTicket(String ticketContent) async {
    if (!_isConnected || _selectedDevice == null) {
      debugPrint('❌ Printer not connected');
      return false;
    }

    try {
      debugPrint('🖨️ Starting print job');
      
      // Create ESC/POS profile
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);

      // Generate ticket bytes
      List<int> bytes = [];
      bytes += generator.text(sanitizeForThermalPrinter(ticketContent));
      bytes += generator.emptyLines(2);
      bytes += generator.cut();

      debugPrint('📤 Sending ticket (${bytes.length} bytes)...');
      return await writeBytesSafe(bytes, jobName: 'Operation Ticket');
    } catch (e) {
      debugPrint('❌ Error printing ticket: $e');
      return false;
    }
  }

  /// Espera a que la impresora consuma el buffer BT antes de cortar el socket.
  /// [totalBytes] es el tamaño aproximado del job ESC/POS enviado.
  Future<void> waitForPrinterBufferDrain(int totalBytes) async {
    // ~25 ms por cada 100 bytes, mínimo 2s, máximo 60s (tickets largos).
    final ms = ((totalBytes / 100) * 25).round().clamp(2000, 60000);
    debugPrint(
      '⏳ Waiting ${ms}ms for printer buffer drain ($totalBytes bytes)...',
    );
    await Future.delayed(Duration(milliseconds: ms));
  }

  /// Envío público con troceo + reintentos (tickets grandes / órdenes largas).
  Future<bool> writeBytesSafe(
    List<int> bytes, {
    String jobName = 'Print Job',
    bool settleAfter = true,
  }) {
    return _sendToPrinterWithRetry(bytes, jobName, settleAfter: settleAfter);
  }

  // Chunks pequeños: muchas térmicas BT fallan con ráfagas grandes.
  static const int _btChunkSize = 256;
  static const Duration _btChunkDelay = Duration(milliseconds: 80);

  /// Escribe en trozos con pausa entre ellos para no saturar el buffer SPP.
  Future<bool> _writeBytesChunked(List<int> bytes) async {
    if (bytes.isEmpty) return true;

    for (var offset = 0; offset < bytes.length; offset += _btChunkSize) {
      final end = (offset + _btChunkSize > bytes.length)
          ? bytes.length
          : offset + _btChunkSize;
      final chunk = bytes.sublist(offset, end);
      final ok = await PrintBluetoothThermal.writeBytes(chunk);
      if (!ok) {
        debugPrint(
          '❌ BT chunk write failed at $offset/${bytes.length} bytes',
        );
        return false;
      }
      if (end < bytes.length) {
        await Future.delayed(_btChunkDelay);
      }
    }
    return true;
  }

  Future<bool> _reconnectSelectedDevice() async {
    final device = _selectedDevice;
    if (device == null) return false;
    try {
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 600));
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: device.macAdress,
      );
      _isConnected = connected;
      debugPrint(
        connected
            ? '🔄 Reconectado a ${device.name}'
            : '❌ No se pudo reconectar a ${device.name}',
      );
      return connected;
    } catch (e) {
      debugPrint('❌ Error reconectando Bluetooth: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Send bytes to printer with chunking + retry (+ reconnect on failure).
  Future<bool> _sendToPrinterWithRetry(
    List<int> bytes,
    String jobName, {
    bool settleAfter = true,
  }) async {
    var result = false;
    var attempts = 0;
    const maxAttempts = 3;

    while (!result && attempts < maxAttempts) {
      attempts++;
      debugPrint(
        '🔄 $jobName - Print attempt $attempts of $maxAttempts '
        '(${bytes.length} bytes)',
      );

      try {
        result = await _writeBytesChunked(bytes);
        if (result) {
          debugPrint('✅ $jobName - Print successful on attempt $attempts');
        } else {
          debugPrint('❌ $jobName - Print failed on attempt $attempts');
          if (attempts < maxAttempts) {
            await _reconnectSelectedDevice();
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      } catch (printError) {
        debugPrint(
          '❌ $jobName - Print error on attempt $attempts: $printError',
        );
        if (attempts < maxAttempts) {
          await _reconnectSelectedDevice();
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    if (!result) {
      debugPrint('❌ $jobName - All print attempts failed');
      return false;
    }

    if (settleAfter) {
      await waitForPrinterBufferDrain(bytes.length);
    }
    return true;
  }

  /// Dispose resources
  void dispose() {
    disconnect();
  }
}
