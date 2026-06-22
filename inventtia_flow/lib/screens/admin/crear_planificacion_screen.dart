import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_theme.dart';
import '../../models/servicio.dart';
import '../../services/plan_servicio_service.dart';

class CrearPlanificacionScreen extends StatefulWidget {
  final LocalServicio localServicio;
  const CrearPlanificacionScreen({super.key, required this.localServicio});

  @override
  State<CrearPlanificacionScreen> createState() =>
      _CrearPlanificacionScreenState();
}

class _CrearPlanificacionScreenState extends State<CrearPlanificacionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadCtrl = TextEditingController(text: '1');
  DateTime? _fecha;
  bool _saving = false;

  @override
  void dispose() {
    _cantidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFecha() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _fecha = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await PlanServicioService.create(
        idLocalServicio: widget.localServicio.id,
        fecha: _fecha,
        cantidad: int.parse(_cantidadCtrl.text.trim()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan creado correctamente')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.localServicio.local;
    final servicio = widget.localServicio.servicio;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Crear Planificación')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info del vínculo
              _InfoCard(local: local, servicio: servicio),
              const SizedBox(height: 24),

              const Text('Datos del plan',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.8)),
              const SizedBox(height: 12),

              // Fecha
              GestureDetector(
                onTap: _pickFecha,
                child: AbsorbPointer(
                  child: TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Fecha del plan',
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                      hintText: 'Seleccionar fecha (opcional)',
                      suffixIcon: _fecha != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () =>
                                  setState(() => _fecha = null),
                            )
                          : null,
                    ),
                    controller: TextEditingController(
                      text: _fecha != null
                          ? DateFormat('dd/MM/yyyy').format(_fecha!)
                          : '',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Cantidad
              TextFormField(
                controller: _cantidadCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cantidad de turnos *',
                  prefixIcon: Icon(Icons.group_outlined),
                  hintText: 'Ej: 20',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  final n = int.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Debe ser un número mayor a 0';
                  return null;
                },
              ),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando...' : 'Crear Plan',
                    style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pantalla: Revisar planificación ──────────────────────────
class RevisarPlanificacionScreen extends StatefulWidget {
  final LocalServicio localServicio;
  const RevisarPlanificacionScreen(
      {super.key, required this.localServicio});

  @override
  State<RevisarPlanificacionScreen> createState() =>
      _RevisarPlanificacionScreenState();
}

class _RevisarPlanificacionScreenState
    extends State<RevisarPlanificacionScreen> {
  List<dynamic> _planes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final planes = await PlanServicioService.getByLocalServicio(
          widget.localServicio.id);
      if (mounted) setState(() => _planes = planes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _eliminar(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar plan'),
        content:
            const Text('¿Estás seguro de eliminar este plan de servicio?'),
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
    if (ok != true) return;
    try {
      await PlanServicioService.delete(id);
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

  @override
  Widget build(BuildContext context) {
    final local = widget.localServicio.local;
    final servicio = widget.localServicio.servicio;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Revisar Planificación'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
          ),
        ],
      ),
      body: Column(
        children: [
          // Info del vínculo
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _InfoCard(local: local, servicio: servicio),
          ),
          const SizedBox(height: 8),
          const Divider(),

          // Lista de planes
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _planes.isEmpty
                    ? _EmptyPlanes(
                        onCrear: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CrearPlanificacionScreen(
                                localServicio: widget.localServicio),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _planes.length,
                          itemBuilder: (_, i) => _PlanCard(
                            plan: _planes[i],
                            onDelete: () => _eliminar(_planes[i].id),
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _planes.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CrearPlanificacionScreen(
                      localServicio: widget.localServicio),
                ),
              ).then((_) => _cargar()),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo plan'),
            )
          : null,
    );
  }
}

// ── Widgets compartidos ───────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final local;
  final servicio;
  const _InfoCard({required this.local, required this.servicio});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.store_outlined,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(local?.nombre ?? 'Local',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(servicio?.nombre ?? 'Servicio',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final dynamic plan;
  final VoidCallback onDelete;
  const _PlanCard({required this.plan, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final fecha = plan.fecha as DateTime?;
    final fechaStr = fecha != null
        ? DateFormat('EEE dd/MM/yyyy', 'es').format(fecha)
        : 'Sin fecha definida';
    final disponibles = plan.disponibles as int;
    final estaLleno = plan.estaLleno as bool;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icono estado
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: estaLleno
                    ? AppTheme.error.withOpacity(0.1)
                    : const Color(0xFF34C759).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                estaLleno ? Icons.block : Icons.calendar_month_outlined,
                color:
                    estaLleno ? AppTheme.error : const Color(0xFF34C759),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fechaStr,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _Chip(
                        label: 'Total: ${plan.cantidad}',
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 6),
                      _Chip(
                        label: 'Agendados: ${plan.agendados}',
                        color: const Color(0xFFFF9500),
                      ),
                      const SizedBox(width: 6),
                      _Chip(
                        label: 'Libres: $disponibles',
                        color: estaLleno
                            ? AppTheme.error
                            : const Color(0xFF34C759),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppTheme.error, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyPlanes extends StatelessWidget {
  final VoidCallback onCrear;
  const _EmptyPlanes({required this.onCrear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 64, color: AppTheme.primary.withOpacity(0.25)),
          const SizedBox(height: 16),
          const Text('Sin planes creados',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('Crea el primer plan para este\nlocal-servicio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onCrear,
            icon: const Icon(Icons.add),
            label: const Text('Crear plan'),
          ),
        ],
      ),
    );
  }
}
