import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/plan_dia.dart';
import '../../models/recurso.dart';
import '../../models/servicio.dart';
import '../../services/agenda_admin_service.dart';
import '../../services/auth_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/plan_config_service.dart';
import '../../services/plan_servicio_service.dart';
import '../../services/recurso_service.dart';
import '../../tutorial/tutorial_anchor.dart';
import 'admin_reserva_transporte_sheet.dart';
import 'config_plan_mensual_screen.dart';
import 'config_recursos_screen.dart';
import 'gestion_servicios_screen.dart';
import 'planificacion_sheets.dart';
import 'promociones_screen.dart';

/// Pestañas de [LocalServicioAdminScreen].
enum PestanaLocalServicio { calendario, configuracion, promociones }

/// Nivel 3 de «Locales y servicios»: todo lo de UN servicio dentro de UN local.
///
/// Reúne lo que antes estaba repartido entre la tarjeta plegable de
/// Planificación y el detalle del servicio, en tres pestañas para que ninguna
/// quede cargada:
///  · Calendario: planificar días y reservar capacidad.
///  · Configuración: publicación, reserva directa, capacidades, recursos y
///    turnos y el plan mensual.
///  · Promociones del par local-servicio.
///
/// Devuelve `true` al salir si cambió algo que la lista de origen pinta
/// (estado, modo, o si se desvinculó).
class LocalServicioAdminScreen extends StatefulWidget {
  final LocalServicio localServicio;
  final int entidadId;
  final PestanaLocalServicio pestanaInicial;

  const LocalServicioAdminScreen({
    super.key,
    required this.localServicio,
    required this.entidadId,
    this.pestanaInicial = PestanaLocalServicio.calendario,
  });

  @override
  State<LocalServicioAdminScreen> createState() =>
      _LocalServicioAdminScreenState();
}

class _LocalServicioAdminScreenState extends State<LocalServicioAdminScreen> {
  /// Ancho máximo del contenido: en tablet y web el calendario y los ajustes no
  /// se estiran a toda la pantalla.
  static const double _anchoContenido = 760;

  late LocalServicio _ls;
  bool _huboCambios = false;

  // Calendario
  List<PlanDia> _planes = [];
  List<Recurso> _recursos = [];
  bool _cargandoPlanes = true;
  DateTime _focusedDay = DateTime.now();

  // Configuración
  bool _togglingActivo = false;
  bool _togglingDirecta = false;
  bool _activandoPadre = false;

  String get _uuid => AuthService.currentUserId ?? '';
  String get _nombreServicio => _ls.servicio?.nombre ?? 'Servicio';
  String get _nombreLocal => _ls.local?.nombre ?? 'Local';

  @override
  void initState() {
    super.initState();
    _ls = widget.localServicio;
    _cargarPlanes();
  }

  void _marcarCambio() => _huboCambios = true;

  void _avisar(String mensaje, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
  }

  // ── Datos ─────────────────────────────────────────────────────────────

  /// Relee el par desde la BD (modo, estado, capacidades) tras volver de una
  /// pantalla que puede haberlo cambiado.
  Future<void> _recargarLs() async {
    try {
      final ls = await CatalogoService.getLocalServicio(_ls.id);
      if (mounted) setState(() => _ls = ls);
    } catch (_) {
      // Se conserva lo que ya había en pantalla.
    }
  }

  Future<void> _cargarPlanes() async {
    setState(() => _cargandoPlanes = true);
    try {
      final recursos = await RecursoService.listar(
        uuidUsuario: _uuid,
        idLocalServicio: _ls.id,
      );
      final planes = await PlanConfigService.getPlanDias(
        uuidUsuario: _uuid,
        idLocalServicio: _ls.id,
      );
      if (!mounted) return;
      setState(() {
        _recursos = recursos.where((r) => r.activo).toList();
        _planes = planes;
      });
    } catch (e) {
      _avisar('No se pudo cargar la planificación: $e', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _cargandoPlanes = false);
    }
  }

  // ── Calendario ───────────────────────────────────────────────────────

  static String _clave(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, PlanDia> get _porDia => {for (final p in _planes) _clave(p.fecha): p};

  List<PlanDia> _planesDelDia(DateTime dia) {
    final p = _porDia[_clave(dia)];
    return p == null ? const [] : [p];
  }

  void _alTocarDia(DateTime dia) {
    final plan = _porDia[_clave(dia)];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DayOptionsSheet(
        dia: dia,
        tienePlan: plan != null && plan.cantidad > 0,
        puedeReservar: plan != null && plan.disponibles > 0,
        onVerPlanificacion: () {
          Navigator.pop(ctx);
          _planificarDia(dia, plan);
        },
        onReservar: () {
          Navigator.pop(ctx);
          _reservarCapacidad(dia, plan);
        },
      ),
    );
  }

