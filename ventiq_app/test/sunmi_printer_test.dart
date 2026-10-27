import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/services/printer_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sunmi_printer_plus');
  final calls = <String>[];
  var available = true;
  var status = 'ERR_PAPER_OUT';

  setUp(() {
    SharedPreferences.setMockInitialValues({'shift_saved_printer_type': 'sunmi'});
    calls.clear();
    available = true;
    status = 'ERR_PAPER_OUT';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'rebindPrinter') return available;
          if (call.method == 'getStatus') return status;
          throw StateError('Unexpected printing call: ${call.method}');
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<PrintResult> printOrder(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Caja'));
    })));
    final order = Order(
      id: 'test',
      fechaCreacion: DateTime(2026, 10, 27),
      items: [],
      total: 0,
      status: OrderStatus.values.first,
      mesaNumero: '1',
    );
    return PrinterManager().printInvoice(context, order);
  }

  testWidgets('restores SUNMI selection and does not send a ticket without paper', (tester) async {
    final result = await printOrder(tester);
    expect(result.success, isFalse);
    expect(result.message, contains('ERR_PAPER_OUT'));
    expect(calls, ['rebindPrinter', 'getStatus']);
    expect(PrinterManager().hasSavedPrinter, isTrue);
    expect(PrinterManager().savedPrinterDescription, 'Integrada SUNMI');
  });

  testWidgets('reports missing internal printer without attempting to print', (tester) async {
    available = false;
    final result = await printOrder(tester);
    expect(result.success, isFalse);
    expect(result.message, contains('No se encontró'));
    expect(calls, ['rebindPrinter']);
  });

  for (final detected in [true, false]) {
    testWidgets('shows SUNMI first only when detected: $detected', (tester) async {
      PrinterManager().clearSavedPrinter();
      available = detected;
      late Future<PrintResult> printing;
      final order = Order(
        id: 'test', fechaCreacion: DateTime(2026, 10, 27),
        items: [], total: 0, status: OrderStatus.values.first,
        mesaNumero: '1',
      );
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return Scaffold(body: TextButton(
          onPressed: () { printing = PrinterManager().printInvoice(context, order); },
          child: const Text('Imprimir factura'),
        ));
      })));
      await tester.tap(find.text('Imprimir factura'));
      await tester.pumpAndSettle();
      expect(calls, ['rebindPrinter']);
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('WiFi'), findsOneWidget);
      expect(find.text('Integrada SUNMI'), detected ? findsOneWidget : findsNothing);
      if (detected) {
        expect(tester.getTopLeft(find.text('Integrada SUNMI')).dy,
            lessThan(tester.getTopLeft(find.text('Bluetooth')).dy));
        expect(find.widgetWithText(ElevatedButton, 'Integrada SUNMI'), findsOneWidget);
      }
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect((await printing).success, isFalse);
    });
  }
}
