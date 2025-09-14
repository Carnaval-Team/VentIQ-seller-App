import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../services/openfoodfacts_service.dart';
import 'barcode_scanner_screen.dart';

class AddProductScreen extends StatefulWidget {
  final Product? product;
  final VoidCallback? onProductSaved;
  
  const AddProductScreen({
    Key? key, 
    this.product,
    this.onProductSaved,
  }) : super(key: key);

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  // Controladores de texto
  final _skuController = TextEditingController();
  final _denominacionController = TextEditingController();
  final _nombreComercialController = TextEditingController();
  final _denominacionCortaController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _descripcionCortaController = TextEditingController();
  final _unidadMedidaController = TextEditingController(); // New controller for unit of measure
  final _diasAlertController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _precioVentaController = TextEditingController();
  final _cantidadPresentacionController = TextEditingController(text: '1'); // Controller for presentation quantity

  // Variables de estado
  bool _isLoading = false;
  bool _isLoadingData = true;
  bool _isLoadingOpenFoodFacts = false;
  bool _showAdvancedConfig = false; // Nueva variable para mostrar/ocultar configuración avanzada

  // Datos para dropdowns
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _subcategorias = [];
  List<Map<String, dynamic>> _presentaciones = [];
  List<Map<String, dynamic>> _atributos = [];

  // Selecciones
  int? _selectedCategoryId;
  List<int> _selectedSubcategorias = [];
  int? _selectedBasePresentationId; // Changed to single base presentation ID
  String _unidadMedida = ''; // New field for unit of measure

  // Presentation management - Removed complex presentation management
  // int? _basePresentationId; // Removed - using _selectedBasePresentationId instead

  // Checkboxes
  bool _esRefrigerado = false;
  bool _esFragil = false;
  bool _esPeligroso = false;
  bool _esVendible = true;
  bool _esComprable = true;
  bool _esInventariable = true;
  bool _esPorLotes = false;

  // Listas dinámicas
  List<String> _etiquetas = [];
  List<Map<String, dynamic>> _multimedias = [];
  List<Map<String, dynamic>> _presentacionesAdicionales = []; // Additional presentations list
  List<Map<String, dynamic>> _selectedPresentaciones = []; // Selected presentations list

