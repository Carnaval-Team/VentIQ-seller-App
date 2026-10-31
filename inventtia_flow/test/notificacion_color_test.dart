import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/config/app_theme.dart';
import 'package:inventtia_flow/models/notificacion.dart';

/// Tests del color/icono de las notificaciones (punto 2 del plan, §3.4).
///
/// Lo importante que se fija aquí:
///   * `cancelacion` en **rojo** (`AppTheme.error`) y con `Icons.event_busy`.
///   * `pago` en **ámbar** (`AppTheme.warning`) y con `Icons.payments_outlined`.
///   * Retrocompatibilidad: las cancelaciones antiguas entraron con
///     `tipo = 'reserva'` y solo se distinguen por el título, así que también
///     tienen que salir en rojo.
///   * `suscripcion` ya no cae en el azul de marca (`AppTheme.primary`), que era
///     el fallo preexistente: tenía icono propio pero color del `default`.
void main() {
  Notificacion notif({required String tipo, String titulo = 'Aviso'}) =>
      Notificacion(
        id: 1,
        uuidUsuario: 'uuid-1',
        tipo: tipo,
        titulo: titulo,
        mensaje: 'Mensaje',
        leida: false,
        createdAt: DateTime(2030, 1, 1, 9),
      );

  group('tipo cancelacion', () {
    test('color rojo y icono de evento cancelado', () {
      final n = notif(tipo: 'cancelacion', titulo: 'Reserva cancelada');
      expect(n.color, AppTheme.error);
      expect(n.icono, Icons.event_busy);
      expect(n.esCancelacion, isTrue);
    });

    test('no depende del título: cualquier aviso de cancelación es rojo', () {
      final n = notif(tipo: 'cancelacion', titulo: 'Aviso del local');
      expect(n.color, AppTheme.error);
    });
  });

  group('tipo pago', () {
    test('color ámbar y icono de pagos', () {
      final n = notif(tipo: 'pago', titulo: 'Pago reportado');
      expect(n.color, AppTheme.warning);
      expect(n.icono, Icons.payments_outlined);
    });

    test('no se confunde con una cancelación', () {
      expect(notif(tipo: 'pago').esCancelacion, isFalse);
    });
  });

  group('retrocompatibilidad (tipo reserva + título de cancelación)', () {
    test('«Reserva cancelada» antiguo también sale en rojo', () {
      final n = notif(tipo: 'reserva', titulo: 'Reserva cancelada');
      expect(n.color, AppTheme.error);
      expect(n.icono, Icons.event_busy);
      expect(n.esCancelacion, isTrue);
    });

    test('títulos de cancelación con prefijo largo también', () {
      final n = notif(
        tipo: 'reserva',
        titulo: 'Reserva cancelada por pago no verificado',
      );
      expect(n.color, AppTheme.error);
    });

    test('tolera mayúsculas y espacios delante', () {
      final n = notif(tipo: 'reserva', titulo: '  RESERVA CANCELADA (admin)');
      expect(n.esCancelacion, isTrue);
      expect(n.color, AppTheme.error);
    });

    test('una reserva normal NO es una cancelación', () {
      final n = notif(tipo: 'reserva', titulo: 'Reserva confirmada');
      expect(n.esCancelacion, isFalse);
      expect(n.color, AppTheme.success);
      expect(n.icono, Icons.confirmation_number);
    });

    test('un tipo desconocido con ese título tampoco se fuerza', () {
      final n = notif(tipo: 'promo', titulo: 'Reserva cancelada');
      expect(n.esCancelacion, isFalse);
      expect(n.color, AppTheme.warning);
    });
  });

  group('tipo suscripcion (fallo preexistente corregido)', () {
    test('ya no usa el color primario del default', () {
      final n = notif(tipo: 'suscripcion', titulo: 'Plan acreditado');
      expect(n.color, isNot(AppTheme.primary));
      expect(n.color, AppTheme.accent);
    });

    test('conserva su icono de suscripción', () {
      expect(notif(tipo: 'suscripcion').icono, Icons.workspace_premium);
    });
  });

  group('los tipos de siempre no cambian', () {
    test('sala_espera → accent/event_seat', () {
      final n = notif(tipo: 'sala_espera');
      expect(n.color, AppTheme.accent);
      expect(n.icono, Icons.event_seat);
    });

    test('promo → warning/campaign', () {
      final n = notif(tipo: 'promo');
      expect(n.color, AppTheme.warning);
      expect(n.icono, Icons.campaign);
    });

    test('sistema (y desconocidos) → primary/notifications', () {
      expect(notif(tipo: 'sistema').color, AppTheme.primary);
      expect(notif(tipo: 'sistema').icono, Icons.notifications);
      expect(notif(tipo: 'lo_que_sea').color, AppTheme.primary);
    });
  });
}