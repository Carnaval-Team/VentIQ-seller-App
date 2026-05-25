import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/wapi_envio_log.dart';
import '../models/wapi_programacion.dart';
import '../models/wapi_session.dart';
import '../services/subscription_service.dart';
import '../services/user_preferences_service.dart';
import '../services/wapi_notification_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/wapi_add_bot_sheet.dart';
import '../widgets/wapi_destinatario_picker.dart';
import '../widgets/wapi_qr_dialog.dart';
import '../widgets/wapi_session_card.dart';
import 'wapi_product_selector_screen.dart';
import 'wapi_schedule_config_screen.dart';

class WapiNotificationsScreen extends StatefulWidget {
  const WapiNotificationsScreen({super.key});

  @override
  State<WapiNotificationsScreen> createState() =>
      _WapiNotificationsScreenState();
}

class _WapiNotificationsScreenState extends State<WapiNotificationsScreen> {
  final _service = WapiNotificationService.instance;
  final _subs = SubscriptionService();

  int? _idTienda;
  bool _isAdvanced = false;
  bool _isPro = false;

  bool _loading = true;
  String? _error;

  List<WapiSession> _sesiones = [];
  WapiProgramacion? _programacion;
  List<WapiEnvioLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final idTienda = await UserPreferencesService().getIdTienda();
      if (idTienda == null) {
        throw Exception('No hay tienda seleccionada');
      }
      _idTienda = idTienda;
      _isAdvanced = await _subs.hasAdvancedPlan(idTienda);
      _isPro = _isAdvanced || await _subs.hasProPlan(idTienda);

      await _reloadData();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadData() async {
    if (_idTienda == null) return;
    final results = await Future.wait([
      _service.listSessions(_idTienda!),
      _service.getProgramacion(_idTienda!),
      _service.getRecentLogs(_idTienda!, limit: 10),
    ]);
    if (!mounted) return;
    setState(() {
      _sesiones = results[0] as List<WapiSession>;
      _programacion = results[1] as WapiProgramacion?;
      _logs = results[2] as List<WapiEnvioLog>;
    });
  }

  Future<void> _onAddBot() async {
    if (_idTienda == null) return;
    final s = await WapiAddBotSheet.show(context, idTienda: _idTienda!);
    if (s == null || !mounted) return;
    await WapiQrDialog.show(context, idSesion: s.id, nombreBot: s.nombre);
    await _reloadData();
  }

