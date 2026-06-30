import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../config/app_theme.dart';
import '../models/campo_adicional.dart';
import '../models/servicio.dart';
import '../models/sala_espera.dart';
import '../models/disponibilidad_dia.dart';
import '../providers/auth_provider.dart';
import '../services/lista_service.dart';
import '../services/agenda_service.dart';
import '../widgets/datos_adicionales_form.dart';
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

    final datos = await _recolectarDatosReserva();
    if (datos == null || !mounted) return;

    setState(() => _isActing = true);
    try {
      await ListaService.entrarSalaEspera(
        uuidUsuario: uuid,
        idLocalServicio: widget.localServicio.id,
        fechaRegla: fecha,
        datosAdicionales:
            datos.datosAdicionales.isEmpty ? null : datos.datosAdicionales,
        paraTercero: datos.paraTercero,
        terceroNombre: datos.tNombre,
        terceroApellidos: datos.tApellidos,
        terceroCi: datos.tCi,
        terceroTelefono: datos.tTelefono,
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

  // ── Reserva directa: abre el calendario de disponibilidad ──
  Future<void> _reservarAhora() async {
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;

    setState(() => _isActing = true);
    List<DisponibilidadDia> dias;
    try {
      dias = await AgendaService.getDisponibilidad(widget.localServicio.id);
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
      return;
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
    if (!mounted) return;

    final sel = await showModalBottomSheet<({DateTime fecha, int cantidad})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DisponibilidadSheet(
        servicio: widget.localServicio.servicio,
        dias: dias,
      ),
    );
    if (sel == null || !mounted) return;

    final datos = await _recolectarDatosReserva();
    if (datos == null || !mounted) return;

    await _confirmarReservaDirecta(uuid, sel.fecha, sel.cantidad, datos);
  }

  Future<void> _confirmarReservaDirecta(
      String uuid, DateTime fecha, int cantidad, _DatosReserva datos) async {
    setState(() => _isActing = true);
    try {
      await AgendaService.reservarDirecto(
        uuidUsuario: uuid,
        idLocalServicio: widget.localServicio.id,
        fecha: fecha,
        cantidad: cantidad,
        datosAdicionales:
            datos.datosAdicionales.isEmpty ? null : datos.datosAdicionales,
        paraTercero: datos.paraTercero,
        terceroNombre: datos.tNombre,
        terceroApellidos: datos.tApellidos,
        terceroCi: datos.tCi,
        terceroTelefono: datos.tTelefono,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Reservado ${cantidad > 1 ? '($cantidad turnos) ' : ''}para el ${DateFormat('dd/MM/yyyy').format(fecha)}'),
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

  /// Flujo previo común a reserva directa y cola: si el servicio permite
  /// terceros pregunta "¿para ti o para alguien más?" (y pide el perfil del
  /// tercero), y si tiene campos adicionales los recolecta. Devuelve null si
  /// el usuario cancela. Si el servicio no requiere nada, devuelve datos vacíos
  /// sin mostrar diálogo.
  Future<_DatosReserva?> _recolectarDatosReserva() async {
    final servicio = widget.localServicio.servicio;
    final campos = servicio?.camposAdicionales ?? const <CampoAdicional>[];
    final permiteTercero = servicio?.permiteTercero ?? false;

    if (!permiteTercero && campos.isEmpty) {
      return const _DatosReserva(paraTercero: false, datosAdicionales: {});
    }

    return showModalBottomSheet<_DatosReserva>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DatosReservaSheet(
        campos: campos,
        permiteTercero: permiteTercero,
      ),
    );
  }

  Future<void> _cambiarFecha() async {
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null || _miLugar == null) return;

    final now = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _miLugar!.fechaRegla.isAfter(now)
          ? _miLugar!.fechaRegla
          : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: '¿A partir de qué fecha quieres el turno?',
      confirmText: 'Confirmar',
      cancelText: 'Cancelar',
    );
    if (fecha == null || !mounted) return;

    setState(() => _isActing = true);
    try {
      await ListaService.actualizarFechaRegla(
        uuidUsuario: uuid,
        idSalaEspera: _miLugar!.id,
        fechaRegla: fecha,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '📅 Fecha actualizada al ${DateFormat('dd/MM/yyyy').format(fecha)}'),
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
            color: Colors.white,
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
                  Row(
                    children: [
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
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isActing ? null : _cambiarFecha,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.edit_calendar,
                                  color: Colors.white, size: 13),
                              SizedBox(width: 5),
                              Text(
                                'Modificar fecha',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
    final permiteDirecta = widget.localServicio.permiteReservaDirecta;

    final Widget child;
    if (enLista) {
      child = OutlinedButton.icon(
        onPressed: _isActing ? null : _salir,
        icon: _isActing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.exit_to_app),
        label: const Text('Salir de la lista'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else if (permiteDirecta) {
      // Reserva directa habilitada: "Reservar ahora" (primaria) + lista (secundaria).
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: _isActing ? null : _reservarAhora,
            icon: _isActing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.event_available),
            label: const Text('Reservar ahora',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(0),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isActing ? null : _anotarse,
            icon: const Icon(Icons.playlist_add, size: 18),
            label: const Text('Anotarme en la lista'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: const BorderSide(color: AppTheme.primary),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      );
    } else {
      child = ElevatedButton.icon(
        onPressed: _isActing ? null : _anotarse,
        icon: _isActing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.playlist_add),
        label: const Text('Anotarme en la lista',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );
    }

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
          child: child,
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

/// Datos recolectados antes de reservar: tercero (si aplica) + datos adicionales.
class _DatosReserva {
  final bool paraTercero;
  final String? tNombre;
  final String? tApellidos;
  final String? tCi;
  final String? tTelefono;
  final Map<String, dynamic> datosAdicionales;

  const _DatosReserva({
    required this.paraTercero,
    this.tNombre,
    this.tApellidos,
    this.tCi,
    this.tTelefono,
    required this.datosAdicionales,
  });
}

/// Diálogo simple para elegir la cantidad de turnos en reserva directa.
class _CantidadDialog extends StatefulWidget {
  final DateTime fecha;
  final int maximo;
  const _CantidadDialog({required this.fecha, required this.maximo});

  @override
  State<_CantidadDialog> createState() => _CantidadDialogState();
}

class _CantidadDialogState extends State<_CantidadDialog> {
  int _cantidad = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('¿Cuántos turnos?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${DateFormat('dd/MM/yyyy').format(widget.fecha)} · ${widget.maximo} disponibles',
            style: const TextStyle(
                fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: _cantidad > 1
                    ? () => setState(() => _cantidad--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '$_cantidad',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _cantidad < widget.maximo
                    ? () => setState(() => _cantidad++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _cantidad),
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

/// Hoja para recolectar: ¿para ti o un tercero? + perfil del tercero + datos
/// adicionales configurados por el admin.
class _DatosReservaSheet extends StatefulWidget {
  final List<CampoAdicional> campos;
  final bool permiteTercero;

  const _DatosReservaSheet({
    required this.campos,
    required this.permiteTercero,
  });

  @override
  State<_DatosReservaSheet> createState() => _DatosReservaSheetState();
}

class _DatosReservaSheetState extends State<_DatosReservaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _datosKey = GlobalKey<DatosAdicionalesFormState>();
  bool _paraTercero = false;

  final _nombreCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _ciCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _apellidosCtrl.dispose();
    _ciCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final formOk = _formKey.currentState?.validate() ?? true;
    final datosOk = _datosKey.currentState?.validar() ?? true;
    if (!formOk || !datosOk) return;

    final valores = _datosKey.currentState?.valores ?? {};
    Navigator.pop(
      context,
      _DatosReserva(
        paraTercero: _paraTercero,
        tNombre: _paraTercero ? _nombreCtrl.text.trim() : null,
        tApellidos: _paraTercero ? _apellidosCtrl.text.trim() : null,
        tCi: _paraTercero ? _ciCtrl.text.trim() : null,
        tTelefono: _paraTercero ? _telefonoCtrl.text.trim() : null,
        datosAdicionales: valores,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            const Text('Datos de la reserva',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // ── ¿Para ti o alguien más? ──
            if (widget.permiteTercero) ...[
              const Text('¿Para quién es la reserva?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('Para mí'),
                      icon: Icon(Icons.person)),
                  ButtonSegment(
                      value: true,
                      label: Text('Para alguien más'),
                      icon: Icon(Icons.group_add)),
                ],
                selected: {_paraTercero},
                onSelectionChanged: (s) =>
                    setState(() => _paraTercero = s.first),
              ),
              const SizedBox(height: 16),
            ],

            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_paraTercero) ...[
                    const Text('Datos de la persona',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre *',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Requerido'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _apellidosCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Apellidos *',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Requerido'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ciCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Carné de identidad *',
                        prefixIcon: Icon(Icons.credit_card),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Requerido';
                        if (t.length != 11) return 'El CI debe tener 11 dígitos';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono *',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Requerido'
                          : null,
                    ),
                    if (widget.campos.isNotEmpty) const SizedBox(height: 16),
                  ],

                  // ── Datos adicionales del servicio ──
                  if (widget.campos.isNotEmpty) ...[
                    const Text('Información adicional',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    DatosAdicionalesForm(
                      key: _datosKey,
                      campos: widget.campos,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _confirmar,
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Continuar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hoja: calendario de disponibilidad para "Reservar ahora" ──
class _DisponibilidadSheet extends StatefulWidget {
  final Servicio? servicio;
  final List<DisponibilidadDia> dias;

  const _DisponibilidadSheet({required this.servicio, required this.dias});

  @override
  State<_DisponibilidadSheet> createState() => _DisponibilidadSheetState();
}

class _DisponibilidadSheetState extends State<_DisponibilidadSheet> {
  late final Map<String, DisponibilidadDia> _porDia;
  late DateTime _focusedDay;

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _porDia = {for (final d in widget.dias) _key(d.fecha): d};
    // Enfoca el primer día con cupo (o hoy si la lista está vacía).
    _focusedDay =
        widget.dias.isNotEmpty ? widget.dias.first.fecha : DateTime.now();
  }

  DisponibilidadDia? _disp(DateTime day) => _porDia[_key(day)];

  Future<void> _confirmar(DateTime day) async {
    final disp = _disp(day);
    if (disp == null || disp.disponibles <= 0) return;
    final fecha = DateTime(day.year, day.month, day.day);
    final maxCant = disp.disponibles;
    // Si solo hay 1 cupo, no preguntamos cantidad.
    if (maxCant <= 1) {
      if (!mounted) return;
      Navigator.pop(context, (fecha: fecha, cantidad: 1));
      return;
    }
    final cantidad = await showDialog<int>(
      context: context,
      builder: (_) => _CantidadDialog(fecha: fecha, maximo: maxCant),
    );
    if (cantidad == null || !mounted) return;
    Navigator.pop(context, (fecha: fecha, cantidad: cantidad));
  }

  @override
  Widget build(BuildContext context) {
    final vacio = widget.dias.isEmpty;
    final first = widget.dias.isNotEmpty
        ? widget.dias.first.fecha
        : DateTime.now();
    final last = widget.dias.isNotEmpty
        ? widget.dias.last.fecha
        : DateTime.now().add(const Duration(days: 90));

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.event_available,
                    size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reservar ahora',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(
                        widget.servicio?.nombre ?? 'Servicio',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (vacio)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 24, 40),
              child: Column(
                children: [
                  Icon(Icons.event_busy_outlined,
                      size: 56, color: AppTheme.textSecondary),
                  SizedBox(height: 12),
                  Text('No hay turnos disponibles',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text(
                    'Por ahora no quedan cupos para reservar.\nPuedes anotarte en la lista de espera.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12.5, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            )
          else ...[
            TableCalendar<DisponibilidadDia>(
              locale: 'es_ES',
              firstDay: DateTime.utc(first.year, first.month, 1),
              lastDay: DateTime.utc(last.year, last.month + 1, 0),
              focusedDay: _focusedDay,
              eventLoader: (day) {
                final d = _disp(day);
                return d != null && d.disponibles > 0 ? [d] : [];
              },
              enabledDayPredicate: (day) {
                final d = _disp(day);
                return d != null && d.disponibles > 0;
              },
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                disabledTextStyle:
                    TextStyle(color: Colors.grey.shade300),
                todayDecoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  final disp = events.first;
                  return Positioned(
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${disp.disponibles}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.success,
                        ),
                      ),
                    ),
                  );
                },
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                headerPadding: EdgeInsets.symmetric(vertical: 6),
              ),
              availableGestures: AvailableGestures.horizontalSwipe,
              onPageChanged: (f) => setState(() => _focusedDay = f),
              onDaySelected: (selected, focused) => _confirmar(selected),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: Text(
                'Toca un día con cupo para reservar. El número indica los turnos libres.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
