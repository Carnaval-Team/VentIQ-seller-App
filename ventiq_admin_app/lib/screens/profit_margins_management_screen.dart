import 'package:flutter/material.dart';
import '../services/financial_service.dart';

class ProfitMarginsManagementScreen extends StatefulWidget {
  const ProfitMarginsManagementScreen({Key? key}) : super(key: key);

  @override
  State<ProfitMarginsManagementScreen> createState() => _ProfitMarginsManagementScreenState();
}

class _ProfitMarginsManagementScreenState extends State<ProfitMarginsManagementScreen> {
  final FinancialService _financialService = FinancialService();
  List<Map<String, dynamic>> _margins = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final margins = await _financialService.getProfitMargins();
      
      // Agrupar márgenes por producto
      final Map<int, List<Map<String, dynamic>>> groupedMargins = {};
      for (final margin in margins) {
        final productId = margin['id_producto'] as int;
        if (!groupedMargins.containsKey(productId)) {
          groupedMargins[productId] = [];
        }
        groupedMargins[productId]!.add(margin);
      }
      
      // Crear lista agrupada con el margen más reciente por producto
      final List<Map<String, dynamic>> processedMargins = [];
      groupedMargins.forEach((productId, productMargins) {
        // Ordenar por fecha_desde descendente para obtener el más reciente
        productMargins.sort((a, b) {
          final dateA = DateTime.tryParse(a['fecha_desde'] ?? '') ?? DateTime(1900);
          final dateB = DateTime.tryParse(b['fecha_desde'] ?? '') ?? DateTime(1900);
          return dateB.compareTo(dateA);
        });
        
        // Agregar información de agrupación
        final mainMargin = Map<String, dynamic>.from(productMargins.first);
        mainMargin['total_margins'] = productMargins.length;
        mainMargin['all_margins'] = productMargins;
        
        // Contar márgenes activos (fecha_hasta es null)
        final activeMargins = productMargins.where((m) => m['fecha_hasta'] == null).length;
        mainMargin['active_margins'] = activeMargins;
        
        // Determinar si el margen principal está activo
        mainMargin['is_main_active'] = mainMargin['fecha_hasta'] == null;
        
        processedMargins.add(mainMargin);
      });
      
