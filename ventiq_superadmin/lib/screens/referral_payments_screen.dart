import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/referral_payments_service.dart';
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
      final rates = await ReferralPaymentsService.getCurrencyRates();
      _valorUsd = rates['usd'] ?? 1;
      _valorEuro = rates['euro'] ?? 1;
      await _reloadReferrers();
    } catch (e) {
      print('❌ Error _loadInitial: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadReferrers() async {
    final referrers = await ReferralPaymentsService.getReferrers();
    final rows = <_ReferrerRow>[];

    for (final u in referrers) {
      final code = u['referal_code'] as String?;
      if (code == null || code.isEmpty) continue;

      final referredCount =
          await ReferralPaymentsService.countReferredUsers(code);
      final orders = await ReferralPaymentsService.getOrdersByReferralCode(
        referalCode: code,
        from: _fromDate,
        to: _toDate,
      );
      final summary = ReferralPaymentsService.computeSummary(
        orders: orders,
        pctNacional: _pctNacional,
        pctInternacional: _pctInternacional,
        valorUsd: _valorUsd,
        valorEuro: _valorEuro,
      );
      rows.add(_ReferrerRow(
        user: u,
        referralCode: code,
        referredCount: referredCount,
        summary: summary,
        orders: orders,
      ));
    }

    // Orden principal: cantidad de referidos (desc). Desempate: comisión CUP (desc).
    rows.sort((a, b) {
      final byReferred = b.referredCount.compareTo(a.referredCount);
      if (byReferred != 0) return byReferred;
      return b.summary.comisionCup.compareTo(a.summary.comisionCup);
    });

    if (mounted) {
      setState(() {
        _referrers = rows;
        if (_selected != null) {
          final match = rows.firstWhere(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Pago a Referidos'),
        actions: [
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
    final total = (o['total'] as num?)?.toDouble() ?? 0;
    final tUsd = (o['totalUsd'] as num?)?.toDouble() ?? 0;
    final tEuro = (o['totalEuro'] as num?)?.toDouble() ?? 0;
    final moneda = (o['moneda'] as String? ?? 'CUP').toUpperCase();
    final metodo = o['metodo_pago'] as String? ?? '—';
    final fecha = o['created_at']?.toString() ?? '';
    final status = o['status'] as String? ?? '';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.info),
      ),
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
                const SizedBox(width: 8),
                Text(
                  '#${o['id']}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(fecha,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
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
            const SizedBox(height: 4),
            Row(
              children: [
                _smallTotal('CUP', total),
                const SizedBox(width: 8),
                _smallTotal('USD', tUsd),
                const SizedBox(width: 8),
                _smallTotal('EUR', tEuro),
              ],
            ),
          ],
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
