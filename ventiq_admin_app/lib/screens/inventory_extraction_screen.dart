import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/cumplimiento_fisico_service.dart';
import '../services/inventory_service.dart';
import '../services/presentacion_cadena_service.dart';
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
  String? _clientRequestUuid;
  String? _requestPayloadSignature;

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
      builder: (context) => _ProductQuantityDialog(
        product: productWithId,
        sourceLocation: _selectedSourceLocation,
        onProductAdded: (productData) {
          final duplicate = _selectedProducts.any(
            (selected) =>
                _stockIdentity(selected) == _stockIdentity(productData),
          );
          if (duplicate) {
            ScaffoldMessenger.of(this.context).showSnackBar(
              const SnackBar(
                content: Text('Esta presentación del producto ya fue agregada'),
                backgroundColor: Colors.orange,
              ),
            );
            return false;
          }
          setState(() => _selectedProducts.add(productData));
          return true;
        },
      ),
    );
  }

  String _stockIdentity(Map<String, dynamic> product) {
    String part(String key) => product[key]?.toString() ?? 'null';
    return [
      part('id_producto'),
      part('id_variante'),
      part('id_opcion_variante'),
      part('id_ubicacion'),
      part('id_presentacion'),
    ].join('|');
  }

  void _removeProductFromExtraction(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
    });
  }

  void _showExtractionConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
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
                            _selectedSourceLocation?.name ?? 'No seleccionada',
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
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
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
      final idTiendaRaw = userData['idTienda'];
      final idTienda = idTiendaRaw is int
          ? idTiendaRaw
          : int.tryParse(idTiendaRaw?.toString() ?? '');

      if (userUuid == null || idTienda == null) {
        throw Exception('No se encontró información del usuario o tienda');
      }

      final motivoRaw = _selectedMotivo!['id'];
      final idMotivo = motivoRaw is int
          ? motivoRaw
          : int.tryParse(motivoRaw?.toString() ?? '');
      if (idMotivo == null) {
        throw Exception('El motivo de extracción no es válido');
      }

      final productos = _selectedProducts.map((product) {
        return {
          'id_producto': product['id_producto'],
          'id_variante': product['id_variante'],
          'id_opcion_variante': product['id_opcion_variante'],
          'id_ubicacion': product['id_ubicacion'],
          'id_presentacion': product['id_presentacion'],
          'cantidad': product['cantidad'],
          'precio_unitario': product['precio_unitario'],
        };
      }).toList();
      final requestPayloadSignature = [
        _autorizadoPorController.text.trim(),
        _selectedMotivo!['id'],
        idTienda,
        _observacionesController.text.trim(),
        productos,
      ].toString();
      if (_requestPayloadSignature != requestPayloadSignature) {
        _clientRequestUuid = InventoryService.createClientRequestUuid();
        _requestPayloadSignature = requestPayloadSignature;
      }

      final result = await InventoryService.insertCompleteExtractionV2(
        autorizadoPor: _autorizadoPorController.text.trim(),
        idMotivoOperacion: idMotivo,
        idTienda: idTienda,
        observaciones: _observacionesController.text.trim(),
        productos: productos,
        clientRequestUuid: _clientRequestUuid!,
      );

      if (result['status'] != 'success') {
        throw Exception(result['message'] ?? 'Error desconocido');
      }

      final operationId = result['id_operacion'];
      final physicalLines = (result['lineas_fisicas'] as List?) ?? const [];
      print(
        '✅ Extracción física registrada con ID: $operationId '
        '(${physicalLines.length} líneas)',
      );

      _clientRequestUuid = null;
      _requestPayloadSignature = null;
      if (mounted) {
        final physicalSummary = physicalLines
            .map((raw) {
              final line = Map<String, dynamic>.from(raw as Map);
              return '${line['cantidad']} ${line['nombre'] ?? 'Presentación'}';
            })
            .join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              physicalSummary.isEmpty
                  ? 'Extracción registrada exitosamente'
                  : 'Despacho físico: $physicalSummary',
            ),
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
    try {
      _motivoOptions = await InventoryService.getMotivoExtraccionOptions();
      if (mounted) setState(() {});
    } catch (e) {
      print('Error loading motivo options: $e');
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
              items: _motivoOptions.map((motivo) {
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
              validationMessage: _selectedSourceLocation == null
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
                  key: ValueKey(
                    'product_selector_${_selectedSourceLocation!.id}',
                  ), // Key única por ubicación
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
                                onPressed: () =>
                                    _removeProductFromExtraction(index),
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
              onPressed: _selectedProducts.isEmpty
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
      builder: (context) => AlertDialog(
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
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
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
      body: _isLoading
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
  final bool Function(Map<String, dynamic>) onProductAdded;

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
  List<Map<String, dynamic>> _inventoryRows = const [];
  List<PresentacionCadena> _presentationChain = const [];
  List<Map<String, dynamic>> _availableIdentities = const [];
  Map<String, dynamic>? _selectedIdentity;
  List<Map<String, dynamic>> _availablePresentations = const [];
  Map<String, dynamic>? _selectedPresentation;
  bool _isLoading = true;
  bool _isPreviewing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDialogData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  int? get _idProducto =>
      _asInt(widget.product['id'] ?? widget.product['id_producto']);

  Map<String, dynamic>? get _selectedInventoryRow {
    final presentationId = _asInt(_selectedPresentation?['id']);
    final identity = _selectedIdentity;
    if (identity == null || presentationId == null) return null;
    return _inventoryRowFor(identity, presentationId);
  }

  Map<String, dynamic>? _inventoryRowFor(
    Map<String, dynamic> identity,
    int presentationId,
  ) {
    for (final row in _inventoryRows) {
      if (_sameIdentity(row, identity) &&
          _asInt(row['id_presentacion']) == presentationId) {
        return row;
      }
    }
    return null;
  }

  Future<void> _loadDialogData() async {
    final productId = _idProducto;
    final locationId = _asInt(widget.sourceLocation?.id);
    if (productId == null || locationId == null) {
      setState(() {
        _isLoading = false;
        _loadError = 'El producto o la ubicación no son válidos.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        InventoryService.getProductPresentationsInZone(
          idProducto: productId,
          idLayout: locationId,
          throwOnError: true,
        ),
        PresentacionCadenaService.cadena(productId),
      ]);
      if (!mounted) return;

      final rows = results[0] as List<Map<String, dynamic>>;
      final chain = results[1] as List<PresentacionCadena>;
      if (chain.isEmpty) {
        throw StateError('El producto no tiene presentaciones configuradas.');
      }
      setState(() {
        _inventoryRows = rows;
        _presentationChain = [...chain]
          ..sort((a, b) => a.nivel.compareTo(b.nivel));
        _availableIdentities = _buildIdentities(rows);
        _selectedIdentity = _initialIdentity(_availableIdentities);
        _refreshPresentations();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'No se pudo cargar el inventario del producto: $e';
      });
    }
  }

  static String _identityKey(Map<String, dynamic> row) =>
      '${_asInt(row['id_variante'])}|${_asInt(row['id_opcion_variante'])}';

  static bool _sameIdentity(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) => _identityKey(left) == _identityKey(right);

  List<Map<String, dynamic>> _buildIdentities(List<Map<String, dynamic>> rows) {
    final identities = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      identities.putIfAbsent(
        _identityKey(row),
        () => <String, dynamic>{
          'id_variante': _asInt(row['id_variante']),
          'id_opcion_variante': _asInt(row['id_opcion_variante']),
          'variante_nombre': row['variante_nombre']?.toString() ?? 'Unidad',
          'opcion_variante_nombre':
              row['opcion_variante_nombre']?.toString() ?? 'Única',
        },
      );
    }
    if (identities.isEmpty) {
      identities['null|null'] = <String, dynamic>{
        'id_variante': _asInt(widget.product['id_variante']),
        'id_opcion_variante': _asInt(widget.product['id_opcion_variante']),
        'variante_nombre': widget.product['variante']?.toString() ?? 'Unidad',
        'opcion_variante_nombre':
            widget.product['opcion_variante']?.toString() ?? 'Única',
      };
    }
    return identities.values.toList(growable: false);
  }

  Map<String, dynamic>? _initialIdentity(
    List<Map<String, dynamic>> identities,
  ) {
    final expectedVariant = _asInt(widget.product['id_variante']);
    final expectedOption = _asInt(widget.product['id_opcion_variante']);
    if (expectedVariant != null || expectedOption != null) {
      final expected = <String, dynamic>{
        'id_variante': expectedVariant,
        'id_opcion_variante': expectedOption,
      };
      for (final identity in identities) {
        if (_sameIdentity(identity, expected)) return identity;
      }
    }
    return identities.length == 1 ? identities.first : null;
  }

  void _refreshPresentations() {
    if (_selectedIdentity == null) {
      _availablePresentations = const [];
      _selectedPresentation = null;
      return;
    }
    final rows = _inventoryRows
        .where((row) => _sameIdentity(row, _selectedIdentity!))
        .toList(growable: false);
    final byPresentation = <int, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = _asInt(row['id_presentacion']);
      if (id != null) byPresentation[id] = row;
    }

    final options = <Map<String, dynamic>>[];
    for (final presentation in _presentationChain) {
      final row = byPresentation.remove(presentation.idPresentacion);
      options.add(_presentationOption(presentation, row));
    }
    for (final entry in byPresentation.entries) {
      final row = entry.value;
      options.add(<String, dynamic>{
        ...row,
        'id': entry.key,
        'denominacion':
            row['presentacion_nombre']?.toString() ?? 'Presentación',
        'factor_rel': null,
        'es_base': false,
        'es_fraccionable': true,
        'nivel': 999,
      });
    }
    _availablePresentations = options;
    final previousId = _asInt(_selectedPresentation?['id']);
    _selectedPresentation =
        _findPresentation(options, previousId) ??
        _findBasePresentation(options) ??
        (options.isEmpty ? null : options.first);
  }

  Map<String, dynamic> _presentationOption(
    PresentacionCadena presentation,
    Map<String, dynamic>? row,
  ) => <String, dynamic>{
    if (row != null) ...row,
    'id': presentation.idPresentacion,
    'id_presentacion': presentation.idPresentacion,
    'denominacion': presentation.nombre,
    'presentacion_nombre': presentation.nombre,
    'factor': presentation.factor,
    'factor_rel': presentation.factorRel,
    'es_base': presentation.esBase,
    'es_fraccionable': presentation.esFraccionable,
    'nivel': presentation.nivel,
    'cantidad_final': _asDouble(row?['cantidad_final']),
    'stock_disponible': _asDouble(row?['stock_disponible']),
  };

  static Map<String, dynamic>? _findPresentation(
    List<Map<String, dynamic>> options,
    int? id,
  ) {
    if (id == null) return null;
    for (final option in options) {
      if (_asInt(option['id']) == id) return option;
    }
    return null;
  }

  static Map<String, dynamic>? _findBasePresentation(
    List<Map<String, dynamic>> options,
  ) {
    for (final option in options) {
      if (option['es_base'] == true) return option;
    }
    return null;
  }

  String get _basePresentationName {
    for (final presentation in _presentationChain) {
      if (presentation.esBase) return presentation.nombre;
    }
    return _presentationChain.isEmpty
        ? 'unidad base'
        : _presentationChain.last.nombre;
  }

  String _presentationDetail(Map<String, dynamic> presentation) {
    final name = presentation['denominacion']?.toString() ?? 'Presentación';
    final physical = _formatQuantity(_asDouble(presentation['cantidad_final']));
    final available = _formatQuantity(
      _asDouble(presentation['stock_disponible']),
    );
    final equivalence = presentation['es_base'] == true
        ? 'base'
        : presentation['factor_rel'] == null
        ? 'equivalencia no disponible'
        : '1 $name = ${_formatQuantity(_asDouble(presentation['factor_rel']))} $_basePresentationName';
    return '$name · $equivalence · físico: $physical · disponible: $available';
  }

  String _identityLabel(Map<String, dynamic> identity) {
    final variant = identity['variante_nombre']?.toString() ?? 'Unidad';
    final option = identity['opcion_variante_nombre']?.toString() ?? 'Única';
    return variant == option ? variant : '$variant · $option';
  }

  Future<void> _previewAndAddProduct() async {
    if (_isPreviewing) return;

    final quantity = double.tryParse(_quantityController.text.trim());
    final idProducto = _idProducto;
    final idUbicacion = _asInt(widget.sourceLocation?.id);
    if (quantity == null || quantity <= 0) {
      _showMessage('Ingrese una cantidad válida');
      return;
    }
    if (idProducto == null || idUbicacion == null) {
      _showMessage('El producto o la ubicación no son válidos');
      return;
    }

    final selectedIdentity = _selectedIdentity;
    final selectedPresentation = _selectedPresentation;
    if (selectedIdentity == null || selectedPresentation == null) {
      _showMessage('Seleccione la variante y la presentación');
      return;
    }
    if (selectedPresentation['es_fraccionable'] != true &&
        quantity != quantity.roundToDouble()) {
      _showMessage('Esta presentación solo permite cantidades enteras');
      return;
    }

    final idPresentacion = _asInt(selectedPresentation['id']);
    if (idPresentacion == null) {
      _showMessage('La presentación seleccionada no es válida');
      return;
    }
    final idVariante = _asInt(selectedIdentity['id_variante']);
    final idOpcionVariante = _asInt(selectedIdentity['id_opcion_variante']);

    setState(() => _isPreviewing = true);
    try {
      final plan = await CumplimientoFisicoService().preview(
        idProducto: idProducto,
        idUbicacion: idUbicacion,
        idPresentacion: idPresentacion,
        cantidad: quantity,
        idVariante: idVariante,
        idOpcionVariante: idOpcionVariante,
      );
      if (!mounted) return;
      if (!plan.esExitoso) {
        _showMessage(plan.mensaje);
        return;
      }

      final accepted = await _confirmPhysicalPlan(plan);
      if (!accepted || !mounted) return;

      final inventoryRow = _inventoryRowFor(selectedIdentity, idPresentacion);
      final baseProductData = {
        'id_producto': idProducto,
        'id_variante': idVariante,
        'id_opcion_variante': idOpcionVariante,
        'id_ubicacion': idUbicacion,
        'precio_unitario': _asDouble(
          inventoryRow?['precio_unitario'] ?? widget.product['precio_venta'],
        ),
        'denominacion':
            inventoryRow?['nombre_producto'] ??
            widget.product['nombre_producto'] ??
            widget.product['denominacion'] ??
            '',
        'sku_producto':
            inventoryRow?['sku_producto'] ??
            widget.product['sku_producto'] ??
            widget.product['sku'] ??
            '',
        'variante': selectedIdentity['variante_nombre'] ?? '',
        'opcionVariante': selectedIdentity['opcion_variante_nombre'] ?? '',
        'zona_nombre': widget.sourceLocation?.name ?? 'Sin zona',
      };
      final processed = await PresentationConverter.processProductForExtraction(
        productId: idProducto.toString(),
        selectedPresentation: {...selectedPresentation, 'id': idPresentacion},
        cantidad: quantity,
        baseProductData: baseProductData,
      );
      if (!mounted) return;
      if (widget.onProductAdded(processed)) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) _showMessage('No se pudo validar el despacho físico: $e');
    } finally {
      if (mounted) setState(() => _isPreviewing = false);
    }
  }

  Future<bool> _confirmPhysicalPlan(PlanCumplimiento plan) async {
    final lines = plan.lineasFisicas
        .map((line) => '${_formatQuantity(line.cantidad)} ${line.nombre}')
        .join('\n');
    final conversions = plan.conversiones.isEmpty
        ? 'No requiere abrir ni reempaquetar presentaciones.'
        : 'Conversiones internas: ${plan.conversiones.length}.';
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirmar despacho físico'),
            content: Text('$lines\n\n$conversions'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Agregar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double _asDouble(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
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
                          ..._buildProductInfoRows(),
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

                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_loadError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _loadError!,
                              style: TextStyle(color: AppColors.error),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _loadDialogData,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      if (_availableIdentities.length > 1) ...[
                        const Text(
                          'Seleccionar Variante',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _selectedIdentity,
                          isExpanded: true,
                          decoration: _selectorDecoration(Icons.tune),
                          hint: const Text('Seleccione variante y opción'),
                          items: _availableIdentities
                              .map(
                                (identity) => DropdownMenuItem(
                                  value: identity,
                                  child: Text(
                                    _identityLabel(identity),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            setState(() {
                              _selectedIdentity = value;
                              _refreshPresentations();
                              _quantityController.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_selectedIdentity == null)
                        _buildSelectionNotice(
                          'Seleccione una variante para ver sus presentaciones y saldos.',
                        )
                      else if (_availablePresentations.isEmpty)
                        _buildSelectionNotice(
                          'No hay presentaciones configuradas para esta variante.',
                        )
                      else ...[
                        const Text(
                          'Seleccionar Presentación',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: AppColors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<Map<String, dynamic>>(
                          value: _selectedPresentation,
                          isExpanded: true,
                          decoration: _selectorDecoration(Icons.category),
                          hint: const Text('Seleccionar presentación'),
                          items: _availablePresentations
                              .map(
                                (presentation) => DropdownMenuItem(
                                  value: presentation,
                                  child: Text(
                                    _presentationDetail(presentation),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            setState(() {
                              _selectedPresentation = value;
                              _quantityController.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        ..._availablePresentations.map(
                          (presentation) => _buildPresentationStockRow(
                            presentation,
                            selected: identical(
                              presentation,
                              _selectedPresentation,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
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
                            _selectedPresentation?['denominacion']
                                ?.toString() ??
                            '',
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
                          _isLoading ||
                              _loadError != null ||
                              _selectedIdentity == null ||
                              _selectedPresentation == null ||
                              _isPreviewing
                          ? null
                          : _previewAndAddProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isPreviewing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
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

  InputDecoration _selectorDecoration(IconData icon) {
    return InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
    );
  }

  Widget _buildSelectionNotice(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _buildPresentationStockRow(
    Map<String, dynamic> presentation, {
    required bool selected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPresentation = presentation;
          _quantityController.clear();
        });
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              presentation['es_base'] == true
                  ? Icons.home_outlined
                  : Icons.inventory_2_outlined,
              size: 18,
              color: selected ? AppColors.primary : AppColors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _presentationDetail(presentation),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.primary : AppColors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _firstText(Iterable<dynamic> values, {String fallback = 'N/A'}) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  List<Widget> _buildProductInfoRows() {
    final row =
        _selectedInventoryRow ??
        (_inventoryRows.isEmpty ? null : _inventoryRows.first);
    final name = _firstText([
      row?['nombre_producto'],
      widget.product['nombre_producto'],
      widget.product['denominacion'],
    ]);
    final sku = _firstText([
      row?['sku_producto'],
      widget.product['sku_producto'],
      widget.product['sku'],
    ]);
    final unit = _firstText([
      row?['um'],
      widget.product['um'],
      widget.product['unidad_medida'],
    ], fallback: '');
    final category = _firstText([
      row?['categoria'],
      widget.product['categoria'],
      widget.product['nombre_categoria'],
    ], fallback: '');
    final subcategory = _firstText([
      row?['subcategoria'],
      widget.product['subcategoria'],
      widget.product['nombre_subcategoria'],
    ], fallback: '');
    return [
      _buildInfoRow('Producto', name),
      _buildInfoRow('SKU', sku),
      _buildInfoRow('Ubicación', widget.sourceLocation?.name ?? 'N/A'),
      if (unit.isNotEmpty) _buildInfoRow('Unidad', unit),
      if (category.isNotEmpty) _buildInfoRow('Categoría', category),
      if (subcategory.isNotEmpty) _buildInfoRow('Subcategoría', subcategory),
      if (_selectedIdentity != null)
        _buildInfoRow('Variante', _identityLabel(_selectedIdentity!)),
    ];
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
}
