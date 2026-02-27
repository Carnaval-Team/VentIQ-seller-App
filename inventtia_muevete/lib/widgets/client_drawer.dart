import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/wallet_provider.dart';

class ClientDrawer extends StatelessWidget {
  const ClientDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final authProvider = context.watch<AuthProvider>();
    final walletProvider = context.watch<WalletProvider>();

    final profile = authProvider.userProfile;
    final name = profile?['name'] as String? ?? 'Usuario';
    final email = profile?['email'] as String? ?? '';
    final photoUrl =
        profile?['photo_url'] as String? ?? profile?['image'] as String?;

    final bg = isDark ? AppTheme.darkSurface : Colors.white;
    final cardColor = isDark ? AppTheme.darkCard : const Color(0xFFF5F7FA);
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white54 : Colors.grey[600]!;

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header: avatar + name + email ──
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                    backgroundImage:
                        photoUrl != null && photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                    child: photoUrl == null || photoUrl.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (email.isNotEmpty)
                          Text(
                            email,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Wallet balance card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo disponible',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                        Text(
                          '\$${walletProvider.balance.toStringAsFixed(2)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/client/wallet');
                      },
                      style: TextButton.styleFrom(
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      child: Text(
                        'Recargar',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            Divider(
                height: 1,
                color: isDark ? AppTheme.darkBorder : Colors.grey[200]),
            const SizedBox(height: 8),

            // ── Menu items ──
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerItem(
                    icon: Icons.person_outline,
                    label: 'Mi Perfil',
                    isDark: isDark,
                    cardColor: cardColor,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/client/profile');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.bookmark_border,
                    label: 'Mis Direcciones',
                    subtitle: 'Acceso rápido a destinos frecuentes',
                    isDark: isDark,
                    cardColor: cardColor,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(
                          context, '/client/saved-addresses');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Mis Solicitudes',
                    subtitle: 'Historial y solicitudes activas',
                    isDark: isDark,
                    cardColor: cardColor,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(
                          context, '/client/request-history');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Billetera',
                    isDark: isDark,
                    cardColor: cardColor,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/client/wallet');
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.notifications_outlined,
                    label: 'Notificaciones',
                    isDark: isDark,
                    cardColor: cardColor,
                    onTap: () => Navigator.pop(context),
                  ),
                  _DrawerItem(
                    icon: isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    label: isDark ? 'Modo claro' : 'Modo oscuro',
                    isDark: isDark,
                    cardColor: cardColor,
                    onTap: () {
                      context.read<ThemeProvider>().toggleTheme();
                      Navigator.pop(context);
                    },
                  ),
                  _DrawerItem(
                    icon: Icons.help_outline,
                    label: 'Ayuda y Soporte',
                    isDark: isDark,
                    cardColor: cardColor,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Divider(
                height: 1,
                color: isDark ? AppTheme.darkBorder : Colors.grey[200]),

            // ── Sign out ──
            ListTile(
              leading: const Icon(Icons.logout, color: AppTheme.error),
              title: Text(
                'Cerrar sesión',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.error,
                ),
              ),
              onTap: () async {
                Navigator.pop(context);
                await context.read<AuthProvider>().signOut();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/login', (_) => false);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool isDark;
  final Color cardColor;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.cardColor,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Colors.transparent,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.primaryColor, size: 20),
        ),
        title: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}
