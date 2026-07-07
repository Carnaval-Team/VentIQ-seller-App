import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../models/plan_servicio.dart';
import '../../models/servicio.dart';
import '../../providers/auth_provider.dart';
import '../../services/agenda_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/plan_servicio_service.dart';
import '../../services/agenda_admin_service.dart';
import '../../widgets/datos_adicionales_form.dart';
import 'config_plan_mensual_screen.dart';

class PlanificacionScreen extends StatefulWidget {
  final Entidad entidad;
  const PlanificacionScreen({super.key, required this.entidad});

  @override
  State<PlanificacionScreen> createState() => _PlanificacionScreenState();
}

class _PlanificacionScreenState extends State<PlanificacionScreen> {
  List<LocalServicio> _localServicios = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final locales =
          await CatalogoService.getLocalesByEntidad(widget.entidad.id);
      final List<LocalServicio> todos = [];
      for (final local in locales) {
        final ls = await CatalogoService.getLocalServicios(idLocal: local.id);
        todos.addAll(ls);
      }
      todos.sort((a, b) {
        final cmp =
            (a.local?.nombre ?? '').compareTo(b.local?.nombre ?? '');
        if (cmp != 0) return cmp;
        return (a.servicio?.nombre ?? '')
            .compareTo(b.servicio?.nombre ?? '');
      });
      if (mounted) setState(() => _localServicios = todos);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al cargar: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _vincular() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _PlanFormSheet(entidad: widget.entidad, onCreated: _cargar),
    );
  }

  Future<void> _desvincular(LocalServicio ls) async {
    try {
      // Check for existing planning
      final planes = await PlanServicioService.getByLocalServicio(ls.id);
      
      // Check for existing reservations
      final auth = context.read<AuthProvider>();
      final reservas = await AgendaAdminService.listarAgendas(
        uuidUsuario: auth.user?.id ?? '',
        idLocalServicio: ls.id,
      );

      // Build confirmation message
      String mensaje = '¿Desvincular "${ls.servicio?.nombre ?? ''}" de "${ls.local?.nombre ?? ''}"?';
      
      if (planes.isNotEmpty || reservas.isNotEmpty) {
        mensaje += '\n\n⚠️ **ADVERTENCIA**: Se encontrará lo siguiente:\n';
        
        if (planes.isNotEmpty) {
          mensaje += '• ${planes.length} plan(es) de servicio\n';
        }
        
        if (reservas.isNotEmpty) {
          mensaje += '• ${reservas.length} reserva(s) agendada(s)\n';
        }
        
        mensaje += '\n**Esta acción eliminará permanentemente toda la planificación y reservas asociadas.**';
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(planes.isNotEmpty || reservas.isNotEmpty ? '⚠️ Desvincular con Datos Existentes' : 'Desvincular'),
          content: Text(mensaje),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Desvincular y Eliminar Todo'),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Eliminando planificación y reservas...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      // Delete all planning first
      for (final plan in planes) {
        await PlanServicioService.delete(plan.id);
      }

      // Delete the local service (this should cascade delete reservations)
      await CatalogoService.deleteLocalServicio(ls.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              planes.isNotEmpty || reservas.isNotEmpty 
                ? 'Servicio desvinculado. Se eliminaron ${planes.length} plan(es) y ${reservas.length} reserva(s).'
                : 'Servicio desvinculado correctamente'
            ),
            backgroundColor: AppTheme.success,
          ),
        );
      }
      
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al desvincular: $e'), 
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  // Agrupa por local
  Map<String, List<LocalServicio>> get _porLocal {
    final map = <String, List<LocalServicio>>{};
    for (final ls in _localServicios) {
      final key = ls.local?.nombre ?? 'Sin local';
      map.putIfAbsent(key, () => []).add(ls);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Planificación'),
            Text(widget.entidad.denominacion,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Vincular servicio a local',
            onPressed: _vincular,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _localServicios.isEmpty
              ? _EmptyState(onAdd: _vincular)
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: _buildLista(),
                ),
      floatingActionButton: _localServicios.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _vincular,
              icon: const Icon(Icons.add_link),
              label: const Text('Vincular'),
            )
          : null,
    );
  }

  Widget _buildLista() {
    final grupos = _porLocal;
    final localNames = grupos.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: localNames.length,
      itemBuilder: (_, i) {
        final localNombre = localNames[i];
        final items = grupos[localNombre]!;
        return _LocalGroup(
          localNombre: localNombre,
          local: items.first.local,
          items: items,
          onDesvincular: _desvincular,
          entidadId: widget.entidad.id,
        );
      },
    );
  }
}

