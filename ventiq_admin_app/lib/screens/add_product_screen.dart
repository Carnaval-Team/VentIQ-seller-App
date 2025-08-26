import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({Key? key}) : super(key: key);

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
  
  // Datos para dropdowns
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _subcategorias = [];
  List<Map<String, dynamic>> _presentaciones = [];
  List<Map<String, dynamic>> _atributos = [];
  
  // Selecciones
  int? _selectedCategoryId;
  List<int> _selectedSubcategorias = [];
  List<int> _selectedPresentaciones = [];
  
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
  List<String> _multimedias = [];
  
  // Variables para variantes
  List<Map<String, dynamic>> _selectedVariantes = [];
  
  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Agregar Producto',
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
            onPressed: _isLoading ? null : _saveProduct,
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
      body: _isLoadingData
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
                  _buildBasicInfoSection(),
                  const SizedBox(height: 24),
                  _buildCategorySection(),
                  const SizedBox(height: 24),
                  _buildPropertiesSection(),
                  const SizedBox(height: 24),
                  _buildPricingSection(),
                  const SizedBox(height: 24),
                  _buildTagsSection(),
                  const SizedBox(height: 24),
                  _buildMultimediaSection(),
                  const SizedBox(height: 24),
                  _buildPresentacionesSection(),
                  const SizedBox(height: 24),
                  _buildVariantesSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información Básica',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _skuController,
              decoration: const InputDecoration(
                labelText: 'SKU *',
                hintText: 'Código único del producto',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'El SKU es requerido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _denominacionController,
              decoration: const InputDecoration(
                labelText: 'Denominación *',
                hintText: 'Nombre completo del producto',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'La denominación es requerida';
                }
                return null;
              },
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
              controller: _descripcionController,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Descripción detallada del producto',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
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
            TextFormField(
              controller: _codigoBarrasController,
              decoration: const InputDecoration(
                labelText: 'Código de Barras',
                hintText: 'Código de barras del producto',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Categorización',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
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
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPropertiesSection() {
    return Card(
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
    );
  }

  Widget _buildPricingSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Precio de Venta',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _precioVentaController,
              decoration: const InputDecoration(
                labelText: 'Precio de Venta *',
                hintText: '0.00',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
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
                    title: Text(media),
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
                  setState(() => _multimedias.add(controller.text));
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

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) {
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
        'descripcion': _descripcionController.text,
        'descripcion_corta': _descripcionCortaController.text,
        'um': _umController.text,
        'es_refrigerado': _esRefrigerado,
        'es_fragil': _esFragil,
        'es_peligroso': _esPeligroso,
        'es_vendible': _esVendible,
        'es_comprable': _esComprable,
        'es_inventariable': _esInventariable,
        'es_por_lotes': _esPorLotes,
        'dias_alert_caducidad': _diasAlertController.text.isNotEmpty 
            ? int.tryParse(_diasAlertController.text) 
            : null,
        'codigo_barras': _codigoBarrasController.text,
      };

      // Preparar subcategorías
      final subcategoriasData = _selectedSubcategorias.map((id) => {
        'id_sub_categoria': id,
      }).toList();

      // Preparar etiquetas
      final etiquetasData = _etiquetas.map((etiqueta) => {
        'etiqueta': etiqueta,
      }).toList();

      // Preparar multimedia
      final multimediasData = _multimedias.map((media) => {
        'media': media,
      }).toList();

      // Preparar presentaciones
      final presentacionesData = _selectedPresentaciones.map((id) => {
        'id_presentacion': id,
        'cantidad': 1, // Cantidad por defecto
        'es_base': _selectedPresentaciones.indexOf(id) == 0, // Primera como base
      }).toList();

      // Solo incluir variantes si hay subcategorías seleccionadas (requerido por RPC)
      List<Map<String, dynamic>>? variantesData;
      if (_selectedVariantes.isNotEmpty && _selectedSubcategorias.isNotEmpty) {
        variantesData = _selectedVariantes.map((variante) => {
          'id_sub_categoria': _selectedSubcategorias.first, // Usar primera subcategoría
          'id_atributo': variante['id_atributo'],
          'opciones': variante['opciones'].map((opcion) => {
            'valor': opcion['valor'],
            'sku_codigo': '${_skuController.text}-${opcion['valor']}'.replaceAll(' ', ''),
          }).toList(),
        }).toList();
      }

      // Preparar precios
      final preciosData = [{
        'precio_venta_cup': double.parse(_precioVentaController.text),
        'fecha_desde': DateTime.now().toIso8601String().split('T')[0],
      }];

      // Insertar producto
      final result = await ProductService.insertProductoCompleto(
        productoData: productoData,
        subcategoriasData: subcategoriasData.isNotEmpty ? subcategoriasData : null,
        presentacionesData: presentacionesData.isNotEmpty ? presentacionesData : null,
        etiquetasData: etiquetasData.isNotEmpty ? etiquetasData : null,
        multimediasData: multimediasData.isNotEmpty ? multimediasData : null,
        variantesData: variantesData,
        preciosData: preciosData,
      );

      // Mostrar éxito y regresar
      _showSuccessSnackBar('Producto creado exitosamente');
      Navigator.pop(context, true); // true indica que se creó un producto

    } catch (e) {
      _showErrorSnackBar('Error al crear producto: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presentaciones.map((presentacion) {
                  final isSelected = _selectedPresentaciones.contains(presentacion['id']);
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
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedPresentaciones.add(presentacion['id']);
                        } else {
                          _selectedPresentaciones.remove(presentacion['id']);
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
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
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
        },
      ),
    );
  }
}

