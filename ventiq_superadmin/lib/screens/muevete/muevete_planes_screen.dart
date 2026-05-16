import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/muevete_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

/// Pantalla de gestión de solicitudes de activación de plan.
/// Carga todas las solicitudes y permite filtrar por estado con chips.
class MuevetesPlanesScreen extends StatefulWidget {
  const MuevetesPlanesScreen({super.key});

  @override
  State<MuevetesPlanesScreen> createState() => _MuevetesPlanesScreenState();
}

class _MuevetesPlanesScreenState extends State<MuevetesPlanesScreen> {
  List<Map<String, dynamic>> _todas = [];
  String _filtro = 'todas'; // 'todas' | 'pendiente' | 'aprobada' | 'rechazada'
  bool _isLoading = true;

  List<Map<String, dynamic>> get _filtradas {
    if (_filtro == 'todas') return _todas;
    return _todas.where((s) => s['estado'] == _filtro).toList();
  }

  int _count(String estado) =>
      _todas.where((s) => s['estado'] == estado).length;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    debugPrint('[MuevetesPlanesScreen] _loadData iniciado');
    try {
      final all = await MueveteService.getSolicitudesPlan();
      debugPrint('[MuevetesPlanesScreen] total recibido: ${all.length}');
      if (mounted) {
        setState(() {
          _todas = all;
          _isLoading = false;
        });
        debugPrint(
            '[MuevetesPlanesScreen] pendientes=${_count('pendiente')} aprobadas=${_count('aprobada')} rechazadas=${_count('rechazada')}');
      }
    } catch (e, st) {
      debugPrint('[MuevetesPlanesScreen] ERROR: $e\n$st');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al cargar solicitudes: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(
        MediaQuery.of(context).size.width);
    final pendientes = _count('pendiente');

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      body: CustomScrollView(
        slivers: [
          // ── AppBar
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            surfaceTintColor: Colors.white,
            elevation: 0.5,
            title: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: pendientes > 0
                        ? [AppColors.warning, AppColors.warning.withOpacity(0.7)]
                        : [AppColors.success, AppColors.success.withOpacity(0.7)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Solicitudes de Plan',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text(
                  '${_todas.length} solicitudes · $pendientes pendientes',
                  style: TextStyle(
                      fontSize: 12,
                      color: pendientes > 0
                          ? AppColors.warning
                          : AppColors.textSecondary),
                ),
              ]),
            ]),
            actions: [
              IconButton(
                  onPressed: _loadData,
                  icon: Icon(Icons.refresh_rounded,
                      color: AppColors.textSecondary)),
              const SizedBox(width: 8),
            ],
          ),

          // ── Filter chips
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'Todas',
                      count: _todas.length,
                      selected: _filtro == 'todas',
                      color: AppColors.primary,
                      onTap: () => setState(() => _filtro = 'todas'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Pendientes',
                      count: _count('pendiente'),
                      selected: _filtro == 'pendiente',
                      color: AppColors.warning,
                      onTap: () => setState(() => _filtro = 'pendiente'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Aprobadas',
                      count: _count('aprobada'),
                      selected: _filtro == 'aprobada',
                      color: AppColors.success,
                      onTap: () => setState(() => _filtro = 'aprobada'),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Rechazadas',
                      count: _count('rechazada'),
                      selected: _filtro == 'rechazada',
                      color: AppColors.error,
                      onTap: () => setState(() => _filtro = 'rechazada'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Divider
          const SliverToBoxAdapter(
            child: Divider(height: 1, color: Color(0xFFE0E0E0)),
          ),

          // ── Lista
          if (_isLoading)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()))
          else if (_filtradas.isEmpty)
            SliverFillRemaining(child: _buildEmpty())
          else
            SliverPadding(
              padding: EdgeInsets.all(isDesktop ? 28 : 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SolicitudCard(
                        data: _filtradas[i], onAction: _loadData),
                  ),
                  childCount: _filtradas.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final labels = {
      'todas': 'No hay solicitudes',
      'pendiente': 'Sin solicitudes pendientes',
      'aprobada': 'Sin solicitudes aprobadas',
      'rechazada': 'Sin solicitudes rechazadas',
    };
    final icons = {
      'todas': Icons.inbox_rounded,
      'pendiente': Icons.check_circle_outline_rounded,
      'aprobada': Icons.verified_rounded,
      'rechazada': Icons.cancel_outlined,
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icons[_filtro] ?? Icons.inbox_rounded,
              size: 48, color: AppColors.success),
        ),
        const SizedBox(height: 20),
        Text(labels[_filtro] ?? 'Sin resultados',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text('Cuando haya solicitudes aparecerán aquí.',
            style:
                TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip de filtro
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : color,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withOpacity(0.25)
                    : color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : color,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tarjeta de solicitud
// ─────────────────────────────────────────────────────────────────────────────

class _SolicitudCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onAction;

  const _SolicitudCard({required this.data, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final estado = data['estado'] as String? ?? 'pendiente';
    final isPendiente = estado == 'pendiente';
    final isAprobada = estado == 'aprobada';

    final nombre =
        data['usuario_nombre'] as String? ?? data['usuario_uuid'] as String? ?? 'Usuario';
    final email = data['usuario_email'] as String? ?? '—';
    final planInfo = data['planes'] as Map<String, dynamic>?;
    final planNombre =
        planInfo?['nombre'] as String? ?? data['plan_codigo'] as String? ?? '—';
    final planPrecio = (planInfo?['precio_mensual'] as num?)?.toDouble();
    final evidenciaUrl = data['evidencia_url'] as String? ?? '';
    final observaciones = data['observaciones'] as String?;
    final codigoTransf = data['codigo_transferencia'] as String?;
    final createdAt =
        DateTime.tryParse(data['created_at'] as String? ?? '');
    final initial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    Color estadoColor;
    String estadoLabel;
    IconData estadoIcon;
    switch (estado) {
      case 'aprobada':
        estadoColor = AppColors.success;
        estadoLabel = 'Aprobada';
        estadoIcon = Icons.check_circle_rounded;
        break;
      case 'rechazada':
        estadoColor = AppColors.error;
        estadoLabel = 'Rechazada';
        estadoIcon = Icons.cancel_rounded;
        break;
      default:
        estadoColor = AppColors.warning;
        estadoLabel = 'Pendiente';
        estadoIcon = Icons.hourglass_top_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPendiente
              ? AppColors.warning.withOpacity(0.45)
              : AppColors.divider,
          width: isPendiente ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: [
        // ── Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: AppColors.surfaceVariant))),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: estadoColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                  child: Text(initial,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: estadoColor))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text(email,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: estadoColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(estadoIcon, size: 12, color: estadoColor),
                  const SizedBox(width: 4),
                  Text(estadoLabel,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: estadoColor)),
                ]),
              ),
              if (createdAt != null) ...[
                const SizedBox(height: 4),
                Text(_fmtFecha(createdAt),
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ],
            ]),
          ]),
        ),

        // ── Body
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan
                Row(children: [
                  Icon(Icons.workspace_premium_rounded,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(planNombre,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          fontSize: 14)),
                  if (planPrecio != null) ...[
                    const SizedBox(width: 6),
                    Text('· \$${planPrecio.toStringAsFixed(0)}/mes',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                  ],
                ]),
                const SizedBox(height: 12),

                // Comprobante
                Text('COMPROBANTE DE PAGO',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.8)),
                const SizedBox(height: 6),
                _EvidenciaThumb(url: evidenciaUrl),

                // Código transferencia
                if (codigoTransf != null && codigoTransf.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _InfoRow(
                      icon: Icons.tag_rounded,
                      label: 'Cód. Transferencia',
                      value: codigoTransf),
                ],

                // Observaciones
                if (observaciones != null && observaciones.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isAprobada
                          ? AppColors.success.withOpacity(0.06)
                          : AppColors.error.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isAprobada
                              ? AppColors.success.withOpacity(0.2)
                              : AppColors.error.withOpacity(0.2)),
                    ),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.comment_rounded,
                              size: 14,
                              color: isAprobada
                                  ? AppColors.success
                                  : AppColors.error),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text(observaciones,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary))),
                        ]),
                  ),
                ],
              ]),
        ),

        // ── Acciones (solo pendientes)
        if (isPendiente)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: ElevatedButton.icon(
              onPressed: () => _showEvidenciaAccionDialog(context, data),
              icon: const Icon(Icons.rate_review_rounded, size: 18),
              label: const Text('Revisar solicitud',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
      ]),
    );
  }

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _showEvidenciaAccionDialog(
      BuildContext context, Map<String, dynamic> data) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EvidenciaAccionDialog(
        data: data,
        onSuccess: (msg, isAprobada) {
          onAction();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor:
                isAprobada ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
          ));
        },
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo único: evidencia + selección de acción + campos expandibles
// ─────────────────────────────────────────────────────────────────────────────

