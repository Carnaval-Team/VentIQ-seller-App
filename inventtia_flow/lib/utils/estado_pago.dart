import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Vocabulario único del **estado del pago por adelantado** de una reserva
/// (`agenda.pago_estado`, migración 62).
///
/// Lo comparten tres pantallas que hasta ahora podían decir lo mismo de tres
/// formas: la tarjeta de «Mis reservas» del cliente, el resumen-calendario del
/// admin y la bandeja de pagos. Tenerlo aquí evita que el mismo estado se lea
/// («Pago pendiente» / «pendiente») o se pinte de distinto color según dónde
/// mires, que es el tipo de desajuste que nadie nota hasta que un cliente
/// reclama.
///
/// Es puro (solo Flutter para el `Color`): se puede testear sin Supabase.
class EstadoPago {
  EstadoPago._();

  static const String pendiente = 'pendiente';
  static const String reportado = 'reportado';
  static const String verificado = 'verificado';
  static const String rechazado = 'rechazado';
  static const String expirado = 'expirado';

  /// Texto del chip, o `null` si no hay pago (`null`) o el valor es desconocido
  /// (una base más nueva que la app): en ese caso **no se pinta nada**, igual
  /// que hace el resto de la app con lo que no entiende.
  static String? etiqueta(String? estado) {
    switch (estado) {
      case pendiente:
        return 'Pago pendiente';
      case reportado:
        return 'Pago por verificar';
      case verificado:
        return 'Pago verificado';
      case rechazado:
        return 'Pago rechazado';
      case expirado:
        return 'Pago expirado';
      default:
        return null;
    }
  }

  /// Color del chip. Ámbar = hay algo en marcha, verde = cobrado, rojo = hay que
  /// arreglarlo, gris = ya no hay nada que hacer.
  static Color color(String? estado) {
    switch (estado) {
      case verificado:
        return AppTheme.success;
      case rechazado:
        return AppTheme.error;
      case expirado:
        return AppTheme.textSecondary;
      default:
        return AppTheme.warning;
    }
  }

  static IconData icono(String? estado) {
    switch (estado) {
      case verificado:
        return Icons.verified_outlined;
      case rechazado:
        return Icons.report_gmailerrorred_outlined;
      case expirado:
        return Icons.timer_off_outlined;
      case reportado:
        return Icons.hourglass_top_outlined;
      default:
        return Icons.schedule_outlined;
    }
  }

  /// Hay un intento vivo que el cliente puede seguir (y reabrir la hoja).
  static bool enCurso(String? estado) =>
      estado == pendiente || estado == reportado;

  /// El cliente puede empezar un pago (o reintentarlo): sin intento todavía, o
  /// con el anterior rechazado/caducado. Con uno verificado no se le ofrece
  /// volver a pagar.
  static bool sePuedePagar(String? estado) =>
      estado == null || estado == rechazado || estado == expirado;

  /// Texto del botón para ese estado.
  static String etiquetaBoton(String? estado) {
    if (enCurso(estado)) return 'Gestionar pago';
    if (estado == rechazado || estado == expirado) return 'Reintentar el pago';
    return 'Pagar por adelantado';
  }
}
