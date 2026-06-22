import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/notificacion.dart';
import '../providers/notificacion_provider.dart';

class NotificacionesScreen extends StatelessWidget {
  const NotificacionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          Consumer<NotificacionProvider>(
            builder: (_, prov, __) {
              if (!prov.hayNoLeidas) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: prov.marcarTodasLeidas,
                icon: const Icon(Icons.done_all,
                    color: Colors.white, size: 18),
                label: const Text('Marcar leídas',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificacionProvider>(
        builder: (_, prov, __) {
          final items = prov.items;
          return RefreshIndicator(
            onRefresh: prov.recargar,
            color: AppTheme.primary,
            child: items.isEmpty
                ? _EmptyState()
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _NotificacionTile(
                      notif: items[i],
                      onTap: () => prov.marcarLeida(items[i].id),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _NotificacionTile extends StatelessWidget {
  final Notificacion notif;
  final VoidCallback onTap;

  const _NotificacionTile({required this.notif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final noLeida = !notif.leida;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: noLeida
                  ? notif.color.withValues(alpha: 0.35)
                  : AppTheme.border,
            ),
            color: noLeida ? notif.color.withValues(alpha: 0.04) : Colors.white,
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: notif.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(notif.icono, color: notif.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notif.titulo,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: noLeida
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (noLeida)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(left: 6, top: 4),
                            decoration: BoxDecoration(
                              color: notif.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notif.mensaje,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fechaRelativa(notif.createdAt),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fechaRelativa(DateTime fecha) {
    final ahora = DateTime.now();
    final diff = ahora.difference(fecha);
    if (diff.inSeconds < 60) return 'Hace un momento';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return DateFormat('dd/MM/yyyy').format(fecha);
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.22),
        Center(
          child: Column(
            children: [
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.10),
                      AppTheme.accent.withValues(alpha: 0.10),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.notifications_none,
                    size: 46, color: AppTheme.primary.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 18),
              const Text('Sin notificaciones',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Aquí verás tus avisos de colas y reservaciones',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}
