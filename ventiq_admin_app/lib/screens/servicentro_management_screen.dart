import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../services/servicentro_service.dart';
import '../widgets/admin_drawer.dart';

/// Gestión de combustibles del modo servicentro (gerente).
///
/// Orden, color de carta, columnas del grid y alta/baja de productos
/// marcados como `es_combustible`.
class ServicentroManagementScreen extends StatefulWidget {
  final int idTpv;
  final String? tpvNombre;

  const ServicentroManagementScreen({
    super.key,
    required this.idTpv,
    this.tpvNombre,
  });

  @override
  State<ServicentroManagementScreen> createState() =>
      _ServicentroManagementScreenState();
}

class _ServicentroManagementScreenState
    extends State<ServicentroManagementScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _modoServicentro = false;
  int _columnas = 2;
  List<ServicentroProductoItem> _productos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await ServicentroService.getConfig(widget.idTpv);
      if (!mounted) return;
      setState(() {
        _modoServicentro = config.modoServicentro;
        _columnas = config.columnas.clamp(1, 4);
        _productos = List.of(config.productos);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _toggleModo(bool value) async {
    setState(() {
      _modoServicentro = value;
      _saving = true;
    });
    try {
      await ServicentroService.setModo(
        idTpv: widget.idTpv,
        activo: value,
        columnas: _columnas,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Modo servicentro activado en este TPV'
                : 'Modo servicentro desactivado',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _modoServicentro = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setColumnas(int value) async {
    setState(() {
      _columnas = value;
      _saving = true;
    });
    try {
      await ServicentroService.setColumnas(widget.idTpv, value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Columnas del grid: $value'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron guardar las columnas: $e'),
          backgroundColor: Colors.red,
        ),
      );
      await _cargar();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _mover(int index, int delta) async {
    final nuevo = index + delta;
    if (nuevo < 0 || nuevo >= _productos.length) return;

    final copia = List<ServicentroProductoItem>.of(_productos);
    final item = copia.removeAt(index);
    copia.insert(nuevo, item);
    setState(() {
      _productos = copia;
      _saving = true;
    });

    try {
      await ServicentroService.reordenar(
        idTpv: widget.idTpv,
        idsProducto: copia.map((e) => e.idProducto).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al reordenar: $e'),
          backgroundColor: Colors.red,
        ),
      );
      await _cargar();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cambiarColor(ServicentroProductoItem item) async {
    final elegido = await showDialog<String>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(initial: item.color),
    );
    if (elegido == null || elegido == item.color) return;

    setState(() => _saving = true);
    try {
      await ServicentroService.upsertProducto(
        idTpv: widget.idTpv,
        idProducto: item.idProducto,
        color: elegido,
        orden: item.orden,
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar color: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _quitar(ServicentroProductoItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Quitar combustible'),
            content: Text(
              '¿Quitar "${item.denominacion}" de la lista del servicentro?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Quitar'),
              ),
            ],
          ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await ServicentroService.eliminarProducto(idTpv: widget.idTpv, idProducto: item.idProducto);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al quitar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _agregar() async {
    final ids = _productos.map((e) => e.idProducto).toSet();
    final elegido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddCombustibleSheet(idsYaEnLista: ids),
    );
    if (elegido == null) return;

    final idProducto = (elegido['id'] as num?)?.toInt();
    if (idProducto == null) return;

    setState(() => _saving = true);
    try {
      await ServicentroService.upsertProducto(idTpv: widget.idTpv, idProducto: idProducto);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al agregar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _colorFromHex(String hex) {
    final parsed = ServicentroService.parseHexColor(hex);
    if (!parsed.valid || parsed.argb == null) {
      return const Color(0xFF64748B);
    }
    return Color(parsed.argb!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        title: Text(
          (widget.tpvNombre == null || widget.tpvNombre!.isEmpty)
              ? 'Servicentro'
              : 'Servicentro · ${widget.tpvNombre}',
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading || _saving ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _saving ? null : _agregar,
        icon: const Icon(Icons.add),
        label: const Text('Agregar combustible'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.local_gas_station,
                        color: _modoServicentro
                            ? AppColors.success
                            : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _modoServicentro
                              ? 'Modo servicentro activo'
                              : 'Modo servicentro inactivo',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _modoServicentro
                        ? 'Este TPV vende solo combustibles.'
                        : 'Activa el modo para que el vendedor de este TPV vea el grid.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Modo servicentro en este TPV'),
                    value: _modoServicentro,
                    onChanged: _saving ? null : _toggleModo,
                  ),
                  const Divider(height: 24),
                  Text(
                    'Columnas del grid en el vendedor',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                      ButtonSegment(value: 4, label: Text('4')),
                    ],
                    selected: {_columnas},
                    onSelectionChanged: _saving
                        ? null
                        : (s) => _setColumnas(s.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Combustibles (${_productos.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_productos.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hay combustibles en la lista.\n'
                  'Marca productos con “Es combustible” y agrégalos aquí.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            ...List.generate(_productos.length, (index) {
              final item = _productos[index];
              final color = _colorFromHex(item.color);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: InkWell(
                    onTap: _saving ? null : () => _cambiarColor(item),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: const Icon(
                        Icons.palette_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  title: Text(item.denominacion),
                  subtitle: Text(
                    [
                      if (item.sku != null && item.sku!.isNotEmpty)
                        'SKU ${item.sku}',
                      if (item.um != null && item.um!.isNotEmpty) item.um,
                      '\$${item.precioVenta.toStringAsFixed(2)}',
                      item.color,
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Subir',
                        onPressed: (!_saving && index > 0)
                            ? () => _mover(index, -1)
                            : null,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Bajar',
                        onPressed: (!_saving &&
                                index < _productos.length - 1)
                            ? () => _mover(index, 1)
                            : null,
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip: 'Quitar',
                        onPressed:
                            _saving ? null : () => _quitar(item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 16),
          Text(
            'Vista previa (${_columnas} col.)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (_productos.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _productos.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columnas,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.2,
              ),
              itemBuilder: (context, index) {
                final item = _productos[index];
                final color = _colorFromHex(item.color);
                return Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.denominacion,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '\$${item.precioVenta.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final String initial;
  const _ColorPickerDialog({required this.initial});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late String _selected;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _hexController = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Color de la carta'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ServicentroService.colorPresets.map((hex) {
                final parsed = ServicentroService.parseHexColor(hex);
                final color = Color(parsed.argb ?? 0xFF64748B);
                final selected = _selected.toUpperCase() == hex.toUpperCase();
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selected = hex;
                      _hexController.text = hex;
                    });
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.black : Colors.black12,
                        width: selected ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hexController,
              decoration: const InputDecoration(
                labelText: 'Hex (#RRGGBB)',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9A-Fa-f]')),
                LengthLimitingTextInputFormatter(7),
              ],
              onChanged: (v) {
                if (ServicentroService.parseHexColor(v).valid) {
                  setState(() => _selected = v);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: ServicentroService.parseHexColor(_selected).valid
              ? () => Navigator.pop(context, _selected)
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AddCombustibleSheet extends StatefulWidget {
  final Set<int> idsYaEnLista;
  const _AddCombustibleSheet({required this.idsYaEnLista});

  @override
  State<_AddCombustibleSheet> createState() => _AddCombustibleSheetState();
}

class _AddCombustibleSheetState extends State<_AddCombustibleSheet> {
  final _searchController = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _buscar([String q = '']) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ServicentroService.buscarCombustiblesDisponibles(
        idsYaEnLista: widget.idsYaEnLista,
        query: q,
      );
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Buscar combustible',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _buscar();
                      },
                    ),
                  ),
                  onChanged: (v) => _buscar(v),
                ),
              ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(child: Center(child: Text(_error!)))
              else if (_items.isEmpty)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No hay productos disponibles.\n'
                        'Marca “Es combustible” en el producto primero.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final p = _items[index];
                      return ListTile(
                        title: Text('${p['denominacion'] ?? ''}'),
                        subtitle: Text(
                          [
                            if ((p['sku'] ?? '').toString().isNotEmpty)
                              'SKU ${p['sku']}',
                            if ((p['um'] ?? '').toString().isNotEmpty)
                              '${p['um']}',
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
