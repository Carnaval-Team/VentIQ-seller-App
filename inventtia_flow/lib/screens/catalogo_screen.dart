import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/servicio.dart';
import '../services/catalogo_service.dart';
import 'local_servicio_detail_screen.dart';

class CatalogoScreen extends StatefulWidget {
  const CatalogoScreen({super.key});

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends State<CatalogoScreen> {
  List<LocalServicio> _localServicios = [];
  bool _isLoading = true;

  // Filtros
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _provinciaFiltro;

  // Datos derivados para los chips de provincia
  List<String> _provincias = [];

  // Rate limiting: máx 5 refrescos por minuto
  static const int _maxRefrescosPorMinuto = 5;
  final List<DateTime> _historialRefrescos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ahora = DateTime.now();
    final hace1Min = ahora.subtract(const Duration(minutes: 1));
    _historialRefrescos.removeWhere((t) => t.isBefore(hace1Min));

    if (_historialRefrescos.length >= _maxRefrescosPorMinuto) {
      final proxDisponible = _historialRefrescos.first.add(const Duration(minutes: 1));
      final espera = proxDisponible.difference(ahora).inSeconds + 1;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Límite alcanzado. Intenta en $espera s.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _historialRefrescos.add(ahora);
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final localServicios = await CatalogoService.getLocalServicios();
      final provinciaSet = <String>{};
      for (final ls in localServicios) {
        final p = ls.local?.provincia;
        if (p != null && p.isNotEmpty) provinciaSet.add(p);
      }
      setState(() {
        _localServicios = localServicios;
        _provincias = provinciaSet.toList()..sort();
        _isLoading = false;
      });
    } catch (e) {
      print('[flow] CatalogoScreen _load ERROR: $e');
      setState(() => _isLoading = false);
    }
  }

  List<LocalServicio> get _filtered {
    var lista = _localServicios;

    if (_provinciaFiltro != null) {
      lista = lista
          .where((ls) => ls.local?.provincia == _provinciaFiltro)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      lista = lista
          .where((ls) =>
              (ls.local?.nombre ?? '').toLowerCase().contains(q) ||
              (ls.servicio?.nombre ?? '').toLowerCase().contains(q))
          .toList();
    }

    return lista;
  }

  void _clearFiltros() {
    _searchCtrl.clear();
    setState(() {
      _searchQuery = '';
      _provinciaFiltro = null;
    });
  }

  bool get _hayFiltros => _searchQuery.isNotEmpty || _provinciaFiltro != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: Column(
        children: [
          // ── Hero con degradado de marca + buscador flotante ──
          _buildHero(),

          // ── Chips de provincia + contador (sobre la superficie) ──
          if (!_isLoading) _buildFiltersBar(),

          // ── Lista ─────────────────────────────────────
          Expanded(
            child: _isLoading
                ? _buildLoading()
                : _filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) =>
                              _LocalServicioCard(localServicio: _filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // Cabecera tipo "hero": gradiente de marca con esquinas inferiores
  // redondeadas. Contiene el saludo, el título grande y el buscador como
  // pastilla blanca flotando sobre el degradado.
  Widget _buildHero() {
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
            color: Color(0x331565C0),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXPLORA',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Servicios cerca de ti',
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
                          'Reserva tu turno y evita las filas',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Logo en pastilla translúcida
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.bolt_rounded,
                        color: Colors.white, size: 26),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSearchField(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 14.5, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Buscar servicio o local...',
          hintStyle:
              const TextStyle(color: AppTheme.textSecondary, fontSize: 14.5),
          prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildFiltersBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_provincias.isNotEmpty) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FilterChip(
                  label: 'Todas',
                  icon: Icons.public,
                  selected: _provinciaFiltro == null,
                  onTap: () => setState(() => _provinciaFiltro = null),
                ),
                ..._provincias.map((p) => _FilterChip(
                      label: p,
                      icon: Icons.place_outlined,
                      selected: _provinciaFiltro == p,
                      onTap: () => setState(() => _provinciaFiltro = p),
                    )),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
          child: Row(
            children: [
              Text(
                '${_filtered.length}',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _filtered.length == 1
                    ? 'servicio disponible'
                    : 'servicios disponibles',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_hayFiltros)
                GestureDetector(
                  onTap: _clearFiltros,
                  child: Row(
                    children: [
                      Icon(Icons.refresh,
                          size: 15,
                          color: AppTheme.primary.withValues(alpha: 0.9)),
                      const SizedBox(width: 3),
                      Text('Limpiar',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          SizedBox(height: 16),
          Text('Cargando servicios...',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
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
            child: Icon(Icons.travel_explore,
                size: 46, color: AppTheme.primary.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 18),
          const Text('Nada por aquí todavía',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Prueba con otra búsqueda o provincia',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          if (_hayFiltros) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _clearFiltros,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Limpiar filtros'),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected ? Colors.white : AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
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

class _LocalServicioCard extends StatelessWidget {
  final LocalServicio localServicio;

  const _LocalServicioCard({required this.localServicio});

  @override
  Widget build(BuildContext context) {
    final local = localServicio.local;
    final servicio = localServicio.servicio;

    return Container(
      margin: const EdgeInsets.only(top: 12),
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  LocalServicioDetailScreen(localServicio: localServicio),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Franja de acento vertical: identidad de marca en cada card.
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
                    child: Row(
                      children: [
                        // ── Avatar / foto del local ──
                        Container(
                          width: 66,
                          height: 66,
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
                          clipBehavior: Clip.antiAlias,
                          child: local?.foto != null
                              ? Image.network(
                                  local!.foto!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.storefront,
                                      color: AppTheme.primary,
                                      size: 30),
                                )
                              : const Icon(Icons.storefront,
                                  color: AppTheme.primary, size: 30),
                        ),
                        const SizedBox(width: 14),

                        // ── Datos ──
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
                                const SizedBox(height: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                          Icons.design_services_outlined,
                                          size: 12,
                                          color: AppTheme.accent),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          servicio.nombre,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.accent,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (local != null) ...[
                                if (local.ubicacion.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  _InfoLinea(
                                    icon: Icons.location_city_outlined,
                                    texto: local.ubicacion,
                                    bold: true,
                                  ),
                                ],
                                if (local.direccion != null &&
                                    local.direccion!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  _InfoLinea(
                                    icon: Icons.location_on_outlined,
                                    texto: local.direccion!,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // ── Indicador de navegación ──
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.arrow_forward_ios,
                              color: AppTheme.primary, size: 15),
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

// Línea de info con ícono + texto truncable (ubicación, dirección).
class _InfoLinea extends StatelessWidget {
  final IconData icon;
  final String texto;
  final bool bold;

  const _InfoLinea({
    required this.icon,
    required this.texto,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
