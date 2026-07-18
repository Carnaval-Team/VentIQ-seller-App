import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/recurso.dart';
import '../../models/servicio.dart';
import '../../services/auth_service.dart';
import '../../services/recurso_service.dart';

/// Configuración de RECURSOS, TRAMOS y TURNOS de un local_servicio.
///
/// Jerarquía editable:
///   Recurso (Carro 1) → Tramos (Ida, Vuelta) → Turnos (Ida y vuelta, Solo ida)
/// Un turno consume 1 plaza de cada tramo marcado. La disponibilidad de un
/// turno = mínimo de los tramos que ocupa (capacidad compartida).
///
/// Es OPCIONAL: si un servicio no define recursos, sigue funcionando con el
/// cupo por día de siempre (plan_servicios).
class ConfigRecursosScreen extends StatefulWidget {
  final LocalServicio localServicio;
  const ConfigRecursosScreen({super.key, required this.localServicio});

  @override
  State<ConfigRecursosScreen> createState() => _ConfigRecursosScreenState();
}

class _ConfigRecursosScreenState extends State<ConfigRecursosScreen> {
  List<Recurso> _recursos = [];
  bool _loading = true;

  String get _uuid => AuthService.currentUserId ?? '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final recursos = await RecursoService.listar(
        uuidUsuario: _uuid,
        idLocalServicio: widget.localServicio.id,
      );
      if (mounted) setState(() => _recursos = recursos);
    } catch (e) {
      _snack('Error al cargar: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ── Recurso ────────────────────────────────────────────────────────────

  Future<void> _editarRecurso({Recurso? recurso}) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RecursoFormSheet(
        uuid: _uuid,
        idLocalServicio: widget.localServicio.id,
        recurso: recurso,
      ),
    );
    if (res == true) _cargar();
  }

  Future<void> _eliminarRecurso(Recurso r) async {
    final ok = await _confirmar(
        '¿Eliminar el recurso "${r.nombre}"?\n\nSe borrarán sus tramos, turnos y los cupos por día asociados.');
    if (ok != true) return;
    try {
      await RecursoService.eliminarRecurso(uuidUsuario: _uuid, id: r.id);
      _cargar();
    } catch (e) {
      _snack('Error: $e', AppTheme.error);
    }
  }

  // ── Tramo ──────────────────────────────────────────────────────────────

  Future<void> _editarTramo(Recurso recurso, {Tramo? tramo}) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TramoFormSheet(
        uuid: _uuid,
        recurso: recurso,
        tramo: tramo,
      ),
    );
    if (res == true) _cargar();
  }

  Future<void> _eliminarTramo(Tramo t) async {
    final ok = await _confirmar(
        '¿Eliminar el tramo "${t.nombre}"?\n\nLos turnos que lo usaban dejarán de ocuparlo.');
    if (ok != true) return;
    try {
      await RecursoService.eliminarTramo(uuidUsuario: _uuid, id: t.id);
      _cargar();
    } catch (e) {
      _snack('Error: $e', AppTheme.error);
    }
  }

  // ── Turno ──────────────────────────────────────────────────────────────

  Future<void> _editarTurno(Recurso recurso, {Turno? turno}) async {
    if (recurso.tramos.where((t) => t.activo).isEmpty) {
      _snack('Primero agrega al menos un tramo a este recurso.',
          AppTheme.warning);
      return;
    }
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _TurnoFormSheet(
        uuid: _uuid,
        recurso: recurso,
        turno: turno,
      ),
    );
    if (res == true) _cargar();
  }

  Future<void> _eliminarTurno(Turno t) async {
    final ok = await _confirmar('¿Eliminar el turno "${t.nombre}"?');
    if (ok != true) return;
    try {
      await RecursoService.eliminarTurno(uuidUsuario: _uuid, id: t.id);
      _cargar();
    } catch (e) {
      _snack('Error: $e', AppTheme.error);
    }
  }

  Future<bool?> _confirmar(String mensaje) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar'),
          content: Text(mensaje),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final servicio = widget.localServicio.servicio?.nombre ?? 'Servicio';
    final local = widget.localServicio.local?.nombre ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recursos y turnos'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editarRecurso(),
        icon: const Icon(Icons.add),
        label: const Text('Recurso'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _Header(servicio: servicio, local: local),
                  const SizedBox(height: 16),
                  if (_recursos.isEmpty)
                    _EmptyState(onCrear: () => _editarRecurso())
                  else
                    ..._recursos.map((r) => _RecursoCard(
                          recurso: r,
                          onEditRecurso: () => _editarRecurso(recurso: r),
                          onDeleteRecurso: () => _eliminarRecurso(r),
                          onAddTramo: () => _editarTramo(r),
                          onEditTramo: (t) => _editarTramo(r, tramo: t),
                          onDeleteTramo: _eliminarTramo,
                          onAddTurno: () => _editarTurno(r),
                          onEditTurno: (t) => _editarTurno(r, turno: t),
                          onDeleteTurno: _eliminarTurno,
                        )),
                ],
              ),
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Header + estado vacío
// ══════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final String servicio;
  final String local;
  const _Header({required this.servicio, required this.local});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_filled_outlined,
              color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(servicio,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                if (local.isNotEmpty)
                  Text(local,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 6),
                const Text(
                  'Define recursos (ej: Carro 1), sus tramos de capacidad '
                  '(Ida, Vuelta) y los turnos reservables. Un turno ocupa 1 '
                  'plaza de cada tramo que abarca.',
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCrear;
  const _EmptyState({required this.onCrear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.dashboard_customize_outlined,
              size: 56, color: AppTheme.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text('Sin recursos configurados',
              style:
                  TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Este servicio usa el cupo por día normal. Agrega recursos solo '
              'si necesitas turnos con capacidad compartida (ej: transporte '
              'ida/vuelta).',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onCrear,
            icon: const Icon(Icons.add),
            label: const Text('Crear primer recurso'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Tarjeta de recurso (con sus tramos y turnos)
// ══════════════════════════════════════════════════════════════════════════

class _RecursoCard extends StatelessWidget {
  final Recurso recurso;
  final VoidCallback onEditRecurso;
  final VoidCallback onDeleteRecurso;
  final VoidCallback onAddTramo;
  final void Function(Tramo) onEditTramo;
  final void Function(Tramo) onDeleteTramo;
  final VoidCallback onAddTurno;
  final void Function(Turno) onEditTurno;
  final void Function(Turno) onDeleteTurno;

  const _RecursoCard({
    required this.recurso,
    required this.onEditRecurso,
    required this.onDeleteRecurso,
    required this.onAddTramo,
    required this.onEditTramo,
    required this.onDeleteTramo,
    required this.onAddTurno,
    required this.onEditTurno,
    required this.onDeleteTurno,
  });

  String _nombresTramos(Turno t) {
    final nombres = recurso.tramos
        .where((tr) => t.tramosIds.contains(tr.id))
        .map((tr) => tr.nombre)
        .toList();
    return nombres.isEmpty ? 'sin tramos' : nombres.join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera recurso
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.widgets_outlined,
                      color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recurso.nombre,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('Capacidad base: ${recurso.capacidad}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (!recurso.activo)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Chip(
                      label: Text('inactivo'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEditRecurso,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppTheme.error),
                  onPressed: onDeleteRecurso,
                ),
              ],
            ),
            const Divider(height: 20),

            // Tramos
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tramos (capacidad)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                TextButton.icon(
                  onPressed: onAddTramo,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Añadir'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            if (recurso.tramos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Aún no hay tramos.',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recurso.tramos.map((t) {
                  final cap = t.capacidad ?? recurso.capacidad;
                  return InputChip(
                    label: Text('${t.nombre} · $cap'),
                    onPressed: () => onEditTramo(t),
                    onDeleted: () => onDeleteTramo(t),
                    backgroundColor:
                        AppTheme.accent.withValues(alpha: 0.10),
                    deleteIconColor: AppTheme.error,
                  );
                }).toList(),
              ),
            const SizedBox(height: 14),

            // Turnos
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Turnos reservables',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                TextButton.icon(
                  onPressed: onAddTurno,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Añadir'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            if (recurso.turnos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Aún no hay turnos.',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              )
            else
              ...recurso.turnos.map((t) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.confirmation_number_outlined,
                        color: AppTheme.primary),
                    title: Text(t.nombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 14)),
                    subtitle: Text(_nombresTramos(t),
                        style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => onEditTurno(t),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: AppTheme.error),
                          onPressed: () => onDeleteTurno(t),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Formularios (bottom sheets)
// ══════════════════════════════════════════════════════════════════════════

class _RecursoFormSheet extends StatefulWidget {
  final String uuid;
  final int idLocalServicio;
  final Recurso? recurso;
  const _RecursoFormSheet({
    required this.uuid,
    required this.idLocalServicio,
    this.recurso,
  });

  @override
  State<_RecursoFormSheet> createState() => _RecursoFormSheetState();
}

class _RecursoFormSheetState extends State<_RecursoFormSheet> {
  late final TextEditingController _nombre =
      TextEditingController(text: widget.recurso?.nombre ?? '');
  late final TextEditingController _cap = TextEditingController(
      text: (widget.recurso?.capacidad ?? 1).toString());
  late bool _activo = widget.recurso?.activo ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _nombre.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final cap = int.tryParse(_cap.text.trim());
    if (nombre.isEmpty) {
      _err('El nombre es obligatorio');
      return;
    }
    if (cap == null || cap < 1) {
      _err('La capacidad debe ser un número ≥ 1');
      return;
    }
    setState(() => _saving = true);
    try {
      await RecursoService.guardarRecurso(
        uuidUsuario: widget.uuid,
        idLocalServicio: widget.idLocalServicio,
        nombre: nombre,
        capacidad: cap,
        activo: _activo,
        id: widget.recurso?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _err('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: AppTheme.error));

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      titulo: widget.recurso == null ? 'Nuevo recurso' : 'Editar recurso',
      saving: _saving,
      onGuardar: _guardar,
      children: [
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre *',
            hintText: 'Ej: Carro 1',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _cap,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Capacidad base *',
            helperText: 'Plazas por defecto de cada tramo (ej: 15)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activo'),
          value: _activo,
          activeThumbColor: AppTheme.primary,
          onChanged: (v) => setState(() => _activo = v),
        ),
      ],
    );
  }
}

class _TramoFormSheet extends StatefulWidget {
  final String uuid;
  final Recurso recurso;
  final Tramo? tramo;
  const _TramoFormSheet({
    required this.uuid,
    required this.recurso,
    this.tramo,
  });

  @override
  State<_TramoFormSheet> createState() => _TramoFormSheetState();
}

class _TramoFormSheetState extends State<_TramoFormSheet> {
  late final TextEditingController _nombre =
      TextEditingController(text: widget.tramo?.nombre ?? '');
  late final TextEditingController _cap = TextEditingController(
      text: widget.tramo?.capacidad?.toString() ?? '');
  late bool _activo = widget.tramo?.activo ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _nombre.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _err('El nombre es obligatorio');
      return;
    }
    final capText = _cap.text.trim();
    int? cap;
    if (capText.isNotEmpty) {
      cap = int.tryParse(capText);
      if (cap == null || cap < 0) {
        _err('La capacidad debe ser un número ≥ 0');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await RecursoService.guardarTramo(
        uuidUsuario: widget.uuid,
        idRecurso: widget.recurso.id,
        nombre: nombre,
        capacidad: cap, // null = hereda recurso
        activo: _activo,
        id: widget.tramo?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _err('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: AppTheme.error));

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      titulo: widget.tramo == null ? 'Nuevo tramo' : 'Editar tramo',
      saving: _saving,
      onGuardar: _guardar,
      children: [
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre *',
            hintText: 'Ej: Ida, Vuelta',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _cap,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Capacidad',
            hintText: 'Vacío = usar base (${widget.recurso.capacidad})',
            helperText: 'Plazas de este tramo por día',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activo'),
          value: _activo,
          activeThumbColor: AppTheme.primary,
          onChanged: (v) => setState(() => _activo = v),
        ),
      ],
    );
  }
}

class _TurnoFormSheet extends StatefulWidget {
  final String uuid;
  final Recurso recurso;
  final Turno? turno;
  const _TurnoFormSheet({
    required this.uuid,
    required this.recurso,
    this.turno,
  });

  @override
  State<_TurnoFormSheet> createState() => _TurnoFormSheetState();
}

class _TurnoFormSheetState extends State<_TurnoFormSheet> {
  late final TextEditingController _nombre =
      TextEditingController(text: widget.turno?.nombre ?? '');
  late final Set<int> _tramosSel = {...(widget.turno?.tramosIds ?? const [])};
  late bool _activo = widget.turno?.activo ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _err('El nombre es obligatorio');
      return;
    }
    if (_tramosSel.isEmpty) {
      _err('Selecciona al menos un tramo que el turno ocupa');
      return;
    }
    setState(() => _saving = true);
    try {
      await RecursoService.guardarTurno(
        uuidUsuario: widget.uuid,
        idRecurso: widget.recurso.id,
        nombre: nombre,
        tramosIds: _tramosSel.toList(),
        activo: _activo,
        id: widget.turno?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _err('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: AppTheme.error));

  @override
  Widget build(BuildContext context) {
    final tramos = widget.recurso.tramos.where((t) => t.activo).toList();
    return _SheetScaffold(
      titulo: widget.turno == null ? 'Nuevo turno' : 'Editar turno',
      saving: _saving,
      onGuardar: _guardar,
      children: [
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre *',
            hintText: 'Ej: Ida y vuelta, Solo ida',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Tramos que ocupa este turno *',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Reservar este turno descuenta 1 plaza de cada tramo marcado.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        ...tramos.map((t) {
          final cap = t.capacidad ?? widget.recurso.capacidad;
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _tramosSel.contains(t.id),
            activeColor: AppTheme.primary,
            title: Text(t.nombre),
            subtitle: Text('Capacidad: $cap'),
            onChanged: (v) => setState(() {
              if (v == true) {
                _tramosSel.add(t.id);
              } else {
                _tramosSel.remove(t.id);
              }
            }),
          );
        }),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activo'),
          value: _activo,
          activeThumbColor: AppTheme.primary,
          onChanged: (v) => setState(() => _activo = v),
        ),
      ],
    );
  }
}

/// Andamiaje común de los bottom sheets: título, contenido y botón guardar.
class _SheetScaffold extends StatelessWidget {
  final String titulo;
  final bool saving;
  final VoidCallback onGuardar;
  final List<Widget> children;
  const _SheetScaffold({
    required this.titulo,
    required this.saving,
    required this.onGuardar,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saving ? null : onGuardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Guardar', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