class _EvidenciaAccionDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function(String msg, bool isAprobada) onSuccess;

  const _EvidenciaAccionDialog(
      {required this.data, required this.onSuccess});

  @override
  State<_EvidenciaAccionDialog> createState() =>
      _EvidenciaAccionDialogState();
}

class _EvidenciaAccionDialogState extends State<_EvidenciaAccionDialog> {
  // null = sin selección, 'aprobar', 'rechazar'
  String? _accion;
  final _codigoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  // Vencimiento: siempre día 2 de un mes. null = función SQL calcula automático.
  DateTime? _fechaVencimiento;

  /// Genera los próximos N meses con día 2, a partir del mes siguiente al actual.
  List<DateTime> get _opcionesVencimiento {
    final now = DateTime.now();
    // Primer día 2 disponible: mes que viene (o este mes si aún no ha pasado el 2)
    final base = now.day < 2
        ? DateTime(now.year, now.month, 2)
        : DateTime(now.year, now.month + 1, 2);
    return List.generate(12, (i) => DateTime(base.year, base.month + i, 2));
  }
  String? _errorMsg;
  bool _loading = false;

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Color get _accionColor {
    if (_accion == 'aprobar') return AppColors.success;
    if (_accion == 'rechazar') return AppColors.error;
    return AppColors.primary;
  }

