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
/// Si el banco no manda ese número, se guarda una huella del [rawMessage]
/// (`MSG:…`) y el texto completo para bloquear reutilización por monto.
class BankSmsPayment {
  /// Banco emisor tal como aparece en el SMS (ej. "Bandec").
  final String banco;

  /// Fecha declarada en el cuerpo del mensaje (no la de recepción).
  final DateTime? fecha;

  /// Comercio receptor (ej. "Carnaval Alimento SURL").
  final String? entidad;

  /// Nro. de transacción de la pasarela.
  ///
  /// En la plantilla nueva corresponde a "Id Compra".
  final String? nroTransaccion;

  /// Nro. de transacción del banco. Identificador único del pago.
  ///
  /// En la plantilla clásica es "Nro. Transaccion Banco"; en la nueva es
  /// "Nro. Transaccion" (valor alfanumérico). Si el SMS no trae id, aquí va
  /// la huella `MSG:…` del mensaje completo.
  final String nroTransaccionBanco;

  /// Monto cobrado al cliente = parte de transferencia / total según el SMS.
  ///
  /// Plantilla clásica: "Monto Pagado". Plantilla nueva: "Importe".
  final double monto;

  /// Monto neto realmente acreditado tras la comisión del banco. Solo aparece
  /// en la plantilla nueva ("Importe Pagado"); null en la clásica. Se guarda
  /// como referencia; la conciliación usa [monto].
  final double? montoPagado;

  /// Moneda (en la práctica siempre CUP).
  final String moneda;

  /// Cuerpo original, para auditoría y para poder re-parsear si la plantilla
  /// cambia sin haber perdido el dato crudo. También sirve de llave anti-reuso
  /// cuando no hay [nroTransaccionBanco] real.
  final String rawMessage;

  /// Momento en que el dispositivo recibió el SMS.
  final DateTime receivedAt;

  /// `true` si [nroTransaccionBanco] es huella del mensaje (no vino id banco).
  final bool idFromRawMessage;

  const BankSmsPayment({
    required this.banco,
    required this.nroTransaccionBanco,
    required this.monto,
    required this.rawMessage,
    required this.receivedAt,
    this.fecha,
    this.entidad,
    this.nroTransaccion,
    this.montoPagado,
    this.moneda = 'CUP',
    this.idFromRawMessage = false,
  });

  /// Id estable para buffer / usados: banco tx o huella del mensaje.
  String get stableId => nroTransaccionBanco;

  /// `true` si [total] coincide con el monto cobrado (o, en su defecto, con el
  /// neto acreditado) dentro de [tolerancia].
  bool matchesAmount(double total, double tolerancia) {
    if ((monto - total).abs() <= tolerancia) return true;
    final neto = montoPagado;
    return neto != null && (neto - total).abs() <= tolerancia;
  }

  Map<String, dynamic> toJson() => {
        'banco': banco,
        'fecha': fecha?.toIso8601String(),
        'entidad': entidad,
        'nro_transaccion': nroTransaccion,
        'nro_transaccion_banco': nroTransaccionBanco,
        'monto': monto,
        'monto_pagado': montoPagado,
        'moneda': moneda,
        'raw_message': rawMessage,
        'received_at': receivedAt.toIso8601String(),
        'id_from_raw_message': idFromRawMessage,
      };

  factory BankSmsPayment.fromJson(Map<String, dynamic> json) {
    final raw = json['raw_message'] as String? ?? '';
    final tx = json['nro_transaccion_banco'] as String? ?? '';
    final fromRaw = json['id_from_raw_message'] as bool? ??
        tx.startsWith('MSG:');
    return BankSmsPayment(
      banco: json['banco'] as String? ?? 'Desconocido',
      fecha: json['fecha'] != null
          ? DateTime.tryParse(json['fecha'] as String)
          : null,
      entidad: json['entidad'] as String?,
      nroTransaccion: json['nro_transaccion'] as String?,
      nroTransaccionBanco: tx,
      monto: (json['monto'] as num?)?.toDouble() ?? 0.0,
      montoPagado: (json['monto_pagado'] as num?)?.toDouble(),
      moneda: json['moneda'] as String? ?? 'CUP',
      rawMessage: raw,
      receivedAt: json['received_at'] != null
          ? DateTime.tryParse(json['received_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      idFromRawMessage: fromRaw,
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
