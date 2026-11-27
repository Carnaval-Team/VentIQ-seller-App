import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/tienda_grupo_service.dart';
import '../utils/platform_utils.dart';

/// Tab de gestión multitienda: vincula tiendas secundarias a una principal.
/// Las secundarias dejan de listarse como clientes independientes en
/// licencias y en el reparto de pagos; al renovar la licencia de la
/// principal se renuevan todas las secundarias.
class MultitiendaTab extends StatefulWidget {
  final int revision;

  const MultitiendaTab({super.key, this.revision = 0});

  @override
  State<MultitiendaTab> createState() => _MultitiendaTabState();
}

class _MultitiendaTabState extends State<MultitiendaTab> {
  List<Map<String, dynamic>> _tiendas = [];
  bool _loading = true;
  String? _error;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MultitiendaTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _load();
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tiendas = await TiendaGrupoService.cargarTiendas();
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _tiendas = tiendas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _error =
            'No se pudieron cargar las tiendas: $e. '
            'Verifica que aplicaste SQL/tienda_multitienda.sql.';
        _loading = false;
      });
    }
  }

  Map<int, int> get _secAPrincipal =>
      TiendaGrupoService.mapaSecundariaPrincipal(_tiendas);

  Future<void> _vincular() async {
    final secAPrincipal = _secAPrincipal;
    final nombres = TiendaGrupoService.mapaNombres(_tiendas);

    int? principal;
    final seleccionadas = <int>{};
    var busquedaSec = '';
    final busquedaCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setLocal) => AlertDialog(
                  title: const Text('Configurar grupo multitienda'),
                  content: SizedBox(
                    width: 440,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownMenu<int>(
                          initialSelection: principal,
                          expandedInsets: EdgeInsets.zero,
                          enableFilter: true,
                          requestFocusOnTap: true,
                          label: const Text('Tienda principal'),
                          menuHeight: 280,
                          dropdownMenuEntries:
                              _tiendas
                                  .map(
                                    (t) => DropdownMenuEntry<int>(
                                      value: (t['id'] as num).toInt(),
                                      label:
                                          t['denominacion']?.toString() ??
                                          'Tienda',
                                    ),
                                  )
                                  .toList(),
                          onSelected:
                              (v) => setLocal(() {
                                principal = v;
                                seleccionadas
                                  ..clear()
                                  ..addAll(
                                    secAPrincipal.entries
                                        .where((e) => e.value == v)
                                        .map((e) => e.key),
                                  );
                              }),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: busquedaCtrl,
                          enabled: principal != null,
                          decoration: const InputDecoration(
                            labelText: 'Buscar secundarias',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setLocal(() => busquedaSec = v),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child:
                              principal == null
                                  ? const Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 24,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Selecciona primero la tienda principal',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  )
                                  : ListView(
                                    shrinkWrap: true,
                                    children:
                                        _tiendas.where((t) {
                                          final id =
                                              (t['id'] as num).toInt();
                                          if (id == principal) return false;
                                          final deOtro =
                                              secAPrincipal[id] != null &&
                                              secAPrincipal[id] != principal;
                                          // Sin cadenas: una tienda que ya es
                                          // principal de un grupo no puede ser
                                          // secundaria de otra.
                                          final esPrincipal =
                                              secAPrincipal.values.contains(id);
                                          if (deOtro || esPrincipal) {
                                            return false;
                                          }
                                          final nombre = (t['denominacion']
                                                      ?.toString() ??
                                                  '')
                                              .toLowerCase();
                                          return nombre.contains(
                                            busquedaSec.toLowerCase(),
                                          );
                                        }).map((t) {
                                          final id =
                                              (t['id'] as num).toInt();
                                          return CheckboxListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            value: seleccionadas.contains(id),
                                            title: Text(
                                              t['denominacion']?.toString() ??
                                                  'Tienda',
                                            ),
                                            onChanged: (v) {
                                              setLocal(() {
                                                if (v == true) {
                                                  seleccionadas.add(id);
                                                } else {
                                                  seleccionadas.remove(id);
                                                }
                                              });
                                            },
                                          );
                                        }).toList(),
                                  ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Las secundarias dejan de listarse como clientes '
                          'independientes: se cobran y renuevan por la '
                          'principal. Desmarcar una las desvincula.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (principal == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecciona la tienda principal'),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Guardar grupo'),
                    ),
                  ],
                ),
          ),
    );

    if (ok != true || principal == null) {
      busquedaCtrl.dispose();
      return;
    }

    try {
      final idPrincipal = principal!;
      final actuales =
          secAPrincipal.entries
              .where((e) => e.value == idPrincipal)
              .map((e) => e.key)
              .toSet();
      for (final id in seleccionadas.difference(actuales)) {
        await TiendaGrupoService.asignarPrincipal(id, idPrincipal);
      }
      for (final id in actuales.difference(seleccionadas)) {
        await TiendaGrupoService.asignarPrincipal(id, null);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Grupo de ${nombres[idPrincipal] ?? idPrincipal} actualizado',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al vincular: $e')),
        );
      }
    } finally {
      busquedaCtrl.dispose();
    }
  }

  Future<void> _desvincular(int idTienda) async {
    try {
      await TiendaGrupoService.asignarPrincipal(idTienda, null);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al desvincular: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    final nombres = TiendaGrupoService.mapaNombres(_tiendas);
    final secAPrincipal = _secAPrincipal;
    final grupos = TiendaGrupoService.secundariasPorPrincipal(_tiendas);
    final principales = grupos.keys.toList()
      ..sort(
        (a, b) => (nombres[a] ?? '').toLowerCase().compareTo(
          (nombres[b] ?? '').toLowerCase(),
        ),
      );
    final libres =
        _tiendas
            .where(
              (t) =>
                  !secAPrincipal.containsKey((t['id'] as num).toInt()) &&
                  !grupos.containsKey((t['id'] as num).toInt()),
            )
            .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Grupos multitienda',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _vincular,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Vincular tienda'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Las secundarias se agrupan bajo su principal en licencias y en el '
            'reparto de pagos. Renovar la licencia de la principal renueva '
            'todas las secundarias.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (principales.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay grupos multitienda configurados.'),
              ),
            )
          else
            ...principales.map((idPrincipal) {
              final secundarias = grupos[idPrincipal]!..sort();
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.store, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nombres[idPrincipal] ?? 'Tienda #$idPrincipal',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            '${secundarias.length} secundaria(s)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            secundarias.map((idSec) {
                              return Chip(
                                avatar: const Icon(
                                  Icons.storefront,
                                  size: 16,
                                ),
                                label: Text(nombres[idSec] ?? 'Tienda #$idSec'),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () => _desvincular(idSec),
                                deleteButtonTooltipMessage: 'Desvincular',
                              );
                            }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Tiendas sin grupo (${libres.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            children:
                libres
                    .map(
                      (t) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.store_outlined, size: 18),
                        title: Text(t['denominacion']?.toString() ?? 'Tienda'),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }
}
