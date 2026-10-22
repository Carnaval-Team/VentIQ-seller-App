/// Piezas de planificación de un local-servicio que comparten las pantallas
/// de administración: el calendario con marcadores de ocupación y las hojas
/// para planificar un día, elegir qué hacer con él, reservar capacidad como
/// admin y fijar las capacidades por reserva.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../config/app_theme.dart';
import '../../models/plan_dia.dart';
import '../../models/disponibilidad_dia.dart';
import '../../models/recurso.dart';
import '../../models/servicio.dart';
import '../../services/agenda_service.dart';
import '../../services/auth_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/plan_config_service.dart';
import '../../services/agenda_admin_service.dart';
import '../../widgets/datos_adicionales_form.dart';
import 'admin_reserva_transporte_sheet.dart';

// ── Calendario con marcadores ─────────────────────────────────
bool _planCasiLleno(PlanDia plan) {
  if (plan.recursos.isNotEmpty) {
    // Con recursos: "casi lleno" si algún tramo pico ≥ 80% de la capacidad.
    return plan.recursos.any(
      (r) => r.cantidad > 0 && r.ocupacionMax >= (r.cantidad * 0.8).ceil(),
    );
  }
  return plan.disponibles < (plan.cantidad * 0.2).ceil();
}

class CalendarioConPlanes extends StatelessWidget {
  final DateTime focusedDay;
  final List<PlanDia> Function(DateTime) planesDelDia;
  final void Function(DateTime) onDayTapped;
  final void Function(DateTime) onPageChanged;

