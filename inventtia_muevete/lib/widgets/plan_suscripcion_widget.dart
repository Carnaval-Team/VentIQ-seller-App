import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/plan_model.dart';
import '../models/solicitud_plan_model.dart';
import '../models/suscripcion_model.dart';
import '../providers/auth_provider.dart';
import '../providers/suscripcion_provider.dart';
import '../providers/theme_provider.dart';
import '../services/document_upload_service.dart';

/// Tile compacto que muestra el plan activo del usuario y un botón para gestionarlo.
/// Incluye el flujo de evidencia de pago al contratar un plan de pago.
class PlanSuscripcionTile extends StatefulWidget {
  const PlanSuscripcionTile({super.key});

  @override
  State<PlanSuscripcionTile> createState() => _PlanSuscripcionTileState();
}

class _PlanSuscripcionTileState extends State<PlanSuscripcionTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  void _cargar() {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.id;
    final tipo = _tipoParaPlan(auth.tipoUsuario);
    if (uid != null && tipo != null) {
      context.read<SuscripcionProvider>().cargarSuscripcion(uid, tipo);
    }
  }

  String? _tipoParaPlan(String? tipoUsuario) {
    switch (tipoUsuario) {
      case 'shipper':
        return 'shipper';
      case 'carrier_carga':
        return 'carrier';
      case 'dispatcher':
        return 'dispatcher';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final prov = context.watch<SuscripcionProvider>();
    final auth = context.watch<AuthProvider>();
    final textPrimary = AppTheme.textPrimary(isDark);
    final textSecondary = AppTheme.textSecondary(isDark);

    if (prov.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final sus = prov.suscripcion;
    final plan = prov.planActual;
    final solicitud = prov.solicitudPendiente;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.card(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: sus != null && sus.estaPorVencer
              ? Colors.orange.withValues(alpha: 0.6)
              : AppTheme.border(isDark),
          width: sus != null && sus.estaPorVencer ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(Icons.workspace_premium_outlined,
                    color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tu Plan',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
                if (sus != null)
                  _EstadoBadge(
                    label: sus.estaActiva ? 'Activa' : sus.estado,
                    color: sus.estaActiva ? Colors.green : Colors.red,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Solicitud pendiente en revisión
          if (solicitud != null)
            _SolicitudPendienteBanner(solicitud: solicitud, isDark: isDark),

          // ── Plan actual
          if (sus == null && !prov.loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'Sin suscripción activa. Elige un plan para comenzar.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: textSecondary),
              ),
            )
          else if (sus != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan?.nombre ?? sus.planCodigo,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: plan?.esGratis == true
                          ? AppTheme.success
                          : AppTheme.primaryColor,
                    ),
                  ),
                  if (plan != null && !plan.esGratis) ...[
                    const SizedBox(height: 2),
                    Text(
                      '\$${plan.precioMensual.toStringAsFixed(0)} / mes',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: textSecondary),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 13, color: textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Vence: ${_fmtFecha(sus.vencimiento)}',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                      const SizedBox(width: 12),
                      if (sus.diasRestantes >= 0) ...[
                        Icon(
                          sus.estaPorVencer
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          size: 13,
                          color:
                              sus.estaPorVencer ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          sus.diasRestantes == 0
                              ? 'Vence hoy'
                              : '${sus.diasRestantes} días',
                          style: TextStyle(
                            fontSize: 12,
                            color: sus.estaPorVencer
                                ? Colors.orange
                                : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else
                        Text(
                          'Vencida',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  if (sus.estaPorVencer) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'Tu plan vence pronto. Renueva o actualiza para continuar.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[800],
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _BotonGestionar(
              tipoUsuario: _tipoParaPlan(auth.tipoUsuario) ?? 'shipper',
              suscripcion: sus,
              plan: plan,
              planesDisponibles: prov.planesDisponibles,
              tieneSolicitudPendiente: solicitud != null,
              isDark: isDark,
              onRefresh: _cargar,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner de solicitud pendiente
// ─────────────────────────────────────────────────────────────────────────────

class _SolicitudPendienteBanner extends StatelessWidget {
  final SolicitudPlanModel solicitud;
  final bool isDark;

  const _SolicitudPendienteBanner(
      {required this.solicitud, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded,
              color: Colors.amber, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Solicitud en revisión',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber[800],
                  ),
                ),
                Text(
                  'Plan: ${solicitud.planCodigo.toUpperCase()} · Pendiente de aprobación',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón gestionar
// ─────────────────────────────────────────────────────────────────────────────

class _BotonGestionar extends StatelessWidget {
  final String tipoUsuario;
  final SuscripcionModel? suscripcion;
  final PlanModel? plan;
  final List<PlanModel> planesDisponibles;
  final bool tieneSolicitudPendiente;
  final bool isDark;
  final VoidCallback onRefresh;

  const _BotonGestionar({
    required this.tipoUsuario,
    required this.suscripcion,
    required this.plan,
    required this.planesDisponibles,
    required this.tieneSolicitudPendiente,
    required this.isDark,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SuscripcionProvider>();
    final auth = context.read<AuthProvider>();

    final planesPago = planesDisponibles
        .where((p) => !p.esGratis && p.codigo != suscripcion?.planCodigo)
        .toList();

    return Column(
      children: [
        if (tieneSolicitudPendiente)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Center(
              child: Text(
                'Esperando aprobación del administrador',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber,
                    fontWeight: FontWeight.w600),
              ),
            ),
          )
        else if (planesPago.isNotEmpty) ...[
          ...planesPago.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PlanUpgradeRow(
                  plan: p,
                  isDark: isDark,
                  loading: prov.actionLoading,
                  onContratar: () => _iniciarFlujoContratacion(
                      context, auth, prov, p),
                ),
              )),
        ],
        TextButton.icon(
          onPressed: () => Navigator.pushNamed(
            context,
            '/planes',
            arguments: {'tipoUsuario': tipoUsuario},
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Ver todos los planes'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primaryColor,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _iniciarFlujoContratacion(
    BuildContext context,
    AuthProvider auth,
    SuscripcionProvider prov,
    PlanModel planSeleccionado,
  ) async {
    final uid = auth.user?.id;
    if (uid == null) return;

    final evidenciaUrl = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EvidenciaDialog(
        plan: planSeleccionado,
        userUuid: uid,
      ),
    );

    if (evidenciaUrl == null || !context.mounted) return;

    final ok = await prov.solicitarCambioPlan(
      userUuid: uid,
      planCodigo: planSeleccionado.codigo,
      evidenciaUrl: evidenciaUrl,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Solicitud enviada. El administrador revisará tu pago.'
            : 'No se pudo enviar la solicitud. Intenta de nuevo.'),
        backgroundColor: ok ? Colors.green[700] : AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
      if (ok) onRefresh();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo de evidencia de pago
// ─────────────────────────────────────────────────────────────────────────────

class _EvidenciaDialog extends StatefulWidget {
  final PlanModel plan;
  final String userUuid;

  const _EvidenciaDialog({required this.plan, required this.userUuid});

  @override
  State<_EvidenciaDialog> createState() => _EvidenciaDialogState();
}

class _EvidenciaDialogState extends State<_EvidenciaDialog> {
  final _docService = DocumentUploadService();
  String? _evidenciaUrl;
  bool _uploading = false;
  bool _sending = false;

  Future<void> _pickEvidencia(ImageSource source) async {
    setState(() => _uploading = true);
    try {
      final url = await _docService.pickCompressAndUpload(
        uuid: widget.userUuid,
        filename:
            'evidencia_plan_${widget.plan.codigo}_${DateTime.now().millisecondsSinceEpoch}',
        source: source,
      );
      if (url != null && mounted) {
        setState(() => _evidenciaUrl = url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al subir imagen: $e'),
          backgroundColor: AppTheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Subir comprobante de pago',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt,
                    color: AppTheme.primaryColor),
                title: const Text('Tomar foto'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickEvidencia(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: AppTheme.primaryColor),
                title: const Text('Elegir de galería'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickEvidencia(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.all(20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                color: AppTheme.primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Contratar ${widget.plan.nombre}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Precio
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '\$${widget.plan.precioMensual.toStringAsFixed(0)} / mes',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Realiza la transferencia y sube el comprobante de pago. '
            'El equipo de Inventtia revisará y activará tu plan.',
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),

          // Zona de evidencia
          GestureDetector(
            onTap: _uploading ? null : _showSourcePicker,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: _evidenciaUrl != null ? 160 : 100,
              decoration: BoxDecoration(
                color: _evidenciaUrl != null
                    ? Colors.transparent
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _evidenciaUrl != null
                      ? Colors.green.withValues(alpha: 0.6)
                      : AppTheme.primaryColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _uploading
                  ? const Center(child: CircularProgressIndicator())
                  : _evidenciaUrl != null
                      ? Stack(
                          children: [
                            Image.network(
                              _evidenciaUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image_rounded)),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: GestureDetector(
                                onTap: _showSourcePicker,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.edit_rounded,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_rounded,
                                        color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text('Comprobante subido',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.upload_file_rounded,
                                size: 28,
                                color: AppTheme.primaryColor
                                    .withValues(alpha: 0.7)),
                            const SizedBox(height: 6),
                            Text(
                              'Toca para subir comprobante',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
            ),
          ),
        ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              (_evidenciaUrl == null || _sending || _uploading)
                  ? null
                  : () {
                      Navigator.pop(context, _evidenciaUrl);
                    },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Enviar solicitud',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PlanUpgradeRow extends StatelessWidget {
  final PlanModel plan;
  final bool isDark;
  final bool loading;
  final VoidCallback onContratar;

  const _PlanUpgradeRow({
    required this.plan,
    required this.isDark,
    required this.loading,
    required this.onContratar,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.nombre,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(isDark)),
              ),
              Text(
                '\$${plan.precioMensual.toStringAsFixed(0)}/mes',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary(isDark)),
              ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: loading ? null : onContratar,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            minimumSize: const Size(0, 34),
          ),
          child: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Contratar',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EstadoBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _EstadoBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
