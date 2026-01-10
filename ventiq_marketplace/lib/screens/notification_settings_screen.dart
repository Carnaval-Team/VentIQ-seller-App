import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/notification_service.dart';
import '../services/user_preferences_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  final UserPreferencesService _preferencesService = UserPreferencesService();

  bool _loadingConsent = true;
  bool _savingConsent = false;
  NotificationConsentStatus? _consent;
  bool _notificationsEnabled = false;

  bool _loadingStores = false;
  String? _storesError;
  List<Map<String, dynamic>> _storeSubscriptions = [];
  final Set<int> _updatingStoreIds = <int>{};

  bool _loadingProducts = false;
  String? _productsError;
  List<Map<String, dynamic>> _productSubscriptions = [];
  final Set<int> _updatingProductIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    setState(() {
      _loadingConsent = true;
    });

    final status = await _preferencesService.getNotificationConsentStatus();
    if (!mounted) return;

    setState(() {
      _consent = status;
      _notificationsEnabled = status == NotificationConsentStatus.accepted;
      _loadingConsent = false;
    });
  }

  Future<void> _onRefresh() async {
    await _loadConsent();

    if (_storeSubscriptions.isNotEmpty || _loadingStores) {
      await _loadStoreSubscriptions(force: true);
    }

    if (_productSubscriptions.isNotEmpty || _loadingProducts) {
      await _loadProductSubscriptions(force: true);
    }
  }

  Future<void> _setGlobalConsent(bool enabled) async {
    if (_savingConsent) return;

    setState(() {
      _savingConsent = true;
      _notificationsEnabled = enabled;
    });

    try {
      final accepted = await _notificationService.saveNotificationConsent(
        status: enabled
            ? NotificationConsentStatus.accepted
            : NotificationConsentStatus.denied,
      );

      if (!mounted) return;

      setState(() {
        _notificationsEnabled = accepted;
        _consent = accepted
            ? NotificationConsentStatus.accepted
            : NotificationConsentStatus.denied;
        _savingConsent = false;
      });

      if (enabled && !accepted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permiso de notificaciones denegado en el sistema. Actívalo desde ajustes.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingConsent = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar la configuración.'),
        ),
      );
      await _loadConsent();
    }
  }

  Future<void> _loadStoreSubscriptions({bool force = false}) async {
    if (_loadingStores) return;
    if (!force && _storeSubscriptions.isNotEmpty) return;

    setState(() {
      _loadingStores = true;
      _storesError = null;
    });

    try {
      final list = await _notificationService.getStoreSubscriptions();
      if (!mounted) return;
      setState(() {
        _storeSubscriptions = list;
        _loadingStores = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _storesError = 'No se pudieron cargar las suscripciones a tiendas.';
        _loadingStores = false;
      });
    }
  }

  Future<void> _loadProductSubscriptions({bool force = false}) async {
    if (_loadingProducts) return;
    if (!force && _productSubscriptions.isNotEmpty) return;

    setState(() {
      _loadingProducts = true;
      _productsError = null;
    });

    try {
      final list = await _notificationService.getProductSubscriptions();
      if (!mounted) return;
      setState(() {
        _productSubscriptions = list;
        _loadingProducts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _productsError = 'No se pudieron cargar las suscripciones a productos.';
        _loadingProducts = false;
      });
    }
  }

  Future<void> _setStoreSubscriptionActive({
    required int storeId,
    required bool active,
  }) async {
    if (_updatingStoreIds.contains(storeId)) return;

    setState(() {
      _updatingStoreIds.add(storeId);
    });

    try {
      await _notificationService.setStoreSubscriptionActive(
        storeId: storeId,
        active: active,
      );

      if (!mounted) return;

      final updated = List<Map<String, dynamic>>.from(_storeSubscriptions);
      final idx = updated.indexWhere(
        (row) => (row['id_tienda'] as int?) == storeId,
      );
      if (idx != -1) {
        final nextRow = Map<String, dynamic>.from(updated[idx]);
        nextRow['activo'] = active;
        updated[idx] = nextRow;
      }

      setState(() {
        _storeSubscriptions = updated;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar la suscripción.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _updatingStoreIds.remove(storeId);
      });
    }
  }

  Future<void> _setProductSubscriptionActive({
    required int productId,
    required bool active,
  }) async {
    if (_updatingProductIds.contains(productId)) return;

    setState(() {
      _updatingProductIds.add(productId);
    });

    try {
      await _notificationService.setProductSubscriptionActive(
        productId: productId,
        active: active,
      );

      if (!mounted) return;

      final updated = List<Map<String, dynamic>>.from(_productSubscriptions);
      final idx = updated.indexWhere(
        (row) => (row['id_producto'] as int?) == productId,
      );
      if (idx != -1) {
        final nextRow = Map<String, dynamic>.from(updated[idx]);
        nextRow['activo'] = active;
        updated[idx] = nextRow;
      }

      setState(() {
        _productSubscriptions = updated;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo actualizar la suscripción.')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _updatingProductIds.remove(productId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final consentSubtitle = _loadingConsent
        ? 'Cargando...'
        : (_notificationsEnabled
              ? 'Activado'
              : (_consent == NotificationConsentStatus.never
                    ? 'Desactivado (nunca)'
                    : 'Desactivado'));

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración de notificaciones')),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.paddingL),
          children: [
            Text(
              'Notificaciones',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Gestiona si deseas recibir notificaciones y qué suscripciones están activas.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile.adaptive(
                value: _notificationsEnabled,
                onChanged: (_loadingConsent || _savingConsent)
                    ? null
                    : _setGlobalConsent,
                secondary: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(31),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppTheme.primaryColor,
                  ),
                ),
                title: const Text(
                  'Recibir notificaciones',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  consentSubtitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ExpansionTile(
                leading: const Icon(
                  Icons.store_outlined,
                  color: AppTheme.primaryColor,
                ),
                title: const Text(
                  'Suscripciones a tiendas',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  _storeSubscriptions.isEmpty
                      ? 'Toca para cargar'
                      : '${_storeSubscriptions.length} tienda(s)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                onExpansionChanged: (expanded) {
                  if (expanded) {
                    _loadStoreSubscriptions();
                  }
                },
                children: [
                  if (_loadingStores)
                    const Padding(
                      padding: EdgeInsets.all(AppTheme.paddingM),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_storesError != null)
                    Padding(
                      padding: const EdgeInsets.all(AppTheme.paddingM),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _storesError!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () =>
                                  _loadStoreSubscriptions(force: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_storeSubscriptions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppTheme.paddingM),
                      child: Text(
                        'No tienes suscripciones a tiendas.',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _storeSubscriptions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = _storeSubscriptions[index];
                        final storeId = row['id_tienda'] as int?;
                        final storeData = row['app_dat_tienda'] as Map?;
                        final name =
                            (storeData?['denominacion'] ??
                                    storeData?['nombre'] ??
                                    '')
                                .toString();
                        final isActive = row['activo'] == true;
                        final isUpdating =
                            storeId != null &&
                            _updatingStoreIds.contains(storeId);

                        return ListTile(
                          title: Text(
                            name.isNotEmpty
                                ? name
                                : (storeId == null
                                      ? 'Tienda'
                                      : 'Tienda #$storeId'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Activar / desactivar',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isUpdating)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              Switch.adaptive(
                                value: isActive,
                                onChanged: (storeId == null || isUpdating)
                                    ? null
                                    : (value) {
                                        _setStoreSubscriptionActive(
                                          storeId: storeId,
                                          active: value,
                                        );
                                      },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                leading: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppTheme.primaryColor,
                ),
                title: const Text(
                  'Suscripciones a productos',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  _productSubscriptions.isEmpty
                      ? 'Toca para cargar'
                      : '${_productSubscriptions.length} producto(s)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                onExpansionChanged: (expanded) {
                  if (expanded) {
                    _loadProductSubscriptions();
                  }
                },
                children: [
                  if (_loadingProducts)
                    const Padding(
                      padding: EdgeInsets.all(AppTheme.paddingM),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_productsError != null)
                    Padding(
                      padding: const EdgeInsets.all(AppTheme.paddingM),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _productsError!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () =>
                                  _loadProductSubscriptions(force: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_productSubscriptions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppTheme.paddingM),
                      child: Text(
                        'No tienes suscripciones a productos.',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _productSubscriptions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = _productSubscriptions[index];
                        final productId = row['id_producto'] as int?;
                        final productData = row['app_dat_producto'] as Map?;
                        final name =
                            (productData?['denominacion'] ??
                                    productData?['nombre'] ??
                                    '')
                                .toString();
                        final isActive = row['activo'] == true;
                        final isUpdating =
                            productId != null &&
                            _updatingProductIds.contains(productId);

                        return ListTile(
                          title: Text(
                            name.isNotEmpty
                                ? name
                                : (productId == null
                                      ? 'Producto'
                                      : 'Producto #$productId'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: const Text(
                            'Activar / desactivar',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isUpdating)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              Switch.adaptive(
                                value: isActive,
                                onChanged: (productId == null || isUpdating)
                                    ? null
                                    : (value) {
                                        _setProductSubscriptionActive(
                                          productId: productId,
                                          active: value,
                                        );
                                      },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
