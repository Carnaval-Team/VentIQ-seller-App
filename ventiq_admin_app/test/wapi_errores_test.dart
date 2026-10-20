import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/wapi_envio_log.dart';
import 'package:ventiq_admin_app/models/wapi_envio_tanda.dart';
import 'package:ventiq_admin_app/utils/wapi_errores.dart';

/// Pruebas del traductor de errores: es la pieza que decide QUÉ lee el cliente
/// final y si se le ofrece reintentar o reconectar. Si esto se rompe, la UI
/// vuelve a mostrar códigos crudos en inglés.
void main() {
  group('diagnosticarError', () {
    test('409 "Session is not connected" → problema de sesión', () {
      final d = diagnosticarError(
        codigo: 'HTTP_409',
        mensaje: 'Session is not connected. The WhatsApp client is not ready. '
            '(tras 3 intento(s))',
      );
      expect(d.tipo, WapiDiagTipo.sesion);
      expect(d.titulo, 'El bot se desconectó');
      expect(d.requiereReconectar, isTrue);
      expect(d.reintentable, isTrue);
      expect(d.queHacer, contains('Reconecta'));
      // El sufijo del backend no debe colarse en el detalle técnico.
      expect(d.detalle, isNot(contains('tras 3')));
    });

    test('400 "is not active" → motor apagado, también es la sesión', () {
      final d = diagnosticarError(
        codigo: 'HTTP_400',
        mensaje: "Session 'abc' is not active. Start the session first.",
      );
      expect(d.tipo, WapiDiagTipo.sesion);
      expect(d.requiereReconectar, isTrue);
    });

    test('500 → fallo transitorio del servidor del bot', () {
      final d = diagnosticarError(
        codigo: 'HTTP_500',
        mensaje: 'Internal server error',
      );
      expect(d.tipo, WapiDiagTipo.transitorio);
      expect(d.requiereReconectar, isFalse);
      expect(d.reintentable, isTrue);
      expect(d.titulo, 'El servidor del bot falló');
    });

    test('PRODUCT_TIMEOUT se presenta como corte por tiempo, no como fallo', () {
      final d = diagnosticarError(codigo: 'PRODUCT_TIMEOUT');
      expect(d.tipo, WapiDiagTipo.informativo);
      expect(d.esInformativo, isTrue);
      expect(d.titulo, contains('no fue un error'));
    });

    test('TIMEOUT avisa de que el mensaje pudo salir y no se duplica', () {
      final d = diagnosticarError(codigo: 'TIMEOUT');
      expect(d.tipo, WapiDiagTipo.transitorio);
      expect(d.explicacion, contains('no se duplica'));
    });

    test('429 / SEND_PACING_LIMITED → WhatsApp pidió esperar', () {
      for (final code in ['HTTP_429', 'SEND_PACING_LIMITED']) {
        final d = diagnosticarError(codigo: code);
        expect(d.tipo, WapiDiagTipo.transitorio, reason: code);
        expect(d.titulo, 'WhatsApp pidió esperar', reason: code);
      }
    });

    test('401/403 → hay que volver a vincular, reintentar no sirve', () {
      final d = diagnosticarError(codigo: 'HTTP_403');
      expect(d.tipo, WapiDiagTipo.definitivo);
      expect(d.reintentable, isFalse);
      expect(d.requiereReconectar, isTrue);
      expect(d.queHacer, contains('Vuelve a vincular'));
    });

    test('SKIPPED explica que el problema es la imagen del producto', () {
      final d = diagnosticarError(
        codigo: 'SKIPPED',
        mensaje: 'No se puede enviar: imagen no es URL http(s): data:image...',
      );
      expect(d.tipo, WapiDiagTipo.definitivo);
      expect(d.explicacion, contains('imagen'));
      expect(d.queHacer, contains('imagen'));
    });

    test('código desconocido → mensaje genérico pero accionable', () {
      final d = diagnosticarError(codigo: 'RARO_XYZ', mensaje: 'algo pasó');
      expect(d.reintentable, isTrue);
      expect(d.titulo, isNotEmpty);
      expect(d.queHacer, isNotNull);
    });

    test('detalle conserva el código y el mensaje para soporte', () {
      final d = diagnosticarError(
        codigo: 'HTTP_500',
        mensaje: 'Internal server error',
      );
      expect(d.detalle, contains('HTTP_500'));
      expect(d.detalle, contains('Internal server error'));
    });
  });

  group('diagnosticarTanda', () {
    WapiEnvioLog log(int id, WapiEnvioEstado estado, String? code, String? msg) =>
        WapiEnvioLog(
          id: id,
          idTienda: 177,
          chatId: '1203@g.us',
          tipoEnvio: 'manual',
          estado: estado,
          errorCode: code,
          errorMessage: msg,
          createdAt: DateTime(2026, 10, 14, 12),
        );

    WapiEnvioTanda tanda(List<WapiEnvioLog> logs) => WapiEnvioTanda(
          id: 't1',
          tipoEnvio: 'manual',
          idProgramacion: null,
          inicio: DateTime(2026, 10, 14, 11),
          ultimaActividad: DateTime(2026, 10, 14, 12),
          logs: logs,
        );

    test('sin fallos no hay diagnóstico', () {
      final d = diagnosticarTanda(tanda([
        log(1, WapiEnvioEstado.enviado, null, null),
      ]));
      expect(d.hayDiagnostico, isFalse);
      expect(d.totalFallidos, 0);
    });

    test('elige el error MÁS FRECUENTE y lo traduce', () {
      final d = diagnosticarTanda(tanda([
        log(1, WapiEnvioEstado.fallido, 'HTTP_500', 'Internal server error'),
        log(2, WapiEnvioEstado.fallido, 'HTTP_409',
            'Session is not connected.'),
        log(3, WapiEnvioEstado.fallido, 'HTTP_409',
            'Session is not connected.'),
        log(4, WapiEnvioEstado.enviado, null, null),
      ]));
      expect(d.principal!.titulo, 'El bot se desconectó');
      expect(d.repeticiones, 2);
      expect(d.totalFallidos, 3);
      expect(d.hayQueReconectar, isTrue);
    });

    test('códigos distintos: el más repetido manda y se sabe si hay sesión', () {
      final d = diagnosticarTanda(tanda([
        log(1, WapiEnvioEstado.fallido, 'PRODUCT_TIMEOUT', null),
        log(2, WapiEnvioEstado.fallido, 'PRODUCT_TIMEOUT', null),
        log(3, WapiEnvioEstado.fallido, 'HTTP_409', 'not connected'),
      ]));
      expect(d.principal!.tipo, WapiDiagTipo.informativo);
      expect(d.repeticiones, 2);
      // Aunque el principal no sea de sesión, hay un 409 ⇒ hay que reconectar.
      expect(d.hayQueReconectar, isTrue);
      expect(d.codigos, containsAll(['PRODUCT_TIMEOUT', 'HTTP_409']));
    });

    test('agrupa por código y no por el texto con ruido variable', () {
      final d = diagnosticarTanda(tanda([
        log(1, WapiEnvioEstado.fallido, 'HTTP_500',
            'Internal server error (tras 3 intento(s))'),
        log(2, WapiEnvioEstado.fallido, 'HTTP_500',
            'Internal server error (tras 1 intento(s))'),
      ]));
      expect(d.repeticiones, 2);
    });
  });

  group('diagnosticarExcepcion', () {
    test('reconoce el 409 del backend por el texto de la excepción', () {
      final d = diagnosticarExcepcion(
        Exception('[wapi-send-products] La sesión no está conectada a WhatsApp '
            '(estado OpenWA: disconnected).'),
      );
      expect(d.requiereReconectar, isTrue);
      expect(d.titulo, 'El bot se desconectó');
    });

    test('reconoce el código NOT_CONNECTED', () {
      final d = diagnosticarExcepcion(
        Exception('[wapi-send-products] ([NOT_CONNECTED]) no conectada'),
      );
      expect(d.tipo, WapiDiagTipo.sesion);
    });

    test('una excepción cualquiera no revienta la UI', () {
      final d = diagnosticarExcepcion(Exception('algo raro'));
      expect(d.titulo, isNotEmpty);
      expect(d.queHacer, isNotNull);
    });
  });
}