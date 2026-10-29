import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/cobro.dart';
import 'package:inventtia_flow/screens/admin/pagos_reserva_screen.dart';

/// [P0] Regla que bloquea la verificación de un pago cuando su reserva ya no
/// está viva.
///
/// `flow.admin_verificar_pago_reserva` no comprueba el estado de la reserva, así
/// que hoy se acepta el pago de una reserva cancelada (caso vivo:
/// `reserva_pago.id = 7` sobre `agenda.id = 302`, `id_estado = 2` Cancelado).
/// Mientras la migración arregla el servidor, la UI lo bloquea con
/// [motivoNoVerificablePago]; este test fija el contrato con los estados reales
/// de `flow.nom_estado_agenda` (Reservado / Cancelado / Completado).
///
/// Modelos puros + una función pura: no hay Supabase ni widgets.
void main() {
  /// Una fila de `admin_listar_pagos_reserva` con el estado de reserva pedido.
  /// El nombre del catálogo viaja en `estado_reserva.nombre`, que es lo que
  /// consume la pantalla.
  PagoAdminItem filaConEstado(String? nombre) => PagoAdminItem.fromJson({
    'id': 7,
    'id_agenda': 302,
    'monto': 1500,
    'moneda': 'CUP',
    'estado': 'creado',
    'id_estado': 2,
    'estado_reserva': nombre == null ? null : {'id': 2, 'nombre': nombre},
    'servicio': {'id': 3, 'nombre': 'Corte'},
    'local': {'id': 2, 'nombre': 'Salón Ana'},
    'cliente': null,
  });

  group('motivoNoVerificablePago', () {
    test('reserva cancelada: se bloquea y se explica', () {
      final motivo = motivoNoVerificablePago(filaConEstado('Cancelado'));

      expect(motivo, isNotNull);
      expect(motivo, contains('cancelada'));
    });

    test('reserva completada: también se bloquea', () {
      final motivo = motivoNoVerificablePago(filaConEstado('Completado'));

      expect(motivo, isNotNull);
      expect(motivo, contains('completado'));
    });

    test('reserva viva: se puede verificar', () {
      expect(motivoNoVerificablePago(filaConEstado('Reservado')), isNull);
    });

    test('no depende de mayúsculas ni de espacios', () {
      expect(motivoNoVerificablePago(filaConEstado('  CANCELADO ')), isNotNull);
    });

    test('sin estado de reserva no se bloquea (dato ausente, no prohibición)',
        () {
      expect(motivoNoVerificablePago(filaConEstado(null)), isNull);
    });

    test('un estado nuevo desconocido no bloquea por accidente', () {
      expect(motivoNoVerificablePago(filaConEstado('En curso')), isNull);
    });
  });
}
