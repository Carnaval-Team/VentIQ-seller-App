import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';

class TransferProductQuantityDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final int sourceLayoutId;
  final Function(Map<String, dynamic>) onAdd;

  const TransferProductQuantityDialog({
    Key? key,
    required this.product,
    required this.sourceLayoutId,
    required this.onAdd,
  }) : super(key: key);

  @override
  State<TransferProductQuantityDialog> createState() =>
      _TransferProductQuantityDialogState();
}

class _TransferProductQuantityDialogState
    extends State<TransferProductQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  
  double _stockDisponible = 0;
  bool _isLoadingStock = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadStockDisponible();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadStockDisponible() async {
    try {
      setState(() {
        _isLoadingStock = true;
        _errorMessage = '';
      });

      print('🔍 Cargando stock para:');
      print('   - ID Producto: ${widget.product['id_producto']}');
      print('   - ID Presentación: ${widget.product['id_presentacion']}');
      print('   - ID Ubicación: ${widget.sourceLayoutId}');

      final productId = widget.product['id_producto'] ?? widget.product['id'];
      final presentationId = widget.product['id_presentacion'];

      if (productId == null) {
        print('❌ Error: ID de producto nulo en el diálogo de transferencia');
        setState(() {
          _errorMessage = 'Error: ID de producto no encontrado';
          _isLoadingStock = false;
        });
        return;
      }

      // Consultar el último registro de inventario para este producto/presentación/ubicación
      final responses = await Supabase.instance.client
          .from('app_dat_inventario_productos')
          .select('cantidad_final')
          .eq('id_producto', productId)
          .eq('id_presentacion', presentationId)
          .eq('id_ubicacion', widget.sourceLayoutId)
          .order('created_at', ascending: false)
          .limit(1);

      if (responses.isNotEmpty) {
        final cantidad = responses[0]['cantidad_final'] as num?;
        setState(() {
          _stockDisponible = cantidad?.toDouble() ?? 0;
          _isLoadingStock = false;
        });
        print('✅ Stock cargado: $_stockDisponible');
      } else {
        setState(() {
          _stockDisponible = 0;
          _isLoadingStock = false;
        });
        print('⚠️ No hay stock en esta ubicación');
      }
    } catch (e) {
      print('❌ Error cargando stock: $e');
      setState(() {
        _errorMessage = 'Error al cargar stock: $e';
        _isLoadingStock = false;
      });
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      final cantidad = double.tryParse(_quantityController.text) ?? 0;

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

      final productData = {
        ...widget.product,
        'cantidad': cantidad,
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
                        'Cantidad a Transferir',
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

            // Stock Information
            if (_isLoadingStock)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: AppColors.error, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.success.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stock disponible en origen:',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '$_stockDisponible ${widget.product['presentacion_nombre'] ?? 'unidades'}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),

            // Form
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _quantityController,
                    decoration: InputDecoration(
                      labelText: 'Cantidad a transferir',
                      hintText: 'Ingrese la cantidad',
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: AppColors.primary, width: 2),
                      ),
                      prefixIcon: Icon(
                        Icons.inventory,
                        color: AppColors.primary,
                      ),
                      suffixText:
                          widget.product['presentacion_nombre'] ?? 'unidades',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'La cantidad es obligatoria';
                      }
                      final cantidad = double.tryParse(value);
                      if (cantidad == null || cantidad <= 0) {
                        return 'Ingrese una cantidad válida';
                      }
                      if (cantidad > _stockDisponible) {
                        return 'La cantidad no puede exceder el stock disponible';
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
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Agregar',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
