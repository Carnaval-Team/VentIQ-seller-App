import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.paddingM),
        children: [
          _buildSectionTitle(context, 'Apariencia'),
          const SizedBox(height: AppTheme.paddingS),
          _buildAppearanceCard(context, themeProvider, isDark),
          const SizedBox(height: AppTheme.paddingL),
          _buildSectionTitle(context, 'Notificaciones'),
          const SizedBox(height: AppTheme.paddingS),
          _buildNotificationsCard(context, isDark),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final accentColor = AppTheme.getAccentColor(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: accentColor,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildAppearanceCard(BuildContext context, ThemeProvider themeProvider, bool isDark) {
    final accentColor = AppTheme.getAccentColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final cardColor = AppTheme.getCardColor(context);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTheme.paddingM),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isDark ? Icons.dark_mode : Icons.light_mode,
                    color: accentColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modo oscuro',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        themeProvider.isDarkMode
                            ? 'Activado'
                            : 'Desactivado',
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: themeProvider.isDarkMode,
                  onChanged: (value) => themeProvider.setDarkMode(value),
                  activeColor: accentColor,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppTheme.darkDividerColor : Colors.grey.shade200,
          ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.paddingM),
            child: Row(
              children: [
                Expanded(
                  child: _buildThemeOption(
                    context: context,
                    icon: Icons.wb_sunny_outlined,
                    label: 'Claro',
                    isSelected: !themeProvider.isDarkMode,
                    onTap: () => themeProvider.setDarkMode(false),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: AppTheme.paddingM),
                Expanded(
                  child: _buildThemeOption(
                    context: context,
                    icon: Icons.nightlight_outlined,
                    label: 'Oscuro',
                    isSelected: themeProvider.isDarkMode,
                    onTap: () => themeProvider.setDarkMode(true),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final accentColor = AppTheme.getAccentColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withOpacity(0.15)
              : (isDark ? AppTheme.darkSurfaceColor : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          border: Border.all(
            color: isSelected ? accentColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? accentColor : textSecondary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? accentColor : textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsCard(BuildContext context, bool isDark) {
    final accentColor = AppTheme.getAccentColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final cardColor = AppTheme.getCardColor(context);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.paddingM,
          vertical: AppTheme.paddingXS,
        ),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(isDark ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.notifications_outlined,
            color: accentColor,
            size: 24,
          ),
        ),
        title: Text(
          'Configurar notificaciones',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        subtitle: Text(
          'Administra tus preferencias de notificaciones',
          style: TextStyle(
            fontSize: 13,
            color: textSecondary,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: textSecondary,
        ),
        onTap: () => Navigator.of(context).pushNamed('/notification-settings'),
      ),
    );
  }
}