  // Variantes
  List<Map<String, dynamic>> _selectedVariantes = [];

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _skuController.text = widget.product!.sku ?? '';
      _denominacionController.text = widget.product!.denominacion ?? '';
      _nombreComercialController.text = widget.product!.nombreComercial ?? '';
      _denominacionCortaController.text = widget.product!.denominacionCorta ?? '';
      _descripcionController.text = widget.product!.description ?? '';
      _descripcionCortaController.text = widget.product!.descripcionCorta ?? '';
      _unidadMedidaController.text = widget.product!.um ?? ''; // New field for unit of measure
      _diasAlertController.text = widget.product!.diasAlertCaducidad.toString() ?? '0';
      _codigoBarrasController.text = widget.product!.codigoBarras ?? '';
      _precioVentaController.text = widget.product!.precioVenta.toString() ?? '0.0';
      _esRefrigerado = widget.product!.esRefrigerado ?? false;
      _esFragil = widget.product!.esFragil ?? false;
      _esPeligroso = widget.product!.esPeligroso ?? false;
      _esVendible = widget.product!.esVendible ?? true;
      _esComprable = widget.product!.esComprable ?? true;
      _esInventariable = widget.product!.esInventariable ?? true;
      _esPorLotes = widget.product!.esPorLotes ?? false;
      _etiquetas = widget.product!.etiquetas ?? [];
      _multimedias = widget.product!.multimedias ?? [];
    }
    _loadInitialData();
  }

  @override
  void dispose() {
    _skuController.dispose();
    _denominacionController.dispose();
    _nombreComercialController.dispose();
    _denominacionCortaController.dispose();
    _descripcionController.dispose();
    _descripcionCortaController.dispose();
    _unidadMedidaController.dispose(); // New controller for unit of measure
    _diasAlertController.dispose();
    _codigoBarrasController.dispose();
    _precioVentaController.dispose();
    _cantidadPresentacionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() => _isLoadingData = true);

      // Cargar datos iniciales en paralelo
      final futures = await Future.wait([
        ProductService.getCategorias(),
        ProductService.getPresentaciones(),
        ProductService.getAtributos(),
      ]);

      setState(() {
        _categorias = futures[0];
        _presentaciones = futures[1];
        _atributos = futures[2];
        
        // Configurar valores por defecto solo para productos nuevos
        if (widget.product == null) {
          _setDefaultValues();
        }
        
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      _showErrorSnackBar('Error al cargar datos iniciales: $e');
    }
  }

  void _setDefaultValues() {
    // 1. Establecer precio de venta por defecto en 100
    _precioVentaController.text = '100.00';
    
    // 2. Seleccionar 'unidad' como presentación base por defecto con cantidad 1
    if (_presentaciones.isNotEmpty) {
      final unidadPresentation = _presentaciones.where(
        (p) => p['denominacion'].toString().toLowerCase() == 'unidad',
      ).firstOrNull;
      _selectedBasePresentationId = unidadPresentation?['id'];
      _cantidadPresentacionController.text = '1';
    }
    
    // 3. Agregar presentación adicional 'caja' por 24 unidades por defecto
    if (_presentaciones.isNotEmpty) {
      final cajaPresentation = _presentaciones.where(
        (p) => p['denominacion'].toString().toLowerCase() == 'caja',
      ).firstOrNull;
      
      if (cajaPresentation != null) {
        // Calcular precio automático para la caja (100 * 24 = 2400)
        final basePrice = 100.0;
        final quantity = 24.0;
        final calculatedPrice = basePrice * quantity;
        
        _presentacionesAdicionales.add({
          'id_presentacion': cajaPresentation['id'],
          'denominacion': cajaPresentation['denominacion'],
          'cantidad': quantity,
          'precio': calculatedPrice,
        });
      }
    }
  }

  Future<void> _loadSubcategorias(int categoryId) async {
    try {
      final subcategorias = await ProductService.getSubcategorias(categoryId);
      setState(() {
        _subcategorias = subcategorias;
        _selectedSubcategorias.clear(); // Limpiar selecciones previas
      });
      _generateSKU(); // Generar SKU cuando cambia la categoría
    } catch (e) {
      print('Error al cargar subcategorías: $e');
      _showErrorSnackBar('Error al cargar subcategorías: $e');
    }
  }

  void _generateSKU() {
    String sku = '';
    
    // Agregar código de categoría
    if (_selectedCategoryId != null) {
      final categoria = _categorias.firstWhere(
        (cat) => cat['id'] == _selectedCategoryId,
        orElse: () => {'denominacion': 'CAT'},
      );
      final catCode = categoria['denominacion']
          .toString()
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9]'), '')
          .substring(0, categoria['denominacion'].toString().length >= 3 ? 3 : categoria['denominacion'].toString().length);
      sku += catCode;
    }
    
    // Agregar código de subcategoría
    if (_selectedSubcategorias.isNotEmpty) {
      final subcategoria = _subcategorias.firstWhere(
        (subcat) => subcat['id'] == _selectedSubcategorias.first,
        orElse: () => {'denominacion': 'SUB'},
      );
      final subCode = subcategoria['denominacion']
          .toString()
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9]'), '')
          .substring(0, subcategoria['denominacion'].toString().length >= 2 ? 2 : subcategoria['denominacion'].toString().length);
      sku += '-$subCode';
    }
    
    // Agregar códigos de variantes
    for (var variante in _selectedVariantes) {
      final opciones = variante['opciones'] as List<Map<String, dynamic>>? ?? [];
      for (var opcion in opciones.take(1)) { // Solo la primera opción
        final varCode = opcion['valor']
            .toString()
            .toUpperCase()
            .replaceAll(RegExp(r'[^A-Z0-9]'), '')
            .substring(0, opcion['valor'].toString().length >= 2 ? 2 : opcion['valor'].toString().length);
        sku += '-$varCode';
      }
    }
    
    // Agregar timestamp para unicidad
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    sku += '-$timestamp';
    
    // Actualizar el campo SKU
    setState(() {
      _skuController.text = sku.isNotEmpty ? sku : 'PROD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product != null ? 'Editar Producto' : 'Agregar Producto',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProduct,
            child: Text(
              widget.product != null ? 'ACTUALIZAR' : 'GUARDAR',
              style: TextStyle(
                color: _isLoading ? Colors.white54 : Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body:
          _isLoadingData
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Cargando datos...'),
                  ],
                ),
              )
              : Form(
                key: _formKey,
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildEssentialFieldsSection(),
                    const SizedBox(height: 32),
                    _buildPresentacionesAdicionalesSection(),
                    const SizedBox(height: 32),
                    _buildAdvancedFieldsSection(),
                  ],
                ),
              ),
    );
  }

  Widget _buildEssentialFieldsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información Esencial',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            
            // Subsección: Información Básica
            _buildBasicInfoSubsection(),
            const SizedBox(height: 24),
            
            // Subsección: Precio de Venta
            _buildPriceSubsection(),
            const SizedBox(height: 24),
            
            // Subsección: Presentación Base
            _buildBasePresentationSubsection(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInfoSubsection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Información Básica',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // SKU - Visible pero auto-generado
        TextFormField(
          controller: _skuController,
          decoration: InputDecoration(
            labelText: 'SKU *',
            hintText: 'Se genera automáticamente',
            border: const OutlineInputBorder(),
            suffixIcon: Icon(Icons.auto_awesome, color: AppColors.primary),
          ),
          readOnly: true,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'El SKU es requerido';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        // Denominación
        TextFormField(
          controller: _denominacionController,
          decoration: const InputDecoration(
            labelText: 'Nombre del Producto *',
            hintText: 'Nombre completo del producto',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'El nombre del producto es requerido';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        // Descripción
        TextFormField(
          controller: _descripcionController,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            hintText: 'Descripción del producto',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        // Categoría
        DropdownButtonFormField<int>(
          value: _selectedCategoryId,
          decoration: const InputDecoration(
            labelText: 'Categoría *',
            border: OutlineInputBorder(),
          ),
          items: _categorias.map((categoria) {
            return DropdownMenuItem<int>(
              value: categoria['id'],
              child: Text(categoria['denominacion']),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCategoryId = value;
              _selectedSubcategorias.clear();
            });
            if (value != null) {
              _loadSubcategorias(value);
            }
          },
          validator: (value) {
            if (value == null) {
              return 'Selecciona una categoría';
            }
            return null;
          },
        ),
        // Subcategorías
        if (_subcategorias.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Subcategorías',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _subcategorias.map((subcat) {
              final isSelected = _selectedSubcategorias.contains(subcat['id']);
              return FilterChip(
                label: Text(subcat['denominacion']),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedSubcategorias.add(subcat['id']);
                    } else {
                      _selectedSubcategorias.remove(subcat['id']);
                    }
                  });
                  _generateSKU();
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceSubsection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.attach_money, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Precio de Venta',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _precioVentaController,
          decoration: const InputDecoration(
            labelText: 'Precio de Venta Base *',
            hintText: '0.00',
            prefixText: '\$ ',
            border: OutlineInputBorder(),
            helperText: 'Este precio se usará como base para calcular precios de presentaciones adicionales',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'El precio de venta es requerido';
            }
            final price = double.tryParse(value);
            if (price == null || price <= 0) {
              return 'Ingresa un precio válido';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildBasePresentationSubsection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.inventory_2, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Presentación Base',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_presentaciones.isEmpty)
          const Text(
            'Cargando presentaciones...',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedBasePresentationId,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Presentación *',
                    border: OutlineInputBorder(),
                  ),
                  items: _presentaciones.map((presentacion) {
                    return DropdownMenuItem<int>(
                      value: presentacion['id'],
                      child: Text(presentacion['denominacion']),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedBasePresentationId = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Selecciona una presentación base';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _cantidadPresentacionController,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad *',
                    border: OutlineInputBorder(),
                    helperText: 'Unidades por presentación',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Cantidad requerida';
                    }
                    final cantidad = double.tryParse(value);
                    if (cantidad == null || cantidad <= 0) {
                      return 'Cantidad inválida';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La presentación base define la unidad mínima de venta y será usada como referencia para presentaciones adicionales.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPresentacionesAdicionalesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Presentaciones Adicionales',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _selectedBasePresentationId != null ? _addPresentacionAdicional : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar', style: TextStyle(fontSize: 14)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_presentacionesAdicionales.isEmpty)
              const Text(
                'No hay presentaciones adicionales configuradas.\nEjemplo: Blister 6 unidades, Caja 24 unidades, Pallet 2479 unidades.',
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _presentacionesAdicionales.length,
                itemBuilder: (context, index) {
                  final presentacion = _presentacionesAdicionales[index];
                  final basePresentacion = _presentaciones.firstWhere(
                    (p) => p['id'] == _selectedBasePresentationId,
                    orElse: () => {'denominacion': 'unidad'},
                  );
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.inventory_2,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        presentacion['denominacion'],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '1 ${presentacion['denominacion']} = ${presentacion['cantidad']} ${basePresentacion['denominacion']}',
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                          if (presentacion['precio'] != null)
                            Text(
                              'Precio: \$${presentacion['precio'].toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _editPresentacionAdicional(index),
                            tooltip: 'Editar',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () => _removePresentacionAdicional(index),
                            tooltip: 'Eliminar',
                          ),
                        ],
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

  Widget _buildAdvancedFieldsSection() {
    return Column(
      children: [
        // Propiedades del producto
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Propiedades del Producto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Es Refrigerado'),
                  subtitle: const Text('Requiere refrigeración'),
                  value: _esRefrigerado,
                  onChanged: (value) => setState(() => _esRefrigerado = value ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Es Frágil'),
                  subtitle: const Text('Requiere manejo especial'),
                  value: _esFragil,
                  onChanged: (value) => setState(() => _esFragil = value ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Es Peligroso'),
                  subtitle: const Text('Producto peligroso o tóxico'),
                  value: _esPeligroso,
                  onChanged: (value) => setState(() => _esPeligroso = value ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Es Vendible'),
                  subtitle: const Text('Disponible para venta'),
                  value: _esVendible,
                  onChanged: (value) => setState(() => _esVendible = value ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Es Comprable'),
                  subtitle: const Text('Se puede comprar a proveedores'),
                  value: _esComprable,
                  onChanged: (value) => setState(() => _esComprable = value ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Es Inventariable'),
                  subtitle: const Text('Se controla en inventario'),
                  value: _esInventariable,
                  onChanged: (value) => setState(() => _esInventariable = value ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Es por Lotes'),
                  subtitle: const Text('Se maneja por lotes con fechas'),
                  value: _esPorLotes,
                  onChanged: (value) => setState(() => _esPorLotes = value ?? false),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _diasAlertController,
                  decoration: const InputDecoration(
                    labelText: 'Días de Alerta de Caducidad',
                    hintText: 'Días antes del vencimiento para alertar',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Variantes
        _buildVariantesSection(),
        const SizedBox(height: 16),
        // Información Adicional
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Información Adicional',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombreComercialController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Comercial',
                    hintText: 'Nombre comercial o marca',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _denominacionCortaController,
                        decoration: const InputDecoration(
                          labelText: 'Denominación Corta',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _descripcionCortaController,
                        decoration: const InputDecoration(
                          labelText: 'Descripción Corta',
                          hintText: 'Descripción breve',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codigoBarrasController,
                        decoration: InputDecoration(
                          labelText: 'Código de Barras',
                          hintText: 'Código de barras del producto',
                          border: const OutlineInputBorder(),
                          suffixIcon: _isLoadingOpenFoodFacts
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoadingOpenFoodFacts ? null : _openBarcodeScanner,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(12),
                        ),
                        child: _isLoadingOpenFoodFacts
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(
                                Icons.qr_code_scanner,
                                size: 24,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Etiquetas
        _buildTagsSection(),
        const SizedBox(height: 16),
        // Multimedia
        _buildMultimediaSection(),
        const SizedBox(height: 16),
        // Variantes
        // _buildVariantesSection(),
      ],
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Por favor corrija los errores en el formulario');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Obtener ID de tienda
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      // Preparar datos del producto
      final productoData = {
        'id_tienda': idTienda,
        'sku': _skuController.text,
        'id_categoria': _selectedCategoryId,
        'denominacion': _denominacionController.text,
        'nombre_comercial': _nombreComercialController.text,
        'denominacion_corta': _denominacionCortaController.text,
        'description': _descripcionController.text,
        'descripcion_corta': _descripcionCortaController.text,
        'es_refrigerado': _esRefrigerado,
        'es_fragil': _esFragil,
        'es_peligroso': _esPeligroso,
        'es_vendible': _esVendible,
        'es_comprable': _esComprable,
        'es_inventariable': _esInventariable,
        'es_por_lotes': _esPorLotes,
        'dias_alert_caducidad':
            _diasAlertController.text.isNotEmpty
                ? int.tryParse(_diasAlertController.text)
                : null,
        'codigo_barras': _codigoBarrasController.text,
      };

      // Preparar subcategorías
      final subcategoriasData =
          _selectedSubcategorias.map((id) => {'id_sub_categoria': id}).toList();

      // Preparar etiquetas
      final etiquetasData =
          _etiquetas.map((etiqueta) => {'etiqueta': etiqueta}).toList();

      // Preparar multimedia
      final multimediasData =
          _multimedias.map((media) => {'media': media}).toList();

      // Preparar presentaciones
      final presentacionesData = [
        {
          'id_presentacion': _selectedBasePresentationId,
          'cantidad': double.parse(_cantidadPresentacionController.text),
          'es_base': true,
        },
      ];

      // Preparar variantes
      List<Map<String, dynamic>>? variantesData;
      if (_selectedVariantes.isNotEmpty && _selectedSubcategorias.isNotEmpty) {
        variantesData = [];
        for (final subcategoriaId in _selectedSubcategorias) {
          for (final variante in _selectedVariantes) {
            variantesData.add({
              'id_sub_categoria': subcategoriaId,
              'id_atributo': variante['id_atributo'],
              'opciones': (variante['opciones'] as List<dynamic>)
                  .map((opcion) {
                    final opcionMap = opcion as Map<String, dynamic>;
                    return {
                      'id_opcion': opcionMap['id'], // AGREGAR ID DE OPCIÓN EXISTENTE
                      'valor': opcionMap['valor'],
                      'sku_codigo': opcionMap['sku_codigo'] ?? 
                          '${_skuController.text}-${opcionMap['valor']}'
                              .replaceAll(' ', '').toUpperCase(),
                    };
                  })
                  .toList(),
            });
          }
        }
      }

      // Preparar precios
      final preciosData = [
        {
          'precio_venta_cup': double.parse(_precioVentaController.text),
          'fecha_desde': DateTime.now().toIso8601String().substring(0, 10),
          'id_variante': null,
        },
      ];

      // DEBUG: Imprimir todos los datos antes de enviar
      print('=== DATOS COMPLETOS ENVIADOS A RPC ===');
      print('PRODUCTO DATA: ${jsonEncode(productoData)}');
      print('SUBCATEGORIAS DATA: ${jsonEncode(subcategoriasData)}');
      print('PRESENTACIONES DATA: ${jsonEncode(presentacionesData)}');
      print('ETIQUETAS DATA: ${jsonEncode(etiquetasData)}');
      print('MULTIMEDIAS DATA: ${jsonEncode(multimediasData)}');
      print('VARIANTES DATA: ${jsonEncode(variantesData)}');
      print('PRECIOS DATA: ${jsonEncode(preciosData)}');
      print('=====================================');

      // Insertar producto
      final result = await ProductService.insertProductoCompleto(
        productoData: productoData,
        subcategoriasData:
            subcategoriasData.isNotEmpty ? subcategoriasData : null,
        presentacionesData:
            presentacionesData.isNotEmpty ? presentacionesData : null,
        etiquetasData: etiquetasData.isNotEmpty ? etiquetasData : null,
        multimediasData: multimediasData.isNotEmpty ? multimediasData : null,
        variantesData: variantesData,
        preciosData: preciosData,
      );

      // Mostrar éxito y regresar
      _showSuccessSnackBar('Producto creado exitosamente');
      if (widget.onProductSaved != null) {
        widget.onProductSaved!();
      }
      Navigator.pop(context, true); // true indica que se creó un producto
    } catch (e) {
      _showErrorSnackBar('Error al crear producto: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  Future<void> _openBarcodeScanner() async {
    try {
      setState(() => _isLoadingOpenFoodFacts = true);
      
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );
      
      if (result != null && result is String) {
        _codigoBarrasController.text = result;
        
        // Intentar obtener información del producto desde OpenFoodFacts
        try {
          final response = await OpenFoodFactsService.getProductByBarcode(result);
          if (response.isSuccess && response.product != null) {
            _showProductInfoDialog(response.product!.toJson());
          }
        } catch (e) {
          print('Error al obtener información de OpenFoodFacts: $e');
        }
      }
    } catch (e) {
      _showErrorSnackBar('Error al escanear código de barras: $e');
    } finally {
      setState(() => _isLoadingOpenFoodFacts = false);
    }
  }

  void _showProductInfoDialog(Map<String, dynamic> productInfo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Información del Producto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (productInfo['product_name'] != null)
              Text('Nombre: ${productInfo['product_name']}'),
            if (productInfo['brands'] != null)
              Text('Marca: ${productInfo['brands']}'),
            if (productInfo['categories'] != null)
              Text('Categorías: ${productInfo['categories']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              // Llenar campos con la información obtenida
              if (productInfo['product_name'] != null) {
                _denominacionController.text = productInfo['product_name'];
              }
              if (productInfo['brands'] != null) {
                _nombreComercialController.text = productInfo['brands'];
              }
              Navigator.pop(context);
            },
            child: const Text('Usar Información'),
          ),
        ],
      ),
    );
  }

  Widget _buildTagsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Etiquetas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addEtiqueta,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_etiquetas.isEmpty)
              const Text(
                'No hay etiquetas agregadas',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _etiquetas.map((etiqueta) {
                  return Chip(
                    label: Text(etiqueta),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() => _etiquetas.remove(etiqueta));
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultimediaSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Multimedia',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addMultimedia,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_multimedias.isEmpty)
              const Text(
                'No hay multimedia agregada',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              Column(
                children: _multimedias.map((media) {
                  return ListTile(
                    leading: const Icon(Icons.image),
                    title: Text(media['url']),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        setState(() => _multimedias.remove(media));
                      },
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Variantes del Producto',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _selectedSubcategorias.isNotEmpty ? _addVariante : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar', style: TextStyle(fontSize: 14)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
            if (_selectedSubcategorias.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selecciona al menos una subcategoría para poder agregar variantes',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (_selectedVariantes.isEmpty)
              const Text(
                'No hay variantes configuradas',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              Column(
                children: _selectedVariantes.map((variante) {
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(variante['atributo_nombre']),
                      subtitle: Text('Opciones: ${variante['opciones'].length}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() => _selectedVariantes.remove(variante));
                          _generateSKU(); // Regenerar SKU cuando se elimina variante
                        },
                      ),
                      onTap: () => _editVariante(variante),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  void _addEtiqueta() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Agregar Etiqueta'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Etiqueta',
              hintText: 'Ej: Orgánico, Sin gluten, etc.',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  setState(() => _etiquetas.add(controller.text));
                  Navigator.pop(context);
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    );
  }

  void _addMultimedia() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Agregar Multimedia'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'URL de imagen',
              hintText: 'https://ejemplo.com/imagen.jpg',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  setState(() => _multimedias.add({'url': controller.text}));
                  Navigator.pop(context);
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        );
      },
    );
  }

  void _addVariante() {
    if (_atributos.isEmpty) {
      _showErrorSnackBar('No hay atributos disponibles');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _VarianteDialog(
        atributos: _atributos,
        onSave: (variante) {
          setState(() => _selectedVariantes.add(variante));
          _generateSKU(); // Regenerar SKU cuando se agrega variante
        },
      ),
    );
  }

  void _editVariante(Map<String, dynamic> variante) {
    showDialog(
      context: context,
      builder: (context) => _VarianteDialog(
        atributos: _atributos,
        initialVariante: variante,
        onSave: (updatedVariante) {
          setState(() {
            final index = _selectedVariantes.indexOf(variante);
            _selectedVariantes[index] = updatedVariante;
          });
          _generateSKU(); // Regenerar SKU cuando se edita variante
        },
      ),
    );
  }

  void _addPresentacionAdicional() {
    // Validar que existe precio de venta base
    final basePrice = double.tryParse(_precioVentaController.text);
    if (basePrice == null || basePrice <= 0) {
      _showErrorSnackBar('Debe ingresar un precio de venta base válido antes de agregar presentaciones adicionales');
      return;
    }
    
    // Validar que existe presentación base seleccionada
    if (_selectedBasePresentationId == null) {
      _showErrorSnackBar('Debe seleccionar una presentación base antes de agregar presentaciones adicionales');
      return;
    }
    
    // Validar que la cantidad de presentación base es válida
    final baseCantidad = double.tryParse(_cantidadPresentacionController.text);
    if (baseCantidad == null || baseCantidad <= 0) {
      _showErrorSnackBar('Debe ingresar una cantidad válida para la presentación base');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Presentación Adicional'),
        content: SizedBox(
          width: double.maxFinite,
          child: _PresentacionDialog(
            presentaciones: _presentaciones,
            basePresentacionId: _selectedBasePresentationId,
            basePrice: basePrice, // Pass base price for calculations
            presentacionesExistentes: _presentacionesAdicionales, // Pass existing presentations
            onSave: (presentacion) {
              setState(() => _presentacionesAdicionales.add(presentacion));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Presentación agregada exitosamente')),
              );
            },
          ),
        ),
      ),
    );
  }

  void _editPresentacionAdicional(int index) {
    if (index >= 0 && index < _presentacionesAdicionales.length) {
      final presentacion = _presentacionesAdicionales[index];
      final basePrice = double.tryParse(_precioVentaController.text);
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Editar Presentación Adicional'),
          content: SizedBox(
            width: double.maxFinite,
            child: _PresentacionDialog(
              presentaciones: _presentaciones,
              basePresentacionId: _selectedBasePresentationId,
              basePrice: basePrice, // Pass base price for calculations
              initialPresentacion: presentacion,
              onSave: (updatedPresentacion) {
                setState(() {
                  _presentacionesAdicionales[index] = updatedPresentacion;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Presentación actualizada exitosamente')),
                );
              },
            ),
          ),
        ),
      );
    }
  }

  void _removePresentacionAdicional(int index) {
    if (index >= 0 && index < _presentacionesAdicionales.length) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar eliminación'),
          content: Text(
            '¿Estás seguro de que deseas eliminar la presentación "${_presentacionesAdicionales[index]['denominacion']}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _presentacionesAdicionales.removeAt(index);
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Presentación eliminada exitosamente')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
    }
  }
}

class _PresentacionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> presentaciones;
  final int? basePresentacionId;
  final double? basePrice;
  final Function(Map<String, dynamic>) onSave;
  final Map<String, dynamic>? initialPresentacion;
  final List<Map<String, dynamic>>? presentacionesExistentes;

  const _PresentacionDialog({
    required this.presentaciones,
    required this.basePresentacionId,
    required this.basePrice,
    required this.onSave,
    this.initialPresentacion,
    this.presentacionesExistentes,
  });

  @override
  State<_PresentacionDialog> createState() => _PresentacionDialogState();
}

class _PresentacionDialogState extends State<_PresentacionDialog> {
  int? _selectedPresentacionId;
  final _cantidadController = TextEditingController(text: '1');
  final _precioController = TextEditingController(); // Agregar controlador de precio
  
  @override
  void initState() {
    super.initState();
    if (widget.initialPresentacion != null) {
      _selectedPresentacionId = widget.initialPresentacion!['id_presentacion'];
      _cantidadController.text = widget.initialPresentacion!['cantidad'].toString();
      _precioController.text = widget.initialPresentacion!['precio']?.toString() ?? '0.0';
    }
    
    // Calcular precio inicial cuando cambie la cantidad
    _cantidadController.addListener(_calculatePrice);
    
    // Calcular precio inicial si hay precio base disponible
    if (widget.basePrice != null) {
      _calculatePrice();
    }
  }

  @override
  void dispose() {
    _cantidadController.removeListener(_calculatePrice);
    _cantidadController.dispose();
    _precioController.dispose();
    super.dispose();
  }

  void _calculatePrice() {
    if (widget.basePrice != null) {
      final cantidad = double.tryParse(_cantidadController.text) ?? 1;
      final calculatedPrice = widget.basePrice! * cantidad;
      _precioController.text = calculatedPrice.toStringAsFixed(2);
    }
  }

  void _savePresentacion() {
    if (_selectedPresentacionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona una presentación')),
      );
      return;
    }

    final cantidad = double.tryParse(_cantidadController.text);
    if (cantidad == null || cantidad <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa una cantidad válida mayor a 0')),
      );
      return;
    }

    final precio = double.tryParse(_precioController.text);
    if (precio == null || precio <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa un precio válido mayor a 0')),
      );
      return;
    }

    // Find the selected presentation
    final selectedPresentacion = widget.presentaciones.firstWhere(
      (p) => p['id'] == _selectedPresentacionId,
      orElse: () => {},
    );

    final presentacion = {
      'id_presentacion': _selectedPresentacionId,
      'denominacion': selectedPresentacion['denominacion'] ?? 'Presentación',
      'cantidad': cantidad,
      'precio': precio, // Incluir precio validado
    };

    // Validar que no exista una presentación con el mismo ID
    if (widget.presentacionesExistentes != null && widget.presentacionesExistentes!.any((p) => p['id_presentacion'] == presentacion['id_presentacion'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya existe una presentación con el mismo ID')),
      );
      return;
    }

    widget.onSave(presentacion);
  }

  @override
  Widget build(BuildContext context) {
    // Get base presentation name for display
    final basePresentacion = widget.presentaciones.firstWhere(
      (p) => p['id'] == widget.basePresentacionId,
      orElse: () => {'denominacion': 'unidad'},
    );

    // Get selected presentation for conversion display
    final selectedPresentacion = _selectedPresentacionId != null
        ? widget.presentaciones.firstWhere(
            (p) => p['id'] == _selectedPresentacionId,
            orElse: () => {},
          )
        : null;

    final cantidad = double.tryParse(_cantidadController.text) ?? 1;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 400, // Limit maximum height
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccionar Presentación:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _selectedPresentacionId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Selecciona una presentación',
              ),
              items: widget.presentaciones
                  .where((p) => p['id'] != widget.basePresentacionId) // Exclude base presentation
                  .map((presentacion) {
                return DropdownMenuItem<int>(
                  value: presentacion['id'],
                  child: Text(presentacion['denominacion'] ?? 'Sin nombre'),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPresentacionId = value;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Cantidad de unidades base por presentación:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _cantidadController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Ej: 24',
                suffixText: basePresentacion['denominacion'],
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                setState(() {}); // Trigger rebuild to update conversion display
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Precio por presentación:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _precioController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixText: '\$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
          
            // Conversion preview
            if (selectedPresentacion != null && selectedPresentacion.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '1 ${selectedPresentacion['denominacion']} = ${cantidad.toStringAsFixed(cantidad.truncateToDouble() == cantidad ? 0 : 1)} ${basePresentacion['denominacion']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _savePresentacion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VarianteDialog extends StatefulWidget {
  final List<Map<String, dynamic>> atributos;
  final Function(Map<String, dynamic>) onSave;
  final Map<String, dynamic>? initialVariante;

  const _VarianteDialog({
    required this.atributos,
    required this.onSave,
    this.initialVariante,
  });

  @override
  State<_VarianteDialog> createState() => _VarianteDialogState();
}

class _VarianteDialogState extends State<_VarianteDialog> {
  int? _selectedAtributoId;
  String _selectedAtributoNombre = '';
  List<Map<String, dynamic>> _opciones = [];
  final TextEditingController _opcionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialVariante != null) {
      _selectedAtributoId = widget.initialVariante!['id_atributo'];
      _selectedAtributoNombre = widget.initialVariante!['atributo_nombre'];
      _opciones = List<Map<String, dynamic>>.from(widget.initialVariante!['opciones'] ?? []);
    }
  }

  @override
  void dispose() {
    _opcionController.dispose();
    super.dispose();
  }

  void _addOpcion() {
    final opcion = _opcionController.text.trim();
    if (opcion.isNotEmpty) {
      setState(() {
        _opciones.add({
          'valor': opcion,
          'id': DateTime.now().millisecondsSinceEpoch, // Temporary ID
        });
        _opcionController.clear();
      });
    }
  }

  void _removeOpcion(int index) {
    setState(() {
      _opciones.removeAt(index);
    });
  }

  void _saveVariante() {
    if (_selectedAtributoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un atributo')),
      );
      return;
    }

    if (_opciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos una opción')),
      );
      return;
    }

    final variante = {
      'id_atributo': _selectedAtributoId,
      'atributo_nombre': _selectedAtributoNombre,
      'opciones': _opciones,
    };

    widget.onSave(variante);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialVariante != null ? 'Editar Variante' : 'Agregar Variante'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selector de atributo
            const Text(
              'Atributo:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _selectedAtributoId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Selecciona un atributo',
              ),
              items: widget.atributos.map((atributo) {
                return DropdownMenuItem<int>(
                  value: atributo['id'],
                  child: Text(atributo['denominacion'] ?? 'Sin nombre'),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedAtributoId = value;
                  final atributo = widget.atributos.firstWhere(
                    (a) => a['id'] == value,
                    orElse: () => {},
                  );
                  _selectedAtributoNombre = atributo['denominacion'] ?? '';
                  
                  // Cargar opciones existentes del atributo seleccionado
                  if (atributo.isNotEmpty && atributo['app_dat_atributo_opcion'] != null) {
                    final opcionesExistentes = atributo['app_dat_atributo_opcion'] as List<dynamic>;
                    _opciones = opcionesExistentes.map((opcion) => {
                      'id': opcion['id'],
                      'valor': opcion['valor'],
                    }).toList().cast<Map<String, dynamic>>();
                  } else {
                    // Si no hay opciones existentes, limpiar la lista
                    _opciones = [];
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // Opciones
            const Text(
              'Opciones:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            
            // Input para agregar opciones
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _opcionController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Ej: Rojo, Azul, Grande, etc.',
                    ),
                    autofocus: true,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addOpcion,
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Lista de opciones agregadas
            if (_opciones.isNotEmpty) ...[
              const Text('Opciones agregadas:'),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate adaptive height based on available space
                  double maxHeight = constraints.maxHeight > 400 ? 150 : 100;
                  return Container(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _opciones.length,
                      itemBuilder: (context, index) {
                        final opcion = _opciones[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              opcion['valor'],
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              onPressed: () => _removeOpcion(index),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ] else
              const Text(
                'No hay opciones agregadas',
                style: TextStyle(color: AppColors.textSecondary),
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
          onPressed: _saveVariante,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
