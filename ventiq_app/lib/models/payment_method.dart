import 'package:flutter/material.dart';

class PaymentMethod {
  final int id;
  final String denominacion;
  final String? descripcion;
  final bool esDigital;
  final bool esEfectivo;
  final bool esActivo;

  /// ID sentinel (no existe en app_nom_medio_pago) para el pseudo-método
  /// "Pago Pendiente" (cuenta por cobrar). Igual que el 999 de "Pago Regular
  /// (Efectivo)", se maneja completamente en el cliente: no genera fila en
  /// app_dat_pago_venta y hace que la venta quede con es_pagada = false.
  static const int pagoPendienteId = 998;

  /// Pseudo-método de pago "Pago Pendiente" para dejar el monto como cuenta
  /// por cobrar asociada al cliente de la venta.
  static PaymentMethod pagoPendiente() => PaymentMethod(
        id: pagoPendienteId,
        denominacion: 'Pago Pendiente (Cuenta por Cobrar)',
        descripcion:
            'El monto queda pendiente de cobro, asociado al cliente de la venta',
        esDigital: false,
        esEfectivo: false,
        esActivo: true,
      );

  bool get esPagoPendiente => id == pagoPendienteId;

  PaymentMethod({
    required this.id,
    required this.denominacion,
    this.descripcion,
    required this.esDigital,
    required this.esEfectivo,
    required this.esActivo,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      descripcion: json['descripcion'] as String?,
      esDigital: json['es_digital'] as bool? ?? false,
      esEfectivo: json['es_efectivo'] as bool? ?? false,
      esActivo: json['es_activo'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'es_digital': esDigital,
      'es_efectivo': esEfectivo,
      'es_activo': esActivo,
    };
  }

  String get displayName => denominacion;

  /// `true` si es una transferencia bancaria — el método que dispara un SMS de
  /// confirmación del corto `PAGOxMOVIL`. Es digital y no efectivo; se excluye
  /// explícitamente el pseudo-método 999 ("Pago regular" efectivo).
  bool get esTransferencia =>
      !esEfectivo &&
      (esDigital || denominacion.toLowerCase().contains('transfer'));

  IconData get typeIcon {
    if (esPagoPendiente) return Icons.schedule_send;
    if (esEfectivo) return Icons.payments;
    if (esDigital) return Icons.credit_card;
    return Icons.account_balance_wallet;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaymentMethod && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
