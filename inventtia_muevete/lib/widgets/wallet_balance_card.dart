import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class WalletBalanceCard extends StatelessWidget {
  final double balance;
  final VoidCallback? onAddFunds;
  final VoidCallback? onWithdraw;

  /// Cuando es true y el saldo es negativo se pinta como **deuda** (monto en
  /// valor absoluto) en vez de como saldo. Se usa en la billetera del chofer:
  /// un saldo negativo es la comisión que quedó a deber a la plataforma.
  final bool esChofer;

  /// Texto pequeño bajo el monto cuando el chofer tiene deuda.
  final String? notaDeuda;

  const WalletBalanceCard({
    super.key,
    required this.balance,
    this.onAddFunds,
    this.onWithdraw,
    this.esChofer = false,
    this.notaDeuda,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enDeuda = esChofer && balance < 0;
    final monto = enDeuda ? balance.abs() : balance;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: enDeuda
              // Rojo de aviso: no es saldo, es lo que debe.
              ? const [Color(0xFFB3261E), Color(0xFF7F1D1D)]
              : const [
                  AppTheme.primaryColor,
                  AppTheme.primaryDark,
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (enDeuda ? const Color(0xFFB3261E) : AppTheme.primaryColor)
                .withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Secure Balance label with lock icon
          Row(
            children: [
              Icon(
                enDeuda ? Icons.warning_amber_rounded : Icons.lock_outline,
                size: 16,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                enDeuda ? 'Deuda' : 'Saldo Seguro',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Large balance amount
          Text(
            '\$${monto.toStringAsFixed(2)}',
            style: theme.textTheme.displayLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 36,
            ),
          ),

          if (enDeuda) ...[
            const SizedBox(height: 6),
            Text(
              notaDeuda ??
                  'Saldo negativo: es la comisión que debes a la plataforma.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Action buttons row
          Row(
            children: [
              // Add Funds button
              Expanded(
                child: _ActionButton(
                  icon: Icons.add,
                  label: enDeuda ? 'Pagar deuda' : 'Recargar',
                  onTap: onAddFunds,
                ),
              ),
              /* const SizedBox(width: 12),

              // Withdraw button
              Expanded(
                child: _ActionButton(
                  icon: Icons.arrow_downward,
                  label: 'Retirar',
                  onTap: onWithdraw,
                ),
              ), */
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
