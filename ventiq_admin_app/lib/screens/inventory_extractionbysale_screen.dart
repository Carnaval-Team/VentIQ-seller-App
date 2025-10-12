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

class InventoryExtractionBySaleScreen extends StatefulWidget {
  const InventoryExtractionBySaleScreen({super.key});

  @override
  State<InventoryExtractionBySaleScreen> createState() =>
      _InventoryExtractionBySaleScreenState();
}

class _InventoryExtractionBySaleScreenState
    extends State<InventoryExtractionBySaleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clienteController = TextEditingController();
  final _observacionesController = TextEditingController();

  static String _lastCliente = '';
  static String _lastObservaciones = '';

  List<Map<String, dynamic>> _selectedProducts = [];
  WarehouseZone? _selectedSourceLocation;
  bool _isLoading = false;

  // Motivos de venta
  List<Map<String, dynamic>> _motivoVentaOptions = [];
  Map<String, dynamic>? _selectedMotivoVenta;
  bool _isLoadingMotivos = false;

  // Medios de pago
  List<Map<String, dynamic>> _medioPagoOptions = [];
  Map<String, dynamic>? _selectedMedioPago;
  bool _isLoadingMediosPago = false;

  // TPVs
  List<Map<String, dynamic>> _tpvOptions = [];
  Map<String, dynamic>? _selectedTPV;
  bool _isLoadingTPVs = false;

  @override
  void initState() {
    super.initState();
    _loadPersistedValues();
    _loadMotivoVentaOptions();
    _loadMedioPagoOptions();
    _loadTPVOptions();
  }

  void _loadPersistedValues() {
    _clienteController.text = _lastCliente;
    _observacionesController.text = _lastObservaciones;
  }

  void _savePersistedValues() {
    _lastCliente = _clienteController.text;
    _lastObservaciones = _observacionesController.text;
  }

  Future<void> _loadMotivoVentaOptions() async {
    setState(() => _isLoadingMotivos = true);

    try {
      // Cargar todos los motivos de extracción
      final allMotivos = await InventoryService.getMotivoExtraccionOptions();
      
      // Filtrar solo los que contengan "venta" en su denominación (case insensitive)
      _motivoVentaOptions = allMotivos.where((motivo) {
        final denominacion = (motivo['denominacion'] ?? '').toString().toLowerCase();
        return denominacion.contains('venta');
      }).toList();

      // Si hay motivos, seleccionar el primero por defecto
      if (_motivoVentaOptions.isNotEmpty) {
        _selectedMotivoVenta = _motivoVentaOptions.first;
      }

      print('✅ Motivos de venta cargados: ${_motivoVentaOptions.length}');
      for (var motivo in _motivoVentaOptions) {
        print('   - ${motivo['denominacion']} (ID: ${motivo['id']})');
      }

      setState(() => _isLoadingMotivos = false);
    } catch (e) {
      print('❌ Error cargando motivos de venta: $e');
      setState(() => _isLoadingMotivos = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar tipos de venta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadMedioPagoOptions() async {
    setState(() => _isLoadingMediosPago = true);

    try {
      final mediosPago = await InventoryService.getMedioPagoOptions();
      _medioPagoOptions = mediosPago;

      // Seleccionar efectivo por defecto
      if (_medioPagoOptions.isNotEmpty) {
        _selectedMedioPago = _medioPagoOptions.firstWhere(
          (medio) => medio['es_efectivo'] == true,
          orElse: () => _medioPagoOptions.first,
        );
      }

      print('✅ Medios de pago cargados: ${_medioPagoOptions.length}');
      setState(() => _isLoadingMediosPago = false);
    } catch (e) {
      print('❌ Error cargando medios de pago: $e');
      setState(() => _isLoadingMediosPago = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar medios de pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadTPVOptions() async {
    setState(() => _isLoadingTPVs = true);

    try {
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final idTienda = userData['idTienda'] as int?;

      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      final tpvs = await InventoryService.getTPVsByTienda(idTienda);
      _tpvOptions = tpvs;

      // Seleccionar el primero por defecto
      if (_tpvOptions.isNotEmpty) {
        _selectedTPV = _tpvOptions.first;
      }

      print('✅ TPVs cargados: ${_tpvOptions.length}');
      for (var tpv in _tpvOptions) {
        print('   - ${tpv['denominacion']} (ID: ${tpv['id']})');
      }

      setState(() => _isLoadingTPVs = false);
    } catch (e) {
      print('❌ Error cargando TPVs: $e');
      setState(() => _isLoadingTPVs = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar TPVs: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  void _addProductToExtraction(Map<String, dynamic> product) {
    if (_selectedSourceLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar una zona primero'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _ProductQuantityWithPriceDialog(
        product: product,
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

  double _calculateTotal() {
    return _selectedProducts.fold(
      0.0,
      (sum, product) =>
          sum +
          ((product['precio_unitario'] ?? 0.0) * (product['cantidad'] ?? 0.0)),
    );
  }

  void _showExtractionConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Confirmar Venta por Acuerdo',
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
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on,
                        color: AppColors.success.withOpacity(0.7), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Zona de Origen:',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
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
              const Text('Productos a Vender:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ..._selectedProducts.map((productData) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        productData['denominacion'] ?? 'Sin nombre',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (productData['variante'] != null &&
                          productData['variante'].toString().isNotEmpty)
                        Text('Variante: ${productData['variante']}',
                            style: TextStyle(
                                color: AppColors.success.withOpacity(0.6),
                                fontSize: 12)),
                      Text('Cantidad: ${productData['cantidad']}',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                        'Precio: \$${(productData['precio_unitario'] ?? 0.0).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: AppColors.success),
                      ),
                      Text(
                        'Subtotal: \$${((productData['cantidad'] ?? 0.0) * (productData['precio_unitario'] ?? 0.0)).toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.success),
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 16),

              // Total
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('\$${_calculateTotal().toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.success)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Cliente y observaciones
              if (_clienteController.text.isNotEmpty ||
                  _observacionesController.text.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.info.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_clienteController.text.isNotEmpty)
                        Text('Cliente: ${_clienteController.text}'),
                      if (_observacionesController.text.isNotEmpty)
                        Text('Observaciones: ${_observacionesController.text}'),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Confirmar Venta'),
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
    if (_selectedMotivoVenta == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar un tipo de venta')),
      );
      return;
    }
    if (_selectedTPV == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar un TPV')),
      );
      return;
    }
    if (_selectedMedioPago == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar un medio de pago')),
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

      // Preparar productos
      final productos = _selectedProducts.map((product) {
        return {
          'id_producto': product['id_producto'],
          'id_variante': product['id_variante'],
          'id_opcion_variante': product['id_opcion_variante'],
          'id_ubicacion': product['id_ubicacion'],
          'id_presentacion': product['id_presentacion'] ?? 1,
          'cantidad': product['cantidad'],
          'precio_unitario': product['precio_unitario'],
          'sku_producto': product['sku_producto'],
          'sku_ubicacion': product['sku_ubicacion'],
        };
      }).toList();

      // Preparar observaciones con información del cliente y total
      String observaciones = '';
      if (_clienteController.text.isNotEmpty) {
        observaciones += 'Cliente: ${_clienteController.text}. ';
      }
      observaciones += 'Total: \$${_calculateTotal().toStringAsFixed(2)}. ';
      if (_observacionesController.text.isNotEmpty) {
        observaciones += _observacionesController.text;
      }

      // Usar el ID del motivo de venta seleccionado
      final idMotivoOperacion = _selectedMotivoVenta!['id'] as int;
      final tipoVenta = _selectedMotivoVenta!['denominacion'] ?? 'Venta';

      print('📝 Registrando venta:');
      print('   - Tipo: $tipoVenta (ID: $idMotivoOperacion)');
      print('   - Productos: ${productos.length}');
      print('   - Total: CUP ${_calculateTotal().toStringAsFixed(2)}');

      final result = await InventoryService.insertCompleteExtraction(
        autorizadoPor: _clienteController.text.isEmpty
            ? 'Venta directa'
            : _clienteController.text,
        estadoInicial: 1,
        idMotivoOperacion: idMotivoOperacion,
        idTienda: idTienda,
        observaciones: observaciones,
        productos: productos,
        uuid: userUuid,
      );

      if (result['status'] != 'success') {
        throw Exception(result['message'] ?? 'Error desconocido');
      }

      final operationId = result['id_operacion'];
      print('✅ Venta por acuerdo registrada con ID: $operationId');

      // Completar operación automáticamente
      if (operationId != null) {
        try {
          final completeResult = await InventoryService.completeOperation(
            idOperacion: operationId,
            comentario: 'Venta por acuerdo completada - $observaciones',
            uuid: userUuid,
          );

          if (completeResult['status'] == 'success') {
            print('✅ Operación completada exitosamente');
          }
        } catch (completeError) {
          print('❌ Error al completar operación: $completeError');
        }

        // Registrar el pago de la venta
        try {
          final totalVenta = _calculateTotal();
          final idTpv = _selectedTPV!['id'] as int;
          final idMedioPago = _selectedMedioPago!['id'];
          final tpvNombre = _selectedTPV!['denominacion'] ?? 'Desconocido';
          final medioPagoNombre = _selectedMedioPago!['denominacion'] ?? 'Desconocido';

          print('💳 Registrando pago:');
          print('   - TPV: $tpvNombre (ID: $idTpv)');
          print('   - Monto: CUP ${totalVenta.toStringAsFixed(2)}');
          print('   - Medio: $medioPagoNombre (ID: $idMedioPago, tipo: ${idMedioPago.runtimeType})');
          print('   - UUID: $userUuid');

          // Crear registro en app_dat_operacion_venta
          print('🔹 Paso 1: Creando operación de venta...');
          final ventaResult = await InventoryService.createOperacionVenta(
            idOperacion: operationId,
            idTpv: idTpv,
            importeTotal: totalVenta,
          );

          print('🔹 Resultado operación venta: $ventaResult');
          
          if (ventaResult['id_operacion'] != null) {
            final idOperacionVenta = ventaResult['id_operacion'] as int;
            print('🔹 Paso 2: Registrando pago con id_operacion_venta: $idOperacionVenta');
            
            // Registrar el pago
            final pagoResult = await InventoryService.registerPagoVenta(
              idOperacionVenta: idOperacionVenta,
              idMedioPago: idMedioPago,
              monto: totalVenta,
              uuid: userUuid,
            );

            print('✅ Pago registrado exitosamente: $pagoResult');
          } else {
            print('❌ No se obtuvo id_operacion de la venta');
          }
        } catch (pagoError, stackTrace) {
          print('❌ Error al registrar pago: $pagoError');
          print('🔴 Stack trace: $stackTrace');
          
          // Mostrar el error al usuario
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Advertencia: Venta registrada pero error en pago: $pagoError'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venta por acuerdo registrada exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar venta: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Venta por Acuerdo'),
        backgroundColor: AppColors.success,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selector de ubicación usando componente reutilizable
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LocationSelectorWidget(
                          type: LocationSelectorType.single,
                          title: 'Zona de Origen',
                          subtitle: 'Seleccione la zona desde donde se venderán los productos',
                          selectedLocation: _selectedSourceLocation,
                          onLocationChanged: (location) {
                            setState(() {
                              _selectedSourceLocation = location;
                              _selectedProducts.clear();
                            });
                          },
                          validationMessage: _selectedSourceLocation == null
                              ? 'Debe seleccionar una zona de origen'
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Información del cliente
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Información de la Venta',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Dropdown de Tipo de Venta
                            if (_isLoadingMotivos)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_motivoVentaOptions.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber,
                                        color: Colors.orange[700]),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'No hay tipos de venta configurados en el sistema',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              DropdownButtonFormField<Map<String, dynamic>>(
                                value: _selectedMotivoVenta,
                                decoration: const InputDecoration(
                                  labelText: 'Tipo de Venta',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.sell),
                                  hintText: 'Seleccione el tipo de venta',
                                ),
                                items: _motivoVentaOptions.map((motivo) {
                                  return DropdownMenuItem(
                                    value: motivo,
                                    child: Text(
                                      motivo['denominacion'] ?? 'Sin nombre',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (motivo) {
                                  setState(() => _selectedMotivoVenta = motivo);
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Debe seleccionar un tipo de venta';
                                  }
                                  return null;
                                },
                              ),
                            const SizedBox(height: 16),
                            // Dropdown de TPV
                            if (_isLoadingTPVs)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_tpvOptions.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber,
                                        color: Colors.orange[700]),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'No hay TPVs configurados en el sistema',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              DropdownButtonFormField<Map<String, dynamic>>(
                                value: _selectedTPV,
                                decoration: const InputDecoration(
                                  labelText: 'Punto de Venta (TPV)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.point_of_sale),
                                  hintText: 'Seleccione el TPV',
                                ),
                                items: _tpvOptions.map((tpv) {
                                  return DropdownMenuItem(
                                    value: tpv,
                                    child: Text(
                                      tpv['denominacion'] ?? 'Sin nombre',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (tpv) {
                                  setState(() => _selectedTPV = tpv);
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Debe seleccionar un TPV';
                                  }
                                  return null;
                                },
                              ),
                            const SizedBox(height: 16),
                            // Dropdown de Medio de Pago
                            if (_isLoadingMediosPago)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_medioPagoOptions.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber,
                                        color: Colors.orange[700]),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'No hay medios de pago configurados',
                                        style: TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              DropdownButtonFormField<Map<String, dynamic>>(
                                value: _selectedMedioPago,
                                decoration: const InputDecoration(
                                  labelText: 'Medio de Pago',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.payment),
                                  hintText: 'Seleccione el medio de pago',
                                ),
                                items: _medioPagoOptions.map((medio) {
                                  return DropdownMenuItem(
                                    value: medio,
                                    child: Row(
                                      children: [
                                        Icon(
                                          medio['es_efectivo'] == true
                                              ? Icons.money
                                              : medio['es_digital'] == true
                                                  ? Icons.credit_card
                                                  : Icons.payment,
                                          size: 18,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          medio['denominacion'] ?? 'Sin nombre',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (medio) {
                                  setState(() => _selectedMedioPago = medio);
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Debe seleccionar un medio de pago';
                                  }
                                  return null;
                                },
                              ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _clienteController,
                              decoration: const InputDecoration(
                                labelText: 'Cliente',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                                hintText: 'Nombre del cliente (opcional)',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _observacionesController,
                              decoration: const InputDecoration(
                                labelText: 'Observaciones',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.notes),
                                hintText: 'Detalles adicionales (opcional)',
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Selector de productos usando componente reutilizable
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Seleccionar Productos',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_selectedSourceLocation == null)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: Colors.orange[700]),
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
                                  key: ValueKey('product_selector_${_selectedSourceLocation!.id}'),
                                  searchType: ProductSearchType.withStock,
                                  requireInventory: true,
                                  locationId:
                                      int.tryParse(_selectedSourceLocation!.id),
                                  searchHint: 'Buscar productos para vender...',
                                  onProductSelected: _addProductToExtraction,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Lista de productos seleccionados
                    if (_selectedProducts.isNotEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Productos Seleccionados',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${_selectedProducts.length} items',
                                    style: const TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _selectedProducts.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(),
                                itemBuilder: (context, index) {
                                  final product = _selectedProducts[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      product['denominacion'] ?? 'Sin nombre',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Cantidad: ${product['cantidad']}',
                                        ),
                                        Text(
                                          'Precio: CUP ${(product['precio_unitario'] ?? 0.0).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          'Subtotal: CUP ${((product['cantidad'] ?? 0.0) * (product['precio_unitario'] ?? 0.0)).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () {
                                        _removeProductFromExtraction(index);
                                      },
                                    ),
                                  );
                                },
                              ),
                              const Divider(),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'TOTAL:',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'CUP ${_calculateTotal().toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Botón fijo en la parte inferior
          if (_selectedProducts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _showExtractionConfirmation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Confirmar Venta (${_selectedProducts.length} productos)',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Dialog widget for selecting product quantity and price
class _ProductQuantityWithPriceDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final WarehouseZone? sourceLocation;
  final Function(Map<String, dynamic>) onProductAdded;

  const _ProductQuantityWithPriceDialog({
    required this.product,
    required this.sourceLocation,
    required this.onProductAdded,
  });

  @override
  State<_ProductQuantityWithPriceDialog> createState() =>
      _ProductQuantityWithPriceDialogState();
}

class _ProductQuantityWithPriceDialogState
    extends State<_ProductQuantityWithPriceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  Map<String, dynamic>? _selectedVariant;
  List<Map<String, dynamic>> _availableVariants = [];
  bool _isLoadingVariants = false;
  double _maxAvailableStock = 0.0;

  @override
  void initState() {
    super.initState();
    _maxAvailableStock =
        (widget.product['stock_disponible'] as num?)?.toDouble() ?? 0.0;
    // Set default price from product
    _priceController.text =
        ((widget.product['precio_venta'] as num?)?.toDouble() ?? 0.0)
            .toStringAsFixed(2);
    _loadLocationSpecificVariants();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
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
          _maxAvailableStock =
              _selectedVariant!['stock_disponible']?.toDouble() ?? 0.0;
        }
        _isLoadingVariants = false;
      });
    } catch (e) {
      setState(() => _isLoadingVariants = false);
      // Fallback data
      _availableVariants = [
        {
          'id_variante': null,
          'variante': 'Estándar',
          'id_presentacion': 1,
          'presentacion_nombre': 'Unidad',
          'stock_disponible': _maxAvailableStock,
        },
      ];
      _selectedVariant = _availableVariants.first;
    }
  }

  void _onVariantChanged(Map<String, dynamic>? variant) {
    setState(() {
      _selectedVariant = variant;
      _maxAvailableStock = variant?['stock_disponible']?.toDouble() ?? 0.0;
      _quantityController.clear();
    });
  }

  void _submitProduct() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedVariant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar una variante')),
      );
      return;
    }

    final quantity = double.parse(_quantityController.text);
    final price = double.parse(_priceController.text);

    final productData = {
      'id_producto': widget.product['id'],
      'id_variante': _selectedVariant!['id_variante'],
      'id_opcion_variante': _selectedVariant!['id_opcion_variante'],
      'id_ubicacion': int.tryParse(widget.sourceLocation!.id),
      'id_presentacion': _selectedVariant!['id_presentacion'] ?? 1,
      'cantidad': quantity,
      'precio_unitario': price,
      'sku_producto': widget.product['sku'] ?? '',
      'sku_ubicacion': widget.sourceLocation?.name ?? '',
      'denominacion':
          widget.product['denominacion'] ?? widget.product['nombre_producto'] ?? '',
      'variante': _selectedVariant!['variante'] ?? '',
      'zona_nombre': widget.sourceLocation?.name ?? '',
    };

    widget.onProductAdded(productData);
    Navigator.pop(context);
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
                color: AppColors.success,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product['denominacion'] ??
                              widget.product['nombre_producto'] ??
                              'Producto',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.product['sku'] != null)
                          Text(
                            'SKU: ${widget.product['sku']}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Variant Selection
                      if (_isLoadingVariants)
                        const Center(child: CircularProgressIndicator())
                      else if (_availableVariants.isNotEmpty) ...[
                        const Text(
                          'Seleccionar Presentación',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._availableVariants.map((variant) {
                          final isSelected = _selectedVariant == variant;
                          return GestureDetector(
                            onTap: () => _onVariantChanged(variant),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.success.withOpacity(0.1)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.success
                                      : AppColors.border,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    color: isSelected
                                        ? AppColors.success
                                        : Colors.grey,
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
                                            color: isSelected
                                                ? AppColors.success
                                                : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          'Stock: ${variant['stock_disponible']?.toStringAsFixed(1) ?? '0.0'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        const SizedBox(height: 20),
                      ],

                      // Quantity Input
                      const Text(
                        'Cantidad',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ingrese la cantidad',
                          prefixIcon: const Icon(Icons.inventory),
                          suffixText: _selectedVariant?['presentacion_nombre'] ?? '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
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
                            return 'Stock insuficiente (Max: ${_maxAvailableStock.toStringAsFixed(1)})';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Price Input
                      const Text(
                        'Precio de Venta',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Ingrese el precio',
                          prefixIcon: const Icon(Icons.attach_money),
                          suffixText: 'CUP',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese un precio';
                          }
                          final price = double.tryParse(value);
                          if (price == null || price <= 0) {
                            return 'El precio debe ser mayor a 0';
                          }
                          return null;
                        },
                      ),

                      // Stock Info
                      if (_selectedVariant != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: AppColors.info),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Stock disponible: ${_maxAvailableStock.toStringAsFixed(1)} unidades',
                                  style: TextStyle(color: AppColors.info),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Action Buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
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
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _selectedVariant == null ? null : _submitProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Agregar Producto'),
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