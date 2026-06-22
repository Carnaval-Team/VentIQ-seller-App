import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/servicio.dart';
import '../models/sala_espera.dart';
import '../providers/auth_provider.dart';
import '../services/lista_service.dart';

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

    setState(() => _isActing = true);
    try {
      await ListaService.entrarSalaEspera(
        uuidUsuario: uuid,
        idLocalServicio: widget.localServicio.id,
        fechaRegla: fecha,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Anotado para el ${DateFormat('dd/MM/yyyy').format(fecha)}'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: AppTheme.error),
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
          const SnackBar(content: Text('Saliste de la lista')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()),
              backgroundColor: AppTheme.error),
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

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: Text(servicio?.nombre ?? 'Servicio')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(Icons.store,
                                      color: AppTheme.primary, size: 32),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        servicio?.nombre ?? '',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      if (local != null)
                                        Text(local.nombre,
                                            style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (servicio?.descripcion != null) ...[
                              const SizedBox(height: 12),
                              Text(servicio!.descripcion!,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary)),
                            ],
                            if (local?.horarioAtencion != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      size: 16,
                                      color: AppTheme.textSecondary),
                                  const SizedBox(width: 6),
                                  Text(local!.horarioAtencion!,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSecondary)),
                                ],
                              ),
                            ],
                            if (local?.ubicacion.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.map_outlined,
                                      size: 16,
                                      color: AppTheme.textSecondary),
                                  const SizedBox(width: 6),
                                  Text(local!.ubicacion,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSecondary)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Contadores de cola
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatItem(
                              label: 'Último atendido',
                              value: '$_ultimoOtorgado',
                              icon: Icons.check_circle_outline,
                              color: AppTheme.primary,
                            ),
                            _StatItem(
                              label: 'Último anotado',
                              value: '$_ultimoEnAnotarse',
                              icon: Icons.person_add_outlined,
                              color: AppTheme.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Acción sala de espera
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _miLugar != null
                            ? Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color:
                                          AppTheme.success.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: AppTheme.success
                                              .withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle,
                                            color: AppTheme.success, size: 28),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Estás en la lista · N° ${_miLugar!.numeroCola}',
                                                style: const TextStyle(
                                                    color: AppTheme.success,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    fontSize: 15),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'A partir del ${DateFormat('dd/MM/yyyy').format(_miLugar!.fechaRegla)}',
                                                style: const TextStyle(
                                                    color: AppTheme.success,
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: _isActing ? null : _salir,
                                      icon: _isActing
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(
                                                      strokeWidth: 2))
                                          : const Icon(Icons.exit_to_app),
                                      label: const Text('Salir de la lista'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.error,
                                        side: const BorderSide(
                                            color: AppTheme.error),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isActing ? null : _anotarse,
                                  icon: _isActing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : const Icon(Icons.playlist_add),
                                  label: const Text('Anotarme en la lista',
                                      style: TextStyle(fontSize: 15)),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 6),
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}
