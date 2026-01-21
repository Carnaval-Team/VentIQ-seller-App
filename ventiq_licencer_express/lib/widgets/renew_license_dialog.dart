import 'package:flutter/material.dart';

import '../models/subscription_models.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

class RenewLicenseDialog extends StatefulWidget {
  const RenewLicenseDialog({
    super.key,
    required this.subscriptionId,
    required this.storeId,
    required this.storeName,
    required this.currentPlanId,
    required this.currentPlanName,
    required this.currentStatusId,
    required this.onRenewed,
  });

  final int subscriptionId;
  final int storeId;
  final String storeName;
  final int? currentPlanId;
  final String currentPlanName;
  final int? currentStatusId;
  final VoidCallback onRenewed;

  static Future<void> show({
    required BuildContext context,
    required int? subscriptionId,
    required int? storeId,
    required String storeName,
    required int? currentPlanId,
    required String currentPlanName,
    required int? currentStatusId,
    required VoidCallback onRenewed,
  }) async {
    if (subscriptionId == null || storeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró la suscripción para renovar.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return RenewLicenseDialog(
          subscriptionId: subscriptionId,
          storeId: storeId,
          storeName: storeName,
          currentPlanId: currentPlanId,
          currentPlanName: currentPlanName,
          currentStatusId: currentStatusId,
          onRenewed: onRenewed,
        );
      },
    );
  }

  @override
  State<RenewLicenseDialog> createState() => _RenewLicenseDialogState();
}

class _RenewLicenseDialogState extends State<RenewLicenseDialog> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  List<SubscriptionPlan> _plans = [];
  SubscriptionPlan? _selectedPlan;
  DateTime? _endDate;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await _subscriptionService.fetchActivePlans();
      SubscriptionPlan? selected;
      if (plans.isNotEmpty) {
        selected = plans.firstWhere(
          (plan) => plan.id == widget.currentPlanId,
          orElse: () => plans.first,
        );
      }
      if (mounted) {
        setState(() {
          _plans = plans;
          _selectedPlan = selected;
          _endDate = _calculateEndDate(selected);
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar planes: $error'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  DateTime _calculateEndDate(SubscriptionPlan? plan) {
    final now = DateTime.now();
    final days = plan?.durationDays ?? 30;
    return DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }

  Future<void> _pickDate() async {
    final current = _endDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null && mounted) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _confirmRenewal() async {
    if (_selectedPlan == null || _selectedPlan!.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un plan valido.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    if (_endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona la fecha de vencimiento.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await _subscriptionService.renewSubscription(
        subscriptionId: widget.subscriptionId,
        storeId: widget.storeId,
        previousPlanId: widget.currentPlanId,
        newPlanId: _selectedPlan!.id!,
        previousStatusId: widget.currentStatusId,
        newEndDate: _endDate!,
        planAmount: _selectedPlan!.price,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onRenewed();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Renovacion completada'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al renovar: $error'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Renovar licencia'),
        content: const SizedBox(
          height: 120,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Renovar licencia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tienda: ${widget.storeName}', style: textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(
              'Plan actual: ${widget.currentPlanName}',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Text('Selecciona el plan:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<SubscriptionPlan>(
              value: _selectedPlan,
              decoration: const InputDecoration(
                labelText: 'Plan',
                border: OutlineInputBorder(),
              ),
              items: _plans
                  .map(
                    (plan) => DropdownMenuItem(
                      value: plan,
                      child: Text(
                        '${plan.name} - \$${plan.price.toStringAsFixed(0)}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (plan) {
                setState(() {
                  _selectedPlan = plan;
                  _endDate = _calculateEndDate(plan);
                });
              },
            ),
            const SizedBox(height: 16),
            const Text('Fecha de vencimiento:'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDate(_endDate ?? DateTime.now())),
                    const Icon(Icons.calendar_today, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border.withOpacity(0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Monto mensual', style: textTheme.bodySmall),
                  Text(
                    _formatCurrency(_selectedPlan?.price ?? 0),
                    style: textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _confirmRenewal,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accentStrong,
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirmar renovacion'),
        ),
      ],
    );
  }

  String _formatCurrency(double value) {
    return '\$${value.toStringAsFixed(0)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
