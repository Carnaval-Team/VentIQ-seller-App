import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../models/wapi_session.dart';

typedef WapiSessionAction = void Function(String action);

/// Card visual de una sesión/bot WhatsApp.
/// `action` puede ser: 'qr' | 'restart' | 'logout' | 'delete' | 'details' | 'docs'
class WapiSessionCard extends StatelessWidget {
  final WapiSession session;
  final WapiSessionAction onAction;
  final bool compact;

  const WapiSessionCard({
    super.key,
    required this.session,
    required this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final st = session.status;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: st.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(st.icon, color: st.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.phoneNumber ?? 'Sin número asociado',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: st),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                onSelected: (v) async {
                  if (v == 'docs') {
                    final ok = await launchUrl(
                      Uri.parse(
                          'https://github.com/open-wa/wa-automate-nodejs/wiki'),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!ok) onAction('docs');
                  } else {
                    onAction(v);
                  }
                },
                itemBuilder: (ctx) => [
                  if (st != WapiStatus.connected)
                    const PopupMenuItem(
                      value: 'qr',
                      child: ListTile(
                        leading: Icon(Icons.qr_code_2),
                        title: Text('Ver QR / Reconectar'),
                        dense: true,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'restart',
                    child: ListTile(
                      leading: Icon(Icons.refresh),
                      title: Text('Reiniciar'),
                      dense: true,
                    ),
                  ),
                  if (st == WapiStatus.connected)
                    const PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.power_off),
                        title: Text('Desconectar'),
                        dense: true,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'details',
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Detalles'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'docs',
                    child: ListTile(
                      leading: Icon(Icons.menu_book_outlined),
                      title: Text('Documentación'),
                      dense: true,
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Eliminar',
                          style: TextStyle(color: Colors.red)),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _ChipMini(
                  icon: Icons.fingerprint,
                  label: session.wapiSessionId,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: _ChipMini(
                    icon: Icons.schedule,
                    label: 'Actualizado ${_relative(session.lastStatusAt)}',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }
}

class _StatusBadge extends StatelessWidget {
  final WapiStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChipMini extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ChipMini({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
