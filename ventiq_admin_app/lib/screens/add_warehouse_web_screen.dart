import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/warehouse_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/admin_drawer.dart';

class AddWarehouseWebScreen extends StatefulWidget {
  final Warehouse? initialWarehouse;

  const AddWarehouseWebScreen({Key? key, this.initialWarehouse})
      : super(key: key);

  @override
  State<AddWarehouseWebScreen> createState() => _AddWarehouseWebScreenState();
}

class _AddWarehouseWebScreenState extends State<AddWarehouseWebScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Controladores de texto
  final _denominacionController = TextEditingController();
  final _direccionController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _tiendaController = TextEditingController();

  // Variables de estado
  bool _isLoading = false;
  bool _isLoadingData = true;

  String _selectedWarehouseType = 'principal';

  // Datos para dropdowns
  List<Map<String, dynamic>> _tiposLayout = [];
  List<Map<String, dynamic>> _condiciones = [];
  List<Map<String, dynamic>> _productos = [];

  // ID de tienda del usuario (desde preferencias)
  int? _tiendaId;
  List<int> _selectedCondiciones = [];

  // Listas dinámicas para layouts y límites de stock
  List<Map<String, dynamic>> _layouts = [];
  List<Map<String, dynamic>> _limitesStock = [];

  final _warehouseService = WarehouseService();
  final _prefsService = UserPreferencesService();

  bool get _isEdit => widget.initialWarehouse != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final warehouse = widget.initialWarehouse!;
      _denominacionController.text =
          warehouse.denominacion.isNotEmpty
              ? warehouse.denominacion
              : warehouse.name;
      _direccionController.text =
          warehouse.direccion.isNotEmpty
              ? warehouse.direccion
              : warehouse.address;
      _ubicacionController.text = warehouse.ubicacion ?? warehouse.city;
      _selectedWarehouseType =
          warehouse.type.isNotEmpty ? warehouse.type : 'principal';
      _tiendaController.text = warehouse.tienda?.denominacion ?? '';
      _isLoadingData = false;
    } else {
      _loadInitialData();
    }
  }

  @override
  void dispose() {
    _denominacionController.dispose();
    _direccionController.dispose();
    _ubicacionController.dispose();
    _tiendaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() => _isLoadingData = true);

      final idTienda = await _prefsService.getIdTienda();
      if (idTienda == null) {
        throw Exception(
          'No se encontró ID de tienda en preferencias del usuario',
        );
      }

      final storeInfo = await _prefsService.getCurrentStoreInfo();
      final storeName =
          storeInfo?['denominacion']?.toString() ?? 'Tienda seleccionada';

      final futures = await Future.wait([
        _warehouseService.getTiposLayout(),
        _warehouseService.getCondiciones(),
        _warehouseService.getProductos(),
      ]);

      setState(() {
        _tiendaId = idTienda;
        _tiposLayout = List<Map<String, dynamic>>.from(futures[0]);
        _condiciones = List<Map<String, dynamic>>.from(futures[1]);
        _productos = List<Map<String, dynamic>>.from(futures[2]);
        _isLoadingData = false;
      });
      _tiendaController.text = storeName;
    } catch (e) {
      setState(() => _isLoadingData = false);
      _showErrorSnackBar('Error al cargar datos iniciales: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Editar Almacén' : 'Nuevo Almacén',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveWarehouse,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : Icon(
                      _isEdit ? Icons.save_outlined : Icons.check_rounded,
                      size: 18,
                    ),
              label: Text(
                _isLoading
                    ? 'Guardando...'
                    : (_isEdit ? 'Actualizar' : 'Guardar'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.white70,
                disabledForegroundColor: AppColors.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
        ],
      ),
      endDrawer: const AdminDrawer(),
      body: _isLoadingData
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text(
                    'Cargando datos del almacén...',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildWebCard(
                          title: 'Información Básica',
                          subtitle: 'Datos principales del almacén',
                          icon: Icons.warehouse_outlined,
                          child: _buildBasicInfoContent(),
                        ),
                        if (!_isEdit) ...[
                          const SizedBox(height: 20),
                          _buildWebCard(
                            title: 'Layouts del Almacén',
                            subtitle:
                                'Estructura interna y zonas de almacenamiento',
                            icon: Icons.view_module_outlined,
                            iconColor: AppColors.info,
                            trailing: _buildActionIconButton(
                              icon: Icons.add_rounded,
                              label: 'Agregar',
                              onPressed: _addLayout,
                            ),
                            child: _buildLayoutsContent(),
                          ),
                          const SizedBox(height: 20),
                          _buildWebCard(
                            title: 'Condiciones del Almacén',
                            subtitle:
                                'Características ambientales y operativas',
                            icon: Icons.science_outlined,
                            iconColor: AppColors.warning,
                            child: _buildConditionsContent(),
                          ),
                          const SizedBox(height: 20),
                          _buildWebCard(
                            title: 'Límites de Stock',
                            subtitle:
                                'Mínimos, máximos y puntos de reorden por producto',
                            icon: Icons.inventory_2_outlined,
                            iconColor: AppColors.success,
                            trailing: _buildActionIconButton(
                              icon: Icons.add_rounded,
                              label: 'Agregar',
                              onPressed: _addStockLimit,
                            ),
                            child: _buildStockLimitsContent(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // =====================================================
  // HELPERS DE DISEÑO CONSISTENTE
  // =====================================================

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    String? helperText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      labelStyle: TextStyle(
        fontSize: 14,
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      helperStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  Widget _buildActionIconButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        backgroundColor: AppColors.primary.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildWebCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
    Color? iconColor,
    Widget? trailing,
  }) {
    final Color accentColor = iconColor ?? AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 20),
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          Container(height: 1, color: Colors.grey.shade100),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SECCIONES DE CONTENIDO
  // =====================================================

  Widget _buildBasicInfoContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _denominacionController,
          decoration: _inputDecoration(
            label: 'Denominación del Almacén *',
            hint: 'Ej. Almacén Central',
            prefixIcon: const Icon(Icons.warehouse_outlined, size: 20),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Por favor ingrese la denominación';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _direccionController,
          decoration: _inputDecoration(
            label: 'Dirección *',
            hint: 'Calle, número, ciudad',
            prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Por favor ingrese la dirección';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _ubicacionController,
          decoration: _inputDecoration(
            label: 'Ubicación',
            hint: 'Referencia adicional',
            prefixIcon: const Icon(Icons.place_outlined, size: 20),
          ),
        ),
        if (_isEdit) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedWarehouseType,
            decoration: _inputDecoration(
              label: 'Tipo',
              prefixIcon: const Icon(Icons.category_outlined, size: 20),
            ),
            items: const [
              DropdownMenuItem(value: 'principal', child: Text('Principal')),
              DropdownMenuItem(value: 'secundario', child: Text('Secundario')),
              DropdownMenuItem(value: 'temporal', child: Text('Temporal')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedWarehouseType = value);
            },
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          enabled: false,
          controller: _tiendaController,
          decoration: _inputDecoration(
            label: 'Tienda',
            hint: _tiendaController.text.isEmpty
                ? 'Se usará la tienda asignada al usuario'
                : null,
            prefixIcon: const Icon(Icons.store_outlined, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutsContent() {
    if (_layouts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.view_module_outlined,
        title: 'Sin layouts agregados',
        message:
            'Agrega zonas, pasillos o estanterías para organizar el almacén.',
      );
    }
    return Column(
      children: List.generate(_layouts.length, (index) {
        final layout = _layouts[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == _layouts.length - 1 ? 0 : 10),
          child: _buildItemTile(
            icon: Icons.view_module_outlined,
            iconColor: AppColors.info,
            title: layout['denominacion'] ?? '',
            subtitle: 'Tipo: ${layout['tipo_layout_nombre'] ?? ''}',
            onDelete: () => _removeLayout(index),
          ),
        );
      }),
    );
  }

  Widget _buildConditionsContent() {
    if (_condiciones.isEmpty) {
      return _buildEmptyState(
        icon: Icons.science_outlined,
        title: 'Sin condiciones disponibles',
        message: 'No hay condiciones registradas en el sistema.',
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _condiciones.map((condicion) {
        final isSelected = _selectedCondiciones.contains(condicion['id']);
        return FilterChip(
          label: Text(condicion['denominacion']),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedCondiciones.add(condicion['id']);
              } else {
                _selectedCondiciones.remove(condicion['id']);
              }
            });
          },
          selectedColor: AppColors.primary.withOpacity(0.15),
          checkmarkColor: AppColors.primary,
          backgroundColor: const Color(0xFFF9FAFB),
          side: BorderSide(
            color: isSelected
                ? AppColors.primary.withOpacity(0.5)
                : Colors.grey.shade300,
          ),
          labelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? AppColors.primary : AppColors.textPrimary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStockLimitsContent() {
    if (_limitesStock.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Sin límites configurados',
        message:
            'Define stock mínimo, máximo y punto de reorden por producto.',
      );
    }
    return Column(
      children: List.generate(_limitesStock.length, (index) {
        final limite = _limitesStock[index];
        return Padding(
          padding: EdgeInsets.only(
              bottom: index == _limitesStock.length - 1 ? 0 : 10),
          child: _buildItemTile(
            icon: Icons.inventory_2_outlined,
            iconColor: AppColors.success,
            title: limite['producto_nombre'] ?? '',
            subtitle:
                'Min: ${limite['stock_min']}  ·  Max: ${limite['stock_max']}  ·  Ordenar: ${limite['stock_ordenar']}',
            onDelete: () => _removeStockLimit(index),
          ),
        );
      }),
    );
  }

  Widget _buildItemTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onDelete,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.error),
            onPressed: onDelete,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  // =====================================================
  // ACCIONES
  // =====================================================

  void _addLayout() {
    showDialog(
      context: context,
      builder: (context) => _LayoutDialog(
        tiposLayout: _tiposLayout,
        onSave: (layout) {
          setState(() {
            _layouts.add(layout);
          });
        },
      ),
    );
  }

  void _removeLayout(int index) {
    setState(() {
      _layouts.removeAt(index);
    });
  }

  void _addStockLimit() {
    showDialog(
      context: context,
      builder: (context) => _StockLimitDialog(
        productos: _productos,
        onSave: (limite) {
          setState(() {
            _limitesStock.add(limite);
          });
        },
      ),
    );
  }

  void _removeStockLimit(int index) {
    setState(() {
      _limitesStock.removeAt(index);
    });
  }

  Future<void> _saveWarehouse() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isEdit) {
        await _warehouseService
            .updateWarehouseBasic(widget.initialWarehouse!.id, {
          'denominacion': _denominacionController.text.trim(),
          'direccion': _direccionController.text.trim(),
          'ubicacion': _ubicacionController.text.trim(),
          'tipo': _selectedWarehouseType,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Almacén actualizado exitosamente'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.of(context).pop(true);
        }
        return;
      }

      final layoutsData = _layouts
          .map(
            (layout) => {
              'id_tipo_layout': layout['id_tipo_layout'],
              'id_layout_padre': layout['id_layout_padre'],
              'denominacion': layout['denominacion'],
              'sku_codigo': layout['sku_codigo'],
              'clasificacion_abc': layout['clasificacion_abc'],
              'fecha_desde': layout['fecha_desde'],
              'fecha_hasta': layout['fecha_hasta'],
            },
          )
          .toList();

      final limitesStockData = _limitesStock
          .map(
            (limite) => {
              'id_producto': limite['id_producto'],
              'stock_min': limite['stock_min'],
              'stock_max': limite['stock_max'],
              'stock_ordenar': limite['stock_ordenar'],
            },
          )
          .toList();

      final response = await _warehouseService.createWarehouse(
        denominacionAlmacen: _denominacionController.text,
        direccionAlmacen: _direccionController.text,
        ubicacionAlmacen: _ubicacionController.text,
        idTiendaParam: _tiendaId!,
        condicionesData:
            _selectedCondiciones.isNotEmpty ? _selectedCondiciones : null,
        layoutsData: layoutsData.isNotEmpty ? layoutsData : null,
        limitesStockData: limitesStockData.isNotEmpty ? limitesStockData : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Almacén creado exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
          _isEdit
              ? 'Error al actualizar almacén: $e'
              : 'Error al crear almacén: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}

// =====================================================
// DIALOG: Agregar Layout
// =====================================================

class _LayoutDialog extends StatefulWidget {
  final List<Map<String, dynamic>> tiposLayout;
  final Function(Map<String, dynamic>) onSave;

  const _LayoutDialog({required this.tiposLayout, required this.onSave});

  @override
  State<_LayoutDialog> createState() => _LayoutDialogState();
}

class _LayoutDialogState extends State<_LayoutDialog> {
  final _denominacionController = TextEditingController();
  final _skuController = TextEditingController();
  int? _selectedTipoLayout;
  int? _selectedLayoutPadre;
  int? _clasificacionAbc;

  @override
  void dispose() {
    _denominacionController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      labelStyle: TextStyle(
        fontSize: 14,
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.view_module_outlined,
                      color: AppColors.info,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Agregar Layout',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Define una zona del almacén',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            Container(height: 1, color: Colors.grey.shade100),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _denominacionController,
                      decoration: _decoration(
                        'Denominación *',
                        hint: 'Ej. Pasillo A',
                        icon: Icons.label_outline_rounded,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      value: _selectedTipoLayout,
                      isExpanded: true,
                      decoration: _decoration(
                        'Tipo de Layout *',
                        icon: Icons.category_outlined,
                      ),
                      items: widget.tiposLayout
                          .map(
                            (tipo) => DropdownMenuItem<int>(
                              value: tipo['id'],
                              child: Text(tipo['denominacion']),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _selectedTipoLayout = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _skuController,
                      decoration: _decoration(
                        'SKU Código',
                        hint: 'Opcional',
                        icon: Icons.qr_code_2_outlined,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      value: _clasificacionAbc,
                      isExpanded: true,
                      decoration: _decoration(
                        'Clasificación ABC',
                        icon: Icons.tune_outlined,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 1, child: Text('A - Alta rotación')),
                        DropdownMenuItem(
                            value: 2, child: Text('B - Media rotación')),
                        DropdownMenuItem(
                            value: 3, child: Text('C - Baja rotación')),
                      ],
                      onChanged: (value) {
                        setState(() => _clasificacionAbc = value);
                      },
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: Colors.grey.shade100),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saveLayout,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Guardar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
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

  void _saveLayout() {
    if (_denominacionController.text.trim().isEmpty ||
        _selectedTipoLayout == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa los campos requeridos'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final tipoLayoutNombre = widget.tiposLayout.firstWhere(
      (tipo) => tipo['id'] == _selectedTipoLayout,
    )['denominacion'];

    widget.onSave({
      'id_tipo_layout': _selectedTipoLayout,
      'id_layout_padre': _selectedLayoutPadre,
      'denominacion': _denominacionController.text.trim(),
      'sku_codigo': _skuController.text.trim().isNotEmpty
          ? _skuController.text.trim()
          : null,
      'clasificacion_abc': _clasificacionAbc,
      'fecha_desde': DateTime.now().toIso8601String(),
      'fecha_hasta': null,
      'tipo_layout_nombre': tipoLayoutNombre,
    });

    Navigator.of(context).pop();
  }
}

// =====================================================
// DIALOG: Agregar Límite de Stock
// =====================================================

class _StockLimitDialog extends StatefulWidget {
  final List<Map<String, dynamic>> productos;
  final Function(Map<String, dynamic>) onSave;

  const _StockLimitDialog({required this.productos, required this.onSave});

  @override
  State<_StockLimitDialog> createState() => _StockLimitDialogState();
}

class _StockLimitDialogState extends State<_StockLimitDialog> {
  final _stockMinController = TextEditingController();
  final _stockMaxController = TextEditingController();
  final _stockOrdenarController = TextEditingController();
  int? _selectedProducto;

  @override
  void dispose() {
    _stockMinController.dispose();
    _stockMaxController.dispose();
    _stockOrdenarController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      labelStyle: TextStyle(
        fontSize: 14,
        color: Colors.grey.shade700,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.success,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Agregar Límite de Stock',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Define mínimo, máximo y reorden',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            Container(height: 1, color: Colors.grey.shade100),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: _selectedProducto,
                      isExpanded: true,
                      decoration: _decoration(
                        'Producto *',
                        icon: Icons.shopping_bag_outlined,
                      ),
                      items: widget.productos
                          .map(
                            (producto) => DropdownMenuItem<int>(
                              value: producto['id'],
                              child: Text(
                                producto['denominacion'],
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _selectedProducto = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _stockMinController,
                            decoration: _decoration(
                              'Mínimo *',
                              hint: '0',
                              icon: Icons.south_rounded,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _stockMaxController,
                            decoration: _decoration(
                              'Máximo *',
                              hint: '0',
                              icon: Icons.north_rounded,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _stockOrdenarController,
                      decoration: _decoration(
                        'Stock a Ordenar *',
                        hint: '0',
                        icon: Icons.refresh_rounded,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _saveStockLimit,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Guardar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
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

  void _saveStockLimit() {
    if (_selectedProducto == null ||
        _stockMinController.text.trim().isEmpty ||
        _stockMaxController.text.trim().isEmpty ||
        _stockOrdenarController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa los campos requeridos'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final productoNombre = widget.productos.firstWhere(
      (producto) => producto['id'] == _selectedProducto,
    )['denominacion'];

    widget.onSave({
      'id_producto': _selectedProducto,
      'stock_min': double.tryParse(_stockMinController.text.trim()) ?? 0,
      'stock_max': double.tryParse(_stockMaxController.text.trim()) ?? 0,
      'stock_ordenar':
          double.tryParse(_stockOrdenarController.text.trim()) ?? 0,
      'producto_nombre': productoNombre,
    });

    Navigator.of(context).pop();
  }
}
