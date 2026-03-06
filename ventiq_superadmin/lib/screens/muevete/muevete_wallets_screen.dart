import 'package:flutter/material.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteWalletsScreen extends StatefulWidget {
  const MueveteWalletsScreen({super.key});
  @override
  State<MueveteWalletsScreen> createState() => _MueveteWalletsScreenState();
}

class _MueveteWalletsScreenState extends State<MueveteWalletsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _clientW = [];
  List<Map<String, dynamic>> _driverW = [];
  List<Map<String, dynamic>> _txns = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); _loadData(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final r = await Future.wait([MueveteService.getClientWallets(), MueveteService.getDriverWallets(), MueveteService.getTransactions()]);
      if (mounted) setState(() { _clientW = r[0]; _driverW = r[1]; _txns = r[2]; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  String _fmtDate(String? s) {
    if (s == null) return '—';
    final d = DateTime.tryParse(s)?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Color _tipoColor(String? t) {
    switch (t) { case 'recarga': return const Color(0xFF10B981); case 'cobro_viaje': return const Color(0xFF0EA5E9);
      case 'pago_viaje': return const Color(0xFFF59E0B); case 'comision_viaje': return const Color(0xFFEF4444);
      default: return const Color(0xFF94A3B8); }
  }

  IconData _tipoIcon(String? t) {
    switch (t) { case 'recarga': return Icons.add_circle_outline_rounded; case 'cobro_viaje': return Icons.arrow_downward_rounded;
      case 'pago_viaje': return Icons.arrow_upward_rounded; case 'comision_viaje': return Icons.percent_rounded;
      default: return Icons.swap_horiz_rounded; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      body: Column(children: [
        Container(
          color: Colors.white,
          child: SafeArea(child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(children: [
                Builder(builder: (ctx) => IconButton(onPressed: () => Scaffold.of(ctx).openDrawer(), icon: const Icon(Icons.menu_rounded, color: Color(0xFF64748B)))),
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFA78BFA)]), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 18)),
                const SizedBox(width: 10),
                const Text('Billeteras', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                const Spacer(),
                IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B))),
              ]),
            ),
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0)))),
              child: TabBar(
                controller: _tab,
                labelColor: const Color(0xFF6366F1), unselectedLabelColor: const Color(0xFF94A3B8),
                indicatorColor: const Color(0xFF6366F1), indicatorWeight: 2.5,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: [Tab(text: 'Clientes (${_clientW.length})'), Tab(text: 'Conductores (${_driverW.length})'), Tab(text: 'Transacciones (${_txns.length})')],
              ),
            ),
          ])),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(controller: _tab, children: [
                  _buildClientTab(), _buildDriverTab(), _buildTxnTab(),
                ]),
        ),
      ]),
    );
  }

  // ── Clients ────────────────────────────────────────────────────────
  Widget _buildClientTab() {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);
    final totalBal = _clientW.fold<double>(0, (s, w) => s + ((w['balance'] as num?)?.toDouble() ?? 0));
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(children: [
        _summaryRow([_SumItem('Total clientes', '${_clientW.length}', const Color(0xFF6366F1)),
            _SumItem('Balance total', 'Gs. ${totalBal.toStringAsFixed(0)}', const Color(0xFF10B981))]),
        const SizedBox(height: 16),
        _buildWalletTable(
          isDesktop: isDesktop,
          headers: const ['Cliente', 'Email', 'Balance'],
          rows: _clientW.map((w) {
            final bal = (w['balance'] as num?)?.toDouble() ?? 0;
            return [w['user_name'] as String? ?? '—', w['user_email'] as String? ?? '—', 'Gs. ${bal.toStringAsFixed(0)}'];
          }).toList(),
          balanceIdx: 2,
        ),
      ]),
    );
  }

  // ── Drivers ────────────────────────────────────────────────────────
  Widget _buildDriverTab() {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);
    final totalBal = _driverW.fold<double>(0, (s, w) => s + ((w['balance'] as num?)?.toDouble() ?? 0));
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(children: [
        _summaryRow([_SumItem('Total conductores', '${_driverW.length}', const Color(0xFF6366F1)),
            _SumItem('Balance total', 'Gs. ${totalBal.toStringAsFixed(0)}', const Color(0xFF10B981))]),
        const SizedBox(height: 16),
        _buildWalletTable(
          isDesktop: isDesktop,
          headers: const ['Conductor', 'Email', 'Teléfono', 'Balance'],
          rows: _driverW.map((w) {
            final drv = w['drivers'] as Map<String, dynamic>?;
            final bal = (w['balance'] as num?)?.toDouble() ?? 0;
            return [drv?['name'] as String? ?? '—', drv?['email'] as String? ?? '—', drv?['telefono'] as String? ?? '—', 'Gs. ${bal.toStringAsFixed(0)}'];
          }).toList(),
          balanceIdx: 3,
        ),
      ]),
    );
  }

  // ── Transactions ───────────────────────────────────────────────────
  Widget _buildTxnTab() {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: isDesktop ? _txnTable() : _txnCards(),
    );
  }

  Widget _txnTable() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 120),
        child: DataTable(
          headingRowColor: WidgetStateColor.resolveWith((_) => const Color(0xFFF8FAFC)),
          headingRowHeight: 48, dataRowMinHeight: 54, dataRowMaxHeight: 54, columnSpacing: 24,
          columns: const [DataColumn(label: Text('ID', style: _th)), DataColumn(label: Text('Tipo', style: _th)),
            DataColumn(label: Text('Monto', style: _th)), DataColumn(label: Text('Balance Después', style: _th)),
            DataColumn(label: Text('Viaje', style: _th)), DataColumn(label: Text('Descripción', style: _th)),
            DataColumn(label: Text('Fecha', style: _th))],
          rows: _txns.map((t) {
            final tipo = t['tipo'] as String? ?? '—';
            final monto = (t['monto'] as num?)?.toDouble() ?? 0;
            return DataRow(cells: [
              DataCell(Text('#${t['id']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)))),
              DataCell(_tipoBadge(tipo)),
              DataCell(Text('Gs. ${monto.toStringAsFixed(0)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: monto >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444)))),
              DataCell(Text('${t['balance_despues'] ?? '—'}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
              DataCell(Text('${t['viaje_id'] ?? '—'}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
              DataCell(Text(_trunc(t['descripcion'] as String?, 35), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
              DataCell(Text(_fmtDate(t['created_at'] as String?), style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)))),
            ]);
          }).toList(),
        ),
      )),
    );
  }

  Widget _txnCards() {
    return Column(children: _txns.map((t) {
      final tipo = t['tipo'] as String? ?? '—';
      final monto = (t['monto'] as num?)?.toDouble() ?? 0;
      final color = _tipoColor(tipo);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(_tipoIcon(tipo), color: color, size: 20)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tipo.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF334155))),
            Text(_fmtDate(t['created_at'] as String?), style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
          ])),
          Text('Gs. ${monto.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: monto >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444))),
        ]),
      );
    }).toList());
  }

  // ── Shared helpers ─────────────────────────────────────────────────
  Widget _summaryRow(List<_SumItem> items) {
    return Row(children: items.map((s) => Expanded(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(s.value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: s.color)),
      ]),
    ))).toList());
  }

  Widget _buildWalletTable({required bool isDesktop, required List<String> headers, required List<List<String>> rows, required int balanceIdx}) {
    if (!isDesktop) {
      return Column(children: rows.map((r) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), shape: BoxShape.circle),
              child: Center(child: Text(r[0][0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF6366F1))))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r[0], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B))),
            Text(r.length > 2 ? r[1] : '', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ])),
          Text(r[balanceIdx], style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
              color: r[balanceIdx].contains('-') ? const Color(0xFFEF4444) : const Color(0xFF10B981))),
        ]),
      )).toList());
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: DataTable(
        headingRowColor: WidgetStateColor.resolveWith((_) => const Color(0xFFF8FAFC)),
        headingRowHeight: 48, dataRowMinHeight: 50, dataRowMaxHeight: 50, columnSpacing: 28,
        columns: headers.map((h) => DataColumn(label: Text(h, style: _th))).toList(),
        rows: rows.map((r) => DataRow(cells: r.asMap().entries.map((e) {
          final isBal = e.key == balanceIdx;
          return DataCell(Text(e.value, style: TextStyle(fontSize: 13,
              fontWeight: isBal ? FontWeight.w700 : FontWeight.w400,
              color: isBal ? (e.value.contains('-') ? const Color(0xFFEF4444) : const Color(0xFF10B981)) : const Color(0xFF334155))));
        }).toList())).toList(),
      ),
    );
  }

  Widget _tipoBadge(String tipo) {
    final c = _tipoColor(tipo);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_tipoIcon(tipo), size: 13, color: c), const SizedBox(width: 4), Text(tipo.replaceAll('_', ' '), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c))]));
  }

  String _trunc(String? s, int max) { if (s == null) return '—'; return s.length > max ? '${s.substring(0, max)}...' : s; }
  static const _th = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.3);
}

class _SumItem { final String label; final String value; final Color color; const _SumItem(this.label, this.value, this.color); }
