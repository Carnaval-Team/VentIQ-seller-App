import 'package:flutter/material.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteRatingsScreen extends StatefulWidget {
  const MueveteRatingsScreen({super.key});
  @override
  State<MueveteRatingsScreen> createState() => _MueveteRatingsScreenState();
}

class _MueveteRatingsScreenState extends State<MueveteRatingsScreen> {
  List<Map<String, dynamic>> _ratings = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final r = await MueveteService.getRatings();
      if (mounted) setState(() { _ratings = r; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  String _fmtDate(String? s) {
    if (s == null) return '—';
    final d = DateTime.tryParse(s)?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);
    double avg = 0;
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    if (_ratings.isNotEmpty) {
      int sum = 0;
      for (final r in _ratings) {
        final v = r['rating'] as int? ?? 0;
        sum += v;
        dist[v] = (dist[v] ?? 0) + 1;
      }
      avg = sum / _ratings.length;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      body: CustomScrollView(slivers: [
        SliverAppBar(floating: true, backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0.5,
          title: const Text('Valoraciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          actions: [IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B))), const SizedBox(width: 8)],
        ),
        SliverPadding(
          padding: EdgeInsets.all(isDesktop ? 32 : 16),
          sliver: SliverList(delegate: SliverChildListDelegate([
            _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator()))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Summary header
                    isDesktop
                        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(flex: 2, child: _buildSummaryCard(avg)),
                            const SizedBox(width: 16),
                            Expanded(flex: 3, child: _buildDistributionCard(dist)),
                          ])
                        : Column(children: [_buildSummaryCard(avg), const SizedBox(height: 12), _buildDistributionCard(dist)]),
                    const SizedBox(height: 24),
                    // Table or cards
                    isDesktop ? _buildTable() : _buildCards(),
                  ]),
          ])),
        ),
      ]),
    );
  }

  Widget _buildSummaryCard(double avg) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(children: [
        Text(avg > 0 ? avg.toStringAsFixed(1) : '—',
            style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), height: 1)),
        const SizedBox(height: 8),
        _stars(avg, 28),
        const SizedBox(height: 8),
        Text('${_ratings.length} valoraciones totales',
            style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
      ]),
    );
  }

  Widget _buildDistributionCard(Map<int, int> dist) {
    final total = _ratings.length;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Distribución', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        const SizedBox(height: 14),
        for (int i = 5; i >= 1; i--) _buildDistRow(i, dist[i] ?? 0, total),
      ]),
    );
  }

  Widget _buildDistRow(int star, int count, int total) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 16, child: Text('$star', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFBBF24)),
        const SizedBox(width: 10),
        Expanded(child: Container(
          height: 8, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(4)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft, widthFactor: pct,
            child: Container(decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)]),
              borderRadius: BorderRadius.circular(4),
            )),
          ),
        )),
        const SizedBox(width: 10),
        SizedBox(width: 40, child: Text('$count', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _buildTable() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 120),
        child: DataTable(
          headingRowColor: WidgetStateColor.resolveWith((_) => const Color(0xFFF8FAFC)),
          headingRowHeight: 48, dataRowMinHeight: 56, dataRowMaxHeight: 56, columnSpacing: 28,
          columns: const [
            DataColumn(label: Text('Viaje', style: _th)), DataColumn(label: Text('Conductor', style: _th)),
            DataColumn(label: Text('Rating', style: _th)), DataColumn(label: Text('Comentario', style: _th)),
            DataColumn(label: Text('Fecha', style: _th)),
          ],
          rows: _ratings.map((r) {
            final drv = r['drivers'] as Map<String, dynamic>?;
            final rating = r['rating'] as int? ?? 0;
            final comment = r['comentario'] as String? ?? '';
            return DataRow(cells: [
              DataCell(Text('#${r['viaje_id']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)))),
              DataCell(Text(drv?['name'] as String? ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF334155)))),
              DataCell(_stars(rating.toDouble(), 16)),
              DataCell(Text(comment.isEmpty ? '—' : (comment.length > 50 ? '${comment.substring(0, 50)}...' : comment),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
              DataCell(Text(_fmtDate(r['created_at'] as String?), style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)))),
            ]);
          }).toList(),
        ),
      )),
    );
  }

  Widget _buildCards() {
    return Column(children: _ratings.map((r) {
      final drv = r['drivers'] as Map<String, dynamic>?;
      final rating = r['rating'] as int? ?? 0;
      final comment = r['comentario'] as String?;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _stars(rating.toDouble(), 18),
            const Spacer(),
            Text(_fmtDate(r['created_at'] as String?), style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
          ]),
          const SizedBox(height: 8),
          Text(drv?['name'] as String? ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
          if (comment != null && comment.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comment, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          ],
        ]),
      );
    }).toList());
  }

  Widget _stars(double rating, double size) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, (i) {
      return Icon(i < rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
          color: const Color(0xFFFBBF24), size: size);
    }));
  }

  static const _th = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.3);
}
