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
      // Verificar duplicado antes de mostrar confirmación
      if (_fecha != null) {
        final existe = await PlanServicioService.existePlanParaFecha(
          idLocalServicio: widget.localServicio.id,
          fecha: _fecha!,
        );
        if (existe) {
          if (!mounted) return;
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ya existe un plan para este servicio en esa fecha'),
              backgroundColor: AppTheme.error,
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      setState(() => _saving = false);

      // Mostrar diálogo de confirmación
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmacionDialog(
          local: widget.localServicio.local,
          servicio: widget.localServicio.servicio,
          fecha: _fecha,
          cantidad: int.parse(_cantidadCtrl.text.trim()),
        ),
      );
      if (confirmado != true) return;

      await _confirmarYCrear();
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

  Future<void> _confirmarYCrear() async {
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

// ── Diálogo de confirmación ───────────────────────────────────
class _ConfirmacionDialog extends StatelessWidget {
  final dynamic local;
  final dynamic servicio;
  final DateTime? fecha;
  final int cantidad;

  const _ConfirmacionDialog({
    required this.local,
    required this.servicio,
    required this.fecha,
    required this.cantidad,
  });

  @override
  Widget build(BuildContext context) {
    final fechaStr = fecha != null
        ? DateFormat('EEEE dd \'de\' MMMM yyyy', 'es').format(fecha!)
        : 'Sin fecha definida';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Encabezado
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
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Revisa los detalles antes de crear',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),

            // Fila: Local
            _DetailRow(
              icon: Icons.store_outlined,
              label: 'Local',
              value: local?.nombre ?? '-',
              iconColor: const Color(0xFF4F7FFA),
            ),
            const SizedBox(height: 14),

            // Fila: Servicio
            _DetailRow(
              icon: Icons.miscellaneous_services_outlined,
              label: 'Servicio',
              value: servicio?.nombre ?? '-',
              iconColor: const Color(0xFF7C5CFC),
            ),
            const SizedBox(height: 14),

            // Fila: Fecha
            _DetailRow(
              icon: Icons.calendar_month_outlined,
              label: 'Fecha',
              value: fechaStr,
              iconColor: const Color(0xFF34C759),
            ),
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),

            // Cantidad destacada
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group_outlined,
                        color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cantidad de turnos',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '$cantidad',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Botones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Confirmar y crear',
                        style: TextStyle(fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
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

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}
