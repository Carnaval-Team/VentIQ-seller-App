import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/consignacion_service.dart';
import '../widgets/product_selector_widget.dart';
import '../services/product_search_service.dart';

class AsignarProductosConsignacionScreen extends StatefulWidget {
  final int idContrato;
  final Map<String, dynamic> contrato;

  const AsignarProductosConsignacionScreen({
    Key? key,
    required this.idContrato,
    required this.contrato,
  }) : super(key: key);

  @override
  State<AsignarProductosConsignacionScreen> createState() => _AsignarProductosConsignacionScreenState();
}

class _AsignarProductosConsignacionScreenState extends State<AsignarProductosConsignacionScreen> {
  List<Map<String, dynamic>> _productosSeleccionados = [];
  bool _isSaving = false;

  void _addProductoToConsignacion(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => ConsignacionProductQuantityDialog(
        product: product,
        idTiendaConsignadora: widget.contrato['id_tienda_consignadora'],
        onAdd: (productData) {
          setState(() {
            _productosSeleccionados.add(productData);
          });
        },
      ),
    );
  }

  void _removeProduct(int index) {
    setState(() {
      _productosSeleccionados.removeAt(index);
    });
  }

  Future<void> _asignarProductos() async {
    if (_productosSeleccionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final success = await ConsignacionService.asignarProductos(
        idContrato: widget.idContrato,
        productos: _productosSeleccionados,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Productos asignados exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al asignar productos'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asignar Productos en Consignación'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_productosSeleccionados.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Chip(
                  label: Text('${_productosSeleccionados.length}'),
                  backgroundColor: Colors.white,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Información del contrato
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.handshake, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contrato con: ${widget.contrato['tienda_consignataria']['denominacion']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      Text(
                        'Comisión: ${widget.contrato['porcentaje_comision']}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Selector de productos
          Expanded(
            child: ProductSelectorWidget(
              onProductSelected: _addProductoToConsignacion,
              searchHint: 'Buscar productos para consignar...',
              searchType: ProductSearchType.all,
              requireInventory: true,
            ),
          ),

          // Productos seleccionados
          if (_productosSeleccionados.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ExpansionTile(
                    title: Text(
                      'Productos Seleccionados (${_productosSeleccionados.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    children: _productosSeleccionados.asMap().entries.map((entry) {
                      final index = entry.key;
                      final prod = entry.value;

                      return ListTile(
                        title: Text(prod['nombre_producto']),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Presentación: ${prod['presentacion_nombre']}'),
                            if (prod['variante_nombre'] != null)
                              Text('Variante: ${prod['variante_nombre']}'),
                            Text('Cantidad: ${prod['cantidad']} ${prod['presentacion_nombre']}'),
                            if (prod['precio_venta_sugerido'] != null)
                              Text('Precio sugerido: \$${prod['precio_venta_sugerido']}'),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeProduct(index),
                        ),
                      );
                    }).toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _asignarProductos,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(_isSaving ? 'Asignando...' : 'Asignar Productos'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Diálogo para seleccionar cantidad, presentación y variante en consignación
class ConsignacionProductQuantityDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final int idTiendaConsignadora;
  final Function(Map<String, dynamic>) onAdd;

  const ConsignacionProductQuantityDialog({
    Key? key,
    required this.product,
    required this.idTiendaConsignadora,
    required this.onAdd,
  }) : super(key: key);

  @override
  State<ConsignacionProductQuantityDialog> createState() =>
      _ConsignacionProductQuantityDialogState();
}

class _ConsignacionProductQuantityDialogState
    extends State<ConsignacionProductQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();

  List<Map<String, dynamic>> _almacenes = [];
  List<Map<String, dynamic>> _ubicaciones = [];
  List<Map<String, dynamic>> _presentaciones = [];
  List<Map<String, dynamic>> _variantes = [];

  int? _selectedAlmacen;
  int? _selectedUbicacion;
  int? _selectedPresentacion;
  int? _selectedVariante;

  double _stockDisponible = 0;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      debugPrint('📦 Cargando datos para producto: ${widget.product['id_producto']}');
      debugPrint('🏪 Tienda consignadora: ${widget.idTiendaConsignadora}');

      // Cargar almacenes de la tienda
      debugPrint('🔄 Cargando almacenes...');
      final almacenesResponse = await Supabase.instance.client
          .from('app_dat_almacen')
          .select('id, denominacion')
          .eq('id_tienda', widget.idTiendaConsignadora);
      debugPrint('✅ Almacenes cargados: ${almacenesResponse.length}');
      debugPrint('   Datos: $almacenesResponse');

      // Cargar presentaciones del producto
      debugPrint('🔄 Cargando presentaciones...');
      final presentacionesResponse = await Supabase.instance.client
          .from('app_dat_producto_presentacion')
          .select('id, id_presentacion, app_nom_presentacion(denominacion)')
          .eq('id_producto', widget.product['id_producto']);
      debugPrint('✅ Presentaciones cargadas: ${presentacionesResponse.length}');
      debugPrint('   Datos: $presentacionesResponse');

      // Cargar variantes del producto (a través de la relación con atributos)
      debugPrint('🔄 Cargando variantes...');
      final variantesResponse = await Supabase.instance.client
          .from('app_dat_variantes')
          .select('id, app_dat_atributos(denominacion)')
          .eq('id_sub_categoria', widget.product['id_producto']);
      debugPrint('✅ Variantes cargadas: ${variantesResponse.length}');
      debugPrint('   Datos: $variantesResponse');

      setState(() {
        _almacenes = List<Map<String, dynamic>>.from(almacenesResponse);
        _presentaciones = List<Map<String, dynamic>>.from(presentacionesResponse);
        _variantes = List<Map<String, dynamic>>.from(variantesResponse);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando datos: $e');
      setState(() {
        _errorMessage = 'Error cargando datos: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUbicaciones() async {
    if (_selectedAlmacen == null) return;

    try {
      final almacenId = _selectedAlmacen;
      if (almacenId == null) return;

      final response = await Supabase.instance.client
          .from('app_dat_layout_almacen')
          .select('id, denominacion')
          .eq('id_almacen', almacenId);

      setState(() {
        _ubicaciones = List<Map<String, dynamic>>.from(response);
        _selectedUbicacion = null;
        _stockDisponible = 0;
      });
    } catch (e) {
      debugPrint('Error cargando ubicaciones: $e');
    }
  }

  Future<void> _loadStockDisponible() async {
    final ubicacionId = _selectedUbicacion;
    final presentacionId = _selectedPresentacion;

    if (ubicacionId == null || presentacionId == null) {
      setState(() => _stockDisponible = 0);
      return;
    }

    try {
      final responses = await Supabase.instance.client
          .from('app_dat_inventario_productos')
          .select('cantidad_final')
          .eq('id_producto', widget.product['id_producto'])
          .eq('id_presentacion', presentacionId)
          .eq('id_ubicacion', ubicacionId)
          .order('created_at', ascending: false)
          .limit(1);

      if (responses.isNotEmpty) {
        final cantidad = responses[0]['cantidad_final'] as num?;
        setState(() {
          _stockDisponible = cantidad?.toDouble() ?? 0;
        });
      } else {
        setState(() => _stockDisponible = 0);
      }
    } catch (e) {
      debugPrint('Error cargando stock: $e');
      setState(() => _stockDisponible = 0);
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      if (_selectedPresentacion == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debe seleccionar una presentación'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final cantidad = double.tryParse(_quantityController.text) ?? 0;
      final precio = _priceController.text.isEmpty
          ? null
          : double.tryParse(_priceController.text);

      if (cantidad > _stockDisponible) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'La cantidad no puede exceder el stock disponible ($_stockDisponible)',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final presentacionData = _presentaciones.firstWhere(
        (p) => p['id'] == _selectedPresentacion,
      );

      String? nombreVariante;
      if (_selectedVariante != null) {
        final varianteData = _variantes.firstWhere((v) => v['id'] == _selectedVariante);
        final atributo = varianteData['app_dat_atributos'] as Map<String, dynamic>?;
        nombreVariante = atributo?['denominacion'];
      }

      final productData = {
        ...widget.product,
        'id_presentacion': _selectedPresentacion,
        'id_variante': _selectedVariante,
        'presentacion_nombre': presentacionData['app_nom_presentacion']?['denominacion'] ?? 'unidades',
        'variante_nombre': nombreVariante,
        'cantidad': cantidad,
        'precio_venta_sugerido': precio,
      };

      widget.onAdd(productData);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        padding: const EdgeInsets.all(24),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.inventory_2,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Asignar en Consignación',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                widget.product['nombre_producto'] ?? 'Producto',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Form
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Almacén
                          const Text('Almacén', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            value: _selectedAlmacen,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: _almacenes.map((almacen) {
                              return DropdownMenuItem<int>(
                                value: almacen['id'],
                                child: Text(almacen['denominacion']),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() => _selectedAlmacen = value);
                              _loadUbicaciones();
                            },
                            validator: (value) => value == null ? 'Seleccione un almacén' : null,
                          ),
                          const SizedBox(height: 16),

                          // Ubicación
                          if (_ubicaciones.isNotEmpty) ...[
                            const Text('Ubicación/Área', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: _selectedUbicacion,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: _ubicaciones.map((ubicacion) {
                                return DropdownMenuItem<int>(
                                  value: ubicacion['id'],
                                  child: Text(ubicacion['denominacion']),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() => _selectedUbicacion = value);
                                _loadStockDisponible();
                              },
                              validator: (value) => value == null ? 'Seleccione una ubicación' : null,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Presentación
                          const Text('Presentación', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            value: _selectedPresentacion,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: _presentaciones.map((pres) {
                              return DropdownMenuItem<int>(
                                value: pres['id'],
                                child: Text(pres['app_nom_presentacion']?['denominacion'] ?? 'N/A'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() => _selectedPresentacion = value);
                              _loadStockDisponible();
                            },
                            validator: (value) => value == null ? 'Seleccione presentación' : null,
                          ),
                          const SizedBox(height: 16),

                          // Variante
                          if (_variantes.isNotEmpty) ...[
                            const Text('Variante (Opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButton<int>(
                              value: _selectedVariante,
                              isExpanded: true,
                              hint: const Text('Sin variante'),
                              items: [
                                const DropdownMenuItem<int>(
                                  value: null,
                                  child: Text('Sin variante'),
                                ),
                                ..._variantes.map((variante) {
                                  final atributo = variante['app_dat_atributos'] as Map<String, dynamic>?;
                                  final nombreVariante = atributo?['denominacion'] ?? 'Variante ${variante['id']}';
                                  return DropdownMenuItem<int>(
                                    value: variante['id'],
                                    child: Text(nombreVariante),
                                  );
                                }).toList(),
                              ],
                              onChanged: (value) {
                                setState(() => _selectedVariante = value);
                                _loadStockDisponible();
                              },
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Stock
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Stock disponible: $_stockDisponible unidades',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Cantidad
                          TextFormField(
                            controller: _quantityController,
                            decoration: InputDecoration(
                              labelText: 'Cantidad',
                              border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                              prefixIcon: const Icon(Icons.inventory, color: AppColors.primary),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Ingrese cantidad';
                              final cantidad = double.tryParse(value);
                              if (cantidad == null || cantidad <= 0) return 'Cantidad inválida';
                              if (cantidad > _stockDisponible) return 'Excede stock disponible';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Precio
                          TextFormField(
                            controller: _priceController,
                            decoration: InputDecoration(
                              labelText: 'Precio sugerido (Opcional)',
                              border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                              prefixIcon: const Icon(Icons.attach_money, color: AppColors.primary),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                final precio = double.tryParse(value);
                                if (precio == null || precio < 0) return 'Precio inválido';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _submitForm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Agregar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
