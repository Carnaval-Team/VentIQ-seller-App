import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/utils/whatsapp_helper.dart';

void main() {
  group('WhatsAppHelper.normalizePhone', () {
    test('antepone el 53 a los móviles cubanos de 8 dígitos', () {
      expect(WhatsAppHelper.normalizePhone('54905391'), '5354905391');
      expect(WhatsAppHelper.normalizePhone('51783599'), '5351783599');
    });

    test('un 53 inicial en 8 dígitos es parte del número, no el prefijo', () {
      // Los móviles cubanos empiezan por 5, así que 53006050 es local.
      expect(WhatsAppHelper.normalizePhone('53006050'), '5353006050');
    });

    test('respeta los números que ya traen código de país', () {
      expect(WhatsAppHelper.normalizePhone('5353277353'), '5353277353');
      expect(WhatsAppHelper.normalizePhone('+5350005083'), '5350005083');
      expect(WhatsAppHelper.normalizePhone('+13052978955'), '13052978955');
    });

    test('trata el 00 como prefijo internacional', () {
      expect(WhatsAppHelper.normalizePhone('00491742055324'), '491742055324');
    });

    test('limpia separadores', () {
      expect(WhatsAppHelper.normalizePhone(' +53 5490-5391 '), '5354905391');
      expect(WhatsAppHelper.normalizePhone('(53) 5490 5391'), '5354905391');
    });

    test('acepta teléfonos guardados como número', () {
      expect(WhatsAppHelper.normalizePhone(54905391), '5354905391');
      expect(WhatsAppHelper.normalizePhone(54905391.0), '5354905391');
    });

    test('rechaza vacíos y nulos', () {
      expect(WhatsAppHelper.normalizePhone(null), isNull);
      expect(WhatsAppHelper.normalizePhone(''), isNull);
      expect(WhatsAppHelper.normalizePhone('   '), isNull);
      expect(WhatsAppHelper.normalizePhone('-'), isNull);
    });

    test('rechaza el dato de relleno que hay en la BD', () {
      expect(WhatsAppHelper.normalizePhone('5555555'), isNull);
      expect(WhatsAppHelper.normalizePhone('555555'), isNull);
      expect(WhatsAppHelper.normalizePhone('0'), isNull);
      expect(WhatsAppHelper.normalizePhone('13123'), isNull);
      expect(WhatsAppHelper.normalizePhone('55555555'), isNull);
    });

    test('rechaza números fuera del rango E.164', () {
      expect(WhatsAppHelper.normalizePhone('+1234567890123456'), isNull);
    });

    test('isContactable refleja normalizePhone', () {
      expect(WhatsAppHelper.isContactable('54905391'), isTrue);
      expect(WhatsAppHelper.isContactable('5555555'), isFalse);
    });
  });
}
