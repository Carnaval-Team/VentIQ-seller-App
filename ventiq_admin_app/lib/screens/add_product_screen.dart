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
  final _umController = TextEditingController();
  final _diasAlertController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _precioVentaController = TextEditingController();

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
  List<Map<String, dynamic>> _selectedPresentaciones = []; // Changed to store presentation details

  // Presentation management
  int? _basePresentationId;

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

  // Variables para variantes
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
      _umController.text = widget.product!.um ?? '';
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
    _umController.dispose();
    _diasAlertController.dispose();
    _codigoBarrasController.dispose();
    _precioVentaController.dispose();
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
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      _showErrorSnackBar('Error al cargar datos iniciales: $e');
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

  Future<void> _loadPresentaciones() async {
    try {
      final presentaciones = await ProductService.getPresentaciones();
      setState(() {
        _presentaciones = presentaciones;
      });
    } catch (e) {
      print('Error al cargar presentaciones: $e');
      _showErrorSnackBar('Error al cargar presentaciones: $e');
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
    
    // Agregar código de variante si existe
    if (_selectedVariantes.isNotEmpty) {
      final variante = _selectedVariantes.first;
      if (variante['opciones'] != null && (variante['opciones'] as List).isNotEmpty) {
        final opcion = (variante['opciones'] as List).first;
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
            const SizedBox(height: 16),
            // Precio de Venta
            TextFormField(
              controller: _precioVentaController,
              decoration: const InputDecoration(
                labelText: 'Precio de Venta *',
                hintText: '0.00',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
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
        ),
      ),
    );
  }

  Widget _buildAdvancedFieldsSection() {
    return Column(
      children: [
        // Campos adicionales básicos
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
                        controller: _umController,
                        decoration: const InputDecoration(
                          labelText: 'Unidad de Medida',
                          hintText: 'Ej: kg, lt, und',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descripcionCortaController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción Corta',
                    hintText: 'Descripción breve',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
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
        // Etiquetas
        _buildTagsSection(),
        const SizedBox(height: 16),
        // Multimedia
        _buildMultimediaSection(),
        const SizedBox(height: 16),
        // Presentaciones
        _buildPresentacionesSection(),
        const SizedBox(height: 16),
        // Variantes
        _buildVariantesSection(),
      ],
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Por favor corrija los errores en el formulario');
      return;
    }

    // Validate that at least one presentation is selected
    if (_selectedPresentaciones.isEmpty) {
      _showErrorSnackBar('Debe seleccionar al menos una presentación para el producto');
      return;
    }

    // Validate that there is exactly one base presentation
    final basePresentations = _selectedPresentaciones.where((p) => p['es_base'] == true).toList();
    if (basePresentations.isEmpty) {
      _showErrorSnackBar('Debe marcar una presentación como base');
      return;
    }
    if (basePresentations.length > 1) {
      _showErrorSnackBar('Solo puede haber una presentación base por producto');
      return;
    }

    // Validate that all presentations have valid quantities
    for (var presentacion in _selectedPresentaciones) {
      final cantidad = presentacion['cantidad'];
      if (cantidad == null || cantidad <= 0) {
        _showErrorSnackBar('Todas las presentaciones deben tener una cantidad válida mayor a 0');
        return;
      }
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
        'um': _umController.text,
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
      final presentacionesData =
          _selectedPresentaciones
              .map(
                (presentacion) => {
                  'id_presentacion': presentacion['id'],
                  'cantidad': presentacion['cantidad'] ?? 1, // Cantidad por defecto
                  'es_base': presentacion['es_base'] ?? false, // Primera como base
                },
              )
              .toList();

      // Solo incluir variantes si hay subcategorías seleccionadas (requerido por RPC)
      List<Map<String, dynamic>>? variantesData;
      
      print('🔍 Debug - Variantes seleccionadas: ${_selectedVariantes.length}');
      print('🔍 Debug - Subcategorías seleccionadas: ${_selectedSubcategorias.length}');
      
      if (_selectedVariantes.isNotEmpty && _selectedSubcategorias.isNotEmpty) {
        variantesData = [];
        
        // Crear una variante por cada combinación de subcategoría y atributo
        for (final subcategoriaId in _selectedSubcategorias) {
          for (final variante in _selectedVariantes) {
            variantesData.add({
              'id_sub_categoria': subcategoriaId,
              'id_atributo': variante['id_atributo'],
              'opciones': (variante['opciones'] as List<dynamic>)
                  .map((opcion) {
                    final opcionMap = opcion as Map<String, dynamic>;
                    return {
                      'id_opcion': opcionMap['id'], // ✅ AGREGAR ID DE OPCIÓN EXISTENTE
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
        
        print('🔧 Variantes preparadas para RPC: $variantesData');
      } else {
        print('⚠️ No se crearán variantes - Variantes: ${_selectedVariantes.length}, Subcategorías: ${_selectedSubcategorias.length}');
      }

      // ✅ CORREGIDO: Preparar precios con validación y formato correcto
      final preciosData = <Map<String, dynamic>>[];
      
      // Validar y convertir precio
      double precioVenta = 0.0;
      try {
        final precioText = _precioVentaController.text.trim();
        if (precioText.isEmpty) {
          throw Exception('El precio de venta no puede estar vacío');
        }
        precioVenta = double.parse(precioText);
        if (precioVenta <= 0) {
          throw Exception('El precio debe ser mayor a 0');
        }
      } catch (e) {
        throw Exception('Precio inválido: ${_precioVentaController.text}');
      }
      
      // Formato de fecha correcto para PostgreSQL
      final fechaDesde = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
      
      if (_selectedVariantes.isNotEmpty && _selectedSubcategorias.isNotEmpty) {
        // Crear precios para cada variante creada
        final variantCount = _selectedSubcategorias.length * _selectedVariantes.length;
        for (int i = 0; i < variantCount; i++) {
          preciosData.add({
            'precio_venta_cup': precioVenta, // ✅ Usar variable validada
            'fecha_desde': fechaDesde, // ✅ Formato correcto
            'id_variante': null, // Se asignará después de crear la variante
          });
        }
      } else {
        // Precio base sin variante
        preciosData.add({
          'precio_venta_cup': precioVenta, // ✅ Usar variable validada
          'fecha_desde': fechaDesde, // ✅ Formato correcto
          'id_variante': null,
        });
      }

      // ✅ DEBUG: Imprimir todos los datos antes de enviar
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

  Widget _buildPresentacionesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Presentaciones del Producto',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (_presentaciones.isEmpty)
              const Text(
                'No hay presentaciones disponibles',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected presentations list
                  if (_selectedPresentaciones.isNotEmpty) ...[
                    const Text(
                      'Presentaciones Seleccionadas:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._selectedPresentaciones.map((selectedPres) {
                      final presentacion = _presentaciones.firstWhere(
                        (p) => p['id'] == selectedPres['id'],
                      );
                      final isBase = selectedPres['es_base'] ?? false;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isBase ? AppColors.primary : Colors.grey.shade300,
                            width: isBase ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: isBase ? AppColors.primary.withOpacity(0.1) : Colors.grey.shade50,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        presentacion['denominacion'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isBase ? AppColors.primary : Colors.black87,
                                        ),
                                      ),
                                      if (isBase) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            'BASE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (presentacion['descripcion'] != null)
                                    Text(
                                      presentacion['descripcion'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Quantity input
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                initialValue: selectedPres['cantidad'].toString(),
                                decoration: const InputDecoration(
                                  labelText: 'Cant.',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (value) {
                                  final cantidad = double.tryParse(value) ?? 1;
                                  setState(() {
                                    selectedPres['cantidad'] = cantidad;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Base presentation toggle
                            Column(
                              children: [
                                const Text('Base', style: TextStyle(fontSize: 10)),
                                Checkbox(
                                  value: isBase,
                                  onChanged: (value) {
                                    setState(() {
                                      if (value == true) {
                                        // Remove base flag from all others
                                        for (var pres in _selectedPresentaciones) {
                                          pres['es_base'] = false;
                                        }
                                        // Set this as base
                                        selectedPres['es_base'] = true;
                                        _basePresentationId = selectedPres['id'];
                                      } else {
                                        selectedPres['es_base'] = false;
                                        if (_basePresentationId == selectedPres['id']) {
                                          _basePresentationId = null;
                                        }
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            // Remove button
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  final wasBase = selectedPres['es_base'] ?? false;
                                  _selectedPresentaciones.removeWhere((p) => p['id'] == selectedPres['id']);
                                  if (wasBase) {
                                    _basePresentationId = null;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 16),
                  ],
                  
                  // Available presentations to add
                  const Text(
                    'Presentaciones Disponibles:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presentaciones.map((presentacion) {
                      final isSelected = _selectedPresentaciones.any((p) => p['id'] == presentacion['id']);
                      if (isSelected) return const SizedBox.shrink();
                      
                      return FilterChip(
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(presentacion['denominacion']),
                            if (presentacion['descripcion'] != null)
                              Text(
                                presentacion['descripcion'],
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              final isFirstPresentation = _selectedPresentaciones.isEmpty;
                              _selectedPresentaciones.add({
                                'id': presentacion['id'],
                                'cantidad': 1.0,
                                'es_base': isFirstPresentation, // First one is automatically base
                              });
                              if (isFirstPresentation) {
                                _basePresentationId = presentacion['id'];
                              }
                            });
                          }
                        },
                        selectedColor: AppColors.primary.withOpacity(0.2),
                        checkmarkColor: AppColors.primary,
                      );
                    }).toList(),
                  ),
                ],
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
                const Text(
                  'Variantes del Producto',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton.icon(
                  onPressed: _selectedSubcategorias.isNotEmpty ? _addVariante : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar Variante'),
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
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _opciones.length,
                  itemBuilder: (context, index) {
                    final opcion = _opciones[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        title: Text(opcion['valor']),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () => _removeOpcion(index),
                        ),
                      ),
                    );
                  },
                ),
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
