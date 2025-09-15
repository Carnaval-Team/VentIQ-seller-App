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

  // New controllers for variantes
  int? _selectedAtributoId;
  final _variantePrecioController = TextEditingController();

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
    _variantePrecioController.dispose();
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
                      title: Text(presentacion['denominacion']),
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
        _buildVariantesStep(),
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
      ],
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Por favor corrija los errores en el formulario');
      return;
    }

    // Validaciones específicas para datos relacionados
    if (_selectedBasePresentationId == null) {
      _showErrorSnackBar('Debe seleccionar una presentación base');
      return;
    }

    if (_cantidadPresentacionController.text.isEmpty || 
        double.tryParse(_cantidadPresentacionController.text) == null ||
        double.parse(_cantidadPresentacionController.text) <= 0) {
      _showErrorSnackBar('La cantidad de presentación debe ser un número válido mayor a 0');
      return;
    }

    if (_precioVentaController.text.isEmpty || 
        double.tryParse(_precioVentaController.text) == null ||
        double.parse(_precioVentaController.text) <= 0) {
      _showErrorSnackBar('El precio de venta debe ser un número válido mayor a 0');
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
        'nombre_comercial': _nombreComercialController.text.isNotEmpty 
            ? _nombreComercialController.text 
            : _denominacionController.text, // Fallback al nombre principal
        'denominacion_corta': _denominacionCortaController.text.isNotEmpty 
            ? _denominacionCortaController.text 
            : _denominacionController.text.substring(0, 
                _denominacionController.text.length > 20 ? 20 : _denominacionController.text.length),
        'descripcion': _descripcionController.text, // Fixed: matches SQL function field
        'descripcion_corta': _descripcionCortaController.text,
        'um': _unidadMedidaController.text.isNotEmpty  // Fixed: 'um' not 'unidad_medida'
            ? _unidadMedidaController.text 
            : 'und', // Valor por defecto
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

      // Preparar subcategorías (solo si hay seleccionadas)
      List<Map<String, dynamic>>? subcategoriasData;
      if (_selectedSubcategorias.isNotEmpty) {
        subcategoriasData = _selectedSubcategorias.map((id) => {'id_sub_categoria': id}).toList();
      }

      // Preparar etiquetas (solo si hay etiquetas)
      List<Map<String, dynamic>>? etiquetasData;
      if (_etiquetas.isNotEmpty) {
        etiquetasData = _etiquetas.map((etiqueta) => {'etiqueta': etiqueta}).toList();
      }

      // Preparar multimedia (solo si hay multimedia)
      List<Map<String, dynamic>>? multimediasData;
      if (_multimedias.isNotEmpty) {
        multimediasData = _multimedias.map((media) => {'media': media}).toList();
      }

      // Preparar presentaciones (OBLIGATORIO - siempre debe haber al menos una base)
      final presentacionesData = [
        {
          'id_presentacion': _selectedBasePresentationId!,
          'cantidad': double.parse(_cantidadPresentacionController.text),
          'es_base': true,
        },
      ];

      // Agregar presentaciones adicionales si existen
      if (_presentacionesAdicionales.isNotEmpty) {
        for (final presentacion in _presentacionesAdicionales) {
          presentacionesData.add({
            'id_presentacion': presentacion['id_presentacion'],
            'cantidad': presentacion['cantidad'],
            'es_base': false,
          });
        }
      }

      // Preparar precios (OBLIGATORIO - solo precio base y variantes simples)
      final preciosData = [
        {
          'precio_venta_cup': double.parse(_precioVentaController.text),
          'fecha_desde': DateTime.now().toIso8601String().substring(0, 10),
          'id_variante': null, // Precio base sin variante
        },
      ];

      // Agregar precios por variantes simples (solo atributo + precio)
      if (_selectedVariantes.isNotEmpty) {
        for (final variante in _selectedVariantes) {
          preciosData.add({
            'precio_venta_cup': variante['precio'],
            'fecha_desde': DateTime.now().toIso8601String().substring(0, 10),
            'id_atributo': variante['id_atributo'],
          });
        }
      }

      // DEBUG: Imprimir todos los datos antes de enviar
      print('=== DATOS COMPLETOS ENVIADOS A RPC ===');
      print('PRODUCTO DATA: ${jsonEncode(productoData)}');
      print('SUBCATEGORIAS DATA: ${jsonEncode(subcategoriasData)}');
      print('PRESENTACIONES DATA: ${jsonEncode(presentacionesData)}');
      print('ETIQUETAS DATA: ${jsonEncode(etiquetasData)}');
      print('MULTIMEDIAS DATA: ${jsonEncode(multimediasData)}');
      print('PRECIOS DATA: ${jsonEncode(preciosData)}');
      print('=====================================');

      // Insertar producto con validación de datos obligatorios
      final result = await ProductService.insertProductoCompleto(
        productoData: productoData,
        subcategoriasData: subcategoriasData,
        presentacionesData: presentacionesData, // OBLIGATORIO
        etiquetasData: etiquetasData,
        multimediasData: multimediasData,
        preciosData: preciosData, // OBLIGATORIO
      );

      if (result == null) {
        throw Exception('No se recibió respuesta del servidor al crear el producto');
      }

      // Mostrar éxito y regresar
      _showSuccessSnackBar('Producto creado exitosamente con todas sus relaciones');
      if (widget.onProductSaved != null) {
        widget.onProductSaved!();
      }
      Navigator.pop(context, true); // true indica que se creó un producto
    } catch (e) {
      print('❌ Error completo al crear producto: $e');
      _showErrorSnackBar('Error al crear producto: ${e.toString()}');
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
                const Expanded(
                  child: Text(
                    'Etiquetas',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
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

  Widget _buildVariantesStep() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Variantes del Producto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Formulario para agregar variante
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Agregar Variante',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      // Selector de atributo
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Atributo:', style: TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Selecciona un atributo',
                                isDense: true,
                              ),
                              items: _atributos.map((atributo) {
                                return DropdownMenuItem<int>(
                                  value: atributo['id'],
                                  child: Text(atributo['denominacion'] ?? 'Sin nombre'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedAtributoId = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // Campo de precio
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Precio:', style: TextStyle(fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: _variantePrecioController,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                prefixText: '\$ ',
                                hintText: '0.00',
                                isDense: true,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // Botón agregar
                      Column(
                        children: [
                          const SizedBox(height: 20), // Espacio para alinear con los campos
                          ElevatedButton.icon(
                            onPressed: _agregarVariante,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Agregar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Lista de variantes seleccionadas
            if (_selectedVariantes.isNotEmpty) ...[
              const Text(
                'Variantes Agregadas:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              
              ...List.generate(_selectedVariantes.length, (index) {
                final variante = _selectedVariantes[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.label, color: AppColors.primary, size: 20),
                      const SizedBox(width: 12),
                      
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              variante['atributo_nombre'],
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Precio: \$${variante['precio'].toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      IconButton(
                        onPressed: () => _eliminarVariante(index),
                        icon: Icon(Icons.delete_outline, color: Colors.red[600]),
                        tooltip: 'Eliminar variante',
                      ),
                    ],
                  ),
                );
              }),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      'No hay variantes agregadas',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _agregarVariante() {
    if (_selectedAtributoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un atributo')),
      );
      return;
    }

    final precio = double.tryParse(_variantePrecioController.text);
    if (precio == null || precio <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un precio válido')),
      );
      return;
    }

    // Verificar que no esté duplicado
    final yaExiste = _selectedVariantes.any(
      (v) => v['id_atributo'] == _selectedAtributoId,
    );

    if (yaExiste) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este atributo ya fue agregado')),
      );
      return;
    }

    final atributo = _atributos.firstWhere(
      (attr) => attr['id'] == _selectedAtributoId,
      orElse: () => {},
    );

    setState(() {
      _selectedVariantes.add({
        'id_atributo': _selectedAtributoId,
        'atributo_nombre': atributo['denominacion'] ?? 'Sin nombre',
        'precio': precio,
      });
      
      // Limpiar formulario
      _selectedAtributoId = null;
      _variantePrecioController.clear();
    });
  }

  void _eliminarVariante(int index) {
    setState(() {
      _selectedVariantes.removeAt(index);
    });
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
            basePrice: basePrice,
            presentacionesExistentes: _presentacionesAdicionales,
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
              basePrice: basePrice,
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
  final _precioController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    if (widget.initialPresentacion != null) {
      _selectedPresentacionId = widget.initialPresentacion!['id_presentacion'];
      _cantidadController.text = widget.initialPresentacion!['cantidad'].toString();
      _precioController.text = widget.initialPresentacion!['precio']?.toString() ?? '0.0';
    }
    
    _cantidadController.addListener(_calculatePrice);
    
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

    final selectedPresentacion = widget.presentaciones.firstWhere(
      (p) => p['id'] == _selectedPresentacionId,
      orElse: () => {'denominacion': 'Presentación'},
    );

    final presentacion = {
      'id_presentacion': _selectedPresentacionId,
      'denominacion': selectedPresentacion['denominacion'] ?? 'Presentación',
      'cantidad': cantidad,
    };

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
    final basePresentacion = widget.presentaciones.firstWhere(
      (p) => p['id'] == widget.basePresentacionId,
      orElse: () => {'denominacion': 'unidad'},
    );

    final selectedPresentacion = _selectedPresentacionId != null
        ? widget.presentaciones.firstWhere(
            (p) => p['id'] == _selectedPresentacionId,
            orElse: () => {},
          )
        : null;

    final cantidad = double.tryParse(_cantidadController.text) ?? 1;

    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 400,
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
                  .where((p) => p['id'] != widget.basePresentacionId)
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
                setState(() {});
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
                    Icon(Icons.info_outline, color: AppColors.primary, size: 16),
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
