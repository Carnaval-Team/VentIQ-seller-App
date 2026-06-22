import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/servicio.dart';
import '../models/sala_espera.dart';
import '../providers/auth_provider.dart';
import '../services/lista_service.dart';
import '../widgets/net_image.dart';

class LocalServicioDetailScreen extends StatefulWidget {
  final LocalServicio localServicio;

  const LocalServicioDetailScreen({super.key, required this.localServicio});

  @override
  State<LocalServicioDetailScreen> createState() =>
      _LocalServicioDetailScreenState();
}

class _LocalServicioDetailScreenState
    extends State<LocalServicioDetailScreen> {
  bool _isLoading = true;
  bool _isActing = false;
  SalaEspera? _miLugar;
  int _ultimoOtorgado = 0;
  int _ultimoEnAnotarse = 0;
  bool _terminosExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final uuid = context.read<AuthProvider>().user?.id ?? '';
      final results = await Future.wait([
        ListaService.getMisListas(uuid),
        ListaService.getContadoresCola(widget.localServicio.id),
      ]);
      final listas = results[0] as List<SalaEspera>;
      final contadores =
          results[1] as ({int ultimoOtorgado, int ultimoEnAnotarse});
      final miLugar = listas
          .where((s) => s.idLocalServicio == widget.localServicio.id)
          .firstOrNull;
      if (mounted) {
        setState(() {
          _miLugar = miLugar;
          _ultimoOtorgado = contadores.ultimoOtorgado;
          _ultimoEnAnotarse = contadores.ultimoEnAnotarse;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _anotarse() async {
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;

    final now = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: '¿A partir de qué fecha quieres el turno?',
      confirmText: 'Confirmar',
      cancelText: 'Cancelar',
    );
    if (fecha == null || !mounted) return;

    setState(() => _isActing = true);
    try {
      await ListaService.entrarSalaEspera(
        uuidUsuario: uuid,
        idLocalServicio: widget.localServicio.id,
        fechaRegla: fecha,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Anotado para el ${DateFormat('dd/MM/yyyy').format(fecha)}'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _salir() async {
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Salir de la lista'),
        content: const Text('¿Deseas salir de la cola de espera?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isActing = true);
    try {
      await ListaService.salirSalaEspera(
        uuidUsuario: uuid,
        idLocalServicio: widget.localServicio.id,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saliste de la lista'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.localServicio.local;
    final servicio = widget.localServicio.servicio;
    final enLista = _miLugar != null;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildHeader(local, servicio),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (enLista) _buildMiTurnoCard(),
                          if (enLista) const SizedBox(height: 14),
                          _buildContadoresCard(),
                          const SizedBox(height: 14),
                          _buildInfoCard(local, servicio),
                          if (local?.terminosCondiciones != null &&
                              local!.terminosCondiciones!.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _buildTerminosCard(local.terminosCondiciones!),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _isLoading ? null : _buildBottomBar(),
    );
  }

  // ── Header colapsable tipo hero: foto del local de fondo + degradado de
  //    marca encima, con el nombre del servicio y del local. ──
  Widget _buildHeader(Local? local, Servicio? servicio) {
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        titlePadding: const EdgeInsets.fromLTRB(54, 0, 16, 14),
        title: Text(
          servicio?.nombre ?? 'Servicio',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: -0.3,
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (local?.foto != null && local!.foto!.isNotEmpty)
              NetImage(
                url: local!.foto!,
                fit: BoxFit.cover,
                placeholder: () => _headerFallback(),
                errorWidget: () => _headerFallback(),
              )
            else
              _headerFallback(),
            // Velo degradado para legibilidad del título.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x22000000),
                    Color(0x00000000),
                    Color(0xCC0D47A1),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            // Pastilla con el nombre del local.
            if (local != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 44,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storefront,
                              size: 14, color: AppTheme.primary),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 220),
                            child: Text(
                              local.nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _headerFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
      ),
      child: Center(
        child: Icon(Icons.storefront_outlined,
            size: 64, color: Colors.white24),
      ),
    );
  }

  // ── Tarjeta "ticket" con tu turno actual ──
  Widget _buildMiTurnoCard() {
    final mi = _miLugar!;
    final esTurno = mi.esSuTurno;
    final delante = mi.personasDelante - 1;
    final accent = esTurno ? AppTheme.success : AppTheme.primary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: esTurno
              ? [const Color(0xFF2E7D32), AppTheme.success]
              : [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.30),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            // Número grande tipo ticket.
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('N°',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  Text(
                    '${mi.numeroCola}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(esTurno ? Icons.notifications_active : Icons.event_seat,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          esTurno ? '¡Es tu turno!' : 'Estás en la lista',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    esTurno
                        ? 'Acércate, ya casi te toca'
                        : (delante <= 0
                            ? 'Eres el siguiente'
                            : '$delante ${delante == 1 ? 'persona' : 'personas'} delante de ti'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today,
                            color: Colors.white, size: 12),
                        const SizedBox(width: 5),
                        Text(
                          'Desde ${DateFormat('dd/MM/yyyy').format(mi.fechaRegla)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Contadores de la cola ──
  Widget _buildContadoresCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
        child: Row(
          children: [
            Expanded(
              child: _StatItem(
                label: 'Último atendido',
                value: '$_ultimoOtorgado',
                icon: Icons.check_circle_outline,
                color: AppTheme.primary,
              ),
            ),
            Container(width: 1, height: 48, color: AppTheme.border),
            Expanded(
              child: _StatItem(
                label: 'Último anotado',
                value: '$_ultimoEnAnotarse',
                icon: Icons.person_add_outlined,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Información del local y el servicio ──
  Widget _buildInfoCard(Local? local, Servicio? servicio) {
    final rows = <Widget>[];

    if (servicio?.descripcion != null &&
        servicio!.descripcion!.isNotEmpty) {
      rows.add(_InfoRow(
        icon: Icons.design_services_outlined,
        label: 'Sobre el servicio',
        value: servicio.descripcion!,
      ));
    }
    if (local?.horarioAtencion != null &&
        local!.horarioAtencion!.isNotEmpty) {
      rows.add(_InfoRow(
        icon: Icons.access_time,
        label: 'Horario de atención',
        value: local.horarioAtencion!,
      ));
    }
    if (local?.direccion != null && local!.direccion!.isNotEmpty) {
      rows.add(_InfoRow(
        icon: Icons.location_on_outlined,
        label: 'Dirección',
        value: local.direccion!,
      ));
    }
    if (local?.ubicacion.isNotEmpty == true) {
      rows.add(_InfoRow(
        icon: Icons.location_city_outlined,
        label: 'Ubicación',
        value: local!.ubicacion,
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Información'),
            const SizedBox(height: 8),
            for (int i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1)
                const Divider(height: 22, color: AppTheme.border),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Términos y condiciones (expandible) ──
  Widget _buildTerminosCard(String terminos) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () =>
                  setState(() => _terminosExpanded = !_terminosExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined,
                        size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Términos y condiciones',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary)),
                    ),
                    AnimatedRotation(
                      turns: _terminosExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more,
                          color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  terminos,
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppTheme.textSecondary),
                ),
              ),
              crossFadeState: _terminosExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  // ── Barra de acción fija abajo ──
  Widget _buildBottomBar() {
    final enLista = _miLugar != null;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: enLista
              ? OutlinedButton.icon(
                  onPressed: _isActing ? null : _salir,
                  icon: _isActing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.exit_to_app),
                  label: const Text('Salir de la lista'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: _isActing ? null : _anotarse,
                  icon: _isActing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.playlist_add),
                  label: const Text('Anotarme en la lista',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}
