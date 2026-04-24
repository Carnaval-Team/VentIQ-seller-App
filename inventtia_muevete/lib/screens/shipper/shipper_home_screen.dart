import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

class ShipperHomeScreen extends StatelessWidget {
  const ShipperHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auth = context.watch<AuthProvider>();
    final name = (auth.userProfile?['name'] as String?) ?? 'Shipper';
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        elevation: 0,
        title: Text(
          'Muevete Carga',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: textPrimary),
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 80,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(height: 24),
              Text(
                'Hola, $name',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Panel de Shipper — Próximamente',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  color: textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Aquí podrás publicar cargas, ver ofertas de transportistas y gestionar tus envíos.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
