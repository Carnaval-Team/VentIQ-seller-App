import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class TransportTypeCard extends StatelessWidget {
  final String vehicleType;
  final IconData icon;
  final int passengerCount;
  final double price;
  final String eta;
  final bool isSelected;
  final VoidCallback? onTap;

  const TransportTypeCard({
    super.key,
    required this.vehicleType,
    required this.icon,
    required this.passengerCount,
    required this.price,
    required this.eta,
    this.isSelected = false,
    this.onTap,
  });

  /// Factory constructors for each vehicle type.
  factory TransportTypeCard.moto({
    required double price,
    required String eta,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return TransportTypeCard(
      vehicleType: 'Moto',
      icon: Icons.two_wheeler,
      passengerCount: 1,
      price: price,
      eta: eta,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  factory TransportTypeCard.auto({
    required double price,
    required String eta,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return TransportTypeCard(
      vehicleType: 'Auto',
      icon: Icons.directions_car,
      passengerCount: 4,
      price: price,
      eta: eta,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  factory TransportTypeCard.microbus({
    required double price,
    required String eta,
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return TransportTypeCard(
      vehicleType: 'Microbus',
      icon: Icons.directions_bus,
      passengerCount: 12,
      price: price,
      eta: eta,
      isSelected: isSelected,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isSelected
        ? AppTheme.primaryColor
        : (isDark ? AppTheme.darkBorder : Colors.grey[300]!);
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.grey[600]!;
    final iconColor = isSelected
        ? AppTheme.primaryColor
        : (isDark ? Colors.white.withValues(alpha: 0.7) : Colors.grey[700]!);
    final iconBg = isSelected
        ? AppTheme.primaryColor.withValues(alpha: 0.15)
        : (isDark ? theme.colorScheme.surface : Colors.grey[100]!);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Vehicle icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // Vehicle info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicleType,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$passengerCount pasajero${passengerCount > 1 ? 's' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Price and ETA
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    eta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