  Future<void> _submit() async {
    // Validaciones locales
    if (_accion == 'aprobar' && _codigoCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'El código de transferencia es requerido');
      return;
    }
    if (_accion == 'rechazar' && _obsCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'El motivo del rechazo es requerido');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final adminUuid = Supabase.instance.client.auth.currentUser?.id;
      if (adminUuid == null) throw Exception('Sin sesión de admin');
      final id = widget.data['id'] as int;

      if (_accion == 'aprobar') {
        await MueveteService.aprobarSolicitudPlan(
          solicitudId: id,
          adminUuid: adminUuid,
          codigoTransferencia: _codigoCtrl.text.trim(),
          observaciones: _obsCtrl.text.trim().isNotEmpty
              ? _obsCtrl.text.trim()
              : null,
          fechaVencimiento: _fechaVencimiento,
        );
        if (mounted) Navigator.pop(context);
        widget.onSuccess('Solicitud aprobada. Plan activado.', true);
      } else {
        await MueveteService.rechazarSolicitudPlan(
          solicitudId: id,
          adminUuid: adminUuid,
          observaciones: _obsCtrl.text.trim(),
        );
        if (mounted) Navigator.pop(context);
        widget.onSuccess('Solicitud rechazada.', false);
      }
    } catch (e, st) {
      final msg = e.toString().replaceAll('Exception: ', '');
      debugPrint('[EvidenciaAccionDialog] ERROR al $_accion: $msg\n$st');
      setState(() {
        _loading = false;
        _errorMsg = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.data['usuario_nombre'] as String? ??
        widget.data['usuario_uuid'] as String? ?? 'Usuario';
    final planInfo = widget.data['planes'] as Map<String, dynamic>?;
    final planNombre = planInfo?['nombre'] as String? ??
        widget.data['plan_codigo'] as String? ?? '—';
    final planPrecio =
        (planInfo?['precio_mensual'] as num?)?.toDouble();
    final evidenciaUrl = widget.data['evidencia_url'] as String? ?? '';

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Encabezado
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.rate_review_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Revisar solicitud',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          Text('$nombre · $planNombre'
                              '${planPrecio != null ? ' · \$${planPrecio.toStringAsFixed(0)}/mes' : ''}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ]),
                  ),
                  IconButton(
                    onPressed:
                        _loading ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ]),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 14),

                // ── Comprobante de pago (tamaño grande)
                Text('COMPROBANTE DE PAGO',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                _EvidenciaFull(url: evidenciaUrl),

                const SizedBox(height: 20),

                // ── Selección de acción
                Text('ACCIÓN',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _AccionToggle(
                      label: 'Aprobar',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success,
                      selected: _accion == 'aprobar',
                      onTap: () => setState(() {
                        _accion = 'aprobar';
                        _errorMsg = null;
                        _fechaVencimiento = null;
                        _obsCtrl.clear();
                        _codigoCtrl.clear();
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AccionToggle(
                      label: 'Rechazar',
                      icon: Icons.cancel_rounded,
                      color: AppColors.error,
                      selected: _accion == 'rechazar',
                      onTap: () => setState(() {
                        _accion = 'rechazar';
                        _errorMsg = null;
                        _obsCtrl.clear();
                        _codigoCtrl.clear();
                      }),
                    ),
                  ),
                ]),

                // ── Campos expandibles según acción
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeInOut,
                  child: _accion == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(),
                              const SizedBox(height: 12),

                              if (_accion == 'aprobar') ...[
                                // Vencimiento: selector de mes (día 2 fijo)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Icon(
                                          Icons.event_rounded,
                                          size: 15,
                                          color: AppColors.success),
                                      const SizedBox(width: 6),
                                      Text('Fecha de vencimiento *',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  AppColors.textSecondary)),
                                      const SizedBox(width: 6),
                                      Text('(siempre día 2)',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textHint)),
                                    ]),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _opcionesVencimiento
                                          .map((fecha) {
                                        final meses = [
                                          'Ene', 'Feb', 'Mar', 'Abr',
                                          'May', 'Jun', 'Jul', 'Ago',
                                          'Sep', 'Oct', 'Nov', 'Dic'
                                        ];
                                        final label =
                                            '2 ${meses[fecha.month - 1]} ${fecha.year}';
                                        final selected =
                                            _fechaVencimiento?.year ==
                                                    fecha.year &&
                                                _fechaVencimiento?.month ==
                                                    fecha.month;
                                        return GestureDetector(
                                          onTap: () => setState(() {
                                            _fechaVencimiento = fecha;
                                            _errorMsg = null;
                                          }),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 160),
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 7),
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? AppColors.success
                                                  : AppColors.success
                                                      .withOpacity(0.07),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: selected
                                                    ? AppColors.success
                                                    : AppColors.success
                                                        .withOpacity(0.3),
                                                width: selected ? 2 : 1,
                                              ),
                                            ),
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: selected
                                                    ? Colors.white
                                                    : AppColors.success,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    if (_fechaVencimiento == null)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 6),
                                        child: Text(
                                          'Sin selección: se usará el próximo día 2 automáticamente',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textHint,
                                              fontStyle: FontStyle.italic),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                // Código transferencia
                                TextField(
                                  controller: _codigoCtrl,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  onChanged: (_) =>
                                      setState(() => _errorMsg = null),
                                  decoration: InputDecoration(
                                    labelText:
                                        'Código de transferencia *',
                                    hintText: 'Ej. TRF-2024-000123',
                                    prefixIcon:
                                        const Icon(Icons.tag_rounded),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: AppColors.success,
                                            width: 1.5)),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _obsCtrl,
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    labelText:
                                        'Observaciones (opcional)',
                                    hintText: 'Nota interna...',
                                    prefixIcon: const Icon(
                                        Icons.comment_outlined),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: AppColors.success,
                                            width: 1.5)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(children: [
                                  Icon(Icons.info_outline_rounded,
                                      size: 13,
                                      color: AppColors.warning),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'El código es único por transferencia. Se verifica contra duplicados.',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary),
                                    ),
                                  ),
                                ]),
                              ],

                              if (_accion == 'rechazar') ...[
                                TextField(
                                  controller: _obsCtrl,
                                  maxLines: 3,
                                  onChanged: (_) =>
                                      setState(() => _errorMsg = null),
                                  decoration: InputDecoration(
                                    labelText: 'Motivo del rechazo *',
                                    hintText:
                                        'Comprobante ilegible, monto incorrecto, transferencia duplicada...',
                                    hintStyle: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textHint),
                                    prefixIcon: const Icon(
                                        Icons.comment_outlined),
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: AppColors.error,
                                            width: 1.5)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),

                // ── Bloque de error independiente
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _errorMsg == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color:
                                      AppColors.error.withOpacity(0.35)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: AppColors.error, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMsg!,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _errorMsg = null),
                                  child: Icon(Icons.close_rounded,
                                      size: 16,
                                      color: AppColors.error
                                          .withOpacity(0.6)),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 16),

                // ── Botón confirmar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_accion == null || _loading)
                        ? null
                        : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accionColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : Text(
                            _accion == 'aprobar'
                                ? 'Confirmar aprobación'
                                : _accion == 'rechazar'
                                    ? 'Confirmar rechazo'
                                    : 'Selecciona una acción',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle de acción (Aprobar / Rechazar)
// ─────────────────────────────────────────────────────────────────────────────

class _AccionToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AccionToggle({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.3),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              size: 18, color: selected ? Colors.white : color),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: selected ? Colors.white : color)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Evidencia a tamaño completo (dentro del diálogo)
// ─────────────────────────────────────────────────────────────────────────────