class _VarianteDialog extends StatefulWidget {
  final List<Map<String, dynamic>> atributos;
  final Map<String, dynamic>? initialVariante;
  final Function(Map<String, dynamic>) onSave;

  const _VarianteDialog({
    required this.atributos,
    this.initialVariante,
    required this.onSave,
  });

  @override
  State<_VarianteDialog> createState() => _VarianteDialogState();
}

class _VarianteDialogState extends State<_VarianteDialog> {
  int? _selectedAtributoId;
  List<Map<String, dynamic>> _selectedOpciones = [];
  List<Map<String, dynamic>> _availableOpciones = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialVariante != null) {
      _selectedAtributoId = widget.initialVariante!['id_atributo'];
      _selectedOpciones = List<Map<String, dynamic>>.from(widget.initialVariante!['opciones']);
      _loadOpciones(_selectedAtributoId!);
    }
  }

  void _loadOpciones(int atributoId) {
    final atributo = widget.atributos.firstWhere((a) => a['id'] == atributoId);
    setState(() {
      _availableOpciones = List<Map<String, dynamic>>.from(
        atributo['app_dat_atributo_opcion'] ?? []
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialVariante == null ? 'Agregar Variante' : 'Editar Variante'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: _selectedAtributoId,
              decoration: const InputDecoration(
                labelText: 'Atributo',
                border: OutlineInputBorder(),
              ),
              items: widget.atributos.map((atributo) {
                return DropdownMenuItem<int>(
                  value: atributo['id'],
                  child: Text(atributo['denominacion']),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedAtributoId = value;
                  _selectedOpciones.clear();
                });
                if (value != null) {
                  _loadOpciones(value);
                }
              },
            ),
            const SizedBox(height: 16),
            if (_availableOpciones.isNotEmpty) ...[
              const Text(
                'Opciones disponibles:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _availableOpciones.map((opcion) {
                    final isSelected = _selectedOpciones.any((o) => o['id'] == opcion['id']);
                    return CheckboxListTile(
                      title: Text(opcion['valor']),
                      value: isSelected,
                      onChanged: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedOpciones.add(opcion);
                          } else {
                            _selectedOpciones.removeWhere((o) => o['id'] == opcion['id']);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _selectedAtributoId != null && _selectedOpciones.isNotEmpty
              ? () {
                  final atributo = widget.atributos.firstWhere((a) => a['id'] == _selectedAtributoId);
                  final variante = {
                    'id_atributo': _selectedAtributoId,
                    'atributo_nombre': atributo['denominacion'],
                    'opciones': _selectedOpciones,
                  };
                  widget.onSave(variante);
                  Navigator.pop(context);
                }
              : null,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
