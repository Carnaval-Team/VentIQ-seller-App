import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../services/catalogo_service.dart';
import 'crear_planificacion_screen.dart' show CrearPlanificacionScreen;
import 'revisar_planificacion_screen.dart';

class PlanificacionScreen extends StatefulWidget {
  final Entidad entidad;
  const PlanificacionScreen({super.key, required this.entidad});

  @override
  State<PlanificacionScreen> createState() => _PlanificacionScreenState();
}

class _PlanificacionScreenState extends State<PlanificacionScreen> {
  List<LocalServicio> _planes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      // Cargamos vía join por locales de la entidad
      final locales =
          await CatalogoService.getLocalesByEntidad(widget.entidad.id);
      final List<LocalServicio> todos = [];
      for (final local in locales) {
        final ls = await CatalogoService.getLocalServicios(idLocal: local.id);
        todos.addAll(ls);
      }
      // Ordenar: por nombre de local, luego por nombre de servicio
      todos.sort((a, b) {
        final cmp =
            (a.local?.nombre ?? '').compareTo(b.local?.nombre ?? '');
        if (cmp != 0) return cmp;
        return (a.servicio?.nombre ?? '')
            .compareTo(b.servicio?.nombre ?? '');
      });
      if (mounted) setState(() => _planes = todos);
    } catch (e) {
      print('[flow] PlanificacionScreen _cargar ERROR: $e');
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

  void _nuevo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _PlanFormSheet(entidad: widget.entidad, onCreated: _cargar),
    );
  }

  Future<void> _eliminar(LocalServicio ls) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar plan'),
        content: Text(
            '¿Desvincular "${ls.servicio?.nombre ?? ''}" de "${ls.local?.nombre ?? ''}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await CatalogoService.deleteLocalServicio(ls.id);
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  // Agrupar planes por local
  Map<String, List<LocalServicio>> get _porLocal {
    final map = <String, List<LocalServicio>>{};
    for (final ls in _planes) {
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
            onPressed: _nuevo,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _planes.isEmpty
              ? _EmptyState(onAdd: _nuevo)
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: _buildLista(),
                ),
      floatingActionButton: _planes.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _nuevo,
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
      padding: const EdgeInsets.all(16),
      itemCount: localNames.length,
      itemBuilder: (_, i) {
        final localNombre = localNames[i];
        final items = grupos[localNombre]!;
        return _LocalGroup(
          localNombre: localNombre,
          local: items.first.local,
          items: items,
          onDelete: _eliminar,
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
  final Future<void> Function(LocalServicio) onDelete;

  const _LocalGroup({
    required this.localNombre,
    required this.local,
    required this.items,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera de local
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
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
                              fontSize: 11, color: AppTheme.textSecondary)),
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
                child: Text('${items.length} servicio${items.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),

        // Servicios asignados con acciones de planificación
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final idx = entry.key;
              final ls = entry.value;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                  Icons.miscellaneous_services_outlined,
                                  size: 16, color: AppTheme.accent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ls.servicio?.nombre ?? '—',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  if (ls.servicio?.descripcion != null)
                                    Text(ls.servicio!.descripcion!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.link_off,
                                  size: 18, color: AppTheme.error),
                              tooltip: 'Desvincular',
                              onPressed: () => onDelete(ls),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CrearPlanificacionScreen(
                                            localServicio: ls),
                                  ),
                                ),
                                icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 15),
                                label: const Text('Crear plan',
                                    style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor:
                                      const Color(0xFF34C759),
                                  side: const BorderSide(
                                      color: Color(0xFF34C759)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RevisarPlanificacionScreen(
                                            localServicio: ls),
                                  ),
                                ),
                                icon: const Icon(
                                    Icons.calendar_view_week,
                                    size: 15),
                                label: const Text('Revisar',
                                    style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  side: BorderSide(
                                      color: AppTheme.primary),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (idx < items.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              );
            }).toList(),
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
          const Text('Sin planes de servicio',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('Vincula servicios a locales para\nhabilitar turnos y agenda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
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
