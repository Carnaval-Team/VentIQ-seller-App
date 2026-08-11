import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/bank_sms_parser.dart';

/// Mensajes reales capturados del corto PAGOxMOVIL.
const _bandec = '''Banco Bandec Elpago externo fue
completado
Fecha: 11/8/2026
Entidad: Carnaval Alimento SURL
Nro. Transaccion: 3479195670
Monto Pagado: 840.00 CUP
Nro. Transaccion Banco:
KW601IONM4999.''';

const _metropolitano = '''Banco Metropolitano El pago
externo fue completado.
Fecha: 11/8/2026
Entidad: Carnaval Alimento SURL
Nro. Transaccion: 4954931326
Monto Pagado:1.00 CUP
Nro. Transaccion Banco:
MM604YONO3987.''';

const _popular = '''Banco Popular de Ahorro El pago
externo fue completado
Fecha: 11/8/2026
Entidad: Carnaval Alimento SURL
Nro. Transaccion: 3050499561
Monto Pagado: 280.00 CUP
Nro. Transaccion Banco:
BR6O123W6W997.''';

void main() {
  group('BankSmsParser.parse - mensajes reales', () {
    test('Bandec: monto con espacio tras los dos puntos', () {
      final p = BankSmsParser.parse(_bandec);
      expect(p, isNotNull);
      expect(p!.banco, 'Bandec');
      expect(p.monto, 840.00);
      expect(p.moneda, 'CUP');
      expect(p.entidad, 'Carnaval Alimento SURL');
      expect(p.nroTransaccion, '3479195670');
      // El punto final NO debe formar parte del identificador.
      expect(p.nroTransaccionBanco, 'KW601IONM4999');
      expect(p.fecha, DateTime(2026, 8, 11));
    });

    test('Metropolitano: monto SIN espacio tras los dos puntos', () {
      final p = BankSmsParser.parse(_metropolitano);
      expect(p, isNotNull);
      expect(p!.banco, 'Metropolitano');
      expect(p.monto, 1.00);
      expect(p.nroTransaccion, '4954931326');
      expect(p.nroTransaccionBanco, 'MM604YONO3987');
    });

    test('Popular de Ahorro: no se confunde con otro banco', () {
      final p = BankSmsParser.parse(_popular);
      expect(p, isNotNull);
      expect(p!.banco, 'Popular de Ahorro');
      expect(p.monto, 280.00);
      expect(p.nroTransaccionBanco, 'BR6O123W6W997');
    });

    test('el nro de transaccion no captura el del banco', () {
      // Regresión: sin el lookahead, `Nro. Transaccion:` haría match con la
      // etiqueta `Nro. Transaccion Banco:`.
      for (final msg in [_bandec, _metropolitano, _popular]) {
        final p = BankSmsParser.parse(msg)!;
        expect(p.nroTransaccion, isNot(equals(p.nroTransaccionBanco)));
        expect(int.tryParse(p.nroTransaccion!), isNotNull);
      }
    });

    test('conserva el mensaje crudo para auditoria', () {
      expect(BankSmsParser.parse(_bandec)!.rawMessage, _bandec);
    });
  });

  group('BankSmsParser.parse - rechazos', () {
    test('rechaza texto vacio', () {
      expect(BankSmsParser.parse(''), isNull);
      expect(BankSmsParser.parse('   '), isNull);
    });

    test('rechaza SMS no relacionado', () {
      expect(BankSmsParser.parse('Hola, recarga tu saldo ya!'), isNull);
    });

    test('rechaza pago NO completado', () {
      const rechazado = '''Banco Bandec El pago externo fue rechazado
Fecha: 11/8/2026
Monto Pagado: 840.00 CUP
Nro. Transaccion Banco: KW601IONM4999.''';
      expect(BankSmsParser.parse(rechazado), isNull);
    });

    test('rechaza mensaje sin nro de transaccion banco', () {
      const sinTx = '''Banco Bandec El pago externo fue completado
Fecha: 11/8/2026
Monto Pagado: 840.00 CUP''';
      expect(BankSmsParser.parse(sinTx), isNull);
    });

    test('rechaza mensaje sin monto', () {
      const sinMonto = '''Banco Bandec El pago externo fue completado
Fecha: 11/8/2026
Nro. Transaccion Banco: KW601IONM4999.''';
      expect(BankSmsParser.parse(sinMonto), isNull);
    });

    test('rechaza monto cero', () {
      const cero = '''Banco Bandec El pago externo fue completado
Monto Pagado: 0.00 CUP
Nro. Transaccion Banco: KW601IONM4999.''';
      expect(BankSmsParser.parse(cero), isNull);
    });
  });

  group('BankSmsParser - multipart', () {
    test('detecta fragmento incompleto como parcial', () {
      const fragmento = 'Banco Bandec Elpago externo fue completado '
          'Fecha: 11/8/2026 Entidad: Carnaval Alimento SURL Monto Pagado: 840.00';
      expect(BankSmsParser.parse(fragmento), isNull);
      expect(BankSmsParser.looksLikePartialPayment(fragmento), isTrue);
    });

    test('un mensaje completo no se marca como parcial', () {
      expect(BankSmsParser.looksLikePartialPayment(_bandec), isFalse);
    });

    test('texto ajeno no se marca como parcial', () {
      expect(BankSmsParser.looksLikePartialPayment('Saldo: 20 CUP'), isFalse);
    });

    test('reensamblado de dos fragmentos parsea correctamente', () {
      const a = 'Banco Bandec Elpago externo fue completado Fecha: 11/8/2026 '
          'Entidad: Carnaval Alimento SURL Nro. Transaccion: 3479195670';
      const b = 'Monto Pagado: 840.00 CUP Nro. Transaccion Banco: KW601IONM4999.';
      expect(BankSmsParser.parse(a), isNull);
      final p = BankSmsParser.parse('$a $b');
      expect(p, isNotNull);
      expect(p!.monto, 840.00);
      expect(p.nroTransaccionBanco, 'KW601IONM4999');
    });
  });

  group('BankSmsParser.isKnownSender', () {
    test('acepta variantes del corto', () {
      expect(BankSmsParser.isKnownSender('PAGOxMOVIL'), isTrue);
      expect(BankSmsParser.isKnownSender('PAGOXMOVIL'), isTrue);
      expect(BankSmsParser.isKnownSender('pagoxmovil'), isTrue);
      expect(BankSmsParser.isKnownSender('PAGO-MOVIL'), isTrue);
      expect(BankSmsParser.isKnownSender('PAGOMOVIL'), isTrue);
    });

    test('rechaza remitentes ajenos y vacios', () {
      expect(BankSmsParser.isKnownSender('CUBACEL'), isFalse);
      expect(BankSmsParser.isKnownSender(null), isFalse);
      expect(BankSmsParser.isKnownSender(''), isFalse);
    });
  });

  group('BankSmsParser - formatos de monto', () {
    String msg(String monto) => '''Banco Bandec El pago externo fue completado
Monto Pagado: $monto CUP
Nro. Transaccion Banco: KW601IONM4999.''';

    test('coma como separador de miles', () {
      expect(BankSmsParser.parse(msg('1,234.56'))!.monto, 1234.56);
    });

    test('coma como separador decimal', () {
      expect(BankSmsParser.parse(msg('840,00'))!.monto, 840.00);
    });

    test('punto como separador de miles', () {
      expect(BankSmsParser.parse(msg('1.234,56'))!.monto, 1234.56);
    });

    test('entero sin decimales', () {
      expect(BankSmsParser.parse(msg('840'))!.monto, 840.0);
    });
  });
}
