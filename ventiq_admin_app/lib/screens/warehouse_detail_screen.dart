import 'package:flutter/material.dart';
import '../config/app_colors.dart';
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.warehouse,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        w.address,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _onEditBasic(w),
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            tooltip: 'Editar información básica',
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo(Warehouse w) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.info_outline,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Información básica',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Nombre, dirección y tipo',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _modernKv('Nombre', w.name, Icons.warehouse),
            _modernKv('Dirección', w.address, Icons.location_on),
            _modernKv('Tipo', w.type, Icons.category),
          ],
        ),
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

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.layers,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Layouts/Zonas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Define zonas, clasificación ABC y condiciones',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Ordenar',
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(value: 'abc', child: Text('Ordenar por ABC')),
                        PopupMenuItem(value: 'type', child: Text('Ordenar por tipo')),
                        PopupMenuItem(value: 'utilization', child: Text('Ordenar por utilización')),
                      ],
                      child: const Icon(Icons.sort, color: AppColors.textSecondary),
                    ),
                    IconButton(
                      onPressed: () => _onAddLayout(w),
                      icon: const Icon(Icons.add, color: AppColors.primary),
                      tooltip: 'Agregar layout',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (w.zones.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Sin layouts aún',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              Column(
                children: zones.map((z) => _buildZoneCard(w, z)).toList(),
              ),
          ],
        ),
      ),
    );
  }


  Widget _abcChip(String abc) {
    Color color;
    switch (abc) {
      case 'A':
        color = Colors.red;
        break;
      case 'B':
        color = Colors.orange;
        break;
      case 'C':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        abc,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _metricChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _conditionIcons(WarehouseZone z) {
    if (z.conditions.isEmpty) return [];
    
    // Split conditions by comma if multiple, otherwise use single condition
    final codes = z.conditions.contains(',') 
        ? z.conditions.split(',').map((e) => e.trim()).toList()
        : [z.conditions];
    
    Widget iconFor(String code) {
      switch (code.toLowerCase()) {
        case 'refrigerado':
          return const Icon(Icons.ac_unit, size: 14, color: Colors.blue);
        case 'fragil':
          return const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange);
        case 'peligroso':
          return const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red);
        default:
          return const Icon(Icons.label_important_outline, size: 14, color: Colors.grey);
      }
    }
    
    final limitedCodes = codes.length > 4 ? codes.sublist(0, 4) : codes;
    return limitedCodes.map((c) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: iconFor(c),
    )).toList();
  }

  Widget _buildZoneCard(Warehouse w, WarehouseZone z) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.layers,
                    color: AppColors.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              z.name,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (z.abc != null) _abcChip(z.abc!),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Código: ${z.code} • Tipo: ${z.type} • Capacidad: ${z.capacity}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _metricChip(Icons.inventory_2_outlined, '${z.productCount} prod.'),
                const SizedBox(width: 8),
                _metricChip(Icons.storage, '${(z.utilization * 100).toStringAsFixed(0)}% ocupado'),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: 'Duplicar layout',
                      onPressed: () => _onDuplicateLayout(w, z.id),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Editar layout',
                      onPressed: () => _onEditLayout(w, z.id),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: z.productCount > 0 ? Colors.grey : Colors.red,
                      ),
                      tooltip: z.productCount > 0
                          ? 'No se puede eliminar: contiene productos'
                          : 'Eliminar layout',
                      onPressed: z.productCount > 0
                          ? () => _showSnack('No se puede eliminar: contiene productos')
                          : () => _onDeleteLayout(w, z.id),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ],
            ),
            if (z.conditions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: _conditionIcons(z),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockLimits(Warehouse w) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Límites de stock',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Mínimos y máximos por producto',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _onEditStockLimits(w),
                  icon: const Icon(Icons.tune, color: AppColors.primary),
                  tooltip: 'Gestionar límites',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Interfaz de gestión de límites por producto estará aquí (pendiente).',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modernKv(String key, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              key,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
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
                                    denominacion: w.denominacion,
                                    direccion: w.direccion,
                                    ubicacion: w.ubicacion,
                                    tienda: w.tienda,
                                    roles: w.roles,
                                    layouts: w.layouts,
                                    condiciones: w.condiciones,
                                    almacenerosCount: w.almacenerosCount,
                                    limitesStockCount: w.limitesStockCount,
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
                                    denominacion: w.denominacion,
                                    direccion: w.direccion,
                                    ubicacion: w.ubicacion,
                                    tienda: w.tienda,
                                    roles: w.roles,
                                    layouts: w.layouts,
                                    condiciones: w.condiciones,
                                    almacenerosCount: w.almacenerosCount,
                                    limitesStockCount: w.limitesStockCount,
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
