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
      appBar: AppBar(
        title: const Text('Catálogo de Servicios'),
        actions: [
          if (_hayFiltros)
            TextButton(
              onPressed: _clearFiltros,
              child: const Text('Limpiar',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Buscador ──────────────────────────────────
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar por servicio o local...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                // ── Chips de provincia ────────────────────────
                if (_provincias.isNotEmpty)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'Todas',
                            selected: _provinciaFiltro == null,
                            onTap: () =>
                                setState(() => _provinciaFiltro = null),
                          ),
                          ..._provincias.map((p) => _FilterChip(
                                label: p,
                                selected: _provinciaFiltro == p,
                                onTap: () => setState(
                                    () => _provinciaFiltro = p),
                              )),
                        ],
                      ),
                    ),
                  ),

                const Divider(height: 1),

                // ── Contador de resultados ────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        '${_filtered.length} resultado${_filtered.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                      if (_provinciaFiltro != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.map_outlined,
                                  size: 12, color: AppTheme.primary),
                              const SizedBox(width: 4),
                              Text(_provinciaFiltro!,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ── Lista ─────────────────────────────────────
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off,
                                  size: 56,
                                  color: AppTheme.primary.withOpacity(0.3)),
                              const SizedBox(height: 12),
                              const Text('Sin resultados',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 15)),
                              if (_hayFiltros) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: _clearFiltros,
                                  child: const Text('Limpiar filtros'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                LocalServicioDetailScreen(localServicio: localServicio),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: local?.foto != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(local!.foto!, fit: BoxFit.cover),
                      )
                    : const Icon(Icons.store,
                        color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
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
                    if (servicio != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          servicio.nombre,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    // Ubicación: provincia/país + dirección
                    if (local != null) ...[
                      if (local.ubicacion.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.map_outlined,
                                size: 13, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              local.ubicacion,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      if (local.direccion != null)
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 13, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                local.direccion!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
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
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
