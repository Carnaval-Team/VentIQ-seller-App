import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/wallet_transaction_model.dart';
import '../utils/helpers.dart';

class TransactionListItem extends StatelessWidget {
  final WalletTransactionModel transaction;
  final VoidCallback? onTap;

  const TransactionListItem({
    super.key,
    required this.transaction,
    this.onTap,
  });

  IconData _getIcon() {
    switch (transaction.tipo) {
      case TipoTransaccion.recarga:
        return Icons.arrow_upward;
      case TipoTransaccion.cobro_viaje:
        return Icons.two_wheeler;
      case TipoTransaccion.pago_viaje:
        return Icons.directions_car;
      case null:
        return Icons.receipt_long;
    }
  }

  Color _getIconColor() {
    switch (transaction.tipo) {
      case TipoTransaccion.recarga:
        return AppTheme.success;
      case TipoTransaccion.cobro_viaje:
        return AppTheme.primaryColor;
      case TipoTransaccion.pago_viaje:
        return AppTheme.error;
      case null:
        return Colors.white54;
    }
  }

  Color _getAmountColor() {
    if (transaction.tipo == TipoTransaccion.recarga ||
        transaction.tipo == TipoTransaccion.cobro_viaje) {
      return AppTheme.success;
    }
    return AppTheme.error;
  }

  String _getAmountPrefix() {
    if (transaction.tipo == TipoTransaccion.recarga ||
        transaction.tipo == TipoTransaccion.cobro_viaje) {
      return '+';
    }
    return '-';
  }

  String _getTitle() {
    switch (transaction.tipo) {
      case TipoTransaccion.recarga:
        return 'Recarga';
      case TipoTransaccion.cobro_viaje:
        return 'Cobro de viaje';
      case TipoTransaccion.pago_viaje:
        return 'Pago de viaje';
      case null:
        return 'Transaccion';
    }
  }

  String _getSubtitle() {
    final parts = <String>[];
    if (transaction.createdAt != null) {
      parts.add(Helpers.formatRelativeTime(transaction.createdAt!));
    }
    if (transaction.descripcion != null &&
        transaction.descripcion!.isNotEmpty) {
      parts.add(transaction.descripcion!);
    }
    return parts.isEmpty ? '' : parts.join(' - ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = _getIconColor();
    final amountColor = _getAmountColor();
    final amount = transaction.monto ?? 0.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            // Transaction icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getIcon(),
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Title and subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTitle(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  if (_getSubtitle().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _getSubtitle(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Amount
            Text(
              '${_getAmountPrefix()}\$${amount.toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
