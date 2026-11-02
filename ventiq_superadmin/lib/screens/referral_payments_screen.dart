import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/referral_payments_service.dart';
import '../services/referral_pdf_service.dart';
import '../widgets/app_drawer.dart';

class ReferralPaymentsScreen extends StatefulWidget {
  const ReferralPaymentsScreen({Key? key}) : super(key: key);

  @override
  State<ReferralPaymentsScreen> createState() => _ReferralPaymentsScreenState();
}

class _ReferralPaymentsScreenState extends State<ReferralPaymentsScreen> {
  late DateTime _fromDate;
  late DateTime _toDate;

  double _pctInternacional = 2.0;
  double _pctNacional = 1.0;

  final TextEditingController _intlCtrl = TextEditingController(text: '2');
  final TextEditingController _natCtrl = TextEditingController(text: '1');

  bool _isLoading = true;
  bool _isLoadingOrders = false;

  double _valorUsd = 1;
  double _valorEuro = 1;

  List<_ReferrerRow> _referrers = [];
  _ReferrerRow? _selected;
  List<Map<String, dynamic>> _selectedOrders = [];

  bool _excludeZeroPayments = true;
  Set<int> _excludedProductIds = {};

  final NumberFormat _moneyFmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
    _loadInitial();
  }

  @override
  void dispose() {
    _intlCtrl.dispose();
    _natCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    try {
      // Tasas + referidores + órdenes + exclusiones en paralelo (vía dashboard).
      await _reloadReferrers(refreshRates: true);
    } catch (e) {
      print('❌ Error _loadInitial: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadReferrers({bool refreshRates = false}) async {
    final dashboard = await ReferralPaymentsService.loadReferrerDashboard(
      from: _fromDate,
      to: _toDate,
      pctNacional: _pctNacional,
      pctInternacional: _pctInternacional,
      valorUsd: refreshRates ? null : _valorUsd,
      valorEuro: refreshRates ? null : _valorEuro,
    );

    final rows = dashboard.referrers
        .map(
          (d) => _ReferrerRow(
            user: d.user,
            referralCode: d.referralCode,
            referredCount: d.referredCount,
            summary: d.summary,
            orders: d.orders,
          ),
        )
        .toList();

    final filteredRows = _excludeZeroPayments
        ? rows.where((row) => row.summary.comisionCup > 0).toList()
        : rows;

    if (mounted) {
      setState(() {
        _valorUsd = dashboard.valorUsd;
        _valorEuro = dashboard.valorEuro;
        _excludedProductIds = dashboard.excludedProductIds;
        _referrers = filteredRows;
        if (_selected != null) {
          final match = filteredRows.firstWhere(
            (r) => r.referralCode == _selected!.referralCode,
            orElse: () => _ReferrerRow.empty(),
          );
          if (match.referralCode.isEmpty) {
            _selected = null;
            _selectedOrders = [];
          } else {
            _selected = match;
            _selectedOrders = match.orders;
          }
        }
      });
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
    await _onFiltersChanged();
  }

  Future<void> _onFiltersChanged() async {
    setState(() => _isLoading = true);
    final intl = double.tryParse(_intlCtrl.text.replaceAll(',', '.'));
    final nat = double.tryParse(_natCtrl.text.replaceAll(',', '.'));
    if (intl != null) _pctInternacional = intl;
    if (nat != null) _pctNacional = nat;
    try {
      await _reloadReferrers();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSelectReferrer(_ReferrerRow row) {
    setState(() {
      _selected = row;
      _selectedOrders = row.orders;
    });
  }

  Future<void> _exportToPdf() async {
    if (_selected == null) return;

    try {
      await ReferralPdfService.generateAndSaveReferralReport(
        referrer: _selected!.user,
        referralCode: _selected!.referralCode,
        referredCount: _selected!.referredCount,
        summary: _selected!.summary,
        orders: _selected!.orders,
        fromDate: _fromDate,
        toDate: _toDate,
        valorUsd: _valorUsd,
        valorEuro: _valorEuro,
        pctNacional: _pctNacional,
        pctInternacional: _pctInternacional,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openExclusionsManager() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ExclusionsDialog(
        onChanged: () async {
          await _onFiltersChanged();
        },
      ),
    );
  }

  Future<void> _openOrderDetail(Map<String, dynamic> order) async {
    final orderId = (order['id'] as num?)?.toInt();
    if (orderId == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<ReferralOrderLine> lines = [];
    try {
      lines = await ReferralPaymentsService.getOrderLines(
        orderId,
        excludedProductIds: _excludedProductIds,
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar detalle: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showDialog<void>(
      context: context,
      builder: (ctx) => _OrderDetailDialog(
        order: order,
        lines: lines,
        moneyFmt: _moneyFmt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pago a Referidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.block),
            tooltip: 'Productos excluidos',
            onPressed: _isLoading ? null : _openExclusionsManager,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _isLoading ? null : _onFiltersChanged,
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          _buildFiltersBar(),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 720;
                      if (isNarrow) {
                        return _buildNarrowLayout();
                      }
                      return Row(
                        children: [
                          Expanded(flex: 6, child: _buildReferrerList()),
                          const VerticalDivider(width: 1),
                          Expanded(flex: 4, child: _buildOrdersPanel()),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildDateButton(
            label: 'Desde',
            date: _fromDate,
            onTap: () => _pickDate(isFrom: true),
          ),
          _buildDateButton(
            label: 'Hasta',
            date: _toDate,
            onTap: () => _pickDate(isFrom: false),
          ),
          _buildPercentField(
            label: '% Internacionales',
            controller: _intlCtrl,
            color: AppColors.warning,
          ),
          _buildPercentField(
            label: '% Nacionales',
            controller: _natCtrl,
            color: AppColors.primary,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Aplicar'),
            onPressed: _isLoading ? null : _onFiltersChanged,
          ),
          _buildExcludeZeroCheckbox(),
          OutlinedButton.icon(
            icon: const Icon(Icons.block, size: 18),
            label: const Text('Productos excluidos'),
            onPressed: _isLoading ? null : _openExclusionsManager,
          ),
          _buildRatesChip(),
        ],
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.info),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                Text(
                  DateFormat('dd/MM/yyyy').format(date),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPercentField({
    required String label,
    required TextEditingController controller,
    required Color color,
  }) {
    return SizedBox(
      width: 180,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixText: '%',
          prefixIcon: Icon(Icons.percent, color: color, size: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildRatesChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_money, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            'USD: ${_moneyFmt.format(_valorUsd)}  |  EUR: ${_moneyFmt.format(_valorEuro)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExcludeZeroCheckbox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _excludeZeroPayments 
            ? AppColors.primary.withOpacity(0.1)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _excludeZeroPayments 
              ? AppColors.primary
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _excludeZeroPayments = !_excludeZeroPayments;
          });
          _onFiltersChanged();
        },
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _excludeZeroPayments ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: _excludeZeroPayments ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            const Text(
              'Excluir \$0',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowLayout() {
    if (_selected != null) {
      return Column(
        children: [
          Container(
            color: Colors.white,
            child: ListTile(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _selected = null;
                  _selectedOrders = [];
                }),
              ),
              title: Text(
                _selected!.user['name'] ?? _selected!.user['email'] ?? '—',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Código: ${_selected!.referralCode}'),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildOrdersPanel()),
        ],
      );
    }
    return _buildReferrerList();
  }

  Widget _buildReferrerList() {
    if (_referrers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay referidores con códigos asignados.'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _referrers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = _referrers[index];
        return _buildReferrerCard(row);
      },
    );
  }

  Widget _buildReferrerCard(_ReferrerRow row) {
    final isSelected = _selected?.referralCode == row.referralCode;
    final s = row.summary;
    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.transparent,
          width: isSelected ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: () => _onSelectReferrer(row),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: const Icon(Icons.person,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.user['name'] ?? row.user['email'] ?? '—',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row.user['email'] ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _codeBadge(row.referralCode),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statChip(
                    icon: Icons.group_add,
                    label: 'Referidos',
                    value: '${row.referredCount}',
                    color: AppColors.info,
                  ),
                  _statChip(
                    icon: Icons.receipt_long,
                    label: 'Órdenes',
                    value: '${s.totalOrders}',
                    color: AppColors.primary,
                  ),
                  _statChip(
                    icon: Icons.flag,
                    label: 'Nac.',
                    value: '${s.nacionalCount}',
                    color: AppColors.success,
                  ),
                  _statChip(
                    icon: Icons.public,
                    label: 'Intl.',
                    value: '${s.internacionalCount}',
                    color: AppColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              _buildTotalsRow(s),
              const SizedBox(height: 10),
              _buildPayoutBox(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeBadge(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text('$label: ',
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.9))),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildTotalsRow(ReferralSummary s) {
    return Row(
      children: [
        Expanded(
          child: _miniTotal(
            label: 'Total CUP',
            value: _moneyFmt.format(s.totalCup),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniTotal(
            label: 'Total USD',
            value: _moneyFmt.format(s.totalUsd),
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _miniTotal(
            label: 'Total EUR',
            value: _moneyFmt.format(s.totalEuro),
            color: AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _miniTotal({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, color: color.withOpacity(0.9))),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildPayoutBox(ReferralSummary s) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'A pagar al referido',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _payoutItem(
                  label: 'CUP',
                  value: _moneyFmt.format(s.comisionCup),
                ),
              ),
              Expanded(
                child: _payoutItem(
                  label: 'USD',
                  value: _moneyFmt.format(s.totalReferidoUsd),
                ),
              ),
              Expanded(
                child: _payoutItem(
                  label: 'EUR',
                  value: _moneyFmt.format(s.totalReferidoEuro),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _payoutItem({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w500)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildOrdersPanel() {
    if (_selected == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app, size: 48, color: AppColors.primary),
                SizedBox(height: 12),
                Text(
                  'Selecciona un referido para ver sus órdenes',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.surfaceVariant,
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selected!.user['name'] ??
                            _selected!.user['email'] ??
                            '—',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Órdenes: ${_selectedOrders.length}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf),
                  tooltip: 'Exportar a PDF',
                  onPressed: _exportToPdf,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    foregroundColor: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoadingOrders
                ? const Center(child: CircularProgressIndicator())
                : _selectedOrders.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Sin órdenes en este rango.'),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: _selectedOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final o = _selectedOrders[index];
                          return _buildOrderTile(o);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTile(Map<String, dynamic> o) {
    final isIntl = ReferralPaymentsService.isInternationalOrder(o);
    final color = isIntl ? AppColors.warning : AppColors.success;
    final hasExclusions = o['_has_exclusions'] == true;
    final eligibleCup = (o['_eligible_total'] as num?)?.toDouble() ??
        (o['total'] as num?)?.toDouble() ??
        0;
    final eligibleUsd = (o['_eligible_totalUsd'] as num?)?.toDouble() ??
        (o['totalUsd'] as num?)?.toDouble() ??
        0;
    final eligibleEuro = (o['_eligible_totalEuro'] as num?)?.toDouble() ??
        (o['totalEuro'] as num?)?.toDouble() ??
        0;
    final moneda = (o['moneda'] as String? ?? 'CUP').toUpperCase();
    final metodo = o['metodo_pago'] as String? ?? '—';
    final fecha = o['created_at']?.toString() ?? '';
    final status = o['status'] as String? ?? '';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: hasExclusions ? AppColors.warning : AppColors.info,
        ),
      ),
      child: InkWell(
        onTap: () => _openOrderDetail(o),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isIntl ? 'Internacional' : 'Nacional',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ),
                  if (hasExclusions) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Con exclusiones',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    '#${o['id']}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$metodo • $moneda',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    status,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                fecha,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _smallTotal('CUP', eligibleCup),
                  const SizedBox(width: 8),
                  _smallTotal('USD', eligibleUsd),
                  const SizedBox(width: 8),
                  _smallTotal('EUR', eligibleEuro),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallTotal(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label ${_moneyFmt.format(value)}',
        style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary),
      ),
    );
  }
}

class _ReferrerRow {
  final Map<String, dynamic> user;
  final String referralCode;
  final int referredCount;
  final ReferralSummary summary;
  final List<Map<String, dynamic>> orders;

  _ReferrerRow({
    required this.user,
    required this.referralCode,
    required this.referredCount,
    required this.summary,
    required this.orders,
  });

  factory _ReferrerRow.empty() => _ReferrerRow(
        user: const {},
        referralCode: '',
        referredCount: 0,
        summary: ReferralSummary(
          totalCup: 0,
          totalUsd: 0,
          totalEuro: 0,
          nacionalCount: 0,
          internacionalCount: 0,
          comisionCup: 0,
          comisionUsd: 0,
          comisionEuro: 0,
          totalReferidoUsd: 0,
          totalReferidoEuro: 0,
        ),
        orders: const [],
      );
}

class _OrderDetailDialog extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<ReferralOrderLine> lines;
  final NumberFormat moneyFmt;

  const _OrderDetailDialog({
    required this.order,
    required this.lines,
    required this.moneyFmt,
  });

  @override
  Widget build(BuildContext context) {
    final orderTotal = (order['total'] as num?)?.toDouble() ?? 0;
    final orderUsd = (order['totalUsd'] as num?)?.toDouble() ?? 0;
    final orderEuro = (order['totalEuro'] as num?)?.toDouble() ?? 0;

    double sumAllCup = 0;
    double sumEligibleCup = 0;
    double sumEligibleUsd = 0;
    double sumEligibleEuro = 0;
    for (final line in lines) {
      sumAllCup += line.lineCup;
      if (!line.isExcluded) {
        sumEligibleCup += line.lineCup;
        sumEligibleUsd += line.lineUsd;
        sumEligibleEuro += line.lineEuro;
      }
    }

    final excludedCount = lines.where((l) => l.isExcluded).length;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Orden #${order['id']}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${order['created_at'] ?? ''} • ${order['metodo_pago'] ?? '—'} • ${(order['moneda'] as String? ?? 'CUP').toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('Total orden CUP', moneyFmt.format(orderTotal)),
                  _chip('Total orden USD', moneyFmt.format(orderUsd)),
                  _chip('Total orden EUR', moneyFmt.format(orderEuro)),
                  _chip(
                    'Acumula CUP',
                    moneyFmt.format(sumEligibleCup),
                    highlight: true,
                  ),
                  if (excludedCount > 0)
                    _chip(
                      'Excluidos',
                      '$excludedCount producto(s)',
                      warning: true,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: lines.isEmpty
                  ? const Center(child: Text('Sin líneas de producto.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: lines.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        return _buildLineCard(line);
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Suma líneas: ${moneyFmt.format(sumAllCup)} CUP'
                      '${excludedCount > 0 ? '  |  Comisionable: ${moneyFmt.format(sumEligibleCup)} CUP / ${moneyFmt.format(sumEligibleUsd)} USD / ${moneyFmt.format(sumEligibleEuro)} EUR' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value,
      {bool highlight = false, bool warning = false}) {
    final color = warning
        ? AppColors.warning
        : highlight
            ? AppColors.primary
            : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildLineCard(ReferralOrderLine line) {
    final muted = line.isExcluded;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: muted
            ? AppColors.warning.withOpacity(0.06)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: muted
              ? AppColors.warning.withOpacity(0.35)
              : AppColors.info.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.productName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: muted
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    decoration:
                        muted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (line.isExcluded)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Excluido',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Cant: ${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity}'
            '  •  P.unit CUP ${moneyFmt.format(line.unitPriceCup)}'
            '${line.extra > 0 ? '  •  Extra ${moneyFmt.format(line.extra)}' : ''}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _lineAmt('CUP', line.lineCup, muted),
              const SizedBox(width: 8),
              _lineAmt('USD', line.lineUsd, muted),
              const SizedBox(width: 8),
              _lineAmt('EUR', line.lineEuro, muted),
              if (muted) ...[
                const Spacer(),
                const Text(
                  'No acumula',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _lineAmt(String label, double value, bool muted) {
    return Text(
      '$label ${moneyFmt.format(value)}',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: muted ? AppColors.textSecondary : AppColors.textPrimary,
        decoration: muted ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

class _ExclusionsDialog extends StatefulWidget {
  final Future<void> Function() onChanged;

  const _ExclusionsDialog({required this.onChanged});

  @override
  State<_ExclusionsDialog> createState() => _ExclusionsDialogState();
}

class _ExclusionsDialogState extends State<_ExclusionsDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _searching = false;
  bool _busy = false;
  List<Map<String, dynamic>> _excluded = [];
  List<Map<String, dynamic>> _searchResults = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ReferralPaymentsService.getExcludedProducts();
      if (mounted) {
        setState(() {
          _excluded = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo cargar. ¿Aplicaste sql_updates/referral_excluded_products.sql?\n$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final rows =
          await ReferralPaymentsService.searchProducts(_searchCtrl.text);
      final excludedIds =
          _excluded.map((e) => (e['product_id'] as num).toInt()).toSet();
      if (mounted) {
        setState(() {
          _searchResults = rows
              .where((p) => !excludedIds.contains((p['id'] as num).toInt()))
              .toList();
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error buscando: $e')),
        );
      }
    }
  }

  Future<void> _add(int productId) async {
    setState(() => _busy = true);
    try {
      await ReferralPaymentsService.addExcludedProduct(productId);
      await _load();
      await widget.onChanged();
      if (mounted) {
        setState(() {
          _searchResults =
              _searchResults.where((p) => (p['id'] as num).toInt() != productId).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al excluir: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int productId) async {
    setState(() => _busy = true);
    try {
      await ReferralPaymentsService.removeExcludedProduct(productId);
      await _load();
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al quitar exclusión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.block, color: AppColors.warning),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Productos excluidos del pago a referidos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Estos productos no acumulan para la comisión. Siguen apareciendo en el detalle de la orden marcados como excluidos.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Buscar producto para excluir…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: const Icon(Icons.search, size: 18),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _busy || _searching ? null : _search,
                    child: _searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Buscar'),
                  ),
                ],
              ),
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final p = _searchResults[index];
                    final id = (p['id'] as num).toInt();
                    return ListTile(
                      dense: true,
                      title: Text(p['name']?.toString() ?? 'Producto #$id'),
                      subtitle: Text('ID $id'),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline,
                            color: AppColors.warning),
                        tooltip: 'Excluir',
                        onPressed: _busy ? null : () => _add(id),
                      ),
                    );
                  },
                ),
              ),
            ],
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Excluidos actuales (${_excluded.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                      : _excluded.isEmpty
                          ? const Center(
                              child: Text(
                                'Ningún producto excluido.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _excluded.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final row = _excluded[index];
                                final id = (row['product_id'] as num).toInt();
                                return ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: AppColors.warning.withOpacity(0.3),
                                    ),
                                  ),
                                  title: Text(row['name']?.toString() ?? 'Producto #$id'),
                                  subtitle: Text('ID $id'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    tooltip: 'Quitar exclusión',
                                    onPressed: _busy ? null : () => _remove(id),
                                  ),
                                );
                              },
                            ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
