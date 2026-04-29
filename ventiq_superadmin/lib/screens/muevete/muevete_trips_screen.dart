import 'package:flutter/material.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteTripsScreen extends StatefulWidget {
  const MueveteTripsScreen({super.key});
  @override
  State<MueveteTripsScreen> createState() => _MueveteTripsScreenState();
}

class _MueveteTripsScreenState extends State<MueveteTripsScreen> {
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;
  String _filter = 'todos';

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      bool? c;
      if (_filter == 'activos') c = false;
      if (_filter == 'completados') c = true;
      final t = await MueveteService.getTrips(completado: c);
      if (mounted) setState(() { _trips = t; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  String _fmtDate(String? s) {
    if (s == null) return '—';
    final d = DateTime.tryParse(s)?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);
    final completed = _trips.where((t) => t['completado'] == true).length;
    final active = _trips.where((t) => t['completado'] == false).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      body: CustomScrollView(slivers: [
        SliverAppBar(floating: true, backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0.5,
          title: const Text('Viajes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          actions: [IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B))), const SizedBox(width: 8)],
        ),
        SliverPadding(
          padding: EdgeInsets.all(isDesktop ? 32 : 16),
          sliver: SliverList(delegate: SliverChildListDelegate([
            // Stats
            Row(children: [
              _statCard('Total', '${_trips.length}', const Color(0xFF6366F1)),
              _statCard('En curso', '$active', const Color(0xFFF59E0B)),
              _statCard('Completados', '$completed', const Color(0xFF10B981)),
            ]),
            const SizedBox(height: 20),
            // Filter
            _buildFilter(isDesktop),
            const SizedBox(height: 16),
            _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator()))
                : _buildTable(isDesktop),
          ])),
        ),
      ]),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        Container(width: 4, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
        ]),
      ]),
    ));
  }

  Widget _buildFilter(bool isDesktop) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        const Icon(Icons.filter_list_rounded, size: 18, color: Color(0xFF94A3B8)),
        const SizedBox(width: 10),
        ...{'todos': 'Todos', 'activos': 'En curso', 'completados': 'Completados'}.entries.map((e) {
          final sel = _filter == e.key;
          return Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
            label: Text(e.value), selected: sel,
            onSelected: (_) { _filter = e.key; _loadData(); },
            selectedColor: const Color(0xFF6366F1),
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF64748B)),
            backgroundColor: const Color(0xFFF1F5F9), side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ));
        }),
        const Spacer(),
        Text('${_trips.length} viajes', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
      ]),
    );
  }

  Widget _buildTable(bool isDesktop) {
    if (!isDesktop) return _buildMobileCards();
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 120),
        child: DataTable(
          headingRowColor: WidgetStateColor.resolveWith((_) => const Color(0xFFF8FAFC)),
          headingRowHeight: 48, dataRowMinHeight: 54, dataRowMaxHeight: 54, columnSpacing: 28,
          columns: const [
            DataColumn(label: Text('ID', style: _th)), DataColumn(label: Text('Conductor', style: _th)),
            DataColumn(label: Text('Pasajero', style: _th)), DataColumn(label: Text('Progreso', style: _th)),
            DataColumn(label: Text('Fecha', style: _th)),
          ],
          rows: _trips.map((t) {
            final drv = t['drivers'] as Map<String, dynamic>?;
            final comp = t['completado'] as bool? ?? false;
            final estado = t['estado'] as bool? ?? false;
            return DataRow(cells: [
              DataCell(Text('#${t['id']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)))),
              DataCell(Text(drv?['name'] as String? ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF334155)))),
              DataCell(Text(_truncUuid(t['user'] as String?), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
              DataCell(_progressBadge(comp, estado)),
              DataCell(Text(_fmtDate(t['created_at'] as String?), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
            ]);
          }).toList(),
        ),
      )),
    );
  }

  Widget _buildMobileCards() {
    return Column(children: _trips.map((t) {
      final drv = t['drivers'] as Map<String, dynamic>?;
      final comp = t['completado'] as bool? ?? false;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: comp ? const Color(0xFF10B981).withOpacity(0.1) : const Color(0xFFF59E0B).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(comp ? Icons.check_circle_rounded : Icons.route_rounded, color: comp ? const Color(0xFF10B981) : const Color(0xFFF59E0B), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Viaje #${t['id']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B))),
            Text(drv?['name'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            Text(_fmtDate(t['created_at'] as String?), style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
          ])),
          _progressBadge(comp, t['estado'] as bool? ?? false),
        ]),
      );
    }).toList());
  }

  Widget _progressBadge(bool comp, bool estado) {
    final label = comp ? 'Completado' : estado ? 'En marcha' : 'Hacia pickup';
    final color = comp ? const Color(0xFF10B981) : estado ? const Color(0xFF0EA5E9) : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  String _truncUuid(String? u) {
    if (u == null || u.length < 8) return u ?? '—';
    return '${u.substring(0, 8)}...';
  }

  static const _th = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.3);
}
