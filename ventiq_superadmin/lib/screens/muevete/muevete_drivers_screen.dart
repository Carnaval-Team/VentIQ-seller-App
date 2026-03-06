import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteDriversScreen extends StatefulWidget {
  const MueveteDriversScreen({super.key});
  @override
  State<MueveteDriversScreen> createState() => _MueveteDriversScreenState();
}

class _MueveteDriversScreenState extends State<MueveteDriversScreen> {
  List<Map<String, dynamic>> _drivers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterKyc = 'todos';

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final d = await MueveteService.getDrivers();
      if (mounted) setState(() { _drivers = d; _applyFilters(); _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  void _applyFilters() {
    _filtered = _drivers.where((d) {
      final q = _searchQuery.toLowerCase();
      final name = (d['name'] as String? ?? '').toLowerCase();
      final email = (d['email'] as String? ?? '').toLowerCase();
      final matchQ = q.isEmpty || name.contains(q) || email.contains(q);
      final kyc = d['kyc'] as bool? ?? false;
      final matchK = _filterKyc == 'todos' || (_filterKyc == 'verificado' && kyc) || (_filterKyc == 'no_verificado' && !kyc);
      return matchQ && matchK;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);
    final total = _drivers.length;
    final online = _drivers.where((d) => d['estado'] == true).length;
    final verified = _drivers.where((d) => d['kyc'] == true).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true, backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0.5,
            title: Text('Conductores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            actions: [
              IconButton(onPressed: _loadData, icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
            ],
          ),
          SliverPadding(
            padding: EdgeInsets.all(isDesktop ? 32 : 16),
            sliver: SliverList(delegate: SliverChildListDelegate([
              // Stats strip
              _buildStatsStrip(total, online, verified, isDesktop),
              const SizedBox(height: 20),
              // Filters
              _buildFilterBar(isDesktop),
              const SizedBox(height: 16),
              // Table container
              _isLoading
                  ? const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator()))
                  : _buildTableContainer(isDesktop),
            ])),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(int total, int online, int verified, bool isDesktop) {
    final items = [
      _StatItem('Total', '$total', AppColors.primary),
      _StatItem('En línea', '$online', AppColors.success),
      _StatItem('Verificados', '$verified', AppColors.secondary),
      _StatItem('Sin verificar', '${total - verified}', AppColors.warning),
    ];
    return Row(
      children: items.map((s) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(width: 4, height: 32, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.value, style: TextStyle(fontSize: isDesktop ? 22 : 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                Text(s.label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
              ]),
            ],
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildFilterBar(bool isDesktop) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 12, runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: isDesktop ? 320 : double.infinity,
            height: 42,
            child: TextField(
              onChanged: (v) { _searchQuery = v; setState(() => _applyFilters()); },
              decoration: InputDecoration(
                hintText: 'Buscar conductor...',
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                filled: true, fillColor: AppColors.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
          ),
          ..._buildChipFilters(),
          Text('${_filtered.length} resultados', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  List<Widget> _buildChipFilters() {
    final opts = {'todos': 'Todos', 'verificado': 'Verificados', 'no_verificado': 'Pendientes'};
    return opts.entries.map((e) {
      final sel = _filterKyc == e.key;
      return ChoiceChip(
        label: Text(e.value),
        selected: sel,
        onSelected: (_) { _filterKyc = e.key; setState(() => _applyFilters()); },
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : AppColors.textSecondary),
        backgroundColor: AppColors.surfaceVariant,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      );
    }).toList();
  }

  Widget _buildTableContainer(bool isDesktop) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: isDesktop ? _buildDesktopTable() : _buildMobileCards(),
    );
  }

  Widget _buildDesktopTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 120),
        child: DataTable(
          headingRowColor: WidgetStateColor.resolveWith((_) => AppColors.surfaceVariant),
          headingRowHeight: 48,
          dataRowMinHeight: 56, dataRowMaxHeight: 56,
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('Conductor', style: _thStyle)),
            DataColumn(label: Text('Contacto', style: _thStyle)),
            DataColumn(label: Text('Estado', style: _thStyle)),
            DataColumn(label: Text('Verificación', style: _thStyle)),
            DataColumn(label: Text('Vehículo', style: _thStyle)),
            DataColumn(label: Text('Acciones', style: _thStyle)),
          ],
          rows: _filtered.map((d) {
            final online = d['estado'] as bool? ?? false;
            final kyc = d['kyc'] as bool? ?? false;
            final revisado = d['revisado'] as bool? ?? false;
            final veh = d['vehiculos'] as Map<String, dynamic>?;
            final vStr = veh != null ? '${veh['marca'] ?? ''} ${veh['modelo'] ?? ''}' : '—';
            final vChapa = veh?['chapa'] as String? ?? '';

            return DataRow(cells: [
              DataCell(Row(children: [
                _avatar(d['name'] as String?, online),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(d['name'] as String? ?? '—', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                  Text('ID: ${d['id']}', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
              ])),
              DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(d['email'] as String? ?? '—', style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                Text(d['telefono'] as String? ?? '—', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ])),
              DataCell(_statusBadge(online ? 'En línea' : 'Desconectado', online ? AppColors.success : AppColors.textSecondary)),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                _statusBadge(kyc ? 'Verificado' : 'Pendiente', kyc ? AppColors.secondary : AppColors.warning),
                if (!revisado) ...[const SizedBox(width: 6), _statusBadge('Sin revisar', AppColors.error)],
              ])),
              DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(vStr, style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                if (vChapa.isNotEmpty) Text(vChapa, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ])),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                _actionBtn(Icons.visibility_rounded, 'Ver detalle', () => _showDriverDetail(d)),
                if (!kyc) _actionBtn(Icons.check_circle_rounded, 'Aprobar', () => _approveKyc(d), color: AppColors.success),
              ])),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileCards() {
    return ListView.separated(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.surfaceVariant),
      itemBuilder: (_, i) {
        final d = _filtered[i];
        final online = d['estado'] as bool? ?? false;
        final kyc = d['kyc'] as bool? ?? false;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _avatar(d['name'] as String?, online),
          title: Text(d['name'] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(d['email'] as String? ?? '', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing: _statusBadge(kyc ? 'Verificado' : 'Pendiente', kyc ? AppColors.secondary : AppColors.warning),
          onTap: () => _showDriverDetail(d),
        );
      },
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────
  static const _thStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B), letterSpacing: 0.3);

  Widget _avatar(String? name, bool online) {
    final initial = (name != null && name.isNotEmpty) ? name[0].toUpperCase() : '?';
    return Stack(
      children: [
        CircleAvatar(radius: 18, backgroundColor: AppColors.primary.withOpacity(0.1),
            child: Text(initial, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 14))),
        Positioned(right: 0, bottom: 0, child: Container(
          width: 10, height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: online ? AppColors.success : AppColors.textHint,
              border: Border.all(color: Colors.white, width: 2)),
        )),
      ],
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _actionBtn(IconData icon, String tooltip, VoidCallback onTap, {Color color = const Color(0xFF64748B)}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6), margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  // ── Detail Dialog ──────────────────────────────────────────────────
  void _showDriverDetail(Map<String, dynamic> d) {
    final kyc = d['kyc'] as bool? ?? false;
    final docF = d['doc_frente_url'] as String?;
    final docD = d['doc_dorso_url'] as String?;
    final veh = d['vehiculos'] as Map<String, dynamic>?;

    showDialog(context: context, builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _avatar(d['name'] as String?, d['estado'] as bool? ?? false),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['name'] as String? ?? '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                Text(d['email'] as String? ?? '', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 20),
            _detailRow('Teléfono', d['telefono'] as String? ?? '—'),
            _detailRow('Tipo doc.', d['tipo_documento'] as String? ?? '—'),
            _detailRow('KYC', kyc ? 'Verificado' : 'Pendiente'),
            _detailRow('Revisado', (d['revisado'] as bool? ?? false) ? 'Sí' : 'No'),
            if (d['motivo'] != null) _detailRow('Motivo rechazo', d['motivo'] as String),
            if (veh != null) ...[
              const SizedBox(height: 12),
              Text('Vehículo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              _detailRow('Marca/Modelo', '${veh['marca'] ?? ''} ${veh['modelo'] ?? ''}'),
              _detailRow('Chapa', veh['chapa'] as String? ?? '—'),
              _detailRow('Color', veh['color'] as String? ?? '—'),
            ],
            const SizedBox(height: 16),
            Text('Documentos', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _docImage('Frente', docF)),
              const SizedBox(width: 12),
              Expanded(child: _docImage('Dorso', docD)),
            ]),
            const SizedBox(height: 20),
            if (!kyc) Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); _rejectKyc(d); },
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Rechazar'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(context); _approveKyc(d); },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Aprobar KYC'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
            ]),
          ]),
        ),
      ),
    ));
  }

  Widget _detailRow(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
      Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: AppColors.textPrimary))),
    ]));
  }

  Widget _docImage(String label, String? url) {
    return Column(children: [
      Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      Container(
        height: 160, width: double.infinity,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: AppColors.surfaceVariant, border: Border.all(color: AppColors.divider)),
        clipBehavior: Clip.antiAlias,
        child: url != null && url.isNotEmpty
            ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_rounded, color: AppColors.textHint, size: 32)))
            : Center(child: Text('Sin documento', style: TextStyle(color: AppColors.textHint, fontSize: 12))),
      ),
    ]);
  }

  Future<void> _approveKyc(Map<String, dynamic> d) async {
    await MueveteService.approveDriverKyc(d['id'] as int);
    _loadData();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${d['name']} verificado'), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  Future<void> _rejectKyc(Map<String, dynamic> d) async {
    final ctrl = TextEditingController();
    final motivo = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Motivo de rechazo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: TextField(controller: ctrl, maxLines: 3, decoration: InputDecoration(hintText: 'Describe el motivo...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white), child: const Text('Rechazar')),
      ],
    ));
    ctrl.dispose();
    if (motivo != null && motivo.isNotEmpty) {
      await MueveteService.rejectDriverKyc(d['id'] as int, motivo);
      _loadData();
    }
  }
}

class _StatItem {
  final String label; final String value; final Color color;
  const _StatItem(this.label, this.value, this.color);
}
