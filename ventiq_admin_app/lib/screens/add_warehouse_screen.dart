import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/warehouse_service.dart';
import '../services/user_preferences_service.dart';

class AddWarehouseScreen extends StatefulWidget {
  const AddWarehouseScreen({Key? key}) : super(key: key);

  @override
  State<AddWarehouseScreen> createState() => _AddWarehouseScreenState();
}

class _AddWarehouseScreenState extends State<AddWarehouseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  
  // Controladores de texto
  final _denominacionController = TextEditingController();
  final _direccionController = TextEditingController();
  final _ubicacionController = TextEditingController();
  
  // Variables de estado
  bool _isLoading = false;
  bool _isLoadingData = true;
  
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

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }
  
  @override
  void dispose() {
    _denominacionController.dispose();
    _direccionController.dispose();
    _ubicacionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() => _isLoadingData = true);
      
      // Obtener tienda del usuario desde preferencias
      final idTienda = await _prefsService.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en preferencias del usuario');
      }
      
      // Cargar datos iniciales en paralelo
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
      
    } catch (e) {
      setState(() => _isLoadingData = false);
      _showErrorSnackBar('Error al cargar datos iniciales: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Agregar Almacén',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveWarehouse,
            child: Text(
              'GUARDAR',
              style: TextStyle(
                color: _isLoading ? Colors.white54 : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBasicInfoSection(),
                    const SizedBox(height: 24),
                    _buildLayoutsSection(),
                    const SizedBox(height: 24),
                    _buildConditionsSection(),
                    const SizedBox(height: 24),
                    _buildStockLimitsSection(),
                    const SizedBox(height: 32),
                    _buildSaveButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Información Básica'),
            const SizedBox(height: 16),
            
            // Campo: Denominación
            TextFormField(
              controller: _denominacionController,
              decoration: const InputDecoration(
                labelText: 'Denominación del Almacén',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.warehouse),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Por favor ingrese la denominación';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Campo: Dirección
            TextFormField(
              controller: _direccionController,
              decoration: const InputDecoration(
                labelText: 'Dirección',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Por favor ingrese la dirección';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Campo: Ubicación
            TextFormField(
              controller: _ubicacionController,
              decoration: const InputDecoration(
                labelText: 'Ubicación',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.place),
              ),
            ),
            const SizedBox(height: 16),
            
            // Información de tienda (solo lectura)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.textSecondary.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.store, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Text(
                    'Tienda: Se usará la tienda asignada al usuario',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildLayoutsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Layouts del Almacén',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _addLayout,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar Layout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_layouts.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'No hay layouts agregados\nToque "Agregar Layout" para comenzar',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _layouts.length,
                itemBuilder: (context, index) {
                  final layout = _layouts[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.view_module),
                      title: Text(layout['denominacion'] ?? ''),
                      subtitle: Text('Tipo: ${layout['tipo_layout_nombre'] ?? ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeLayout(index),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Condiciones del Almacén',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
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
                  selectedColor: AppColors.primary.withOpacity(0.2),
                  checkmarkColor: AppColors.primary,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockLimitsSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Límites de Stock',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _addStockLimit,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar Límite'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_limitesStock.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'No hay límites de stock configurados\nToque "Agregar Límite" para comenzar',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _limitesStock.length,
                itemBuilder: (context, index) {
                  final limite = _limitesStock[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.inventory),
                      title: Text(limite['producto_nombre'] ?? ''),
                      subtitle: Text('Min: ${limite['stock_min']} | Max: ${limite['stock_max']} | Ordenar: ${limite['stock_ordenar']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeStockLimit(index),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveWarehouse,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                'CREAR ALMACÉN',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

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
      // Preparar datos para el RPC
      final layoutsData = _layouts.map((layout) => {
        'id_tipo_layout': layout['id_tipo_layout'],
        'id_layout_padre': layout['id_layout_padre'],
        'denominacion': layout['denominacion'],
        'sku_codigo': layout['sku_codigo'],
        'clasificacion_abc': layout['clasificacion_abc'],
        'fecha_desde': layout['fecha_desde'],
        'fecha_hasta': layout['fecha_hasta'],
      }).toList();

      final limitesStockData = _limitesStock.map((limite) => {
        'id_producto': limite['id_producto'],
        'stock_min': limite['stock_min'],
        'stock_max': limite['stock_max'],
        'stock_ordenar': limite['stock_ordenar'],
      }).toList();

      final response = await _warehouseService.createWarehouse(
        denominacionAlmacen: _denominacionController.text,
        direccionAlmacen: _direccionController.text,
        ubicacionAlmacen: _ubicacionController.text,
        idTiendaParam: _tiendaId!,
        condicionesData: _selectedCondiciones.isNotEmpty ? _selectedCondiciones : null,
        layoutsData: layoutsData.isNotEmpty ? layoutsData : null,
        limitesStockData: limitesStockData.isNotEmpty ? limitesStockData : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Almacén creado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Retornar true para indicar éxito
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error al crear almacén: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}

class _LayoutDialog extends StatefulWidget {
  final List<Map<String, dynamic>> tiposLayout;
  final Function(Map<String, dynamic>) onSave;

  const _LayoutDialog({
    required this.tiposLayout,
    required this.onSave,
  });

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
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar Layout'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _denominacionController,
              decoration: const InputDecoration(
                labelText: 'Denominación *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedTipoLayout,
              decoration: const InputDecoration(
                labelText: 'Tipo de Layout *',
                border: OutlineInputBorder(),
              ),
              items: widget.tiposLayout.map((tipo) => DropdownMenuItem<int>(
                value: tipo['id'],
                child: Text(tipo['denominacion']),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedTipoLayout = value;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _skuController,
              decoration: const InputDecoration(
                labelText: 'SKU Código',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _clasificacionAbc,
              decoration: const InputDecoration(
                labelText: 'Clasificación ABC',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('A - Alta rotación')),
                DropdownMenuItem(value: 2, child: Text('B - Media rotación')),
                DropdownMenuItem(value: 3, child: Text('C - Baja rotación')),
              ],
              onChanged: (value) {
                setState(() {
                  _clasificacionAbc = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saveLayout,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _saveLayout() {
    if (_denominacionController.text.trim().isEmpty || _selectedTipoLayout == null) {
      return;
    }

    final tipoLayoutNombre = widget.tiposLayout
        .firstWhere((tipo) => tipo['id'] == _selectedTipoLayout)['denominacion'];

    widget.onSave({
      'id_tipo_layout': _selectedTipoLayout,
      'id_layout_padre': _selectedLayoutPadre,
      'denominacion': _denominacionController.text.trim(),
      'sku_codigo': _skuController.text.trim().isNotEmpty ? _skuController.text.trim() : null,
      'clasificacion_abc': _clasificacionAbc,
      'fecha_desde': DateTime.now().toIso8601String(),
      'fecha_hasta': null,
      'tipo_layout_nombre': tipoLayoutNombre,
    });

    Navigator.of(context).pop();
  }
}

class _StockLimitDialog extends StatefulWidget {
  final List<Map<String, dynamic>> productos;
  final Function(Map<String, dynamic>) onSave;

  const _StockLimitDialog({
    required this.productos,
    required this.onSave,
  });

  @override
  State<_StockLimitDialog> createState() => _StockLimitDialogState();
}

class _StockLimitDialogState extends State<_StockLimitDialog> {
  final _stockMinController = TextEditingController();
  final _stockMaxController = TextEditingController();
  final _stockOrdenarController = TextEditingController();
  int? _selectedProducto;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar Límite de Stock'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: _selectedProducto,
              decoration: const InputDecoration(
                labelText: 'Producto *',
                border: OutlineInputBorder(),
              ),
              items: widget.productos.map((producto) => DropdownMenuItem<int>(
                value: producto['id'],
                child: Text(producto['denominacion']),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedProducto = value;
                });
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stockMinController,
              decoration: const InputDecoration(
                labelText: 'Stock Mínimo *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stockMaxController,
              decoration: const InputDecoration(
                labelText: 'Stock Máximo *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stockOrdenarController,
              decoration: const InputDecoration(
                labelText: 'Stock a Ordenar *',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saveStockLimit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _saveStockLimit() {
    if (_selectedProducto == null ||
        _stockMinController.text.trim().isEmpty ||
        _stockMaxController.text.trim().isEmpty ||
        _stockOrdenarController.text.trim().isEmpty) {
      return;
    }

    final productoNombre = widget.productos
        .firstWhere((producto) => producto['id'] == _selectedProducto)['denominacion'];

    widget.onSave({
      'id_producto': _selectedProducto,
      'stock_min': double.tryParse(_stockMinController.text.trim()) ?? 0,
      'stock_max': double.tryParse(_stockMaxController.text.trim()) ?? 0,
      'stock_ordenar': double.tryParse(_stockOrdenarController.text.trim()) ?? 0,
      'producto_nombre': productoNombre,
    });

    Navigator.of(context).pop();
  }
}
