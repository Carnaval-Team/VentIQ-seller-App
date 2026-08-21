import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../models/cocina.dart';
import '../../services/cocina_service.dart';

/// Pestaña "Platos": asigna productos elaborados a una cocina y define su modo
/// de elaboración.
///
/// Es el paso que conecta el catálogo con las estaciones: un plato sin cocina
/// no se enruta a ninguna parte, y el modo (al pedido / por tanda) decide si se
/// cocina al pedirlo o se sirve de lo ya preparado.
class CocinasPlatosWidget extends StatefulWidget {
  const CocinasPlatosWidget({
    super.key,
    required this.searchQuery,
    required this.onRefresh,
  });

  final String searchQuery;
  final VoidCallback onRefresh;

  @override
  State<CocinasPlatosWidget> createState() => _CocinasPlatosWidgetState();
}

class _CocinasPlatosWidgetState extends State<CocinasPlatosWidget> {
  List<Cocina> _cocinas = [];

  /// Platos ya asignados, agrupados por id de cocina.
  final Map<int, List<Map<String, dynamic>>> _platosPorCocina = {};

  /// Elaborados de la tienda que todavía no tienen cocina.
  List<Map<String, dynamic>> _sinAsignar = [];

  bool _cargando = true;
  String? _error;

  /// Cocina cuya lista está expandida. Solo una a la vez para no saturar.
  int? _expandida;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final cocinas = await CocinaService.listarCocinas();
      final sinAsignar = await CocinaService.listarElaboradosSinCocina();

      // Se cargan los platos de cada cocina de una vez: son pocas cocinas por
      // tienda y así el usuario puede expandir sin esperas.
      final mapa = <int, List<Map<String, dynamic>>>{};
      for (final c in cocinas) {
        mapa[c.id] = await CocinaService.listarProductosDeCocina(c.id);
      }