      setState(() {
        _margins = processedMargins;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando datos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Márgenes Comerciales'),
        backgroundColor: Colors.red[800],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _margins.length,
              itemBuilder: (context, index) {
                final margin = _margins[index];
                final isActive = margin['fecha_hasta'] == null;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    title: Text(
                      margin['producto_nombre'] ?? 'Producto ${margin['id_producto']}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 4),
                        if (margin['variante_nombre'] != null)
                          Text(
                            'Variante: ${margin['variante_nombre']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        Text(
                          'Margen: ${margin['margen_deseado']}% (${margin['tipo_margen'] == 1 ? 'Porcentaje' : 'Valor fijo'})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          'Total: ${margin['total_margins']} | Activos: ${margin['active_margins']}',
                          style: TextStyle(
                            fontSize: 11, 
                            color: (margin['active_margins'] as int) > 0 ? Colors.green[700] : Colors.grey[600]
                          ),
                        ),
                      ],
                    ),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: (margin['active_margins'] as int) > 0 ? Colors.green : Colors.grey,
                      child: Text(
                        '${margin['active_margins']}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    trailing: SizedBox(
                      width: 100,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add, size: 20),
                            color: Colors.blue,
                            onPressed: () => _showAddDialogForProduct(margin['id_producto']),
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                          PopupMenuButton<String>(
                            padding: const EdgeInsets.all(4),
                            iconSize: 20,
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _showEditDialog(margin);
                                  break;
                                case 'deactivate':
                                  if (margin['fecha_hasta'] == null) {
                                    _deactivateMargin(margin['id']);
                                  }
                                  break;
                                case 'delete':
                                  _confirmDelete(margin['id']);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, color: Colors.blue, size: 16),
                                    SizedBox(width: 8),
                                    Text('Editar', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                              if (margin['fecha_hasta'] == null)
                                const PopupMenuItem(
                                  value: 'deactivate',
                                  child: Row(
                                    children: [
                                      Icon(Icons.stop, color: Colors.orange, size: 16),
                                      SizedBox(width: 8),
                                      Text('Desactivar', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red, size: 16),
                                    SizedBox(width: 8),
                                    Text('Eliminar', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Historial de Márgenes:',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            ...(margin['all_margins'] as List<Map<String, dynamic>>)
                                .map((m) => _buildMarginHistoryItem(m))
                                .toList(),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        backgroundColor: Colors.red[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => _MarginDialog(
        onSaved: _loadData,
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> margin) {
    showDialog(
      context: context,
      builder: (context) => _MarginDialog(
        margin: margin,
        onSaved: _loadData,
      ),
    );
  }

  void _deactivateMargin(int id) async {
    try {
      await _financialService.deactivateProfitMargin(id);
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Margen desactivado exitosamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error desactivando margen: $e')),
      );
    }
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Margen'),
        content: const Text('¿Está seguro de eliminar este margen comercial?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _financialService.deleteProfitMargin(id);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Margen eliminado exitosamente')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error eliminando margen: $e')),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddDialogForProduct(int productId) {
    showDialog(
      context: context,
      builder: (context) => _MarginDialog(
        productId: productId,
        onSaved: _loadData,
      ),
    );
  }

  Widget _buildMarginHistoryItem(Map<String, dynamic> margin) {
    final isActive = margin['fecha_hasta'] == null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isActive ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive ? Colors.green[200]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Margen: ${margin['margen_deseado']}% (${margin['tipo_margen'] == 1 ? 'Porcentaje' : 'Valor fijo'})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive ? Colors.green[800] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Desde: ${margin['fecha_desde']}${margin['fecha_hasta'] != null ? ' - Hasta: ${margin['fecha_hasta']}' : ' (Activo)'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive ? Colors.green[600] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'ACTIVO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MarginDialog extends StatefulWidget {
  final Map<String, dynamic>? margin;
  final int? productId;
  final VoidCallback onSaved;

  const _MarginDialog({
    this.margin,
    this.productId,
    required this.onSaved,
  });

  @override
  State<_MarginDialog> createState() => _MarginDialogState();
}

class _MarginDialogState extends State<_MarginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _marginController = TextEditingController();
  final FinancialService _financialService = FinancialService();
  
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _variants = [];
  int? _selectedProductId;
  int? _selectedVariantId;
  int _marginType = 1; // 1 = porcentaje, 2 = valor fijo
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    if (widget.margin != null) {
      _selectedProductId = widget.margin!['id_producto'];
      _selectedVariantId = widget.margin!['id_variante'];
      _marginController.text = widget.margin!['margen_deseado'].toString();
      _marginType = widget.margin!['tipo_margen'];
    } else if (widget.productId != null) {
      _selectedProductId = widget.productId;
    }
  }

  Future<void> _loadProducts() async {
    try {
      // Cargar productos (necesitarás implementar este método en FinancialService)
      final products = await _financialService.getProducts();
      setState(() {
        _products = products;
        _isLoading = false;
      });
      
      if (_selectedProductId != null) {
        _loadVariants(_selectedProductId!);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando productos: $e')),
      );
    }
  }

  Future<void> _loadVariants(int productId) async {
    try {
      // Cargar variantes del producto (necesitarás implementar este método)
      final variants = await _financialService.getProductVariants(productId);
      setState(() {
        _variants = variants;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando variantes: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.margin != null;
    
    if (_isLoading) {
      return const AlertDialog(
        content: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return AlertDialog(
      title: Text(isEditing ? 'Editar Margen' : 'Nuevo Margen'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: _selectedProductId,
                decoration: const InputDecoration(labelText: 'Producto'),
                items: _products.map((product) {
                  return DropdownMenuItem<int>(
                    value: product['id'],
                    child: Text(
                      product['denominacion'] ?? 'Producto ${product['id']}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList(),
                onChanged: isEditing ? null : (value) {
                  setState(() {
                    _selectedProductId = value;
                    _selectedVariantId = null;
                    _variants = [];
                  });
                  if (value != null) {
                    _loadVariants(value);
                  }
                },
                validator: (value) => value == null ? 'Seleccione un producto' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: _selectedVariantId,
                decoration: const InputDecoration(labelText: 'Variante (Opcional)'),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('Sin variante específica'),
                  ),
                  ..._variants.map((variant) {
                    return DropdownMenuItem<int>(
                      value: variant['id'],
                      child: Text(
                        variant['denominacion'] ?? 'Variante ${variant['id']}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                ],
                onChanged: isEditing ? null : (value) {
                  setState(() => _selectedVariantId = value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                isExpanded: true,
                value: _marginType,
                decoration: const InputDecoration(labelText: 'Tipo de Margen'),
                items: const [
                  DropdownMenuItem<int>(
                    value: 1,
                    child: Text('Porcentaje'),
                  ),
                  DropdownMenuItem<int>(
                    value: 2,
                    child: Text('Valor Fijo'),
                  ),
                ],
                onChanged: (value) => setState(() => _marginType = value!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _marginController,
                decoration: InputDecoration(
                  labelText: _marginType == 1 ? 'Margen (%)' : 'Margen (Valor)',
                  suffixText: _marginType == 1 ? '%' : '\$',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty == true) return 'Requerido';
                  final number = double.tryParse(value!);
                  if (number == null) return 'Ingrese un número válido';
                  if (number <= 0) return 'Debe ser mayor a 0';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final marginValue = double.parse(_marginController.text);
      
      if (widget.margin != null) {
        await _financialService.updateProfitMargin(
          productId: _selectedProductId!,
          variantId: _selectedVariantId,
          marginDesired: marginValue,
          marginType: _marginType,
        );
      } else {
        await _financialService.createProfitMargin(
          productId: _selectedProductId!,
          variantId: _selectedVariantId,
          marginDesired: marginValue,
          marginType: _marginType,
        );
      }
      
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Margen ${widget.margin != null ? 'actualizado' : 'creado'} exitosamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
