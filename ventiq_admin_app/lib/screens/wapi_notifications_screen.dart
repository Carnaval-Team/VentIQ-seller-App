import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../models/wapi_envio_log.dart';
import '../models/wapi_licencia.dart';
import '../models/wapi_programacion.dart';
import '../models/wapi_session.dart';
import '../services/user_preferences_service.dart';
import '../services/wapi_licencia_service.dart';
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
  final _licService = WapiLicenciaService.instance;

  int? _idTienda;

  bool _loading = true;
  String? _error;

  // Estado de licencia
  WapiLicencia? _licencia;
  WapiLicenciaPlan? _planVigente;

  // Datos de la feature (solo se cargan si la licencia está activa)
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

      // Refrescar licencia ignorando caché para reflejar acreditaciones
      // recientes hechas en backend.
      _licService.invalidate(idTienda);
      final results = await Future.wait([
        _licService.getLicenciaActual(idTienda),
        _licService.getPlanVigente(),
      ]);
      _licencia = results[0] as WapiLicencia?;
      _planVigente = results[1] as WapiLicenciaPlan?;

      // Solo cargamos sesiones/programación/logs cuando hay licencia activa.
      if (_licencia?.isActive == true) {
        await _reloadData();
      }
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

  // ── Gating: cualquier acción WAPI requiere licencia activa ─────────────
  bool _ensureActive() {
    if (_licencia?.isActive == true) return true;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Tu licencia WAPI no está activa.'),
      backgroundColor: Colors.red,
    ));
    return false;
  }

  // ── Solicitar licencia ─────────────────────────────────────────────────
  Future<void> _onSolicitarLicencia() async {
    if (_idTienda == null || _planVigente == null) return;
    final plan = _planVigente!;

    final esGratis = plan.esPruebaGratis;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esGratis ? 'Activar prueba gratuita' : 'Adquirir licencia'),
        content: Text(
          esGratis
              ? 'Solicitarás la prueba gratuita por ${plan.duracionMesesDefault} '
                  'mes(es). Tu solicitud quedará en verificación hasta que el '
                  'equipo de soporte la acredite.'
              : 'Solicitarás una licencia por ${plan.duracionMesesDefault} '
                  'mes(es) a US\$${plan.precioVigente.toStringAsFixed(2)}. '
                  'Tu solicitud quedará en verificación hasta que confirmemos '
                  'el pago.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            child: Text(esGratis ? 'Solicitar prueba' : 'Solicitar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final email = await UserPreferencesService().getUserEmail();
      final uid = await UserPreferencesService().getUserId();
      final solicitante = email ?? uid ?? 'desconocido';

      await _licService.solicitarLicencia(
        idTienda: _idTienda!,
        idPlan: plan.id,
        solicitadoPor: solicitante,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: AppColors.success,
        content: Text(
            '✅ Solicitud enviada. Te notificaremos cuando se acredite.'),
        duration: Duration(seconds: 4),
      ));
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error al solicitar licencia: $e')));
    }
  }

  // ── Acciones del módulo (solo accesibles con licencia activa) ──────────
  Future<void> _onAddBot() async {
    if (!_ensureActive() || _idTienda == null) return;
    final s = await WapiAddBotSheet.show(context, idTienda: _idTienda!);
    if (s == null || !mounted) return;
    await WapiQrDialog.show(context, idSesion: s.id, nombreBot: s.nombre);
    await _reloadData();
  }

  Future<void> _onSessionAction(WapiSession s, String action) async {
    // Permitimos siempre "details" como solo-lectura; el resto exige licencia.
    if (action != 'details' && !_ensureActive()) return;
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
    if (!_ensureActive()) return;

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
        builder: (_) => WapiProductSelectorScreen(
          idTienda: _idTienda!,
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
    if (!_ensureActive()) return;
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

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 800;
    final showSendButton =
        !_loading && _error == null && _licencia?.isActive == true;
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
          if (isWeb && showSendButton)
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
      floatingActionButton: (!isWeb && showSendButton)
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
              : _buildBody(isWeb),
    );
  }

  Widget _buildBody(bool isWeb) {
    // 1) Sin licencia o estados terminales → oferta
    final lic = _licencia;
    if (lic == null ||
        lic.estado == WapiLicenciaEstado.rechazada ||
        lic.estado == WapiLicenciaEstado.vencida ||
        lic.estado == WapiLicenciaEstado.cancelada ||
        lic.vencida) {
      return _WapiLicenseOfferView(
        plan: _planVigente,
        licenciaPrevia: lic, // para mostrar contexto si fue rechazada/vencida
        onSolicitar: _onSolicitarLicencia,
      );
    }

    // 2) En verificación → pantalla bloqueada
    if (lic.isEnVerificacion) {
      return _WapiLicensePendingView(
        licencia: lic,
        onRefresh: _bootstrap,
      );
    }

    // 3) Activa → UI completa
    return RefreshIndicator(
      onRefresh: _reloadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LicenseBadge(licencia: lic),
          const SizedBox(height: 14),
          _SectionHeader(
            icon: Icons.smart_toy,
            title: 'Bots activos',
            subtitle: '${_sesiones.length} sesión(es) registrada(s)',
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
            subtitle: 'Configura una difusión diaria automática',
            action: TextButton.icon(
              onPressed: _onConfigureSchedule,
              icon: const Icon(Icons.settings),
              label: Text(_programacion == null ? 'Configurar' : 'Editar'),
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
        title: 'Sin programación configurada',
        subtitle:
            'Elige hora, productos y destinatarios para activar el envío automático diario.',
        action: ElevatedButton.icon(
          onPressed: _onConfigureSchedule,
          icon: const Icon(Icons.add),
          label: const Text('Configurar'),
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
                    'Próximo envío: ${_formatNextRun(p.nextRunAt!)} '
                    '(${p.timezone})',
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
              if (!_ensureActive()) return;
              await _service.setProgramacionActiva(p.id, v);
              await _reloadData();
            },
          ),
        ],
      ),
    );
  }

  /// Formatea `nextRunAt` (UTC en el modelo) a la zona local del dispositivo
  /// en un formato legible — la zona IANA en la que se programó se muestra
  /// aparte para que el usuario entienda la correspondencia.
  String _formatNextRun(DateTime utc) {
    final local = utc.toLocal();
    // Sin locale: evita depender de initializeDateFormatting, que no se llama
    // en ningún sitio del proyecto.
    return DateFormat('dd/MM/yyyy HH:mm').format(local);
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
// Sub-widgets
// =========================================================================

/// Vista para usuarios sin licencia activa o con licencia terminal.
class _WapiLicenseOfferView extends StatelessWidget {
  final WapiLicenciaPlan? plan;
  final WapiLicencia? licenciaPrevia;
  final VoidCallback onSolicitar;
  const _WapiLicenseOfferView({
    required this.plan,
    required this.licenciaPrevia,
    required this.onSolicitar,
  });

  @override
  Widget build(BuildContext context) {
    if (plan == null) {
      return _ErrorState(
        error: 'No hay planes disponibles en este momento. '
            'Contacta al soporte.',
        onRetry: onSolicitar,
      );
    }
    final p = plan!;
    final esGratis = p.esPruebaGratis;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (licenciaPrevia != null) _PreviousLicenseNotice(licenciaPrevia!),
          if (licenciaPrevia != null) const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign,
                        color: Colors.white, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        p.denominacion,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18),
                      ),
                    ),
                    if (esGratis)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'GRATIS',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (p.descripcion != null && p.descripcion!.isNotEmpty)
                  Text(
                    p.descripcion!,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                  ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      esGratis
                          ? 'US\$0.00'
                          : 'US\$${p.precioVigente.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 28),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Text('/mes',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ),
                  ],
                ),
                if (esGratis && p.precioMensual > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Precio normal: US\$${p.precioMensual.toStringAsFixed(2)} — '
                    'gratis durante el periodo de prueba',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Duración: ${p.duracionMesesDefault} mes(es)',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _BulletItem(
              icon: Icons.smart_toy,
              text: 'Crea bots de WhatsApp y conéctalos por QR.'),
          _BulletItem(
              icon: Icons.send,
              text: 'Envío manual de catálogos a contactos y grupos.'),
          _BulletItem(
              icon: Icons.schedule,
              text: 'Envío automático diario programable.'),
          _BulletItem(
              icon: Icons.history,
              text: 'Historial completo de mensajes enviados.'),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.warning.withOpacity(0.4), width: 1),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    color: AppColors.warning, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Al solicitar, tu licencia quedará en verificación hasta '
                    'que el equipo de soporte la acredite. Normalmente esto '
                    'toma menos de 24 horas.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onSolicitar,
            icon: const Icon(Icons.rocket_launch),
            label: Text(
              esGratis ? 'Activar prueba gratis' : 'Adquirir licencia',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de aviso cuando hay una licencia previa (rechazada / vencida).
class _PreviousLicenseNotice extends StatelessWidget {
  final WapiLicencia licencia;
  const _PreviousLicenseNotice(this.licencia);

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String title;
    String? subtitle;
    switch (licencia.estado) {
      case WapiLicenciaEstado.rechazada:
        color = Colors.red;
        icon = Icons.cancel_outlined;
        title = 'Tu solicitud anterior fue rechazada';
        subtitle = licencia.notas;
        break;
      case WapiLicenciaEstado.vencida:
        color = AppColors.warning;
        icon = Icons.event_busy_outlined;
        title = 'Tu licencia anterior venció';
        subtitle = licencia.fechaFin == null
            ? null
            : 'El ${DateFormat('dd/MM/yyyy').format(licencia.fechaFin!.toLocal())}';
        break;
      case WapiLicenciaEstado.cancelada:
        color = AppColors.textLight;
        icon = Icons.block_outlined;
        title = 'Tu licencia anterior fue cancelada';
        subtitle = licencia.notas;
        break;
      default:
        // Si la licencia "activa" venció por fecha
        color = AppColors.warning;
        icon = Icons.event_busy_outlined;
        title = 'Tu licencia venció';
        subtitle = licencia.fechaFin == null
            ? null
            : 'El ${DateFormat('dd/MM/yyyy').format(licencia.fechaFin!.toLocal())}';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vista de licencia en verificación (bloquea toda la feature).
class _WapiLicensePendingView extends StatelessWidget {
  final WapiLicencia licencia;
  final VoidCallback onRefresh;
  const _WapiLicensePendingView({
    required this.licencia,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final dfmt = DateFormat('dd/MM/yyyy HH:mm');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_top,
                  color: AppColors.warning, size: 56),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Solicitud en revisión',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Te notificaremos cuando tu licencia quede acreditada. '
            'Normalmente esto toma menos de 24 horas.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _kv('Plan',
                    licencia.plan?.denominacion ?? 'WAPI'),
                _kv('Solicitada',
                    dfmt.format(licencia.fechaSolicitud.toLocal())),
                _kv('Duración', '${licencia.duracionMeses} mes(es)'),
                _kv(
                    'Monto',
                    licencia.montoPagado == 0
                        ? 'Gratis (prueba)'
                        : 'US\$${licencia.montoPagado.toStringAsFixed(2)}'),
                if (licencia.referenciaPago != null &&
                    licencia.referenciaPago!.isNotEmpty)
                  _kv('Referencia pago', licencia.referenciaPago!),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refrescar estado'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// Badge superior mostrado cuando la licencia está activa.
class _LicenseBadge extends StatelessWidget {
  final WapiLicencia licencia;
  const _LicenseBadge({required this.licencia});

  @override
  Widget build(BuildContext context) {
    final dias = licencia.diasRestantes;
    final nombrePlan = licencia.plan?.denominacion ?? 'Licencia WAPI';
    final showAlerta = dias != null && dias <= 7;
    final dfmt = DateFormat('dd/MM/yyyy');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$nombrePlan activa',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  licencia.fechaFin == null
                      ? 'Sin fecha de vencimiento.'
                      : dias != null && dias > 0
                          ? 'Vence el ${dfmt.format(licencia.fechaFin!.toLocal())} '
                              '($dias día(s) restantes)'
                          : 'Vence hoy (${dfmt.format(licencia.fechaFin!.toLocal())})',
                  style: TextStyle(
                      fontSize: 12,
                      color: showAlerta
                          ? Colors.yellow.shade100
                          : Colors.white70,
                      fontWeight: showAlerta
                          ? FontWeight.w600
                          : FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _BulletItem({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.textPrimary)),
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
