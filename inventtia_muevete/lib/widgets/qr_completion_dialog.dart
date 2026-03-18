import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/app_theme.dart';
import '../providers/theme_provider.dart';
import '../services/trip_completion_qr_service.dart';

/// Dialog shown to the **client** when offline.
/// Displays a QR code that the driver can scan to complete the trip locally.
class QrCompletionDialog extends StatelessWidget {
  final int solicitudId;
  final int viajeId;
  final int driverId;
  final String userId;
  final double precio;
  final String metodoPago;

  const QrCompletionDialog({
    super.key,
    required this.solicitudId,
    required this.viajeId,
    required this.driverId,
    required this.userId,
    required this.precio,
    required this.metodoPago,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final payload = TripCompletionQrService.generatePayload(
      solicitudId: solicitudId,
      viajeId: viajeId,
      driverId: driverId,
      userId: userId,
      precio: precio,
      metodoPago: metodoPago,
    );

    return Dialog(
      backgroundColor: AppTheme.surface(isDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 32, color: AppTheme.warning),
            const SizedBox(height: 12),
            Text(
              'Sin conexión',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Muestra este QR a tu conductor para completar el viaje.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppTheme.textSecondary(isDark),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 220,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Listo',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