// ── Grupo por local ───────────────────────────────────────────
class _LocalGroup extends StatelessWidget {
  final String localNombre;
  final Local? local;
  final List<LocalServicio> items;
  final Future<void> Function(LocalServicio) onDesvincular;
  final int entidadId;

  const _LocalGroup({
    required this.localNombre,
    required this.local,
    required this.items,
    required this.onDesvincular,
    required this.entidadId,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera de local
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.store_outlined,
                    size: 16, color: AppTheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(localNombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    if (local?.ubicacion.isNotEmpty == true)
                      Text(local!.ubicacion,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    '${items.length} servicio${items.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        // Un _ServicioCalendarTile por cada local-servicio
        ...items.map((ls) => _ServicioCalendarTile(
              ls: ls,
              onDesvincular: () => onDesvincular(ls),
              entidadId: entidadId,
            )),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Tile con ExpansionTile + calendario ───────────────────────
class _ServicioCalendarTile extends StatefulWidget {
  final LocalServicio ls;
  final VoidCallback onDesvincular;
  final int entidadId;

  const _ServicioCalendarTile(
      {required this.ls, required this.onDesvincular, required this.entidadId});

  @override
  State<_ServicioCalendarTile> createState() => _ServicioCalendarTileState();
}

class _ServicioCalendarTileState extends State<_ServicioCalendarTile> {
  List<PlanServicio> _planes = [];
  bool _loadingPlanes = false;
  bool _expanded = false;
  DateTime _focusedDay = DateTime.now();
  late bool _permiteDirecta;
  bool _togglingDirecta = false;

  @override
  void initState() {
    super.initState();
    _permiteDirecta = widget.ls.permiteReservaDirecta;
  }

  Future<void> _toggleReservaDirecta(bool value) async {
    final uuid = context.read<AuthProvider>().user?.id ?? '';
    setState(() {
      _permiteDirecta = value; // optimista
      _togglingDirecta = true;
    });
    try {
      await CatalogoService.setReservaDirecta(
        uuidUsuario: uuid,
        idLocalServicio: widget.ls.id,
        permite: value,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _permiteDirecta = !value); // revertir
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingDirecta = false);
    }
  }

  void _abrirConfigMensual() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConfigPlanMensualScreen(
          localServicio: widget.ls.copyWith(
              permiteReservaDirecta: _permiteDirecta),
        ),
      ),
    ).then((_) => _cargarPlanes());
  }

  void _abrirConfigCapacidades() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ConfigCapacidadesSheet(
        localServicio: widget.ls,
        onUpdated: (ls) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Capacidades actualizadas'),
                backgroundColor: AppTheme.success,
              ),
            );
          }
        },
      ),
    );
  }

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, List<PlanServicio>> get _porDia {
    final map = <String, List<PlanServicio>>{};
    for (final p in _planes) {
      if (p.fecha == null) continue;
      map.putIfAbsent(_dayKey(p.fecha!), () => []).add(p);
    }
    return map;
  }

  List<PlanServicio> _planesDelDia(DateTime day) =>
      _porDia[_dayKey(day)] ?? [];

  Future<void> _cargarPlanes() async {
    setState(() => _loadingPlanes = true);
    try {
      final planes =
          await PlanServicioService.getByLocalServicio(widget.ls.id);
      if (mounted) setState(() => _planes = planes);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingPlanes = false);
    }
  }

  void _onDayTapped(DateTime day) {
    final planes = _planesDelDia(day);
    if (planes.isNotEmpty) {
      _mostrarOpcionesDia(day, planes);
    } else {
      _mostrarOpcionesDia(day, []);
    }
  }

  void _mostrarOpcionesDia(DateTime dia, List<PlanServicio> planes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DayOptionsSheet(
        dia: dia,
        planes: planes,
        onVerPlanificacion: () {
          Navigator.pop(context);
          if (planes.isNotEmpty) {
            _mostrarInfoDia(dia, planes);
          } else {
            _mostrarCrearPlan(dia);
          }
        },
        onReservar: () {
          Navigator.pop(context);
          _mostrarReservarCapacidad(dia);
        },
      ),
    );
  }

  void _mostrarReservarCapacidad(DateTime dia) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AdminReservationSheet(
        dia: dia,
        entidadId: widget.entidadId,
        localServicio: widget.ls,
        onReservationCreated: () => _cargarPlanes(),
      ),
    );
  }

  void _mostrarInfoDia(DateTime dia, List<PlanServicio> planes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DayInfoSheet(
        dia: dia,
        planes: planes,
        onUpdated: _cargarPlanes,
      ),
    );
  }

  void _mostrarCrearPlan(DateTime fecha) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CrearPlanSheet(
        ls: widget.ls,
        fechaInicial: fecha,
        onCreated: _cargarPlanes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: EdgeInsets.zero,
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.miscellaneous_services_outlined,
                size: 18, color: AppTheme.accent),
          ),
          title: Text(
            widget.ls.servicio?.nombre ?? '—',
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: widget.ls.servicio?.descripcion != null
              ? Text(
                  widget.ls.servicio!.descripcion!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.link_off,
                    size: 17, color: AppTheme.error),
                tooltip: 'Desvincular',
                onPressed: widget.onDesvincular,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              Icon(
                _expanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
          onExpansionChanged: (v) {
            setState(() => _expanded = v);
            if (v && _planes.isEmpty) _cargarPlanes();
          },
          children: [
            const Divider(height: 1),
            // Toggle de reserva directa
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              dense: true,
              value: _permiteDirecta,
              onChanged: _togglingDirecta ? null : _toggleReservaDirecta,
              secondary: Icon(
                _permiteDirecta
                    ? Icons.flash_on
                    : Icons.flash_off_outlined,
                color: _permiteDirecta
                    ? AppTheme.success
                    : AppTheme.textSecondary,
              ),
              title: const Text('Reserva directa',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Permite reservar al instante si hay cupo (sin cola)',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary),
              ),
            ),
            // Acceso a la configuración mensual recurrente
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                onPressed: _abrirConfigMensual,
                icon: const Icon(Icons.event_repeat, size: 18),
                label: const Text('Configuración mensual'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            // Configuración de capacidades por reserva
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: OutlinedButton.icon(
                onPressed: _abrirConfigCapacidades,
                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                label: const Text('Capacidades por reserva'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  side: BorderSide(
                      color: AppTheme.accent.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const Divider(height: 1),
            if (_loadingPlanes)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _CalendarioConPlanes(
                planes: _planes,
                focusedDay: _focusedDay,
                planesDelDia: _planesDelDia,
                onDayTapped: _onDayTapped,
                onPageChanged: (f) => setState(() => _focusedDay = f),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Calendario con marcadores ─────────────────────────────────
class _CalendarioConPlanes extends StatelessWidget {
  final List<PlanServicio> planes;
  final DateTime focusedDay;
  final List<PlanServicio> Function(DateTime) planesDelDia;
  final void Function(DateTime) onDayTapped;
  final void Function(DateTime) onPageChanged;

  const _CalendarioConPlanes({
    required this.planes,
    required this.focusedDay,
    required this.planesDelDia,
    required this.onDayTapped,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar<PlanServicio>(
          locale: 'es_ES',
          firstDay: DateTime.utc(2024, 1, 1),
          lastDay: DateTime.utc(2027, 12, 31),
          focusedDay: focusedDay,
          eventLoader: planesDelDia,
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.25),
              shape: BoxShape.circle,
            ),
            selectedDecoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            markerDecoration: const BoxDecoration(
              color: AppTheme.accent,
              shape: BoxShape.circle,
            ),
            markersMaxCount: 1,
            markerSize: 6,
            markerMargin: const EdgeInsets.only(top: 1),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, day, events) {
              if (events.isEmpty) return null;
              final plan = events.first as PlanServicio;
              final color = plan.estaLleno
                  ? AppTheme.error
                  : plan.disponibles < (plan.cantidad * 0.2).ceil()
                      ? AppTheme.warning
                      : AppTheme.success;
              return Positioned(
                bottom: 4,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle),
                ),
              );
            },
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            headerPadding: EdgeInsets.symmetric(vertical: 6),
          ),
          onDaySelected: (selected, focused) => onDayTapped(selected),
          onPageChanged: onPageChanged,
          availableGestures: AvailableGestures.horizontalSwipe,
        ),
        // Leyenda
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              _LegendaDot(color: AppTheme.success, label: 'Disponible'),
              SizedBox(width: 14),
              _LegendaDot(color: AppTheme.warning, label: 'Casi lleno'),
              SizedBox(width: 14),
              _LegendaDot(color: AppTheme.error, label: 'Lleno'),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendaDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendaDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppTheme.textSecondary)),
      ],
    );
  }
}