      if (!mounted) return;
      setState(() {
        _cocinas = cocinas;
        _sinAsignar = sinAsignar;
        _platosPorCocina
          ..clear()
          ..addAll(mapa);
        _cargando = false;
      });
    } on CocinaException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.mensaje;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los platos: $e';
        _cargando = false;
      });
    }
  }

  bool _coincide(Map<String, dynamic> plato) {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final nombre = plato['denominacion']?.toString().toLowerCase() ?? '';
    final sku = plato['sku']?.toString().toLowerCase() ?? '';
    return nombre.contains(q) || sku.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 44, color: AppColors.error),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_cocinas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.soup_kitchen_outlined,
                size: 44,
                color: AppColors.textLight,
              ),
              SizedBox(height: 14),
              Text(
                'Primero crea una cocina',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'Los platos se asignan a una cocina. Crea una en la pestaña '
                'anterior y vuelve aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 32),
        children: [
          if (_sinAsignar.isNotEmpty) _buildSinAsignar(),
          ..._cocinas.map(_buildGrupoCocina),
        ],
      ),
    );
  }

  /// Bloque destacado con los elaborados que no van a ninguna cocina.
  /// Se pone arriba porque es el trabajo pendiente del gerente.
  Widget _buildSinAsignar() {
    final visibles = _sinAsignar.where(_coincide).toList();
    if (visibles.isEmpty && widget.searchQuery.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: 12,
          ),
          leading: const Icon(
            Icons.help_outline,
            color: AppColors.warning,
            size: 22,
          ),
          title: const Text(
            'Elaborados sin cocina',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            '${_sinAsignar.length} no se enrutan a ninguna estación',
            style: const TextStyle(fontSize: 12, color: AppColors.warning),
          ),
          children: visibles
              .map(
                (p) => _FilaPlato(
                  plato: p,
                  cocinas: _cocinas,
                  cocinaActual: null,
                  onAsignar: (idCocina, modo) =>
                      _asignar(p, idCocina, modo),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildGrupoCocina(Cocina cocina) {
    final todos = _platosPorCocina[cocina.id] ?? const [];
    final visibles = todos.where(_coincide).toList();

    // Con búsqueda activa, ocultar cocinas que no tienen coincidencias.
    if (widget.searchQuery.isNotEmpty && visibles.isEmpty) {
      return const SizedBox.shrink();
    }

    final expandida =
        _expandida == cocina.id || widget.searchQuery.isNotEmpty;
    final porTanda = todos
        .where((p) => p['modo_elaboracion'] == 'por_tanda')
        .length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('grupo_${cocina.id}_$expandida'),
          initiallyExpanded: expandida,
          onExpansionChanged: (abierto) => setState(
            () => _expandida = abierto ? cocina.id : null,
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.only(
            left: 14,
            right: 14,
            bottom: 12,
          ),
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: cocina.activa ? AppColors.primaryGradient : null,
              color: cocina.activa
                  ? null
                  : AppColors.textLight.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.soup_kitchen,
              size: 19,
              color: cocina.activa ? Colors.white : AppColors.textSecondary,
            ),
          ),
          title: Text(
            cocina.denominacion,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
              Text(
                '${todos.length} ${todos.length == 1 ? "plato" : "platos"}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (porTanda > 0) ...[
                const Text(
                  ' · ',
                  style: TextStyle(color: AppColors.textLight),
                ),
                Text(
                  '$porTanda por tanda',
                  style: const TextStyle(fontSize: 12, color: AppColors.info),
                ),
              ],
              if (!cocina.activa) ...[
                const Text(
                  ' · ',
                  style: TextStyle(color: AppColors.textLight),
                ),
                const Text(
                  'inactiva',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ],
            ],
          ),
          children: todos.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Sin platos asignados todavía.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                ]
              : visibles
                    .map(
                      (p) => _FilaPlato(
                        plato: p,
                        cocinas: _cocinas,
                        cocinaActual: cocina,
                        onAsignar: (idCocina, modo) =>
                            _asignar(p, idCocina, modo),
                      ),
                    )
                    .toList(),
        ),
      ),
    );
  }

  /// Asigna (o desasigna con idCocina == null) y refresca.
  Future<void> _asignar(
    Map<String, dynamic> plato,
    int? idCocina,
    ModoElaboracion? modo,
  ) async {
    final idProducto = (plato['id'] as num).toInt();
    final nombre = plato['denominacion']?.toString() ?? 'Plato';

    try {
      await CocinaService.asignarCocinaAProducto(
        idProducto: idProducto,
        idCocina: idCocina,
        modoElaboracion: modo,
      );

      if (!mounted) return;

      final texto = idCocina == null
          ? '"$nombre" quedó sin cocina'
          : '"$nombre" → ${_cocinas.firstWhere((c) => c.id == idCocina).denominacion}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(texto), backgroundColor: AppColors.success),
      );

      await _cargar();
      widget.onRefresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo asignar: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

/// Fila de un plato con su selector de cocina y de modo de elaboración.
class _FilaPlato extends StatelessWidget {
  const _FilaPlato({
    required this.plato,
    required this.cocinas,
    required this.cocinaActual,
    required this.onAsignar,
  });

  final Map<String, dynamic> plato;
  final List<Cocina> cocinas;
  final Cocina? cocinaActual;
  final void Function(int? idCocina, ModoElaboracion? modo) onAsignar;

  @override
  Widget build(BuildContext context) {
    final modo = ModoElaboracion.desdeValor(
      plato['modo_elaboracion']?.toString(),
    );
    final nombre = plato['denominacion']?.toString() ?? 'Sin nombre';
    final sku = plato['sku']?.toString();
    final vendible = plato['es_vendible'] != false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (sku != null && sku.isNotEmpty)
                      Text(
                        sku,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textLight,
                        ),
                      ),
                  ],
                ),
              ),
              if (!vendible)
                const Tooltip(
                  message: 'No vendible: no aparece en el catálogo del TPV',
                  child: Icon(
                    Icons.visibility_off_outlined,
                    size: 16,
                    color: AppColors.textLight,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _SelectorCocina(
                  cocinas: cocinas,
                  seleccionada: cocinaActual?.id,
                  onCambio: (id) => onAsignar(id, null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _SelectorModo(
                  modo: modo,
                  habilitado: cocinaActual != null,
                  onCambio: (m) => onAsignar(cocinaActual?.id, m),
                ),
              ),
            ],
          ),
          if (modo == ModoElaboracion.porTanda && cocinaActual != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 13,
                  color: AppColors.info,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Se vende del stock ya preparado en '
                    '${cocinaActual!.denominacion}.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.info,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectorCocina extends StatelessWidget {
  const _SelectorCocina({
    required this.cocinas,
    required this.seleccionada,
    required this.onCambio,
  });

  final List<Cocina> cocinas;
  final int? seleccionada;
  final ValueChanged<int?> onCambio;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: seleccionada,
      isExpanded: true,
      isDense: true,
      style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Cocina',
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Sin cocina', overflow: TextOverflow.ellipsis),
        ),
        ...cocinas.map(
          (c) => DropdownMenuItem<int?>(
            value: c.id,
            child: Text(
              c.activa ? c.denominacion : '${c.denominacion} (inactiva)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (v) {
        if (v != seleccionada) onCambio(v);
      },
    );
  }
}

class _SelectorModo extends StatelessWidget {
  const _SelectorModo({
    required this.modo,
    required this.habilitado,
    required this.onCambio,
  });

  final ModoElaboracion modo;
  final bool habilitado;
  final ValueChanged<ModoElaboracion> onCambio;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ModoElaboracion>(
      initialValue: modo,
      isExpanded: true,
      isDense: true,
      style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Modo',
        labelStyle: const TextStyle(fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: habilitado
            ? AppColors.surface
            : AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: ModoElaboracion.values
          .map(
            (m) => DropdownMenuItem(
              value: m,
              child: Tooltip(
                message: m.descripcion,
                child: Text(m.etiqueta, overflow: TextOverflow.ellipsis),
              ),
            ),
          )
          .toList(),
      // Sin cocina asignada el modo no tiene efecto: se deshabilita para no
      // dar la impresión de que hace algo.
      onChanged: habilitado
          ? (v) {
              if (v != null && v != modo) onCambio(v);
            }
          : null,
    );
  }
}
