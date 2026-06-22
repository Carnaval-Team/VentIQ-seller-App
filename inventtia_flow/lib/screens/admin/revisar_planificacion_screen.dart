import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../config/app_theme.dart';
import '../../models/plan_servicio.dart';
import '../../models/servicio.dart';
import '../../services/plan_servicio_service.dart';

class RevisarPlanificacionScreen extends StatefulWidget {
  final LocalServicio localServicio;
  const RevisarPlanificacionScreen({super.key, required this.localServicio});

  @override
  State<RevisarPlanificacionScreen> createState() =>
      _RevisarPlanificacionScreenState();
}

class _RevisarPlanificacionScreenState
    extends State<RevisarPlanificacionScreen> {
  List<PlanServicio> _planes = [];
  bool _loading = true;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Map date (yyyy-MM-dd) → lista de planes ese día
  Map<String, List<PlanServicio>> get _planesPorDia {
    final map = <String, List<PlanServicio>>{};
    for (final p in _planes) {
      if (p.fecha == null) continue;
      final key = _dayKey(p.fecha!);
      map.putIfAbsent(key, () => []).add(p);
    }
    return map;
  }

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<PlanServicio> _planesDelDia(DateTime day) =>
      _planesPorDia[_dayKey(day)] ?? [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final planes = await PlanServicioService.getByLocalServicio(
          widget.localServicio.id);
      if (mounted) setState(() => _planes = planes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
    });
    final planes = _planesDelDia(selected);
    if (planes.isEmpty) return;
    _showDayDetail(selected, planes);
  }

  void _showDayDetail(DateTime dia, List<PlanServicio> planes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DayDetailSheet(
        dia: dia,
        planes: planes,
        onUpdated: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.localServicio.local;
    final servicio = widget.localServicio.servicio;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Planificación'),
            Text(
              '${servicio?.nombre ?? ''} · ${local?.nombre ?? ''}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TableCalendar<PlanServicio>(
                  locale: 'es_ES',
                  firstDay: DateTime.utc(2024, 1, 1),
                  lastDay: DateTime.utc(2027, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) =>
                      _selectedDay != null &&
                      isSameDay(_selectedDay, day),
                  eventLoader: _planesDelDia,
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.3),
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
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                  ),
                  onDaySelected: _onDaySelected,
                  onPageChanged: (f) => setState(() => _focusedDay = f),
                ),
                const Divider(height: 1),
                if (_selectedDay != null) ...[
                  _buildSelectedDayList(),
                ] else ...[
                  Expanded(
                    child: Center(
                      child: Text(
                        'Selecciona un día para ver los planes',
                        style: TextStyle(
                            color: AppTheme.textSecondary.withOpacity(0.6)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildSelectedDayList() {
    final planes = _planesDelDia(_selectedDay!);
    if (planes.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            'Sin planes para ${DateFormat('dd/MM/yyyy').format(_selectedDay!)}',
            style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.6)),
          ),
        ),
      );
    }
    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: planes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _PlanTile(
          plan: planes[i],
          onTap: () =>
              _showDayDetail(_selectedDay!, _planesDelDia(_selectedDay!)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet: detalle del día con edición de cantidad
// ─────────────────────────────────────────────────────────────────────────────
class _DayDetailSheet extends StatefulWidget {
  final DateTime dia;
  final List<PlanServicio> planes;
  final VoidCallback onUpdated;

  const _DayDetailSheet({
    required this.dia,
    required this.planes,
    required this.onUpdated,
  });

  @override
  State<_DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends State<_DayDetailSheet> {
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
              'Reservados: ${plan.agendados}  ·  Mínimo permitido: ${plan.agendados}',
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'La cantidad debe ser ≥ ${plan.agendados}'),
                    backgroundColor: AppTheme.error,
                  ),
                );
                return;
              }
              Navigator.pop(context, v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _saving = true);
    try {
      await PlanServicioService.update(
          id: plan.id, fecha: plan.fecha, cantidad: result);
      widget.onUpdated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.error),
        );
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
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, dd MMMM yyyy', 'es').format(widget.dia),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
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
              itemBuilder: (_, i) => _PlanTile(
                plan: widget.planes[i],
                showEdit: true,
                onTap: () => _editarCantidad(widget.planes[i]),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile individual de un plan
// ─────────────────────────────────────────────────────────────────────────────
class _PlanTile extends StatelessWidget {
  final PlanServicio plan;
  final VoidCallback? onTap;
  final bool showEdit;

  const _PlanTile(
      {required this.plan, this.onTap, this.showEdit = false});

  @override
  Widget build(BuildContext context) {
    final pct =
        plan.cantidad > 0 ? plan.agendados / plan.cantidad : 0.0;
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
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  backgroundColor: color.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation(color),
                  minHeight: 6,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${plan.disponibles} disponibles',
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary),
          ),
        ),
        trailing: showEdit
            ? IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: AppTheme.primary),
                onPressed: onTap,
              )
            : null,
        onTap: showEdit ? null : onTap,
      ),
    );
  }
}
