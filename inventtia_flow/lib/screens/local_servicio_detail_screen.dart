import 'package:flutter/material.dart';
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
  List<SalaEspera> _cola = [];
  int _ultimoNumero = 0;
  bool _isLoading = true;
  bool _isJoining = false;
  SalaEspera? _miLugar;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final uuid = context.read<AuthProvider>().user?.id ?? '';
      final cola =
          await ListaService.getListaCompleta(widget.localServicio.id);
      final ultimo =
          await ListaService.getUltimoNumero(widget.localServicio.id);
      final miLugar = cola.where((s) => s.uuidUsuario == uuid).firstOrNull;
      setState(() {
        _cola = cola;
        _ultimoNumero = ultimo;
        _miLugar = miLugar;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _anotarse() async {
    final uuid = context.read<AuthProvider>().user?.id;
    if (uuid == null) return;
    setState(() => _isJoining = true);
    try {
      await ListaService.anotarseEnLista(
        uuidUsuario: uuid,
        idLocalServicio: widget.localServicio.id,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Te has anotado en la lista'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      setState(() => _isJoining = false);
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
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ListaService.salirDeLista(
        uuidUsuario: uuid, idLocalServicio: widget.localServicio.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.localServicio.local;
    final servicio = widget.localServicio.servicio;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: Text(local?.nombre ?? 'Local')),
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
                                        local?.nombre ?? '',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                      if (servicio != null)
                                        Text(servicio.nombre,
                                            style: const TextStyle(
                                                color: AppTheme.accent,
                                                fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (local?.descripcion != null) ...[
                              const SizedBox(height: 12),
                              Text(local!.descripcion!,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary)),
                            ],
                            if (local?.horarioAtencion != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      size: 16, color: AppTheme.textSecondary),
                                  const SizedBox(width: 6),
                                  Text(local!.horarioAtencion!,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.textSecondary)),
                                ],
                              ),
                            ],
                            if (local?.direccion != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 16, color: AppTheme.textSecondary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(local!.direccion!,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.textSecondary)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Estado de la cola
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _StatItem(
                                  label: 'En cola',
                                  value: '${_cola.length}',
                                  icon: Icons.people,
                                  color: AppTheme.primary,
                                ),
                                _StatItem(
                                  label: 'Último N°',
                                  value: '$_ultimoNumero',
                                  icon: Icons.tag,
                                  color: AppTheme.warning,
                                ),
                                if (_miLugar != null)
                                  _StatItem(
                                    label: 'Tu N°',
                                    value: '${_miLugar!.numeroCola}',
                                    icon: Icons.confirmation_num_outlined,
                                    color: AppTheme.success,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (_miLugar != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          AppTheme.success.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle,
                                        color: AppTheme.success),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Estás en la lista con el N° ${_miLugar!.numeroCola}',
                                        style: const TextStyle(
                                            color: AppTheme.success,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _salir,
                                icon: const Icon(Icons.exit_to_app),
                                label: const Text('Salir de la lista'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.error,
                                    side: const BorderSide(
                                        color: AppTheme.error)),
                              ),
                            ] else
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isJoining ? null : _anotarse,
                                  icon: _isJoining
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : const Icon(Icons.add),
                                  label: const Text('Anotarme en la Lista',
                                      style: TextStyle(fontSize: 15)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Lista de personas en cola
                    if (_cola.isNotEmpty) ...[
                      const Text(
                        'Cola de Espera',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._cola.map((s) {
                        final uuid =
                            context.read<AuthProvider>().user?.id ?? '';
                        final esYo = s.uuidUsuario == uuid;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: esYo
                                ? AppTheme.primary.withOpacity(0.08)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: esYo
                                  ? AppTheme.primary.withOpacity(0.3)
                                  : AppTheme.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: esYo
                                      ? AppTheme.primary
                                      : AppTheme.surface,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${s.numeroCola}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: esYo
                                          ? Colors.white
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                esYo ? 'Tú' : 'Persona ${s.numeroCola}',
                                style: TextStyle(
                                  fontWeight: esYo
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: esYo
                                      ? AppTheme.primary
                                      : AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
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
