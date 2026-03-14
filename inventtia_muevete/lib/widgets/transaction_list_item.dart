import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';
import '../models/wallet_transaction_model.dart';
import '../utils/helpers.dart';

class TransactionListItem extends StatelessWidget {
  final WalletTransactionModel transaction;
  final VoidCallback? onTap;
  final VoidCallback? onVerificar;

  const TransactionListItem({
    super.key,
    required this.transaction,
    this.onTap,
    this.onVerificar,
  });

  IconData _getIcon() {
    switch (transaction.tipo) {
      case TipoTransaccion.recarga:
        return Icons.arrow_upward;
      case TipoTransaccion.cobro_viaje:
        return Icons.two_wheeler;
      case TipoTransaccion.pago_viaje:
        return Icons.directions_car;
      case TipoTransaccion.reembolso:
        return Icons.replay;
      case TipoTransaccion.comision_viaje:
        return Icons.percent;
      case null:
        return Icons.receipt_long;
    }
  }

  Color _getIconColor() {
    if (transaction.estado == EstadoTransaccion.pendiente) {
      return AppTheme.warning;
    }
    switch (transaction.tipo) {
      case TipoTransaccion.recarga:
        return AppTheme.success;
      case TipoTransaccion.cobro_viaje:
        return AppTheme.primaryColor;
      case TipoTransaccion.pago_viaje:
        return AppTheme.error;
      case TipoTransaccion.reembolso:
        return AppTheme.success;
      case TipoTransaccion.comision_viaje:
        return AppTheme.error;
      case null:
        return Colors.grey;
    }
  }

  Color _getAmountColor() {
    if (transaction.estado == EstadoTransaccion.pendiente) {
      return AppTheme.warning;
    }
    // Use the actual sign of the amount from DB
    final amount = transaction.monto ?? 0.0;
    return amount >= 0 ? AppTheme.success : AppTheme.error;
  }

  String _getTitle() {
    switch (transaction.tipo) {
      case TipoTransaccion.recarga:
        return 'Recarga';
      case TipoTransaccion.cobro_viaje:
        return 'Cobro de viaje';
      case TipoTransaccion.pago_viaje:
        return 'Pago de viaje';
      case TipoTransaccion.reembolso:
        return 'Reembolso';
      case TipoTransaccion.comision_viaje:
        return 'Comisión de viaje';
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

  Widget? _buildEstadoBadge() {
    if (transaction.estado == null ||
        transaction.estado == EstadoTransaccion.completada) {
      return null;
    }

    Color badgeColor;
    String label;

    switch (transaction.estado!) {
      case EstadoTransaccion.pendiente:
        badgeColor = AppTheme.warning;
        label = 'Pendiente';
        break;
      case EstadoTransaccion.aceptada:
        badgeColor = AppTheme.success;
        label = 'Aceptada';
        break;
      case EstadoTransaccion.cancelada:
        badgeColor = AppTheme.error;
        label = 'Cancelada';
        break;
      case EstadoTransaccion.completada:
        return null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: badgeColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = _getIconColor();
    final amountColor = _getAmountColor();
    final amount = transaction.monto ?? 0.0;
    final estadoBadge = _buildEstadoBadge();
    final showVerifyButton = transaction.estado == EstadoTransaccion.pendiente &&
        onVerificar != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          children: [
            Row(
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

                // Title, subtitle, and badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _getTitle(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (estadoBadge != null) ...[
                            const SizedBox(width: 8),
                            estadoBadge,
                          ],
                        ],
                      ),
                      if (_getSubtitle().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _getSubtitle(),
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Amount
                Text(
                  '\$${amount.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
              ],
            ),

            // Verify button for pending recargas
            if (showVerifyButton) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: onVerificar,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: Text(
                    'Verificar operación',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(color: AppTheme.primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
