import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../models/inventory.dart';
import '../services/warehouse_service.dart';
import '../services/inventory_service.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../services/tpv_service.dart';
import '../services/printer_manager.dart';
import '../services/wifi_printer_service.dart';
import '../widgets/conversion_info_widget.dart';
import '../widgets/product_selector_widget.dart';
import '../widgets/location_selector_widget.dart';
import '../services/product_search_service.dart';
import '../utils/presentation_converter.dart';
import '../services/export_service.dart';

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
  bool _showDescriptionInSelectors = false;
  bool _isGeneratingOffer = false;

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
    _loadShowDescriptionConfig();
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

  Future<void> _loadShowDescriptionConfig() async {
    try {
      final userPreferencesService = UserPreferencesService();
      final showDescription =
          await userPreferencesService.getShowDescriptionInSelectors();
      setState(() {
        _showDescriptionInSelectors = showDescription;
      });
      print(
        '📋 ExtractionBySale - Configuración "Mostrar descripción en selectores" cargada: $showDescription',
      );
    } catch (e) {
      print(
        '❌ ExtractionBySale - Error al cargar configuración de mostrar descripción: $e',
      );
      // Mantener valor por defecto (false)
    }
  }

  Future<void> _loadMotivoVentaOptions() async {
    setState(() => _isLoadingMotivos = true);

    try {
      // Cargar todos los motivos de extracción
      final allMotivos = await InventoryService.getMotivoExtraccionOptions();

      // Filtrar solo los que contengan "venta" en su denominación (case insensitive)
      _motivoVentaOptions =
          allMotivos.where((motivo) {
            final denominacion =
                (motivo['denominacion'] ?? '').toString().toLowerCase();
            return denominacion.contains('venta');
          }).toList();

      // Buscar y seleccionar automáticamente "Venta normal"
      if (_motivoVentaOptions.isNotEmpty) {
        // Intentar encontrar "Venta normal" específicamente
        final ventaNormal = _motivoVentaOptions.firstWhere(
          (motivo) {
            final denominacion =
                (motivo['denominacion'] ?? '').toString().toLowerCase();
            return denominacion == 'venta normal';
          },
          orElse:
              () =>
                  _motivoVentaOptions
                      .first, // Fallback al primero si no encuentra "Venta normal"
        );
        _selectedMotivoVenta = ventaNormal;

        print(
          '🎯 Motivo seleccionado automáticamente: ${_selectedMotivoVenta!['denominacion']}',
        );
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

      final tpvs = await TpvService.getTpvsByStore();
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
      builder:
          (context) => _ProductQuantityWithPriceDialog(
            product: product,
            sourceLocation: _selectedSourceLocation,
            onProductAdded: (productData) {
              print('productData');
              print(productData);
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
      builder:
          (context) => AlertDialog(
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
                      border: Border.all(
                        color: AppColors.success.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: AppColors.success.withOpacity(0.7),
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
                    'Productos a Vender:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ..._selectedProducts.map((productData) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.success.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nombre del producto - ocupa todo el ancho
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              productData['denominacion'] ?? 'Sin nombre',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Primera fila: SKU y Variante
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'SKU: ${productData['sku_producto'] ?? 'N/A'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (productData['variante'] != null &&
                                  productData['variante'].toString().isNotEmpty)
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    'Variante: ${productData['variante']}',
                                    style: TextStyle(
                                      color: AppColors.success.withOpacity(0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Segunda fila: Cantidad y Precio
                          Row(
                            children: [
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'Cantidad: ${productData['cantidad']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  'Precio: \$${(productData['precio_unitario'] ?? 0.0).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Tercera fila: Subtotal - centrado y destacado
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              'Subtotal: \$${((productData['cantidad'] ?? 0.0) * (productData['precio_unitario'] ?? 0.0)).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.right,
                            ),
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
                        const Text(
                          'TOTAL:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '\$${_calculateTotal().toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.success,
                          ),
                        ),
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
                        border: Border.all(
                          color: AppColors.info.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_clienteController.text.isNotEmpty)
                            Text('Cliente: ${_clienteController.text}'),
                          if (_observacionesController.text.isNotEmpty)
                            Text(
                              'Observaciones: ${_observacionesController.text}',
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
                  backgroundColor: AppColors.success,
                ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Debe seleccionar un TPV')));
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
      final idTpv = _selectedTPV!['id'] as int;

      if (userUuid == null || idTienda == null) {
        throw Exception('No se encontró información del usuario o tienda');
      }

      // Preparar productos usando el mismo formato que order_service.dart
      final productos =
          _selectedProducts.map((product) {
            return {
              'id_producto': product['meta']['id_producto'],
              'id_variante': product['id_variante'],
              'id_opcion_variante': product['id_opcion_variante'],
              'id_ubicacion': product['id_ubicacion'],
              'id_presentacion': product['meta']['id_presentacion'] ?? 1,
              'cantidad': product['cantidad'],
              'precio_unitario': product['precio_unitario'],
              'sku_producto':
                  product['sku_producto'] ?? product['id_producto'].toString(),
              'sku_ubicacion': product['sku_ubicacion'],
              'es_producto_venta':
                  true, // Mark as sales product like in order_service
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

      final tipoVenta = _selectedMotivoVenta!['denominacion'] ?? 'Venta';

      print('📝 Registrando venta usando fn_registrar_venta:');
      print('   - Tipo: $tipoVenta');
      print('   - Productos: ${productos.length}');
      print('   - Total: CUP ${_calculateTotal().toStringAsFixed(2)}');
      print('   - TPV ID: $idTpv');

      // Usar fn_registrar_venta como en order_service.dart
      final rpcParams = {
        'p_codigo_promocion': null,
        'p_denominacion':
            'Venta por Acuerdo - ${DateTime.now().millisecondsSinceEpoch}',
        'p_estado_inicial': 1,
        'p_id_tpv': idTpv,
        'p_observaciones': observaciones,
        'p_productos': productos,
        'p_uuid': userUuid,
        'p_id_cliente': null,
      };

      print('=== PARAMETROS RPC fn_registrar_venta ===');
      print('p_codigo_promocion: ${rpcParams['p_codigo_promocion']}');
      print('p_denominacion: ${rpcParams['p_denominacion']}');
      print('p_estado_inicial: ${rpcParams['p_estado_inicial']}');
      print('p_id_tpv: ${rpcParams['p_id_tpv']}');
      print('p_observaciones: ${rpcParams['p_observaciones']}');
      print('p_uuid: ${rpcParams['p_uuid']}');
      print('p_productos (${productos.length} items): $productos');
      print('========================================');

      // Llamar a fn_registrar_venta usando Supabase directamente
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_venta',
        params: rpcParams,
      );

      print('Respuesta fn_registrar_venta: $response');

      if (response != null && response['status'] == 'success') {
        final operationId = response['id_operacion'] as int?;
        if (operationId == null) {
          throw Exception('No se recibió ID de operación válido del servidor');
        }

        print('✅ Venta registrada con ID: $operationId');

        // Registrar pagos usando fn_registrar_pago_venta como en order_service.dart
        try {
          final totalVenta = _calculateTotal();
          final idMedioPago = _selectedMedioPago!['id'];
          final medioPagoNombre =
              _selectedMedioPago!['denominacion'] ?? 'Desconocido';

          print('💳 Registrando pago:');
          print('   - Monto: CUP ${totalVenta.toStringAsFixed(2)}');
          print('   - Medio: $medioPagoNombre (ID: $idMedioPago)');

          // Preparar array de pagos
          List<Map<String, dynamic>> pagos = [
            {
              'id_medio_pago': idMedioPago,
              'monto': totalVenta,
              'referencia_pago':
                  'Venta por Acuerdo - ${DateTime.now().millisecondsSinceEpoch}',
            },
          ];

          // Llamar a fn_registrar_pago_venta
          final pagoResponse = await Supabase.instance.client.rpc(
            'fn_registrar_pago_venta',
            params: {'p_id_operacion_venta': operationId, 'p_pagos': pagos},
          );

          print('Respuesta fn_registrar_pago_venta: $pagoResponse');

          if (pagoResponse == true) {
            print('✅ Pago registrado exitosamente');
          } else {
            print(
              '⚠️ Advertencia: Respuesta inesperada del registro de pago: $pagoResponse',
            );
          }
        } catch (pagoError, stackTrace) {
          print('❌ Error al registrar pago: $pagoError');
          print('🔴 Stack trace: $stackTrace');

          // Mostrar advertencia pero no fallar la operación
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Advertencia: Venta registrada pero error en pago: $pagoError',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }

        // Completar operación automáticamente usando fn_registrar_cambio_estado_operacion
        try {
          print('🔄 Completando operación automáticamente...');

          final completeResponse = await Supabase.instance.client.rpc(
            'fn_registrar_cambio_estado_operacion',
            params: {
              'p_id_operacion': operationId,
              'p_nuevo_estado': 2, // Estado completado
              'p_uuid_usuario': userUuid,
            },
          );

          print(
            'Respuesta fn_registrar_cambio_estado_operacion: $completeResponse',
          );
          print('✅ Operación completada automáticamente');
        } catch (completeError) {
          print('❌ Error al completar operación: $completeError');
          // No fallar la operación principal por esto
        }

        if (mounted) {
          // Limpiar campos de cliente y observaciones
          _clienteController.clear();
          _observacionesController.clear();
          _lastCliente = '';
          _lastObservaciones = '';

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Venta por acuerdo registrada y completada exitosamente',
              ),
              backgroundColor: AppColors.success,
            ),
          );

          // ✅ Mostrar diálogo de impresión INMEDIATAMENTE (sin delay)
          // El diálogo se mostrará antes de que se cierre la pantalla
          _showPrintDialog();
        }
      } else {
        throw Exception(
          response?['message'] ?? 'Error en el registro de venta',
        );
      }
    } catch (e) {
      print('❌ Error en _submitExtraction: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al registrar venta: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _generateOfferPdf() async {
    if (_selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar al menos un producto')),
      );
      return;
    }

    setState(() => _isGeneratingOffer = true);

    try {
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final idTienda = userData['idTienda'] as int?;

      Map<String, dynamic>? tiendaData;
      if (idTienda != null) {
        tiendaData =
            await Supabase.instance.client
                .from('app_dat_tienda')
                .select('denominacion, direccion, ubicacion')
                .eq('id', idTienda)
                .maybeSingle();
      }

      final storeName =
          (tiendaData?['denominacion'] ?? 'Tienda').toString().trim().isEmpty
              ? 'Tienda'
              : (tiendaData?['denominacion'] ?? 'Tienda').toString();

      final storeAddress = (tiendaData?['direccion'])?.toString();
      final storeLocation = (tiendaData?['ubicacion'])?.toString();

      final productsForPdf =
          _selectedProducts.map<Map<String, dynamic>>((p) {
            return {
              'denominacion': p['denominacion'],
              'sku_producto': p['sku_producto'],
              'cantidad': p['cantidad'],
              'precio_unitario': p['precio_unitario'],
              'descripcion': p['descripcion'],
              'descripcion_corta': p['descripcion_corta'],
            };
          }).toList();

      await ExportService().exportCommercialOfferPdf(
        context: context,
        storeName: storeName,
        storeAddress: storeAddress,
        storeLocation: storeLocation,
        currencyCode: 'CUP',
        offerTitle: 'OFERTA COMERCIAL',
        issuedAt: DateTime.now(),
        clientName:
            _clienteController.text.isEmpty ? null : _clienteController.text,
        observations:
            _observacionesController.text.isEmpty
                ? null
                : _observacionesController.text,
        products: productsForPdf,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al generar oferta: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingOffer = false);
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
                          includeConsignations: true,
                          subtitle:
                              'Seleccione la zona desde donde se venderán los productos',
                          selectedLocation: _selectedSourceLocation,
                          onLocationChanged: (location) {
                            setState(() {
                              _selectedSourceLocation = location;
                              _selectedProducts.clear();
                            });
                          },
                          validationMessage:
                              _selectedSourceLocation == null
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
                                    Icon(
                                      Icons.warning_amber,
                                      color: Colors.orange[700],
                                    ),
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
                                items:
                                    _motivoVentaOptions.map((motivo) {
                                      return DropdownMenuItem(
                                        value: motivo,
                                        child: Text(
                                          motivo['denominacion'] ??
                                              'Sin nombre',
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
                                    Icon(
                                      Icons.warning_amber,
                                      color: Colors.orange[700],
                                    ),
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
                                items:
                                    _tpvOptions.map((tpv) {
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
                                    Icon(
                                      Icons.warning_amber,
                                      color: Colors.orange[700],
                                    ),
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
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Medio de Pago',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.payment),
                                  hintText: 'Seleccione el medio de pago',
                                ),
                                items:
                                    _medioPagoOptions.map((medio) {
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
                                            Expanded(
                                              child: Text(
                                                medio['denominacion'] ??
                                                    'Sin nombre',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
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
                                    Icon(
                                      Icons.info_outline,
                                      color: Colors.orange[700],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Seleccione una zona de origen para ver productos disponibles',
                                        style: TextStyle(
                                          color: Colors.orange[700],
                                        ),
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
                                  ),
                                  searchType: ProductSearchType.withStock,
                                  requireInventory: true,
                                  locationId: int.tryParse(
                                    _selectedSourceLocation!.id,
                                  ),
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
                                separatorBuilder:
                                    (context, index) => const Divider(),
                                itemBuilder: (context, index) {
                                  final product = _selectedProducts[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${product['denominacion']}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        // Mostrar descripción si está habilitado y existe
                                        if (_showDescriptionInSelectors &&
                                            _hasDescription(product)) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            _getProductDescription(product),
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                              fontStyle: FontStyle.italic,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (product['sku_producto'] != null &&
                                            product['sku_producto']
                                                .toString()
                                                .isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'SKU: ${product['sku_producto']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ],
                                      ],
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
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
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
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            (_isLoading || _isGeneratingOffer)
                                ? null
                                : _generateOfferPdf,
                        icon:
                            _isGeneratingOffer
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.picture_as_pdf),
                        label: const Text('Oferta PDF'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: const BorderSide(color: AppColors.success),
                          foregroundColor: AppColors.success,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed:
                            (_isLoading || _isGeneratingOffer)
                                ? null
                                : _showExtractionConfirmation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child:
                            _isLoading
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : Text(
                                  'Confirmar Venta (${_selectedProducts.length} productos)',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Verifica si el producto tiene descripción disponible
  bool _hasDescription(Map<String, dynamic> product) {
    final descripcion = product['descripcion'];
    final descripcionCorta = product['descripcion_corta'];

    return (descripcion != null && descripcion.toString().isNotEmpty) ||
        (descripcionCorta != null && descripcionCorta.toString().isNotEmpty);
  }

  /// Obtiene la descripción del producto, priorizando descripcion sobre descripcion_corta
  String _getProductDescription(Map<String, dynamic> product) {
    final descripcion = product['descripcion'];
    final descripcionCorta = product['descripcion_corta'];

    if (descripcion != null && descripcion.toString().isNotEmpty) {
      return descripcion.toString();
    } else if (descripcionCorta != null &&
        descripcionCorta.toString().isNotEmpty) {
      return descripcionCorta.toString();
    }

    return '';
  }

  /// 🖨️ Mostrar diálogo de impresión después de completar la extracción
  void _showPrintDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Evitar cerrar tocando afuera
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.print, color: Color(0xFF4A90E2)),
                const SizedBox(width: 8),
                const Expanded(child: Text('¿Deseas imprimir el ticket?')),
              ],
            ),
            content: const Text(
              'Se imprimirá un ticket con los detalles de la venta por acuerdo.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Cerrar diálogo
                  Navigator.pop(context); // Cerrar pantalla
                },
                child: const Text('No'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Cerrar diálogo
                  _printExtractionTicket(); // Iniciar impresión
                  // La pantalla se cerrará después de que termine la impresión
                },
                icon: const Icon(Icons.print),
                label: const Text('Sí, Imprimir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
    );
  }

  /// 🖨️ Método para imprimir ticket de extracción - Seleccionar tipo de impresora
  Future<void> _printExtractionTicket() async {
    try {
      print('🖨️ Iniciando impresión de ticket de extracción...');

      if (!mounted) return;

      // Verificar si hay productos para imprimir
      if (_selectedProducts.isEmpty) {
        if (mounted)
          _showErrorDialog('Error', 'No hay productos para imprimir');
        return;
      }

      // Mostrar diálogo de selección de tipo de impresora
      final printerType = await showDialog<String>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.print, color: Color(0xFF4A90E2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: const Text(
                      'Seleccionar Impresora',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('¿Cómo deseas imprimir el ticket?'),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.wifi, color: Color(0xFF10B981)),
                    title: const Text('Impresora WiFi'),
                    subtitle: const Text('Imprimir por red WiFi'),
                    onTap: () => Navigator.pop(context, 'wifi'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.bluetooth,
                      color: Color(0xFF4A90E2),
                    ),
                    title: const Text('Impresora Bluetooth'),
                    subtitle: const Text('Imprimir por Bluetooth'),
                    onTap: () => Navigator.pop(context, 'bluetooth'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
      );

      if (printerType == null || !mounted) return;

      if (printerType == 'wifi') {
        await _printExtractionTicketWiFi();
      } else {
        await _printExtractionTicketBluetooth();
      }
    } catch (e) {
      print('❌ Error en _printExtractionTicket: $e');
      if (mounted) {
        _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
      }
    }
  }

  /// 🖨️ Imprimir ticket usando WiFi
  Future<void> _printExtractionTicketWiFi() async {
    try {
      print('📶 Imprimiendo por WiFi...');

      if (!mounted) return;

      final wifiService = WiFiPrinterService();

      // Mostrar diálogo de selección de impresora WiFi
      final selectedPrinter = await wifiService.showPrinterSelectionDialog(
        context,
      );
      if (selectedPrinter == null) {
        print('❌ No se seleccionó impresora WiFi');
        return;
      }

      if (!mounted) return;

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF10B981)),
                  SizedBox(height: 16),
                  Text('Imprimiendo por WiFi...'),
                ],
              ),
            ),
      );

      // Conectar e imprimir
      bool connected = await wifiService.connectToPrinter(
        selectedPrinter['ip'],
        port: selectedPrinter['port'] ?? 9100,
      );

      if (!connected) {
        if (mounted) {
          Navigator.pop(context);
          _showErrorDialog(
            'Error de Conexión',
            'No se pudo conectar a la impresora WiFi',
          );
        }
        return;
      }

      // Generar ticket
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);

      // ========== IMPRIMIR COPIA 1: COMPROBANTE PRINCIPAL ==========
      print('📄 Imprimiendo copia 1: COMPROBANTE PRINCIPAL');
      List<int> bytes1 = _generateExtractionTicket(generator, copyNumber: 1);
      bool printed1 = await wifiService.sendRawBytes(bytes1);

      if (!printed1) {
        await wifiService.disconnect();
        if (!mounted) return;
        Navigator.pop(context);
        _showErrorDialog('Error', 'No se pudo imprimir la primera copia');
        return;
      }

      // Esperar entre impresiones
      print('⏳ Esperando 3 segundos antes de segunda copia...');
      await Future.delayed(const Duration(seconds: 3));

      // ========== IMPRIMIR COPIA 2: COMPROBANTE ALMACÉN ==========
      print('🏭 Imprimiendo copia 2: COMPROBANTE ALMACÉN');
      List<int> bytes2 = _generateExtractionTicket(generator, copyNumber: 2);
      bool printed2 = await wifiService.sendRawBytes(bytes2);

      await wifiService.disconnect();

      if (!mounted) return;
      Navigator.pop(context);

      if (printed1 && printed2) {
        print('✅ Ambas copias impresas exitosamente');
        _showSuccessDialog(
          '¡Impreso!',
          'Ambas copias se imprimieron correctamente por WiFi',
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pop(context); // Cerrar diálogo
            Navigator.pop(context); // Cerrar pantalla
          }
        });
      } else {
        print('⚠️ Solo se imprimió la primera copia');
        _showErrorDialog(
          'Advertencia',
          'Solo se pudo imprimir la primera copia',
        );
      }
    } catch (e) {
      print('❌ Error imprimiendo por WiFi: $e');
      if (mounted) {
        try {
          Navigator.pop(context);
        } catch (_) {}
        _showErrorDialog('Error WiFi', 'Error al imprimir por WiFi: $e');
      }
    }
  }

  /// 🖨️ Imprimir ticket usando Bluetooth
  Future<void> _printExtractionTicketBluetooth() async {
    try {
      print('📱 Imprimiendo por Bluetooth...');

      if (!mounted) return;

      final printerManager = PrinterManager();

      // Mostrar diálogo de confirmación
      bool shouldPrint = await printerManager.showPrintConfirmationDialog(
        context,
      );
      if (!shouldPrint || !mounted) return;

      // Seleccionar dispositivo Bluetooth
      final bluetoothService = printerManager.bluetoothService;
      var selectedDevice = await bluetoothService.showDeviceSelectionDialog(
        context,
      );
      if (selectedDevice == null || !mounted) return;

      // ✅ Verificar si el widget sigue montado
      if (!mounted) {
        print('⚠️ Widget desmontado después de seleccionar dispositivo');
        return;
      }

      // Paso 3: Mostrar diálogo de progreso - Conectando
      print('🔌 Paso 3: Conectando a impresora');
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Conectando a impresora...'),
                ],
              ),
            ),
      );

      // Conectar a la impresora
      bool connected = await bluetoothService.connectToDevice(selectedDevice);
      if (!connected) {
        if (mounted) {
          Navigator.pop(context);
          _showErrorDialog(
            'Conexión Fallida',
            'No se pudo conectar a la impresora',
          );
        }
        return;
      }

      // ✅ Verificar si el widget sigue montado
      if (!mounted) {
        print('⚠️ Widget desmontado después de conectar');
        await bluetoothService.disconnect();
        return;
      }

      // Paso 4: Actualizar diálogo - Imprimiendo
      print('🖨️ Paso 4: Imprimiendo ticket');
      Navigator.pop(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Imprimiendo ticket...'),
                ],
              ),
            ),
      );

      // Generar y enviar tickets (2 copias)
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);

      // ========== IMPRIMIR COPIA 1: COMPROBANTE PRINCIPAL ==========
      print('📄 Imprimiendo copia 1: COMPROBANTE PRINCIPAL');
      List<int> bytes1 = _generateExtractionTicket(generator, copyNumber: 1);
      bool printed1 = await PrintBluetoothThermal.writeBytes(bytes1);

      if (!printed1) {
        await bluetoothService.disconnect();
        if (!mounted) return;
        Navigator.pop(context);
        _showErrorDialog('Error', 'No se pudo imprimir la primera copia');
        return;
      }

      // Esperar entre impresiones
      print('⏳ Esperando 3 segundos antes de segunda copia...');
      await Future.delayed(const Duration(seconds: 3));

      // ========== IMPRIMIR COPIA 2: COMPROBANTE ALMACÉN ==========
      print('🏭 Imprimiendo copia 2: COMPROBANTE ALMACÉN');
      List<int> bytes2 = _generateExtractionTicket(generator, copyNumber: 2);
      bool printed2 = await PrintBluetoothThermal.writeBytes(bytes2);

      // Desconectar
      await bluetoothService.disconnect();

      // ✅ Verificar si el widget sigue montado antes de cerrar diálogo
      if (!mounted) {
        print('⚠️ Widget desmontado antes de mostrar resultado');
        return;
      }

      // Paso 5: Cerrar diálogo y mostrar resultado
      print(' Paso 5: Mostrar resultado');
      Navigator.pop(context);

      if (printed1 && printed2) {
        if (mounted) {
          _showSuccessDialog(
            '¡Ticket Impreso!',
            'El ticket se imprimió correctamente',
          );
          // Cerrar la pantalla después de mostrar el éxito
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              Navigator.pop(context); // Cerrar diálogo de éxito
              Navigator.pop(context); // Cerrar pantalla de venta
            }
          });
        }
        print(' Ticket impreso exitosamente');
      } else {
        if (mounted) {
          _showErrorDialog(
            'Error de Impresión',
            'No se pudo imprimir el ticket',
          );
          // Cerrar la pantalla después de mostrar el error
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              Navigator.pop(context); // Cerrar diálogo de error
              Navigator.pop(context); // Cerrar pantalla de venta
            }
          });
        }
        print(' Error al imprimir ticket');
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.pop(context);
        } catch (_) {}
        _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
        // Cerrar la pantalla después de mostrar el error
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.pop(context); // Cerrar diálogo de error
            Navigator.pop(context); // Cerrar pantalla de venta
          }
        });
      }
      print(' Error en _printExtractionTicket: $e');
    }
  }

  /// Generar contenido del ticket de extracción
  List<int> _generateExtractionTicket(
    Generator generator, {
    int copyNumber = 1,
  }) {
    List<int> bytes = [];

    // Header
    bytes += generator.text(
      'INVENTTIA',
      styles: PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      'VENTA POR ACUERDO',
      styles: PosStyles(align: PosAlign.center, bold: true),
    );

    // Indicador de copia
    String copyLabel =
        copyNumber == 1 ? 'COMPROBANTE PRINCIPAL' : 'COMPROBANTE ALMACÉN';
    bytes += generator.text(
      copyLabel,
      styles: PosStyles(align: PosAlign.center, bold: true),
    );
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    // Información de la venta
    bytes += generator.text(
      'Cliente: ${_clienteController.text.isNotEmpty ? _clienteController.text : 'N/A'}',
      styles: PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      'Tipo: ${_selectedMotivoVenta?['denominacion'] ?? 'N/A'}',
      styles: PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      'Pago: ${_selectedMedioPago?['denominacion'] ?? 'N/A'}',
      styles: PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      'Fecha: ${DateTime.now().toString().split('.')[0]}',
      styles: PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );

    // Productos
    double total = 0;
    for (var product in _selectedProducts) {
      final cantidad = product['cantidad'] as double? ?? 0;
      final precio = product['precio'] as double? ?? 0;
      final subtotal = cantidad * precio;
      total += subtotal;

      String nombre = product['nombre'] ?? 'Producto';
      if (nombre.length > 28) nombre = nombre.substring(0, 25) + '...';

      bytes += generator.text(
        '${cantidad.toStringAsFixed(1)}x $nombre',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        '  \$${precio.toStringAsFixed(0)} = \$${subtotal.toStringAsFixed(0)}',
        styles: PosStyles(align: PosAlign.right),
      );
    }

    // Total
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'TOTAL: \$${total.toStringAsFixed(0)}',
      styles: PosStyles(align: PosAlign.right, bold: true),
    );

    // Observaciones
    if (_observacionesController.text.isNotEmpty) {
      bytes += generator.text(
        '----------------------------',
        styles: PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        'Obs: ${_observacionesController.text}',
        styles: PosStyles(align: PosAlign.left),
      );
    }

    // Footer
    bytes += generator.text(
      '----------------------------',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'Gracias por su compra',
      styles: PosStyles(align: PosAlign.center),
    );
    bytes += generator.emptyLines(2);
    bytes += generator.cut();

    return bytes;
  }

  /// Mostrar diálogo de error
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  /// Mostrar diálogo de éxito
  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('¡Genial!'),
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
    _priceController
        .text = ((widget.product['precio_venta'] as num?)?.toDouble() ?? 0.0)
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
      'sku_producto': widget.product['sku_producto'] ?? '',
      'denominacion_corta': widget.product['denominacion_corta'] ?? '',
      'sku_ubicacion': widget.sourceLocation?.name ?? '',
      'denominacion':
          widget.product['denominacion'] ??
          widget.product['nombre_producto'] ??
          '',
      'variante': _selectedVariant!['variante'] ?? '',
      'zona_nombre': widget.sourceLocation?.name ?? '',
      'meta': widget.product,
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
                        if (widget.product['sku_producto'] != null)
                          Text(
                            'SKU: ${widget.product['sku_producto']}',
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
                                color:
                                    isSelected
                                        ? AppColors.success.withOpacity(0.1)
                                        : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      isSelected
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
                                    color:
                                        isSelected
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
                                            color:
                                                isSelected
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
                          suffixText:
                              _selectedVariant?['presentacion_nombre'] ?? '',
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
                          if (price == null) {
                            return 'Ingrese un precio';
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
                      onPressed:
                          _selectedVariant == null ? null : _submitProduct,
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
