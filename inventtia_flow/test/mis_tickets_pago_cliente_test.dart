import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/screens/mis_tickets_screen.dart';

/// Regla del botón «Pagar por adelantado» de la tarjeta de reservas del cliente
/// (P1-2 de la auditoría del pago por adelantado, migración 62).
///
/// El fallo era que toda reserva activa mostraba el botón aunque la entidad o el
/// servicio tuvieran el cobro apagado, porque la decisión solo miraba
/// `agenda.pago_estado`. Ahora, sin intento de pago, hace falta que el servidor
/// (`flow.cliente_cobro_info`) lo haya confirmado.
void main() {
  group('sin intento de pago manda la disponibilidad del servidor', () {
    test('disponible = true ofrece el pago', () {
      expect(
        puedeOfrecerPagoAlCliente(
          activa: true,
          pagoEstado: null,
          cobroDisponible: true,
        ),
        isTrue,
      );
    });

    test('disponible = false NO lo ofrece', () {
      expect(
        puedeOfrecerPagoAlCliente(
          activa: true,
          pagoEstado: null,
          cobroDisponible: false,
        ),
        isFalse,
      );
    });

    test('sin resolver (o error de red) tampoco: antes ocultar que prometer', () {
      expect(
        puedeOfrecerPagoAlCliente(
          activa: true,
          pagoEstado: null,
          cobroDisponible: null,
        ),
        isFalse,
      );
    });
  });

  group('con intento de pago manda el estado del intento', () {
    test('pendiente se puede gestionar aunque la disponibilidad no se sepa', () {
      expect(
        puedeOfrecerPagoAlCliente(
          activa: true,
          pagoEstado: 'pendiente',
          cobroDisponible: null,
        ),
        isTrue,
      );
    });

    test('reportado se puede gestionar', () {
      expect(
        puedeOfrecerPagoAlCliente(
          activa: true,
          pagoEstado: 'reportado',
          cobroDisponible: false,
        ),
        isTrue,
      );
    });

    test('rechazado y expirado permiten reintentar', () {
      for (final estado in ['rechazado', 'expirado']) {
        expect(
          puedeOfrecerPagoAlCliente(
            activa: true,
            pagoEstado: estado,
            cobroDisponible: false,
          ),
          isTrue,
          reason: 'estado $estado',
        );
      }
    });

    test('verificado ya no se toca', () {
      expect(
        puedeOfrecerPagoAlCliente(
          activa: true,
          pagoEstado: 'verificado',
          cobroDisponible: true,
        ),
        isFalse,
      );
    });

    test('un estado desconocido (base más nueva que la app) no se ofrece', () {
      expect(
        puedeOfrecerPagoAlCliente(
          activa: true,
          pagoEstado: 'en_revision_manual',
          cobroDisponible: true,
        ),
        isFalse,
      );
    });
  });

  test('reserva cancelada o completada no ofrece pago nunca', () {
    expect(
      puedeOfrecerPagoAlCliente(
        activa: false,
        pagoEstado: null,
        cobroDisponible: true,
      ),
      isFalse,
    );
    expect(
      puedeOfrecerPagoAlCliente(
        activa: false,
        pagoEstado: 'pendiente',
        cobroDisponible: true,
      ),
      isFalse,
    );
  });
}
