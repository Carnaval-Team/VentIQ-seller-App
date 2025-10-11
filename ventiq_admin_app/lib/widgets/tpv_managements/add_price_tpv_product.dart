import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ventiq_admin_app/models/product.dart';
import '../../config/app_colors.dart';
import '../../services/tpv_price_service.dart';
import '../../services/product_service.dart';
import '../../models/tpv_price.dart';
import 'package:intl/intl.dart';

/// Widget para agregar o editar precios específicos de productos por TPV
class AddPriceTpvProductDialog extends StatefulWidget {
  final int? tpvId;
  final int? productId;
  final TpvPrice? existingPrice; // Para edición
  final VoidCallback onSuccess;

  const AddPriceTpvProductDialog({
    Key? key,
    this.tpvId,
    this.productId,
    this.existingPrice,
    required this.onSuccess,
  }) : super(key: key);

  @override
  State<AddPriceTpvProductDialog> createState() => _AddPriceTpvProductDialogState();
}

class _AddPriceTpvProductDialogState extends State<AddPriceTpvProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _precioController = TextEditingController();
  final _descuentoController = TextEditingController(text: '0');
  final _observacionesController = TextEditingController();
  
  bool _isLoading = false;
  bool _isLoadingData = true;
  
  // Datos
  List<Map<String, dynamic>> _tpvs = [];
  List<Product> _products = [];
  Product? _selectedProduct;
  int? _selectedTpvId;
  
  // Fechas
  DateTime _fechaDesde = DateTime.now();
  DateTime? _fechaHasta;
  
  // Estado
  bool _esActivo = true;
  
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _selectedTpvId = widget.tpvId;
    _loadInitialData();
  }

  @override
  void dispose() {
    _precioController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    
    try {
      // Cargar TPVs disponibles
      final tpvs = await TpvPriceService.getAvailableTpvs(null);
      
      // Cargar productos (simplificado - puedes mejorar con búsqueda)
      final products = await ProductService.getProductsByTienda();
      
      setState(() {
        _tpvs = tpvs;
        _products = products;
        _isLoadingData = false;
      });
      
      // Si hay precio existente, cargar datos
      if (widget.existingPrice != null) {
        _loadExistingPrice();
      }
      
      // Si hay productId pre-seleccionado, buscarlo
      if (widget.productId != null) {
        try {
          _selectedProduct = _products.firstWhere(
            (p) => int.parse(p.id) == widget.productId,
          );
        } catch (e) {
          print('⚠️ Producto pre-seleccionado no encontrado: ${widget.productId}');
        }
      }
    } catch (e) {
      print('❌ Error cargando datos: $e');
      setState(() => _isLoadingData = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _loadExistingPrice() {
    final price = widget.existingPrice!;
    _precioController.text = price.precioVentaCup.toString();
    _fechaDesde = price.fechaDesde;
    _fechaHasta = price.fechaHasta;
    _esActivo = price.esActivo;
    _selectedTpvId = price.idTpv;
  }

  Future<void> _submitPrice() async {
    if (!_formKey.currentState!.validate()) return;

    // Validaciones adicionales
    if (_selectedProduct == null && widget.productId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedTpvId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un TPV'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final productId = widget.productId ?? int.parse(_selectedProduct!.id);
      final precio = double.parse(_precioController.text);

      bool success = false;

      if (widget.existingPrice != null) {
        // Actualizar precio existente
        success = await TpvPriceService.updateTpvPrice(
          priceId: widget.existingPrice!.id!,
          price: precio,
          fechaDesde: _fechaDesde,
          fechaHasta: _fechaHasta,
          esActivo: _esActivo,
        );
      } else {
        // Crear nuevo precio
        final result = await TpvPriceService.createTpvPrice(
          productId: productId,
          tpvId: _selectedTpvId!,
          price: precio,
          fechaDesde: _fechaDesde,
          fechaHasta: _fechaHasta,
        );
        success = result != null;
      }

      setState(() => _isLoading = false);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.existingPrice != null
                    ? 'Precio actualizado exitosamente'
                    : 'Precio creado exitosamente',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
          widget.onSuccess();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al guardar el precio'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _fechaDesde : (_fechaHasta ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('es', 'ES'),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _fechaDesde = picked;
          // Si la fecha hasta es anterior a la nueva fecha desde, limpiarla
          if (_fechaHasta != null && _fechaHasta!.isBefore(_fechaDesde)) {
            _fechaHasta = null;
          }
        } else {
          _fechaHasta = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.existingPrice != null ? Icons.edit : Icons.add_circle,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.existingPrice != null
                          ? 'Editar Precio TPV'
                          : 'Agregar Precio TPV',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoadingData
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Selector de Producto
                            if (widget.productId == null) ...[
                              const Text(
                                'Producto *',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<Product>(
                                value: _selectedProduct,
                                decoration: InputDecoration(
                                  hintText: 'Seleccione un producto',
                                  prefixIcon: const Icon(Icons.inventory_2),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                                isExpanded: true,
                                items: _products.map((product) {
                                  return DropdownMenuItem<Product>(
                                    value: product,
                                    child: Text(
                                      '${product.denominacion} ${product.sku != null && product.sku!.isNotEmpty ? '(${product.sku})' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() => _selectedProduct = value);
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Debe seleccionar un producto';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Selector de TPV
                            const Text(
                              'TPV *',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: _selectedTpvId,
                              decoration: InputDecoration(
                                hintText: 'Seleccione un TPV',
                                prefixIcon: const Icon(Icons.point_of_sale),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              isExpanded: true,
                              items: _tpvs.map((tpv) {
                                return DropdownMenuItem<int>(
                                  value: tpv['id'],
                                  child: Text(
                                    tpv['denominacion'] ?? 'TPV',
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                );
                              }).toList(),
                              onChanged: widget.tpvId == null
                                  ? (value) {
                                      setState(() => _selectedTpvId = value);
                                    }
                                  : null,
                              validator: (value) {
                                if (value == null) {
                                  return 'Debe seleccionar un TPV';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Precio
                            const Text(
                              'Precio de Venta (CUP) *',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _precioController,
                              decoration: InputDecoration(
                                hintText: '0.00',
                                prefixIcon: const Icon(Icons.attach_money),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El precio es obligatorio';
                                }
                                final precio = double.tryParse(value);
                                if (precio == null || precio <= 0) {
                                  return 'Ingrese un precio válido mayor a 0';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Descuento
                            const Text(
                              'Descuento (%)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _descuentoController,
                              decoration: InputDecoration(
                                hintText: '0',
                                prefixIcon: const Icon(Icons.discount),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                              ],
                              validator: (value) {
                                if (value != null && value.isNotEmpty) {
                                  final descuento = double.tryParse(value);
                                  if (descuento == null || descuento < 0 || descuento > 100) {
                                    return 'Ingrese un descuento entre 0 y 100';
                                  }
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Fechas
                            const Text(
                              'Vigencia',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _selectDate(context, true),
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Desde *',
                                        prefixIcon: const Icon(Icons.calendar_today),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey[50],
                                      ),
                                      child: Text(_dateFormat.format(_fechaDesde)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _selectDate(context, false),
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Hasta',
                                        prefixIcon: const Icon(Icons.event),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey[50],
                                        suffixIcon: _fechaHasta != null
                                            ? IconButton(
                                                icon: const Icon(Icons.clear, size: 18),
                                                onPressed: () {
                                                  setState(() => _fechaHasta = null);
                                                },
                                              )
                                            : null,
                                      ),
                                      child: Text(
                                        _fechaHasta != null
                                            ? _dateFormat.format(_fechaHasta!)
                                            : 'Sin límite',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Estado
                            SwitchListTile(
                              title: const Text('Precio activo'),
                              subtitle: Text(
                                _esActivo
                                    ? 'El precio está activo y se aplicará'
                                    : 'El precio está inactivo',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _esActivo ? Colors.green : Colors.grey,
                                ),
                              ),
                              value: _esActivo,
                              onChanged: (value) {
                                setState(() => _esActivo = value);
                              },
                              activeColor: AppColors.success,
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 20),

                            // Observaciones
                            const Text(
                              'Observaciones',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _observacionesController,
                              decoration: InputDecoration(
                                hintText: 'Notas adicionales sobre este precio...',
                                prefixIcon: const Icon(Icons.notes),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              maxLines: 3,
                              maxLength: 500,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submitPrice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            widget.existingPrice != null ? 'Actualizar' : 'Guardar',
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