class _EvidenciaFull extends StatelessWidget {
  final String url;
  const _EvidenciaFull({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(
            child: Text('Sin comprobante',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textHint))),
      );
    }
    return GestureDetector(
      onTap: () => _showFull(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          Image.network(
            url,
            fit: BoxFit.contain,
            width: double.infinity,
            errorBuilder: (_, __, ___) => Container(
              height: 100,
              color: AppColors.surfaceVariant,
              child: Center(
                  child: Icon(Icons.broken_image_rounded,
                      color: AppColors.textHint)),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.fullscreen_rounded,
                  size: 16, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }

  void _showFull(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 800, maxHeight: 700),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Text('Comprobante de pago',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                          child: Text('Error cargando imagen'))),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EvidenciaThumb extends StatelessWidget {
  final String url;
  const _EvidenciaThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Container(
        height: 80,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Center(
            child: Text('Sin comprobante',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textHint))),
      );
    }

    return GestureDetector(
      onTap: () => _showFull(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(children: [
            Image.network(url,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: AppColors.textHint))),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.fullscreen_rounded,
                    size: 16, color: Colors.white),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showFull(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 700, maxHeight: 620),
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Text('Comprobante de pago',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                          child: Text('Error cargando imagen'))),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      Text('$label: ',
          style: TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}
