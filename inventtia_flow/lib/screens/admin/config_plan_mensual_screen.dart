import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/plan_config.dart';
import '../../models/servicio.dart';
import '../../providers/auth_provider.dart';
import '../../services/plan_config_service.dart';

/// Configuración recurrente de capacidades por día de la semana para un
/// local_servicio + generación de los plan_servicios de un mes en lote.
class ConfigPlanMensualScreen extends StatefulWidget {
  final LocalServicio localServicio;
  const ConfigPlanMensualScreen({super.key, required this.localServicio});

  @override
  State<ConfigPlanMensualScreen> createState() =>
      _ConfigPlanMensualScreenState();
}

class _ConfigPlanMensualScreenState extends State<ConfigPlanMensualScreen> {
  static const _nombresDia = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  final _defaultCtrl = TextEditingController(text: '30');
  // ISO 1..7 -> controlador (vacío = usar default)
  final Map<int, TextEditingController> _diaCtrls = {
    for (var d = 1; d <= 7; d++) d: TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;
  bool _generando = false;
  late DateTime _mesSel; // primer día del mes elegido

  String get _uuid => context.read<AuthProvider>().user?.id ?? '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Por defecto, el próximo mes (la idea es planificar por adelantado).
    _mesSel = DateTime(now.year, now.month + 1, 1);
    _cargar();
  }

  @override
  void dispose() {
    _defaultCtrl.dispose();
    for (final c in _diaCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final cfg = await PlanConfigService.obtenerConfig(
        uuidUsuario: _uuid,
        idLocalServicio: widget.localServicio.id,
      );
      if (cfg != null && mounted) {
        _defaultCtrl.text = cfg.porDefecto.toString();
        for (var d = 1; d <= 7; d++) {
          _diaCtrls[d]!.text =
              cfg.porDia.containsKey(d) ? cfg.porDia[d].toString() : '';
        }
      }
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

  PlanConfig _buildConfig() {
    final porDefecto = int.tryParse(_defaultCtrl.text.trim()) ?? 0;
    final porDia = <int, int>{};
    for (var d = 1; d <= 7; d++) {
      final txt = _diaCtrls[d]!.text.trim();
      if (txt.isEmpty) continue; // vacío = usar default
      final v = int.tryParse(txt);
      if (v != null) porDia[d] = v;
    }
    return PlanConfig(
      idLocalServicio: widget.localServicio.id,
      porDefecto: porDefecto,
      porDia: porDia,
    );
  }

  Future<void> _guardar() async {
    final porDefecto = int.tryParse(_defaultCtrl.text.trim());
    if (porDefecto == null || porDefecto < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ingresa una capacidad por defecto válida (≥ 0)'),
        backgroundColor: AppTheme.error,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await PlanConfigService.guardarConfig(
        uuidUsuario: _uuid,
        idLocalServicio: widget.localServicio.id,
        config: _buildConfig(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuración guardada'),
          backgroundColor: AppTheme.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickMes() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _mesSel,
      firstDate: DateTime(DateTime.now().year, DateTime.now().month, 1),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
      helpText: 'Elige cualquier día del mes a planificar',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() => _mesSel = DateTime(picked.year, picked.month, 1));
    }
  }

  Future<void> _generar() async {
    // Guarda primero para que la generación use lo que se ve en pantalla.
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Generar planes del mes'),
        content: Text(
          'Se crearán los planes de ${DateFormat('MMMM yyyy', 'es').format(_mesSel)} '
          'según la configuración. Los días que ya tengan plan se ajustarán a la '
          'nueva capacidad (sin bajar de lo ya reservado).\n\n'
          '¿Deseas guardar la configuración y generar?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _generando = true);
    try {
      // 1) Persistir config actual
      await PlanConfigService.guardarConfig(
        uuidUsuario: _uuid,
        idLocalServicio: widget.localServicio.id,
        config: _buildConfig(),
      );
      // 2) Generar el mes
      final res = await PlanConfigService.generarPlanMensual(
        uuidUsuario: _uuid,
        idLocalServicio: widget.localServicio.id,
        anio: _mesSel.year,
        mes: _mesSel.month,
      );
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Planificación generada'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResumenRow(
                    label: 'Creados', valor: res.creados, color: AppTheme.success),
                const SizedBox(height: 6),
                _ResumenRow(
                    label: 'Actualizados',
                    valor: res.actualizados,
                    color: AppTheme.primary),
                const SizedBox(height: 6),
                _ResumenRow(
                    label: 'Días sin cupo (cerrados)',
                    valor: res.diasSinCupo,
                    color: AppTheme.textSecondary),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicio = widget.localServicio.servicio;
    final local = widget.localServicio.local;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configuración mensual'),
            Text(
              '${servicio?.nombre ?? ''} · ${local?.nombre ?? ''}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _sectionTitle('Capacidades por día'),
                const SizedBox(height: 4),
                const Text(
                  'Define la capacidad por defecto y, opcionalmente, una distinta '
                  'por día. Deja un día vacío para usar el valor por defecto, o pon '
                  '0 para no abrir ese día.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                // Capacidad por defecto
                TextField(
                  controller: _defaultCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Capacidad por defecto *',
                    prefixIcon: Icon(Icons.tune),
                    hintText: 'Ej: 30',
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    child: Column(
                      children: [
                        for (var d = 1; d <= 7; d++) ...[
                          if (d > 1)
                            Divider(height: 1, color: Colors.grey.shade100),
                          _DiaRow(
                            nombre: _nombresDia[d - 1],
                            controller: _diaCtrls[d]!,
                            hintDefault: _defaultCtrl.text.trim(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _guardar,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
                ),

                const SizedBox(height: 28),
                _sectionTitle('Planificar mes'),
                const SizedBox(height: 4),
                const Text(
                  'Genera los planes del mes elegido a partir de la configuración '
                  'guardada. Puedes repetirlo cada mes.',
                  style: TextStyle(
                      fontSize: 12.5, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _pickMes,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_outlined,
                            color: AppTheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Mes a planificar',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary)),
                              Text(
                                DateFormat('MMMM yyyy', 'es')
                                    .format(_mesSel),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.edit_calendar,
                            size: 18, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _generando ? null : _generar,
                  icon: _generando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_motion_outlined),
                  label: Text(
                      _generando ? 'Generando...' : 'Generar planes del mes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: AppTheme.textSecondary,
        ),
      );
}

class _DiaRow extends StatelessWidget {
  final String nombre;
  final TextEditingController controller;
  final String hintDefault;

  const _DiaRow({
    required this.nombre,
    required this.controller,
    required this.hintDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(nombre,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: hintDefault.isEmpty ? 'def.' : hintDefault,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumenRow extends StatelessWidget {
  final String label;
  final int valor;
  final Color color;
  const _ResumenRow(
      {required this.label, required this.valor, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14))),
        Text('$valor',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
