import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/utils/parse_monto.dart';

/// El admin escribe montos a mano y convive con las dos convenciones:
/// es-CU (`1.500`, `1.500,50`) y en-US (`18.5`, `1,500.75`).
void main() {
  group('parseMonto — casos del plan', () {
    test('punto como millar (es-CU)', () {
      expect(parseMonto('1.500'), 1500);
    });

    test('sin separadores', () {
      expect(parseMonto('1500'), 1500);
    });

    test('coma como decimal (es-CU)', () {
      expect(parseMonto('1,50'), 1.5);
    });

    test('millar y decimal (es-CU)', () {
      expect(parseMonto('1.500,50'), 1500.5);
    });

    test('punto como decimal (en-US)', () {
      expect(parseMonto('18.5'), 18.5);
    });

    test('símbolo de moneda, millar y decimal (en-US)', () {
      expect(parseMonto(r'$1,500.75'), 1500.75);
    });

    test('vacío o basura devuelve null, nunca 0', () {
      expect(parseMonto(''), isNull);
      expect(parseMonto('   '), isNull);
      expect(parseMonto('abc'), isNull);
      expect(parseMonto(r'$'), isNull);
      expect(parseMonto('USD'), isNull);
    });
  });

  group('parseMonto — bordes', () {
    test('recorta espacios y símbolos alrededor', () {
      expect(parseMonto(' 18.5 '), 18.5);
      expect(parseMonto('CUP 1.500'), 1500);
      expect(parseMonto(r'1.500,50 $'), 1500.5);
      expect(parseMonto('CUP1.500'), 1500);
    });

    test('un solo separador con 3 dígitos detrás y parte entera = millares', () {
      expect(parseMonto('1,500'), 1500);
      expect(parseMonto('12.345'), 12345);
      expect(parseMonto('1.500.000'), 1500000);
      expect(parseMonto('1,500,000'), 1500000);
    });

    test('sin parte entera delante, el separador es decimal', () {
      expect(parseMonto('.500'), 0.5);
      expect(parseMonto(',500'), 0.5);
    });

    test('un solo separador con 1 o 2 dígitos detrás = decimal', () {
      expect(parseMonto('18.5'), 18.5);
      expect(parseMonto('18,5'), 18.5);
      expect(parseMonto('1.50'), 1.5);
      expect(parseMonto('0,99'), 0.99);
    });

    test('un separador con 4 dígitos detrás es decimal', () {
      expect(parseMonto('1.5000'), 1.5);
    });

    test('decimales de más de dos dígitos se conservan', () {
      expect(parseMonto('1.500,125'), 1500.125);
    });

    test('cero', () {
      expect(parseMonto('0'), 0);
      expect(parseMonto('0,00'), 0);
    });

    test('negativo', () {
      expect(parseMonto('-1.500,50'), -1500.5);
    });

    test('separador decimal sin decimales detrás se ignora', () {
      expect(parseMonto('1500.'), 1500);
    });
  });
}