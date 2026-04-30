import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/warehouse_service.dart';
import '../services/inventory_service.dart';
import '../services/export_service.dart';
import '../services/user_preferences_service.dart';

class InventoryExportDialogWeb extends StatefulWidget {
  const InventoryExportDialogWeb({super.key});

  @override
  State<InventoryExportDialogWeb> createState() =>
      _InventoryExportDialogWebState();
}

class _InventoryExportDialogWebState extends State<InventoryExportDialogWeb> {
  final WarehouseService _warehouseService = WarehouseService();
  final ExportService _exportService = ExportService();
  final UserPreferencesService _prefsService = UserPreferencesService();

  bool _isLoading = false;
  bool _isExporting = false;
  String _selectedExportMethod = 'pdf';
  int? _selectedWarehouseId;
  String _selectedWarehouseName = 'Todos los almacenes';
  DateTime? _selectedDate;
  DateTime? _selectedDateTo;
  List<Warehouse> _warehouses = [];
  String? _error;

  bool _includeSku = true;
  bool _includeNombreCorto = false;
  bool _includeMarca = false;
  bool _includeDescripcionCorta = false;
  bool _includeDescripcion = false;
  bool _includeZeroStock = false;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final warehouses = await _warehouseService.listWarehouses();
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error al cargar almacenes: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          (isFrom ? _selectedDate : _selectedDateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _selectedDate = picked;
      } else {
        _selectedDateTo = picked;
      }
    });
  }

  Future<void> _exportInventory() async {
    setState(() => _isExporting = true);
    try {
      final storeId = await _prefsService.getIdTienda();
      if (storeId == null) {
        throw Exception('No se encontró el ID de tienda del usuario');
      }

      final inventoryData = await InventoryService.getInventarioSimple(
        idAlmacen: _selectedWarehouseId,
        idTienda: storeId,
        fechaDesde: _selectedDate,
        fechaHasta: _selectedDateTo,
        includeZero: _includeZeroStock,
      );

      if (inventoryData.isEmpty) {
        throw Exception('No se encontraron datos de inventario para exportar');
      }

      await _exportService.exportInventorySimple(
        context: context,
        inventoryData: inventoryData,
        warehouseName: _selectedWarehouseName,
        filterDateFrom: _selectedDate,
        filterDateTo: _selectedDateTo,
        format: _selectedExportMethod == 'excel' ? 'excel' : 'pdf',
        includeSku: _includeSku,
        includeNombreCorto: _includeNombreCorto,
        includeMarca: _includeMarca,
        includeDescripcionCorta: _includeDescripcionCorta,
        includeDescripcion: _includeDescripcion,
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al exportar: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final isWide = screenW >= 880;
    final dialogW = isWide ? 900.0 : screenW * 0.94;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogW,
          maxHeight: screenH * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: AppColors.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: isWide ? _buildWideBody() : _buildNarrowBody(),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E3A8A),
            AppColors.primary,
            const Color(0xFF3B82F6),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.22)),
            ),
            child: const Icon(
              Icons.file_download_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Exportar Inventario',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Genera un reporte de inventario en PDF o Excel',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _isExporting ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'Cerrar',
          ),
        ],
      ),
    );
  }

  Widget _buildWideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMethodSection(),
              const SizedBox(height: 22),
              _buildWarehouseSection(),
              const SizedBox(height: 22),
              _buildDateSection(),
            ],
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildColumnsSection(),
              const SizedBox(height: 18),
              _buildFilterSection(),
              const SizedBox(height: 18),
              _buildInfoBanner(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMethodSection(),
        const SizedBox(height: 20),
        _buildWarehouseSection(),
        const SizedBox(height: 20),
        _buildDateSection(),
        const SizedBox(height: 20),
        _buildColumnsSection(),
        const SizedBox(height: 16),
        _buildFilterSection(),
        const SizedBox(height: 16),
        _buildInfoBanner(),
      ],
    );
  }

  Widget _buildSectionTitle(IconData icon, String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.2,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          Icons.style_rounded,
          'Método de exportación',
          subtitle: 'Elige el formato del archivo',
        ),
        Row(
          children: [
            Expanded(
              child: _MethodCard(
                icon: Icons.picture_as_pdf_rounded,
                label: 'PDF',
                description: 'Documento portable',
                color: const Color(0xFFEF4444),
                selected: _selectedExportMethod == 'pdf',
                onTap: () =>
                    setState(() => _selectedExportMethod = 'pdf'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MethodCard(
                icon: Icons.table_chart_rounded,
                label: 'Excel',
                description: 'Hoja de cálculo',
                color: const Color(0xFF10B981),
                selected: _selectedExportMethod == 'excel',
                onTap: () =>
                    setState(() => _selectedExportMethod = 'excel'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWarehouseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          Icons.warehouse_rounded,
          'Almacén',
          subtitle: 'Filtra por uno o todos los almacenes',
        ),
        if (_isLoading)
          Container(
            height: 56,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _selectedWarehouseId,
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded,
                    color: AppColors.textLight),
                hint: const Text(
                  'Seleccionar almacén',
                  style: TextStyle(fontSize: 13.5),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Row(
                      children: [
                        Icon(Icons.all_inclusive_rounded,
                            color: AppColors.textSecondary, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Todos los almacenes',
                          style: TextStyle(fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
                  ..._warehouses.map(
                    (w) => DropdownMenuItem<int?>(
                      value: int.parse(w.id),
                      child: Row(
                        children: [
                          const Icon(Icons.warehouse_rounded,
                              color: Color(0xFF4A90E2), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              w.name,
                              style: const TextStyle(fontSize: 13.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedWarehouseId = value;
                    _selectedWarehouseName = value == null
                        ? 'Todos los almacenes'
                        : _warehouses
                            .firstWhere((w) => int.parse(w.id) == value)
                            .name;
                  });
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          Icons.event_rounded,
          'Rango de fechas',
          subtitle: 'Opcional — deja vacío para incluir todo',
        ),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Desde',
                value: _selectedDate,
                onTap: () => _selectDate(isFrom: true),
                onClear: () => setState(() => _selectedDate = null),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DateField(
                label: 'Hasta',
                value: _selectedDateTo,
                onTap: () => _selectDate(isFrom: false),
                onClear: () => setState(() => _selectedDateTo = null),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColumnsSection() {
    final items = [
      ('SKU', 'Código SKU del producto', _includeSku, (bool v) {
        setState(() => _includeSku = v);
      }),
      (
        'Nombre corto',
        'Denominación corta del producto',
        _includeNombreCorto,
        (bool v) {
          setState(() => _includeNombreCorto = v);
        }
      ),
      ('Marca', 'Nombre comercial / marca', _includeMarca, (bool v) {
        setState(() => _includeMarca = v);
      }),
      (
        'Descripción corta',
        'Descripción corta del producto',
        _includeDescripcionCorta,
        (bool v) {
          setState(() => _includeDescripcionCorta = v);
        }
      ),
      (
        'Descripción',
        'Descripción completa del producto',
        _includeDescripcion,
        (bool v) {
          setState(() => _includeDescripcion = v);
        }
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            Icons.view_column_rounded,
            'Columnas adicionales',
            subtitle: 'Activa las columnas que quieres incluir',
          ),
          ...items.map(
            (it) => _CheckRow(
              title: it.$1,
              subtitle: it.$2,
              value: it.$3,
              onChanged: it.$4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            Icons.filter_alt_rounded,
            'Opciones de filtrado',
            subtitle: 'Controla qué productos se incluyen',
          ),
          _CheckRow(
            title: 'Incluir productos con stock cero',
            subtitle:
                'Mostrar productos sin stock pero con registro en inventario',
            value: _includeZeroStock,
            onChanged: (v) => setState(() => _includeZeroStock = v),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.info.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.info, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'El reporte siempre incluye nombre del producto, stock disponible, cantidad inicial, cantidad final, precio de venta y presentación.',
              style: TextStyle(
                color: AppColors.info.withOpacity(0.95),
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          if (_selectedWarehouseId != null || _selectedDate != null ||
              _selectedDateTo != null)
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (_selectedWarehouseId != null)
                    _summaryChip(
                      icon: Icons.warehouse_rounded,
                      label: _selectedWarehouseName,
                      color: const Color(0xFF4A90E2),
                    ),
                  if (_selectedDate != null)
                    _summaryChip(
                      icon: Icons.event_rounded,
                      label:
                          'Desde ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                      color: const Color(0xFF8B5CF6),
                    ),
                  if (_selectedDateTo != null)
                    _summaryChip(
                      icon: Icons.event_available_rounded,
                      label:
                          'Hasta ${_selectedDateTo!.day}/${_selectedDateTo!.month}/${_selectedDateTo!.year}',
                      color: const Color(0xFF8B5CF6),
                    ),
                ],
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          TextButton(
            onPressed:
                _isExporting ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isExporting ? null : _exportInventory,
            icon: _isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.file_download_rounded, size: 18),
            label: Text(_isExporting ? 'Exportando...' : 'Exportar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 14,
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                letterSpacing: 0.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _MethodCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withOpacity(0.14),
                    color.withOpacity(0.06),
                  ],
                )
              : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: selected ? color : AppColors.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? color : AppColors.border,
                  width: 1.4,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasValue ? AppColors.primary.withOpacity(0.4) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              color: hasValue ? AppColors.primary : AppColors.textSecondary,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    hasValue
                        ? '${value!.day}/${value!.month}/${value!.year}'
                        : 'Sin fecha',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: hasValue
                          ? AppColors.textPrimary
                          : AppColors.textLight,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (hasValue)
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: value ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: value ? AppColors.primary : AppColors.border,
                  width: 1.4,
                ),
              ),
              child: value
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showInventoryExportDialogWeb(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const InventoryExportDialogWeb(),
  );
}
