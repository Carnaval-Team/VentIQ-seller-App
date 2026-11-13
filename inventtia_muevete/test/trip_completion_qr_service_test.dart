import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_muevete/services/trip_completion_qr_service.dart';

/// Firma un payload igual que el servicio, para poder fabricar QRs de prueba
/// (incluidos los inválidos y los viejos).
String _firmar(String secreto, Map<String, dynamic> data) {
  final json = jsonEncode(data);
  final hmac =
      Hmac(sha256, utf8.encode(secreto)).convert(utf8.encode(json)).toString();
  data['hmac'] = hmac;
  return base64Encode(utf8.encode(jsonEncode(data)));
}

Map<String, dynamic> _decodificar(String raw) =>
    jsonDecode(utf8.decode(base64Decode(raw))) as Map<String, dynamic>;

void main() {
  const secreto = 'secreto-solo-para-tests';

  setUp(() {
    TripCompletionQrService.secretoParaTests = secreto;
  });

  tearDown(() {
    TripCompletionQrService.secretoParaTests = null;
  });

  group('payload v2', () {
    test('genera y valida un QR sin precios', () {
      final raw = TripCompletionQrService.generatePayload(
        solicitudId: 12,
        viajeId: 34,
      );

      final payload = _decodificar(raw);
      // El QR v2 sólo identifica el viaje: nada de montos.
      expect(payload['v'], 2);
      expect(payload['solicitud_id'], 12);
      expect(payload['viaje_id'], 34);
      expect(payload.containsKey('precio'), isFalse);
      expect(payload.containsKey('precio_base'), isFalse);
      expect(payload['ts'], isNotNull);
      expect(payload['hmac'], isA<String>());

      final data = TripCompletionQrService.validateAndDecode(raw);
      expect(data, isNotNull);
      expect(data!['v'], 2);
      expect(data['solicitud_id'], 12);
      expect(data['viaje_id'], 34);
      expect(data.containsKey('precio'), isFalse);
    });

    test('una firma manipulada se rechaza', () {
      final raw = TripCompletionQrService.generatePayload(
        solicitudId: 12,
        viajeId: 34,
      );

      // Cambia el viaje pero deja la firma original.
      final payload = _decodificar(raw);
      payload['viaje_id'] = 35;
      final manipulado = base64Encode(utf8.encode(jsonEncode(payload)));

      expect(TripCompletionQrService.validateAndDecode(manipulado), isNull);
    });

    test('una firma con otro secreto se rechaza', () {
      final raw = _firmar('otro-secreto', {
        'v': 2,
        'solicitud_id': 1,
        'viaje_id': 2,
        'ts': DateTime.now().toUtc().toIso8601String(),
      });

      expect(TripCompletionQrService.validateAndDecode(raw), isNull);
    });

    test('un QR con más de 10 minutos se rechaza (anti-replay)', () {
      final viejo = _firmar(secreto, {
        'v': 2,
        'solicitud_id': 7,
        'viaje_id': 8,
        'ts': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 11))
            .toIso8601String(),
      });

      expect(TripCompletionQrService.validateAndDecode(viejo), isNull);
    });

    test('un QR dentro de la ventana de 10 minutos se acepta', () {
      final reciente = _firmar(secreto, {
        'v': 2,
        'solicitud_id': 7,
        'viaje_id': 8,
        'ts': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 9))
            .toIso8601String(),
      });

      final data = TripCompletionQrService.validateAndDecode(reciente);
      expect(data, isNotNull);
      expect(data!['viaje_id'], 8);
    });
  });

  group('compatibilidad v1', () {
    test('acepta el payload viejo pero ignora sus precios', () {
      final v1 = _firmar(secreto, {
        'sol_id': 99,
        'viaje_id': 100,
        'driver_id': 5,
        'user_id': 'uuid-cliente',
        'precio': 250.0,
        'precio_base': 200.0,
        'metodo': 'efectivo',
        'ts': DateTime.now().toUtc().toIso8601String(),
      });

      final data = TripCompletionQrService.validateAndDecode(v1);
      expect(data, isNotNull);
      expect(data!['solicitud_id'], 99);
      expect(data['viaje_id'], 100);
      // Los montos del QR viejo no salen del servicio.
      expect(data.containsKey('precio'), isFalse);
      expect(data.containsKey('precio_base'), isFalse);
      expect(data.containsKey('metodo'), isFalse);
    });
  });

  group('fail closed sin MUEVETE_QR_SECRET', () {
    test('generar lanza StateError y validar devuelve null', () {
      TripCompletionQrService.secretoParaTests = '';

      expect(TripCompletionQrService.configurado, isFalse);
      expect(
        () => TripCompletionQrService.generatePayload(
          solicitudId: 1,
          viajeId: 2,
        ),
        throwsStateError,
      );

      final raw = _firmar(secreto, {
        'v': 2,
        'solicitud_id': 1,
        'viaje_id': 2,
        'ts': DateTime.now().toUtc().toIso8601String(),
      });
      expect(TripCompletionQrService.validateAndDecode(raw), isNull);
    });
  });

  group('entradas basura', () {
    test('texto que no es base64/JSON devuelve null', () {
      expect(TripCompletionQrService.validateAndDecode('no-es-un-qr'), isNull);
      expect(TripCompletionQrService.validateAndDecode(''), isNull);
    });
  });
}