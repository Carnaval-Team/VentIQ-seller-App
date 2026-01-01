import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../models/inventory.dart';
import '../services/warehouse_service.dart';
import '../services/inventory_service.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/conversion_info_widget.dart';
import '../widgets/product_selector_widget.dart';
import '../widgets/location_selector_widget.dart';
import '../services/product_search_service.dart';
import '../utils/presentation_converter.dart';

class InventoryExtractionScreen extends StatefulWidget {
  const InventoryExtractionScreen({super.key});

  @override
  State<InventoryExtractionScreen> createState() =>
      _InventoryExtractionScreenState();
}

class _InventoryExtractionScreenState extends State<InventoryExtractionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _autorizadoPorController = TextEditingController();
  final _observacionesController = TextEditingController();

  // Static variables to persist field values
  static String _lastAutorizadoPor = '';
  static String _lastObservaciones = '';

  List<Map<String, dynamic>> _selectedProducts = [];
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  WarehouseZone? _selectedSourceLocation;
  bool _isLoading = false;
  bool _isLoadingMotivos = true;

  @override
  void initState() {
    super.initState();
    _loadMotivoOptions();
    _loadPersistedValues();
  }

  void _loadPersistedValues() {
    _autorizadoPorController.text = _lastAutorizadoPor;
    _observacionesController.text = _lastObservaciones;
  }

  void _savePersistedValues() {
    _lastAutorizadoPor = _autorizadoPorController.text;
    _lastObservaciones = _observacionesController.text;
  }

  @override
  void dispose() {
    _autorizadoPorController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _addProductToExtraction(Map<String, dynamic> product) {
    // Validar que hay zona seleccionada
    if (_selectedSourceLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar una zona primero'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Asegurar que el producto tiene el campo 'id' (puede venir como 'id_producto')
    final productWithId = Map<String, dynamic>.from(product);
    if (productWithId['id'] == null && productWithId['id_producto'] != null) {
      productWithId['id'] = productWithId['id_producto'];
    }

    showDialog(
      context: context,
      builder:
          (context) => _ProductQuantityDialog(
            product: productWithId,
            sourceLocation: _selectedSourceLocation,
            onProductAdded: (productData) {
              setState(() {
                _selectedProducts.add(productData);
              });
            },
          ),
    );
  }

  void _removeProductFromExtraction(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
    });
  }

  void _showExtractionConfirmation() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              'Confirmar Extracción',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ubicación origen
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: AppColors.warning.withOpacity(0.7),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Zona de Origen:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _selectedSourceLocation?.name ??
                                    'No seleccionada',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Lista de productos
                  const Text(
                    'Productos a Extraer:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ..._selectedProducts.map((productData) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productData['denominacion'] ??
                                productData['nombre_producto'] ??
                                'Sin nombre',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (productData['variante'] != null &&
                              productData['variante'].toString().isNotEmpty)
                            Text(
                              'Variante: ${productData['variante']}',
                              style: TextStyle(
                                color: AppColors.warning.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          if (productData['presentacion'] != null &&
                              productData['presentacion'].toString().isNotEmpty)
                            Text(
                              'Presentación: ${productData['presentacion']}',
                              style: TextStyle(
                                color: AppColors.warning.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          Text(
                            'Cantidad: ${productData['cantidad']}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Zona: ${productData['zona_nombre']}',
                            style: TextStyle(
                              color: AppColors.warning.withOpacity(0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 16),

                  // Motivo y autorizado por
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.warning.withOpacity(0.7),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Información Adicional:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Motivo: ${_selectedMotivo?['denominacion'] ?? 'No seleccionado'}',
                        ),
                        Text(
                          'Autorizado por: ${_autorizadoPorController.text.isEmpty ? 'No especificado' : _autorizadoPorController.text}',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _submitExtraction();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                ),
                child: const Text('Confirmar Extracción'),
              ),
            ],
          ),
    );
  }

  Future<void> _submitExtraction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar al menos un producto')),
      );
      return;
    }
    if (_selectedSourceLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar una zona de origen')),
      );
      return;
    }
    if (_selectedMotivo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un motivo de extracción'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    _savePersistedValues();

    try {
      final userPrefs = UserPreferencesService();
      final userUuid = await userPrefs.getUserId();
      final userData = await userPrefs.getUserData();
      final idTienda = userData['idTienda'] as int?;

      if (userUuid == null || idTienda == null) {
        throw Exception('No se encontró información del usuario o tienda');
      }

      // Prepare products list for the RPC
      final productos =
          _selectedProducts.map((product) {
            // Validar que id_presentacion no sea null
            final idPresentacion = product['id_presentacion'];
            if (idPresentacion == null) {
              print(
                '⚠️ Producto sin id_presentacion: ${product['denominacion']}',
              );
              print('⚠️ Datos del producto: $product');
            }

            return {
              'id_producto': product['id_producto'],
              'id_variante': product['id_variante'],
              'id_opcion_variante': product['id_opcion_variante'],
              'id_ubicacion': product['id_ubicacion'],
              'id_presentacion':
                  idPresentacion ?? 1, // Fallback a 1 (Unidad base)
              'cantidad': product['cantidad'],
              'precio_unitario': product['precio_unitario'],
              'sku_producto': product['sku_producto'],
              'sku_ubicacion': product['sku_ubicacion'],
            };
          }).toList();

      final result = await InventoryService.insertCompleteExtraction(
        autorizadoPor: _autorizadoPorController.text.trim(),
        estadoInicial: 1, // 2 = Confirmado (completed immediately)
        idMotivoOperacion: _selectedMotivo!['id'],
        idTienda: idTienda,
        observaciones: _observacionesController.text.trim(),
        productos: productos,
        uuid: userUuid,
      );

      if (result['status'] != 'success') {
        throw Exception(result['message'] ?? 'Error desconocido');
      }

      final operationId = result['id_operacion'];
      print('✅ Extracción registrada con ID: $operationId');

      // Complete the operation after successful extraction
      if (operationId != null) {
        try {
          print('🔄 Iniciando completar operación...');
          print('📊 ID Operación: $operationId');
          print('👤 UUID Usuario: $userUuid');

          final completeResult = await InventoryService.completeOperation(
            idOperacion: operationId,
            comentario:
                'Extracción completada automáticamente - ${_observacionesController.text.trim()}',
            uuid: userUuid,
          );

          print('📋 Resultado completeOperation: $completeResult');

          if (completeResult['status'] == 'success') {
            print('✅ Operación completada exitosamente');
            print(
              '📊 Productos afectados: ${completeResult['productos_afectados']}',
            );
          } else {
            print(
              '⚠️ Advertencia al completar operación: ${completeResult['message']}',
            );
            print('🔍 Detalles del error: $completeResult');
          }
        } catch (completeError, stackTrace) {
          print('❌ Error al completar operación: $completeError');
          print('📍 StackTrace completo: $stackTrace');
          // Don't throw here - extraction was successful, completion is secondary
        }
      } else {
        print('⚠️ No se obtuvo ID de operación para completar');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Extracción registrada exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar extracción: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMotivoOptions() async {
    setState(() => _isLoadingMotivos = true);

    try {
      // Load extraction motives from Supabase database
      _motivoOptions = await InventoryService.getMotivoExtraccionOptions();

      setState(() => _isLoadingMotivos = false);
    } catch (e) {
      print('Error loading motivo options: $e');
      setState(() => _isLoadingMotivos = false);
    }
  }

  Widget _buildExtractionInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detalles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Motivo
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedMotivo,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                border: OutlineInputBorder(),
              ),
              items:
                  _motivoOptions.map((motivo) {
                    return DropdownMenuItem(
                      value: motivo,
                      child: Text(motivo['denominacion'] ?? ''),
                    );
                  }).toList(),
              onChanged: (motivo) {
                setState(() => _selectedMotivo = motivo);
              },
              validator: (value) {
                if (value == null) return 'Campo requerido';
                return null;
              },
            ),

            const SizedBox(height: 12),

            // Autorizado por
            TextFormField(
              controller: _autorizadoPorController,
              decoration: const InputDecoration(
                labelText: 'Autorizado por',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Campo requerido';
                }
                return null;
              },
            ),

            const SizedBox(height: 12),

            // Observaciones
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSelectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /*const Text(
              'Seleccionar Ubicación',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),*/
