import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../models/servicio.dart';
import '../providers/favoritos_provider.dart';
import '../services/auth_service.dart';
import '../services/favorito_service.dart';
import '../utils/precio_reserva.dart';
import '../widgets/net_image.dart';
import '../widgets/notificaciones_bell.dart';
import 'local_servicio_detail_screen.dart';

/// Servicios que el cliente guardó con el corazón.
///
/// No confundir con "Mis Listas" (`MisListasScreen`), que es la **sala de
/// espera**: una entrada de cola dura lo que dura la cola y se puede
/// abandonar; un favorito es permanente hasta que se quita.
class FavoritosScreen extends StatefulWidget {
  const FavoritosScreen({super.key});

  @override
  State<FavoritosScreen> createState() => FavoritosScreenState();
}

class FavoritosScreenState extends State<FavoritosScreen> {
  List<LocalServicio> _favoritos = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void reload() => _cargar();

  Future<void> _cargar() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final lista = await FavoritoService.getLocalServiciosFavoritos(uuid);
      if (!mounted) return;
      setState(() {
        _favoritos = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'No pudimos cargar tus favoritos. Si el problema continúa, revisa '
            'tu conexión.';
        _cargando = false;
      });
      debugPrint('[flow] FavoritosScreen._cargar ERROR: $e');
    }
  }

  Future<void> _quitar(LocalServicio ls) async {
    final favoritos = context.read<FavoritosProvider>();
    // Optimista: la fila desaparece ya; si falla, se recarga.
    setState(() {
      _favoritos = _favoritos.where((f) => f.id != ls.id).toList();
    });
    try {
      await favoritos.alternar(ls.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos quitar el favorito.'),
          backgroundColor: AppTheme.error,
        ),
      );
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Column(
        children: [
          _buildHero(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildError()
                : _favoritos.isEmpty
                ? _buildVacio()
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _cargar,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: _favoritos.length,
                      itemBuilder: (_, i) => _FavoritoCard(
                        localServicio: _favoritos[i],
                        onQuitar: () => _quitar(_favoritos[i]),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LocalServicioDetailScreen(
                                localServicio: _favoritos[i],
                              ),
                            ),
                          );
                          // El detalle también permite quitar el favorito.
                          if (mounted) await _cargar();
                        },
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final n = _favoritos.length;
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
                      'GUARDADOS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Favoritos',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      n == 0
                          ? 'Todavía no guardaste servicios'
                          : n == 1
                          ? '1 servicio guardado'
                          : '$n servicios guardados',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const NotificacionesBell(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: 56,
              color: AppTheme.primary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 14),
            const Text(
              'Sin favoritos todavía',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Toca el corazón de un servicio y aparecerá aquí, listo para '
              'reservarlo cuando quieras.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: AppTheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritoCard extends StatelessWidget {
  final LocalServicio localServicio;
  final VoidCallback onTap;
  final VoidCallback onQuitar;

  const _FavoritoCard({
    required this.localServicio,
    required this.onTap,
    required this.onQuitar,
  });

  @override
  Widget build(BuildContext context) {
    final servicio = localServicio.servicio;
    final local = localServicio.local;
    final foto = servicio?.foto ?? local?.foto;
    final precio = _precioLabel(servicio);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: (foto == null || foto.trim().isEmpty)
                      ? Container(
                          color: AppTheme.surface,
                          child: const Icon(
                            Icons.image_outlined,
                            color: AppTheme.textSecondary,
                          ),
                        )
                      : NetImage(
                          url: foto,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorWidget: () => Container(
                            color: AppTheme.surface,
                            child: const Icon(
                              Icons.image_outlined,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      servicio?.nombre ?? 'Servicio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      local?.nombre ?? 'Local',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (localServicio.permiteReservaDirecta)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Reserva directa',
                              style: TextStyle(
                                color: AppTheme.success,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          precio ?? 'Consultar',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onQuitar,
                tooltip: 'Quitar de favoritos',
                icon: const Icon(
                  Icons.favorite_rounded,
                  color: AppTheme.error,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Precio base de la moneda por defecto del servicio, o `null` si no tiene
  /// (`config_precio = '{}'`, caso real en varios servicios). La regla vive en
  /// `utils/precio_reserva.dart` para no duplicarla con el Home.
  static String? _precioLabel(Servicio? servicio) =>
      etiquetaPrecioBase(servicio?.configPrecio);
}
