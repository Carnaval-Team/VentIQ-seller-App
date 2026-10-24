import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bank_sms_payment.dart';
import '../models/order.dart';
import '../services/bank_sms_service.dart';
import '../utils/price_utils.dart';

/// Helpers compartidos para conciliar SMS de transferencia (PAGOxMOVIL)
/// entre checkout y el detalle de una orden pendiente.
class TransferSmsConfirmation {
  TransferSmsConfirmation._();

  /// `true` si la orden tiene alguna parte pagada por transferencia.
  static bool orderHasTransferencia(Order order) {
    if (order.items.any(
      (item) => item.paymentMethod?.esTransferencia ?? false,
    )) {
      return true;
    }
    for (final payment in PriceUtils.normalizePayments(order.pagos)) {
      if (_paymentLooksLikeTransfer(payment)) return true;
    }
    return false;
  }

  /// Monto que debe casar el SMS: solo la parte transferencia.
  ///
  /// [fallbackTotal] suele ser el total con descuento ya aplicado.
  static double transferExpectedAmount(
    Order order, {
    required double fallbackTotal,
  }) {
    var fromItems = 0.0;
    for (final item in order.items) {
      if (item.paymentMethod?.esTransferencia ?? false) {
        fromItems += item.subtotal;
      }
    }
    if (fromItems > 0) return fromItems;

    var fromPagos = 0.0;
    for (final payment in PriceUtils.normalizePayments(order.pagos)) {
      if (_paymentLooksLikeTransfer(payment)) {
        fromPagos += (payment['monto'] as num?)?.toDouble() ?? 0.0;
      }
    }
    if (fromPagos > 0) return fromPagos;

    return fallbackTotal;
  }

  static bool _paymentLooksLikeTransfer(Map<String, dynamic> payment) {
    final esEfectivo =
        payment['medio_pago_es_efectivo'] == true ||
        payment['es_efectivo'] == true;
    if (esEfectivo) return false;

    final denom =
        (payment['denominacion'] ??
                payment['medio_pago'] ??
                payment['nombre'] ??
                '')
            .toString()
            .toLowerCase();
    final esDigital =
        payment['medio_pago_es_digital'] == true ||
        payment['es_digital'] == true;
    return esDigital ||
        denom.contains('transfer') ||
        denom.contains('transferencia');
  }

  /// Órdenes aún no cerradas donde tiene sentido seguir escuchando el SMS.
  static bool isPendingForSmsWatch(Order order) {
    return order.status != OrderStatus.completada &&
        order.status != OrderStatus.cancelada &&
        order.status != OrderStatus.devuelta &&
        order.status != OrderStatus.pagoConfirmado;
  }

  static Future<BankSmsPayment?> resolvePayment(
    double expectedAmount, {
    BankSmsPayment? alreadyConfirmed,
  }) async {
    if (alreadyConfirmed != null) return alreadyConfirmed;
    if (!BankSmsService.isSupported) return null;
    final service = BankSmsService();
    await service.reconcileFromInbox();
    return service.findMatchingPayment(expectedAmount);
  }

  /// Adjunta el SMS a la operación. Best-effort: no bloquea el cobro.
  ///
  /// Si el SMS ya estaba vinculado a esta misma operación, se trata como OK
  /// y se marca usado en el dispositivo para no reutilizarlo.
  static Future<void> persistToOperation({
    required int operationId,
    required double expectedAmount,
    BankSmsPayment? alreadyConfirmed,
  }) async {
    final service = BankSmsService();
    final payment = await resolvePayment(
      expectedAmount,
      alreadyConfirmed: alreadyConfirmed,
    );
    if (payment == null) {
      service.stopListening();
      return;
    }

    try {
      final resp = await Supabase.instance.client.rpc(
        'fn_confirmar_pago_sms',
        params: {
          'p_id_operacion': operationId,
          'p_sms_json': payment.toJson(),
          'p_tolerancia': BankSmsService.amountTolerance,
        },
      );
      final status = (resp is Map) ? resp['status'] : null;
      final existingOp =
          (resp is Map) ? (resp['id_operacion'] as num?)?.toInt() : null;

      if (status == 'success' ||
          (status == 'duplicate' && existingOp == operationId)) {
        debugPrint(
          '✅ Pago SMS ${payment.nroTransaccionBanco} vinculado a op '
          '$operationId ($status)',
        );
      } else {
        debugPrint('⚠️ fn_confirmar_pago_sms devolvió: $resp');
      }
    } catch (e) {
      debugPrint('❌ Error vinculando pago SMS a operación $operationId: $e');
    } finally {
      await service.removePendingPayment(payment.nroTransaccionBanco);
      service.stopListening();
    }
  }

