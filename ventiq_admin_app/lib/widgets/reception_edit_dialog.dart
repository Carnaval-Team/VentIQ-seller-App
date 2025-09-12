import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../services/product_service.dart';

class ReceptionEditDialog extends StatefulWidget {
  final String operationId;
  final Map<String, dynamic> operationData;
  final VoidCallback? onUpdated;

  const ReceptionEditDialog({
    Key? key,
    required this.operationId,
    required this.operationData,
    this.onUpdated,
  }) : super(key: key);

  @override
  State<ReceptionEditDialog> createState() => _ReceptionEditDialogState();
}

class _ReceptionEditDialogState extends State<ReceptionEditDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  
  // Expansion states for collapsible sections
  bool _invoiceExpanded = false;
  bool _operationExpanded = false;
  
  // Controladores para campos de la operación
  late TextEditingController _entregadoPorController;
  late TextEditingController _recibidoPorController;
  late TextEditingController _montoTotalController;
  late TextEditingController _observacionesController;
  late TextEditingController _numeroFacturaController;
  late TextEditingController _montoFacturaController;
  late TextEditingController _observacionesCompraController;
  
  DateTime? _fechaFactura;
  String _monedaFactura = 'USD';
  
  // Lista de productos con sus controladores
  List<Map<String, dynamic>> _productos = [];
  Map<String, Map<String, TextEditingController>> _productControllers = {};

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadOperationDetails();
  }

  void _initializeControllers() {
    final operation = widget.operationData;
    
    _entregadoPorController = TextEditingController(text: operation['entregado_por'] ?? '');
    _recibidoPorController = TextEditingController(text: operation['recibido_por'] ?? '');
    _montoTotalController = TextEditingController(text: operation['monto_total']?.toString() ?? '');
    _observacionesController = TextEditingController(text: operation['observaciones'] ?? '');
    _numeroFacturaController = TextEditingController(text: operation['numero_factura'] ?? '');
    _montoFacturaController = TextEditingController(text: operation['monto_factura']?.toString() ?? '');
    _observacionesCompraController = TextEditingController(text: operation['observaciones_compra'] ?? '');
    
    if (operation['fecha_factura'] != null) {
      _fechaFactura = DateTime.tryParse(operation['fecha_factura']);
    }
    
    _monedaFactura = operation['moneda_factura'] ?? 'USD';
  }

  Future<void> _loadOperationDetails() async {
    setState(() => _isLoading = true);
    
    try {
      final details = await ProductService.getReceptionOperationDetails(widget.operationId);
      
      if (details != null && details['app_dat_recepcion_productos'] != null) {
        _productos = List<Map<String, dynamic>>.from(details['app_dat_recepcion_productos']);
        
        // Inicializar controladores para cada producto
        for (var producto in _productos) {
          final productId = producto['id_producto'].toString();
          _productControllers[productId] = {
            'precio_unitario': TextEditingController(text: producto['precio_unitario']?.toString() ?? '0'),
            'precio_referencia': TextEditingController(text: producto['precio_referencia']?.toString() ?? '0'),
            'descuento_porcentaje': TextEditingController(text: producto['descuento_porcentaje']?.toString() ?? '0'),
            'descuento_monto': TextEditingController(text: producto['descuento_monto']?.toString() ?? '0'),
            'bonificacion_cantidad': TextEditingController(text: producto['bonificacion_cantidad']?.toString() ?? '0'),
          };
        }
      }
    } catch (e) {
      print('Error al cargar detalles: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar los detalles de la operación')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _entregadoPorController.dispose();
    _recibidoPorController.dispose();
    _montoTotalController.dispose();
    _observacionesController.dispose();
    _numeroFacturaController.dispose();
    _montoFacturaController.dispose();
    _observacionesCompraController.dispose();
    
    // Dispose product controllers
    for (var controllers in _productControllers.values) {
      for (var controller in controllers.values) {
        controller.dispose();
      }
    }
    
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaFactura ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      setState(() {
        _fechaFactura = picked;
      });
    }
  }

  double _calculateTotalCost(Map<String, dynamic> producto) {
    final productId = producto['id_producto'].toString();
    final controllers = _productControllers[productId];
    if (controllers == null) return 0.0;
    
    final precioUnitario = double.tryParse(controllers['precio_unitario']!.text) ?? 0.0;
    final descuentoPorcentaje = double.tryParse(controllers['descuento_porcentaje']!.text) ?? 0.0;
    final descuentoMonto = double.tryParse(controllers['descuento_monto']!.text) ?? 0.0;
    final cantidad = producto['cantidad'] ?? 0;
    
    double subtotal = precioUnitario * cantidad;
    double descuentoTotal = (subtotal * descuentoPorcentaje / 100) + descuentoMonto;
    return subtotal - descuentoTotal;
  }

  // Helper method to detect mobile screen size
  bool _isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  // Helper method to create responsive row/column layout
  Widget _buildResponsiveLayout(BuildContext context, List<Widget> children, {double spacing = 16}) {
    if (_isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children
            .expand((child) => [child, SizedBox(height: spacing)])
            .take(children.length * 2 - 1)
            .toList(),
      );
    } else {
      return Row(
        children: children
            .expand((child) => [Expanded(child: child), SizedBox(width: spacing)])
            .take(children.length * 2 - 1)
            .toList(),
      );
    }
  }

  // Special method for product badges that need to wrap properly
  Widget _buildProductBadges(BuildContext context, Map<String, dynamic> productInfo, Map<String, dynamic> producto) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'SKU: ${productInfo?['sku'] ?? 'N/A'}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue[700],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Cantidad: ${producto['cantidad']}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.green[700],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Preparar datos de productos
      List<Map<String, dynamic>> productosData = [];
      
      for (var producto in _productos) {
        final productId = producto['id_producto'].toString();
        final controllers = _productControllers[productId];
        
        if (controllers != null) {
          productosData.add({
            'id_producto': producto['id_producto'],
            'precio_unitario': double.tryParse(controllers['precio_unitario']!.text) ?? 0,
            'precio_referencia': double.tryParse(controllers['precio_referencia']!.text) ?? 0,
            'descuento_porcentaje': double.tryParse(controllers['descuento_porcentaje']!.text) ?? 0,
            'descuento_monto': double.tryParse(controllers['descuento_monto']!.text) ?? 0,
            'bonificacion_cantidad': double.tryParse(controllers['bonificacion_cantidad']!.text) ?? 0,
          });
        }
      }
      
      final result = await ProductService.updateReceptionOperation(
        operationId: widget.operationId,
        entregadoPor: _entregadoPorController.text.isNotEmpty ? _entregadoPorController.text : null,
        recibidoPor: _recibidoPorController.text.isNotEmpty ? _recibidoPorController.text : null,
        montoTotal: _montoTotalController.text.isNotEmpty ? double.tryParse(_montoTotalController.text) : null,
        observaciones: _observacionesController.text.isNotEmpty ? _observacionesController.text : null,
        numeroFactura: _numeroFacturaController.text.isNotEmpty ? _numeroFacturaController.text : null,
        fechaFactura: _fechaFactura,
        montoFactura: _montoFacturaController.text.isNotEmpty ? double.tryParse(_montoFacturaController.text) : null,
        monedaFactura: _monedaFactura,
        observacionesCompra: _observacionesCompraController.text.isNotEmpty ? _observacionesCompraController.text : null,
        productosData: productosData.isNotEmpty ? productosData : null,
      );
      
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Operación actualizada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        
        widget.onUpdated?.call();
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Error al actualizar la operación'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.edit, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  'Editar Recepción',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            SizedBox(height: 16),
            
            if (_isLoading)
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // PRIORITY 1: Products Section (Always visible)
                        _buildProductsSection(),
                        SizedBox(height: 20),
                        
                        // PRIORITY 2: Invoice Section (Collapsible but prominent)
                        _buildCollapsibleInvoiceSection(),
                        SizedBox(height: 16),
                        
                        // PRIORITY 3: Operation Details (Collapsible)
                        _buildCollapsibleOperationSection(),
                      ],
                    ),
                  ),
                ),
              ),
            
            // Actions
            if (!_isLoading)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancelar'),
                  ),
                  SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('Guardar Cambios'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsSection() {
    if (_productos.isEmpty) {
      return Card(
        elevation: 4,
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No hay productos en esta operación',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.inventory_2, color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Text(
              'Productos (${_productos.length})',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        ..._productos.map((producto) => _buildPriorityProductCard(producto)).toList(),
      ],
    );
  }

  Widget _buildPriorityProductCard(Map<String, dynamic> producto) {
    final productId = producto['id_producto'].toString();
    final controllers = _productControllers[productId];
    final productInfo = producto['app_dat_producto'];
    
    if (controllers == null) return SizedBox.shrink();

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 3,
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Header - Prominent
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2, color: AppColors.primary, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productInfo?['denominacion'] ?? 'Producto',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(height: 4),
                        _buildProductBadges(context, productInfo, producto),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            
            // PRIORITY: Purchase Price - Most Important
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Precio de Compra',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: controllers['precio_unitario'],
                    decoration: InputDecoration(
                      labelText: 'Precio Unitario de Compra',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'El precio de compra es obligatorio';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            
            // Cost Summary - Calculated in real time
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Costo Total:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '\$${_calculateTotalCost(producto).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            
            // Advanced Product Options - Collapsible
            ExpansionTile(
              title: Text(
                'Opciones Avanzadas',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              leading: Icon(Icons.settings, color: AppColors.primary),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Reference Price
                      TextFormField(
                        controller: controllers['precio_referencia'],
                        decoration: InputDecoration(
                          labelText: 'Precio de Referencia',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                        ],
                      ),
                      SizedBox(height: 12),
                      
                      // Discount fields - Responsive
                      _buildResponsiveLayout(
                        context,
                        [
                          TextFormField(
                            controller: controllers['descuento_porcentaje'],
                            decoration: InputDecoration(
                              labelText: 'Descuento %',
                              suffixText: '%',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                            ],
                          ),
                          TextFormField(
                            controller: controllers['descuento_monto'],
                            decoration: InputDecoration(
                              labelText: 'Descuento Fijo',
                              prefixText: '\$ ',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                            ],
                          ),
                        ],
                        spacing: 12,
                      ),
                      SizedBox(height: 12),
                      
                      // Bonus
                      TextFormField(
                        controller: controllers['bonificacion_cantidad'],
                        decoration: InputDecoration(
                          labelText: 'Bonificación (cantidad extra)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsibleInvoiceSection() {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              'Datos de Factura',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        subtitle: Text(
          _numeroFacturaController.text.isNotEmpty 
              ? 'Factura: ${_numeroFacturaController.text}'
              : 'Toque para agregar información de factura',
          style: TextStyle(fontSize: 12),
        ),
        initiallyExpanded: _invoiceExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            _invoiceExpanded = expanded;
          });
        },
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildResponsiveLayout(
                  context,
                  [
                    TextFormField(
                      controller: _numeroFacturaController,
                      decoration: InputDecoration(
                        labelText: 'Número de Factura',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.receipt),
                      ),
                    ),
                    InkWell(
                      onTap: _selectDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Fecha de Factura',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _fechaFactura != null
                              ? '${_fechaFactura!.day}/${_fechaFactura!.month}/${_fechaFactura!.year}'
                              : 'Seleccionar fecha',
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                _buildResponsiveLayout(
                  context,
                  [
                    TextFormField(
                      controller: _montoFacturaController,
                      decoration: InputDecoration(
                        labelText: 'Monto de Factura',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                    ),
                    DropdownButtonFormField<String>(
                      value: _monedaFactura,
                      decoration: InputDecoration(
                        labelText: 'Moneda',
                        border: OutlineInputBorder(),
                      ),
                      items: ['USD', 'EUR', 'COP', 'MXN'].map((currency) {
                        return DropdownMenuItem(
                          value: currency,
                          child: Text(currency),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _monedaFactura = value ?? 'USD';
                        });
                      },
                    ),
                  ],
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _observacionesCompraController,
                  decoration: InputDecoration(
                    labelText: 'Observaciones de Compra',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleOperationSection() {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey[600]),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Detalles de Operación',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Información adicional de la recepción',
          style: TextStyle(fontSize: 12),
        ),
        initiallyExpanded: _operationExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            _operationExpanded = expanded;
          });
        },
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildResponsiveLayout(
                  context,
                  [
                    TextFormField(
                      controller: _entregadoPorController,
                      decoration: InputDecoration(
                        labelText: 'Entregado por',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    TextFormField(
                      controller: _recibidoPorController,
                      decoration: InputDecoration(
                        labelText: 'Recibido por',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                _buildResponsiveLayout(
                  context,
                  [
                    TextFormField(
                      controller: _montoTotalController,
                      decoration: InputDecoration(
                        labelText: 'Monto Total de Operación',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                    ),
                    TextFormField(
                      controller: _observacionesController,
                      decoration: InputDecoration(
                        labelText: 'Observaciones Generales',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note_alt),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
