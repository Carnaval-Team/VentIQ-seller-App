import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/services/printer_manager.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';

/// La impresora «guardada para el turno» solo vale para el turno donde se
/// guardó: al abrirse otro (online u offline) hay que volver a preguntar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final prefs = UserPreferencesService();
  final printer = PrinterManager();
  const wifi = {'ip': '192.168.1.50', 'port': 9100};

  Future<void> abrirTurno(String localId) async {
    await prefs.clearOfflineTurno();
    await prefs.upsertOfflineTurno({
      'local_id': localId,
      'status': UserPreferencesService.offlineTurnoStatusOpen,
      'id_tpv': 9,
      'fecha_apertura': '2026-11-20T08:00:00.000Z',
    });
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    printer.debugForgetMemory();
  });

  test('en el mismo turno la impresora guardada se conserva', () async {
    await abrirTurno('turno-A');
    await printer.debugRememberWifiForShift(wifi);
    expect(printer.hasSavedPrinter, isTrue);

    await printer.refreshSavedPrinter();
    expect(printer.hasSavedPrinter, isTrue);

    // Tras reiniciar la app (memoria vacía, disco igual) se restaura.
    printer.debugForgetMemory();
    await printer.refreshSavedPrinter();
    expect(printer.hasSavedPrinter, isTrue);
    expect(printer.savedPrinterDescription, contains('192.168.1.50'));
  });

  test('al abrirse otro turno se descarta y se vuelve a preguntar', () async {
    await abrirTurno('turno-A');
    await printer.debugRememberWifiForShift(wifi);

    await abrirTurno('turno-B');
    await printer.refreshSavedPrinter();
    expect(printer.hasSavedPrinter, isFalse);

    // Tampoco reaparece desde disco.
    printer.debugForgetMemory();
    await printer.refreshSavedPrinter();
    expect(printer.hasSavedPrinter, isFalse);
  });

  test('tras reiniciar con otro turno abierto no se restaura', () async {
    await abrirTurno('turno-A');
    await printer.debugRememberWifiForShift(wifi);

    printer.debugForgetMemory();
    await abrirTurno('turno-B');
    await printer.refreshSavedPrinter();
    expect(printer.hasSavedPrinter, isFalse);
  });

  test('una selección guardada antes de esta versión (sin turno) se repregunta',
      () async {
    SharedPreferences.setMockInitialValues({
      'shift_saved_printer_type': 'wifi',
      'shift_saved_printer_wifi_ip': '10.0.0.9',
      'shift_saved_printer_wifi_port': 9100,
    });
    printer.debugForgetMemory();
    await abrirTurno('turno-C');
    await printer.refreshSavedPrinter();
    expect(printer.hasSavedPrinter, isFalse);
  });

  test('abrir turno (online y offline) limpia la impresora guardada', () {
    final src = File('lib/screens/apertura_screen.dart').readAsStringSync();
    expect(
      RegExp(r'PrinterManager\(\)\.clearSavedPrinter\(\);').allMatches(src).length,
      2,
    );
  });
}
