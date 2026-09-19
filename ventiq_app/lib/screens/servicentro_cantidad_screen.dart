import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/payment_method.dart' as pm;
import '../models/product.dart';
import '../services/bank_sms_service.dart';
import '../services/order_service.dart';
import '../services/payment_method_service.dart';
import '../services/servicentro_service.dart';
import '../services/store_config_service.dart';
import '../services/turno_service.dart';
import '../services/user_preferences_service.dart';
import 'checkout_screen.dart';

/// Entrada dual litros ↔ monto + método de pago, luego checkout de 1 línea.
class ServicentroCantidadScreen extends StatefulWidget {
  final ServicentroFuelItem fuel;

  const ServicentroCantidadScreen({super.key, required this.fuel});

  @override
  State<ServicentroCantidadScreen> createState() =>
      _ServicentroCantidadScreenState();
}

class _ServicentroCantidadScreenState extends State<ServicentroCantidadScreen> {
  final _litrosCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _litrosFocus = FocusNode();
  final _montoFocus = FocusNode();
  final _orderService = OrderService();
  final _prefs = UserPreferencesService();

  bool _syncing = false;
  bool _submitting = false;
  bool _loadingPayments = true;
  String? _error;

  List<pm.PaymentMethod> _paymentMethods = [];
  pm.PaymentMethod? _selectedPayment;

  ServicentroFuelItem get _fuel => widget.fuel;
  double get _precio => _fuel.precioVenta;
  String get _um =>
      (_fuel.um != null && _fuel.um!.trim().isNotEmpty) ? _fuel.um!.trim() : 'L';

  Color get _accent {
    return Color(ServicentroFuelItem.parseColor(_fuel.color).argb);
  }

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _litrosFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _litrosCtrl.dispose();
    _montoCtrl.dispose();
    _litrosFocus.dispose();
    _montoFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentMethods() async {
    setState(() => _loadingPayments = true);
    try {
      // Misma regla que catálogo/preorden: full-offline o modo offline → cache.
      final useLocal = await _prefs.shouldUseLocalData();
      final methods = await PaymentMethodService.getPaymentMethodsWithCache(
        isOfflineModeEnabled: useLocal,
      );

      // Mismo set especial que PreorderScreen.
      final pagoRegularEfectivo = pm.PaymentMethod(
        id: 999,
        denominacion: 'Pago Regular (Efectivo)',
        descripcion: 'Pago en efectivo sin descuento aplicado',
        esDigital: false,
        esEfectivo: true,
        esActivo: true,
      );
      final withSpecial = <pm.PaymentMethod>[pagoRegularEfectivo, ...methods];

      // Temporalmente oculto: "Pago Pendiente" (cuenta por cobrar).

      if (!mounted) return;
      if (withSpecial.isEmpty) {
        setState(() {
          _paymentMethods = [];
          _selectedPayment = null;
          _loadingPayments = false;
          _error = useLocal
              ? 'Sin métodos de pago en cache. Sincroniza online primero.'
              : 'Sin métodos de pago disponibles.';
        });
        return;
      }

      setState(() {
        _paymentMethods = withSpecial;
        _selectedPayment = withSpecial.firstWhere(
          (m) => m.id == 999 || m.esEfectivo,
          orElse: () => withSpecial.first,
        );
        _loadingPayments = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPayments = false;
        _error = 'No se pudieron cargar los métodos de pago: $e';
      });
    }
  }

  double? _parsePositive(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final v = double.tryParse(cleaned);
    if (v == null || v <= 0) return null;
    return v;
  }

  void _onLitrosChanged(String raw) {
    if (_syncing) return;
    final litros = _parsePositive(raw);
    _syncing = true;
    if (litros == null || _precio <= 0) {
      _montoCtrl.text = '';
    } else {
      _montoCtrl.text = (litros * _precio).toStringAsFixed(2);
    }
    _syncing = false;
    setState(() => _error = null);
  }

  void _onMontoChanged(String raw) {
    if (_syncing) return;
    final monto = _parsePositive(raw);
    _syncing = true;
    if (monto == null || _precio <= 0) {
      _litrosCtrl.text = '';
    } else {
      _litrosCtrl.text = _formatLitros(monto / _precio);
    }
    _syncing = false;
    setState(() => _error = null);
  }

