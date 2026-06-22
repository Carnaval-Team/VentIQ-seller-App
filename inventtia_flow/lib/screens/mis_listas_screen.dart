import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/sala_espera.dart';
import '../providers/auth_provider.dart';
import '../services/lista_service.dart';
import 'local_servicio_detail_screen.dart';
import '../services/catalogo_service.dart';

class MisListasScreen extends StatefulWidget {
  const MisListasScreen({super.key});

  @override
  State<MisListasScreen> createState() => MisListasScreenState();
}

class MisListasScreenState extends State<MisListasScreen> {
  List<SalaEspera> _listas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void reload() => _load();

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final uuid = context.read<AuthProvider>().user?.id ?? '';
      final listas = await ListaService.getMisListas(uuid);
      if (!mounted) return;
      setState(() {
        _listas = listas;
        _isLoading = false;
      });
    } catch (e) {
      print('[flow] MisListasScreen _load ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _salir(SalaEspera s) async {
    final uuid = context.read<AuthProvider>().user?.id ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Salir de la lista'),
        content: Text(
            '¿Deseas salir de la cola de ${s.localServicio?.local?.nombre ?? 'este local'}?'),
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
    if (confirm != true) return;
    try {
      await ListaService.salirSalaEspera(
          uuidUsuario: uuid, idLocalServicio: s.idLocalServicio);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
        );
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Mis Listas'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _listas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.list_alt_outlined,
                          size: 64,
                          color: AppTheme.textSecondary.withOpacity(0.4)),
                      const SizedBox(height: 16),
                      const Text(
                        'No estás en ninguna lista',
                        style: TextStyle(
                            fontSize: 16, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Explora el catálogo y anótate en una cola',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _listas.length,
                    itemBuilder: (_, i) => _ListaCard(
                      sala: _listas[i],
                      onSalir: () => _salir(_listas[i]),
                      onTap: () async {
                        final ls = await CatalogoService.getLocalServicio(
                            _listas[i].idLocalServicio);
                        if (!mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LocalServicioDetailScreen(localServicio: ls),
                          ),
                        ).then((_) => _load());
                      },
                    ),
                  ),
                ),
    );
  }
}

class _ListaCard extends StatelessWidget {
  final SalaEspera sala;
  final VoidCallback onSalir;
  final VoidCallback onTap;

  const _ListaCard({
    required this.sala,
    required this.onSalir,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final local = sala.localServicio?.local;
    final servicio = sala.localServicio?.servicio;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.store,
                        color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          local?.nombre ?? 'Local',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (servicio != null)
                          Text(servicio.nombre,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.accent)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'N° ${sala.numeroCola}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.access_time,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Anotado: ${fmt.format(sala.fechaRegla.toLocal())}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onSalir,
                    icon: const Icon(Icons.exit_to_app,
                        size: 16, color: AppTheme.error),
                    label: const Text('Salir',
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.error)),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
