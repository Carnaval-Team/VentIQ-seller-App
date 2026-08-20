import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia local de la impresora por defecto en la app de administración.
/// Guarda una impresora Bluetooth (nombre + MAC) y/o una impresora WiFi
/// (IP + puerto) para poder reutilizarla sin volver a escanear/seleccionar.
class PrinterPreferencesService {
  static final PrinterPreferencesService _instance =
      PrinterPreferencesService._internal();
  factory PrinterPreferencesService() => _instance;
  PrinterPreferencesService._internal();

  static const String _defaultBluetoothPrinterKey = 'default_bluetooth_printer';
  static const String _defaultWiFiPrinterKey = 'default_wifi_printer';

  Future<Map<String, dynamic>?> getDefaultBluetoothPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_defaultBluetoothPrinterKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['name']?.toString().isNotEmpty != true ||
          map['mac']?.toString().isNotEmpty != true) {
        return null;
      }
      return map;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDefaultBluetoothPrinter(String name, String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _defaultBluetoothPrinterKey,
      jsonEncode({'name': name, 'mac': mac}),
    );
  }

  Future<void> clearDefaultBluetoothPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultBluetoothPrinterKey);
  }

  Future<Map<String, dynamic>?> getDefaultWiFiPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_defaultWiFiPrinterKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['ip']?.toString().isNotEmpty != true) return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDefaultWiFiPrinter(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _defaultWiFiPrinterKey,
      jsonEncode({'ip': ip, 'port': port}),
    );
  }

  Future<void> clearDefaultWiFiPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultWiFiPrinterKey);
  }

  Future<bool> hasDefaultPrinter() async {
    final bt = await getDefaultBluetoothPrinter();
    final wifi = await getDefaultWiFiPrinter();
    return bt != null || wifi != null;
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultBluetoothPrinterKey);
    await prefs.remove(_defaultWiFiPrinterKey);
  }
}
