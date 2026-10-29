import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/config/app_theme.dart';
import 'package:inventtia_flow/utils/estado_pago.dart';

/// El vocabulario del pago por adelantado es **contrato de UI**: lo consumen la
/// tarjeta de «Mis reservas», el resumen-calendario del admin y la bandeja de
/// pagos. Si alguien cambia una etiqueta o un color aquí, las tres pantallas
/// cambian a la vez (que es lo que se busca) y este test lo deja escrito.
void main() {
  group('EstadoPago.etiqueta', () {
    test('cada estado conocido tiene su texto', () {
      expect(EstadoPago.etiqueta(EstadoPago.pendiente), 'Pago pendiente');
      expect(EstadoPago.etiqueta(EstadoPago.reportado), 'Pago por verificar');
      expect(EstadoPago.etiqueta(EstadoPago.verificado), 'Pago verificado');
      expect(EstadoPago.etiqueta(EstadoPago.rechazado), 'Pago rechazado');
      expect(EstadoPago.etiqueta(EstadoPago.expirado), 'Pago expirado');
    });

    test('sin pago o con un valor desconocido no se pinta nada', () {
      expect(EstadoPago.etiqueta(null), isNull);
      expect(EstadoPago.etiqueta(''), isNull);
      // Una base más nueva que la app puede mandar estados nuevos: NO se
      // inventa un texto, se deja sin chip.
      expect(EstadoPago.etiqueta('anulado'), isNull);
    });
  });

  group('EstadoPago.color', () {
    test('verde cobrado, rojo hay que arreglarlo, gris caducado, ámbar en curso', () {
      expect(EstadoPago.color(EstadoPago.verificado), AppTheme.success);
      expect(EstadoPago.color(EstadoPago.rechazado), AppTheme.error);
      expect(EstadoPago.color(EstadoPago.expirado), AppTheme.textSecondary);
      expect(EstadoPago.color(EstadoPago.pendiente), AppTheme.warning);
      expect(EstadoPago.color(EstadoPago.reportado), AppTheme.warning);
      expect(EstadoPago.color(null), AppTheme.warning);
    });
  });

  group('EstadoPago.icono', () {
    test('cada estado tiene icono y nunca es null', () {
      for (final estado in [
        EstadoPago.pendiente,
        EstadoPago.reportado,
        EstadoPago.verificado,
        EstadoPago.rechazado,
        EstadoPago.expirado,
        null,
        'desconocido',
      ]) {
        expect(EstadoPago.icono(estado), isNotNull);
      }
    });
  });

  group('enCurso / sePuedePagar', () {
    test('en curso = pendiente o reportado', () {
      expect(EstadoPago.enCurso(EstadoPago.pendiente), isTrue);
      expect(EstadoPago.enCurso(EstadoPago.reportado), isTrue);
      expect(EstadoPago.enCurso(EstadoPago.verificado), isFalse);
      expect(EstadoPago.enCurso(EstadoPago.rechazado), isFalse);
      expect(EstadoPago.enCurso(EstadoPago.expirado), isFalse);
      expect(EstadoPago.enCurso(null), isFalse);
    });

    test('se puede pagar sin intento, rechazado o caducado', () {
      expect(EstadoPago.sePuedePagar(null), isTrue);
      expect(EstadoPago.sePuedePagar(EstadoPago.rechazado), isTrue);
      expect(EstadoPago.sePuedePagar(EstadoPago.expirado), isTrue);
      // Con uno vivo no se crea otro (la BD lo rechazaría).
      expect(EstadoPago.sePuedePagar(EstadoPago.pendiente), isFalse);
      expect(EstadoPago.sePuedePagar(EstadoPago.reportado), isFalse);
      // Ni con uno ya cobrado.
      expect(EstadoPago.sePuedePagar(EstadoPago.verificado), isFalse);
    });

    test('un estado desconocido no habilita ni «en curso» ni «pagar»', () {
      expect(EstadoPago.enCurso('anulado'), isFalse);
      expect(EstadoPago.sePuedePagar('anulado'), isFalse);
    });
  });

  group('EstadoPago.etiquetaBoton', () {
    test('el botón dice qué va a pasar', () {
      expect(EstadoPago.etiquetaBoton(null), 'Pagar por adelantado');
      expect(EstadoPago.etiquetaBoton(EstadoPago.pendiente), 'Gestionar pago');
      expect(EstadoPago.etiquetaBoton(EstadoPago.reportado), 'Gestionar pago');
      expect(EstadoPago.etiquetaBoton(EstadoPago.rechazado), 'Reintentar el pago');
      expect(EstadoPago.etiquetaBoton(EstadoPago.expirado), 'Reintentar el pago');
    });
  });
}