import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  bool _pushNotifications = true;
  bool _emailSummary = true;
  bool _smsAlerts = false;
  bool _autoRenewAlerts = true;
  bool _dailyDigest = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentUser = Supabase.instance.client.auth.currentUser;

    return AppBackground(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: textTheme.headlineLarge),
              Text(
                'Configura notificaciones y renovaciones',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              _SettingsProfileCard(textTheme: textTheme),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Cuenta',
                children: [
                  _SettingsInfoTile(
                    title: 'Usuario',
                    subtitle: currentUser?.email ?? 'Sin correo disponible',
                    icon: Icons.verified_user_rounded,
                  ),
                  _SettingsActionTile(
                    title: 'Cerrar sesion',
                    subtitle: 'Salir del panel de licencias',
                    icon: Icons.logout_rounded,
                    onTap: _handleSignOut,
                    highlight: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SettingsSection(
                title: 'Notificaciones',
                children: [
                  _buildSwitchTile(
                    title: 'Push en tiempo real',
                    subtitle: 'Alertas de pagos, vencimientos y renovaciones.',
                    value: _pushNotifications,
                    onChanged: (value) =>
                        setState(() => _pushNotifications = value),
                  ),
                  _buildSwitchTile(
                    title: 'Resumen por correo',
                    subtitle: 'Reporte semanal de licencias y facturacion.',
                    value: _emailSummary,
                    onChanged: (value) => setState(() => _emailSummary = value),
                  ),
                  _buildSwitchTile(
                    title: 'Alertas SMS',
                    subtitle: 'Avisos criticos para vencimientos hoy.',
                    value: _smsAlerts,
                    onChanged: (value) => setState(() => _smsAlerts = value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Renovaciones',
                children: [
                  _buildSwitchTile(
                    title: 'Recordatorios automaticos',
                    subtitle: 'Notifica a las tiendas 3 dias antes.',
                    value: _autoRenewAlerts,
                    onChanged: (value) =>
                        setState(() => _autoRenewAlerts = value),
                  ),
                  _buildSwitchTile(
                    title: 'Digest diario',
                    subtitle: 'Resumen diario de pagos pendientes.',
                    value: _dailyDigest,
                    onChanged: (value) => setState(() => _dailyDigest = value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Integraciones',
                children: const [
                  _SettingsActionTile(
                    title: 'Webhook pagos',
                    subtitle: 'Sincroniza eventos con tu CRM.',
                    icon: Icons.link_rounded,
                  ),
                  _SettingsActionTile(
                    title: 'Canal Slack',
                    subtitle: 'Publica alertas automaticas.',
                    icon: Icons.chat_bubble_outline_rounded,
                  ),
                  _SettingsActionTile(
                    title: 'Backup automatico',
                    subtitle: 'Copia diaria en la nube.',
                    icon: Icons.cloud_done_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.accentStrong,
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }

  Future<void> _handleSignOut() async {
    await _authService.signOut();
  }
}

class _SettingsProfileCard extends StatelessWidget {
  const _SettingsProfileCard({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppGradients.cardCyan,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppGradients.accentGlow,
            ),
            alignment: Alignment.center,
            child: Text('VA', style: textTheme.titleMedium),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VentIQ Admin', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Licencias y renovaciones',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceBright.withOpacity(0.6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Premium',
              style: textTheme.bodySmall?.copyWith(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Column(children: children),
      ],
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: highlight ? AppColors.surfaceBright : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceBright,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.accent),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _SettingsInfoTile extends StatelessWidget {
  const _SettingsInfoTile({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceBright,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.accent),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
