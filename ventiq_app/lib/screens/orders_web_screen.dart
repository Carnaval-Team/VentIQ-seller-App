import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/payment_method.dart';
import '../services/order_service.dart';
import '../services/payment_method_service.dart';
import '../services/printer_manager.dart';
import '../services/user_preferences_service.dart';
import '../services/store_config_service.dart';
import '../services/currency_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/notification_widget.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/bill_count_dialog.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sales_monitor_fab.dart';
import '../widgets/order_detail_view.dart';

class OrdersWebScreen extends StatefulWidget {
  const OrdersWebScreen({Key? key}) : super(key: key);

  @override
  State<OrdersWebScreen> createState() => _OrdersWebScreenState();
}

class _OrdersWebScreenState extends State<OrdersWebScreen> {
  final OrderService _orderService = OrderService();
  final PrinterManager _printerManager = PrinterManager();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  List<Order> _filteredOrders = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _allowDiscountOnVendedor = false;
  bool _isGeneratingCustomerInvoice = false;
  bool _allowPrintPendingOrders = false;
  double _usdRate = 0.0;
  bool _isLoadingUsdRate = false;
  Order? _selectedOrder;
  int _paymentRefreshKey = 0;
  String? _pendingOpenOrderId;

  @override
  void initState() {
    super.initState();
    _filteredOrders = _orderService.orders;
    _searchController.addListener(_onSearchChanged);
    _loadUsdRate();
    // Cargar órdenes desde Supabase y órdenes pendientes offline
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Capturar argumento de orden a abrir automáticamente
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic> && args['openOrderId'] != null) {
        _pendingOpenOrderId = args['openOrderId'] as String;
      }
      _loadOrdersFromSupabase();
      _loadDiscountPermission();
      _loadPrintPendingPermission();
    });
  }

  Future<void> _loadUsdRate() async {
    setState(() {
      _isLoadingUsdRate = true;
    });

    try {
      final rate = await CurrencyService.getUsdRate();
      setState(() {
        _usdRate = rate;
        _isLoadingUsdRate = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading USD rate: $e');
      setState(() {
        _usdRate = 420.0;
        _isLoadingUsdRate = false;
      });
    }
  }

  Future<void> _loadDiscountPermission() async {
    try {
      final storeId = await _userPreferencesService.getIdTienda();
      if (storeId == null) {
        debugPrint('⚠️ No se pudo obtener id_tienda para verificar descuentos');
        return;
      }
      final allow = await StoreConfigService.getAllowDiscountOnVendedor(
        storeId,
      );
      if (mounted) {
        setState(() {
          _allowDiscountOnVendedor = allow;
        });
      }
    } catch (e) {
      debugPrint('❌ Error cargando permiso de descuento: $e');
    }
  }

  Future<void> _loadPrintPendingPermission() async {
    try {
      final storeId = await _userPreferencesService.getIdTienda();
      if (storeId == null) {
        debugPrint(
          '⚠️ No se pudo obtener id_tienda para permitir impresión de pendientes',
        );
        return;
      }
      final allow = await StoreConfigService.getAllowPrintPending(storeId);
      if (mounted) {
        setState(() {
          _allowPrintPendingOrders = allow;
        });
      }
    } catch (e) {
      debugPrint('❌ Error cargando permiso de impresión de pendientes: $e');
    }
  }

  bool _isPendingForDiscount(Order order) {
    return order.status == OrderStatus.enviada ||
        order.status == OrderStatus.procesando ||
        order.status == OrderStatus.pagoConfirmado ||
        order.status == OrderStatus.pendienteDeSincronizacion;
  }

  void _showDiscountSheet(Order order) {
    final baseTotal = order.total;
    final TextEditingController valueController = TextEditingController();
    int selectedType = 1; // 1 = %
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        bool isSaving = false;
        String? error; // mensaje puntual (ej. supabase)

        return StatefulBuilder(
          builder: (context, setModalState) {
            double parsedValue = double.tryParse(valueController.text) ?? 0;
            if (parsedValue < 0) parsedValue = 0;

            final bool percentInvalid =
                selectedType == 1 && (parsedValue <= 0 || parsedValue > 100);
            final bool fixedInvalid =
                selectedType == 2 &&
                (parsedValue <= 0 || parsedValue > baseTotal);
            final bool hasValidationError = percentInvalid || fixedInvalid;

            final double effectiveValue =
                selectedType == 1
                    ? parsedValue.clamp(0, 100)
                    : parsedValue.clamp(0, baseTotal);

            double discountAmount =
                selectedType == 1
                    ? baseTotal * (effectiveValue / 100)
                    : effectiveValue;
            if (discountAmount > baseTotal) discountAmount = baseTotal;
            final double finalTotal = (baseTotal - discountAmount).clamp(
              0,
              double.maxFinite,
            );

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.65,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 12,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Aplicar descuento',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Total actual: \$${baseTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0D9FF)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.security_outlined,
                                color: const Color(0xFF6B4EFF),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Solo para órdenes pendientes. El descuento queda registrado junto a la operación.',
                                  style: TextStyle(
                                    color: Colors.grey[800],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Text(
                              'Tipo de descuento',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(width: 12),
                            ChoiceChip(
                              label: const Text('Porcentaje'),
                              selected: selectedType == 1,
                              onSelected: (_) {
                                setModalState(() {
                                  selectedType = 1;
                                });
                              },
                              selectedColor: const Color(0xFF6B4EFF).withValues(alpha: 0.15),
                              labelStyle: TextStyle(
                                color: selectedType == 1 ? const Color(0xFF6B4EFF) : Colors.grey[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('Monto fijo'),
                              selected: selectedType == 2,
                              onSelected: (_) {
                                setModalState(() {
                                  selectedType = 2;
                                });
                              },
                              selectedColor: const Color(0xFF6B4EFF).withValues(alpha: 0.15),
                              labelStyle: TextStyle(
                                color: selectedType == 2 ? const Color(0xFF6B4EFF) : Colors.grey[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              selectedType == 1 ? 'Porcentaje (0 - 100)' : 'Monto a descontar',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: TextField(
                          controller: valueController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,4}'),
                            ),
                          ],
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              selectedType == 1
                                  ? Icons.percent
                                  : Icons.attach_money,
                              color: const Color(0xFF6B4EFF),
                            ),
                            hintText:
                                selectedType == 1
                                    ? 'Ej: 10 para 10%'
                                    : 'Ej: 50.00',
                            filled: true,
                            fillColor: Colors.grey[100],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (_) {
                            setModalState(() {
                              error = null;
                            });
                          },
                        )),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Descuento',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '-\$${discountAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total con descuento',
                                    style: TextStyle(
                                      color: Colors.grey[900],
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    '\$${finalTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Color(0xFF10B981),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (hasValidationError) ...[
                          const SizedBox(height: 10),
                          Text(
                            percentInvalid
                                ? 'El porcentaje debe ser mayor que 0 y menor o igual a 100.'
                                : 'El monto debe ser mayor que 0 y no superar \$${baseTotal.toStringAsFixed(2)}.',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    isSaving
                                        ? null
                                        : () => Navigator.of(context).pop(),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed:
                                    isSaving || hasValidationError
                                        ? null
                                        : () async {
                                          final value =
                                              double.tryParse(
                                                valueController.text,
                                              ) ??
                                              0;
                                          setModalState(() {
                                            isSaving = true;
                                            error = null;
                                          });
                                          final result = await _orderService
                                              .applyManualDiscount(
                                                order: order,
                                                discountType: selectedType,
                                                discountValue: value,
                                              );
                                          setModalState(() {
                                            isSaving = false;
                                          });
                                          if (!mounted) return;
                                          if (result['success'] == true) {
                                            Navigator.of(context).pop();
                                            setState(() {
                                              _filteredOrders =
                                                  _orderService.orders;
                                            });
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Descuento aplicado. Total ahora: \$${(result['precioFinal'] as double).toStringAsFixed(2)}',
                                                ),
                                                backgroundColor: const Color(
                                                  0xFF10B981,
                                                ),
                                              ),
                                            );
                                          } else {
                                            setModalState(() {
                                              error =
                                                  result['error']?.toString() ??
                                                  'No se pudo aplicar el descuento';
                                            });
                                          }
                                        },
                                icon:
                                    isSaving
                                        ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                        : const Icon(Icons.check),
                                label: Text(
                                  isSaving ? 'Guardando...' : 'Aplicar',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6B4EFF),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _loadOrdersFromSupabase() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        debugPrint('🔌 Modo offline - Preservando cambios locales y recargando...');

        // Guardar cambios de estado locales antes de limpiar
        final localStateChanges = <String, OrderStatus>{};
        final pendingOperations =
            await _userPreferencesService.getPendingOperations();

        // Identificar órdenes que han sido modificadas offline
        for (final order in _orderService.orders) {
          // Capturar órdenes pendientes de sincronización
          if (order.status == OrderStatus.pendienteDeSincronizacion) {
            localStateChanges[order.id] = order.status;
          }

          // Capturar órdenes que tienen operaciones pendientes de cambio de estado
          for (final operation in pendingOperations) {
            if (operation['type'] == 'order_status_change' &&
                operation['order_id'] == order.id) {
              final newStatusString = operation['new_status'] as String;
              final newStatus = _stringToOrderStatus(newStatusString);
              if (newStatus != null) {
                localStateChanges[order.id] = newStatus;
                debugPrint(
                  '📋 Cambio de estado offline detectado: ${order.id} -> $newStatusString',
                );
              }
              break;
            }
          }
        }

        // Limpiar órdenes antes de cargar las nuevas
        _orderService.clearAllOrders();

        // Cargar órdenes sincronizadas desde cache
        final offlineData = await _userPreferencesService.getOfflineData();
        if (offlineData != null && offlineData['orders'] != null) {
          final ordersData = offlineData['orders'] as List<dynamic>;
          _orderService.transformSupabaseToOrdersPublic(ordersData);
          debugPrint(
            '✅ Órdenes sincronizadas cargadas desde cache: ${ordersData.length}',
          );
        }

        // Cargar órdenes pendientes de sincronización
        final pendingOrders = await _userPreferencesService.getPendingOrders();
        if (pendingOrders.isNotEmpty) {
          _orderService.addPendingOrdersToList(pendingOrders);
          debugPrint(
            '⏳ Órdenes pendientes de sincronización: ${pendingOrders.length}',
          );
        }

        // Aplicar cambios de estado offline después de cargar todas las órdenes
        if (localStateChanges.isNotEmpty) {
          debugPrint(
            '🔄 Aplicando ${localStateChanges.length} cambios de estado offline...',
          );
          for (final entry in localStateChanges.entries) {
            final orderId = entry.key;
            final newStatus = entry.value;

            final orderIndex = _orderService.orders.indexWhere(
              (order) => order.id == orderId,
            );
            if (orderIndex != -1) {
              final currentOrder = _orderService.orders[orderIndex];

              // Solo actualizar si el estado actual es diferente al cambio offline
              if (currentOrder.status != newStatus) {
                final updatedOrder = currentOrder.copyWith(status: newStatus);
                _orderService.orders[orderIndex] = updatedOrder;
                debugPrint(
                  '🔄 Estado aplicado: $orderId -> ${currentOrder.status} → ${newStatus.toString()}',
                );
              } else {
                debugPrint(
                  'ℹ️ Estado ya correcto: $orderId -> ${newStatus.toString()}',
                );
              }
            } else {
              debugPrint('⚠️ Orden no encontrada para restaurar estado: $orderId');
            }
          }

          // Verificar si hay operaciones pendientes que necesitan ser aplicadas
          final hasChanges = await _applyPendingStatusChanges();

          // Actualizar UI después de aplicar todos los cambios
          if (hasChanges) {
            debugPrint(
              '🔄 Forzando actualización de UI después de cambios de estado...',
            );
            setState(() {
              _filteredOrders = List.from(_orderService.orders);
              _filterOrders(); // Re-aplicar filtros si los hay
            });
          }
        }
      } else {
        debugPrint('🌐 Modo online - Cargando órdenes desde Supabase...');
        // Limpiar órdenes antes de cargar las nuevas para evitar mezclar usuarios
        _orderService.clearAllOrders();
        await _orderService.listOrdersFromSupabase();
        debugPrint('✅ Órdenes cargadas desde Supabase');
      }

      // Actualizar la UI después de cargar las órdenes
      if (mounted) {
        setState(() {
          _filteredOrders = _orderService.orders;
          _isLoading = false;
        });
        // Auto-abrir detalle si viene de crear orden
        if (_pendingOpenOrderId != null) {
          final orderId = _pendingOpenOrderId!;
          _pendingOpenOrderId = null;
          // Buscar la orden recién cargada
          final order = _orderService.getOrderById(orderId);
          if (order != null && mounted) {
            _showOrderDetails(order);
          } else {
            // Si no se encontró, buscar la más reciente como fallback
            final orders = _orderService.orders;
            if (orders.isNotEmpty && mounted) {
              _showOrderDetails(orders.first);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error cargando órdenes: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshOrders() async {
    // Recargar órdenes desde Supabase
    await _loadOrdersFromSupabase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterOrders();
    });
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home
        // Usar pushNamed en lugar de pushNamedAndRemoveUntil para mantener la persistencia
        Navigator.pushNamed(context, '/categories');
        break;
      case 1: // Preorden
        Navigator.pushNamed(context, '/preorder');
        break;
      case 2: // Órdenes (current)
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }

  void _filterOrders() {
    final allOrders = _orderService.orders;
    List<Order> filtered;

    if (_searchQuery.isEmpty) {
      // Crear una nueva lista para evitar modificar la original
      filtered = List<Order>.from(allOrders);
    } else {
      filtered =
          allOrders.where((order) {
            final buyerName = order.buyerName?.toLowerCase() ?? '';
            final buyerPhone = order.buyerPhone?.toLowerCase() ?? '';
            return buyerName.contains(_searchQuery) ||
                buyerPhone.contains(_searchQuery);
          }).toList();
    }

    // Ordenar por prioridad de estado y luego por fecha
    filtered.sort((a, b) {
      final aPriority = _getStatusPriority(a.status);
      final bPriority = _getStatusPriority(b.status);

      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }

      // Si tienen la misma prioridad, ordenar por fecha (más recientes primero)
      return b.fechaCreacion.compareTo(a.fechaCreacion);
    });
    _filteredOrders = filtered;
  }

  int _getStatusPriority(OrderStatus status) {
    switch (status) {
      case OrderStatus.pendienteDeSincronizacion:
        return 0; // Órdenes offline - prioridad máxima
      case OrderStatus.borrador:
        return 1; // Borradores - prioridad muy alta
      case OrderStatus.enviada:
      case OrderStatus.procesando:
        return 2; // Pendientes - prioridad alta
      case OrderStatus.pagoConfirmado:
        return 3; // Pago confirmado - prioridad media
      case OrderStatus.completada:
      case OrderStatus.cancelada:
      case OrderStatus.devuelta:
        return 4; // Finalizadas - prioridad baja
    }
  }

  @override
  Widget build(BuildContext context) {
    _filterOrders();
    final orders = _filteredOrders;

    if (_selectedOrder != null) {
      return _buildFullScreenOrderDetail(_selectedOrder!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes'),
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacementNamed(context, '/preorder');
            }
          },
        ),
        actions: [
          const NotificationWidget(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshOrders,
            tooltip: 'Actualizar órdenes',
          ),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFF4A90E2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Cargando órdenes...',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshOrders,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Buscar por cliente o teléfono...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ),
                      Expanded(
                        child: orders.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'No hay órdenes registradas'
                                          : 'No se encontraron órdenes para "$_searchQuery"',
                                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: orders.length,
                                itemBuilder: (context, index) {
                                  final order = orders[index];
                                  return _buildOrderCard(order);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
          const Positioned(
            bottom: 16,
            left: 16,
            child: SyncStatusChip(),
          ),
        ],
      ),
      endDrawer: const AppDrawer(),
      floatingActionButton: const SalesMonitorFAB(),
    );
  }

  Widget _buildOrderCard(Order order) {
    final statusColor = _getStatusColor(order.status);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showOrderDetails(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con ID y estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A90E2).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.receipt_long_outlined,
                            size: 18,
                            color: Color(0xFF4A90E2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            order.id,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_getCarnavalOrderId(order.notas) != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.purple.withOpacity(0.2),
                              ),
                            ),
                            child: const Text(
                              'Carnaval',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.status.displayName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Cliente y fecha
              Row(
                children: [
                  if (order.buyerName != null) ...[
                    Icon(
                      Icons.person_rounded,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        order.buyerName!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey[400]),
                  const SizedBox(width: 6),
                  Text(
                    _formatDate(order.fechaCreacion),
                    style: TextStyle(
                      fontSize: 13, 
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Información de productos y total
              Builder(
                builder: (_) {
                  final discountData = _getDiscountData(order);
                  final hasDiscount = discountData['hasDiscount'] as bool;
                  final displayTotal =
                      discountData['finalTotal'] as double? ?? order.total;
                  final saved = discountData['saved'] as double? ?? 0;
                  final label = discountData['label'] as String?;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${order.totalItems} ${order.totalItems == 1 ? 'producto' : 'productos'}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '\$${displayTotal.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: hasDiscount
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF4A90E2),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.local_offer_outlined, size: 12, color: Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$label · Ahorras \$${saved.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // Preview de productos y botón de impresión
              if (order.items.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.items.take(3).map((item) => item.nombre).join(', ') + (order.items.length > 3 ? '...' : ''),
                        style: TextStyle(
                          fontSize: 12, 
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_canPrintOrder(order))
                      IconButton(
                        onPressed: () => _printOrder(order),
                        icon: const Icon(Icons.print_outlined),
                        iconSize: 20,
                        color: const Color(0xFF4A90E2),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Imprimir factura',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.borrador:
        return Colors.orange;
      case OrderStatus.enviada:
        return const Color(0xFF4A90E2);
      case OrderStatus.procesando:
        return Colors.amber;
      case OrderStatus.completada:
        return Colors.green;
      case OrderStatus.cancelada:
        return Colors.red;
      case OrderStatus.devuelta:
        return const Color(0xFFFF6B35);
      case OrderStatus.pagoConfirmado:
        return const Color(0xFF10B981);
      case OrderStatus.pendienteDeSincronizacion:
        return const Color(0xFFFF8C00); // Naranja oscuro para offline
    }
  }

  String? _getCarnavalOrderId(String? notas) {
    if (notas == null) return null;
    final regex = RegExp(r'Venta desde orden (\d+)');
    final match = regex.firstMatch(notas);
    return match?.group(1);
  }

  bool _canPrintOrder(Order order) {
    if (order.status == OrderStatus.pagoConfirmado ||
        order.status == OrderStatus.completada) {
      return true;
    }
    if (_allowPrintPendingOrders && order.status == OrderStatus.enviada) {
      return true;
    }
    final isCarnavalOrder = _getCarnavalOrderId(order.notas) != null;
    if (isCarnavalOrder &&
        (order.status == OrderStatus.enviada ||
            order.status == OrderStatus.procesando ||
            order.status == OrderStatus.pendienteDeSincronizacion)) {
      return true;
    }

    return false;
  }

  String _formatDate(DateTime date) {
    // Convert to local time if it's not already
    final localDate = date.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDate);

    if (difference.inDays == 0) {
      return 'Hoy ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Ayer ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} días atrás';
    } else {
      return '${localDate.day}/${localDate.month}/${localDate.year}';
    }
  }

  void _showOrderDetails(Order order) {
    setState(() {
      _selectedOrder = order;
      _paymentRefreshKey = 0;
    });
  }

  void _closeOrderDetails() {
    setState(() {
      _selectedOrder = null;
    });
  }

  Widget _buildFullScreenOrderDetail(Order order) {
    final statusColor = _getStatusColor(order.status);
    final discountData = _getDiscountData(order);

    Widget? carnavalStatus;
    if (_getCarnavalOrderId(order.notas) != null) {
      carnavalStatus = FutureBuilder<String?>(
        future: _orderService.getCarnavalOrderStatus(
          _getCarnavalOrderId(order.notas)!,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Estado Carnaval:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                  Text(snapshot.data!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      );
    }

    Widget? paymentBreakdown;
    if (order.operationId != null) {
      paymentBreakdown = _buildPaymentBreakdown(
        order,
        refreshKey: _paymentRefreshKey,
        onPaymentUpdated: () {
          setState(() {
            _paymentRefreshKey++;
          });
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: Text('Orden ${order.id}'),
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeOrderDetails,
        ),
      ),
      body: OrderDetailView(
        order: order,
        statusColor: statusColor,
        carnavalStatus: carnavalStatus,
        paymentBreakdown: paymentBreakdown,
        primaryActions: _buildPrimaryActions(order),
        actionButtons: _buildSecondaryActions(order),
        onClose: _closeOrderDetails,
        discountData: discountData,
      ),
    );
  }

  // ── Primary actions: Cancel + Confirm Pago — shown in top hero area ──
  Widget? _buildPrimaryActions(Order order) {
    final isPending = order.status != OrderStatus.cancelada &&
        order.status != OrderStatus.devuelta &&
        order.status != OrderStatus.completada;
    if (!isPending) return null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _miniActionBtn(
          icon: Icons.cancel_outlined,
          label: 'Cancelar',
          color: const Color(0xFFEF4444),
          filled: false,
          onTap: () => _showConfirmationDialog(
            order,
            OrderStatus.cancelada,
            'Cancelar Orden',
            '¿Estás seguro de que quieres cancelar esta orden?',
            Colors.red,
          ),
        ),
        const SizedBox(width: 8),
        FutureBuilder<bool>(
          future: _hasEffectivoPayment(order),
          builder: (context, snapshot) {
            return _miniActionBtn(
              icon: Icons.check_circle_outline,
              label: 'Confirmar Pago',
              color: const Color(0xFF10B981),
              filled: true,
              onTap: () => _showConfirmationDialog(
                order,
                OrderStatus.completada,
                'Confirmar Pago',
                '¿Confirmas que el pago de esta orden ha sido recibido?',
                const Color(0xFF10B981),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _miniActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: filled ? null : Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: filled ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Secondary actions: bottom toolbar, single row ──
  Widget _buildSecondaryActions(Order order) {
    final isPending = order.status != OrderStatus.cancelada &&
        order.status != OrderStatus.devuelta &&
        order.status != OrderStatus.completada;

    final List<Widget> buttons = [];

    if (_canPrintOrder(order)) {
      buttons.add(_toolbarBtn(
        icon: Icons.print_outlined,
        label: 'Imprimir',
        color: const Color(0xFF4A90E2),
        onTap: () => _printOrder(order),
      ));
    }

    if (order.status == OrderStatus.completada) {
      buttons.add(_toolbarBtn(
        icon: _isGeneratingCustomerInvoice ? Icons.hourglass_top_rounded : Icons.picture_as_pdf_outlined,
        label: _isGeneratingCustomerInvoice ? 'Generando...' : 'Factura',
        color: const Color(0xFF10B981),
        onTap: _isGeneratingCustomerInvoice
            ? null
            : () {
                _closeOrderDetails();
                Future.microtask(() => _generateCustomerInvoice(order));
              },
      ));
    }

    if (isPending) {
      if (_allowDiscountOnVendedor && _isPendingForDiscount(order)) {
        buttons.add(_toolbarBtn(
          icon: Icons.percent_rounded,
          label: 'Descuento',
          color: const Color(0xFF6B4EFF),
          onTap: () => _showDiscountSheet(order),
        ));
      }

      buttons.add(_toolbarBtn(
        icon: Icons.keyboard_return_rounded,
        label: 'Devolver',
        color: const Color(0xFFFF6B35),
        onTap: () => _showConfirmationDialog(
          order,
          OrderStatus.devuelta,
          'Devolver Orden',
          '¿Estás seguro de que quieres marcar esta orden como devuelta?',
          const Color(0xFFFF6B35),
        ),
      ));

    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    // Wrap in FutureBuilder to conditionally add "Contar Billetes" button
    if (isPending) {
      return FutureBuilder<bool>(
        future: _hasEffectivoPayment(order),
        builder: (context, snapshot) {
          final allButtons = [...buttons];
          final hasEfectivo = snapshot.data ?? false;
          if (hasEfectivo) {
            allButtons.add(_toolbarBtn(
              icon: Icons.calculate_outlined,
              label: 'Billetes',
              color: const Color(0xFF4A90E2),
              onTap: () => _showBillCountDialog(order),
            ));
          }
          return Row(
            children: allButtons
                .expand((btn) => [
                      Expanded(child: btn),
                      const SizedBox(width: 8),
                    ])
                .toList()
              ..removeLast(),
          );
        },
      );
    }

    return Row(
      children: buttons
          .expand((btn) => [
                Expanded(child: btn),
                const SizedBox(width: 8),
              ])
          .toList()
        ..removeLast(),
    );
  }

  Widget _toolbarBtn({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
            color: color.withValues(alpha: 0.04),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 18 : 16,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? const Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(OrderItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '\$${item.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text('Cant: ${item.cantidad}', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 16),
              const Icon(Icons.warehouse_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(item.ubicacionAlmacen, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
          if (item.ingredientes != null && item.ingredientes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(),
            const Text(
              'Ingredientes:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            ...item.ingredientes!.map((ing) => Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(
                '• ${ing['nombre_ingrediente']} (${ing['cantidad_vendida']} ${ing['unidad_medida'] ?? ''})',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(Order order) {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Acciones:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 12),

        // Botón de imprimir (siempre disponible para órdenes con pago confirmado o completadas)
        if (_canPrintOrder(order)) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _printOrder(order),
              icon: const Icon(Icons.print),
              label: const Text('Imprimir Factura'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

                if (order.status == OrderStatus.completada) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isGeneratingCustomerInvoice
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  Future.microtask(() => _generateCustomerInvoice(order));
                                },
                      icon:
                          _isGeneratingCustomerInvoice
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        _isGeneratingCustomerInvoice
                            ? 'Generando factura...'
                            : 'Generar factura cliente',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Botones de gestión solo para órdenes que no estén en estado final
                if (order.status != OrderStatus.cancelada &&
                    order.status != OrderStatus.devuelta &&
                    order.status != OrderStatus.completada) ...[
                  if (_allowDiscountOnVendedor && _isPendingForDiscount(order)) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _showDiscountSheet(order),
                        icon: const Icon(Icons.percent),
                        label: const Text('Realizar descuento'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B4EFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      // Botón Cancelar
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              () => _showConfirmationDialog(
                                order,
                                OrderStatus.cancelada,
                                'Cancelar Orden',
                                '¿Estás seguro de que quieres cancelar esta orden?',
                                Colors.red,
                              ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancelar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botón Devolver
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              () => _showConfirmationDialog(
                                order,
                                OrderStatus.devuelta,
                                'Devolver Orden',
                                '¿Estás seguro de que quieres marcar esta orden como devuelta?',
                                const Color(0xFFFF6B35),
                              ),
                          icon: const Icon(Icons.keyboard_return),
                          label: const Text('Devolver'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF6B35),
                            side: const BorderSide(color: Color(0xFFFF6B35)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Botones de pago - Contar Billetes y Confirmar Pago
                  FutureBuilder<bool>(
                    future: _hasEffectivoPayment(order),
                    builder: (context, snapshot) {
                      final hasEfectivo = snapshot.data ?? false;

                      if (hasEfectivo) {
                        // Si tiene efectivo, mostrar ambos botones
                        return Column(
                          children: [
                            // Fila con Contar Billetes y Confirmar Pago
                            Row(
                              children: [
                                // Botón Contar Billetes
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      _showBillCountDialog(order);
                                    },
                                    icon: const Icon(Icons.calculate_outlined),
                                    label: const Text('Contar Billetes'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF4A90E2),
                                      side: const BorderSide(color: Color(0xFF4A90E2)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Botón Confirmar Pago
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed:
                                        () => _showConfirmationDialog(
                                          order,
                                          OrderStatus.completada,
                                          'Confirmar Pago',
                                          '¿Confirmas que el pago de esta orden ha sido recibido?',
                                          const Color(0xFF10B981),
                                        ),
                                    icon: const Icon(Icons.payment),
                                    label: const Text('Confirmar Pago'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      } else {
                        // Si no tiene efectivo, solo mostrar Confirmar Pago
                        return SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                () => _showConfirmationDialog(
                                  order,
                                  OrderStatus.completada,
                                  'Confirmar Pago',
                                  '¿Confirmas que el pago de esta orden ha sido recibido?',
                                  const Color(0xFF10B981),
                                ),
                            icon: const Icon(Icons.payment),
                            label: const Text('Confirmar Pago'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
      ],
    );
  }

  /// Mostrar diálogo de conteo de billetes
  void _showBillCountDialog(Order order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, // No se puede cerrar tocando fuera
      enableDrag: false, // No se puede cerrar arrastrando
      builder:
          (context) => BillCountDialog(
            order: order,
            userPreferencesService: _userPreferencesService,
            onConfirmPayment: () {
              // Confirmar el pago después del conteo
              _updateOrderStatus(order, OrderStatus.completada);
            },
          ),
    );
  }

  void _showConfirmationDialog(
    Order order,
    OrderStatus newStatus,
    String title,
    String message,
    Color color,
  ) async {
    // Verificar si es cancelación y si se requiere contraseña maestra
    if (newStatus == OrderStatus.cancelada) {
      try {
        final storeConfig = await _userPreferencesService.getStoreConfig();
        if (storeConfig != null &&
            storeConfig['need_master_password_to_cancel'] == true) {
          _showMasterPasswordDialog(order, newStatus, title, message, color);
          return;
        }
      } catch (e) {
        debugPrint('❌ Error al verificar configuración de contraseña maestra: $e');
        // Continuar con el flujo normal si hay error en la configuración
      }
    }

    // Flujo normal para otros estados o cuando no se requiere contraseña maestra
    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _updateOrderStatus(order, newStatus);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirmar'),
              ),
            ],
          ),
    );
  }

  Future<void> _updateOrderStatus(Order order, OrderStatus newStatus) async {
    // Mostrar indicador de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF4A90E2)),
                const SizedBox(height: 16),
                const Text('Actualizando estado...'),
              ],
            ),
          ),
    );

    try {
      final result = await _orderService.updateOrderStatus(order.id, newStatus);

      if (mounted) Navigator.pop(context); // Cerrar indicador de carga

      if (result['success'] == true) {
        if (mounted) {
          // Guardar ID para re-seleccionar después de recargar
          final orderId = order.id;
          await _loadOrdersFromSupabase();
          if (mounted) {
            // Re-seleccionar la orden actualizada
            final updatedOrder = _orderService.getOrderById(orderId);
            if (updatedOrder != null) {
              setState(() {
                _selectedOrder = updatedOrder;
              });
            }
          }

          String statusMessage = '';
          switch (newStatus) {
            case OrderStatus.cancelada:
              statusMessage = 'Orden cancelada exitosamente';
              break;
            case OrderStatus.devuelta:
              statusMessage = 'Orden marcada como devuelta';
              break;
            case OrderStatus.completada:
            case OrderStatus.pagoConfirmado:
              statusMessage = 'Pago confirmado exitosamente';
              _checkAndShowPrintDialog(order);
              break;
            default:
              statusMessage = 'Estado actualizado correctamente';
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(statusMessage),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          _showErrorDialog(
            'Error al actualizar estado',
            result['error'] ?? 'No se pudo actualizar el estado de la orden',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Cerrar indicador de carga si hay excepción
        _showErrorDialog(
          'Error de conexión',
          'No se pudo conectar con el servidor. Verifica tu conexión a internet.',
        );
        debugPrint('Error en _updateOrderStatus: $e');
      }
    }
  }

  Widget _buildPaymentBreakdown(
    Order order, {
    int refreshKey = 0,
    VoidCallback? onPaymentUpdated,
  }) {
    final operationId = order.operationId;
    if (operationId == null) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('payment-breakdown-$refreshKey'),
      future: _orderService.getSalePayments(operationId),
      builder: (context, snapshot) {
        final payments = snapshot.data ?? [];
        final canEdit = _canEditPaymentBreakdown(order) && payments.isNotEmpty;

        Widget header = Row(
          children: [
            Icon(Icons.payments_outlined, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Desglose de Pagos',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            if (canEdit)
              InkWell(
                onTap: () => _showPaymentBreakdownEditor(
                  order,
                  payments,
                  onUpdated: onPaymentUpdated,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 4),
                      const Text(
                        'Editar',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4F46E5)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey[400])),
                    const SizedBox(width: 10),
                    Text('Cargando pagos...', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                  ],
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError || payments.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'No hay información de pagos disponible',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400], fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          );
        }

        final totalPaid = payments.fold<double>(
          0.0,
          (sum, payment) => sum + _resolvePaymentAmount(payment),
        );
        final double? usdTotal =
            _usdRate > 0 ? totalPaid / _usdRate : null;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 14),
              // Lista de pagos en 2 columnas
              for (int i = 0; i < payments.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildPaymentCard(payments[i])),
                      const SizedBox(width: 8),
                      if (i + 1 < payments.length)
                        Expanded(child: _buildPaymentCard(payments[i + 1]))
                      else
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              // Resumen total
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFCDE7C8)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 18, color: const Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Total pagado',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                    Text(
                      '\$${totalPaid.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                    if (_usdRate > 0) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _isLoadingUsdRate
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF2E7D32)),
                              )
                            : Text(
                                'USD \$${usdTotal?.toStringAsFixed(2) ?? 'N/D'} (${_usdRate.toStringAsFixed(2)})',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    final methodColor = _getPaymentMethodColor(payment);
    final hasDiscount = payment['importe_sin_descuento'] != null &&
        (payment['importe_sin_descuento'] as num).toDouble() !=
            (payment['monto'] ?? 0.0).toDouble();
    final double paymentAmount = (payment['monto'] != null && payment['monto'] is num)
        ? (payment['monto'] as num).toDouble()
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: methodColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getPaymentMethodIcon(payment),
              size: 16,
              color: methodColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _resolvePaymentMethodName(payment),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                if (payment['referencia_pago'] != null &&
                    payment['referencia_pago'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Ref: ${payment['referencia_pago']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  ),
              ],
            ),
          ),
          if (hasDiscount) ...[
            Text(
              '\$${(payment['importe_sin_descuento'] as num).toDouble().toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.grey[400],
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Text(
            '\$${paymentAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: methodColor,
            ),
          ),
        ],
      ),
    );
  }

  bool _canEditPaymentBreakdown(Order order) {
    return _isPendingForDiscount(order);
  }

  int _resolvePaymentMethodId(Map<String, dynamic> payment) {
    final id = payment['medio_pago_id'] ?? payment['id_medio_pago'];
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '') ?? 0;
  }

  String _resolvePaymentMethodName(Map<String, dynamic> payment) {
    final name =
        payment['medio_pago_denominacion'] ??
        payment['medio_pago_nombre'] ??
        payment['denominacion'];
    if (name is String && name.trim().isNotEmpty) {
      return name;
    }
    return _getCustomPaymentMethodName(payment);
  }

  double _resolvePaymentAmount(Map<String, dynamic> payment) {
    final amount = payment['monto'];
    if (amount is num) return amount.toDouble();
    return double.tryParse(amount?.toString() ?? '') ?? 0.0;
  }

  Color _getPaymentMethodColorFromMethod(PaymentMethod method) {
    if (method.esEfectivo) {
      return Colors.green;
    } else if (method.esDigital) {
      return Colors.blue;
    }
    return Colors.orange;
  }

  Future<List<PaymentMethod>> _loadPaymentMethodsForEdit() async {
    final isOfflineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();
    if (isOfflineModeEnabled) {
      final paymentMethodsData =
          await _userPreferencesService.getPaymentMethodsOffline();
      return paymentMethodsData
          .map((data) => PaymentMethod.fromJson(data))
          .toList();
    }
    return PaymentMethodService.getActivePaymentMethods();
  }

  Future<void> _showPaymentBreakdownEditor(
    Order order,
    List<Map<String, dynamic>> payments, {
    VoidCallback? onUpdated,
  }) async {
    final operationId = order.operationId;
    if (operationId == null) return;

    final isOfflineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();
    if (isOfflineModeEnabled) {
      _showErrorDialog(
        'Modo offline',
        'Para editar el desglose de pagos necesitas conexión.',
      );
      return;
    }

    final amountController = TextEditingController();
    Map<String, dynamic>? selectedSource;
    PaymentMethod? selectedTarget;
    bool isSaving = false;
    String? errorMessage;
    Future<List<PaymentMethod>>? paymentMethodsFuture;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 12,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 16,
                      bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Editar desglose de pagos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Mueve un monto desde un método existente hacia otro.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 20),
                        FutureBuilder<List<PaymentMethod>>(
                          future:
                              paymentMethodsFuture ??=
                                  _loadPaymentMethodsForEdit(),
                          builder: (context, methodsSnapshot) {
                            if (methodsSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: const Row(
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Cargando métodos de pago...'),
                                  ],
                                ),
                              );
                            }

                            if (!methodsSnapshot.hasData ||
                                methodsSnapshot.data!.isEmpty) {
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red[200]!),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.warning_amber,
                                      color: Colors.red[400],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'No pudimos cargar los métodos de pago.',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Revisa tu conexión y vuelve a intentarlo.',
                                          ),
                                          const SizedBox(height: 10),
                                          OutlinedButton(
                                            onPressed: () {
                                              setModalState(() {
                                                paymentMethodsFuture =
                                                    _loadPaymentMethodsForEdit();
                                              });
                                            },
                                            child: const Text('Reintentar'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final methods = methodsSnapshot.data!;
                            final sourceAmount =
                                selectedSource == null
                                    ? 0.0
                                    : _resolvePaymentAmount(selectedSource!);
                            final amountToMove =
                                double.tryParse(amountController.text) ?? 0.0;
                            final sourceId =
                                selectedSource == null
                                    ? null
                                    : _resolvePaymentMethodId(selectedSource!);
                            final isAmountValid =
                                amountToMove > 0 &&
                                amountToMove <= sourceAmount;
                            final canSave =
                                selectedSource != null &&
                                selectedTarget != null &&
                                isAmountValid &&
                                !isSaving;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Origen',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: payments.map((payment) {
                                    final isSelected = identical(payment, selectedSource);
                                    final accentColor = _getPaymentMethodColor(payment);
                                    final paymentAmount = _resolvePaymentAmount(payment);
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: payment != payments.last ? 10 : 0,
                                        ),
                                        child: GestureDetector(
                                          onTap: () {
                                            setModalState(() {
                                              selectedSource = payment;
                                              errorMessage = null;
                                              final currentAmount = double.tryParse(amountController.text) ?? 0.0;
                                              if (currentAmount <= 0 || currentAmount > paymentAmount) {
                                                amountController.text = paymentAmount.toStringAsFixed(2);
                                              }
                                              if (selectedTarget != null &&
                                                  selectedTarget!.id == _resolvePaymentMethodId(payment)) {
                                                selectedTarget = null;
                                              }
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 180),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: isSelected ? accentColor.withValues(alpha: 0.12) : Colors.white,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: isSelected ? accentColor : Colors.grey[200]!,
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: accentColor,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(_getPaymentMethodIcon(payment), size: 16, color: Colors.white),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        _resolvePaymentMethodName(payment),
                                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1F2937)),
                                                      ),
                                                      Text(
                                                        '\$${paymentAmount.toStringAsFixed(2)}',
                                                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (isSelected)
                                                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Destino',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: methods.map((method) {
                                    final isDisabled = sourceId != null && method.id == sourceId;
                                    final isSelected = method == selectedTarget;
                                    final accentColor = _getPaymentMethodColorFromMethod(method);
                                    return Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          right: method != methods.last ? 10 : 0,
                                        ),
                                        child: GestureDetector(
                                          onTap: isDisabled
                                              ? null
                                              : () {
                                                  setModalState(() {
                                                    selectedTarget = method;
                                                    errorMessage = null;
                                                  });
                                                },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 180),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: isDisabled
                                                  ? Colors.grey[100]
                                                  : isSelected
                                                      ? accentColor.withValues(alpha: 0.12)
                                                      : Colors.white,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: isSelected ? accentColor : Colors.grey[200]!,
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: isDisabled ? Colors.grey[300] : accentColor,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(method.typeIcon, size: 16, color: Colors.white),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        method.denominacion,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 13,
                                                          color: isDisabled ? Colors.grey[400] : const Color(0xFF1F2937),
                                                        ),
                                                      ),
                                                      Text(
                                                        isDisabled ? 'Es el origen' : 'Mover aquí',
                                                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (isSelected)
                                                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: amountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d+\.?\d{0,2}'),
                                    ),
                                  ],
                                  onChanged: (_) {
                                    setModalState(() {
                                      errorMessage = null;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Monto a mover',
                                    prefixText: '\$',
                                    helperText:
                                        selectedSource == null
                                            ? 'Selecciona un origen primero'
                                            : 'Máximo disponible: \$${sourceAmount.toStringAsFixed(2)}',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('Monto a transferir'),
                                          Text(
                                            '\$${amountToMove.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2563EB),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Text('Origen: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                                Flexible(
                                                  child: Text(
                                                    selectedSource == null ? '--' : _resolvePaymentMethodName(selectedSource!),
                                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF9CA3AF)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                Text('Destino: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                                                Flexible(
                                                  child: Text(
                                                    selectedTarget?.denominacion ?? '--',
                                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isAmountValid &&
                                    selectedSource != null &&
                                    amountToMove > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      'El monto supera el disponible del método origen.',
                                      style: TextStyle(
                                        color: Colors.red[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                if (errorMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      errorMessage!,
                                      style: TextStyle(
                                        color: Colors.red[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed:
                                            isSaving
                                                ? null
                                                : () => Navigator.pop(context),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: const Text('Cancelar'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed:
                                            canSave
                                                ? () async {
                                                  setModalState(() {
                                                    isSaving = true;
                                                    errorMessage = null;
                                                  });
                                                  final result = await _orderService
                                                      .moveSalePaymentAmount(
                                                        operationId:
                                                            operationId,
                                                        fromPaymentMethodId:
                                                            _resolvePaymentMethodId(
                                                              selectedSource!,
                                                            ),
                                                        toPaymentMethodId:
                                                            selectedTarget!.id,
                                                        amount: amountToMove,
                                                      );
                                                  if (!mounted) return;
                                                  if (result['success'] ==
                                                      true) {
                                                    Navigator.pop(context);
                                                    onUpdated?.call();
                                                    setState(() {});
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Desglose actualizado correctamente',
                                                        ),
                                                        backgroundColor:
                                                            Colors.green,
                                                      ),
                                                    );
                                                  } else {
                                                    setModalState(() {
                                                      isSaving = false;
                                                      errorMessage =
                                                          result['error'] ??
                                                          'No se pudo actualizar el desglose.';
                                                    });
                                                  }
                                                }
                                                : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF4A90E2,
                                          ),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                        ),
                                        child:
                                            isSaving
                                                ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                                : const Text('Guardar cambio'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );

    amountController.dispose();
  }

  Color _getPaymentMethodColor(Map<String, dynamic> payment) {
    final esEfectivo = payment['medio_pago_es_efectivo'] ?? false;
    final esDigital = payment['medio_pago_es_digital'] ?? false;

    if (esEfectivo) {
      return Colors.green;
    } else if (esDigital) {
      return Colors.blue;
    } else {
      return Colors.orange;
    }
  }

  IconData _getPaymentMethodIcon(Map<String, dynamic> payment) {
    final esEfectivo = payment['medio_pago_es_efectivo'] ?? false;
    final esDigital = payment['medio_pago_es_digital'] ?? false;

    if (esEfectivo) {
      return Icons.payments;
    } else if (esDigital) {
      return Icons.credit_card;
    } else {
      return Icons.account_balance;
    }
  }

  /// Verificar si la orden tiene pagos en efectivo
  Future<bool> _hasEffectivoPayment(Order order) async {
    if (order.operationId == null) return false;

    try {
      final payments = await _orderService.getSalePayments(order.operationId!);
      return payments.any(
        (payment) => payment['medio_pago_es_efectivo'] == true,
      );
    } catch (e) {
      debugPrint('❌ Error verificando pagos en efectivo: $e');
      return false;
    }
  }

  /// Calcula información de descuento para mostrar totales e info
  Map<String, dynamic> _getDiscountData(Order order) {
    final descuento = order.descuento;
    if (descuento == null) {
      return {
        'hasDiscount': false,
        'originalTotal': order.total,
        'finalTotal': order.total,
        'saved': 0.0,
        'label': null,
      };
    }

    final double montoReal =
        (descuento['monto_real'] as num?)?.toDouble() ?? order.total;
    final double montoDescontado =
        (descuento['monto_descontado'] as num?)?.toDouble() ?? 0.0;
    final int tipo = (descuento['tipo_descuento'] as num?)?.toInt() ?? 1;
    final double valor =
        (descuento['valor_descuento'] as num?)?.toDouble() ?? 0.0;

    final double finalTotal = (montoReal - montoDescontado).clamp(
      0,
      double.maxFinite,
    );
    final bool isPercent = tipo == 1;
    final String label =
        isPercent
            ? 'Descuento ${valor.toStringAsFixed(0)}%'
            : 'Descuento fijo \$${valor.toStringAsFixed(2)}';

    return {
      'hasDiscount': true,
      'originalTotal': montoReal,
      'finalTotal': finalTotal,
      'saved': montoDescontado,
      'label': label,
    };
  }

  Future<void> _generateCustomerInvoice(Order order) async {
    debugPrint('📄 Generar factura cliente (PDF) - Orden: ${order.id}');

    // Web aún no soporta shareXFiles con filesystem temporal
    if (PlatformUtils.isWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La generación/compartir de factura en PDF no está disponible en Web en esta versión.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    bool didShowDialog = false;
    if (mounted) {
      didShowDialog = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            content: Row(
              children: const [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Generando factura en PDF...')),
              ],
            ),
          );
        },
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Generando factura PDF...'),
          backgroundColor: Colors.blueAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }

    setState(() {
      _isGeneratingCustomerInvoice = true;
    });

    try {
      final storeId = await _userPreferencesService.getIdTienda();
      debugPrint('🏪 StoreId para factura: $storeId');
      Map<String, dynamic>? storeData;

      if (storeId != null) {
        storeData =
            await Supabase.instance.client
                .from('app_dat_tienda')
                .select('denominacion, direccion, ubicacion, imagen_url, phone')
                .eq('id', storeId)
                .maybeSingle();
      }

      final storeName = storeData?['denominacion'] as String? ?? 'VentIQ';
      final storeAddress = storeData?['direccion'] as String? ?? '';
      final storeLocation = storeData?['ubicacion'] as String? ?? '';
      final storePhone = storeData?['phone'] as String? ?? '';
      final storeLogoUrl = storeData?['imagen_url'] as String?;
      debugPrint('🏪 Tienda: $storeName');
      final logoBytes = await _downloadImageBytes(storeLogoUrl);

      final discountData = _getDiscountData(order);
      final hasDiscount = discountData['hasDiscount'] as bool;
      final double originalTotal =
          (discountData['originalTotal'] as num?)?.toDouble() ?? order.total;
      final double finalTotal =
          (discountData['finalTotal'] as num?)?.toDouble() ?? order.total;
      final double saved = (discountData['saved'] as num?)?.toDouble() ?? 0.0;
      final String discountLabel = discountData['label'] as String? ?? '';
      final items = order.items.where((item) => item.subtotal > 0).toList();
      final ingredientsByProduct = await _loadIngredientsForProducts(
        items.map((i) => i.producto.id).toSet(),
      );
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          build:
              (context) => [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoBytes != null)
                      pw.Container(
                        width: 72,
                        height: 72,
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(12),
                          border: pw.Border.all(
                            color: PdfColors.grey300,
                            width: 1,
                          ),
                        ),
                        child: pw.ClipRRect(
                          horizontalRadius: 12,
                          verticalRadius: 12,
                          child: pw.Image(
                            pw.MemoryImage(logoBytes),
                            fit: pw.BoxFit.cover,
                          ),
                        ),
                      ),
                    if (logoBytes != null) pw.SizedBox(width: 16),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            storeName,
                            style: pw.TextStyle(
                              fontSize: 20,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                          if (storeAddress.isNotEmpty ||
                              storeLocation.isNotEmpty)
                            pw.Text(
                              [
                                if (storeAddress.isNotEmpty) storeAddress,
                                if (storeLocation.isNotEmpty) storeLocation,
                              ].join(' · '),
                              style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey600,
                              ),
                            ),
                          if (storePhone.isNotEmpty)
                            pw.Text(
                              'Tel: $storePhone',
                              style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Factura Cliente',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#0F172A'),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Orden: ${order.id}',
                          style: const pw.TextStyle(
                            fontSize: 11,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.Text(
                          _formatInvoiceDate(order.fechaCreacion),
                          style: const pw.TextStyle(
                            fontSize: 11,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F8FAFC'),
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(color: PdfColors.grey300, width: 1),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Cliente',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#334155'),
                            ),
                          ),
                          pw.Text(
                            order.buyerName?.isNotEmpty == true
                                ? order.buyerName!
                                : 'Cliente Final',
                            style: const pw.TextStyle(
                              fontSize: 11,
                              color: PdfColors.grey700,
                            ),
                          ),
                          if (order.buyerPhone != null &&
                              order.buyerPhone!.isNotEmpty)
                            pw.Text(
                              order.buyerPhone!,
                              style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey600,
                              ),
                            ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Estado',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#334155'),
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex('#DCFCE7'),
                              borderRadius: pw.BorderRadius.circular(8),
                            ),
                            child: pw.Text(
                              'Completada',
                              style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromHex('#15803D'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Productos',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder(
                    horizontalInside: pw.BorderSide(
                      color: PdfColors.grey300,
                      width: 0.4,
                    ),
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.6),
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(4),
                    1: const pw.FlexColumnWidth(1.3),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.7),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        _pdfHeaderCell('Producto'),
                        _pdfHeaderCell('Cant.'),
                        _pdfHeaderCell('Precio'),
                        _pdfHeaderCell('Subtotal'),
                      ],
                    ),
                    ...items.expand((item) {
                      final List<pw.TableRow> rows = [
                        pw.TableRow(
                          children: [
                            _pdfBodyCell(item.nombre),
                            _pdfBodyCell('${item.cantidad}'),
                            _pdfBodyCell(
                              '\$${item.displayPrice.toStringAsFixed(2)}',
                            ),
                            _pdfBodyCell(
                              '\$${item.subtotal.toStringAsFixed(2)}',
                              isBold: true,
                            ),
                          ],
                        ),
                      ];

                      final ingredientes =
                          ingredientsByProduct[item.producto.id] ??
                          item.ingredientes;
                      if (ingredientes != null && ingredientes.isNotEmpty) {
                        rows.add(
                          pw.TableRow(
                            children: [
                              _pdfBodyCell(
                                '    Aditamentos',
                                isBold: true,
                                isIngredient: true,
                              ),
                              _pdfBodyCell('', isIngredient: true),
                              _pdfBodyCell('', isIngredient: true),
                              _pdfBodyCell('', isIngredient: true),
                            ],
                          ),
                        );

                        rows.addAll(
                          ingredientes.map<pw.TableRow>((ingrediente) {
                            final nombreIngrediente =
                                (ingrediente['nombre_ingrediente'] ??
                                        'Ingrediente')
                                    .toString();
                            final double cantidadBase =
                                (ingrediente['cantidad_necesaria'] ??
                                            ingrediente['cantidad_vendida'] ??
                                            0)
                                        is num
                                    ? (ingrediente['cantidad_necesaria'] ??
                                            ingrediente['cantidad_vendida'])
                                        .toDouble()
                                    : 0;
                            final unidad =
                                (ingrediente['unidad_medida'] ?? 'unid')
                                    .toString();
                            final double cantidadTotal =
                                (ingrediente['cantidad_vendida'] is num)
                                    ? (ingrediente['cantidad_vendida'] as num)
                                        .toDouble()
                                    : (cantidadBase * item.cantidad);
                            final cantidad = cantidadTotal.toStringAsFixed(2);

                            return pw.TableRow(
                              children: [
                                _pdfBodyCell(
                                  '    $nombreIngrediente',
                                  isIngredient: true,
                                ),
                                _pdfBodyCell(
                                  '$cantidad $unidad',
                                  isIngredient: true,
                                ),
                                _pdfBodyCell('', isIngredient: true),
                                _pdfBodyCell('', isIngredient: true),
                              ],
                            );
                          }),
                        );
                      }

                      return rows;
                    }),
                  ],
                ),
                pw.SizedBox(height: 18),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F1F5F9'),
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(color: PdfColors.grey300, width: 1),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          _pdfSummaryLabel('Total sin descuento'),
                          _pdfSummaryValue(
                            '\$${originalTotal.toStringAsFixed(2)}',
                          ),
                        ],
                      ),
                      if (hasDiscount) ...[
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            _pdfSummaryLabel(
                              discountLabel.isNotEmpty
                                  ? discountLabel
                                  : 'Descuento aplicado',
                            ),
                            _pdfSummaryValue(
                              '- \$${saved.toStringAsFixed(2)}',
                              color: PdfColor.fromHex('#DC2626'),
                            ),
                          ],
                        ),
                      ],
                      pw.Divider(
                        color: PdfColors.grey400,
                        height: 14,
                        thickness: 0.6,
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          _pdfSummaryLabel(
                            'Total a pagar',
                            fontSize: 13,
                            isBold: true,
                          ),
                          _pdfSummaryValue(
                            '\$${finalTotal.toStringAsFixed(2)}',
                            fontSize: 14,
                            isBold: true,
                            color: PdfColor.fromHex('#0F172A'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Gracias por su compra.',
                  style: const pw.TextStyle(
                    fontSize: 11,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/factura_${order.id}.pdf');
      await file.writeAsBytes(await pdf.save());

      debugPrint('✅ PDF generado: ${file.path}');

      if (didShowDialog && mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        didShowDialog = false;
      }

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        text:
            'Factura de $storeName - Orden ${order.id}. Comparte por WhatsApp u otra app.',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Factura generada. Selecciona WhatsApp u otra app.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error generando factura cliente: $e');

      if (didShowDialog && mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        didShowDialog = false;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar factura: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (didShowDialog && mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isGeneratingCustomerInvoice = false;
        });
      }
    }
  }

  pw.Widget _pdfHeaderCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#1F2937'),
        ),
      ),
    );
  }

  pw.Widget _pdfBodyCell(
    String text, {
    bool isBold = false,
    bool isIngredient = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isIngredient ? 9 : 10,
          fontWeight:
              isBold
                  ? pw.FontWeight.bold
                  : (isIngredient
                      ? pw.FontWeight.normal
                      : pw.FontWeight.normal),
          color:
              isIngredient
                  ? PdfColor.fromHex('#6B7280')
                  : PdfColor.fromHex('#334155'),
        ),
      ),
    );
  }

  pw.Widget _pdfSummaryLabel(
    String text, {
    double fontSize = 12,
    bool isBold = false,
  }) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: PdfColor.fromHex('#475569'),
      ),
    );
  }

  /// Carga ingredientes de múltiples productos elaborados en una sola consulta
  Future<Map<int, List<Map<String, dynamic>>>> _loadIngredientsForProducts(
    Set<int> productIds,
  ) async {
    if (productIds.isEmpty) return {};

    try {
      final response = await Supabase.instance.client
          .from('app_dat_producto_ingredientes')
          .select('''
            id_producto_elaborado,
            id_ingrediente,
            cantidad_necesaria,
            unidad_medida,
            app_dat_producto!app_dat_producto_ingredientes_ingrediente_fkey(
              id,
              denominacion,
              sku
            )
          ''')
          .filter('id_producto_elaborado', 'in', '(${productIds.join(',')})');

      final Map<int, List<Map<String, dynamic>>> grouped = {};

      for (final item in response) {
        final int elaboradoId = item['id_producto_elaborado'] as int? ?? -1;
        if (elaboradoId == -1) continue;

        final producto =
            item['app_dat_producto'] as Map<String, dynamic>? ?? {};

        final mapped = {
          'nombre_ingrediente':
              producto['denominacion'] ?? 'Ingrediente desconocido',
          'cantidad_necesaria': item['cantidad_necesaria'] ?? 0,
          'unidad_medida': item['unidad_medida'] ?? 'unid',
          'sku': producto['sku'],
          'id_ingrediente': item['id_ingrediente'],
        };

        grouped.putIfAbsent(elaboradoId, () => []).add(mapped);
      }

      return grouped;
    } catch (e) {
      debugPrint('❌ Error cargando ingredientes para productos: $e');
      return {};
    }
  }

  pw.Widget _pdfSummaryValue(
    String text, {
    double fontSize = 12,
    bool isBold = false,
    PdfColor color = PdfColors.black,
  }) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    );
  }

  String _formatInvoiceDate(DateTime date) {
    final local = date.toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  Future<Uint8List?> _downloadImageBytes(String? url) async {
    if (url == null || url.isEmpty) return null;

    const objectPrefix =
        'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/';
    const renderPrefix =
        'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/render/image/public/images_back/';

    // Construir URL de render con dimensiones fijas para supabase
    final renderUrl =
        url.contains(objectPrefix)
            ? '${url.replaceFirst(objectPrefix, renderPrefix)}?width=500&height=600'
            : url;

    try {
      final response = await http.get(Uri.parse(renderUrl));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ No se pudo descargar imagen de tienda: $e');
      return null;
    }
  }

  /// Verificar configuración de Impresión y mostrar diálogo si está habilitada
  Future<void> _checkAndShowPrintDialog(Order order) async {
    debugPrint(
      'DEBUG: Verificando configuración de Impresión para orden ${order.id}',
    );

    // Verificar si la Impresión está habilitada
    final isPrintEnabled = await _userPreferencesService.isPrintEnabled();
    debugPrint('DEBUG: Impresión habilitada: $isPrintEnabled');

    if (isPrintEnabled) {
      debugPrint('DEBUG: Impresión habilitada - Usando PrinterManager');
      debugPrint(' Plataforma detectada: ${PlatformUtils.isWeb ? "Web" : "Móvil"}');

      // Usar PrinterManager que decide automáticamente el tipo de Impresión
      Future.delayed(Duration(milliseconds: 500), () {
        _printOrderWithManager(order);
      });
    } else {
      debugPrint(
        'DEBUG: Impresión deshabilitada - No se muestra diálogo de Impresión',
      );
    }
  }

  /// Imprimir orden usando PrinterManager (detecta automáticamente la plataforma)
  Future<void> _printOrderWithManager(Order order) async {
    try {
      debugPrint(
        '🖨️ Iniciando impresión con PrinterManager para orden ${order.id}',
      );

      // Usar PrinterManager que maneja automáticamente web vs móvil
      final result = await _printerManager.printInvoice(context, order);

      if (result.success) {
        _showSuccessDialog('¡Factura Impresa!', result.message);
        debugPrint('✅ ${result.message} (${result.platform})');
      } else {
        _showErrorDialog('Error de Impresión', result.message);
        debugPrint('❌ ${result.message} (${result.platform})');
      }

      if (result.details != null) {
        debugPrint('ℹ️ Detalles: ${result.details}');
      }
    } catch (e) {
      _showErrorDialog('Error', 'Ocurrió un error durante la impresión: $e');
      debugPrint('❌ Error en _printOrderWithManager: $e');
    }
  }

  /// Mostrar diálogo de error
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
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
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
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

  /// Imprimir orden individual (usa PrinterManager para detectar plataforma)
  Future<void> _printOrder(Order order) async {
    // Usar el mismo método unificado para impresión manual
    await _printOrderWithManager(order);
  }

  // Personalizar nombres de métodos de pago para el desglose
  String _getCustomPaymentMethodName(Map<String, dynamic> payment) {
    final mediopagoId = payment['medio_pago_id'];

    if (mediopagoId == 1) {
      return 'Dinero en efectivo';
    } else {
      return 'Transferencia';
    }
  }

  // Convertir string a OrderStatus
  OrderStatus? _stringToOrderStatus(String statusString) {
    switch (statusString.toLowerCase()) {
      case 'borrador':
        return OrderStatus.borrador;
      case 'enviada':
        return OrderStatus.enviada;
      case 'pagoconfirmado':
      case 'pago_confirmado':
        return OrderStatus.pagoConfirmado;
      case 'completada':
        return OrderStatus.completada;
      case 'cancelada':
        return OrderStatus.cancelada;
      case 'devuelta':
        return OrderStatus.devuelta;
      case 'pendientedesincronizacion':
      case 'pendiente_de_sincronizacion':
        return OrderStatus.pendienteDeSincronizacion;
      default:
        debugPrint('⚠️ Estado no reconocido: $statusString');
        return null;
    }
  }

  /// Aplicar cambios de estado pendientes que no se han sincronizado
  Future<bool> _applyPendingStatusChanges() async {
    try {
      final pendingOperations =
          await _userPreferencesService.getPendingOperations();

      if (pendingOperations.isEmpty) {
        debugPrint('ℹ️ No hay operaciones pendientes de cambio de estado');
        return false;
      }

      debugPrint(
        '🔄 Aplicando ${pendingOperations.length} operaciones pendientes...',
      );
      bool hasChanges = false;

      for (final operation in pendingOperations) {
        if (operation['type'] == 'order_status_change') {
          final orderId = operation['order_id'] as String;
          final newStatusString = operation['new_status'] as String;
          final newStatus = _stringToOrderStatus(newStatusString);

          if (newStatus != null) {
            final orderIndex = _orderService.orders.indexWhere(
              (order) => order.id == orderId,
            );
            if (orderIndex != -1) {
              final currentOrder = _orderService.orders[orderIndex];

              // Aplicar el cambio de estado pendiente
              if (currentOrder.status != newStatus) {
                final updatedOrder = currentOrder.copyWith(status: newStatus);
                _orderService.orders[orderIndex] = updatedOrder;
                hasChanges = true;
                debugPrint(
                  '🔄 Operación pendiente aplicada: $orderId -> ${currentOrder.status} → ${newStatus.toString()}',
                );
                debugPrint(
                  '🎯 Estado final confirmado: ${_orderService.orders[orderIndex].status}',
                );
              } else {
                debugPrint(
                  'ℹ️ Estado ya aplicado: $orderId -> ${newStatus.toString()}',
                );
              }
            } else {
              debugPrint(
                '⚠️ Orden no encontrada para operación pendiente: $orderId',
              );
            }
          }
        }
      }

      if (hasChanges) {
        debugPrint('✅ Se aplicaron cambios de estado - UI será actualizada');
      }

      return hasChanges;
    } catch (e) {
      debugPrint('❌ Error aplicando cambios de estado pendientes: $e');
      return false;
    }
  }

  void _showMasterPasswordDialog(
    Order order,
    OrderStatus newStatus,
    String title,
    String message,
    Color color,
  ) {
    final TextEditingController passwordController = TextEditingController();
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.vpn_key, color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Contraseña Maestra',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ingresa la contraseña maestra para cancelar esta orden.',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Contraseña Maestra',
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final enteredPassword = passwordController.text.trim();
                        if (enteredPassword.isEmpty) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Por favor ingresa la contraseña'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                          return;
                        }

                        // Verificar la contraseña
                        try {
                          final storeConfig =
                              await _userPreferencesService.getStoreConfig();
                          final storedPassword =
                              storeConfig?['master_password'];

                          if (!context.mounted) return;

                          if (storedPassword == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No hay contraseña maestra configurada',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          // Encriptar la contraseña ingresada para compararla
                          final bytes = utf8.encode(enteredPassword);
                          final digest = sha256.convert(bytes);
                          final encryptedEnteredPassword = digest.toString();

                          if (encryptedEnteredPassword == storedPassword) {
                            // Contraseña correcta - proceder con la cancelación
                            Navigator.pop(
                              context,
                            ); // Cerrar diálogo de contraseña
                            
                            if (context.mounted) {
                              Navigator.pop(context); // Cerrar modal de detalles
                              _updateOrderStatus(order, newStatus);
                            }
                          } else {
                            // Contraseña incorrecta
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Contraseña incorrecta'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          debugPrint('❌ Error al verificar contraseña maestra: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Error al verificar contraseña: $e',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Confirmar'),
                    ),
                  ],
                ),
          ),
    );
  }
}
