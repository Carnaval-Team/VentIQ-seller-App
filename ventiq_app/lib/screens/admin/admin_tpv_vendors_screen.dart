import 'package:flutter/material.dart';

import '../../services/admin_inventory_service.dart';

/// Gestión lite de TPVs y vendedores (offline-first).
class AdminTpvVendorsScreen extends StatefulWidget {
  const AdminTpvVendorsScreen({super.key});

  @override
  State<AdminTpvVendorsScreen> createState() => _AdminTpvVendorsScreenState();
}

class _AdminTpvVendorsScreenState extends State<AdminTpvVendorsScreen>
    with SingleTickerProviderStateMixin {
  final _service = AdminInventoryService();
  final _searchCtrl = TextEditingController();
  late TabController _tabs;

  List<Map<String, dynamic>> _tpvs = [];
  List<Map<String, dynamic>> _vendors = [];
  List<Map<String, dynamic>> _warehouses = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final q = _searchCtrl.text;
    final tpvs = await _service.listCachedTpvs();
    final vendors = await _service.listCachedVendors(query: q);
    final warehouses = await _service.listCachedWarehouses();
    final filteredTpvs = q.trim().isEmpty
        ? tpvs
        : tpvs
            .where(
              (t) => (t['denominacion']?.toString().toLowerCase() ?? '')
                  .contains(q.trim().toLowerCase()),
            )
            .toList();
    if (!mounted) return;
    setState(() {
      _tpvs = filteredTpvs;
      _vendors = vendors;
      _warehouses = warehouses;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final n = await _service.syncTpvsAndPricesFromServer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cache: ${n['tpvs']} TPVs, ${n['vendors']} vendedores, '
            '${n['warehouses']} almacenes',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _createTpv() async {
    if (_warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin almacenes en cache. Sincroniza online primero.'),
        ),
      );
      return;
    }
    final nameCtrl = TextEditingController();
    int? almacenId = (_warehouses.first['id'] as num?)?.toInt();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nuevo TPV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Denominación',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: almacenId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Almacén',
                  border: OutlineInputBorder(),
                ),
                items: _warehouses
                    .map(
                      (w) => DropdownMenuItem<int>(
                        value: (w['id'] as num?)?.toInt(),
                        child: Text(
                          w['denominacion']?.toString() ?? '#${w['id']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .where((i) => i.value != null)
                    .toList(),
                onChanged: (v) => setLocal(() => almacenId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || almacenId == null) return;

    final almacenNombre = _warehouses
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (w) => (w?['id'] as num?)?.toInt() == almacenId,
          orElse: () => null,
        )?['denominacion']
        ?.toString();

    try {
      await _service.createTpvOffline(
        denominacion: nameCtrl.text,
        idAlmacen: almacenId!,
        almacenNombre: almacenNombre,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TPV creado (se sincronizará si está offline)'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editTpv(Map<String, dynamic> tpv) async {
    final id = (tpv['id'] as num?)?.toInt();
    if (id == null) return;
    final nameCtrl = TextEditingController(
      text: tpv['denominacion']?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar TPV'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Denominación',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.updateTpvOffline(
        idTpv: id,
        denominacion: nameCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('TPV actualizado'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _assignVendor(Map<String, dynamic> vendor) async {
    final vendorId = (vendor['id'] as num?)?.toInt();
    if (vendorId == null) return;
    final realTpvs =
        _tpvs.where((t) => ((t['id'] as num?)?.toInt() ?? -1) > 0).toList();
    if (realTpvs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay TPVs sincronizados para asignar')),
      );
      return;
    }
    int? tpvId = (vendor['id_tpv'] as num?)?.toInt() ??
        (realTpvs.first['id'] as num?)?.toInt();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            'Asignar TPV · ${vendor['nombres'] ?? ''} ${vendor['apellidos'] ?? ''}',
          ),
          content: DropdownButtonFormField<int>(
            value: tpvId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'TPV',
              border: OutlineInputBorder(),
            ),
            items: realTpvs
                .map(
                  (t) => DropdownMenuItem<int>(
                    value: (t['id'] as num?)?.toInt(),
                    child: Text(
                      t['denominacion']?.toString() ?? '#${t['id']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .where((i) => i.value != null)
                .toList(),
            onChanged: (v) => setLocal(() => tpvId = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || tpvId == null) return;

    final tpvNombre = realTpvs
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (t) => (t?['id'] as num?)?.toInt() == tpvId,
          orElse: () => null,
        )?['denominacion']
        ?.toString();

    try {
      await _service.assignVendorToTpvOffline(
        vendorId: vendorId,
        idTpv: tpvId!,
        tpvNombre: tpvNombre,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vendedor reasignado'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _toggleCustomize(Map<String, dynamic> vendor) async {
    final vendorId = (vendor['id'] as num?)?.toInt();
    if (vendorId == null) return;
    final current = vendor['permitir_customizar_precio_venta'] == true;
    try {
      await _service.updateVendorCustomizeFlagOffline(
        vendorId: vendorId,
        permitirCustomizar: !current,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TPVs y vendedores'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'TPVs'),
            Tab(text: 'Vendedores'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton(
              onPressed: _createTpv,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _load(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildTpvs(),
                      _buildVendors(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTpvs() {
    if (_tpvs.isEmpty) {
      return Center(
        child: Text(
          'Sin TPVs en cache. Sincroniza online.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
    return ListView.separated(
      itemCount: _tpvs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = _tpvs[i];
        final pending = t['pending_local'] == true;
        final id = (t['id'] as num?)?.toInt();
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue[50],
            child: Icon(Icons.point_of_sale, color: Colors.blue[700]),
          ),
          title: Text(t['denominacion']?.toString() ?? 'TPV'),
          subtitle: Text(
            [
              if (t['almacen'] != null) 'Almacén: ${t['almacen']}',
              if (id != null) 'ID $id',
              if (pending) 'pendiente sync',
            ].join(' · '),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _editTpv(t),
        );
      },
    );
  }

  Widget _buildVendors() {
    if (_vendors.isEmpty) {
      return Center(
        child: Text(
          'Sin vendedores en cache. Sincroniza online.',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }
    return ListView.separated(
      itemCount: _vendors.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final v = _vendors[i];
        final name =
            '${v['nombres'] ?? ''} ${v['apellidos'] ?? ''}'.trim();
        final canCustomize = v['permitir_customizar_precio_venta'] == true;
        final registered = v['registered_offline'] == true;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.teal[50],
            child: Icon(Icons.person, color: Colors.teal[700]),
          ),
          title: Text(name.isEmpty ? 'Vendedor #${v['id']}' : name),
          subtitle: Text(
            [
              v['tpv_nombre'] ?? 'Sin TPV',
              if (v['email'] != null && '${v['email']}'.isNotEmpty)
                v['email'],
              if (registered) 'offline OK',
              if (v['pending_local'] == true) 'pendiente sync',
            ].join(' · '),
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'assign') _assignVendor(v);
              if (action == 'toggle') _toggleCustomize(v);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'assign',
                child: Text('Asignar TPV'),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: Text(
                  canCustomize
                      ? 'Quitar permiso cambiar precio'
                      : 'Permitir cambiar precio',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
