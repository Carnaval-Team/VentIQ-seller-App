import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

class MueveteKycScreen extends StatefulWidget {
  const MueveteKycScreen({super.key});
  @override
  State<MueveteKycScreen> createState() => _MueveteKycScreenState();
}

class _MueveteKycScreenState extends State<MueveteKycScreen> {
  List<Map<String, dynamic>> _pending = [];
  bool _isLoading = true;

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final d = await MueveteService.getPendingKycDrivers();
      if (mounted) setState(() { _pending = d; _isLoading = false; });
    } catch (_) { if (mounted) setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      body: CustomScrollView(slivers: [
        SliverAppBar(floating: true, backgroundColor: Colors.white, surfaceTintColor: Colors.white, elevation: 0.5,
          title: Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(
              gradient: _pending.isNotEmpty ? LinearGradient(colors: [AppColors.error, AppColors.error.withOpacity(0.7)]) : LinearGradient(colors: [AppColors.success, AppColors.success.withOpacity(0.7)]),
              borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 18)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Verificación KYC', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text('${_pending.length} pendientes', style: TextStyle(fontSize: 12, color: _pending.isNotEmpty ? AppColors.error : AppColors.success)),
            ]),
          ]),
          actions: [IconButton(onPressed: _loadData, icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary)), const SizedBox(width: 8)],
        ),
        SliverPadding(
          padding: EdgeInsets.all(isDesktop ? 32 : 16),
          sliver: _isLoading
              ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              : _pending.isEmpty
                  ? SliverFillRemaining(child: _buildEmptyState())
                  : SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: isDesktop ? 480 : 600,
                        childAspectRatio: isDesktop ? 0.68 : 0.72,
                        crossAxisSpacing: 16, mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _buildKycCard(_pending[i]),
                        childCount: _pending.length,
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(Icons.verified_rounded, size: 48, color: AppColors.success),
      ),
      const SizedBox(height: 20),
      Text('Todo verificado', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 8),
      Text('No hay conductores pendientes de revisión', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
    ]));
  }

  Widget _buildKycCard(Map<String, dynamic> d) {
    final name = d['name'] as String? ?? 'Sin nombre';
    final email = d['email'] as String? ?? '—';
    final telefono = d['telefono'] as String? ?? '—';
    final tipoDoc = d['tipo_documento'] as String? ?? '—';
    final docF = d['doc_frente_url'] as String?;
    final docD = d['doc_dorso_url'] as String?;
    final veh = d['vehiculos'] as Map<String, dynamic>?;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.surfaceVariant)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), shape: BoxShape.circle),
              child: Center(child: Text(initial, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.error))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(email, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Text('Pendiente', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.error)),
            ),
          ]),
        ),
        // Info
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _infoRow(Icons.phone_rounded, telefono),
            _infoRow(Icons.badge_rounded, 'Doc: $tipoDoc'),
            if (veh != null) _infoRow(Icons.directions_car_rounded, '${veh['marca'] ?? ''} ${veh['modelo'] ?? ''} · ${veh['chapa'] ?? ''}'),
            const SizedBox(height: 12),
            Text('DOCUMENTOS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _docThumb('Frente', docF)),
              const SizedBox(width: 10),
              Expanded(child: _docThumb('Dorso', docD)),
            ]),
          ]),
        )),
        // Actions
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.surfaceVariant))),
          child: Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _reject(d),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: BorderSide(color: AppColors.error.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Rechazar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () => _approve(d),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Aprobar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
      Icon(icon, size: 15, color: AppColors.textHint),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
    ]));
  }

  Widget _docThumb(String label, String? url) {
    return GestureDetector(
      onTap: url != null && url.isNotEmpty ? () => _showDocFull(label, url) : null,
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          height: 80, width: double.infinity,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: AppColors.surfaceVariant, border: Border.all(color: AppColors.divider)),
          clipBehavior: Clip.antiAlias,
          child: url != null && url.isNotEmpty
              ? Stack(children: [
                  Image.network(url, fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                      errorBuilder: (_, __, ___) => Center(child: Icon(Icons.broken_image_rounded, color: AppColors.textHint))),
                  Positioned(right: 4, bottom: 4, child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                    child: const Icon(Icons.fullscreen_rounded, size: 14, color: Colors.white),
                  )),
                ])
              : Center(child: Text('Sin doc.', style: TextStyle(fontSize: 11, color: AppColors.textHint))),
        ),
      ]),
    );
  }

  void _showDocFull(String label, String url) {
    showDialog(context: context, builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Text('Documento — $label', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ])),
          Flexible(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ClipRRect(borderRadius: BorderRadius.circular(10),
              child: Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Text('Error cargando imagen')))),
          )),
        ]),
      ),
    ));
  }

  Future<void> _approve(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Aprobar conductor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('¿Confirmas la verificación de ${d['name']}?\nEl conductor podrá operar con el badge "Verificado".'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Aprobar')),
      ],
    ));
    if (ok != true) return;
    await MueveteService.approveDriverKyc(d['id'] as int);
    _loadData();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${d['name']} verificado'), backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  Future<void> _reject(Map<String, dynamic> d) async {
    final ctrl = TextEditingController();
    final motivo = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Rechazar conductor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('¿Por qué se rechaza a ${d['name']}?', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        TextField(controller: ctrl, maxLines: 3, decoration: InputDecoration(
          hintText: 'Documentos ilegibles, datos incorrectos...',
          hintStyle: TextStyle(color: AppColors.textHint, fontSize: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.error, width: 1.5)),
        )),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () { if (ctrl.text.trim().isNotEmpty) Navigator.pop(context, ctrl.text.trim()); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Rechazar')),
      ],
    ));
    ctrl.dispose();
    if (motivo != null && motivo.isNotEmpty) {
      await MueveteService.rejectDriverKyc(d['id'] as int, motivo);
      _loadData();
    }
  }
}
