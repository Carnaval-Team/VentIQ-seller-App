import 'package:flutter/material.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para impresoras conectadas por WiFi/Red
class WiFiPrinterService {
  static final WiFiPrinterService _instance = WiFiPrinterService._internal();
  factory WiFiPrinterService() => _instance;
  WiFiPrinterService._internal();

  Socket? _socket;
  bool _isConnected = false;
  String? _selectedPrinterIP;
  int _selectedPrinterPort = 9100; // Puerto estándar para impresoras térmicas

  // Puertos comunes para impresoras térmicas
  static const List<int> COMMON_PRINTER_PORTS = [
    9100,  // Puerto estándar ESC/POS
    300,   // Epson WiFi
    515,   // LPD
    631,   // CUPS
    9600,  // Algunos modelos
    8080,  // Alternativo
  ];

  // Clave para SharedPreferences
  static const String _SAVED_PRINTERS_KEY = 'wifi_saved_printers';

  // Getters
  bool get isConnected => _isConnected;
  String? get selectedPrinterIP => _selectedPrinterIP;
  int get selectedPrinterPort => _selectedPrinterPort;

  /// Guardar impresora en favoritos
  Future<void> savePrinter(Map<String, dynamic> printer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPrinters = await getSavedPrinters();
      
      // Verificar si ya existe (por IP)
      final existingIndex = savedPrinters.indexWhere((p) => p['ip'] == printer['ip']);
      
      if (existingIndex >= 0) {
        // Actualizar existente
        savedPrinters[existingIndex] = printer;
        debugPrint('📝 Impresora actualizada: ${printer['ip']}');
      } else {
        // Agregar nueva
        savedPrinters.add(printer);
        debugPrint('📝 Impresora guardada: ${printer['ip']}');
      }
      
      // Guardar en SharedPreferences
      final printersJson = savedPrinters.map((p) => jsonEncode(p)).toList();
      await prefs.setStringList(_SAVED_PRINTERS_KEY, printersJson);
      
      debugPrint('✅ Total impresoras guardadas: ${savedPrinters.length}');
    } catch (e) {
      debugPrint('❌ Error guardando impresora: $e');
    }
  }

  /// Obtener impresoras guardadas
  Future<List<Map<String, dynamic>>> getSavedPrinters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final printersJson = prefs.getStringList(_SAVED_PRINTERS_KEY) ?? [];
      
      final printers = printersJson.map((json) {
        try {
          return jsonDecode(json) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('⚠️ Error decodificando impresora: $e');
          return null;
        }
      }).whereType<Map<String, dynamic>>().toList();
      
      debugPrint('📋 Impresoras guardadas cargadas: ${printers.length}');
      return printers;
    } catch (e) {
      debugPrint('❌ Error cargando impresoras guardadas: $e');
      return [];
    }
  }

  /// Eliminar impresora guardada
  Future<void> removeSavedPrinter(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPrinters = await getSavedPrinters();
      
      savedPrinters.removeWhere((p) => p['ip'] == ip);
      
      final printersJson = savedPrinters.map((p) => jsonEncode(p)).toList();
      await prefs.setStringList(_SAVED_PRINTERS_KEY, printersJson);
      
      debugPrint('🗑️ Impresora eliminada: $ip');
      debugPrint('✅ Total impresoras guardadas: ${savedPrinters.length}');
    } catch (e) {
      debugPrint('❌ Error eliminando impresora: $e');
    }
  }

  /// Descubrir impresoras WiFi - PRIMERO en redes AP, LUEGO en red local
  Future<List<Map<String, dynamic>>> discoverPrinters({
    String? subnet,
    int timeout = 500,
    int maxConcurrent = 20,
  }) async {
    List<Map<String, dynamic>> foundPrinters = [];

    // 1. PRIMERO: Buscar en redes AP comunes de impresoras (más rápido)
    debugPrint('🔍 FASE 1: Buscando en redes AP de impresoras...');
    final apPrinters = await _discoverAPPrinters(timeout);
    foundPrinters.addAll(apPrinters);
    debugPrint('📊 FASE 1 completada: ${apPrinters.length} impresoras AP encontradas');

    // 2. SEGUNDO: Buscar en la red local actual (más lento)
    debugPrint('🔍 FASE 2: Buscando en red local...');
    if (subnet == null) {
      subnet = await _detectNetworkSubnet();
      if (subnet == null) {
        subnet = '192.168.1'; // Fallback por defecto
      }
    }

    debugPrint('🔍 Buscando impresoras WiFi en la red $subnet.0/24...');
    debugPrint('⏱️ Timeout: ${timeout}ms, Concurrencia: $maxConcurrent');
    
    List<Future<void>> futures = [];

    // Escanear rango de IPs (1-254) con límite de concurrencia
    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      
      // Limitar concurrencia
      if (futures.length >= maxConcurrent) {
        await Future.wait(futures);
        futures.clear();
      }

      futures.add(
        _checkPrinterAtIP(ip, timeout).then((isAvailable) {
          if (isAvailable) {
            foundPrinters.add({
              'ip': ip,
              'port': _selectedPrinterPort,
              'name': 'Impresora $ip',
              'type': 'network',
            });
            debugPrint('✅ Impresora encontrada en red: $ip');
          }
        }).catchError((_) {
          // Ignorar errores de conexión
        }),
      );
    }

    // Esperar a que se completen las búsquedas restantes
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
    
    debugPrint('📊 Se encontraron ${foundPrinters.length} impresoras WiFi totales');
    return foundPrinters;
  }

  /// Buscar impresoras en modo AP (Access Point)
  Future<List<Map<String, dynamic>>> _discoverAPPrinters(int timeout) async {
    List<Map<String, dynamic>> apPrinters = [];
    
    // IPs comunes para impresoras en modo AP
    final commonAPIPs = [
      '192.168.0.1',    // IP por defecto de muchas impresoras
      '192.168.1.1',    // Router/Impresora AP
      '10.10.100.254',  // Epson AP
      '10.10.100.1',    // Epson AP alternativo
      '172.16.0.1',     // Algunos modelos
      '169.254.1.1',    // Link-local
    ];

    debugPrint('🔍 Probando ${commonAPIPs.length} IPs comunes de AP...');

    for (final ip in commonAPIPs) {
      try {
        if (await _checkPrinterAtIP(ip, timeout)) {
          apPrinters.add({
            'ip': ip,
            'port': _selectedPrinterPort,
            'name': 'Impresora AP $ip',
            'type': 'access_point',
          });
          debugPrint('✅ Impresora AP encontrada: $ip');
        }
      } catch (e) {
        // Continuar con siguiente IP
        continue;
      }
    }

    if (apPrinters.isNotEmpty) {
      debugPrint('📊 Se encontraron ${apPrinters.length} impresoras en modo AP');
    } else {
      debugPrint('⚠️ No se encontraron impresoras en modo AP');
    }

    return apPrinters;
  }

  /// Detectar subnet de la red actual
  Future<String?> _detectNetworkSubnet() async {
    try {
      debugPrint('🔍 Intentando detectar subnet de la red...');
      
      // Intentar conectar a un servidor público para obtener IP local
      final socket = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 2),
      ).timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('Timeout detectando red'),
      );
      
      final address = socket.address.address;
      socket.destroy();
      
      debugPrint('🌐 IP local detectada: $address');
      
      // Extraer subnet (primeros 3 octetos)
      final parts = address.split('.');
      if (parts.length == 4) {
        final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
        debugPrint('✅ Subnet detectado: $subnet');
        return subnet;
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo detectar subnet automáticamente: $e');
    }
    
    return null;
  }

  /// Verificar si hay una impresora en una IP específica (probando múltiples puertos)
  Future<bool> _checkPrinterAtIP(String ip, int timeout) async {
    // Probar puertos comunes
    for (final port in COMMON_PRINTER_PORTS) {
      try {
        final socket = await Socket.connect(
          ip,
          port,
          timeout: Duration(milliseconds: timeout),
        ).timeout(
          Duration(milliseconds: timeout),
          onTimeout: () => throw TimeoutException('Timeout conectando a $ip:$port'),
        );
        socket.destroy();
        debugPrint('✅ Impresora encontrada en $ip:$port');
        // Guardar el puerto encontrado para uso posterior
        _selectedPrinterPort = port;
        return true;
      } catch (e) {
        // Continuar con el siguiente puerto
        continue;
      }
    }
    return false;
  }

  /// Conectar a una impresora WiFi específica (con fallback a otros puertos)
  Future<bool> connectToPrinter(String ip, {int port = 9100}) async {
    // Primero intentar con el puerto especificado
    if (await _tryConnectToPort(ip, port)) {
      return true;
    }

    // Si falla, intentar con otros puertos comunes
    debugPrint('⚠️ Puerto $port no disponible, probando otros puertos...');
    for (final alternativePort in COMMON_PRINTER_PORTS) {
      if (alternativePort == port) continue; // Saltar el puerto ya probado
      
      if (await _tryConnectToPort(ip, alternativePort)) {
        debugPrint('✅ Conectado usando puerto alternativo: $alternativePort');
        return true;
      }
    }

    debugPrint('❌ No se pudo conectar a $ip en ningún puerto');
    _isConnected = false;
    return false;
  }

  /// Intentar conectar a un puerto específico
  Future<bool> _tryConnectToPort(String ip, int port) async {
    try {
      debugPrint('🔌 Intentando conectar a $ip:$port...');
      
      _socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
      );
      
      _isConnected = true;
      _selectedPrinterIP = ip;
      _selectedPrinterPort = port;
      
      debugPrint('✅ Conectado a impresora WiFi: $ip:$port');
      return true;
    } catch (e) {
      debugPrint('⚠️ No se pudo conectar a $ip:$port - $e');
      _isConnected = false;
      return false;
    }
  }

  /// Desconectar de la impresora WiFi
  Future<void> disconnect() async {
    try {
      if (_socket != null) {
        _socket!.destroy();
        _socket = null;
      }
      _isConnected = false;
      _selectedPrinterIP = null;
      debugPrint('✅ Desconectado de impresora WiFi');
    } catch (e) {
      debugPrint('❌ Error desconectando: $e');
    }
  }

  /// Imprimir operación de inventario en impresora WiFi (2 copias)
  Future<bool> printInventoryOperation(Map<String, dynamic> operation, List<Map<String, dynamic>> details) async {
    if (!_isConnected || _socket == null) {
      debugPrint('❌ Impresora WiFi no conectada');
      return false;
    }

    try {
      debugPrint('🖨️ Iniciando impresión de operación: ${operation['id']}');
      debugPrint('📦 Operación tiene ${details.length} productos');
      
      // Crear perfil ESC/POS
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);

      // ========== IMPRIMIR COPIA 1: COMPROBANTE PRINCIPAL ==========
      debugPrint('📄 Imprimiendo copia 1 (Comprobante Principal)...');
      List<int> bytes1 = [];
      bytes1 += _buildInventoryOperationReceipt(generator, operation, details, copyNumber: 1);
      bytes1 += generator.emptyLines(1);
      bytes1 += generator.cut();
      
      bool result1 = await _sendToPrinterWithRetry(bytes1, 'Comprobante Principal');
      
      if (!result1) {
        debugPrint('❌ Error imprimiendo copia 1');
        return false;
      }
      
      // Esperar entre impresiones
      debugPrint('⏳ Esperando 2 segundos antes de la segunda copia...');
      await Future.delayed(const Duration(seconds: 2));
      
      // ========== IMPRIMIR COPIA 2: COMPROBANTE DE ALMACÉN ==========
      debugPrint('🏭 Imprimiendo copia 2 (Comprobante de Almacén)...');
      List<int> bytes2 = [];
      bytes2 += _buildInventoryOperationReceipt(generator, operation, details, copyNumber: 2);
      bytes2 += generator.emptyLines(1);
      bytes2 += generator.cut();
      
      bool result2 = await _sendToPrinterWithRetry(bytes2, 'Comprobante de Almacén');
      
      if (!result2) {
        debugPrint('❌ Error imprimiendo copia 2');
        return false;
      }
      
      debugPrint('✅ Ambas copias impresas exitosamente');
      return true;
      
    } catch (e) {
      debugPrint('❌ Error imprimiendo operación: $e');
      return false;
    }
  }

  /// Enviar bytes crudos a la impresora (para uso externo)
  Future<bool> sendRawBytes(List<int> bytes) async {
    if (!_isConnected || _socket == null) {
      debugPrint('❌ Impresora WiFi no conectada');
      return false;
    }

    try {
      _socket!.add(bytes);
      await _socket!.flush();
      debugPrint('✅ Bytes enviados exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error enviando bytes: $e');
      return false;
    }
  }

  /// Enviar bytes a la impresora con reintentos
  Future<bool> _sendToPrinterWithRetry(List<int> bytes, String jobName) async {
    bool result = false;
    int attempts = 0;
    const maxAttempts = 3;
    
    while (!result && attempts < maxAttempts) {
      attempts++;
      debugPrint('🔄 $jobName - Intento $attempts de $maxAttempts');
      
      try {
        if (_socket != null) {
          _socket!.add(bytes);
          await _socket!.flush();
          result = true;
          debugPrint('✅ $jobName - Impresión exitosa en intento $attempts');
        }
      } catch (printError) {
        debugPrint('❌ $jobName - Error en intento $attempts: $printError');
        if (attempts < maxAttempts) {
          debugPrint('⏳ Esperando 2 segundos antes de reintentar...');
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
    
    if (!result) {
      debugPrint('❌ $jobName - Todos los intentos fallaron');
    }
    
    return result;
  }

  /// Construir recibo de operación de inventario
  List<int> _buildInventoryOperationReceipt(
    Generator generator, 
    Map<String, dynamic> operation, 
    List<Map<String, dynamic>> details,
    {int copyNumber = 1}
  ) {
    List<int> bytes = [];

    debugPrint('📋 Construyendo recibo de operación ${operation['id']} - Copia $copyNumber');
    
    // Encabezado
    bytes += generator.text('INVENTTIA', styles: PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('OPERACION INVENTARIO', styles: PosStyles(align: PosAlign.center, bold: true));
    
    // Indicar número de copia
    final copyLabel = copyNumber == 1 ? 'COMPROBANTE PRINCIPAL' : 'COMPROBANTE ALMACEN';
    bytes += generator.text(copyLabel, styles: PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('----------------------------', styles: PosStyles(align: PosAlign.center));

    // Información de la operación
    final operationId = operation['id']?.toString() ?? 'N/A';
    bytes += generator.text('ID: ${operationId.length > 20 ? operationId.substring(0, 20) : operationId}', 
                           styles: PosStyles(align: PosAlign.left, bold: true));
    
    final tipoOperacion = operation['tipo_operacion_nombre'] ?? operation['tipo_operacion'] ?? 'N/A';
    bytes += generator.text('Tipo: $tipoOperacion', styles: PosStyles(align: PosAlign.left));
    
    final estado = operation['estado_nombre'] ?? operation['estado'] ?? 'N/A';
    bytes += generator.text('Estado: $estado', styles: PosStyles(align: PosAlign.left));
    
    if (operation['fecha_operacion'] != null) {
      final fecha = DateTime.parse(operation['fecha_operacion'].toString());
      bytes += generator.text('Fecha: ${_formatDateForPrint(fecha)}', styles: PosStyles(align: PosAlign.left));
    }
    
    if (operation['observaciones'] != null && operation['observaciones'].toString().isNotEmpty) {
      String obs = operation['observaciones'].toString();
      if (obs.length > 28) obs = obs.substring(0, 25) + '...';
      bytes += generator.text('Obs: $obs', styles: PosStyles(align: PosAlign.left));
    }
    
    bytes += generator.text('----------------------------', styles: PosStyles(align: PosAlign.center));

    // Productos
    debugPrint('📦 Agregando ${details.length} productos');
    bytes += generator.text('PRODUCTOS:', styles: PosStyles(align: PosAlign.left, bold: true));
    
    for (int i = 0; i < details.length; i++) {
      var detail = details[i];
      final cantidad = detail['cantidad'] ?? 0;
      String productName = detail['producto_nombre'] ?? detail['producto']?['denominacion'] ?? 'Producto';
      
      debugPrint('📋 Producto ${i + 1}: ${cantidad}x $productName');
      
      // Truncar nombre si es muy largo
      if (productName.length > 24) {
        productName = productName.substring(0, 21) + '...';
      }
      
      bytes += generator.text('${cantidad}x $productName', styles: PosStyles(align: PosAlign.left));
      
      // Agregar ubicación si existe
      if (detail['ubicacion'] != null) {
        bytes += generator.text('  Ubic: ${detail['ubicacion']}', styles: PosStyles(align: PosAlign.left));
      }
    }
    
    debugPrint('✅ Todos los productos agregados');

    // Resumen
    bytes += generator.text('----------------------------', styles: PosStyles(align: PosAlign.center));
    bytes += generator.text('Total productos: ${details.length}', styles: PosStyles(align: PosAlign.left, bold: true));

    // Pie de página
    bytes += generator.text('INVENTTIA Inventario', styles: PosStyles(align: PosAlign.center));
    bytes += generator.emptyLines(1);
    
    debugPrint('📋 Recibo completado (${bytes.length} bytes)');
    return bytes;
  }

  /// Formatear fecha para impresión
  String _formatDateForPrint(DateTime date) {
    final localDate = date.toLocal();
    return "${localDate.day.toString().padLeft(2, '0')}/"
           "${localDate.month.toString().padLeft(2, '0')}/"
           "${localDate.year} "
           "${localDate.hour.toString().padLeft(2, '0')}:"
           "${localDate.minute.toString().padLeft(2, '0')}";
  }

  /// Mostrar diálogo de selección de impresora WiFi con entrada manual
  Future<Map<String, dynamic>?> showPrinterSelectionDialog(BuildContext context) async {
    // Variables fuera del builder para que persistan entre rebuilds
    bool isScanning = false;
    List<Map<String, dynamic>> printers = [];
    List<Map<String, dynamic>> savedPrinters = [];
    String? scanMessage;
    bool searchCompleted = false;
    bool showingSaved = true;
    
    // Cargar impresoras guardadas
    savedPrinters = await getSavedPrinters();
    if (savedPrinters.isNotEmpty) {
      printers = List.from(savedPrinters);
      scanMessage = '⭐ ${savedPrinters.length} impresora(s) guardada(s)';
      debugPrint('⭐ Mostrando ${savedPrinters.length} impresoras guardadas');
    }
    
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.router, color: const Color(0xFF10B981)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Conectar Impresora WiFi',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Botón de búsqueda
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isScanning ? null : () async {
                        debugPrint('🔍 Usuario presionó buscar impresoras');
                        setState(() {
                          isScanning = true;
                          scanMessage = '🔍 Buscando impresoras...';
                          printers.clear();
                          searchCompleted = false;
                          showingSaved = false;
                        });
                        
                        try {
                          debugPrint('🔍 Iniciando búsqueda de impresoras...');
                          final foundPrinters = await discoverPrinters();
                          debugPrint('📊 Búsqueda completada: ${foundPrinters.length} impresora(s) encontrada(s)');
                          
                          // Guardar impresoras encontradas
                          for (final printer in foundPrinters) {
                            await savePrinter(printer);
                          }
                          
                          setState(() {
                            printers = foundPrinters;
                            searchCompleted = true;
                            
                            debugPrint('🔄 setState: Actualizando UI con ${foundPrinters.length} impresoras');
                            debugPrint('📋 Impresoras: ${foundPrinters.map((p) => '${p['ip']}:${p['port']}').join(', ')}');
                            
                            if (printers.isEmpty) {
                              scanMessage = '❌ No se encontraron impresoras';
                              debugPrint('❌ Lista vacía');
                            } else {
                              final networkCount = printers.where((p) => p['type'] == 'network').length;
                              final apCount = printers.where((p) => p['type'] == 'access_point').length;
                              scanMessage = '✅ Se encontraron ${printers.length} impresora(s) (Red: $networkCount, AP: $apCount)';
                              debugPrint('✅ setState ejecutado: ${printers.length} impresoras en lista');
                              debugPrint('✅ Tipos: Red=$networkCount, AP=$apCount');
                            }
                            isScanning = false;
                          });
                        } catch (e) {
                          debugPrint('❌ Error en búsqueda: $e');
                          setState(() {
                            scanMessage = '❌ Error: $e';
                            isScanning = false;
                            searchCompleted = true;
                          });
                        }
                      },
                      icon: isScanning ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      ) : Icon(Icons.search),
                      label: Text(isScanning ? 'Buscando...' : 'Buscar Impresoras'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Listado de impresoras encontradas
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Estado de búsqueda
                          if (isScanning) ...[
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                children: [
                                  CircularProgressIndicator(
                                    color: const Color(0xFF10B981),
                                    strokeWidth: 2,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Buscando impresoras en la red...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[800],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 12),
                          ],
                          
                          // Mensaje de resultado
                          if (scanMessage != null && !isScanning) ...[
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: scanMessage!.startsWith('✅') 
                                  ? Colors.green.shade50 
                                  : scanMessage!.startsWith('❌')
                                    ? Colors.red.shade50
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: scanMessage!.startsWith('✅') 
                                    ? Colors.green.shade200 
                                    : scanMessage!.startsWith('❌')
                                      ? Colors.red.shade200
                                      : Colors.blue.shade200,
                                ),
                              ),
                              child: Text(
                                scanMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[800],
                                  height: 1.4,
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                          ],
                          
                          // Lista de impresoras
                          if (printers.isNotEmpty && !isScanning) ...[
                            ...printers.map((printer) {
                              final isAP = printer['type'] == 'access_point';
                              final isSaved = showingSaved || savedPrinters.any((p) => p['ip'] == printer['ip']);
                              debugPrint('🖨️ Renderizando impresora: ${printer['ip']}:${printer['port']} (${printer['type']})');
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: InkWell(
                                  onTap: () => Navigator.pop(context, printer),
                                  child: Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isAP ? Colors.orange.shade50 : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isAP ? Colors.orange.shade300 : Colors.green.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isAP ? Icons.router : Icons.print,
                                          size: 20,
                                          color: isAP ? Colors.orange : const Color(0xFF10B981),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      printer['name'] ?? 'Impresora',
                                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                                    ),
                                                  ),
                                                  if (isSaved)
                                                    Container(
                                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.yellow.shade100,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.star, size: 10, color: Colors.orange.shade700),
                                                          SizedBox(width: 2),
                                                          Text(
                                                            'Guardada',
                                                            style: TextStyle(
                                                              fontSize: 9,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.orange.shade700,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  SizedBox(width: 4),
                                                  if (isAP)
                                                    Container(
                                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange.shade200,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        'AP',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.orange.shade900,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                '${printer['ip']}:${printer['port'] ?? 9100}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isSaved && showingSaved)
                                          IconButton(
                                            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                                            onPressed: () async {
                                              await removeSavedPrinter(printer['ip']);
                                              final updated = await getSavedPrinters();
                                              setState(() {
                                                savedPrinters = updated;
                                                printers = List.from(updated);
                                                if (printers.isEmpty) {
                                                  scanMessage = null;
                                                } else {
                                                  scanMessage = '⭐ ${printers.length} impresora(s) guardada(s)';
                                                }
                                              });
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints: BoxConstraints(),
                                          )
                                        else
                                          Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                          
                          if (printers.isEmpty && scanMessage != null && !isScanning)
                            Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 32),
                                child: Column(
                                  children: [
                                    Icon(Icons.print_disabled, size: 48, color: Colors.grey[400]),
                                    SizedBox(height: 16),
                                    Text(
                                      'No se encontraron impresoras',
                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancelar'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dispose resources
  void dispose() {
    disconnect();
  }
}