/*
            const SizedBox(height: 16),
*/
            LocationSelectorWidget(
              type: LocationSelectorType.single,
              title: 'Seleccionar Zona',
              subtitle: 'Desde donde se extraerán los productos',
              selectedLocation: _selectedSourceLocation,
              onLocationChanged: (location) {
                setState(() {
                  _selectedSourceLocation = location;
                  _selectedProducts.clear();
                });
              },
              validationMessage:
                  _selectedSourceLocation == null
                      ? 'Debe seleccionar una zona'
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSelectionSection() {
    final isEnabled = _selectedSourceLocation != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccionar Productos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (!isEnabled)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Seleccione una zona de origen para ver productos disponibles',
                        style: TextStyle(color: Colors.orange[700]),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 300,
                child: ProductSelectorWidget(
                  key: ValueKey('product_selector_${_selectedSourceLocation!.id}'), // Key única por ubicación
                  searchType: ProductSearchType.withStock,
                  requireInventory: true,
                  locationId: int.tryParse(_selectedSourceLocation!.id),
                  searchHint:
                  'Buscar productos en ${_selectedSourceLocation!.name}...',
                  onProductSelected: _addProductToExtraction,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: AppColors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Selected products summary
          if (_selectedProducts.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Productos Seleccionados: ${_selectedProducts.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                      if (_selectedProducts.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedProducts.clear();
                            });
                          },
                          icon: Icon(
                            Icons.clear_all,
                            size: 16,
                            color: AppColors.warning.withOpacity(0.6),
                          ),
                          label: Text(
                            'Limpiar',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.warning.withOpacity(0.6),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Lista expandible de productos
                  ...(_selectedProducts.length <= 3
                          ? _selectedProducts
                          : _selectedProducts.take(2).toList())
                      .asMap()
                      .entries
                      .map((entry) {
                        final index = entry.key;
                        final product = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.warning.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product['denominacion'] ??
                                          product['nombre_producto'] ??
                                          'Sin nombre',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.warning.withOpacity(
                                          0.7,
                                        ),
                                      ),
                                    ),
                                    if (product['zona_nombre'] != null)
                                      Text(
                                        'Zona: ${product['zona_nombre']}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.warning.withOpacity(
                                            0.5,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      'Cant: ${product['cantidad']}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.warning.withOpacity(
                                          0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed:
                                    () => _removeProductFromExtraction(index),
                                icon: Icon(
                                  Icons.remove_circle,
                                  color: AppColors.warning.withOpacity(0.4),
                                  size: 18,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  if (_selectedProducts.length > 3) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        _showAllSelectedProducts();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.expand_more,
                              size: 16,
                              color: AppColors.warning.withOpacity(0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ver ${_selectedProducts.length - 2} productos más',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.warning.withOpacity(0.6),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  ConversionInfoWidget(
                    conversions: _selectedProducts,
                    showDetails: true,
                  ),
                ],
              ),
            ),
          ],

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _selectedProducts.isEmpty
                      ? null
                      : _showExtractionConfirmation,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                _selectedProducts.isEmpty
                    ? 'Seleccione productos para extraer'
                    : 'Procesar Extracción (${_selectedProducts.length} productos)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllSelectedProducts() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Productos Seleccionados (${_selectedProducts.length})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.warning.withOpacity(0.7),
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _selectedProducts.length,
                itemBuilder: (context, index) {
                  final product = _selectedProducts[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['denominacion'] ??
                                    product['nombre_producto'] ??
                                    'Producto sin nombre',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'Cantidad: ${product['cantidad']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.warning.withOpacity(0.6),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    ' • ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.warning.withOpacity(0.6),
                                    ),
                                  ),
                                  Text(
                                    '${product['zona_nombre'] ?? 'N/A'}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.warning.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            _removeProductFromExtraction(index);
                            Navigator.pop(context);
                            if (_selectedProducts.length <= 3) {
                              // If we're back to 3 or fewer products, close the dialog
                              return;
                            }
                            // Refresh the dialog if there are still more than 3 products
                            _showAllSelectedProducts();
                          },
                          icon: Icon(
                            Icons.remove_circle,
                            color: AppColors.warning.withOpacity(0.4),
                            size: 18,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cerrar',
                  style: TextStyle(color: AppColors.warning.withOpacity(0.6)),
                ),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Extracción de Productos',
          style: TextStyle(
            color: AppColors.background,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.warning,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.background),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                key: _formKey,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildExtractionInfoSection(),
                            const SizedBox(height: 24),
                            _buildLocationSelectionSection(),
                            const SizedBox(height: 24),
                            _buildProductSelectionSection(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }
}

class _ProductQuantityDialog extends StatefulWidget {
  final Map<String, dynamic> product; // Cambiar tipo
  final WarehouseZone? sourceLocation;
  final Function(Map<String, dynamic>) onProductAdded;

  const _ProductQuantityDialog({
    required this.product,
    required this.onProductAdded, // Cambiar nombre de onProductAdded
    this.sourceLocation, // Cambiar de warehouseName
  });

  @override
  State<_ProductQuantityDialog> createState() => _ProductQuantityDialogState();
}

class _ProductQuantityDialogState extends State<_ProductQuantityDialog> {
  final _quantityController = TextEditingController();
  Map<String, dynamic>? _selectedVariant;
  List<Map<String, dynamic>> _availableVariants = [];
  bool _isLoadingVariants = false;
  double _maxAvailableStock = 0.0;

  // Variables para presentaciones
  Map<String, dynamic>? _selectedPresentation;
  List<Map<String, dynamic>> _availablePresentations = [];
  bool _isLoadingPresentations = false;

  @override
  void initState() {
    super.initState();
    _maxAvailableStock = 0.0;
    print('🔍 DEBUG: Stock inicial del producto: $_maxAvailableStock');
    _loadLocationSpecificVariants();
    _loadAvailablePresentations(); // NUEVO: Cargar presentaciones disponibles
  }

  Future<void> _loadLocationSpecificVariants() async {
    if (widget.sourceLocation == null) return;

    final sourceLayoutId = int.tryParse(widget.sourceLocation!.id);
    if (sourceLayoutId == null) return;

    setState(() => _isLoadingVariants = true);

    try {
      final variants = await InventoryService.getProductVariantsInLocation(
        idProducto: widget.product['id'] as int,
        idLayout: sourceLayoutId,
      );

      setState(() {
        _availableVariants = variants;
        if (variants.isNotEmpty) {
          _selectedVariant = variants.first;
          print('🔍 DEBUG: Selected variant data: $_selectedVariant');
          print(
            '🔍 DEBUG: Stock disponible: ${_selectedVariant!['stock_disponible']}',
          );
          _maxAvailableStock =
              _selectedVariant!['stock_disponible']?.toDouble() ?? 0.0;
          print('🔍 DEBUG: Max available stock set to: $_maxAvailableStock');
        }
        _isLoadingVariants = false;
      });
    } catch (e) {
      setState(() => _isLoadingVariants = false);
      // Fallback data if service fails
      final fallbackStock = (widget.product['stock_disponible'] as num?)?.toDouble() ?? 0.0;
      _availableVariants = [
        {
          'id_variante': null,
          'variante': 'Estándar',
          'id_presentacion': null,
          'presentacion': 'Unidad',
          'stock_disponible': fallbackStock,
        },
      ];
      _selectedVariant = _availableVariants.first;
      _maxAvailableStock = fallbackStock;
    }
  }

  void _onVariantChanged(Map<String, dynamic>? variant) {
    setState(() {
      _selectedVariant = variant;
      _maxAvailableStock = variant?['stock_disponible']?.toDouble() ?? 0.0;
      _quantityController.clear();
    });
  }

  Future<void> _loadAvailablePresentations() async {
    if (widget.sourceLocation == null) return;

    final sourceLayoutId = int.tryParse(widget.sourceLocation!.id);
    if (sourceLayoutId == null) return;

    setState(() => _isLoadingPresentations = true);

    try {
      print(
        '🔍 DEBUG: Cargando presentaciones para producto ${widget.product['id']}',
      );

      final presentations =
          await InventoryService.getProductPresentationsInZone(
            idProducto: widget.product['id'] as int,
            idLayout: sourceLayoutId,
          );

      setState(() {
        _availablePresentations = presentations;
        if (presentations.isNotEmpty) {
          _selectedPresentation = presentations.first;
          print('🔍 DEBUG: Presentación seleccionada: $_selectedPresentation');
        } else {
          // Si no hay presentaciones, usar fallback con presentación base
          print('⚠️ No hay presentaciones disponibles, usando fallback');
          final stockFromVariant = _selectedVariant?['stock_disponible']?.toDouble() ?? _maxAvailableStock;
          _availablePresentations = [
            {
              'id':
                  widget.product['id_presentacion'] ??
                  1, // Fallback a ID 1 (Unidad)
              'denominacion': widget.product['presentacion'] ?? 'Unidad',
              'cantidad': 1.0,
              'stock_disponible': stockFromVariant,
            },
          ];
          _selectedPresentation = _availablePresentations.first;
        }
        _isLoadingPresentations = false;
      });

      print('✅ Presentaciones cargadas: ${presentations.length}');
    } catch (e) {
      print('❌ Error cargando presentaciones: $e');
      setState(() => _isLoadingPresentations = false);

      // Fallback: usar presentación del producto
      final stockFromVariant = _selectedVariant?['stock_disponible']?.toDouble() ?? _maxAvailableStock;
      _availablePresentations = [
        {
          'id': widget.product['id_presentacion'],
          'denominacion': widget.product['presentacion'] ?? 'Unidad',
          'cantidad': 1.0,
          'stock_disponible': stockFromVariant,
        },
      ];
      _selectedPresentation = _availablePresentations.first;
    }
  }

  /// Valida si hay stock suficiente de ingredientes para un producto elaborado
  Future<bool> _validateIngredientStock(int productId, double quantity) async {
    try {
      final ingredients = await ProductService.getProductIngredients(
        productId.toString(),
      );

      for (final ingredient in ingredients) {
        final ingredientId = ingredient['producto_id'] as int;
        final cantidadNecesaria =
            (ingredient['cantidad_necesaria'] as num).toDouble();
        final totalRequired = cantidadNecesaria * quantity;

        // Aquí se podría verificar stock real del ingrediente
        // Por ahora retorna true, pero se puede extender
        print('🔍 Ingrediente $ingredientId requiere: $totalRequired');
      }

      return true;
    } catch (e) {
      print('❌ Error validando stock de ingredientes: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.product['denominacion'] ??
                          widget.product['nombre_producto'] ??
                          'Extraer Producto',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Info Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Información del Producto',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow('SKU', widget.product['sku'] ?? 'N/A'),
                          _buildInfoRow(
                            'Stock en Ubicación',
                            _maxAvailableStock.toStringAsFixed(1),
                            valueColor:
                                _maxAvailableStock > 0
                                    ? AppColors.success
                                    : AppColors.error,
                          ),
                          if ((widget.product['presentacion'] ?? '')
                              .toString()
                              .isNotEmpty)
                            _buildInfoRow(
                              'Presentación',
                              widget.product['presentacion'] ?? 'N/A',
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Aviso para producto elaborado
                    if (widget.product['es_elaborado'] == true)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⚠️ Producto elaborado - se extraerán ingredientes automáticamente',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Presentation Selection
                    if (_isLoadingVariants)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_availableVariants.isNotEmpty) ...[
                      /*Text(
                        'Seleccionar Presentación',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: AppColors.black87,
                        ),
                      ),*/
                      /*const SizedBox(height: 12),

                      // Presentation Cards
                      ..._availableVariants.map((variant) {
                        final isSelected = _selectedVariant == variant;
                        return GestureDetector(
                          onTap: () => _onVariantChanged(variant),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color:
                                  isSelected
                                      ? AppColors.primary.withOpacity(0.1)
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    isSelected
                                        ? AppColors.primary
                                        : AppColors.border,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        isSelected
                                            ? AppColors.primary
                                            : Colors.transparent,
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? AppColors.primary
                                              : AppColors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child:
                                      isSelected
                                          ? const Icon(
                                            Icons.check,
                                            color: Colors.white,
                                            size: 12,
                                          )
                                          : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        variant['presentacion_nombre'] ??
                                            'Sin presentación',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color:
                                              isSelected
                                                  ? AppColors.primary
                                                  : AppColors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Stock disponible: ${variant['stock_disponible']?.toStringAsFixed(1) ?? '0.0'}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),*/

                      /*const SizedBox(height: 20),*/

                      // Stock Info
                      if (_selectedVariant != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.success.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: AppColors.success,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Stock disponible: ${_maxAvailableStock.toStringAsFixed(1)} unidades',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),
                      // Presentation Selection Section
                      if (_isLoadingPresentations)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_availablePresentations.isNotEmpty) ...[
                        Text(
                          'Seleccionar Presentación',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Presentation Dropdown
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _selectedPresentation,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            prefixIcon: Icon(
                              Icons.category,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          hint: const Text('Seleccionar presentación'),
                          isExpanded: true, // Esta línea es clave
                          items: _availablePresentations.map((presentation) {
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: presentation,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    presentation['denominacion'] + ' - ' + presentation['cantidad'].toString() ??
                                        'Sin nombre',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis, // Añadir esto
                                    maxLines: 1, // Opcional: forzar una sola línea
                                  ),
                                  /*if (presentation['cantidad'] != null)
            Text(
              '${presentation['cantidad']} unidades base',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.grey.shade600,
              ),
            ),
          if (presentation['stock_disponible'] !=
              null)
            Text(
              'Stock: ${presentation['stock_disponible']}',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.success,
                fontWeight: FontWeight.w500,
              ),
            ),*/
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedPresentation = value;
                              _quantityController.clear();
                            });
                          },
                        ),

                        const SizedBox(height: 20),
                      ],
                    ],

                    // Quantity Input
                    Text(
                      'Cantidad a Extraer',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppColors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ingrese la cantidad',
                        hintStyle: TextStyle(
                          color: AppColors.grey.shade500,
                          fontWeight: FontWeight.normal,
                        ),
                        prefixIcon: Icon(
                          Icons.inventory,
                          color: AppColors.primary,
                        ),
                        suffixText:
                            _selectedVariant?['presentacion_nombre'] ?? '',
                        suffixStyle: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingrese una cantidad';
                        }
                        final quantity = double.tryParse(value);
                        if (quantity == null || quantity <= 0) {
                          return 'La cantidad debe ser mayor a 0';
                        }
                        if (quantity > _maxAvailableStock) {
                          return 'Cantidad excede stock disponible (Max: ${_maxAvailableStock.toStringAsFixed(1)})';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Action Buttons
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.grey.shade300),
                        ),
                      ),
                      child: Text(
                        'Cancelar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                          _selectedVariant == null
                              ? null
                              : () async {
                                final quantity = double.tryParse(
                                  _quantityController.text,
                                );
                                if (quantity == null || quantity <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Ingrese una cantidad válida',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                if (quantity > _maxAvailableStock) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Cantidad excede stock disponible',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                try {
                                  // Datos base del producto
                                  final baseProductData = {
                                    'id_producto': widget.product['id'],
                                    'id_variante':
                                        widget.product['id_variante'],
                                    'id_opcion_variante':
                                        widget.product['id_opcion_variante'],
                                    'id_ubicacion':
                                        widget.sourceLocation != null
                                            ? int.tryParse(
                                              widget.sourceLocation!.id,
                                            )
                                            : null,
                                    'precio_unitario':
                                        (widget.product['precio_venta'] as num?)
                                            ?.toDouble() ??
                                        0.0,
                                    'sku_producto': widget.product['sku'] ?? '',
                                    'sku_ubicacion':
                                        widget.product['ubicacion'] ?? '',
                                    'denominacion':
                                        widget.product['denominacion'] ??
                                        widget.product['nombre_producto'] ??
                                        '',
                                    'variante':
                                        widget.product['variante'] ?? '',
                                    'opcionVariante':
                                        widget.product['opcion_variante'] ?? '',
                                    'zona_nombre':
                                        widget.sourceLocation?.name ??
                                        'Sin zona',
                                  };

                                  // Usar PresentationConverter para procesar el producto
                                  final processedProductData =
                                      await PresentationConverter.processProductForExtraction(
                                        productId:
                                            widget.product['id'].toString(),
                                        selectedPresentation:
                                            _selectedPresentation,
                                        cantidad: quantity,
                                        baseProductData: baseProductData,
                                      );

                                  print(
                                    '✅ Producto procesado para extracción: $processedProductData',
                                  );

                                  widget.onProductAdded(processedProductData);
                                  Navigator.of(context).pop();
                                } catch (e) {
                                  print(
                                    '❌ Error procesando producto para extracción: $e',
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error procesando producto: $e',
                                      ),
                                    ),
                                  );
                                }
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Agregar Producto',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Muestra ingredientes de producto elaborado
  Widget _buildIngredientsList() {
    if (widget.product['es_elaborado'] != true) return const SizedBox.shrink();

    return FutureBuilder(
      future: ProductService.getProductIngredients(
        widget.product['id'].toString(),
      ),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          return Text(
            'Ingredientes: ${snapshot.data!.length}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
