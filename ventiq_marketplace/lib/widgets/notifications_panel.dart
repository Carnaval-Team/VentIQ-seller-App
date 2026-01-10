import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/notification_model.dart';
import '../services/notification_service.dart';
import '../services/product_detail_service.dart';
import '../services/store_service.dart';
import '../screens/product_detail_screen.dart';
import '../screens/store_detail_screen.dart';
import 'supabase_image.dart';

class NotificationsPanel extends StatefulWidget {
  final NotificationService notificationService;
  final bool embedded;

  const NotificationsPanel({
    super.key,
    required this.notificationService,
    this.embedded = false,
  });

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  bool _showOnlyUnread = false;
  bool _isRefreshing = false;

  final ProductDetailService _productDetailService = ProductDetailService();
  final StoreService _storeService = StoreService();

  static const List<String> _imageDataKeys = [
    'image',
    'imagen',
    'image_url',
    'imagen_url',
    'imageUrl',
    'imagenUrl',
    'thumbnail',
    'thumb',
    'foto',
    'url_imagen',
    'urlImagen',
  ];

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      await widget.notificationService.loadNotifications(
        onlyUnread: _showOnlyUnread,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  String _formatRelativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 0) return 'ahora';
    if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 7) return 'hace ${diff.inDays}d';

    final weeks = (diff.inDays / 7).floor();
    if (weeks < 4) return 'hace ${weeks}sem';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _markAllAsRead() async {
    final ok = await widget.notificationService.markAllAsRead();
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Notificaciones marcadas como leídas'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }

  bool _looksLikeImageUrl(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return lower.contains('.png') ||
          lower.contains('.jpg') ||
          lower.contains('.jpeg') ||
          lower.contains('.webp') ||
          lower.contains('.gif') ||
          lower.contains('supabase.co');
    }
    return lower.contains('supabase.co');
  }

  String? _extractImageUrlFromDynamic(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return _looksLikeImageUrl(trimmed) ? trimmed : null;
    }

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final tipo = (map['tipo'] as String?)?.toLowerCase();
      final rawUrl = map['url'] ?? map['image'] ?? map['imagen'];
      final url = rawUrl is String ? rawUrl.trim() : null;
      if (url == null || url.isEmpty) return null;
      if (tipo != null &&
          tipo.isNotEmpty &&
          !(tipo.contains('image') || tipo.contains('imagen'))) {
        return null;
      }
      return url;
    }

    if (value is List) {
      for (final item in value) {
        final url = _extractImageUrlFromDynamic(item);
        if (url != null) return url;
      }
    }

    return null;
  }

  String? _extractNotificationImageUrl(NotificationModel notification) {
    final data = notification.data;
    if (data == null) return null;

    for (final key in _imageDataKeys) {
      final value = data[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty && _looksLikeImageUrl(trimmed)) {
          return trimmed;
        }
      }
    }

    final multimedia =
        data['multimedias'] ??
        data['imagenes'] ??
        data['images'] ??
        data['media'];
    final fromMultimedia = _extractImageUrlFromDynamic(multimedia);
    if (fromMultimedia != null) return fromMultimedia;

    final rawUrl = data['url'];
    if (rawUrl is String) {
      final trimmed = rawUrl.trim();
      if (trimmed.isNotEmpty && _looksLikeImageUrl(trimmed)) return trimmed;
    }

    return null;
  }

  Widget _buildContent(ScrollController? scrollController) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Notificaciones',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                onPressed: _isRefreshing ? null : _refresh,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: 'Actualizar',
              ),
              StreamBuilder<int>(
                stream: widget.notificationService.unreadCountStream,
                initialData: widget.notificationService.unreadCount,
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return TextButton(
                    onPressed: unread > 0 ? _markAllAsRead : null,
                    child: const Text('Marcar todas'),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('Sin leer'),
                selected: _showOnlyUnread,
                onSelected: (value) async {
                  setState(() {
                    _showOnlyUnread = value;
                  });
                  await _refresh();
                },
              ),
              const Spacer(),
              StreamBuilder<int>(
                stream: widget.notificationService.unreadCountStream,
                initialData: widget.notificationService.unreadCount,
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  if (unread <= 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unread sin leer',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<List<NotificationModel>>(
              stream: widget.notificationService.notificationsStream,
              initialData: widget.notificationService.notifications,
              builder: (context, snapshot) {
                final notifications = snapshot.data ?? [];

                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _showOnlyUnread
                              ? 'No hay notificaciones sin leer'
                              : 'No hay notificaciones',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Aquí aparecerán tus novedades',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  controller: scrollController,
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    final color = notification.getColor();
                    final imageUrl = _extractNotificationImageUrl(notification);
                    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

                    return Dismissible(
                      key: Key('notification_${notification.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF44336),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 18),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      onDismissed: (_) =>
                          _handleNotificationDelete(notification),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _handleNotificationTap(notification),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: notification.leida
                                ? (hasImage
                                      ? color.withOpacity(0.03)
                                      : Colors.white)
                                : (hasImage
                                      ? color.withOpacity(0.10)
                                      : color.withOpacity(0.06)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: hasImage
                                  ? color.withOpacity(0.35)
                                  : Colors.black.withOpacity(0.06),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  notification.getIcon(),
                                  color: color,
                                ),
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
                                            notification.titulo,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: notification.leida
                                                  ? FontWeight.w700
                                                  : FontWeight.w900,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (notification.prioridad ==
                                            NotificationPriority.urgente)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF44336),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'URGENTE',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      notification.mensaje,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatRelativeTime(
                                            notification.createdAt,
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        if (!notification.leida)
                                          Container(
                                            width: 9,
                                            height: 9,
                                            decoration: BoxDecoration(
                                              color: color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (hasImage) const SizedBox(width: 12),
                              if (hasImage)
                                SupabaseImage(
                                  imageUrl: imageUrl,
                                  width: 52,
                                  height: 52,
                                  borderRadius: 14,
                                  fit: BoxFit.cover,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    if (!notification.leida) {
      await widget.notificationService.markAsRead(notification.id);
    }

    final action = notification.accion?.trim();
    if (action == null || action.isEmpty) return;

    final data = notification.data;

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    String? parseString(dynamic value) {
      final v = value?.toString().trim();
      if (v == null || v.isEmpty) return null;
      return v;
    }

    if (action == 'ir_a_producto') {
      final productId = parseInt(data?['id_producto'] ?? data?['product_id']);

      if (productId == null || productId <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el producto.')),
        );
        return;
      }

      try {
        final product = await _productDetailService.getProductDetail(productId);
        if (!mounted) return;

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cargar el producto.')),
        );
      }

      return;
    }

    if (action == 'ir_a_tienda') {
      final storeId = parseInt(data?['id_tienda'] ?? data?['store_id']);

      if (storeId == null || storeId <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la tienda.')),
        );
        return;
      }

      try {
        final store = await _storeService.getStoreDetails(storeId);
        if (!mounted) return;

        final storeName =
            parseString(
              data?['store_nombre'] ?? data?['denominacion_tienda'],
            ) ??
            store?['nombre']?.toString() ??
            store?['denominacion']?.toString() ??
            'Tienda';

        final storeImage =
            parseString(data?['store_imagen'] ?? data?['imagen_url']) ??
            store?['imagen_url']?.toString() ??
            store?['logoUrl']?.toString();

        final normalizedStore = <String, dynamic>{
          ...(store ?? <String, dynamic>{}),
          'id': storeId,
          'nombre': storeName,
          'denominacion': store?['denominacion'] ?? storeName,
          'logoUrl': storeImage,
          'imagen_url': storeImage,
          'ubicacion': store?['ubicacion'] ?? data?['ubicacion'],
          'direccion': store?['direccion'] ?? data?['direccion'],
          'phone': store?['phone'] ?? data?['phone'],
          'productCount':
              parseInt(data?['product_count']) ?? store?['productCount'] ?? 0,
        };

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StoreDetailScreen(store: normalizedStore),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cargar la tienda.')),
        );
      }
    }
  }

  Future<void> _handleNotificationDelete(NotificationModel notification) async {
    final ok = await widget.notificationService.deleteNotification(
      notification.id,
    );

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🗑️ Notificación eliminada'),
          backgroundColor: Colors.grey.shade800,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: widget.embedded
          ? _buildContent(null)
          : DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return _buildContent(scrollController);
              },
            ),
    );
  }
}
