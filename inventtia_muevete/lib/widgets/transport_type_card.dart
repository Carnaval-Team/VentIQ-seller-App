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
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.darkBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Vehicle icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withValues(alpha: 0.15)
                    : colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? AppTheme.primaryColor
                    : Colors.white.withValues(alpha: 0.7),
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
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$passengerCount pasajero${passengerCount > 1 ? 's' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.5),
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
                    color: Colors.white,
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