  const CalendarioConPlanes({
    super.key,
    required this.focusedDay,
    required this.planesDelDia,
    required this.onDayTapped,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar<PlanDia>(
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
              final plan = events.first;
              if (plan.cantidad <= 0) return null;
              final color = plan.estaLleno
                  ? AppTheme.error
                  : _planCasiLleno(plan)
                  ? AppTheme.warning
                  : AppTheme.success;
              return Positioned(
                bottom: 4,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
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
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

// ── Sheet: planificar un día (crear o editar) ─────────────────
// Unifica el antiguo "crear plan" e "info del día". Dos modos:
//  • CON recursos: un campo de capacidad por recurso (todos los tramos del
//    recurso reciben esa cantidad ese día). 0 = cerrar el recurso ese día.
//  • SIN recursos: un único campo de cantidad de turnos del día.
class PlanificarDiaSheet extends StatefulWidget {
  final LocalServicio ls;
  final DateTime fecha;
  final List<Recurso> recursos; // vacío = servicio sin recursos
  final PlanDia? planActual; // null o cantidad 0 = día sin planificar
  final VoidCallback onSaved;

  const PlanificarDiaSheet({
    super.key,
    required this.ls,
    required this.fecha,
    required this.recursos,
    required this.planActual,
    required this.onSaved,
  });

  @override
  State<PlanificarDiaSheet> createState() => _PlanificarDiaSheetState();
}

class _PlanificarDiaSheetState extends State<PlanificarDiaSheet> {
  // Modo SIN recursos.
  late final TextEditingController _cantidadCtrl;
  // Modo CON recursos: un controlador por recurso.
  final Map<int, TextEditingController> _recCtrls = {};
  // Agendados reales (display) y ocupación máxima de tramo (piso al bajar capacidad).
  final Map<int, int> _recAgendados = {};
  final Map<int, int> _recOcupacionMax = {};
  int _agendadosSimple = 0;
  bool _saving = false;

  bool get _porRecurso => widget.recursos.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_porRecurso) {
      // Precargar con la capacidad actual de cada recurso ese día (si existe).
      final actualPorRecurso = <int, RecursoDia>{
        for (final r in widget.planActual?.recursos ?? const []) r.idRecurso: r,
      };
      for (final r in widget.recursos) {
        final actual = actualPorRecurso[r.id];
        _recCtrls[r.id] = TextEditingController(
          text: actual != null ? actual.cantidad.toString() : '',
        );
        _recAgendados[r.id] = actual?.agendados ?? 0;
        _recOcupacionMax[r.id] = actual?.minimoCapacidad ?? 0;
      }
    } else {
      final actual = widget.planActual;
      _agendadosSimple = actual?.agendados ?? 0;
      _cantidadCtrl = TextEditingController(
        text: (actual != null && actual.cantidad > 0)
            ? actual.cantidad.toString()
            : '10',
      );
    }
  }

  @override
  void dispose() {
    if (_porRecurso) {
      for (final c in _recCtrls.values) {
        c.dispose();
      }
    } else {
      _cantidadCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    Map<int, int>? caps;
    int? cantidad;

    if (_porRecurso) {
      caps = {};
      for (final r in widget.recursos) {
        final txt = _recCtrls[r.id]!.text.trim();
        final v = txt.isEmpty ? 0 : int.tryParse(txt);
        if (v == null || v < 0) {
          _err('Capacidad inválida en "${r.nombre}" (usa un número ≥ 0)');
          return;
        }
        final min = _recOcupacionMax[r.id] ?? 0;
        if (v > 0 && v < min) {
          _err(
            '"${r.nombre}": no puedes bajar de $min ya ocupado(s) en un tramo',
          );
          return;
        }
        caps[r.id] = v;
      }
    } else {
      cantidad = int.tryParse(_cantidadCtrl.text.trim());
      if (cantidad == null || cantidad <= 0) {
        _err('Ingresa una cantidad válida mayor a 0');
        return;
      }
      if (cantidad < _agendadosSimple) {
        _err('No puedes bajar de $_agendadosSimple ya reservado(s)');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await PlanConfigService.planificarDia(
        uuidUsuario: AuthService.currentUserId ?? '',
        idLocalServicio: widget.ls.id,
        fecha: widget.fecha,
        capsPorRecurso: caps,
        cantidad: cantidad,
      );
      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Planificación guardada'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      _err('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(m), backgroundColor: AppTheme.error));

  @override
  Widget build(BuildContext context) {
    final fechaStr = DateFormat(
      'EEEE, dd \'de\' MMMM yyyy',
      'es',
    ).format(widget.fecha);
    final yaPlanificado =
        widget.planActual != null && widget.planActual!.cantidad > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.event_available_outlined,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Planificar día',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      fechaStr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.ls.servicio?.nombre ?? ''} · ${widget.ls.local?.nombre ?? ''}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),

          if (_porRecurso) ...[
            const Text(
              'Capacidad por recurso ese día. Todos los tramos del recurso '
              'reciben esta cantidad. Pon 0 para cerrar el recurso ese día.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final r in widget.recursos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.widgets_outlined,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.nombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if ((_recAgendados[r.id] ?? 0) > 0)
                                    Text(
                                      '${_recAgendados[r.id]} reservado(s)',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _recCtrls[r.id],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: '0',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ] else ...[
            if (yaPlanificado)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${widget.planActual!.agendados} / ${widget.planActual!.cantidad} reservado(s)',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            TextField(
              controller: _cantidadCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cantidad de turnos *',
                prefixIcon: Icon(Icons.group_outlined),
                hintText: 'Ej: 20',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _saving ? null : _guardar,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(
              _saving
                  ? 'Guardando...'
                  : (yaPlanificado ? 'Guardar cambios' : 'Planificar día'),
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}


// ── Chip de estado del par local-servicio ────────────────────
class ChipEstado extends StatelessWidget {
  const ChipEstado({
    super.key,required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── Sheet: configurar cantidad default y máxima por reserva ───────────
class ConfigCapacidadesSheet extends StatefulWidget {
  final LocalServicio localServicio;
  final ValueChanged<LocalServicio> onUpdated;

  const ConfigCapacidadesSheet({
    super.key,
    required this.localServicio,
    required this.onUpdated,
  });

  @override
  State<ConfigCapacidadesSheet> createState() =>
      _ConfigCapacidadesSheetState();
}

class _ConfigCapacidadesSheetState extends State<ConfigCapacidadesSheet> {
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
                child: const Icon(
                  Icons.confirmation_number_outlined,
                  color: AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Capacidades por reserva',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
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
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(
              _saving ? 'Guardando...' : 'Guardar',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Day Options Sheet ─────────────────────────────────────
class DayOptionsSheet extends StatelessWidget {
  final DateTime dia;
  final bool tienePlan;
  final bool puedeReservar;
  final VoidCallback onVerPlanificacion;
  final VoidCallback onReservar;

  const DayOptionsSheet({
    super.key,
    required this.dia,
    required this.tienePlan,
    required this.puedeReservar,
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
            label: Text(
              tienePlan ? 'Ver / editar planificación' : 'Planificar día',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Reservar Capacidad
          ElevatedButton.icon(
            onPressed: puedeReservar ? onReservar : null,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Reservar Capacidad'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          if (!puedeReservar) ...[
            const SizedBox(height: 8),
            Text(
              tienePlan
                  ? 'No hay capacidad disponible este día (cupo agotado).'
                  : 'No hay capacidad planificada para este día.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Admin Reservation Sheet ─────────────────────────────────
class AdminReservationSheet extends StatefulWidget {
  final DateTime dia;
  final int entidadId;
  final LocalServicio? localServicio;
  final VoidCallback onReservationCreated;

  const AdminReservationSheet({
    super.key,
    required this.dia,
    required this.entidadId,
    this.localServicio,
    required this.onReservationCreated,
  });

  @override
  State<AdminReservationSheet> createState() => _AdminReservationSheetState();
}

class _AdminReservationSheetState extends State<AdminReservationSheet> {
  final _formKey = GlobalKey<FormState>();
  GlobalKey<DatosAdicionalesFormState> _datosAdicionalesKey =
      GlobalKey<DatosAdicionalesFormState>();
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

  // Disponibilidad del día para el servicio elegido. Si trae turnos, el
  // servicio usa recursos y el admin debe elegir un turno antes de reservar.
  DisponibilidadDia? _dispDia;
  bool _loadingDisp = false;
  TurnoDisponible? _turnoSel;

  bool get _servicioPreseleccionado => widget.localServicio != null;
  bool get _usaRecursos => _dispDia?.tieneTurnos ?? false;
  bool get _sinCupoDia =>
      !_loadingDisp &&
      _selectedLocalServicio != null &&
      (_dispDia == null || _dispDia!.disponibles <= 0);

  @override
  void initState() {
    super.initState();
    if (_servicioPreseleccionado) {
      _selectedLocalServicio = widget.localServicio;
    }
    _loadLocalesServicios();
    if (_selectedLocalServicio != null) _loadDisponibilidad();
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
        final refreshed = await CatalogoService.getLocalServicio(
          _selectedLocalServicio!.id,
        );
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
      final localesServicios = await CatalogoService.getLocalServiciosByEntidad(
        widget.entidadId,
      );
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

  /// Carga la disponibilidad del día del servicio elegido para saber si usa
  /// recursos (turnos) y, en ese caso, ofrecer el selector de turno.
  Future<void> _loadDisponibilidad() async {
    final ls = _selectedLocalServicio;
    if (ls == null) return;
    setState(() {
      _loadingDisp = true;
      _dispDia = null;
      _turnoSel = null;
    });
    try {
      final dias = await AgendaService.getDisponibilidad(ls.id);
      final key = widget.dia.toIso8601String().substring(0, 10);
      DisponibilidadDia? match;
      for (final d in dias) {
        if (d.fecha.toIso8601String().substring(0, 10) == key) {
          match = d;
          break;
        }
      }
      if (mounted) setState(() => _dispDia = match);
    } catch (_) {
      // Sin disponibilidad: se trata como servicio sin turnos.
    } finally {
      if (mounted) setState(() => _loadingDisp = false);
    }
  }

  Future<void> _elegirTurno() async {
    final dia = _dispDia;
    if (dia == null || !dia.tieneTurnos) return;
    final elegido = await showModalBottomSheet<TurnoDisponible>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AdminTurnoPickerSheet(fecha: widget.dia, dia: dia),
    );
    if (elegido != null && mounted) setState(() => _turnoSel = elegido);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedLocalServicio == null)
      return;

    // Validar carné para reservas del mismo día
    final ahora = DateTime.now();
    final esHoy =
        widget.dia.year == ahora.year &&
        widget.dia.month == ahora.month &&
        widget.dia.day == ahora.day;
    if (esHoy) {
      final ci = _ciCtrl.text.trim();
      if (ci.length != 11 || int.tryParse(ci) == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Para reservar hoy el CI debe tener 11 dígitos.'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
        return;
      }
    }

    if (_sinCupoDia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay capacidad disponible para esta fecha'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    // Servicios con recursos: exigir turno elegido.
    if (_usaRecursos && _turnoSel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un turno para este servicio'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    final camposAdicionales =
        _selectedLocalServicio!.servicio?.camposAdicionales ?? [];
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
        idTurno: _turnoSel?.idTurno,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onReservationCreated();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        showDialog<void>(
          context: context,
          useRootNavigator: true,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Error al crear reserva'),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
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
    // ScaffoldMessenger propio: las SnackBars salen encima del bottom sheet.
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.white,
        resizeToAvoidBottomInset: true,
        body: Padding(
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
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
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else ...[
                    if (_sinCupoDia) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.warning.withOpacity(0.4),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.event_busy_outlined,
                              color: AppTheme.warning,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No hay capacidad disponible para esta fecha. '
                                'Planifica el día o elige otra fecha.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Local-Servicio: solo dropdown si no viene preseleccionado
                    if (_servicioPreseleccionado) ...[
                      InputDecorator(
                        // Campo de sólo lectura con valor puesto: `isEmpty: false`
                        // explícito para que la etiqueta flote (si no, se dibujaría
                        // junto al texto, el solape del punto 2).
                        isEmpty: false,
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
                        // El valor tiene que existir entre los items: si la lista
                        // aún no cargó, un `initialValue` huérfano dejaría el campo
                        // con etiqueta flotante y placeholder a la vez (punto 2).
                        initialValue:
                            _localesServicios.any(
                              (ls) => ls.id == _selectedLocalServicio?.id,
                            )
                            ? _selectedLocalServicio
                            : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Local - Servicio',
                        ),
                        items: _localesServicios.map((ls) {
                          return DropdownMenuItem(
                            value: ls,
                            child: Text(
                              '${ls.local?.nombre ?? ''} - ${ls.servicio?.nombre ?? ''}',
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value?.esTransporteOmnibus == true) {
                            Navigator.pop(context);
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              enableDrag: false,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              builder: (_) => AdminReservaTransporteSheet(
                                localServicio: value!,
                                diaInicial: widget.dia,
                                onCreated: widget.onReservationCreated,
                              ),
                            );
                            return;
                          }
                          setState(() {
                            _selectedLocalServicio = value;
                            _datosAdicionalesValores = {};
                            _datosAdicionalesKey =
                                GlobalKey<DatosAdicionalesFormState>();
                            _turnoSel = null;
                            _dispDia = null;
                          });
                          if (value != null) _loadDisponibilidad();
                        },
                        validator: (value) => value == null
                            ? 'Selecciona un local-servicio'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Selector de turno (solo servicios con recursos)
                    if (_loadingDisp)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    else if (_usaRecursos) ...[
                      InkWell(
                        onTap: _elegirTurno,
                        borderRadius: BorderRadius.circular(4),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Turno *',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(
                              Icons.confirmation_number_outlined,
                            ),
                            errorText: _turnoSel == null
                                ? 'Selecciona un turno'
                                : null,
                          ),
                          child: Text(
                            _turnoSel == null
                                ? 'Elegir turno'
                                : '${_turnoSel!.recurso} · ${_turnoSel!.turno}',
                            style: TextStyle(
                              fontSize: 15,
                              color: _turnoSel == null
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Datos del cliente ──
                    // CI
                    TextFormField(
                      controller: _ciCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'CI',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      validator: (value) {
                        final t = (value ?? '').trim();
                        if (t.isEmpty) return 'Ingresa el CI';
                        final ahora = DateTime.now();
                        final esHoy =
                            widget.dia.year == ahora.year &&
                            widget.dia.month == ahora.month &&
                            widget.dia.day == ahora.day;
                        if (esHoy &&
                            (t.length != 11 || int.tryParse(t) == null)) {
                          return 'El CI debe tener 11 dígitos';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Nombre
                    TextFormField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value?.isEmpty == true ? 'Ingresa el nombre' : null,
                    ),
                    const SizedBox(height: 16),

                    // Apellidos
                    TextFormField(
                      controller: _apellidosCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Apellidos',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value?.isEmpty == true
                          ? 'Ingresa los apellidos'
                          : null,
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
                      validator: (value) =>
                          value?.isEmpty == true ? 'Ingresa el teléfono' : null,
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
                        if (!value!.contains('@'))
                          return 'Ingresa un email válido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Cantidad (servicios con recursos reservan 1 turno)
                    if (!_usaRecursos) ...[
                      Row(
                        children: [
                          const Text('Cantidad:'),
                          const Spacer(),
                          IconButton(
                            onPressed: _cantidad > 1
                                ? () => setState(() => _cantidad--)
                                : null,
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
                    ],

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
                    if (_selectedLocalServicio
                            ?.servicio
                            ?.camposAdicionales
                            .isNotEmpty ??
                        false) ...[
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
                              campos: _selectedLocalServicio!
                                  .servicio!
                                  .camposAdicionales,
                              onChanged: (v) =>
                                  setState(() => _datosAdicionalesValores = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 24),

                    // Submit button
                    ElevatedButton(
                      onPressed: (_saving || _sinCupoDia) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Crear Reserva',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selector de turno para la reserva administrativa (servicios con recursos).
/// Agrupa los turnos por recurso y devuelve el [TurnoDisponible] elegido.
class _AdminTurnoPickerSheet extends StatelessWidget {
  final DateTime fecha;
  final DisponibilidadDia dia;

  const _AdminTurnoPickerSheet({required this.fecha, required this.dia});

  @override
  Widget build(BuildContext context) {
    final porRecurso = <int, List<TurnoDisponible>>{};
    final nombreRecurso = <int, String>{};
    for (final t in dia.turnos) {
      porRecurso.putIfAbsent(t.idRecurso, () => []).add(t);
      nombreRecurso[t.idRecurso] = t.recurso;
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(
                  Icons.confirmation_number_outlined,
                  size: 20,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Elige un turno · ${DateFormat('dd/MM/yyyy').format(fecha)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                for (final idRec in porRecurso.keys) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Text(
                      nombreRecurso[idRec] ?? 'Recurso',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  for (final t in porRecurso[idRec]!)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        enabled: t.disponibles > 0,
                        title: Text(
                          t.turno,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('${t.disponibles} disponibles'),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppTheme.primary,
                        ),
                        onTap: t.disponibles > 0
                            ? () => Navigator.pop(context, t)
                            : null,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
