import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/models/bank_sms_payment.dart';
import 'package:ventiq_app/services/bank_sms_service.dart';

BankSmsPayment payment({
  required String tx,
  required double monto,
  Duration ago = Duration.zero,
}) {
  return BankSmsPayment(
    banco: 'Bandec',
    nroTransaccionBanco: tx,
    monto: monto,
    rawMessage: 'raw $tx',
    receivedAt: DateTime.now().subtract(ago),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('buffer de pagos pendientes', () {
    test('guarda y recupera un pago', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(
        payment(tx: 'KW601IONM4999', monto: 840.0),
      );

      final pending = await svc.getPendingPayments();
      expect(pending, hasLength(1));
      expect(pending.first.nroTransaccionBanco, 'KW601IONM4999');
      expect(pending.first.monto, 840.0);
    });

    test('deduplica por nro de transaccion banco', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(
        payment(tx: 'KW601IONM4999', monto: 840.0),
      );
      await BankSmsService.appendPendingPayment(
        payment(tx: 'KW601IONM4999', monto: 840.0),
      );

      expect(await svc.getPendingPayments(), hasLength(1));
    });

    test('acumula pagos distintos', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(payment(tx: 'AAA11111', monto: 1));
      await BankSmsService.appendPendingPayment(payment(tx: 'BBB22222', monto: 2));

      expect(await svc.getPendingPayments(), hasLength(2));
    });

    test('descarta pagos mas viejos que maxPaymentAge', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(
        payment(tx: 'VIEJO111', monto: 500, ago: const Duration(hours: 2)),
      );
      await BankSmsService.appendPendingPayment(
        payment(tx: 'NUEVO111', monto: 600),
      );

      final pending = await svc.getPendingPayments();
      expect(pending, hasLength(1));
      expect(pending.first.nroTransaccionBanco, 'NUEVO111');
    });

    test('ordena del mas reciente al mas antiguo', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(
        payment(tx: 'ANTES111', monto: 1, ago: const Duration(minutes: 10)),
      );
      await BankSmsService.appendPendingPayment(
        payment(tx: 'DESPUES1', monto: 2, ago: const Duration(minutes: 1)),
      );

      final pending = await svc.getPendingPayments();
      expect(pending.first.nroTransaccionBanco, 'DESPUES1');
    });

    test('remueve un pago conciliado', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(payment(tx: 'AAA11111', monto: 1));
      await BankSmsService.appendPendingPayment(payment(tx: 'BBB22222', monto: 2));

      await svc.removePendingPayment('AAA11111');

      final pending = await svc.getPendingPayments();
      expect(pending, hasLength(1));
      expect(pending.first.nroTransaccionBanco, 'BBB22222');
    });

    test('limpia todo el buffer', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(payment(tx: 'AAA11111', monto: 1));
      await svc.clearPendingPayments();
      expect(await svc.getPendingPayments(), isEmpty);
    });

    test('tolera entradas corruptas sin romper', () async {
      SharedPreferences.setMockInitialValues({
        'bank_sms_pending_payments': ['no-es-json', '{"malformado":'],
      });
      expect(await BankSmsService().getPendingPayments(), isEmpty);
    });
  });

  group('findMatchingPayment', () {
    test('casa por monto exacto', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(
        payment(tx: 'KW601IONM4999', monto: 840.0),
      );

      final match = await svc.findMatchingPayment(840.0);
      expect(match, isNotNull);
      expect(match!.nroTransaccionBanco, 'KW601IONM4999');
    });

    test('casa dentro de la tolerancia', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(payment(tx: 'AAA11111', monto: 840.0));

      expect(await svc.findMatchingPayment(840.005), isNotNull);
    });

    test('no casa fuera de la tolerancia', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(payment(tx: 'AAA11111', monto: 840.0));

      expect(await svc.findMatchingPayment(841.0), isNull);
      expect(await svc.findMatchingPayment(700.0), isNull);
    });

    test('sin pagos en buffer devuelve null', () async {
      expect(await BankSmsService().findMatchingPayment(840.0), isNull);
    });

    test('ante dos montos iguales elige el mas reciente', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(
        payment(tx: 'VIEJO222', monto: 840.0, ago: const Duration(minutes: 8)),
      );
      await BankSmsService.appendPendingPayment(
        payment(tx: 'NUEVO222', monto: 840.0, ago: const Duration(minutes: 1)),
      );

      final match = await svc.findMatchingPayment(840.0);
      expect(match!.nroTransaccionBanco, 'NUEVO222');
    });

    test('elige el monto correcto entre varios pagos', () async {
      final svc = BankSmsService();
      await BankSmsService.appendPendingPayment(payment(tx: 'AAA11111', monto: 280.0));
      await BankSmsService.appendPendingPayment(payment(tx: 'BBB22222', monto: 840.0));

      final match = await svc.findMatchingPayment(280.0);
      expect(match!.nroTransaccionBanco, 'AAA11111');
    });
  });

  group('serializacion', () {
    test('roundtrip json conserva los campos', () {
      final original = BankSmsPayment(
        banco: 'Metropolitano',
        fecha: DateTime(2026, 8, 11),
        entidad: 'Carnaval Alimento SURL',
        nroTransaccion: '4954931326',
        nroTransaccionBanco: 'MM604YONO3987',
        monto: 1.0,
        rawMessage: 'cuerpo original',
        receivedAt: DateTime(2026, 8, 11, 14, 30),
      );

      final copy = BankSmsPayment.fromJson(original.toJson());

      expect(copy.banco, original.banco);
      expect(copy.fecha, original.fecha);
      expect(copy.entidad, original.entidad);
      expect(copy.nroTransaccion, original.nroTransaccion);
      expect(copy.nroTransaccionBanco, original.nroTransaccionBanco);
      expect(copy.monto, original.monto);
      expect(copy.rawMessage, original.rawMessage);
      expect(copy.receivedAt, original.receivedAt);
    });

    test('igualdad por nro de transaccion banco', () {
      expect(
        payment(tx: 'SAME1234', monto: 1),
        equals(payment(tx: 'SAME1234', monto: 999)),
      );
    });
  });

  group('plataforma', () {
    test('isSupported es false en el entorno de test (no Android)', () {
      // Los tests corren en Dart VM de escritorio: sin soporte de SMS.
      expect(BankSmsService.isSupported, isFalse);
    });

    test('startListening degrada a false sin soporte', () async {
      expect(await BankSmsService().startListening(), isFalse);
    });

    test('reconcileFromInbox devuelve 0 sin soporte', () async {
      expect(await BankSmsService().reconcileFromInbox(), 0);
    });

    test('stopListening es seguro sin haber arrancado', () {
      expect(() => BankSmsService().stopListening(), returnsNormally);
    });
  });
}
