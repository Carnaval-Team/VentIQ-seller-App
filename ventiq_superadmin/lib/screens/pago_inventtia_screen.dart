import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/inventtia_payment_model.dart';
import '../services/inventtia_payment_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';

class PagoInventtiaScreen extends StatefulWidget {
  const PagoInventtiaScreen({super.key});

  @override
  State<PagoInventtiaScreen> createState() => _PagoInventtiaScreenState();
}

class _PagoInventtiaScreenState extends State<PagoInventtiaScreen> {
  // Configurar fechas por defecto: primer día del mes actual hasta hoy
  late DateTime _fechaInicio;
  late DateTime _fechaFin;

  InventtiaPaymentModel? _paymentData;
  ExchangeRates? _exchangeRates;
  double _commissionPercentage = 1.0;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeDefaultDates();
    _loadCommissionPercentage();
    _loadReport();
  }

  void _initializeDefaultDates() {
    final now = DateTime.now();
    _fechaInicio = DateTime(now.year, now.month, 1); // Primer día del mes
    _fechaFin = now; // Hoy
  }

  Future<void> _loadCommissionPercentage() async {
    final percentage =
        await InventtiaPaymentService.getInventtiaCommissionPercentage();
    if (mounted) {
      setState(() {
        _commissionPercentage = percentage;
      });
    }
  }

  Future<void> _showConfigDialog() async {
    final controller = TextEditingController(
      text: _commissionPercentage.toString(),
    );

    final result = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Configurar Comisión Inventtia'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '% Comisión',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                    helperText:
                        'Ingrese el porcentaje de comisión (ej: 1.0 para 1%)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Guardar'),
              ),
            ],
          ),
    );

    if (result == true) {
      final newPercentage =
          double.tryParse(controller.text) ?? _commissionPercentage;
      final ok =
          await InventtiaPaymentService.updateInventtiaCommissionPercentage(
            newPercentage,
          );

      if (ok && mounted) {
        setState(() {
          _commissionPercentage = newPercentage;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Porcentaje de comisión actualizado')),
        );
        // Recargar el reporte con el nuevo porcentaje
        _loadReport();
      }
    }
    controller.dispose();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final exchangeRates = await InventtiaPaymentService.getExchangeRates();
      final paymentData = await InventtiaPaymentService.getInventtiaPayments(
        _fechaInicio,
        _fechaFin,
      );

      if (mounted) {
        setState(() {
          _exchangeRates = exchangeRates;
          _paymentData = paymentData;
          _commissionPercentage = paymentData.commissionPercentage;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _setDateRange(String range) {
    final now = DateTime.now();
    setState(() {
      switch (range) {
        case 'week':
          _fechaInicio = now.subtract(const Duration(days: 7));
          _fechaFin = now;
          break;
        case 'month':
          _fechaInicio = DateTime(now.year, now.month, 1);
          _fechaFin = now;
          break;
        case '3months':
          _fechaInicio = DateTime(now.year, now.month - 3, 1);
          _fechaFin = now;
          break;
        case 'year':
          _fechaInicio = DateTime(now.year, 1, 1);
          _fechaFin = now;
          break;
      }
    });
    _loadReport();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isDesktop ? 'Reporte de Pago a Inventtia' : 'Pago a Inventtia',
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Comisión: ${_commissionPercentage.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_exchangeRates != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'USD: ${_exchangeRates!.valorUsd.toStringAsFixed(2)}  |  EUR: ${_exchangeRates!.valorEuro.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showConfigDialog,
            tooltip: 'Configurar comisión',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _buildBody(isDesktop),
    );
  }

  Widget _buildBody(bool isDesktop) {
    if (_isLoading && _paymentData == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generando reporte...'),
          ],
        ),
      );
    }

    if (_errorMessage != null && _paymentData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Error al generar reporte',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReport,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateFilters(),
            const SizedBox(height: 24),
            if (_paymentData != null) ...[
              _buildStatsSection(isDesktop),
              const SizedBox(height: 24),
              _buildCommissionCard(isDesktop),
              const SizedBox(height: 24),
              _buildOrdersList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilters() {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtros de Fecha',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Última semana'),
                  selected: false,
                  onSelected: (_) => _setDateRange('week'),
                ),
                FilterChip(
                  label: const Text('Mes actual'),
                  selected: false,
                  onSelected: (_) => _setDateRange('month'),
                ),
                FilterChip(
                  label: const Text('Últimos 3 meses'),
                  selected: false,
                  onSelected: (_) => _setDateRange('3months'),
                ),
                FilterChip(
                  label: const Text('Este año'),
                  selected: false,
                  onSelected: (_) => _setDateRange('year'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _fechaInicio,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _fechaInicio = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha Inicio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(dateFormat.format(_fechaInicio)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _fechaFin,
                        firstDate: _fechaInicio,
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _fechaFin = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha Fin',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(dateFormat.format(_fechaFin)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loadReport,
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Generar'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(bool isDesktop) {
    final numberFormat = NumberFormat('#,##0.00', 'es');

    return isDesktop
        ? Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total en USD',
                '\$${numberFormat.format(_paymentData!.totalUsd)}',
                Icons.attach_money,
                AppColors.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Total en EUR',
                '€${numberFormat.format(_paymentData!.totalEuro)}',
                Icons.euro,
                AppColors.warning,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Total en CUP',
                '\$${numberFormat.format(_paymentData!.totalCup)}',
                Icons.payments,
                AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Órdenes',
                '${_paymentData!.ordersCount}',
                Icons.receipt,
                AppColors.info,
              ),
            ),
          ],
        )
        : Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total USD',
                    '\$${numberFormat.format(_paymentData!.totalUsd)}',
                    Icons.attach_money,
                    AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Total EUR',
                    '€${numberFormat.format(_paymentData!.totalEuro)}',
                    Icons.euro,
                    AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total CUP',
                    '\$${numberFormat.format(_paymentData!.totalCup)}',
                    Icons.payments,
                    AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Órdenes',
                    '${_paymentData!.ordersCount}',
                    Icons.receipt,
                    AppColors.info,
                  ),
                ),
              ],
            ),
          ],
        );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionCard(bool isDesktop) {
    final numberFormat = NumberFormat('#,##0.00', 'es');

    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comisión a Pagar a Inventtia (${_commissionPercentage.toStringAsFixed(1)}%)',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Calculado sobre órdenes pagadas con Stripe y Tropipay (Estados: Entregando, Completado, Asignado)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            isDesktop
                ? Row(
                  children: [
                    Expanded(
                      child: _buildCommissionDetail(
                        'Comisión USD',
                        '\$${numberFormat.format(_paymentData!.commissionUsd)}',
                        Icons.attach_money,
                        AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildCommissionDetail(
                        'Comisión EUR',
                        '€${numberFormat.format(_paymentData!.commissionEuro)}',
                        Icons.euro,
                        AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildCommissionDetail(
                        'Total en CUP',
                        '\$${numberFormat.format(_paymentData!.commissionCup)}',
                        Icons.payments,
                        AppColors.primary,
                        isHighlighted: true,
                      ),
                    ),
                  ],
                )
                : Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildCommissionDetail(
                            'Comisión USD',
                            '\$${numberFormat.format(_paymentData!.commissionUsd)}',
                            Icons.attach_money,
                            AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildCommissionDetail(
                            'Comisión EUR',
                            '€${numberFormat.format(_paymentData!.commissionEuro)}',
                            Icons.euro,
                            AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildCommissionDetail(
                      'Total a Pagar en CUP',
                      '\$${numberFormat.format(_paymentData!.commissionCup)}',
                      Icons.payments,
                      AppColors.primary,
                      isHighlighted: true,
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionDetail(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlighted ? color.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted ? Border.all(color: color, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: isHighlighted ? 14 : 13,
                    fontWeight:
                        isHighlighted ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isHighlighted ? 24 : 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    if (_paymentData!.orders.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text(
                  'No hay órdenes para el rango seleccionado',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Órdenes (${_paymentData!.orders.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _paymentData!.orders.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final order = _paymentData!.orders[index];
              return _buildOrderItem(order);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(OrderDetail order) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final numberFormat = NumberFormat('#,##0.00', 'es');
    final commission = order.totalInCurrency * (_commissionPercentage / 100);

    Color currencyColor;
    String currencySymbol;

    switch (order.moneda) {
      case 'USD':
        currencyColor = AppColors.success;
        currencySymbol = '\$';
        break;
      case 'EUR':
        currencyColor = AppColors.warning;
        currencySymbol = '€';
        break;
      default:
        currencyColor = AppColors.primary;
        currencySymbol = '\$';
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: currencyColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.receipt, color: currencyColor, size: 24),
      ),
      title: Row(
        children: [
          Text(
            'Orden #${order.orderId}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: currencyColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: currencyColor, width: 1),
            ),
            child: Text(
              order.moneda,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: currencyColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              order.metodoPago,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.info,
              ),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            dateFormat.format(order.createdAt),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total: $currencySymbol${numberFormat.format(order.totalInCurrency)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: currencyColor,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Comisión ${_commissionPercentage.toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            '$currencySymbol${numberFormat.format(commission)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: currencyColor,
            ),
          ),
        ],
      ),
    );
  }
}
