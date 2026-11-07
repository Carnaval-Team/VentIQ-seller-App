import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/costos_nomenclador_service.dart';
import '../widgets/app_drawer.dart';

/// Nomencladores globales de costo (tipos + naturalezas).
///
/// Catálogo compartido por todas las tiendas; lo usan gastos financieros y
/// costos adicionales por producto en admin.
class CostosNomencladorScreen extends StatefulWidget {
  const CostosNomencladorScreen({super.key});

  @override
  State<CostosNomencladorScreen> createState() =>
      _CostosNomencladorScreenState();
}

class _CostosNomencladorScreenState extends State<CostosNomencladorScreen>
    with SingleTickerProviderStateMixin {
  final _service = CostosNomencladorService();
  late final TabController _tabs;

  List<Map<String, dynamic>> _tipos = [];
  List<Map<String, dynamic>> _naturalezas = [];
  bool _loadingTipos = true;
  bool _loadingNaturalezas = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _cargarTodo();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    await Future.wait([_cargarTipos(), _cargarNaturalezas()]);
  }

  Future<void> _cargarTipos() async {
    setState(() => _loadingTipos = true);
    try {
      final rows = await _service.listarTipos();
      if (!mounted) return;
      setState(() {
        _tipos = rows;
        _loadingTipos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingTipos = false);
      _avisar('Error cargando tipos: $e', error: true);
    }
  }

  Future<void> _cargarNaturalezas() async {
    setState(() => _loadingNaturalezas = true);
    try {
      // Si el wipe dejó la tabla vacía, resiembra Gasto/Ingreso.
      final rows = await _service.asegurarNaturalezasBase();
      if (!mounted) return;
      setState(() {
        _naturalezas = rows;
        _loadingNaturalezas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingNaturalezas = false);
      _avisar('Error cargando naturalezas: $e', error: true);
    }
  }

  void _avisar(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }

  String _nombreNaturaleza(dynamic naturalezaId) {
    final id = naturalezaId is int
        ? naturalezaId
        : int.tryParse('$naturalezaId');
    for (final n in _naturalezas) {
      final nid = n['id'] is int ? n['id'] as int : int.tryParse('${n['id']}');
      if (nid == id) return n['denominacion']?.toString() ?? '—';
    }
    return id == null ? '—' : 'Nat. $id';
  }

  Future<void> _editarTipo({Map<String, dynamic>? existing}) async {
    // Refrescar naturalezas por si la BD se limpió con la app abierta.
    try {
      final rows = await _service.asegurarNaturalezasBase();
      if (!mounted) return;
      setState(() => _naturalezas = rows);
    } catch (e) {
      _avisar('No se pudieron cargar naturalezas: $e', error: true);
      return;
    }

    if (_naturalezas.isEmpty) {
      _avisar('Crea al menos una naturaleza antes de agregar tipos.', error: true);
      return;
    }

    final nombreCtrl = TextEditingController(
      text: existing?['denominacion']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text: existing?['descripcion']?.toString() ?? '',
    );
    final idsNat = _naturalezas
        .map((n) => (n['id'] as num).toInt())
        .toList();
    final preferred = (existing?['naturaleza'] as num?)?.toInt();
    int naturaleza =
        (preferred != null && idsNat.contains(preferred))
            ? preferred
            : idsNat.first;
    bool afectaMargen = existing?['afecta_margen'] as bool? ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Nuevo tipo de costo' : 'Editar tipo de costo',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Denominación',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Descripción',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: naturaleza,
                        decoration: const InputDecoration(
                          labelText: 'Naturaleza',
                          border: OutlineInputBorder(),
                        ),
                        items: _naturalezas
                            .map(
                              (n) => DropdownMenuItem<int>(
                                value: (n['id'] as num).toInt(),
                                child: Text(n['denominacion']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setLocal(() => naturaleza = v);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Afecta margen'),
                        value: afectaMargen,
                        onChanged: (v) => setLocal(() => afectaMargen = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    final nombre = nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _avisar('La denominación es obligatoria', error: true);
      return;
    }

    try {
      if (existing == null) {
        await _service.crearTipo(
          denominacion: nombre,
          descripcion: descCtrl.text,
          naturaleza: naturaleza,
          afectaMargen: afectaMargen,
        );
        _avisar('Tipo de costo creado');
      } else {
        await _service.actualizarTipo(
          id: existing['id'] as int,
          denominacion: nombre,
          descripcion: descCtrl.text,
          naturaleza: naturaleza,
          afectaMargen: afectaMargen,
        );
        _avisar('Tipo de costo actualizado');
      }
      await _cargarTipos();
    } catch (e) {
      _avisar('Error: $e', error: true);
    }
  }

  Future<void> _eliminarTipo(Map<String, dynamic> tipo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar tipo de costo'),
        content: Text(
          '¿Eliminar «${tipo['denominacion']}»?\n'
          'Fallará si ya está referenciado por gastos o costos de producto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.eliminarTipo(tipo['id'] as int);
      _avisar('Tipo eliminado');
      await _cargarTipos();
    } catch (e) {
      _avisar('No se pudo eliminar: $e', error: true);
    }
  }

  Future<void> _editarNaturaleza({Map<String, dynamic>? existing}) async {
    final nombreCtrl = TextEditingController(
      text: existing?['denominacion']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text: existing?['descripcion']?.toString() ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          existing == null ? 'Nueva naturaleza' : 'Editar naturaleza',
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Denominación',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final nombre = nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _avisar('La denominación es obligatoria', error: true);
      return;
    }

    try {
      if (existing == null) {
        await _service.crearNaturaleza(
          denominacion: nombre,
          descripcion: descCtrl.text,
        );
        _avisar('Naturaleza creada');
      } else {
        await _service.actualizarNaturaleza(
          id: (existing['id'] as num).toInt(),
          denominacion: nombre,
          descripcion: descCtrl.text,
        );
        _avisar('Naturaleza actualizada');
      }
      await _cargarNaturalezas();
      await _cargarTipos();
    } catch (e) {
      _avisar('Error: $e', error: true);
    }
  }

  Future<void> _eliminarNaturaleza(Map<String, dynamic> nat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar naturaleza'),
        content: Text(
          '¿Eliminar «${nat['denominacion']}»?\n'
          'Solo es posible si ningún tipo de costo la referencia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.eliminarNaturaleza((nat['id'] as num).toInt());
      _avisar('Naturaleza eliminada');
      await _cargarNaturalezas();
    } catch (e) {
      _avisar('No se pudo eliminar: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Nomencladores de costo'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Tipos de costo'),
            Tab(text: 'Naturalezas'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargarTodo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabs.index == 0) {
            _editarTipo();
          } else {
            _editarNaturaleza();
          }
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(_tabs.index == 0 ? 'Nuevo tipo' : 'Nueva naturaleza'),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildTiposTab(),
          _buildNaturalezasTab(),
        ],
      ),
    );
  }

  Widget _buildTiposTab() {
    if (_loadingTipos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tipos.isEmpty) {
      return const Center(
        child: Text('No hay tipos de costo. Crea el primero.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: _tipos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final t = _tipos[index];
        final afecta = t['afecta_margen'] == true;
        final natNombre = () {
          final nested = t['app_nom_naturaleza_costo'];
          if (nested is Map && nested['denominacion'] != null) {
            return nested['denominacion'].toString();
          }
          return _nombreNaturaleza(t['naturaleza']);
        }();

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.divider),
          ),
          child: ListTile(
            title: Text(
              t['denominacion']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                if ((t['descripcion']?.toString() ?? '').isNotEmpty)
                  t['descripcion'].toString(),
                'Naturaleza: $natNombre',
                afecta ? 'Afecta margen' : 'No afecta margen',
              ].join('\n'),
            ),
            isThreeLine: true,
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editarTipo(existing: t),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => _eliminarTipo(t),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNaturalezasTab() {
    if (_loadingNaturalezas) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_naturalezas.isEmpty) {
      return const Center(
        child: Text('No hay naturalezas. Crea Gasto / Ingreso u otras.'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: _naturalezas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final n = _naturalezas[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.divider),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              foregroundColor: AppColors.primary,
              child: Text('${n['id']}'),
            ),
            title: Text(
              n['denominacion']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(n['descripcion']?.toString() ?? 'Sin descripción'),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editarNaturaleza(existing: n),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => _eliminarNaturaleza(n),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
