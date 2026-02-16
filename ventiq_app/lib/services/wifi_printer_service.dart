import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order.dart';
import '../services/currency_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/price_utils.dart';

class _StorePrintInfo {
  final String name;
  final Uint8List? logoBytes;

  const _StorePrintInfo({required this.name, this.logoBytes});
}

/// Servicio para impresoras conectadas por WiFi/Red
class WiFiPrinterService {
  static final WiFiPrinterService _instance = WiFiPrinterService._internal();
  factory WiFiPrinterService() => _instance;
  WiFiPrinterService._internal();

  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  _StorePrintInfo? _storePrintInfoCache;
  Future<_StorePrintInfo>? _storePrintInfoFuture;

  Socket? _socket;
  bool _isConnected = false;
  String? _selectedPrinterIP;
  int _selectedPrinterPort = 9100; // Puerto estándar para impresoras térmicas

  // Puertos comunes para impresoras térmicas
  static const List<int> COMMON_PRINTER_PORTS = [
    9100, // Puerto estándar ESC/POS
    300, // Epson WiFi
    515, // LPD
    631, // CUPS
    9600, // Algunos modelos
    8080, // Alternativo
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
      final existingIndex = savedPrinters.indexWhere(
        (p) => p['ip'] == printer['ip'],
      );

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

      final printers =
          printersJson
              .map((json) {
                try {
                  return jsonDecode(json) as Map<String, dynamic>;
                } catch (e) {
                  debugPrint('⚠️ Error decodificando impresora: $e');
                  return null;
                }
              })
              .whereType<Map<String, dynamic>>()
              .toList();

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
    debugPrint(
      '📊 FASE 1 completada: ${apPrinters.length} impresoras AP encontradas',
    );

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
        _checkPrinterAtIP(ip, timeout)
            .then((isAvailable) {
              if (isAvailable) {
                foundPrinters.add({
                  'ip': ip,
                  'port': _selectedPrinterPort,
                  'name': 'Impresora $ip',
                  'type': 'network',
                });
                debugPrint('✅ Impresora encontrada en red: $ip');
              }
            })
            .catchError((_) {
              // Ignorar errores de conexión
            }),
      );
    }

    // Esperar a que se completen las búsquedas restantes
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    debugPrint(
      '📊 Se encontraron ${foundPrinters.length} impresoras WiFi totales',
    );
    return foundPrinters;
  }

  /// Buscar impresoras en modo AP (Access Point)
  Future<List<Map<String, dynamic>>> _discoverAPPrinters(int timeout) async {
    List<Map<String, dynamic>> apPrinters = [];

    // IPs comunes para impresoras en modo AP
    final commonAPIPs = [
      '192.168.0.1', // IP por defecto de muchas impresoras
      '192.168.1.1', // Router/Impresora AP
      '10.10.100.254', // Epson AP
      '10.10.100.1', // Epson AP alternativo
      '172.16.0.1', // Algunos modelos
      '169.254.1.1', // Link-local
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
      debugPrint(
        '📊 Se encontraron ${apPrinters.length} impresoras en modo AP',
      );
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
          onTimeout:
              () => throw TimeoutException('Timeout conectando a $ip:$port'),
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

  /// Imprimir múltiples recibos de cliente en una sola impresión
  Future<bool> printCustomerReceiptsBatch(List<Order> orders) async {
    if (!_isConnected || _socket == null) {
      debugPrint('❌ Impresora WiFi no conectada');
      return false;
    }
    if (orders.isEmpty) {
      debugPrint('⚠️ No hay órdenes para impresión por lote');
      return false;
    }

    try {
      debugPrint('🖨️ Iniciando impresión por lote (${orders.length} órdenes)');
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

      debugPrint('📤 Enviando recibos por lote (${bytes.length} bytes)...');
      return await _sendToPrinterWithRetry(bytes, 'Recibos de Cliente (Lote)');
    } catch (e) {
      debugPrint('❌ Error imprimiendo recibos por lote: $e');
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

  /// Imprimir factura en impresora WiFi
  Future<bool> printInvoice(Order order) async {
    if (!_isConnected || _socket == null) {
      debugPrint('❌ Impresora WiFi no conectada');
      return false;
    }

    try {
      debugPrint('🖨️ Iniciando impresión en WiFi para orden: ${order.id}');
      debugPrint('📦 Orden tiene ${order.items.length} items');

      // Crear perfil ESC/POS
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      final storeInfo = await _getStorePrintInfo();

      // ========== IMPRIMIR RECIBO DEL CLIENTE ==========
      debugPrint('📄 Imprimiendo recibo del cliente...');
      bool customerResult = await _printCustomerReceipt(
        generator,
        order,
        storeInfo,
      );

      if (!customerResult) {
        debugPrint('❌ Error imprimiendo recibo del cliente');
        return false;
      }

      // Esperar entre impresiones
      debugPrint('⏳ Esperando 3 segundos antes de guía de almacén...');
      await Future.delayed(const Duration(seconds: 3));

      // ========== IMPRIMIR GUÍA DE ALMACÉN ==========
      debugPrint('🏭 Imprimiendo guía de almacén...');
      bool warehouseResult = await _printWarehouseSlip(
        generator,
        order,
        storeInfo,
      );

      if (!warehouseResult) {
        debugPrint('❌ Error imprimiendo guía de almacén');
        return false;
      }

      debugPrint('✅ Ambos recibos impresos exitosamente');

      // Esperar entre impresiones
      debugPrint('⏳ Esperando 3 segundos antes de recibo vendedor...');
      await Future.delayed(const Duration(seconds: 3));

      // ========== IMPRIMIR SELLER RECEIPT ==========
      debugPrint('👤 Imprimiendo recibo vendedor...');
      bool sellerResult = await _printCustomerReceipt(
        generator,
        order,
        storeInfo,
        title: 'RECIBO VENDEDOR',
      );

      if (!sellerResult) {
        debugPrint('❌ Error imprimiendo recibo de vendedor');
        // No retornamos false porque ya se imprimieron los principales
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error imprimiendo factura: $e');
      return false;
    }
  }

  /// Imprimir recibo del cliente
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

      debugPrint('📤 Enviando $title (${bytes.length} bytes)...');

      return await _sendToPrinterWithRetry(bytes, title);
    } catch (e) {
      debugPrint('❌ Error creando $title: $e');
      return false;
    }
  }

  /// Agregar separador punteado entre recibos
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

  /// Imprimir guía de almacén
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

      debugPrint('📤 Enviando guía de almacén (${bytes.length} bytes)...');

      return await _sendToPrinterWithRetry(bytes, 'Guía de Almacén');
    } catch (e) {
      debugPrint('❌ Error creando guía de almacén: $e');
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
        '⚠️ No se pudo cargar datos de tienda para impresión WiFi: $e',
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
            ? '${url.replaceFirst(objectPrefix, renderPrefix)}?width=500&height=600'
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
    // ESC/POS raster printing is typically more reliable when width is a
    // multiple of 8 pixels (byte-aligned).
    final normalizedWidth = (image.width ~/ 8) * 8;
    final byteAligned =
        (normalizedWidth > 0 && normalizedWidth != image.width)
            ? img.copyResize(image, width: normalizedWidth)
            : image;

    // Some printers behave better with grayscale images.
    return img.grayscale(byteAligned);
  }

  List<int> _escPosInit() {
    // ESC @ (Initialize printer)
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

        // Some printers leave the data stream in a state where the next bytes
        // (text) get printed as garbage. Re-initialize before continuing.
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

  /// Agregar recibo del cliente
  List<int> _addCustomerReceipt(
    Generator generator,
    Order order,
    _StorePrintInfo storeInfo, {
    bool includeHeader = true,
    double? usdRate,
    String title = 'FACTURA',
  }) {
    List<int> bytes = [];

    // Encabezado compacto
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

    // Información de la orden compacta
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

    // Productos compactos
    double subtotal = 0;
    for (var item in order.items) {
      double itemTotal = item.cantidad * item.precioUnitario;
      subtotal += itemTotal;

      // Nombre del producto en una línea
      String prodName = item.producto.denominacion;
      if (prodName.length > 28) prodName = prodName.substring(0, 25) + '...';
      bytes += generator.text(
        '${PriceUtils.formatQuantity(item.cantidad)}x $prodName',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        '  \$${item.precioUnitario.toStringAsFixed(0)} = \$${itemTotal.toStringAsFixed(0)}',
        styles: PosStyles(align: PosAlign.right),
      );
    }

    // Totales compactos
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    // Mostrar descuento si existe
    if (order.descuento != null) {
      final double montoReal = ((order.descuento!['monto_real'] ?? order.total) as num).toDouble();
      final double montoDescontado = ((order.descuento!['monto_descontado'] ?? 0) as num).toDouble();
      if (montoDescontado > 0) {
        bytes += generator.text(
          'Subtotal: \$${montoReal.toStringAsFixed(0)}',
          styles: PosStyles(align: PosAlign.right),
        );
        bytes += generator.text(
          'Descuento: -\$${montoDescontado.toStringAsFixed(0)}',
          styles: PosStyles(align: PosAlign.right),
        );
      }
    }

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

    // Pie de página compacto
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

  /// Agregar guía de almacén
  List<int> _addWarehousePickingSlip(
    Generator generator,
    Order order,
    _StorePrintInfo storeInfo, {
    double? usdRate,
  }) {
    List<int> bytes = [];

    debugPrint('🏭 Creando guía de almacén para orden ${order.id}');

    // Encabezado compacto
    bytes += _addStoreHeader(generator, storeInfo);
    bytes += generator.text(
      'GUIA ALMACEN',
      styles: PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    debugPrint('📋 Encabezado de almacén agregado');

    // Información de la orden compacta
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

    // Productos - mostrar nombre completo
    debugPrint(
      '📦 Agregando ${order.items.length} productos a la guía de almacén',
    );
    for (int i = 0; i < order.items.length; i++) {
      var item = order.items[i];
      String ubicacion = item.ubicacionAlmacen ?? 'N/A';
      String productName = item.producto.denominacion;

      debugPrint(
        '📋 Producto ${i + 1}: ${PriceUtils.formatQuantity(item.cantidad)}x $productName @ $ubicacion',
      );

      // Mostrar cantidad y nombre completo del producto
      bytes += generator.text(
        '${PriceUtils.formatQuantity(item.cantidad)}x $productName',
        styles: PosStyles(align: PosAlign.left, bold: true),
      );
      bytes += generator.text(
        '   Ubic: $ubicacion',
        styles: PosStyles(align: PosAlign.left),
      );
      // Agregar linea de separacion entre productos
      if (i < order.items.length - 1) {
        bytes += generator.text(
          '- - - - - - - - - - - - - -',
          styles: PosStyles(align: PosAlign.center),
        );
      }
    }
    debugPrint('✅ Todos los productos de almacén agregados');

    // Resumen compacto
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'TOT: ${order.distinctItemCount} prod - \$${order.total.toStringAsFixed(0)}',
      styles: PosStyles(align: PosAlign.left, bold: true),
    );
    if (usdRate != null && usdRate > 0) {
      final usdTotal = order.total / usdRate;
      bytes += generator.text(
        'USD (${usdRate.toStringAsFixed(0)}): \$${usdTotal.toStringAsFixed(2)}',
        styles: PosStyles(align: PosAlign.left, bold: true),
      );
    }

    // Pie de página compacto
    bytes += generator.text(
      '${storeInfo.name} Almacen',
      styles: const PosStyles(align: PosAlign.center),
    );

    debugPrint('🏭 Guía de almacén completada (${bytes.length} bytes)');
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
  Future<Map<String, dynamic>?> showPrinterSelectionDialog(
    BuildContext context,
  ) async {
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
      builder:
          (context) => StatefulBuilder(
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
                          onPressed:
                              isScanning
                                  ? null
                                  : () async {
                                    debugPrint(
                                      '🔍 Usuario presionó buscar impresoras',
                                    );
                                    setState(() {
                                      isScanning = true;
                                      scanMessage = '🔍 Buscando impresoras...';
                                      printers.clear();
                                      searchCompleted = false;
                                      showingSaved = false;
                                    });

                                    try {
                                      debugPrint(
                                        '🔍 Iniciando búsqueda de impresoras...',
                                      );
                                      final foundPrinters =
                                          await discoverPrinters();
                                      debugPrint(
                                        '📊 Búsqueda completada: ${foundPrinters.length} impresora(s) encontrada(s)',
                                      );

                                      // Guardar impresoras encontradas
                                      for (final printer in foundPrinters) {
                                        await savePrinter(printer);
                                      }

                                      setState(() {
                                        printers = foundPrinters;
                                        searchCompleted = true;

                                        debugPrint(
                                          '🔄 setState: Actualizando UI con ${foundPrinters.length} impresoras',
                                        );
                                        debugPrint(
                                          '📋 Impresoras: ${foundPrinters.map((p) => '${p['ip']}:${p['port']}').join(', ')}',
                                        );

                                        if (printers.isEmpty) {
                                          scanMessage =
                                              '❌ No se encontraron impresoras';
                                          debugPrint('❌ Lista vacía');
                                        } else {
                                          final networkCount =
                                              printers
                                                  .where(
                                                    (p) =>
                                                        p['type'] == 'network',
                                                  )
                                                  .length;
                                          final apCount =
                                              printers
                                                  .where(
                                                    (p) =>
                                                        p['type'] ==
                                                        'access_point',
                                                  )
                                                  .length;
                                          scanMessage =
                                              '✅ Se encontraron ${printers.length} impresora(s) (Red: $networkCount, AP: $apCount)';
                                          debugPrint(
                                            '✅ setState ejecutado: ${printers.length} impresoras en lista',
                                          );
                                          debugPrint(
                                            '✅ Tipos: Red=$networkCount, AP=$apCount',
                                          );
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
                          icon:
                              isScanning
                                  ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : Icon(Icons.search),
                          label: Text(
                            isScanning ? 'Buscando...' : 'Buscar Impresoras',
                          ),
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
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                    ),
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
                                    color:
                                        scanMessage!.startsWith('✅')
                                            ? Colors.green.shade50
                                            : scanMessage!.startsWith('❌')
                                            ? Colors.red.shade50
                                            : Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color:
                                          scanMessage!.startsWith('✅')
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
                                  final isAP =
                                      printer['type'] == 'access_point';
                                  final isSaved =
                                      showingSaved ||
                                      savedPrinters.any(
                                        (p) => p['ip'] == printer['ip'],
                                      );
                                  debugPrint(
                                    '🖨️ Renderizando impresora: ${printer['ip']}:${printer['port']} (${printer['type']})',
                                  );
                                  return Padding(
                                    padding: EdgeInsets.symmetric(vertical: 6),
                                    child: InkWell(
                                      onTap:
                                          () => Navigator.pop(context, printer),
                                      child: Container(
                                        padding: EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color:
                                              isAP
                                                  ? Colors.orange.shade50
                                                  : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color:
                                                isAP
                                                    ? Colors.orange.shade300
                                                    : Colors.green.shade300,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isAP ? Icons.router : Icons.print,
                                              size: 20,
                                              color:
                                                  isAP
                                                      ? Colors.orange
                                                      : const Color(0xFF10B981),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          printer['name'] ??
                                                              'Impresora',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                      if (isSaved)
                                                        Container(
                                                          padding:
                                                              EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors
                                                                    .yellow
                                                                    .shade100,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                Icons.star,
                                                                size: 10,
                                                                color:
                                                                    Colors
                                                                        .orange
                                                                        .shade700,
                                                              ),
                                                              SizedBox(
                                                                width: 2,
                                                              ),
                                                              Text(
                                                                'Guardada',
                                                                style: TextStyle(
                                                                  fontSize: 9,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color:
                                                                      Colors
                                                                          .orange
                                                                          .shade700,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      SizedBox(width: 4),
                                                      if (isAP)
                                                        Container(
                                                          padding:
                                                              EdgeInsets.symmetric(
                                                                horizontal: 8,
                                                                vertical: 3,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors
                                                                    .orange
                                                                    .shade200,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            'AP',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  Colors
                                                                      .orange
                                                                      .shade900,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    '${printer['ip']}:${printer['port'] ?? 9100}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isSaved && showingSaved)
                                              IconButton(
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                  color: Colors.red.shade400,
                                                ),
                                                onPressed: () async {
                                                  await removeSavedPrinter(
                                                    printer['ip'],
                                                  );
                                                  final updated =
                                                      await getSavedPrinters();
                                                  setState(() {
                                                    savedPrinters = updated;
                                                    printers = List.from(
                                                      updated,
                                                    );
                                                    if (printers.isEmpty) {
                                                      scanMessage = null;
                                                    } else {
                                                      scanMessage =
                                                          '⭐ ${printers.length} impresora(s) guardada(s)';
                                                    }
                                                  });
                                                },
                                                padding: EdgeInsets.zero,
                                                constraints: BoxConstraints(),
                                              )
                                            else
                                              Icon(
                                                Icons.arrow_forward_ios,
                                                size: 14,
                                                color: Colors.grey[400],
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],

                              if (printers.isEmpty &&
                                  scanMessage != null &&
                                  !isScanning)
                                Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 32),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.print_disabled,
                                          size: 48,
                                          color: Colors.grey[400],
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No se encontraron impresoras',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
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

  /// Mostrar diálogo de confirmación de impresión
  Future<bool> showPrintConfirmationDialog(
    BuildContext context,
    Order order,
  ) async {
    final result =
        await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.print, color: const Color(0xFF4A90E2)),
                    SizedBox(width: 8),
                    Text(
                      'Imprimir Factura',
                      style: Theme.of(context).textTheme.titleLarge,
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
                          SizedBox(height: 8),
                          Text(
                            'Impresora: $_selectedPrinterIP:$_selectedPrinterPort',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('No imprimir'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: Icon(Icons.print),
                    label: Text('Imprimir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90E2),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
        ) ??
        false;

    return result;
  }

  /// Dispose resources
  void dispose() {
    disconnect();
  }
}
