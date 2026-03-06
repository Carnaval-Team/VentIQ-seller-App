import 'package:flutter/material.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteRequestsScreen extends StatefulWidget {
  const MueveteRequestsScreen({super.key});
  @override
  State<MueveteRequestsScreen> createState() => _MueveteRequestsScreenState();
}

class _MueveteRequestsScreenState extends State<MueveteRequestsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _offers = [];
  bool _isLoading = true;
  String _filter = 'todos';

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _loadData(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final e = _filter == 'todos' ? null : _filter;
      final r = await Future.wait([MueveteService.getRequests(estado: e), MueveteService.getOffers()]);
      if (mounted) setState(() { _requests = r[0]; _offers = r[1]; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  String _fmtDate(String? s) {
    if (s == null) return '—';
    final d = DateTime.tryParse(s)?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Color _estadoColor(String? e) {
    switch (e) { case 'pendiente': return const Color(0xFFF59E0B); case 'aceptada': return const Color(0xFF0EA5E9);
      case 'completada': return const Color(0xFF10B981); case 'cancelada': return const Color(0xFFEF4444);
      case 'rechazada': return const Color(0xFFEF4444); case 'expirada': return const Color(0xFF94A3B8);
      default: return const Color(0xFFCBD5E1); }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      drawer: const AppDrawer(),
      body: Column(children: [
        // Custom header
        Container(
          color: Colors.white,
          child: SafeArea(child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(children: [
                Builder(builder: (ctx) => IconButton(onPressed: () => Scaffold.of(ctx).openDrawer(), icon: const Icon(Icons.menu_rounded, color: Color(0xFF64748B)))),
                const Text('Solicitudes y Ofertas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
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
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                tabs: [Tab(text: 'Solicitudes (${_requests.length})'), Tab(text: 'Ofertas (${_offers.length})')],
              ),
            ),
          ])),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(controller: _tab, children: [
                  _buildRequestsTab(isDesktop),
                  _buildOffersTab(isDesktop),
                ]),
        ),
      ]),
    );
  }

  // ── Requests Tab ───────────────────────────────────────────────────
  Widget _buildRequestsTab(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Filter chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.filter_list_rounded, size: 18, color: Color(0xFF94A3B8)),
            ...{'todos': 'Todos', 'pendiente': 'Pendientes', 'aceptada': 'Aceptadas', 'completada': 'Completadas', 'cancelada': 'Canceladas'}.entries.map((e) {
              final sel = _filter == e.key;
              return ChoiceChip(
                label: Text(e.value), selected: sel,
                onSelected: (_) { _filter = e.key; _loadData(); },
                selectedColor: const Color(0xFF6366F1),
                labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF64748B)),
                backgroundColor: const Color(0xFFF1F5F9), side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              );
            }),
          ]),
        ),
        const SizedBox(height: 16),
        isDesktop ? _requestsTable() : _requestsCards(),
      ]),
    );
  }

  Widget _requestsTable() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 120),
        child: DataTable(
          headingRowColor: WidgetStateColor.resolveWith((_) => const Color(0xFFF8FAFC)),
          headingRowHeight: 48, dataRowMinHeight: 56, dataRowMaxHeight: 56, columnSpacing: 20,
          columns: const [
            DataColumn(label: Text('ID', style: _th)), DataColumn(label: Text('Estado', style: _th)),
            DataColumn(label: Text('Tipo', style: _th)), DataColumn(label: Text('Precio', style: _th)),
            DataColumn(label: Text('Distancia', style: _th)), DataColumn(label: Text('Pago', style: _th)),
            DataColumn(label: Text('Origen', style: _th)), DataColumn(label: Text('Destino', style: _th)),
            DataColumn(label: Text('Fecha', style: _th)),
          ],
          rows: _requests.map((r) {
            final est = r['estado'] as String? ?? '—';
            return DataRow(cells: [
              DataCell(Text('#${r['id']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)))),
              DataCell(_badge(est, _estadoColor(est))),
              DataCell(_vehicleIcon(r['tipo_vehiculo'] as String?)),
              DataCell(Text('${r['precio_oferta'] ?? '—'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)))),
              DataCell(Text(r['distancia_km'] != null ? '${(r['distancia_km'] as num).toStringAsFixed(1)} km' : '—', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
              DataCell(_badge(r['metodo_pago'] as String? ?? 'efectivo', const Color(0xFF8B5CF6))),
              DataCell(Text(_trunc(r['direccion_origen'] as String?, 25), style: const TextStyle(fontSize: 12, color: Color(0xFF475569)))),
              DataCell(Text(_trunc(r['direccion_destino'] as String?, 25), style: const TextStyle(fontSize: 12, color: Color(0xFF475569)))),
              DataCell(Text(_fmtDate(r['created_at'] as String?), style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)))),
            ]);
          }).toList(),
        ),
      )),
    );
  }

  Widget _requestsCards() {
    return Column(children: _requests.map((r) {
      final est = r['estado'] as String? ?? '—';
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('#${r['id']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF6366F1))),
            const Spacer(), _badge(est, _estadoColor(est)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.my_location_rounded, size: 14, color: Color(0xFF10B981)),
            const SizedBox(width: 6),
            Expanded(child: Text(_trunc(r['direccion_origen'] as String?, 40), style: const TextStyle(fontSize: 12, color: Color(0xFF475569)))),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFFEF4444)),
            const SizedBox(width: 6),
            Expanded(child: Text(_trunc(r['direccion_destino'] as String?, 40), style: const TextStyle(fontSize: 12, color: Color(0xFF475569)))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('${r['precio_oferta'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B))),
            const SizedBox(width: 8), _vehicleIcon(r['tipo_vehiculo'] as String?),
            const Spacer(),
            Text(_fmtDate(r['created_at'] as String?), style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
          ]),
        ]),
      );
    }).toList());
  }

  // ── Offers Tab ─────────────────────────────────────────────────────
  Widget _buildOffersTab(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 32 : 16),
      child: isDesktop ? _offersTable() : _offersCards(),
    );
  }

  Widget _offersTable() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 120),
        child: DataTable(
          headingRowColor: WidgetStateColor.resolveWith((_) => const Color(0xFFF8FAFC)),
          headingRowHeight: 48, dataRowMinHeight: 54, dataRowMaxHeight: 54, columnSpacing: 28,
          columns: const [
            DataColumn(label: Text('ID', style: _th)), DataColumn(label: Text('Solicitud', style: _th)),
            DataColumn(label: Text('Conductor', style: _th)), DataColumn(label: Text('Precio', style: _th)),
            DataColumn(label: Text('Tiempo Est.', style: _th)), DataColumn(label: Text('Estado', style: _th)),
            DataColumn(label: Text('Fecha', style: _th)),
          ],
          rows: _offers.map((o) {
            final drv = o['drivers'] as Map<String, dynamic>?;
            final est = o['estado'] as String? ?? '—';
            return DataRow(cells: [
              DataCell(Text('#${o['id']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6366F1)))),
              DataCell(Text('#${o['solicitud_id'] ?? '—'}', style: const TextStyle(fontSize: 13, color: Color(0xFF334155)))),
              DataCell(Text(drv?['name'] as String? ?? '—', style: const TextStyle(fontSize: 13, color: Color(0xFF334155)))),
              DataCell(Text('${o['precio'] ?? '—'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
              DataCell(Text('${o['tiempo_estimado'] ?? '—'} min', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)))),
              DataCell(_badge(est, _estadoColor(est))),
              DataCell(Text(_fmtDate(o['created_at'] as String?), style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)))),
            ]);
          }).toList(),
        ),
      )),
    );
  }

  Widget _offersCards() {
    return Column(children: _offers.map((o) {
      final drv = o['drivers'] as Map<String, dynamic>?;
      final est = o['estado'] as String? ?? '—';
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _estadoColor(est).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.handshake_rounded, color: _estadoColor(est), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Oferta #${o['id']} → Sol. #${o['solicitud_id']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B))),
            Text(drv?['name'] as String? ?? '—', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${o['precio'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1E293B))),
            const SizedBox(height: 4), _badge(est, _estadoColor(est)),
          ]),
        ]),
      );
    }).toList());
  }

  // ── Helpers ─────────────────────────────────────────────────────────
  static const _th = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.3);

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );

  Widget _vehicleIcon(String? tipo) {
    final IconData ic;
    switch (tipo) { case 'moto': ic = Icons.two_wheeler_rounded; break; case 'microbus': ic = Icons.airport_shuttle_rounded; break; default: ic = Icons.directions_car_rounded; }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
      child: Icon(ic, size: 16, color: const Color(0xFF64748B)),
    );
  }

  String _trunc(String? s, int max) {
    if (s == null) return '—';
    return s.length > max ? '${s.substring(0, max)}...' : s;
  }
}
