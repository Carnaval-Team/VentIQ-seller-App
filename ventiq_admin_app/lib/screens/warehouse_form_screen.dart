import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/warehouse_service.dart';

class WarehouseFormScreen extends StatefulWidget {
  const WarehouseFormScreen({super.key});

  @override
  State<WarehouseFormScreen> createState() => _WarehouseFormScreenState();
}

class _WarehouseFormScreenState extends State<WarehouseFormScreen> {
  final _service = WarehouseService();

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  String _type = 'principal';

  // Layouts creados en el formulario
  final List<WarehouseZone> _zones = [];

  // Límites de stock (simple): sku/nombre y min/max
  final List<_StockLimitRow> _limits = [];

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo almacén'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.background,
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBasicInfo(),
              const SizedBox(height: 12),
              _buildLayoutsSection(),
              const SizedBox(height: 12),
              _buildStockLimitsSection(),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _onSave,
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                  label: const Text('Guardar almacén'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Información básica', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Dirección', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityCtrl,
                      decoration: const InputDecoration(labelText: 'Ciudad', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _countryCtrl,
                      decoration: const InputDecoration(labelText: 'País', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'principal', child: Text('Principal')),
                  DropdownMenuItem(value: 'secundario', child: Text('Secundario')),
                  DropdownMenuItem(value: 'temporal', child: Text('Temporal')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'principal'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayoutsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Gestión de layouts (con ABC)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ElevatedButton.icon(
                  onPressed: _onAddLayout,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar layout'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_zones.isEmpty)
              const Text('Sin layouts aún', style: TextStyle(color: AppColors.textSecondary))
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _zones.length,
                itemBuilder: (context, index) {
                  final z = _zones[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.layers)),
                    title: Row(
                      children: [
                        Expanded(child: Text(z.name)),
                        if (z.abc != null) _abcChip(z.abc!),
                      ],
                    ),
                    subtitle: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _chip(Icons.badge, 'Código ${z.code}') ,
                        _chip(Icons.category, z.type),
                        _chip(Icons.view_array, 'Cap ${z.capacity}') ,
                        if (z.parentId != null) _chip(Icons.account_tree, 'Padre ${_zones.firstWhere((e)=>e.id==z.parentId!, orElse: ()=>z).name}'),
                      ],
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(onPressed: () => _onEditLayout(index), icon: const Icon(Icons.edit)),
                        IconButton(onPressed: () => _onDuplicateLayout(index), icon: const Icon(Icons.copy)),
                        IconButton(onPressed: () => _onDeleteLayout(index), icon: const Icon(Icons.delete_outline)),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockLimitsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Límites de stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ElevatedButton.icon(
                  onPressed: _onAddLimit,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar límite'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_limits.isEmpty)
              const Text('Sin límites aún', style: TextStyle(color: AppColors.textSecondary))
            else
              Column(
                children: _limits
                    .asMap()
                    .entries
                    .map((entry) => _limitRow(entry.key, entry.value))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _limitRow(int index, _StockLimitRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: row.skuCtrl,
              decoration: const InputDecoration(labelText: 'SKU/Producto', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: row.minCtrl,
              decoration: const InputDecoration(labelText: 'Mín', border: OutlineInputBorder(), isDense: true),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: row.maxCtrl,
              decoration: const InputDecoration(labelText: 'Máx', border: OutlineInputBorder(), isDense: true),
              keyboardType: TextInputType.number,
            ),
          ),
          IconButton(onPressed: () => setState(() => _limits.removeAt(index)), icon: const Icon(Icons.delete_outline)),
        ],
      ),
    );
  }

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_saving) return;
    setState(() => _saving = true);

    final now = DateTime.now();
    final w = Warehouse(
      id: 'w_${now.millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      country: _countryCtrl.text.trim(),
      type: _type,
      createdAt: now,
      zones: _zones,
    );

    await _service.createWarehouse(w);

    // Enviar límites al servicio (stubbed)
    final limitsPayload = _limits
        .map((e) => {
              'sku': e.skuCtrl.text.trim(),
              'min': int.tryParse(e.minCtrl.text.trim()) ?? 0,
              'max': int.tryParse(e.maxCtrl.text.trim()) ?? 0,
            })
        .toList();
    await _service.updateStockLimits(w.id, limitsPayload);

    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Almacén creado')));
    }
  }

  void _onAddLayout() {
    _openLayoutForm();
  }

  void _onEditLayout(int index) {
    _openLayoutForm(initial: _zones[index]);
  }

  void _onDuplicateLayout(int index) {
    _openLayoutForm(initial: _zones[index], isDuplicate: true);
  }

  void _onDeleteLayout(int index) {
    setState(() => _zones.removeAt(index));
  }

  void _onAddLimit() {
    setState(() => _limits.add(_StockLimitRow()));
  }

  void _openLayoutForm({WarehouseZone? initial, bool isDuplicate = false}) {
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

    // Códigos tomados localmente en el formulario
    final Set<String> takenCodes = {for (final z in _zones) z.code};
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
                          ..._zones.map((z) => DropdownMenuItem<String?>(value: z.id, child: Text(z.name)))
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
                            onPressed: () {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              if (initial == null || isDuplicate) {
                                final newZone = WarehouseZone(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                                  warehouseId: 'temp',
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
                                setState(() => _zones.add(newZone));
                              } else {
                                final idx = _zones.indexWhere((e) => e.id == initial.id);
                                if (idx != -1) {
                                  _zones[idx] = WarehouseZone(
                                    id: initial.id,
                                    warehouseId: 'temp',
                                    name: nameCtrl.text.trim(),
                                    code: codeCtrl.text.trim(),
                                    type: type,
                                    conditions: selectedConds.join(','),
                                    capacity: int.parse(capacityCtrl.text.trim()),
                                    currentOccupancy: _zones[idx].currentOccupancy,
                                    locations: _zones[idx].locations,
                                    abc: abc,
                                    conditionCodes: selectedConds.toList(),
                                    productCount: _zones[idx].productCount,
                                    utilization: _zones[idx].utilization,
                                    parentId: parentId,
                                  );
                                  setState(() {});
                                }
                              }
                              Navigator.of(ctx).pop();
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

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [Icon(icon, size: 14), const SizedBox(width: 4), Text(text)]),
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
}

class _StockLimitRow {
  final TextEditingController skuCtrl = TextEditingController();
  final TextEditingController minCtrl = TextEditingController();
  final TextEditingController maxCtrl = TextEditingController();
}