// ── Sheet: info del día (planes existentes) ───────────────────
class _DayInfoSheet extends StatefulWidget {
  final DateTime dia;
  final List<PlanServicio> planes;
  final VoidCallback onUpdated;

  const _DayInfoSheet(
      {required this.dia,
      required this.planes,
      required this.onUpdated});

  @override
  State<_DayInfoSheet> createState() => _DayInfoSheetState();
}

class _DayInfoSheetState extends State<_DayInfoSheet> {
  bool _saving = false;

  Future<void> _editarCantidad(PlanServicio plan) async {
    final ctrl =
        TextEditingController(text: plan.cantidad.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modificar cantidad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agendados: ${plan.agendados}  ·  Mínimo: ${plan.agendados}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nueva cantidad',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < plan.agendados) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('Mínimo permitido: ${plan.agendados}'),
                  backgroundColor: AppTheme.error,
                ));
                return;
              }
              Navigator.pop(context, v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await PlanServicioService.update(
          id: plan.id, fecha: plan.fecha, cantidad: result);
      widget.onUpdated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _eliminar(PlanServicio plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar plan'),
        content: const Text('¿Eliminar este plan del día?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await PlanServicioService.delete(plan.id);
      widget.onUpdated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const Icon(Icons.calendar_today,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    DateFormat('EEEE, dd \'de\' MMMM yyyy', 'es')
                        .format(widget.dia),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: widget.planes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final plan = widget.planes[i];
                final pct = plan.cantidad > 0
                    ? plan.agendados / plan.cantidad
                    : 0.0;
                final color = pct >= 1.0
                    ? AppTheme.error
                    : pct >= 0.8
                        ? AppTheme.warning
                        : AppTheme.success;
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${plan.agendados} / ${plan.cantidad}',
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct.clamp(0.0, 1.0),
                                  backgroundColor:
                                      color.withOpacity(0.1),
                                  valueColor:
                                      AlwaysStoppedAnimation(color),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppTheme.primary, size: 18),
                              tooltip: 'Editar cantidad',
                              onPressed: () => _editarCantidad(plan),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: AppTheme.error, size: 18),
                              tooltip: 'Eliminar plan',
                              onPressed: () => _eliminar(plan),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${plan.disponibles} turnos disponibles',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Sheet: crear plan para un día vacío ───────────────────────
class _CrearPlanSheet extends StatefulWidget {
  final LocalServicio ls;
  final DateTime fechaInicial;
  final VoidCallback onCreated;

  const _CrearPlanSheet({
    required this.ls,
    required this.fechaInicial,
    required this.onCreated,
  });

  @override
  State<_CrearPlanSheet> createState() => _CrearPlanSheetState();
}

class _CrearPlanSheetState extends State<_CrearPlanSheet> {
  final _cantidadCtrl = TextEditingController(text: '10');
  bool _saving = false;

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cantidad = int.tryParse(_cantidadCtrl.text.trim());
    if (cantidad == null || cantidad <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ingresa una cantidad válida mayor a 0'),
        backgroundColor: AppTheme.error,
      ));
      return;
    }

    // Doble verificación: diálogo de confirmación
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        local: widget.ls.local,
        servicio: widget.ls.servicio,
        fecha: widget.fechaInicial,
        cantidad: cantidad,
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await PlanServicioService.create(
        idLocalServicio: widget.ls.id,
        fecha: widget.fechaInicial,
        cantidad: cantidad,
      );
      widget.onCreated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Plan creado correctamente'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fechaStr = DateFormat('EEEE, dd \'de\' MMMM yyyy', 'es')
        .format(widget.fechaInicial);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),

          // Título
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_circle_outline,
                    color: AppTheme.success, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Planificar día',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Sin planificación aún',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Info del día
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.primary.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 16, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fechaStr,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppTheme.primary)),
                      Text(
                        '${widget.ls.servicio?.nombre ?? ''} · ${widget.ls.local?.nombre ?? ''}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Campo cantidad
          TextField(
            controller: _cantidadCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad de turnos *',
              prefixIcon: Icon(Icons.group_outlined),
              hintText: 'Ej: 20',
            ),
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(_saving ? 'Creando...' : 'Crear plan',
                style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

// ── Diálogo de confirmación ───────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final dynamic local;
  final dynamic servicio;
  final DateTime fecha;
  final int cantidad;

  const _ConfirmDialog({
    required this.local,
    required this.servicio,
    required this.fecha,
    required this.cantidad,
  });

  @override
  Widget build(BuildContext context) {
    final fechaStr =
        DateFormat('EEEE dd \'de\' MMMM yyyy', 'es').format(fecha);

    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.fact_check_outlined,
                      color: AppTheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Confirmar plan',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      Text('Revisa antes de crear',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _ConfirmRow(
                icon: Icons.store_outlined,
                label: 'Local',
                value: local?.nombre ?? '-',
                color: const Color(0xFF4F7FFA)),
            const SizedBox(height: 12),
            _ConfirmRow(
                icon: Icons.miscellaneous_services_outlined,
                label: 'Servicio',
                value: servicio?.nombre ?? '-',
                color: const Color(0xFF7C5CFC)),
            const SizedBox(height: 12),
            _ConfirmRow(
                icon: Icons.calendar_month_outlined,
                label: 'Fecha',
                value: fechaStr,
                color: AppTheme.success),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  vertical: 14, horizontal: 18),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.primary.withOpacity(0.18)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group_outlined,
                        color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Text('Cantidad de turnos',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary)),
                  const Spacer(),
                  Text('$cantidad',
                      style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary)),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check_circle_outline,
                        size: 17),
                    label: const Text('Confirmar',
                        style: TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ConfirmRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(height: 1),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Estado vacío ──────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_tree_outlined,
              size: 72, color: AppTheme.primary.withOpacity(0.25)),
          const SizedBox(height: 16),
          const Text('Sin servicios vinculados',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text(
              'Vincula servicios a locales para\nhabilitar turnos y planificación.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_link),
            label: const Text('Vincular servicio a local'),
          ),
        ],
      ),
    );
  }
}

