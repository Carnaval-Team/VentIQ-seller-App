import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/sala_espera.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/lista_service.dart';
import 'local_servicio_detail_screen.dart';
import '../services/catalogo_service.dart';
import '../widgets/notificaciones_bell.dart';

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
      final uuid = AuthService.currentUserId ?? '';
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
    final uuid = AuthService.currentUserId ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
      body: Column(
        children: [
          _buildHero(),
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _listas.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: _listas.length,
                          itemBuilder: (_, i) => _ListaCard(
                            sala: _listas[i],
                            onSalir: () => _salir(_listas[i]),
                            onTap: () async {
                              final ls =
                                  await CatalogoService.getLocalServicio(
                                      _listas[i].idLocalServicio);
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LocalServicioDetailScreen(
                                      localServicio: ls),
                                ),
                              ).then((_) => _load());
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // Cabecera "hero" coherente con el catálogo: degradado de marca, eyebrow,
  // título grande, contador de colas activas y la campana de notificaciones.
  Widget _buildHero() {
    final n = _listas.length;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33405F90),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TUS COLAS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mis Listas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLoading
                          ? 'Cargando tus colas...'
                          : n == 0
                              ? 'No estás en ninguna cola'
                              : n == 1
                                  ? 'Estás en 1 cola activa'
                                  : 'Estás en $n colas activas',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _HeroIconButton(onTap: _load),
                  const SizedBox(width: 4),
                  const NotificacionesBell(color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          SizedBox(height: 16),
          Text('Cargando tus colas...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.12),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.10),
                        AppTheme.accent.withValues(alpha: 0.10),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.list_alt_rounded,
                      size: 46, color: AppTheme.primary.withValues(alpha: 0.55)),
                ),
                const SizedBox(height: 18),
                const Text('No estás en ninguna lista',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Explora el catálogo y anótate en una cola',
                    style:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Botón circular translúcido para acciones dentro del hero.
class _HeroIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.refresh, color: Colors.white, size: 22),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Franja de acento vertical (identidad de marca).
                Container(
                  width: 5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppTheme.primary, AppTheme.accent],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Avatar del local.
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppTheme.primary.withValues(alpha: 0.14),
                                    AppTheme.accent.withValues(alpha: 0.14),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.storefront_rounded,
                                  color: AppTheme.primary, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    local?.nombre ?? 'Local',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: AppTheme.textPrimary,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (servicio != null) ...[
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        const Icon(Icons.design_services_outlined,
                                            size: 12, color: AppTheme.accent),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            servicio.nombre,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              color: AppTheme.accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Badge con el número de cola.
                            _ColaBadge(numero: sala.numeroCola),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(height: 1, color: AppTheme.border),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Anotado el ${fmt.format(sala.fechaRegla.toLocal())}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _SalirButton(onTap: onSalir),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Pastilla con el turno (número de cola) destacada con degradado de marca.
class _ColaBadge extends StatelessWidget {
  final int numero;
  const _ColaBadge({required this.numero});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.primaryLight],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.30),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TURNO',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$numero',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// Botón "Salir" discreto con fondo suave de error.
class _SalirButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SalirButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.exit_to_app_rounded, size: 15, color: AppTheme.error),
              SizedBox(width: 4),
              Text('Salir',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.error)),
            ],
          ),
        ),
      ),
    );
  }
}
