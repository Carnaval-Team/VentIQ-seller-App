import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_theme.dart';

/// Fila compacta para subir o ver foto de licencia (frente / dorso).
class LicensePhotoRow extends StatelessWidget {
  final String label;
  final String? url;
  final bool uploading;
  final bool isDark;
  final VoidCallback? onTap;

  const LicensePhotoRow({
    super.key,
    required this.label,
    required this.url,
    required this.uploading,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : Colors.grey[200]!;
    final hasPhoto = url != null && url!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: onTap != null
                ? AppTheme.primaryColor.withValues(alpha: 0.4)
                : borderColor,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 44,
                child: uploading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : hasPhoto
                        ? Image.network(
                            url!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder(),
                          )
                        : _placeholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPhoto ? 'Foto cargada' : 'Sin foto',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasPhoto
                          ? AppTheme.success
                          : (isDark ? Colors.white38 : Colors.grey[500]),
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                hasPhoto ? Icons.edit_outlined : Icons.upload_outlined,
                size: 18,
                color: AppTheme.primaryColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        child: Icon(
          Icons.image_outlined,
          color: AppTheme.primaryColor.withValues(alpha: 0.5),
          size: 24,
        ),
      );
}