  /// Carga un SMS ya guardado en la operación (si existe).
  static Future<BankSmsPayment?> loadExistingFromOperation(
    int operationId,
  ) async {
    try {
      final row = await Supabase.instance.client
          .from('app_dat_operacion_venta')
          .select('pago_sms_json')
          .eq('id_operacion', operationId)
          .maybeSingle();
      final json = row?['pago_sms_json'];
      if (json is Map<String, dynamic>) {
        return BankSmsPayment.fromJson(json);
      }
      if (json is Map) {
        return BankSmsPayment.fromJson(Map<String, dynamic>.from(json));
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo leer pago_sms_json de op $operationId: $e');
    }
    return null;
  }
}

/// Banner de espera / confirmación de transferencia por SMS.
///
/// Informativo: si no llega el SMS, el cobro puede seguir. Al casar un monto,
/// notifica vía [onConfirmedChanged] y muestra el detalle del SMS.
class TransferSmsConfirmationBanner extends StatefulWidget {
  final double expectedAmount;
  final int? operationId;
  final ValueChanged<BankSmsPayment?>? onConfirmedChanged;
  final bool showSuccessSnackBar;

  const TransferSmsConfirmationBanner({
    super.key,
    required this.expectedAmount,
    this.operationId,
    this.onConfirmedChanged,
    this.showSuccessSnackBar = true,
  });

  @override
  State<TransferSmsConfirmationBanner> createState() =>
      TransferSmsConfirmationBannerState();
}

class TransferSmsConfirmationBannerState
    extends State<TransferSmsConfirmationBanner> {
  final BankSmsService _bankSmsService = BankSmsService();
  StreamSubscription<BankSmsPayment>? _smsSub;
  BankSmsPayment? _confirmedPayment;
  bool _loadedExisting = false;

  BankSmsPayment? get confirmedPayment => _confirmedPayment;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant TransferSmsConfirmationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expectedAmount != widget.expectedAmount &&
        _confirmedPayment == null) {
      _tryMatchPending();
    }
  }

  @override
  void dispose() {
    _smsSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final opId = widget.operationId;
    if (opId != null && !_loadedExisting) {
      final existing =
          await TransferSmsConfirmation.loadExistingFromOperation(opId);
      _loadedExisting = true;
      if (existing != null && mounted) {
        setState(() => _confirmedPayment = existing);
        widget.onConfirmedChanged?.call(existing);
        return;
      }
    }

    if (!BankSmsService.isSupported) return;

    await _bankSmsService.startListening();
    await _bankSmsService.reconcileFromInbox();
    await _tryMatchPending();
    _smsSub ??= _bankSmsService.onPayment.listen((_) => _tryMatchPending());
  }

  Future<void> _tryMatchPending() async {
    if (_confirmedPayment != null) return;
    final match = await _bankSmsService.findMatchingPayment(
      widget.expectedAmount,
    );
    if (match == null || !mounted) return;
    setState(() => _confirmedPayment = match);
    widget.onConfirmedChanged?.call(match);
    if (widget.showSuccessSnackBar && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Pago de \$${match.monto.toMoneyString(2)} confirmado por SMS '
            '(${match.banco})',
          ),
          backgroundColor: Colors.green[700],
        ),
      );
    }
  }

  /// Último intento de casar antes de crear/confirmar la orden.
  Future<BankSmsPayment?> resolveNow() => TransferSmsConfirmation.resolvePayment(
        widget.expectedAmount,
        alreadyConfirmed: _confirmedPayment,
      );

  @override
  Widget build(BuildContext context) {
    final confirmed = _confirmedPayment;

    if (confirmed != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pago confirmado por SMS',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${confirmed.banco} · \$${confirmed.monto.toMoneyString(2)} ${confirmed.moneda}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                  ),
                  Text(
                    'Tx: ${confirmed.nroTransaccionBanco}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (!BankSmsService.isSupported) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Confirmación automática de transferencia solo disponible en '
                'Android. Verifica el pago manualmente.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE65100)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esperando confirmación de transferencia…',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE65100),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Buscando SMS de PAGOxMOVIL por '
                  '\$${widget.expectedAmount.toMoneyString(2)}. '
                  'Puedes continuar sin esperar.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
