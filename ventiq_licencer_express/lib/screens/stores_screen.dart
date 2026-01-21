import 'package:flutter/material.dart';

import '../models/license_models.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/renew_license_dialog.dart';

class StoresScreen extends StatefulWidget {
  const StoresScreen({super.key});

  @override
  State<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  late Future<List<StoreInfo>> _storesFuture;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showOnlyOverdue = false;
  bool _showOnlyActive = false;
  bool _hideFreePlans = true;
  bool _showFilters = true;

  @override
  void initState() {
    super.initState();
    _storesFuture = _subscriptionService.fetchStores();
  }

  void _refreshStores() {
    setState(() {
      _storesFuture = _subscriptionService.fetchStores();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StoreInfo>>(
      future: _storesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppBackground(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _buildErrorState(context);
        }
        return _buildContent(context, snapshot.data!);
      },
    );
  }

  Widget _buildContent(BuildContext context, List<StoreInfo> stores) {
    final textTheme = Theme.of(context).textTheme;
    final filteredStores = _applyFilters(stores);

    return AppBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tiendas', style: textTheme.headlineLarge),
                      Text(
                        'Listado completo de licencias',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _showFilters = !_showFilters;
                      });
                    },
                    icon: Icon(
                      _showFilters ? Icons.filter_alt_off : Icons.filter_alt,
                    ),
                    tooltip: _showFilters
                        ? 'Ocultar filtros'
                        : 'Mostrar filtros',
                  ),
                ],
              ),
            ),
            if (_showFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: _buildFilters(textTheme),
              ),
            Expanded(
              child: filteredStores.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: _EmptyState(
                        message:
                            'No hay licencias que coincidan con el filtro.',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                      itemCount: filteredStores.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final store = filteredStores[index];
                        return _StoreCard(
                          store: store,
                          onRenewed: _refreshStores,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return AppBackground(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(
                'No pudimos cargar las tiendas.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _storesFuture = _subscriptionService.fetchStores();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentStrong,
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filtros rápidos',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              TextButton(
                onPressed: _resetFilters,
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                child: const Text('Limpiar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Buscar por tienda, plan, owner o ubicación',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _FilterSwitch(
                label: 'Solo vencidas',
                value: _showOnlyOverdue,
                onChanged: (value) {
                  setState(() {
                    _showOnlyOverdue = value;
                    if (value) {
                      _showOnlyActive = false;
                    }
                  });
                },
              ),
              _FilterSwitch(
                label: 'Solo activas',
                value: _showOnlyActive,
                onChanged: (value) {
                  setState(() {
                    _showOnlyActive = value;
                    if (value) {
                      _showOnlyOverdue = false;
                    }
                  });
                },
              ),
              _FilterSwitch(
                label: 'Ocultar gratis',
                value: _hideFreePlans,
                onChanged: (value) {
                  setState(() {
                    _hideFreePlans = value;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _showOnlyOverdue = false;
      _showOnlyActive = false;
      _hideFreePlans = true;
      _searchController.clear();
    });
  }

  List<StoreInfo> _applyFilters(List<StoreInfo> stores) {
    final query = _searchQuery.trim().toLowerCase();
    return stores.where((store) {
      final planName = store.plan.toLowerCase();
      final matchesSearch =
          query.isEmpty ||
          store.storeName.toLowerCase().contains(query) ||
          planName.contains(query) ||
          store.owner.toLowerCase().contains(query) ||
          (store.phone ?? '').toLowerCase().contains(query) ||
          (store.state ?? '').toLowerCase().contains(query) ||
          (store.country ?? '').toLowerCase().contains(query);

      final isFreePlan =
          store.renewalAmount <= 0 ||
          planName.contains('gratis') ||
          planName.contains('free');
      final matchesFree = !_hideFreePlans || !isFreePlan;

      final matchesOverdue =
          !_showOnlyOverdue || store.status == LicenseStatus.overdue;
      final matchesActive =
          !_showOnlyActive || store.status == LicenseStatus.active;

      return matchesSearch && matchesFree && matchesOverdue && matchesActive;
    }).toList();
  }
}

class _FilterSwitch extends StatelessWidget {
  const _FilterSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.onRenewed});

  final StoreInfo store;
  final VoidCallback onRenewed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final statusColor = _statusColor(store.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.surfaceBright,
            child: Text(
              store.storeName.substring(0, 2).toUpperCase(),
              style: textTheme.titleMedium?.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.storeName, style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  store.plan,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Owner: ${store.owner}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ultimo pago: ${store.lastPayment}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(store),
                  style: textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  RenewLicenseDialog.show(
                    context: context,
                    subscriptionId: store.subscriptionId,
                    storeId: store.storeId,
                    storeName: store.storeName,
                    currentPlanId: store.planId,
                    currentPlanName: store.plan,
                    currentStatusId: store.statusId,
                    onRenewed: onRenewed,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentStrong,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  minimumSize: const Size(120, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                label: const Text(
                  'Renovar',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '\$${store.renewalAmount.toStringAsFixed(0)}',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(StoreInfo store) {
    if (store.daysLeft == 0) {
      return 'Vence hoy';
    }
    if (store.daysLeft < 0) {
      return 'Vencida';
    }
    return '${store.daysLeft} dias';
  }

  Color _statusColor(LicenseStatus status) {
    switch (status) {
      case LicenseStatus.active:
        return AppColors.success;
      case LicenseStatus.expiringSoon:
        return AppColors.accentWarm;
      case LicenseStatus.dueToday:
        return AppColors.danger;
      case LicenseStatus.overdue:
        return AppColors.danger;
    }
  }
}
