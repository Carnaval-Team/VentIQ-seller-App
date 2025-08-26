import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_card.dart';
import '../services/warehouse_service.dart';
import '../models/warehouse.dart';

class WarehouseDetailScreen extends StatefulWidget {
  final String warehouseId;
  const WarehouseDetailScreen({super.key, required this.warehouseId});

  @override
  State<WarehouseDetailScreen> createState() => _WarehouseDetailScreenState();
}

class _WarehouseDetailScreenState extends State<WarehouseDetailScreen> {
  final _service = WarehouseService();
  Warehouse? _warehouse;
  bool _loading = true;
  String _sort = 'abc'; // abc | type | utilization

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _parentName(Warehouse w, WarehouseZone z) {
    if (z.parentId == null) return null;
    final idx = w.zones.indexWhere((e) => e.id == z.parentId);
    if (idx == -1) return null;
    return w.zones[idx].name;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final w = await _service.getWarehouseDetail(widget.warehouseId);
    setState(() {
      _warehouse = w;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Almacén'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.background,
      body: _loading || _warehouse == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(_warehouse!),
                    const SizedBox(height: 12),
                    _buildBasicInfo(_warehouse!),
                    const SizedBox(height: 12),
                    _buildLayouts(_warehouse!),
                    const SizedBox(height: 12),
                    _buildStockLimits(_warehouse!),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader(Warehouse w) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          w.name,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _onEditBasic(w),
              icon: const Icon(Icons.edit),
              label: const Text('Editar'),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildBasicInfo(Warehouse w) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AdminSectionHeader(
            title: 'Información básica',
            subtitle: 'Nombre, dirección y tipo',
          ),
          const SizedBox(height: 8),
          _kv('Nombre', w.name),
          _kv('Dirección', w.address),
          _kv('Tipo', w.type),
        ],
      ),
    );
  }

  Widget _buildLayouts(Warehouse w) {
    // sort zones based on selected criteria
    final zones = [...w.zones];
    zones.sort((a, b) {
      switch (_sort) {
        case 'type':
          return (a.type).compareTo(b.type);
        case 'utilization':
          return (b.utilization).compareTo(a.utilization);
        case 'abc':
        default:
          int rank(String? v) {
            switch (v) {
              case 'A':
                return 0;
              case 'B':
                return 1;
              case 'C':
                return 2;
              default:
                return 3;
            }
          }
          final r = rank(a.abc) - rank(b.abc);
          return r != 0 ? r : (a.name).compareTo(b.name);
      }
    });

    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: 'Layouts/Zonas',
            subtitle: 'Define zonas, clasificación ABC y condiciones',
            action: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Ordenar',
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'abc', child: Text('Ordenar por ABC')),
                    PopupMenuItem(value: 'type', child: Text('Ordenar por tipo')),
                    PopupMenuItem(value: 'utilization', child: Text('Ordenar por utilización')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Row(children: const [Icon(Icons.sort), SizedBox(width: 6), Text('Ordenar')]),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _onAddLayout(w),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar layout'),
                ),
              ],
            ),
          ),
          if (w.zones.isEmpty)
            const Text('Sin layouts aún', style: TextStyle(color: AppColors.textSecondary))
          else
            Column(
              children: zones
                  .map((z) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _zoneLeading(z),
                        title: Row(
                          children: [
                            Expanded(child: Text(z.name)),
                            const SizedBox(width: 8),
                            if (z.abc != null) _abcChip(z.abc!),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Código: ${z.code} • Tipo: ${z.type} • Capacidad: ${z.capacity}'
                                '${_parentName(w, z) != null ? ' • Padre: ${_parentName(w, z)}' : ''}'),
                            const SizedBox(height: 4),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _metricChip(Icons.inventory_2_outlined, '${z.productCount} prod.'),
                                _metricChip(Icons.storage, '${(z.utilization * 100).toStringAsFixed(0)}% ocupado'),
                                ..._conditionIcons(z),
                              ],
                            ),
                          ],
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Duplicar layout',
                              onPressed: () => _onDuplicateLayout(w, z.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              tooltip: 'Editar layout',
                              onPressed: () => _onEditLayout(w, z.id),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: z.productCount > 0 ? Colors.grey : null,
                              ),
                              tooltip: z.productCount > 0
                                  ? 'No se puede eliminar: contiene productos'
                                  : 'Eliminar layout',
                              onPressed: z.productCount > 0
                                  ? () => _showSnack('No se puede eliminar: contiene productos')
                                  : () => _onDeleteLayout(w, z.id),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _zoneLeading(WarehouseZone z) {
    return CircleAvatar(
      backgroundColor: Colors.blueGrey.shade50,
      child: const Icon(Icons.layers, color: AppColors.primary),
    );
  }

  Widget _abcChip(String abc) {
    Color c;
    switch (abc) {
      case 'A':
        c = Colors.green;
        break;
      case 'B':
        c = Colors.orange;
        break;
      case 'C':
      default:
        c = Colors.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text('ABC $abc', style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _metricChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [Icon(icon, size: 14), const SizedBox(width: 4), Text(text)]),
    );
  }

  List<Widget> _conditionIcons(WarehouseZone z) {
    final codes = z.conditionCodes.isNotEmpty
        ? z.conditionCodes
        : (z.conditions.isNotEmpty ? z.conditions.split(',').map((e) => e.trim()).toList() : <String>[]);
    Icon iconFor(String c) {
      switch (c.toLowerCase()) {
        case 'refrigerado':
          return const Icon(Icons.ac_unit, size: 16);
        case 'fragil':
          return const Icon(Icons.incomplete_circle, size: 16);
        case 'peligroso':
          return const Icon(Icons.warning_amber_rounded, size: 16);
        default:
          return const Icon(Icons.label_important_outline, size: 16);
      }
    }
    return codes.take(4).map((c) => Padding(padding: const EdgeInsets.only(right: 6), child: iconFor(c))).toList();
  }

  Widget _buildStockLimits(Warehouse w) {
    // Using zones placeholder to show limits section structure
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSectionHeader(
            title: 'Límites de stock',
            subtitle: 'Mínimos y máximos por producto',
            action: ElevatedButton.icon(
              onPressed: () => _onEditStockLimits(w),
              icon: const Icon(Icons.tune),
              label: const Text('Gestionar límites'),
            ),
          ),
          const Text(
            'Interfaz de gestión de límites por producto estará aquí (pendiente).',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(child: Text(v, style: const TextStyle(color: AppColors.textPrimary))),
        ],
      ),
    );
  }

  void _onEditBasic(Warehouse w) {
    _showSnack('Editar información básica (pendiente)');
  }

  void _onAddLayout(Warehouse w) {
    _openLayoutForm(w);
  }

  void _openLayoutForm(Warehouse w, {WarehouseZone? initial, bool isDuplicate = false}) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: initial != null ? (isDuplicate ? '${initial.name} (copia)' : initial.name) : '');
    final codeCtrl = TextEditingController(text: initial?.code ?? '');
    final capacityCtrl = TextEditingController(text: initial?.capacity.toString() ?? '');
    String type = initial?.type ?? 'almacenamiento';
    String? abc = initial?.abc ?? 'B';
    String? parentId = initial?.parentId;
    final List<String> allTypes = const ['recepcion', 'almacenamiento', 'picking', 'expedicion'];
    final List<String> allConditions = const ['refrigerado', 'fragil', 'peligroso'];
    final Set<String> selectedConds = {...(initial?.conditionCodes ?? <String>[])};
    // Unique code validation context
    final Set<String> takenCodes = {for (final z in w.zones) z.code};
    if (initial != null && !isDuplicate) {
      takenCodes.remove(initial.code);
    }
    if (isDuplicate && (initial?.code ?? '').isNotEmpty) {
      final base = initial!.code;
      var candidate = base;
      var i = 1;
      while (takenCodes.contains(candidate)) {
        candidate = '$base-$i';
        i++;
      }
      codeCtrl.text = candidate;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        initial == null
                            ? 'Nuevo layout'
                            : isDuplicate
                                ? 'Duplicar layout'
                                : 'Editar layout',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(labelText: 'Código', border: OutlineInputBorder()),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Requerido';
                          final code = v.trim();
                          if (takenCodes.contains(code)) return 'Código ya existe';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: type,
                        items: allTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (v) => setSheet(() => type = v ?? type),
                        decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: capacityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Capacidad', border: OutlineInputBorder()),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Requerido';
                          final n = int.tryParse(v);
                          if (n == null || n <= 0) return 'Debe ser un entero > 0';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        value: abc,
                        items: const [
                          DropdownMenuItem(value: 'A', child: Text('ABC A')),
                          DropdownMenuItem(value: 'B', child: Text('ABC B')),
                          DropdownMenuItem(value: 'C', child: Text('ABC C')),
                        ],
                        onChanged: (v) => setSheet(() => abc = v),
                        decoration: const InputDecoration(labelText: 'Clasificación ABC', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: const InputDecoration(labelText: 'Condiciones', border: OutlineInputBorder()),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: allConditions
                              .map((c) => FilterChip(
                                    label: Text(c),
                                    selected: selectedConds.contains(c),
                                    onSelected: (sel) => setSheet(() {
                                      if (sel) {
                                        selectedConds.add(c);
                                      } else {
                                        selectedConds.remove(c);
                                      }
                                    }),
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        value: parentId,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('Sin padre')),
                          ...w.zones.map((z) => DropdownMenuItem<String?>(value: z.id, child: Text(z.name)))
                        ],
                        onChanged: (v) => setSheet(() => parentId = v),
                        decoration: const InputDecoration(labelText: 'Layout padre (opcional)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              if (initial == null || isDuplicate) {
                                // Create or Duplicate -> create new layout
                                final newZone = WarehouseZone(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                                  warehouseId: w.id,
                                  name: nameCtrl.text.trim(),
                                  code: codeCtrl.text.trim(),
                                  type: type,
                                  conditions: selectedConds.join(','),
                                  capacity: int.parse(capacityCtrl.text.trim()),
                                  currentOccupancy: 0,
                                  locations: const [],
                                  abc: abc,
                                  conditionCodes: selectedConds.toList(),
                                  productCount: 0,
                                  utilization: 0.0,
                                  parentId: parentId,
                                );
                                await _service.addLayout(w.id, newZone.toJson());
                                setState(() {
                                  _warehouse = Warehouse(
                                    id: w.id,
                                    name: w.name,
                                    description: w.description,
                                    address: w.address,
                                    city: w.city,
                                    country: w.country,
                                    latitude: w.latitude,
                                    longitude: w.longitude,
                                    type: w.type,
                                    isActive: w.isActive,
                                    createdAt: w.createdAt,
                                    zones: [...w.zones, newZone],
                                  );
                                });
                                if (mounted) Navigator.of(ctx).pop();
                                _showSnack(isDuplicate ? 'Layout duplicado' : 'Layout creado');
                              } else {
                                // Edit
                                final updatedZone = WarehouseZone(
                                  id: initial.id,
                                  warehouseId: w.id,
                                  name: nameCtrl.text.trim(),
                                  code: codeCtrl.text.trim(),
                                  type: type,
                                  conditions: selectedConds.join(','),
                                  capacity: int.parse(capacityCtrl.text.trim()),
                                  currentOccupancy: initial.currentOccupancy,
                                  locations: initial.locations,
                                  abc: abc,
                                  conditionCodes: selectedConds.toList(),
                                  productCount: initial.productCount,
                                  utilization: initial.utilization,
                                  parentId: parentId,
                                );
                                await _service.updateLayout(w.id, initial.id, updatedZone.toJson());
                                setState(() {
                                  final newZones = w.zones.map((z) => z.id == updatedZone.id ? updatedZone : z).toList();
                                  _warehouse = Warehouse(
                                    id: w.id,
                                    name: w.name,
                                    description: w.description,
                                    address: w.address,
                                    city: w.city,
                                    country: w.country,
                                    latitude: w.latitude,
                                    longitude: w.longitude,
                                    type: w.type,
                                    isActive: w.isActive,
                                    createdAt: w.createdAt,
                                    zones: newZones,
                                  );
                                });
                                if (mounted) Navigator.of(ctx).pop();
                                _showSnack('Layout actualizado');
                              }
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('Guardar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _onEditLayout(Warehouse w, String layoutId) {
    final z = w.zones.firstWhere((e) => e.id == layoutId, orElse: () => w.zones.first);
    _openLayoutForm(w, initial: z);
  }

  void _onDuplicateLayout(Warehouse w, String layoutId) {
    final z = w.zones.firstWhere((e) => e.id == layoutId, orElse: () => w.zones.first);
    _openLayoutForm(w, initial: z, isDuplicate: true);
  }

  void _onDeleteLayout(Warehouse w, String layoutId) {
    _showSnack('Eliminar layout $layoutId (pendiente)');
  }

  void _onEditStockLimits(Warehouse w) {
    _showSnack('Gestionar límites de stock (pendiente)');
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