  void _planificarDia(DateTime dia, PlanDia? plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PlanificarDiaSheet(
        ls: _ls,
        fecha: dia,
        recursos: _recursos,
        planActual: plan,
        onSaved: _cargarPlanes,
      ),
    );
  }

  void _reservarCapacidad(DateTime dia, PlanDia? plan) {
    if (plan == null || plan.disponibles <= 0) {
      _avisar(
        'No hay capacidad disponible para este día. '
        'Planifica el día o elige uno con cupo.',
        color: AppTheme.warning,
      );
      return;
    }
    void alCrear() {
      _cargarPlanes();
      _avisar('Reserva creada exitosamente', color: AppTheme.success);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ls.esTransporteOmnibus
          ? AdminReservaTransporteSheet(
              localServicio: _ls,
              diaInicial: dia,
              onCreated: alCrear,
            )
          : AdminReservationSheet(
              dia: dia,
              entidadId: widget.entidadId,
              localServicio: _ls,
              onReservationCreated: alCrear,
            ),
    );
  }

  // ── Configuración ────────────────────────────────────────────────────

  Future<void> _cambiarActivo(bool valor) async {
    setState(() => _togglingActivo = true);
    try {
      final ls = await CatalogoService.updateLocalServicio(
        id: _ls.id,
        activo: valor,
      );
      if (!mounted) return;
      // El update devuelve el par sin el tipo de actividad: se conserva el
      // servicio que ya teníamos para no perder ese dato.
      setState(() => _ls = ls.copyWith(servicio: _ls.servicio));
      _marcarCambio();
      _avisar(
        valor
            ? 'Servicio publicado en este local'
            : 'Servicio oculto: los clientes ya no lo ven ni pueden reservarlo',
        color: valor ? AppTheme.success : AppTheme.warning,
      );
    } catch (e) {
      _avisar('Error: $e', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _togglingActivo = false);
    }
  }

  Future<void> _cambiarReservaDirecta(bool valor) async {
    setState(() => _togglingDirecta = true);
    try {
      final permite = await CatalogoService.setReservaDirecta(
        uuidUsuario: _uuid,
        idLocalServicio: _ls.id,
        permite: valor,
      );
      if (!mounted) return;
      setState(() => _ls = _ls.copyWith(permiteReservaDirecta: permite));
      _marcarCambio();
    } catch (e) {
      _avisar('Error: $e', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _togglingDirecta = false);
    }
  }

  /// Activa el local o el servicio que deja oculto a este par aunque su propio
  /// interruptor esté encendido. Se resuelve aquí mismo para no mandar al admin
  /// a buscarlo en otra pantalla.
  Future<void> _activarPadre() async {
    setState(() => _activandoPadre = true);
    try {
      if (_ls.local?.activo == false) {
        await CatalogoService.setLocalActivo(id: _ls.idLocal, activo: true);
      } else if (_ls.servicio?.activo == false) {
        await CatalogoService.setServicioActivo(
          id: _ls.idServicio,
          activo: true,
        );
      }
      _marcarCambio();
      await _recargarLs();
      _avisar('Activado', color: AppTheme.success);
    } catch (e) {
      _avisar('Error: $e', color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _activandoPadre = false);
    }
  }

  void _editarCapacidades() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ConfigCapacidadesSheet(
        localServicio: _ls,
        onUpdated: (ls) {
          if (!mounted) return;
          setState(() => _ls = ls.copyWith(servicio: _ls.servicio));
          _avisar('Capacidades actualizadas', color: AppTheme.success);
        },
      ),
    );
  }

  Future<void> _abrirRecursos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConfigRecursosScreen(localServicio: _ls)),
    );
    // El modo (solo turnos / sin tramos) y los recursos pueden haber cambiado.
    _marcarCambio();
    await _recargarLs();
    await _cargarPlanes();
  }

  Future<void> _abrirPlanMensual() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfigPlanMensualScreen(localServicio: _ls),
      ),
    );
    await _cargarPlanes();
  }

  // ── Menú ─────────────────────────────────────────────────────────────

  Future<void> _editarServicio() async {
    final servicio = _ls.servicio;
    if (servicio == null) return;
    final actualizado = await showModalBottomSheet<Servicio>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          ServicioFormSheet(idEntidad: widget.entidadId, servicio: servicio),
    );
    if (actualizado == null || !mounted) return;
    _marcarCambio();
    setState(() => _ls = _ls.copyWith(servicio: actualizado));
  }

  Future<void> _desvincular() async {
    try {
      final planes = await PlanServicioService.getByLocalServicio(_ls.id);
      final reservas = await AgendaAdminService.listarAgendas(
        uuidUsuario: _uuid,
        idLocalServicio: _ls.id,
      );
      if (!mounted) return;
      final conDatos = planes.isNotEmpty || reservas.isNotEmpty;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            conDatos ? 'Desvincular con datos existentes' : 'Desvincular',
          ),
          content: Text(
            '¿Quitar «$_nombreServicio» de «$_nombreLocal»?'
            '${conDatos ? '\n\nSe eliminarán de forma permanente:'
                      '${planes.isNotEmpty ? '\n• ${planes.length} plan(es) de servicio' : ''}'
                      '${reservas.isNotEmpty ? '\n• ${reservas.length} reserva(s)' : ''}' : ''}'
            '\n\nEl servicio sigue en el catálogo y en los demás locales.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(conDatos ? 'Desvincular y eliminar' : 'Desvincular'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
      for (final plan in planes) {
        await PlanServicioService.delete(plan.id);
      }
      await CatalogoService.deleteLocalServicio(_ls.id);
      if (!mounted) return;
      _avisar('Servicio desvinculado del local', color: AppTheme.success);
      Navigator.pop(context, true);
    } catch (e) {
      _avisar('Error al desvincular: $e', color: AppTheme.error);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _huboCambios);
      },
      child: DefaultTabController(
        length: PestanaLocalServicio.values.length,
        initialIndex: widget.pestanaInicial.index,
        child: Scaffold(
          backgroundColor: AppTheme.surface,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_nombreServicio, overflow: TextOverflow.ellipsis),
                Text(
                  _nombreLocal,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Más opciones',
                onSelected: (v) {
                  if (v == 'editar') _editarServicio();
                  if (v == 'desvincular') _desvincular();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'editar',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Editar servicio'),
                      subtitle: Text('Afecta a todos los locales'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'desvincular',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.link_off, color: AppTheme.error),
                      title: Text(
                        'Quitar de este local',
                        style: TextStyle(color: AppTheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // La AppBar es azul primario: con los colores por defecto del
            // TabBar (primario / gris) las pestañas no se leían. Blanco para la
            // seleccionada y blanco atenuado para las demás.
            bottom: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.78),
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Calendario'),
                Tab(icon: Icon(Icons.tune), text: 'Configuración'),
                Tab(icon: Icon(Icons.local_offer_outlined), text: 'Promociones'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _centrado(_buildCalendario()),
              _centrado(_buildConfiguracion()),
              _centrado(
                PromocionesScreen(
                  idLocalServicio: _ls.id,
                  nombreServicio: '$_nombreServicio · $_nombreLocal',
                  embebida: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centrado(Widget hijo) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _anchoContenido),
      child: hijo,
    ),
  );

  /// Motivo por el que el par no se ve aunque su interruptor esté encendido.
  String? get _motivoOculto {
    if (!_ls.activo) return null;
    if (_ls.local?.activo == false) {
      return 'El local «$_nombreLocal» está inactivo, así que este servicio '
          'no se ve.';
    }
    if (_ls.servicio?.activo == false) {
      return 'El servicio «$_nombreServicio» está inactivo en el catálogo: '
          'no se ve en ningún local.';
    }
    return null;
  }

  Widget _buildCalendario() {
    return RefreshIndicator(
      onRefresh: _cargarPlanes,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!_ls.activoEfectivo) ...[
            _Aviso(
              texto: _ls.activo
                  ? (_motivoOculto ?? 'Este servicio no está visible.')
                  : 'Oculto: los clientes no ven este servicio en este local. '
                        'Publícalo en Configuración.',
            ),
            const SizedBox(height: 12),
          ],
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: _cargandoPlanes
                ? const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : CalendarioConPlanes(
                    focusedDay: _focusedDay,
                    planesDelDia: _planesDelDia,
                    onDayTapped: _alTocarDia,
                    onPageChanged: (f) => setState(() => _focusedDay = f),
                  ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Toca un día para planificarlo o reservar capacidad. Para abrir un '
            'mes entero usa «Plan mensual» en Configuración.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildConfiguracion() {
    final motivo = _motivoOculto;
    final modo = _ls.soloTurnos
        ? 'Modo simple: solo turnos'
        : _ls.sinTramos
        ? 'Modo simple: recursos y turnos, sin tramos'
        : 'Recursos, tramos y turnos';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Primero qué significa cada cosa; debajo, los ajustes. Así los
        // ajustes solo dicen su estado y no repiten la explicación.
        const _Glosario(
          entradas: [
            _EntradaGlosario(
              icono: Icons.visibility_outlined,
              titulo: 'Disponible para clientes',
              texto: 'Si este servicio aparece en el catálogo de este local y '
                  'admite reservas. Para verse, el local y el servicio también '
                  'tienen que estar activos.',
            ),
            _EntradaGlosario(
              icono: Icons.flash_on_outlined,
              titulo: 'Reserva directa',
              texto: 'El cliente reserva al instante si hay cupo. Apagada, se '
                  'anota en la lista de espera y lo atiendes por orden.',
            ),
            _EntradaGlosario(
              icono: Icons.confirmation_number_outlined,
              titulo: 'Capacidad por reserva',
              texto: 'Cuántos lugares ocupa una reserva por defecto y el máximo '
                  'que un cliente puede pedir de una vez.',
            ),
            _EntradaGlosario(
              icono: Icons.widgets_outlined,
              titulo: 'Recursos y turnos',
              texto: 'Recurso: lo que se ocupa (silla, carro, mesa). Tramo: '
                  'parte del recurso que comparte el cupo (ida, vuelta). Turno: '
                  'la opción que elige el cliente, con su horario y precio. En '
                  'modo simple solo defines turnos.',
            ),
            _EntradaGlosario(
              icono: Icons.event_repeat,
              titulo: 'Plan mensual',
              texto: 'La capacidad de cada día de la semana. Al generar el mes '
                  'se crean los días reservables: sin días generados, nadie '
                  'puede reservar.',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Seccion(
          titulo: 'Visibilidad',
          children: [
            SwitchListTile(
              value: _ls.activo,
              onChanged: _togglingActivo ? null : _cambiarActivo,
              secondary: Icon(
                _ls.activo
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _ls.activo ? AppTheme.success : AppTheme.textSecondary,
              ),
              title: const Text('Disponible para clientes'),
              subtitle: Text(_ls.activo ? 'Publicado' : 'Oculto'),
            ),
            if (motivo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _Aviso(
                  texto: motivo,
                  accion: _activandoPadre
                      ? null
                      : TextButton(
                          onPressed: _activarPadre,
                          child: Text(
                            _ls.local?.activo == false
                                ? 'Activar local'
                                : 'Activar servicio',
                          ),
                        ),
                ),
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            TutorialAnchor(
              id: 'admin_reserva_directa',
              child: SwitchListTile(
                value: _ls.permiteReservaDirecta,
                onChanged: _togglingDirecta ? null : _cambiarReservaDirecta,
                secondary: Icon(
                  _ls.permiteReservaDirecta
                      ? Icons.flash_on
                      : Icons.flash_off_outlined,
                  color: _ls.permiteReservaDirecta
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                ),
                title: const Text('Reserva directa'),
                subtitle: Text(
                  _ls.permiteReservaDirecta
                      ? 'Activada'
                      : 'Apagada · los clientes usan la lista de espera',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Seccion(
          titulo: 'Capacidad',
          children: [
            TutorialAnchor(
              id: 'admin_capacidades',
              child: ListTile(
                leading: const Icon(
                  Icons.confirmation_number_outlined,
                  color: AppTheme.accent,
                ),
                title: const Text('Capacidad por reserva'),
                subtitle: Text(
                  'Por defecto ${_ls.cantidadDefault} · '
                  'máximo ${_ls.cantidadMaxCapacidad}',
                ),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: _editarCapacidades,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Seccion(
          titulo: 'Planificación',
          children: [
            ListTile(
              leading: Icon(
                _ls.ocultaTramos
                    ? Icons.schedule_outlined
                    : Icons.widgets_outlined,
                color: AppTheme.primaryDark,
              ),
              title: Text(_ls.soloTurnos ? 'Turnos y horarios' : 'Recursos y turnos'),
              subtitle: Text(modo),
              trailing: const Icon(Icons.chevron_right),
              onTap: _abrirRecursos,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.event_repeat, color: AppTheme.primary),
              title: const Text('Plan mensual'),
              subtitle: const Text('Configurar y generar los días del mes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _abrirPlanMensual,
            ),
          ],
        ),
      ],
    );
  }
}

/// Una definición del glosario de la pestaña de configuración.
class _EntradaGlosario {
  final IconData icono;
  final String titulo;
  final String texto;

  const _EntradaGlosario({
    required this.icono,
    required this.titulo,
    required this.texto,
  });
}

/// Explicación de los conceptos, encima de los ajustes.
class _Glosario extends StatelessWidget {
  final List<_EntradaGlosario> entradas;

  const _Glosario({required this.entradas});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: AppTheme.primary),
              SizedBox(width: 6),
              Text(
                'Qué es cada cosa',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final e in entradas)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(e.icono, size: 16, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${e.titulo}. ',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          TextSpan(text: e.texto),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bloque con título de la pestaña de configuración.
class _Seccion extends StatelessWidget {
  final String titulo;
  final List<Widget> children;

  const _Seccion({required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            titulo.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// Aviso en ámbar, con una acción opcional para resolverlo en el sitio.
class _Aviso extends StatelessWidget {
  final String texto;
  final Widget? accion;

  const _Aviso({required this.texto, this.accion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          if (accion != null) accion!,
        ],
      ),
    );
  }
}