  String _formatLitros(double litros) {
    final s = litros.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  ProductVariant? _matchVariantForInventory(
    Product product,
    Map<String, dynamic> inventoryData,
  ) {
    if (product.variantes.isEmpty) return null;

    final idUbicacion = (inventoryData['id_ubicacion'] as num?)?.toInt();
    final idInventario = (inventoryData['id_inventario'] as num?)?.toInt();

    for (final v in product.variantes) {
      final meta = v.inventoryMetadata;
      if (meta == null) continue;
      final metaUbic = (meta['id_ubicacion'] as num?)?.toInt();
      final metaInv = (meta['id_inventario'] as num?)?.toInt();
      if (idUbicacion != null && metaUbic == idUbicacion) {
        if (idInventario == null || metaInv == idInventario) return v;
      }
    }
    return product.variantes.first;
  }

  Future<void> _confirmar() async {
    if (_submitting) return;

    if (_precio <= 0) {
      setState(() => _error = 'Este combustible no tiene precio configurado.');
      return;
    }

    final litros = _parsePositive(_litrosCtrl.text);
    if (litros == null) {
      setState(() => _error = 'Ingresa una cantidad mayor que cero.');
      return;
    }

    if (_fuel.stockDisponible > 0 && litros > _fuel.stockDisponible) {
      setState(() {
        _error =
            'Stock insuficiente. Disponible: ${_fuel.stockDisponible} $_um.';
      });
      return;
    }

    if (!_fuel.puedeVender) {
      setState(() => _error = 'Este combustible no tiene stock disponible.');
      return;
    }

    final montoIngresado = _parsePositive(_montoCtrl.text);
    final monto = montoIngresado ??
        double.parse((litros * _precio).toStringAsFixed(2));
    if (monto <= 0) {
      setState(() => _error = 'El monto resultante debe ser mayor que cero.');
      return;
    }

    if (_selectedPayment == null) {
      setState(() => _error = 'Selecciona un método de pago.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final hasShift = await TurnoService.hasOpenShift();
      if (!hasShift) {
        if (!mounted) return;
        setState(() => _submitting = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Turno requerido'),
            content: const Text(
              'Debes abrir un turno antes de registrar una venta.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        return;
      }

      // Un solo tipo por ticket: descartar cualquier borrador previo.
      _orderService.cancelCurrentOrder();

      // Mismo camino que el catálogo: detalle + inventoryData + descuento stock.
      final product =
          await ServicentroService.resolveProductForSale(_fuel);
      final stockReal = product.cantidadReal.toDouble();
      if (stockReal <= 0) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = 'Este combustible no tiene stock disponible.';
        });
        return;
      }
      if (litros > stockReal) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error =
              'Stock insuficiente. Disponible: $stockReal $_um.';
        });
        return;
      }

      final precio = ServicentroService.unitPriceForEnteredAmount(
        liters: litros,
        amount: monto,
      );
      final inventoryData =
          await ServicentroService.inventoryDataFromProduct(product);
      final idUbicacion = (inventoryData['id_ubicacion'] as num?)?.toInt();
      if (idUbicacion == null) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error =
              'Sin ubicación de inventario para este combustible. '
              'Sincroniza productos e inténtalo de nuevo.';
        });
        return;
      }

      final selectedVariant = _matchVariantForInventory(product, inventoryData);

      await _orderService.addItemToCurrentOrder(
        producto: product,
        variante: selectedVariant,
        cantidad: litros,
        ubicacionAlmacen:
            await ServicentroService.ubicacionFromProduct(product),
        inventoryData: inventoryData,
        precioUnitario: precio,
        precioBase: precio,
      );

      final order = _orderService.currentOrder;
      if (order == null || order.items.isEmpty) {
        throw Exception('No se pudo armar la orden de combustible');
      }

      // Asignar método de pago a la única línea (requerido por checkout).
      _orderService.updateItemPaymentMethod(
        order.items.first.id,
        _selectedPayment,
      );
      final checkoutOrder = _orderService.currentOrder;
      if (checkoutOrder == null || checkoutOrder.items.isEmpty) {
        throw Exception('No se pudo actualizar la orden de combustible');
      }

      // Misma rama que PreorderScreen: offline / full-offline → checkout offline.
      final isOfflineModeEnabled = await _prefs.isOfflineModeEnabled();
      final stayFullyOffline = await _prefs.shouldStayFullyOffline();
      final useOfflinePath = isOfflineModeEnabled || stayFullyOffline;
      checkoutOrder.isOfflineOrder = useOfflinePath;

      // Transferencia: escuchar SMS antes del checkout (igual que preorden).
      if (_selectedPayment?.esTransferencia == true) {
        BankSmsService().startListening();
      }

      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CheckoutScreen(order: checkoutOrder),
        ),
      );

      if (mounted) {
        setState(() => _submitting = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPayment = _selectedPayment != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_fuel.denominacion),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_gas_station, color: _accent, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fuel.denominacion,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${_precio.toStringAsFixed(2)} / $_um'
                          ' · Stock: ${_fuel.stockDisponible == _fuel.stockDisponible.roundToDouble() ? _fuel.stockDisponible.toInt() : _fuel.stockDisponible.toStringAsFixed(2)} $_um',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text('Cantidad ($_um)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _litrosCtrl,
              focusNode: _litrosFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                hintText: '0',
                suffixText: _um,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onLitrosChanged,
              onSubmitted: (_) => _montoFocus.requestFocus(),
            ),
            const SizedBox(height: 20),
            Text('Monto (\$)', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _montoCtrl,
              focusNode: _montoFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                hintText: '0.00',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              onChanged: _onMontoChanged,
            ),
            const SizedBox(height: 20),
            Text('Método de pago', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _buildPaymentSelector(theme, hasPayment),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: (_submitting || _loadingPayments) ? null : _confirmar,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.payments_outlined),
              label: Text(_submitting ? 'Preparando…' : 'Cobrar'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSelector(ThemeData theme, bool hasPayment) {
    if (_loadingPayments) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Cargando métodos de pago…'),
          ],
        ),
      );
    }

    if (_paymentMethods.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: const Text('Sin métodos de pago disponibles'),
      );
    }

    return InputDecorator(
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        prefixIcon: Icon(
          hasPayment ? Icons.check_circle : Icons.payment,
          color: hasPayment ? const Color(0xFF10B981) : Colors.red[600],
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<pm.PaymentMethod>(
          isExpanded: true,
          value: _selectedPayment,
          hint: const Text('Seleccionar…'),
          items: _paymentMethods.map((method) {
            return DropdownMenuItem<pm.PaymentMethod>(
              value: method,
              child: Text(
                method.denominacion,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (method) {
            setState(() {
              _selectedPayment = method;
              _error = null;
            });
          },
        ),
      ),
    );
  }
}
