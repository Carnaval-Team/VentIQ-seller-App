import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../services/openfoodfacts_service.dart';
import 'barcode_scanner_screen.dart';

final _supabase = Supabase.instance.client;

class AddProductScreen extends StatefulWidget {
  final Product? product;
  final VoidCallback? onProductSaved;

  const AddProductScreen({Key? key, this.product, this.onProductSaved})
    : super(key: key);

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _IngredientDialog extends StatefulWidget {
  final Map<String, dynamic>? ingrediente;
  final List<Map<String, dynamic>>? ingredientesExistentes;
  final Function(Map<String, dynamic>) onSave;

  const _IngredientDialog({
    this.ingrediente,
    this.ingredientesExistentes,
    required this.onSave,
  });

  @override
  State<_IngredientDialog> createState() => _IngredientDialogState();
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
  final _unidadMedidaController =
      TextEditingController(); // New controller for unit of measure
  final _diasAlertController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _precioVentaController = TextEditingController();
  final _cantidadPresentacionController = TextEditingController(
    text: '1',
  ); // Controller for presentation quantity
  final _cantidadUnidadMedidaController = TextEditingController(
    text: '1',
  ); // NUEVO CONTROLLER

  // Variables de estado
  bool _isLoading = false;
  bool _isLoadingData = true;
  bool _isLoadingOpenFoodFacts = false;
  bool _showAdvancedConfig =
      false; // Nueva variable para mostrar/ocultar configuración avanzada

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
  // Unidad de medida seleccionada
  int? _selectedUnidadMedidaId;

  // Checkboxes
  bool _esRefrigerado = false;
  bool _esFragil = false;
  bool _esPeligroso = false;
  bool _esVendible = true;
  bool _esComprable = true;
  bool _esInventariable = true;
  bool _esPorLotes = false;

  // Campos para productos elaborados
  bool _esElaborado = false;
  bool _esServicio = false;
  List<Map<String, dynamic>> _ingredientes = [];
  double _costoProduccionCalculado = 0.0;

  // Listas dinámicas
  List<String> _etiquetas = [];
  List<Map<String, dynamic>> _multimedias = [];
  List<Map<String, dynamic>> _presentacionesAdicionales =
      []; // Additional presentations list
  List<Map<String, dynamic>> _selectedPresentaciones =
      []; // Selected presentations list

  // Variantes
  List<Map<String, dynamic>> _selectedVariantes = [];

  // New controllers for variantes
  int? _selectedAtributoId;
  final _variantePrecioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      print('🔄 ===== MODO EDICIÓN - CARGANDO DATOS DEL PRODUCTO =====');
      print('🔍 Producto ID: ${widget.product!.id}');
      print('🔍 Producto nombre: ${widget.product!.denominacion}');

      // Cargar datos básicos del producto
      _skuController.text = widget.product!.sku ?? '';
      _denominacionController.text = widget.product!.denominacion ?? '';
      _nombreComercialController.text = widget.product!.nombreComercial ?? '';
      _denominacionCortaController.text =
          widget.product!.denominacionCorta ?? '';
      _descripcionController.text = widget.product!.description ?? '';
      _descripcionCortaController.text = widget.product!.descripcionCorta ?? '';
      _unidadMedidaController.text = widget.product!.um ?? '';
      _diasAlertController.text =
          widget.product!.diasAlertCaducidad?.toString() ?? '';
      _codigoBarrasController.text = widget.product!.codigoBarras ?? '';

      // Cargar precio de venta desde el modelo Product
      if (widget.product!.basePrice > 0) {
        _precioVentaController.text = widget.product!.basePrice.toString();
        print('✅ Precio base cargado: ${widget.product!.basePrice}');
      } else {
        print('⚠️ Precio base es 0, se cargará desde la base de datos');
      }

      // Cargar propiedades booleanas
      _esRefrigerado = widget.product!.esRefrigerado ?? false;
      _esFragil = widget.product!.esFragil ?? false;
      _esPeligroso = widget.product!.esPeligroso ?? false;
      _esVendible = widget.product!.esVendible ?? true;
      _esComprable = widget.product!.esComprable ?? true;
      _esInventariable = widget.product!.esInventariable ?? true;
      _esPorLotes = widget.product!.esPorLotes ?? false;
      _esElaborado = widget.product!.esElaborado ?? false;
      _esServicio = widget.product!.esServicio ?? false;

      // Cargar listas
      _etiquetas = widget.product!.etiquetas ?? [];
      _multimedias = widget.product!.multimedias ?? [];

      // Cargar presentaciones existentes
      if (widget.product!.presentaciones.isNotEmpty) {
        print(
          '🔍 Cargando presentaciones existentes: ${widget.product!.presentaciones.length}',
        );

        // Buscar la presentación base (es_base = true)
        final presentacionBase = widget.product!.presentaciones.firstWhere(
          (p) => p['es_base'] == true,
          orElse: () => widget.product!.presentaciones.first,
        );

        if (presentacionBase.isNotEmpty) {
          _selectedBasePresentationId = presentacionBase['id_presentacion'];
          _cantidadPresentacionController.text =
              presentacionBase['cantidad']?.toString() ?? '1';
          print(
            '✅ Presentación base cargada: ID ${_selectedBasePresentationId}, cantidad ${presentacionBase['cantidad']}',
          );
        }

        // Cargar presentaciones adicionales (es_base = false)
        _presentacionesAdicionales =
            widget.product!.presentaciones
                .where((p) => p['es_base'] != true)
                .map(
                  (p) => {
                    'id_presentacion': p['id_presentacion'],
                    'denominacion':
                        p['presentacion'] ??
                        p['denominacion'] ??
                        'Presentación',
                    'cantidad': p['cantidad'],
                  },
                )
                .toList();

        print(
          '✅ Presentaciones adicionales cargadas: ${_presentacionesAdicionales.length}',
        );
      }

      print('🔍 Es elaborado: $_esElaborado');
    } else {
      // MODO CREACIÓN - Inicializar valores por defecto para nuevo producto
      print('🆕 ===== MODO CREACIÓN DE NUEVO PRODUCTO =====');
      // Los controladores ya están inicializados con valores por defecto
      // Solo establecer valores por defecto para campos específicos
      _cantidadPresentacionController.text = '1';
      _cantidadUnidadMedidaController.text = '1';
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
    _cantidadUnidadMedidaController.dispose(); // Dispose del nuevo controller
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
        } else {
          // MODO EDICIÓN: Cargar presentación base después de tener las presentaciones disponibles
          _loadBasePresentationForEditing();
          _loadExistingIngredients();
          // MODO EDICIÓN: Cargar categoría y subcategorías
          _loadCategoryAndSubcategoriesForEditing();
        }

        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
      _showErrorSnackBar('Error al cargar datos iniciales: $e');
    }
  }

  /// Carga la presentación base correcta en modo edición
  void _loadBasePresentationForEditing() {
    if (widget.product!.presentaciones.isNotEmpty &&
        _presentaciones.isNotEmpty) {
      print('🔍 Cargando presentación base para edición...');

      // Buscar la presentación base del producto
      final presentacionBase = widget.product!.presentaciones.firstWhere(
        (p) => p['es_base'] == true,
        orElse: () => widget.product!.presentaciones.first,
      );

      if (presentacionBase.isNotEmpty) {
        final idPresentacionProducto = presentacionBase['id_presentacion'];
        print('🔍 ID presentación del producto: $idPresentacionProducto');

        // Buscar la presentación correspondiente en la lista de presentaciones disponibles
        final presentacionDisponible = _presentaciones.firstWhere(
          (p) => p['id'] == idPresentacionProducto,
          orElse: () => <String, dynamic>{},
        );

        if (presentacionDisponible.isNotEmpty) {
          setState(() {
            _selectedBasePresentationId = presentacionDisponible['id'];
            _cantidadPresentacionController.text =
                presentacionBase['cantidad']?.toString() ?? '1';
          });

          print('✅ Presentación base cargada correctamente:');
          print('   - ID: ${_selectedBasePresentationId}');
          print('   - Denominación: ${presentacionDisponible['denominacion']}');
          print('   - Cantidad: ${presentacionBase['cantidad']}');
        } else {
          print(
            '⚠️ No se encontró presentación disponible con ID: $idPresentacionProducto',
          );
          // Fallback: usar la primera presentación disponible
          if (_presentaciones.isNotEmpty) {
            setState(() {
              _selectedBasePresentationId = _presentaciones.first['id'];
              _cantidadPresentacionController.text = '1';
            });
            print(
              '🔄 Usando presentación por defecto: ${_presentaciones.first['denominacion']}',
            );
          }
        }
      }
    }
  }

  /// Carga los ingredientes existentes para productos elaborados en modo edición
  Future<void> _loadExistingIngredients() async {
    if (widget.product == null) return;

    try {
      print('🍽️ Cargando ingredientes existentes para producto elaborado...');

      final ingredientesExistentes = await ProductService.getProductIngredients(
        widget.product!.id,
      );

      if (ingredientesExistentes.isNotEmpty) {
        print('✅ Ingredientes cargados: ${ingredientesExistentes.length}');

        // Convertir los ingredientes al formato esperado por la UI
        final ingredientesFormateados =
            ingredientesExistentes.map((ingrediente) {
              return {
                'id_producto': ingrediente['producto_id'],
                'nombre': ingrediente['producto_nombre'],
                'nombre_producto': ingrediente['producto_nombre'],
                'sku': ingrediente['producto_sku'],
                'imagen': ingrediente['producto_imagen'],
                'cantidad': ingrediente['cantidad_necesaria'],
                'unidad_medida': ingrediente['unidad_medida'],
                'unidad':
                    ingrediente['unidad_medida'], // ✅ Agregar para compatibilidad
                'costo_unitario': 0.0,
                'stock_disponible': 0,
              };
            }).toList();

        setState(() {
          _ingredientes = ingredientesFormateados;
        });

        // Calcular el costo de producción
        _calcularCostoProduccion();

        print('✅ Ingredientes cargados en la UI: ${_ingredientes.length}');
        for (final ingrediente in _ingredientes) {
          print(
            '   - ${ingrediente['nombre_producto']}: ${ingrediente['cantidad']} ${ingrediente['unidad_medida']}',
          );
        }
      } else {
        print('ℹ️ No se encontraron ingredientes para este producto elaborado');
      }
    } catch (e) {
      print('❌ Error cargando ingredientes existentes: $e');
      _showErrorSnackBar('Error al cargar ingredientes: $e');
    }
  }

  /// Carga la categoría y subcategorías en modo edición
  Future<void> _loadCategoryAndSubcategoriesForEditing() async {
    if (widget.product == null) return;

    try {
      print('🏷️ Cargando categoría y subcategorías existentes...');

      // Cargar categoría usando categoryId del producto
      final categoryId = int.tryParse(widget.product!.categoryId);
      if (categoryId != null) {
        setState(() {
          _selectedCategoryId = categoryId;
        });

        print('✅ Categoría cargada: ID $categoryId');

        // Cargar subcategorías de esta categoría
        await _loadSubcategorias(categoryId);

        // Después de cargar las subcategorías, seleccionar las del producto
        if (widget.product!.subcategorias.isNotEmpty) {
          final subcategoriasIds =
              widget.product!.subcategorias
                  .map((sub) => sub['id'] as int?)
                  .where((id) => id != null)
                  .cast<int>()
                  .toList();

          setState(() {
            _selectedSubcategorias = subcategoriasIds;
          });

          print('✅ Subcategorías cargadas: ${subcategoriasIds.length}');
          for (final subcat in widget.product!.subcategorias) {
            print('   - ${subcat['denominacion']} (ID: ${subcat['id']})');
          }
        }
      } else {
        print('⚠️ ID de categoría inválido: ${widget.product!.categoryId}');
      }
    } catch (e) {
      print('❌ Error cargando categoría y subcategorías: $e');
      _showErrorSnackBar('Error al cargar categoría y subcategorías: $e');
    }
  }

  /// Establece valores por defecto para productos nuevos
  void _setDefaultValues() {
    print('🔧 Estableciendo valores por defecto para nuevo producto...');

    // Establecer presentación base por defecto (primera disponible)
    if (_presentaciones.isNotEmpty) {
      _selectedBasePresentationId = _presentaciones.first['id'];
      print(
        '✅ Presentación base por defecto: ${_presentaciones.first['denominacion']}',
      );
    }

    // Establecer unidad de medida por defecto
    _unidadMedidaController.text = 'und'; // Unidad por defecto
    _selectedUnidadMedidaId = 1; // ID por defecto para "unidad"

    // Establecer cantidades por defecto
    _cantidadPresentacionController.text = '1';
    _cantidadUnidadMedidaController.text = '1';

    // Establecer valores booleanos por defecto
    _esVendible = true;
    _esComprable = true;
    _esInventariable = true;
    _esElaborado = false;
    _esServicio = false;
    _esRefrigerado = false;
    _esFragil = false;
    _esPeligroso = false;
    _esPorLotes = false;

    print('✅ Valores por defecto establecidos correctamente');
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
          .substring(
            0,
            categoria['denominacion'].toString().length >= 3
                ? 3
                : categoria['denominacion'].toString().length,
          );
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
          .substring(
            0,
            subcategoria['denominacion'].toString().length >= 2
                ? 2
                : subcategoria['denominacion'].toString().length,
          );
      sku += '-$subCode';
    }

    // Agregar códigos de variantes
    for (var variante in _selectedVariantes) {
      final opciones =
          variante['opciones'] as List<Map<String, dynamic>>? ?? [];
      for (var opcion in opciones.take(1)) {
        // Solo la primera opción
        final varCode = opcion['valor']
            .toString()
            .toUpperCase()
            .replaceAll(RegExp(r'[^A-Z0-9]'), '')
            .substring(
              0,
              opcion['valor'].toString().length >= 2
                  ? 2
                  : opcion['valor'].toString().length,
            );
        sku += '-$varCode';
      }
    }

    // Agregar timestamp para unicidad
    final timestamp = DateTime.now().millisecondsSinceEpoch
        .toString()
        .substring(8);
    sku += '-$timestamp';

    // Actualizar el campo SKU
    setState(() {
      _skuController.text =
          sku.isNotEmpty
              ? sku
              : 'PROD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
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
          items:
              _categorias.map((categoria) {
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
            children:
                _subcategorias.map((subcat) {
                  final isSelected = _selectedSubcategorias.contains(
                    subcat['id'],
                  );
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
            helperText:
                'Este precio se usará como base para calcular precios de presentaciones adicionales',
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configuración de Presentación Base',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Dropdown de presentación
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      value: _selectedBasePresentationId,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de Presentación *',
                        border: OutlineInputBorder(),
                        helperText: '',
                      ),
                      items:
                          _presentaciones.map((presentacion) {
                            return DropdownMenuItem<int>(
                              value: presentacion['id'],
                              child: Text(presentacion['denominacion']),
                            );
                          }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedBasePresentationId = value);
                      },
                      validator:
                          (value) =>
                              value == null
                                  ? 'Seleccione una presentación'
                                  : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Campo de cantidad
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _cantidadPresentacionController,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad *',
                        border: OutlineInputBorder(),
                        helperText: 'Unidades por presentación',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Requerido';
                        final cantidad = double.tryParse(value);
                        if (cantidad == null || cantidad <= 0)
                          return 'Cantidad inválida';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Segunda fila: Unidad de medida y cantidad por unidad
              Row(
                children: [
                  // Dropdown de unidad de medida
                  Expanded(
                    flex: 2,
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: ProductService.getUnidadesMedida(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox(
                            height: 56,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        // DESPUÉS - Código corregido:
                        final unidades = snapshot.data ?? [];
                        if (unidades.isEmpty) {
                          return TextFormField(
                            controller: _unidadMedidaController,
                            decoration: const InputDecoration(
                              labelText: 'Unidad de Medida *',
                              border: OutlineInputBorder(),
                              helperText: '',
                            ),
                            validator:
                                (value) =>
                                    value?.isEmpty == true ? 'Requerido' : null,
                          );
                        }

                        // ✅ DEDUPLICAR POR 'abreviatura' PARA EVITAR DUPLICADOS
                        final uniqueUnidades = <String, Map<String, dynamic>>{};
                        for (final unidad in unidades) {
                          final abreviatura =
                              unidad['abreviatura']?.toString() ?? '';
                          if (abreviatura.isNotEmpty) {
                            uniqueUnidades[abreviatura] = unidad;
                          }
                        }
                        final unidadesLimpias = uniqueUnidades.values.toList();

                        // ✅ VALIDAR QUE EL VALOR ACTUAL EXISTE EN LA LISTA
                        String? currentValue =
                            _unidadMedidaController.text.isNotEmpty
                                ? _unidadMedidaController.text
                                : null;

                        if (currentValue != null &&
                            !unidadesLimpias.any(
                              (u) => u['abreviatura'] == currentValue,
                            )) {
                          currentValue = null;
                          _unidadMedidaController.text = '';
                        }

                        return DropdownButtonFormField<String>(
                          value: currentValue,
                          decoration: const InputDecoration(
                            labelText: 'Unidad de Medida *',
                            helperText: '',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              unidadesLimpias.map((unidad) {
                                return DropdownMenuItem<String>(
                                  value: unidad['abreviatura'],
                                  child: Text(
                                    '${unidad['denominacion']} (${unidad['abreviatura']})',
                                  ),
                                );
                              }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _unidadMedidaController.text = value ?? '';
                              final unidadSeleccionada = unidadesLimpias
                                  .firstWhere(
                                    (unidad) => unidad['abreviatura'] == value,
                                    orElse: () => {'id': 1},
                                  );
                              _selectedUnidadMedidaId =
                                  unidadSeleccionada['id'];
                            });
                          },
                          validator:
                              (value) =>
                                  value == null || value.isEmpty
                                      ? 'Seleccione una unidad'
                                      : null,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Campo de cantidad de unidad de medida
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _cantidadUnidadMedidaController,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad UM *',
                        border: OutlineInputBorder(),
                        helperText: 'Cantidad de UM por presentación',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Requerido';
                        final cantidad = double.tryParse(value);
                        if (cantidad == null || cantidad <= 0)
                          return 'Cantidad inválida';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Información adicional
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'La presentación base define la unidad mínima de venta. Ejemplo: 1 Unidad = 1 und, 1 Caja = 24 und',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      ),
                    ),
                  ],
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
              Icon(Icons.info_outline, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La presentación base define la unidad mínima de venta y será usada como referencia para presentaciones adicionales.',
                  style: TextStyle(fontSize: 12, color: AppColors.primary),
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
                  onPressed:
                      _selectedBasePresentationId != null
                          ? _addPresentacionAdicional
                          : null,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar', style: TextStyle(fontSize: 14)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
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
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.red,
                              size: 20,
                            ),
                            onPressed:
                                () => _removePresentacionAdicional(index),
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
                  onChanged:
                      (value) =>
                          setState(() => _esRefrigerado = value ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Es Frágil'),
                  subtitle: const Text('Requiere manejo especial'),
                  value: _esFragil,
                  onChanged:
                      (value) => setState(() => _esFragil = value ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Es Peligroso'),
                  subtitle: const Text('Producto peligroso o tóxico'),
                  value: _esPeligroso,
                  onChanged:
                      (value) => setState(() => _esPeligroso = value ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Es Vendible'),
                  subtitle: const Text('Disponible para venta'),
                  value: _esVendible,
                  onChanged:
                      (value) => setState(() => _esVendible = value ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Es Comprable'),
                  subtitle: const Text('Se puede comprar a proveedores'),
                  value: _esComprable,
                  onChanged:
                      (value) => setState(() => _esComprable = value ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Es Inventariable'),
                  subtitle: const Text('Se controla en inventario'),
                  value: _esInventariable,
                  onChanged:
                      (value) =>
                          setState(() => _esInventariable = value ?? true),
                ),
                CheckboxListTile(
                  title: const Text('Es Elaborado'),
                  subtitle: const Text('Producto elaborado con ingredientes'),
                  value: _esElaborado,
                  onChanged:
                      (value) => setState(() {
                        _esElaborado = value ?? false;
                        if (!_esElaborado) {
                          _ingredientes.clear();
                          _costoProduccionCalculado = 0.0;
                        }
                      }),
                ),
                CheckboxListTile(
                  title: const Text('Es Servicio'),
                  subtitle: const Text('Servicio brindado'),
                  value: _esServicio,
                  onChanged:
                      (value) => setState(() {
                        _esServicio = value ?? false;
                    if (!_esServicio) {
                      _ingredientes.clear();
                      _costoProduccionCalculado = 0.0;
                    }
                  }),
                ),
                // Sección de ingredientes para productos elaborados
                if (_esElaborado || _esServicio) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Ingredientes',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _agregarIngrediente,
                                icon: const Icon(Icons.add),
                                label: const Text('Agregar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_ingredientes.isEmpty)
                            const Text(
                              'No hay ingredientes agregados',
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _ingredientes.length,
                              itemBuilder: (context, index) {
                                final ingrediente = _ingredientes[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primary
                                          .withOpacity(0.1),
                                      child: Text(
                                        (ingrediente['nombre'] ?? 'I')[0]
                                            .toUpperCase(),
                                        style: TextStyle(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      ingrediente['nombre'] ?? 'Ingrediente',
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Cantidad: ${ingrediente['cantidad']} ${ingrediente['unidad'] ?? 'und'}',
                                        ),
                                        // Mostrar insignia de elaborado en el texto también
                                        if (ingrediente['es_elaborado'] == true)
                                          const Text(
                                            '🍽️ Producto Elaborado',
                                            style: TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          onPressed:
                                              () => _editarIngrediente(index),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed:
                                              () => _eliminarIngrediente(index),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ],
                CheckboxListTile(
                  title: const Text('Es por Lotes'),
                  subtitle: const Text('Se maneja por lotes con fechas'),
                  value: _esPorLotes,
                  onChanged:
                      (value) => setState(() => _esPorLotes = value ?? false),
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
                          suffixIcon:
                              _isLoadingOpenFoodFacts
                                  ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              AppColors.primary,
                                            ),
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
                        onPressed:
                            _isLoadingOpenFoodFacts
                                ? null
                                : _openBarcodeScanner,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child:
                            _isLoadingOpenFoodFacts
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                                : const Icon(Icons.qr_code_scanner, size: 24),
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
      _showErrorSnackBar(
        'La cantidad de presentación debe ser un número válido mayor a 0',
      );
      return;
    }

    if (_precioVentaController.text.isEmpty ||
        double.tryParse(_precioVentaController.text) == null ||
        double.parse(_precioVentaController.text) <= 0) {
      _showErrorSnackBar(
        'El precio de venta debe ser un número válido mayor a 0',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final isEditing = widget.product != null;

      if (isEditing) {
        print('🔄 ===== MODO EDICIÓN =====');
        await _updateProduct();
      } else {
        print('🆕 ===== MODO CREACIÓN =====');
        await _createProduct();
      }
    } catch (e) {
      print('❌ Error en _saveProduct: $e');
      _showErrorSnackBar(
        'Error al ${widget.product != null ? 'actualizar' : 'crear'} producto: $e',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createProduct() async {
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
      'nombre_comercial':
          _nombreComercialController.text.isNotEmpty
              ? _nombreComercialController.text
              : _denominacionController.text,
      'denominacion_corta':
          _denominacionCortaController.text.isNotEmpty
              ? _denominacionCortaController.text
              : _denominacionController.text.substring(
                0,
                _denominacionController.text.length > 20
                    ? 20
                    : _denominacionController.text.length,
              ),
      'descripcion': _descripcionController.text,
      'descripcion_corta': _descripcionCortaController.text,
      'um':
          _unidadMedidaController.text.isNotEmpty
              ? _unidadMedidaController.text
              : 'und',
      'es_refrigerado': _esRefrigerado,
      'es_fragil': _esFragil,
      'es_peligroso': _esPeligroso,
      'es_vendible': _esVendible,
      'es_comprable': _esComprable,
      'es_inventariable': _esInventariable,
      'es_elaborado': _esElaborado,
      'es_servicio': _esServicio,
      'es_por_lotes': _esPorLotes,
      'dias_alert_caducidad':
          _diasAlertController.text.isNotEmpty
              ? int.tryParse(_diasAlertController.text)
              : null,
      'codigo_barras': _codigoBarrasController.text,
    };

    // Preparar subcategorías
    List<Map<String, dynamic>>? subcategoriasData;
    if (_selectedSubcategorias.isNotEmpty) {
      subcategoriasData =
          _selectedSubcategorias.map((id) => {'id_sub_categoria': id}).toList();
    }

    // Preparar etiquetas
    List<Map<String, dynamic>>? etiquetasData;
    if (_etiquetas.isNotEmpty) {
      etiquetasData =
          _etiquetas.map((etiqueta) => {'etiqueta': etiqueta}).toList();
    }

    // Preparar multimedia
    List<Map<String, dynamic>>? multimediasData;
    if (_multimedias.isNotEmpty) {
      multimediasData = _multimedias.map((media) => {'media': media}).toList();
    }

    // Preparar presentaciones (OBLIGATORIO)
    final presentacionesData = [
      {
        'id_presentacion': _selectedBasePresentationId!,
        'cantidad': double.parse(_cantidadPresentacionController.text),
        'es_base': true,
      },
    ];

    // Agregar presentaciones adicionales
    if (_presentacionesAdicionales.isNotEmpty) {
      for (final presentacion in _presentacionesAdicionales) {
        presentacionesData.add({
          'id_presentacion': presentacion['id_presentacion'],
          'cantidad': presentacion['cantidad'],
          'es_base': false,
        });
      }
    }

    // Preparar datos de unidades de medida por presentación
    final presentacionUnidadMedidaData = <Map<String, dynamic>>[];

    print('🔧 ===== PREPARANDO DATOS DE UNIDADES DE MEDIDA =====');
    print('🔧 Presentación base: $_selectedBasePresentationId');
    print('🔧 Unidad de medida: $_selectedUnidadMedidaId');
    print('🔧 Cantidad UM: ${_cantidadUnidadMedidaController.text}');

    if (_selectedUnidadMedidaId != null) {
      final umData = {
        'id_presentacion': _selectedBasePresentationId!,
        'id_unidad_medida': _selectedUnidadMedidaId!,
        'cantidad_um': double.parse(_cantidadUnidadMedidaController.text),
      };
      presentacionUnidadMedidaData.add(umData);
      print('✅ Datos de UM preparados: $umData');
    } else {
      print('⚠️ ADVERTENCIA: No se seleccionó unidad de medida');
    }

    // Preparar precios
    final preciosData = [
      {
        'precio_venta_cup': double.parse(_precioVentaController.text),
        'fecha_desde': DateTime.now().toIso8601String().substring(0, 10),
        'id_variante': null,
      },
    ];

    // Agregar precios por variantes
    if (_selectedVariantes.isNotEmpty) {
      for (final variante in _selectedVariantes) {
        preciosData.add({
          'precio_venta_cup': variante['precio'],
          'fecha_desde': DateTime.now().toIso8601String().substring(0, 10),
          'id_atributo': variante['id_atributo'],
        });
      }
    }

    // DEBUG: Imprimir datos
    print('=== DATOS COMPLETOS ENVIADOS A RPC ===');
    print('PRODUCTO DATA: ${jsonEncode(productoData)}');
    print('PRESENTACIONES DATA: ${jsonEncode(presentacionesData)}');
    print(
      'PRESENTACION UNIDAD MEDIDA DATA: ${jsonEncode(presentacionUnidadMedidaData)}',
    );
    print('=====================================');

    // Insertar producto
    final result = await ProductService.insertProductoCompleto(
      productoData: productoData,
      subcategoriasData: subcategoriasData,
      presentacionesData: presentacionesData,
      etiquetasData: etiquetasData,
      multimediasData: multimediasData,
      preciosData: preciosData,
    );

    if (result == null) {
      throw Exception('No se recibió respuesta del servidor');
    }

    // DEBUG: Imprimir respuesta completa para entender estructura
    print('🔍 RESPUESTA COMPLETA DEL RPC: ${jsonEncode(result)}');
    print('🔍 TIPO DE RESPUESTA: ${result.runtimeType}');
    print('🔍 CLAVES DISPONIBLES: ${result.keys.toList()}');

    // Intentar obtener el ID del producto de diferentes ubicaciones posibles
    int? productId;

    // Opción 1: Directamente en la raíz
    productId = result['producto_id'] as int?;

    // Opción 2: En data
    if (productId == null) {
      final data = result['data'];
      if (data != null && data is Map<String, dynamic>) {
        productId =
            data['producto_id'] as int? ??
            data['id_producto'] as int? ??
            data['id'] as int?;
      }
    }

    // Opción 3: En result
    if (productId == null) {
      final resultData = result['result'];
      if (resultData != null && resultData is Map<String, dynamic>) {
        productId =
            resultData['producto_id'] as int? ??
            resultData['id_producto'] as int? ??
            resultData['id'] as int?;
      }
    }

    // Opción 4: Directamente como id
    if (productId == null) {
      productId = result['id'] as int? ?? result['id_producto'] as int?;
    }

    print('🔍 ID DEL PRODUCTO EXTRAÍDO: $productId');

    if (productId == null) {
      print('❌ ESTRUCTURA DE RESPUESTA NO RECONOCIDA');
      print('❌ Respuesta completa: ${jsonEncode(result)}');
      throw Exception(
        'No se pudo obtener el ID del producto creado. Estructura de respuesta: ${result.keys.toList()}',
      );
    }

    print('✅ Producto creado exitosamente con ID: $productId');

    // Insertar unidades de medida por presentación
    if (presentacionUnidadMedidaData.isNotEmpty) {
      print('🔧 Insertando unidades de medida por presentación...');
      try {
        await ProductService.insertPresentacionUnidadMedida(
          productId: productId,
          presentacionUnidadMedidaData: presentacionUnidadMedidaData,
        );
        print('✅ Unidades de medida insertadas exitosamente');
      } catch (e) {
        print('❌ ERROR insertando unidades de medida: $e');
      }
    }

    // Insertar ingredientes si es elaborado
    if ((_esElaborado || _esServicio) && _ingredientes.isNotEmpty) {
      print('🍽️ Insertando ingredientes...');
      final ingredientesData =
          _ingredientes
              .map(
                (ingrediente) => {
                  'id_producto': ingrediente['id_producto'],
                  'cantidad': ingrediente['cantidad'],
                  'unidad_medida': ingrediente['unidad'],
                },
              )
              .toList();

      try {
        await ProductService.insertProductIngredients(
          productId: productId,
          ingredientes: ingredientesData,
        );
        print('✅ Ingredientes insertados exitosamente');
      } catch (e) {
        print('❌ ERROR insertando ingredientes: $e');
      }
    }

    _showSuccessSnackBar('Producto creado exitosamente');
    if (widget.onProductSaved != null) {
      widget.onProductSaved!();
    }
    Navigator.of(context).pop();
  }

  Future<void> _updateProduct() async {
    final productId = int.tryParse(widget.product!.id);
    if (productId == null) {
      throw Exception('ID de producto inválido');
    }

    print('🔄 ===== ACTUALIZANDO PRODUCTO ID: $productId =====');

    // Obtener ID de tienda
    final userPrefs = UserPreferencesService();
    final idTienda = await userPrefs.getIdTienda();

    if (idTienda == null) {
      throw Exception('No se encontró ID de tienda');
    }

    // Preparar datos del producto para actualización
    final productoData = {
      'id': productId,
      'id_tienda': idTienda,
      'sku': _skuController.text,
      'id_categoria': _selectedCategoryId,
      'denominacion': _denominacionController.text,
      'nombre_comercial':
          _nombreComercialController.text.isNotEmpty
              ? _nombreComercialController.text
              : _denominacionController.text,
      'denominacion_corta':
          _denominacionCortaController.text.isNotEmpty
              ? _denominacionCortaController.text
              : _denominacionController.text.substring(
                0,
                _denominacionController.text.length > 20
                    ? 20
                    : _denominacionController.text.length,
              ),
      'descripcion': _descripcionController.text,
      'descripcion_corta': _descripcionCortaController.text,
      'um':
          _unidadMedidaController.text.isNotEmpty
              ? _unidadMedidaController.text
              : 'und',
      'es_refrigerado': _esRefrigerado,
      'es_fragil': _esFragil,
      'es_peligroso': _esPeligroso,
      'es_vendible': _esVendible,
      'es_comprable': _esComprable,
      'es_inventariable': _esInventariable,
      'es_elaborado': _esElaborado,
      'es_servicio': _esServicio,
      'es_por_lotes': _esPorLotes,
      'dias_alert_caducidad':
          _diasAlertController.text.isNotEmpty
              ? int.tryParse(_diasAlertController.text)
              : null,
      'codigo_barras': _codigoBarrasController.text,
    };

    print('🔄 Datos del producto a actualizar: ${jsonEncode(productoData)}');

    try {
      // Actualizar datos básicos del producto
      await _supabase
          .from('app_dat_producto')
          .update(productoData)
          .eq('id', productId);

      print('✅ Datos básicos del producto actualizados');

      // Actualizar unidades de medida por presentación
      await _updatePresentacionUnidadMedida(productId);

      // Actualizar presentación base si cambió
      if (_selectedBasePresentationId != null) {
        print('🔄 Actualizando presentación base...');

        // Primero, quitar es_base=true de todas las presentaciones
        await _supabase
            .from('app_dat_producto_presentacion')
            .update({'es_base': false})
            .eq('id_producto', productId);

        // Luego, establecer la nueva presentación base
        await _supabase
            .from('app_dat_producto_presentacion')
            .update({
              'es_base': true,
              'cantidad': double.parse(_cantidadPresentacionController.text),
            })
            .eq('id_producto', productId)
            .eq('id_presentacion', _selectedBasePresentationId!);

        print('✅ Presentación base actualizada');
      }

      // Actualizar ingredientes si es producto elaborado
      if ((_esElaborado || _esServicio) && _ingredientes.isNotEmpty) {
        print('🍽️ Actualizando ingredientes...');

        // Eliminar ingredientes existentes
        await _supabase
            .from('app_dat_producto_ingredientes')
            .delete()
            .eq('id_producto_elaborado', productId);

        // Insertar nuevos ingredientes
        final ingredientesData =
            _ingredientes
                .map(
                  (ingrediente) => {
                    'id_producto_elaborado': productId,
                    'id_ingrediente': ingrediente['id_producto'],
                    'cantidad_necesaria': ingrediente['cantidad'],
                    'unidad_medida': ingrediente['unidad'],
                  },
                )
                .toList();

        if (ingredientesData.isNotEmpty) {
          await _supabase
              .from('app_dat_producto_ingredientes')
              .insert(ingredientesData);

          print('✅ Ingredientes actualizados exitosamente');
        }
      } else if (!(_esElaborado || _esServicio)) {
        // Si ya no es elaborado, eliminar todos los ingredientes
        await _supabase
            .from('app_dat_producto_ingredientes')
            .delete()
            .eq('id_producto_elaborado', productId);

        print('✅ Ingredientes eliminados (producto ya no es elaborado)');
      }

      print('✅ Producto actualizado exitosamente');
    } catch (e) {
      print('❌ Error actualizando producto: $e');
      throw Exception('Error actualizando producto: $e');
    }

    _showSuccessSnackBar('Producto actualizado exitosamente');
    if (widget.onProductSaved != null) {
      widget.onProductSaved!();
    }
    Navigator.of(context).pop();
  }

  Future<void> _updatePresentacionUnidadMedida(int productId) async {
    try {
      print('🔧 Actualizando unidades de medida por presentación...');

      // Preparar datos de unidades de medida por presentación
      final presentacionUnidadMedidaData = <Map<String, dynamic>>[];

      print('🔧 ===== PREPARANDO DATOS DE UNIDADES DE MEDIDA =====');
      print('🔧 Presentación base: $_selectedBasePresentationId');
      print('🔧 Unidad de medida: $_selectedUnidadMedidaId');
      print('🔧 Cantidad UM: ${_cantidadUnidadMedidaController.text}');

      if (_selectedUnidadMedidaId != null &&
          _selectedBasePresentationId != null) {
        final umData = {
          'id_presentacion': _selectedBasePresentationId!,
          'id_unidad_medida': _selectedUnidadMedidaId!,
          'cantidad_um': double.parse(_cantidadUnidadMedidaController.text),
        };
        presentacionUnidadMedidaData.add(umData);
        print('✅ Datos de UM preparados: $umData');
      } else {
        print(
          '⚠️ ADVERTENCIA: No se seleccionó unidad de medida o presentación base',
        );
        return;
      }

      // Eliminar registros existentes de unidades de medida por presentación
      await _supabase
          .from('app_dat_presentacion_unidad_medida')
          .delete()
          .eq('id_producto', productId);

      print('🗑️ Registros anteriores de unidades de medida eliminados');

      // Insertar nuevos registros
      if (presentacionUnidadMedidaData.isNotEmpty) {
        // Agregar el id_producto a cada registro
        final dataWithProductId =
            presentacionUnidadMedidaData.map((data) {
              return {...data, 'id_producto': productId};
            }).toList();

        await _supabase
            .from('app_dat_presentacion_unidad_medida')
            .insert(dataWithProductId);

        print(
          '✅ Unidades de medida por presentación actualizadas exitosamente',
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error al actualizar unidades de medida por presentación: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception(
        'Error al actualizar unidades de medida por presentación: $e',
      );
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
          final response = await OpenFoodFactsService.getProductByBarcode(
            result,
          );
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
      builder:
          (context) => AlertDialog(
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
                children:
                    _etiquetas.map((etiqueta) {
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
                children:
                    _multimedias.map((media) {
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

                  // Usamos LayoutBuilder para adaptarnos al ancho disponible
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Para pantallas pequeñas (menos de 600px de ancho), cambiamos a columna
                      if (constraints.maxWidth < 600) {
                        return Column(
                          children: [
                            // Selector de atributo
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Atributo:',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
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
                                      child: Text(
                                        atributo['denominacion'] ?? 'Sin nombre',
                                      ),
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
                            const SizedBox(height: 12),

                            // Campo de precio
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Precio:',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                TextFormField(
                                  controller: _variantePrecioController,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    prefixText: '\$ ',
                                    hintText: '0.00',
                                    isDense: true,
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Botón agregar
                            SizedBox(
                              width: double.infinity, // Ocupa todo el ancho
                              child: ElevatedButton.icon(
                                onPressed: _agregarVariante,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Agregar Variante'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        );
                      } else {
                        // Para pantallas grandes, mantenemos el diseño en fila
                        return Row(
                          children: [
                            // Selector de atributo
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Atributo:',
                                    style: TextStyle(fontWeight: FontWeight.w500),
                                  ),
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
                                        child: Text(
                                          atributo['denominacion'] ?? 'Sin nombre',
                                        ),
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
                                  const Text(
                                    'Precio:',
                                    style: TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 4),
                                  TextFormField(
                                    controller: _variantePrecioController,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      prefixText: '\$ ',
                                      hintText: '0.00',
                                      isDense: true,
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),

                            // Botón agregar
                            Column(
                              children: [
                                const SizedBox(height: 20),
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
                        );
                      }
                    },
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
                        icon: Icon(
                          Icons.delete_outline,
                          color: Colors.red[600],
                        ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selecciona un atributo')));
      return;
    }

    final precio = double.tryParse(_variantePrecioController.text);
    if (precio == null || precio <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ingresa un precio válido')));
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
      _showErrorSnackBar(
        'Debe ingresar un precio de venta base válido antes de agregar presentaciones adicionales',
      );
      return;
    }

    // Validar que existe presentación base seleccionada
    if (_selectedBasePresentationId == null) {
      _showErrorSnackBar(
        'Debe seleccionar una presentación base antes de agregar presentaciones adicionales',
      );
      return;
    }

    // Validar que la cantidad de presentación base es válida
    final baseCantidad = double.tryParse(_cantidadPresentacionController.text);
    if (baseCantidad == null || baseCantidad <= 0) {
      _showErrorSnackBar(
        'Debe ingresar una cantidad válida para la presentación base',
      );
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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
                    const SnackBar(
                      content: Text('Presentación agregada exitosamente'),
                    ),
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
        builder:
            (context) => AlertDialog(
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
                      const SnackBar(
                        content: Text('Presentación actualizada exitosamente'),
                      ),
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
        builder:
            (context) => AlertDialog(
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
                      const SnackBar(
                        content: Text('Presentación eliminada exitosamente'),
                      ),
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

  // Métodos para gestionar ingredientes
  void _agregarIngrediente() {
    print('🔍 DEBUG: _agregarIngrediente llamado');
    print('🔍 DEBUG: _esElaborado: $_esElaborado');
    print('🔍 DEBUG: _esServicio: $_esServicio');
    print('🔍 DEBUG: Lista actual de ingredientes: ${_ingredientes.length}');

    showDialog(
      context: context,
      builder:
          (context) => _IngredientDialog(
            ingrediente: null, // Nuevo ingrediente vacío
            ingredientesExistentes: _ingredientes,
            onSave: (ingrediente) {
              print('🔍 DEBUG: onSave callback ejecutado');
              print('🔍 DEBUG: Ingrediente recibido: $ingrediente');

              setState(() {
                _ingredientes.add(ingrediente); // Agregar nuevo ingrediente
                _calcularCostoProduccion();
              });

              print(
                '🔍 DEBUG: Ingrediente agregado. Total: ${_ingredientes.length}',
              );
            },
          ),
    );
  }

  void _editarIngrediente(int index) {
    showDialog(
      context: context,
      builder:
          (context) => _IngredientDialog(
            ingrediente: _ingredientes[index],
            ingredientesExistentes:
                _ingredientes
                    .where((ing) => ing != _ingredientes[index])
                    .toList(),
            onSave: (ingrediente) {
              setState(() {
                _ingredientes[index] = ingrediente;
                _calcularCostoProduccion();
              });
            },
          ),
    );
  }

  void _eliminarIngrediente(int index) {
    setState(() {
      _ingredientes.removeAt(index);
      _calcularCostoProduccion();
    });
  }

  void _calcularCostoProduccion() {
    _costoProduccionCalculado = _ingredientes.fold(0.0, (total, ingrediente) {
      final cantidad = ingrediente['cantidad'] ?? 0.0;
      final costo = ingrediente['costo_unitario'] ?? 0.0;
      return total + (cantidad * costo);
    });
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

class _IngredientDialogState extends State<_IngredientDialog> {
  final _formKey = GlobalKey<FormState>();
  final _cantidadController = TextEditingController();

  // Variables para selección de producto
  List<Map<String, dynamic>> _productosDisponibles = [];
  Map<String, dynamic>? _productoSeleccionado;
  bool _isLoadingProducts = true;
  String _searchQuery = '';

  // Variables para unidades de medida
  List<Map<String, dynamic>> _unidadesMedida = [];
  Map<String, dynamic>? _unidadSeleccionada;
  bool _isLoadingUnidades = true;

  @override
  void initState() {
    super.initState();
    _loadProductosDisponibles();
    _loadUnidadesMedida();

    if (widget.ingrediente != null) {
      _cantidadController.text =
          widget.ingrediente!['cantidad']?.toString() ?? '';

      // ✅ NO inicializar _productoSeleccionado aquí
      // Se inicializará después de cargar la lista real
      print(
        '🔄 Modo edición - ID producto: ${widget.ingrediente!['id_producto']}',
      );

      // Buscar la unidad seleccionada por abreviatura
      final unidadAbrev = widget.ingrediente!['unidad_medida'] ?? 'und';
      _unidadSeleccionada = {
        'abreviatura': unidadAbrev,
        'denominacion': unidadAbrev,
      };
    }
  }

  Future<void> _loadProductosDisponibles() async {
    try {
      print('🔍 ===== INICIANDO CARGA DE PRODUCTOS PARA INGREDIENTES =====');
      setState(() => _isLoadingProducts = true);

      final productos = await ProductService.getProductsForIngredients();
      print('📦 Productos recibidos del servicio: ${productos.length}');

      // DEBUG: Mostrar detalles de los primeros 3 productos
      if (productos.isNotEmpty) {
        print('🔍 ===== ANÁLISIS DE PRODUCTOS RECIBIDOS =====');
        for (int i = 0; i < productos.length && i < 3; i++) {
          final producto = productos[i];
          print('--- Producto ${i + 1} ---');
          print('ID: ${producto['id']}');
          print('Denominación: ${producto['denominacion']}');
          print('SKU: ${producto['sku']}');
          print('Es elaborado: ${producto['es_elaborado']}');
          print(
            'Precio venta: ${producto['precio_venta']} (tipo: ${producto['precio_venta'].runtimeType})',
          );
          print(
            'Stock disponible: ${producto['stock_disponible']} (tipo: ${producto['stock_disponible'].runtimeType})',
          );
          print('Imagen: ${producto['imagen']}');
          print('Claves disponibles: ${producto.keys.toList()}');
          print('---');
        }
        print('=======================================');
      } else {
        print('❌ No se recibieron productos del servicio');
      }

      setState(() {
        _productosDisponibles = productos;
        _isLoadingProducts = false;

        // ✅ SINCRONIZAR PRODUCTO SELECCIONADO CON LA LISTA REAL
        if (widget.ingrediente != null && _productoSeleccionado != null) {
          final idProducto = widget.ingrediente!['id_producto'];

          // Buscar el producto real en la lista cargada
          final productoReal = productos.firstWhere(
            (p) => p['id'] == idProducto,
            orElse: () => <String, dynamic>{},
          );

          if (productoReal.isNotEmpty) {
            _productoSeleccionado = productoReal;
            print('✅ Producto sincronizado: ${productoReal['denominacion']}');
          } else {
            print('❌ No se encontró el producto con ID: $idProducto');
            _productoSeleccionado = null;
          }
        }
      });

      print(
        '✅ Productos cargados en el estado: ${_productosDisponibles.length}',
      );
    } catch (e) {
      print('❌ Error cargando productos para ingredientes: $e');
      print('📍 Stack trace: ${StackTrace.current}');
      setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _loadUnidadesMedida() async {
    try {
      setState(() => _isLoadingUnidades = true);

      final unidades = await ProductService.getUnidadesMedida();

      // ✅ DEDUPLICAR POR 'abreviatura' PARA EVITAR DUPLICADOS
      final uniqueUnidades = <String, Map<String, dynamic>>{};
      for (final unidad in unidades) {
        final abreviatura = unidad['abreviatura']?.toString() ?? '';
        if (abreviatura.isNotEmpty) {
          uniqueUnidades[abreviatura] = unidad;
        }
      }
      final unidadesLimpias = uniqueUnidades.values.toList();

      setState(() {
        _unidadesMedida = unidadesLimpias;
        _isLoadingUnidades = false;

        // ✅ VALIDAR QUE LA UNIDAD SELECCIONADA EXISTE EN LA LISTA LIMPIA
        if (_unidadSeleccionada != null) {
          final abrevActual = _unidadSeleccionada!['abreviatura'];
          final existeEnLista = unidadesLimpias.any(
            (u) => u['abreviatura'] == abrevActual,
          );
          if (!existeEnLista) {
            _unidadSeleccionada =
                unidadesLimpias.isNotEmpty ? unidadesLimpias.first : null;
          }
        } else if (unidadesLimpias.isNotEmpty) {
          _unidadSeleccionada = unidadesLimpias.first;
        }
      });
    } catch (e) {
      print('Error cargando unidades de medida: $e');
      setState(() => _isLoadingUnidades = false);
    }
  }

  List<Map<String, dynamic>> get _productosFiltrados {
    if (_searchQuery.isEmpty) return _productosDisponibles;

    return _productosDisponibles.where((producto) {
      final denominacion = (producto['denominacion'] ?? '').toLowerCase();
      final sku = (producto['sku'] ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      return denominacion.contains(query) || sku.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.ingrediente == null
            ? 'Agregar Ingrediente'
            : 'Editar Ingrediente',
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.of(context).size.height *
              0.8, // Aumentado de 0.6 a 0.8
          maxWidth: MediaQuery.of(context).size.width * 0.85,
          minHeight: 400, // Aumentado de 300 a 400
        ),
        child: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selector de producto
                  const Text(
                    'Seleccionar Producto:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Campo de búsqueda
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar producto...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Lista de productos con estado de carga mejorado
                  if (_isLoadingProducts) ...[
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(height: 8),
                            Text('Cargando productos...'),
                          ],
                        ),
                      ),
                    ),
                  ] else if (_productosFiltrados.isEmpty) ...[
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text('No se encontraron productos disponibles'),
                      ),
                    ),
                  ] else ...[
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _productosFiltrados.length,
                        itemBuilder: (context, index) {
                          final producto = _productosFiltrados[index];
                          final isSelected =
                              _productoSeleccionado?['id'] == producto['id'];

                          return ListTile(
                            selected: isSelected,
                            leading: Stack(
                              children: [
                                CircleAvatar(
                                  backgroundImage:
                                      producto['imagen'] != null &&
                                              producto['imagen'].isNotEmpty
                                          ? NetworkImage(producto['imagen'])
                                          : null,
                                  child:
                                      producto['imagen'] == null ||
                                              producto['imagen'].isEmpty
                                          ? const Icon(Icons.inventory_2)
                                          : null,
                                ),
                                if (producto['es_elaborado'] == true)
                                  Positioned(
                                    top: -2,
                                    right: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.restaurant,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: Text(
                              producto['denominacion'] ?? 'Sin nombre',
                              style: TextStyle(
                                fontWeight:
                                    isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('SKU: ${producto['sku'] ?? 'N/A'}'),
                                if (producto['es_elaborado'] == true)
                                  const Text(
                                    '🍽️ Producto Elaborado',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () {
                              print(
                                '🔍 Producto seleccionado: ${producto['denominacion']}',
                              );
                              setState(() => _productoSeleccionado = producto);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Información del producto seleccionado (MANTENER SOLO UNA VERSIÓN)
                  if (_productoSeleccionado != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Producto Seleccionado:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            _productoSeleccionado!['denominacion'] ??
                                'Sin nombre',
                          ),
                          Text(
                            'ID: ${_productoSeleccionado!['id']} | SKU: ${_productoSeleccionado!['sku'] ?? 'N/A'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Campos de cantidad y unidad
                  const SizedBox(height: 12),

                  // Campo de cantidad (fila separada)
                  TextFormField(
                    controller: _cantidadController,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad *',
                      border: OutlineInputBorder(),
                      hintText: 'Ej: 2.5',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Requerido';
                      }
                      final cantidad = double.tryParse(value);
                      if (cantidad == null || cantidad <= 0) {
                        return 'Cantidad inválida';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // Campo de unidad de medida (fila separada)
                  _isLoadingUnidades
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<Map<String, dynamic>>(
                        value: _unidadSeleccionada,
                        decoration: const InputDecoration(
                          labelText: 'Unidad de Medida *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items:
                            _unidadesMedida.map((unidad) {
                              return DropdownMenuItem<Map<String, dynamic>>(
                                value: unidad,
                                child: Text(
                                  '${unidad['abreviatura']} - ${unidad['denominacion']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _unidadSeleccionada = value;
                          });
                        },
                        validator:
                            (value) =>
                                value == null ? 'Seleccione una unidad' : null,
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              (_productoSeleccionado == null || _unidadSeleccionada == null)
                  ? null
                  : () {
                    if (_formKey.currentState!.validate()) {
                      // Verificar si el producto ya está agregado (solo para nuevos ingredientes)
                      if (widget.ingrediente == null) {
                        final productosExistentes =
                            widget.ingredientesExistentes ?? [];
                        final productoYaExiste = productosExistentes.any(
                          (ing) =>
                              ing['id_producto']?.toString() ==
                              _productoSeleccionado!['id']?.toString(),
                        );

                        if (productoYaExiste) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Este producto ya está agregado como ingrediente',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                      }

                      // En el botón de guardar del diálogo, agrega logs antes de llamar widget.onSave:
                      final ingrediente = {
                        'id_producto': _productoSeleccionado!['id'],
                        'nombre': _productoSeleccionado!['denominacion'],
                        'cantidad': double.parse(_cantidadController.text),
                        'unidad_medida': _unidadSeleccionada!['abreviatura'],
                      };

                      print('💾 ===== GUARDANDO INGREDIENTE =====');
                      print('💾 Datos del ingrediente: $ingrediente');
                      print('💾 ================================');

                      widget.onSave(ingrediente);
                      Navigator.of(context).pop();
                    }
                  },
          // ... resto del botón
          //),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  double _calcularCostoTotal() {
    return 0.0;
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    super.dispose();
  }
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
      _cantidadController.text =
          widget.initialPresentacion!['cantidad'].toString();
      _precioController.text =
          widget.initialPresentacion!['precio']?.toString() ?? '0.0';
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
        const SnackBar(
          content: Text('Por favor ingresa una cantidad válida mayor a 0'),
        ),
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

    if (widget.presentacionesExistentes != null &&
        widget.presentacionesExistentes!.any(
          (p) => p['id_presentacion'] == presentacion['id_presentacion'],
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ya existe una presentación con el mismo ID'),
        ),
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

    final selectedPresentacion =
        _selectedPresentacionId != null
            ? widget.presentaciones.firstWhere(
              (p) => p['id'] == _selectedPresentacionId,
              orElse: () => {},
            )
            : null;

    final cantidad = double.tryParse(_cantidadController.text) ?? 1;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 400),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccionar Presentación:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _selectedPresentacionId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Selecciona una presentación',
              ),
              items:
                  widget.presentaciones
                      .where((p) => p['id'] != widget.basePresentacionId)
                      .map((presentacion) {
                        return DropdownMenuItem<int>(
                          value: presentacion['id'],
                          child: Text(
                            presentacion['denominacion'] ?? 'Sin nombre',
                          ),
                        );
                      })
                      .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPresentacionId = value;
                });
              },
              validator:
                  (value) =>
                      value == null ? 'Seleccione una presentación' : null,
            ),
            const SizedBox(height: 16),

            const Text(
              'Cantidad de unidades base por presentación:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _precioController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixText: '\$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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
                    Icon(
                      Icons.info_outline,
                      color: AppColors.primary,
                      size: 16,
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