  Future<void> _onSessionAction(WapiSession s, String action) async {
    try {
      switch (action) {
        case 'qr':
          await WapiQrDialog.show(context,
              idSesion: s.id, nombreBot: s.nombre);
          break;
        case 'restart':
          await _service.sessionAction(s.id, 'restart');
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bot reiniciándose…')));
          break;
        case 'logout':
          await _service.sessionAction(s.id, 'logout');
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bot desconectado')));
          break;
        case 'delete':
          final ok = await _confirm(
              'Eliminar bot',
              '¿Eliminar el bot "${s.nombre}"? '
              'Esta acción no se puede deshacer.');
          if (ok != true) return;
          await _service.sessionAction(s.id, 'delete');
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bot eliminado')));
          break;
        case 'details':
          await _showDetails(s);
          break;
      }
      await _reloadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Confirmar',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  Future<void> _showDetails(WapiSession s) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.nombre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('ID interno', '${s.id}'),
            _detailRow('Session ID', s.wapiSessionId),
            _detailRow('Estado', s.status.label),
            _detailRow('Número', s.phoneNumber ?? '—'),
            _detailRow('Actualizado', s.lastStatusAt.toLocal().toString()),
            _detailRow('Creado', s.createdAt.toLocal().toString()),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _detailRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(k,
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textPrimary)),
            ),
          ],
        ),
      );

  Future<void> _onSendNow() async {
    final connected =
        _sesiones.where((s) => s.status == WapiStatus.connected).toList();
    if (connected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Necesitas al menos un bot conectado.')));
      return;
    }

    // Si hay más de un bot conectado, pedir cuál usar
    WapiSession? sesion = connected.first;
    if (connected.length > 1) {
      sesion = await showDialog<WapiSession>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('¿Desde qué bot enviar?'),
          children: connected
              .map((s) => SimpleDialogOption(
                    child: ListTile(
                      leading: Icon(Icons.smart_toy, color: s.status.color),
                      title: Text(s.nombre),
                      subtitle: Text(s.phoneNumber ?? ''),
                    ),
                    onPressed: () => Navigator.pop(ctx, s),
                  ))
              .toList(),
        ),
      );
      if (sesion == null) return;
    }

    // 1. Selector productos
    final productIds = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => const WapiProductSelectorScreen(
          mode: WapiProductSelectorMode.manual,
        ),
      ),
    );
    if (productIds == null || productIds.isEmpty) return;

    // 2. Destinatarios
    if (!mounted) return;
    final picker = await WapiDestinatarioPicker.show(
      context,
      idTienda: _idTienda!,
      sesion: sesion,
    );
    if (picker == null || picker.destinatarios.isEmpty) return;

    // 3. Enviar
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final res = await _service.sendProductsNow(
        idSesion: sesion.id,
        productIds: productIds,
        destinations: picker.destinatarios,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar loading

      // El backend ahora responde inmediatamente: el envío corre en background.
      // Aceptamos el formato nuevo (queued) y caemos al viejo si el backend
      // aún no se ha redesplegado.
      final queued = res['queued'] == true;
      final totalEstim = res['total_mensajes_estimados'] ?? res['enviados'] ?? 0;
      final tiempoSeg = res['tiempo_estimado_segundos'];
      final tiempoStr = tiempoSeg is num
          ? '~${(tiempoSeg / 60).ceil()} min'
          : 'unos minutos';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 5),
          content: Text(
            queued
                ? '✅ $totalEstim mensaje(s) en cola. Tiempo estimado: $tiempoStr. '
                    'Puedes seguir usando la app — revisa el historial para ver el progreso.'
                : '$totalEstim mensaje(s) encolados. '
                    'Se enviarán con jitter aleatorio para evitar bloqueos.',
          ),
        ),
      );
      await _reloadData();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red, content: Text('Error: $e')));
    }
  }

  Future<void> _onConfigureSchedule() async {
    if (!_isAdvanced) {
      _showUpgradeDialog();
      return;
    }
    final connected =
        _sesiones.where((s) => s.status == WapiStatus.connected).toList();
    if (connected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Necesitas al menos un bot conectado.'),
      ));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WapiScheduleConfigScreen(
        idTienda: _idTienda!,
        sesiones: connected,
        existente: _programacion,
      ),
    ));
    await _reloadData();
  }

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.workspace_premium, color: AppColors.warning),
          SizedBox(width: 8),
          Text('Función Avanzada'),
        ]),
        content: const Text(
          'El envío automático programado requiere el plan Avanzado. '
          'Contacta al soporte para mejorar tu plan.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notificación a Clientes'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _bootstrap,
          ),
          if (isWeb && _isPro)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Enviar productos ahora'),
                onPressed: _onSendNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                ),
              ),
            ),
        ],
      ),
      drawer: const AdminDrawer(),
      floatingActionButton: (!isWeb && _isPro)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.send),
              label: const Text('Enviar ahora'),
              onPressed: _onSendNow,
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(error: _error!, onRetry: _bootstrap)
              : RefreshIndicator(
                  onRefresh: _reloadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _PlanBadge(isAdvanced: _isAdvanced),
                      const SizedBox(height: 14),
                      _SectionHeader(
                        icon: Icons.smart_toy,
                        title: 'Bots activos',
                        subtitle:
                            '${_sesiones.length} sesión(es) registrada(s)',
                        action: TextButton.icon(
                          onPressed: _onAddBot,
                          icon: const Icon(Icons.add),
                          label: const Text('Añadir bot'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSesionesGrid(isWeb),
                      const SizedBox(height: 22),
                      _SectionHeader(
                        icon: Icons.schedule,
                        title: 'Envío automático diario',
                        subtitle: _isAdvanced
                            ? 'Plan Avanzado: configura una difusión diaria automática'
                            : 'Disponible solo con plan Avanzado',
                        action: TextButton.icon(
                          onPressed: _onConfigureSchedule,
                          icon: const Icon(Icons.settings),
                          label: Text(
                              _programacion == null ? 'Configurar' : 'Editar'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildProgramacionCard(),
                      const SizedBox(height: 22),
                      _SectionHeader(
                        icon: Icons.history,
                        title: 'Envíos recientes',
                        subtitle: 'Últimos 10 mensajes despachados',
                      ),
                      const SizedBox(height: 8),
                      _buildLogsList(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSesionesGrid(bool isWeb) {
    if (_sesiones.isEmpty) {
      return _EmptyCard(
        icon: Icons.smart_toy_outlined,
        title: 'Aún no tienes bots',
        subtitle:
            'Crea un bot, escanea el QR con tu WhatsApp y empieza a difundir.',
        action: ElevatedButton.icon(
          onPressed: _onAddBot,
          icon: const Icon(Icons.add),
          label: const Text('Crear primer bot'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      );
    }
    if (isWeb) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _sesiones.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 420,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 140,
        ),
        itemBuilder: (_, i) => WapiSessionCard(
          session: _sesiones[i],
          onAction: (a) => _onSessionAction(_sesiones[i], a),
        ),
      );
    }
    return Column(
      children: _sesiones
          .map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: WapiSessionCard(
                  session: s,
                  onAction: (a) => _onSessionAction(s, a),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildProgramacionCard() {
    final p = _programacion;
    if (p == null) {
      return _EmptyCard(
        icon: Icons.schedule_outlined,
        title: _isAdvanced
            ? 'Sin programación configurada'
            : 'Función exclusiva Avanzado',
        subtitle: _isAdvanced
            ? 'Elige hora, productos y destinatarios para activar el envío automático diario.'
            : 'Mejora tu plan para difundir productos cada día automáticamente.',
        action: ElevatedButton.icon(
          onPressed: _onConfigureSchedule,
          icon: Icon(_isAdvanced ? Icons.add : Icons.lock_outline),
          label: Text(_isAdvanced ? 'Configurar' : 'Saber más'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
                p.activa ? Icons.play_circle_fill : Icons.pause_circle_filled,
                color: p.activa ? AppColors.success : AppColors.textLight,
                size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.nombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  'Hora: ${p.horaEnvio.format(context)} • '
                  '${p.productIds.length} producto(s) • '
                  '${p.destinatarioIds.length} destino(s)',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                if (p.nextRunAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Próximo envío: ${p.nextRunAt!.toLocal()}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textLight),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: p.activa,
            activeColor: AppColors.success,
            onChanged: (v) async {
              await _service.setProgramacionActiva(p.id, v);
              await _reloadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    if (_logs.isEmpty) {
      return _EmptyCard(
        icon: Icons.inbox_outlined,
        title: 'Sin envíos aún',
        subtitle: 'Cuando difundas productos los verás aquí.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(_logs.length, (i) {
          final l = _logs[i];
          final last = i == _logs.length - 1;
          IconData icon;
          Color color;
          switch (l.estado) {
            case WapiEnvioEstado.enviado:
              icon = Icons.check_circle;
              color = AppColors.success;
              break;
            case WapiEnvioEstado.fallido:
              icon = Icons.error;
              color = Colors.red;
              break;
            default:
              icon = Icons.schedule;
              color = AppColors.warning;
          }
          return Column(
            children: [
              ListTile(
                dense: true,
                leading: Icon(icon, color: color),
                title: Text(
                  '${l.tipoEnvio.toUpperCase()} → ${l.chatId}',
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  l.errorMessage ??
                      (l.sentAt != null
                          ? 'Enviado ${l.sentAt!.toLocal()}'
                          : 'Pendiente'),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!last) const Divider(height: 1),
            ],
          );
        }),
      ),
    );
  }
}

// =========================================================================
// Sub-widgets simples
// =========================================================================

class _PlanBadge extends StatelessWidget {
  final bool isAdvanced;
  const _PlanBadge({required this.isAdvanced});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isAdvanced ? 'Plan Avanzado activo' : 'Plan Pro activo',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  isAdvanced
                      ? 'Difunde productos en WhatsApp con envío manual y automático diario.'
                      : 'Difunde productos en WhatsApp con envío manual. Mejora a Avanzado para envío automático.',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textLight),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary)),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 64),
            const SizedBox(height: 14),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