// ── Form: vincular servicio a local ──────────────────────────
class _PlanFormSheet extends StatefulWidget {
  final Entidad entidad;
  final VoidCallback onCreated;

  const _PlanFormSheet({required this.entidad, required this.onCreated});

  @override
  State<_PlanFormSheet> createState() => _PlanFormSheetState();
}

class _PlanFormSheetState extends State<_PlanFormSheet> {
  List<Local> _locales = [];
  List<Servicio> _servicios = [];
  Local? _localSel;
  Servicio? _servicioSel;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    try {
      final locales =
          await CatalogoService.getLocalesByEntidad(widget.entidad.id);
      final servicios =
          await CatalogoService.getServiciosByEntidad(widget.entidad.id);
      if (mounted) {
        setState(() {
          _locales = locales;
          _servicios = servicios;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_localSel == null || _servicioSel == null) {
      setState(() => _error = 'Selecciona un local y un servicio');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Verificar que no exista ya
      final existe = await CatalogoService.existeLocalServicio(
        idLocal: _localSel!.id,
        idServicio: _servicioSel!.id,
      );
      if (existe) {
        setState(() {
          _error =
              '"${_servicioSel!.nombre}" ya está vinculado a "${_localSel!.nombre}"';
          _saving = false;
        });
        return;
      }
      await CatalogoService.createLocalServicio(
        idLocal: _localSel!.id,
        idServicio: _servicioSel!.id,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().contains('unique')
              ? 'Este vínculo ya existe'
              : 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Título
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_link,
                    color: Color(0xFF34C759), size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Vincular Servicio a Local',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Entidad: ${widget.entidad.denominacion}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 20),

          if (_loading)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ))
          else ...[
            // Selector de local
            _SelectorDropdown<Local>(
              label: 'Local *',
              icon: Icons.store_outlined,
              hint: _locales.isEmpty
                  ? 'No hay locales en esta entidad'
                  : 'Seleccionar local',
              value: _localSel,
              items: _locales,
              enabled: _locales.isNotEmpty,
              labelOf: (l) => l.nombre,
              subtitleOf: (l) => l.ubicacion.isNotEmpty ? l.ubicacion : l.direccion,
              onChanged: (l) => setState(() => _localSel = l),
            ),
            const SizedBox(height: 12),

            // Selector de servicio
            _SelectorDropdown<Servicio>(
              label: 'Servicio *',
              icon: Icons.miscellaneous_services_outlined,
              hint: _servicios.isEmpty
                  ? 'No hay servicios en esta entidad'
                  : 'Seleccionar servicio',
              value: _servicioSel,
              items: _servicios,
              enabled: _servicios.isNotEmpty,
              labelOf: (s) => s.nombre,
              subtitleOf: (s) => s.descripcion,
              onChanged: (s) => setState(() => _servicioSel = s),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppTheme.error, fontSize: 13))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.link, size: 18),
              label: Text(_saving ? 'Vinculando...' : 'Vincular',
                  style: const TextStyle(fontSize: 16)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Dropdown selector genérico con subtítulo ─────────────────
class _SelectorDropdown<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final String hint;
  final T? value;
  final List<T> items;
  final bool enabled;
  final String Function(T) labelOf;
  final String? Function(T) subtitleOf;
  final ValueChanged<T?> onChanged;

  const _SelectorDropdown({
    required this.label,
    required this.icon,
    required this.hint,
    required this.value,
    required this.items,
    required this.enabled,
    required this.labelOf,
    required this.subtitleOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      isEmpty: value == null,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14)),
          isExpanded: true,
          isDense: true,
          onChanged: enabled ? onChanged : null,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(
                      subtitleOf(item) != null && subtitleOf(item)!.isNotEmpty
                          ? '${labelOf(item)}  •  ${subtitleOf(item)}'
                          : labelOf(item),
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ── Sheet: configurar cantidad default y máxima por reserva ───────────
class _ConfigCapacidadesSheet extends StatefulWidget {
  final LocalServicio localServicio;
  final ValueChanged<LocalServicio> onUpdated;

  const _ConfigCapacidadesSheet({
    super.key,
    required this.localServicio,
    required this.onUpdated,
  });

  @override
  State<_ConfigCapacidadesSheet> createState() =>
      _ConfigCapacidadesSheetState();
}

class _ConfigCapacidadesSheetState extends State<_ConfigCapacidadesSheet> {
  late final TextEditingController _defaultCtrl;
  late final TextEditingController _maxCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _defaultCtrl = TextEditingController(
      text: widget.localServicio.cantidadDefault.toString(),
    );
    _maxCtrl = TextEditingController(
      text: widget.localServicio.cantidadMaxCapacidad.toString(),
    );
  }

  @override
  void dispose() {
    _defaultCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final defaultValue = int.tryParse(_defaultCtrl.text.trim()) ?? 1;
    final maxValue = int.tryParse(_maxCtrl.text.trim()) ?? 1;

    if (defaultValue < 1 || maxValue < 1 || defaultValue > maxValue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cantidad default debe estar entre 1 y el máximo'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await CatalogoService.updateLocalServicio(
        id: widget.localServicio.id,
        cantidadDefault: defaultValue,
        cantidadMaxCapacidad: maxValue,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onUpdated(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.confirmation_number_outlined,
                    color: AppTheme.accent, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Capacidades por reserva',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.localServicio.servicio?.nombre ?? 'Servicio',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _defaultCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad default *',
              prefixIcon: Icon(Icons.looks_one_outlined),
              helperText: 'Turnos que se reservan por defecto',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _maxCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad máxima por reserva *',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
              helperText: 'Límite de turnos que puede reservar un cliente',
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save, size: 18),
            label: Text(_saving ? 'Guardando...' : 'Guardar',
                style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

// ── Day Options Sheet ─────────────────────────────────────
class _DayOptionsSheet extends StatelessWidget {
  final DateTime dia;
  final List<PlanServicio> planes;
  final VoidCallback onVerPlanificacion;
  final VoidCallback onReservar;

  const _DayOptionsSheet({
    required this.dia,
    required this.planes,
    required this.onVerPlanificacion,
    required this.onReservar,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Opciones para ${DateFormat('d MMMM yyyy', 'es_ES').format(dia)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Ver/Crear Planificación
          ElevatedButton.icon(
            onPressed: onVerPlanificacion,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(planes.isNotEmpty ? 'Ver Planificación' : 'Crear Planificación'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          
          // Reservar Capacidad
          ElevatedButton.icon(
            onPressed: onReservar,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Reservar Capacidad'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Admin Reservation Sheet ─────────────────────────────────
class _AdminReservationSheet extends StatefulWidget {
  final DateTime dia;
  final int entidadId;
  final LocalServicio? localServicio;
  final VoidCallback onReservationCreated;

  const _AdminReservationSheet({
    required this.dia,
    required this.entidadId,
    this.localServicio,
    required this.onReservationCreated,
  });

  @override
  State<_AdminReservationSheet> createState() => _AdminReservationSheetState();
}

class _AdminReservationSheetState extends State<_AdminReservationSheet> {
  final _formKey = GlobalKey<FormState>();
  GlobalKey<DatosAdicionalesFormState> _datosAdicionalesKey = GlobalKey<DatosAdicionalesFormState>();
  final _ciCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();

  List<LocalServicio> _localesServicios = [];
  LocalServicio? _selectedLocalServicio;
  Map<String, dynamic> _datosAdicionalesValores = {};
  int _cantidad = 1;
  bool _loading = false;
  bool _saving = false;

  bool get _servicioPreseleccionado => widget.localServicio != null;

  @override
  void initState() {
    super.initState();
    if (_servicioPreseleccionado) {
      _selectedLocalServicio = widget.localServicio;
    }
    _loadLocalesServicios();
  }

  @override
  void dispose() {
    _ciCtrl.dispose();
    _nombreCtrl.dispose();
    _apellidosCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocalesServicios() async {
    if (_servicioPreseleccionado) {
      final servicio = _selectedLocalServicio?.servicio;
      if (servicio != null && servicio.camposAdicionales.isNotEmpty) {
        setState(() => _loading = false);
        return;
      }
      setState(() => _loading = true);
      try {
        final refreshed = await CatalogoService.getLocalServicio(_selectedLocalServicio!.id);
        if (mounted) {
          setState(() {
            _selectedLocalServicio = refreshed;
            _loading = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final localesServicios = await CatalogoService.getLocalServiciosByEntidad(widget.entidadId);
      if (mounted) {
        setState(() {
          _localesServicios = localesServicios;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedLocalServicio == null) return;

    final camposAdicionales = _selectedLocalServicio!.servicio?.camposAdicionales ?? [];
    if (camposAdicionales.isNotEmpty &&
        _datosAdicionalesKey.currentState != null &&
        !_datosAdicionalesKey.currentState!.validar()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final datosAdicionales = <String, dynamic>{
        'ci': _ciCtrl.text.trim(),
        'nombre': _nombreCtrl.text.trim(),
        'apellidos': _apellidosCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'notas': _notasCtrl.text.trim(),
      };
      if (camposAdicionales.isNotEmpty) {
        datosAdicionales.addAll(_datosAdicionalesValores);
      }

      await AgendaAdminService.crearReservaDirecta(
        idLocalServicio: _selectedLocalServicio!.id,
        fecha: widget.dia,
        cantidad: _cantidad,
        datosAdicionales: datosAdicionales,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reserva creada exitosamente'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context);
        widget.onReservationCreated();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Error al crear reserva'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Nueva Reserva Administrativa',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      foregroundColor: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              Text(
                'Fecha: ${DateFormat('d MMMM yyyy', 'es_ES').format(widget.dia)}',
                style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),

              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Local-Servicio: solo dropdown si no viene preseleccionado
                if (_servicioPreseleccionado) ...[
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Local - Servicio',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      '${_selectedLocalServicio?.local?.nombre ?? ''} - ${_selectedLocalServicio?.servicio?.nombre ?? ''}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ] else ...[
                  DropdownButtonFormField<LocalServicio>(
                    value: _selectedLocalServicio,
                    decoration: const InputDecoration(
                      labelText: 'Local - Servicio',
                      border: OutlineInputBorder(),
                    ),
                    items: _localesServicios.map((ls) {
                      return DropdownMenuItem(
                        value: ls,
                        child: Text('${ls.local?.nombre ?? ''} - ${ls.servicio?.nombre ?? ''}'),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() {
                      _selectedLocalServicio = value;
                      _datosAdicionalesValores = {};
                      _datosAdicionalesKey = GlobalKey<DatosAdicionalesFormState>();
                    }),
                    validator: (value) => value == null ? 'Selecciona un local-servicio' : null,
                  ),
                ],
                const SizedBox(height: 16),

                // ── Datos del cliente ──
                // CI
                TextFormField(
                  controller: _ciCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CI',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Ingresa el CI' : null,
                ),
                const SizedBox(height: 16),

                // Nombre
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Ingresa el nombre' : null,
                ),
                const SizedBox(height: 16),

                // Apellidos
                TextFormField(
                  controller: _apellidosCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Apellidos',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Ingresa los apellidos' : null,
                ),
                const SizedBox(height: 16),

                // Teléfono
                TextFormField(
                  controller: _telefonoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) => value?.isEmpty == true ? 'Ingresa el teléfono' : null,
                ),
                const SizedBox(height: 16),

                // Email
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value?.isEmpty == true) return 'Ingresa el email';
                    if (!value!.contains('@')) return 'Ingresa un email válido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Cantidad
                Row(
                  children: [
                    const Text('Cantidad:'),
                    const Spacer(),
                    IconButton(
                      onPressed: _cantidad > 1 ? () => setState(() => _cantidad--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Text(_cantidad.toString()),
                    IconButton(
                      onPressed: () => setState(() => _cantidad++),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Notas
                TextFormField(
                  controller: _notasCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // Campos adicionales del servicio (después de los datos del cliente)
                if (_selectedLocalServicio?.servicio?.camposAdicionales.isNotEmpty ?? false) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Información adicional requerida',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        DatosAdicionalesForm(
                          key: _datosAdicionalesKey,
                          campos: _selectedLocalServicio!.servicio!.camposAdicionales,
                          onChanged: (v) => setState(() => _datosAdicionalesValores = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 24),
                
                // Submit button
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Crear Reserva', style: TextStyle(fontSize: 16)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
