/// Pago bancario confirmado por SMS del número corto `PAGOxMOVIL`.
///
/// Los tres bancos cubanos que operan pasarela de pago externo (Bandec,
/// Metropolitano y Popular de Ahorro) mandan un SMS con la misma plantilla,
/// salvo variaciones de espaciado y saltos de línea:
///
/// ```
/// Banco Bandec Elpago externo fue
/// completado
/// Fecha: 11/8/2026
/// Entidad: Carnaval Alimento SURL
/// Nro. Transaccion: 3479195670
/// Monto Pagado: 840.00 CUP
/// Nro. Transaccion Banco:
/// KW601IONM4999.
/// ```
///
/// El identificador único real del pago es [nroTransaccionBanco] — es lo que
/// se usa para que un mismo SMS no pueda confirmar dos ventas distintas.
class BankSmsPayment {
  /// Banco emisor tal como aparece en el SMS (ej. "Bandec").
  final String banco;

  /// Fecha declarada en el cuerpo del mensaje (no la de recepción).
  final DateTime? fecha;

  /// Comercio receptor (ej. "Carnaval Alimento SURL").
  final String? entidad;

  /// Nro. de transacción de la pasarela.
  final String? nroTransaccion;

  /// Nro. de transacción del banco. Identificador único del pago.
  final String nroTransaccionBanco;

  /// Monto cobrado.
  final double monto;

  /// Moneda (en la práctica siempre CUP).
  final String moneda;

  /// Cuerpo original, para auditoría y para poder re-parsear si la plantilla
  /// cambia sin haber perdido el dato crudo.
  final String rawMessage;

  /// Momento en que el dispositivo recibió el SMS.
  final DateTime receivedAt;

  const BankSmsPayment({
    required this.banco,
    required this.nroTransaccionBanco,
    required this.monto,
    required this.rawMessage,
    required this.receivedAt,
    this.fecha,
    this.entidad,
    this.nroTransaccion,
    this.moneda = 'CUP',
  });

  Map<String, dynamic> toJson() => {
        'banco': banco,
        'fecha': fecha?.toIso8601String(),
        'entidad': entidad,
        'nro_transaccion': nroTransaccion,
        'nro_transaccion_banco': nroTransaccionBanco,
        'monto': monto,
        'moneda': moneda,
        'raw_message': rawMessage,
        'received_at': receivedAt.toIso8601String(),
      };

  factory BankSmsPayment.fromJson(Map<String, dynamic> json) {
    return BankSmsPayment(
      banco: json['banco'] as String? ?? 'Desconocido',
      fecha: json['fecha'] != null
          ? DateTime.tryParse(json['fecha'] as String)
          : null,
      entidad: json['entidad'] as String?,
      nroTransaccion: json['nro_transaccion'] as String?,
      nroTransaccionBanco: json['nro_transaccion_banco'] as String? ?? '',
      monto: (json['monto'] as num?)?.toDouble() ?? 0.0,
      moneda: json['moneda'] as String? ?? 'CUP',
      rawMessage: json['raw_message'] as String? ?? '',
      receivedAt: json['received_at'] != null
          ? DateTime.tryParse(json['received_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  String toString() =>
      'BankSmsPayment($banco, $monto $moneda, tx=$nroTransaccionBanco)';

  @override
  bool operator ==(Object other) =>
      other is BankSmsPayment &&
      other.nroTransaccionBanco == nroTransaccionBanco;

  @override
  int get hashCode => nroTransaccionBanco.hashCode;
}
