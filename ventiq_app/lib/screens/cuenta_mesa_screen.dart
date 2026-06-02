import 'dart:async';
import 'package:flutter/material.dart';
import '../models/mesa_cuenta.dart';
import '../services/mesa_cuenta_service.dart';
import '../services/order_service.dart';
import '../utils/price_utils.dart';

/// Pantalla de **cuenta abierta** de una mesa.
///
/// Es el equivalente a la preorden, pero los items viven en BD
/// (`app_dat_mesa_cuenta_item`) — no en memoria local. Esto permite:
///  - Reabrir la cuenta tras cerrar la app o cambiar de dispositivo.
///  - Que el inventario NO se descuente hasta cobrar (al "Cerrar Nota").
///  - Que múltiples vendedores vean la misma cuenta.
///
/// Flujo:
///  1. Vendedor toca "Nueva Cuenta" en MesaDetailScreen → se crea la cuenta
///     en BD (RPC `fn_abrir_cuenta_mesa`) y se navega aquí.
///  2. Aquí ve los items. "+ Agregar productos" abre `/categories` con la
///     cuenta activa marcada en `MesaCuentaService`. Cada `addItem` desde
///     producto/detalle se redirige a `agregarOrderItem` en lugar de
///     `OrderService.addItemToCurrentOrder`.
///  3. "Cerrar Nota" → arma una Order local desde los items de la cuenta y
///     navega al checkout estándar, donde se cobra y se llama a la RPC
///     `fn_registrar_venta_mesa` exactamente igual que en el modo normal.
class CuentaMesaScreen extends StatefulWidget {
  final int idCuenta;
  const CuentaMesaScreen({Key? key, required this.idCuenta}) : super(key: key);

  @override
  State<CuentaMesaScreen> createState() => _CuentaMesaScreenState();
}

class _CuentaMesaScreenState extends State<CuentaMesaScreen> {
  final MesaCuentaService _cuentaService = MesaCuentaService();
  final OrderService _orderService = OrderService();

  MesaCuenta? _cuenta;
  bool _loading = true;
  bool _busy = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadCuenta();
    // Poll suave: si otro vendedor agregó items, los vemos al volver al foreground.
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_busy) _loadCuenta(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCuenta({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final cuenta = await _cuentaService.obtenerCuenta(widget.idCuenta);
      if (!mounted) return;
      setState(() {
        _cuenta = cuenta;
        _loading = false;
      });
      // Mantener active en sincronía (por si entraron por deep link).
      _cuentaService.setActive(
        idCuenta: cuenta.id,
        idMesa: cuenta.idMesa,
        mesaNumero: cuenta.mesaNumero,
      );
    } catch (e) {
      print('❌ Error cargando cuenta ${widget.idCuenta}: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _agregarProductos() async {
    if (_cuenta == null) return;
    // La cuenta queda activa para que CategoriesScreen/ProductDetails
    // redirijan los addItem a la BD en vez de a OrderService local.
    _cuentaService.setActive(
      idCuenta: _cuenta!.id,
      idMesa: _cuenta!.idMesa,
      mesaNumero: _cuenta!.mesaNumero,
    );

    // pushNamed (NO remove) — al volver atrás aterrizamos aquí otra vez.
    await Navigator.pushNamed(context, '/categories');
    if (mounted) _loadCuenta();
  }

  Future<void> _cambiarCantidad(MesaCuentaItem item, double nueva) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _cuentaService.actualizarCantidad(idItem: item.id, cantidad: nueva);
      await _loadCuenta(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _eliminarItem(MesaCuentaItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Eliminar "${item.displayName}" de la cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _cuentaService.eliminarItem(item.id);
      await _loadCuenta(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelarCuenta() async {
    if (_cuenta == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Cuenta'),
        content: Text(
          'Se descartarán los ${_cuenta!.items.length} producto(s) de esta cuenta. ¿Estás seguro?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _cuentaService.cancelarCuenta(_cuenta!.id);
      _orderService.clearActiveMesa();
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
      setState(() => _busy = false);
    }
  }

  /// Convierte los items de la cuenta a una orden local en `OrderService` y
  /// navega al checkout (o a la preorden si quieres una pasada extra).
  ///
  /// Estrategia: en el modo restaurante el flujo "preorden local" no aporta
  /// nada (ya tenemos los items). Cargamos directo el checkout. La
  /// confirmación allí dispara `fn_registrar_venta_mesa` que aceptará
  /// `p_id_cuenta_abierta` para marcar la cuenta cerrada.
  Future<void> _cerrarNota() async {
    if (_cuenta == null || _cuenta!.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La cuenta no tiene productos')),
      );
      return;
    }

    // El order_service.dart se encargará de:
    //   1. Hidratar una orden local desde los items de la cuenta.
    //   2. Marcar mesa activa + cuenta activa.
    //   3. Navegar a preorden / checkout según el flujo normal.
    //
    // De momento sólo navegamos a /preorder; OrderService.loadPreorderFromCuenta
    // se encargará de hidratar la orden in-memory. La preorden actúa como
    // "revisión final" del pedido antes del cobro.
    setState(() => _busy = true);
    try {
      await _orderService.loadPreorderFromCuenta(_cuenta!);
      _cuentaService.setActive(
        idCuenta: _cuenta!.id,
        idMesa: _cuenta!.idMesa,
        mesaNumero: _cuenta!.mesaNumero,
      );
      _orderService.setActiveMesa(
        idMesa: _cuenta!.idMesa,
        numero: _cuenta!.mesaNumero,
      );
      if (!mounted) return;
      // pushNamed para mantener stack — al volver de checkout vendrá a aquí.
      await Navigator.pushNamed(context, '/preorder');
      if (mounted) _loadCuenta();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ----------------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Limpiar contexto activo al volver atrás (a Mesa Detail).
        _cuentaService.clearActive();
        _orderService.clearActiveMesa();
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          backgroundColor: const Color(0xFF4A90E2),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            _cuenta == null
                ? 'Cuenta'
                : 'Mesa ${_cuenta!.mesaNumero ?? _cuenta!.idMesa}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Refrescar',
              onPressed: _loading ? null : () => _loadCuenta(),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _cuenta == null
                ? _buildError()
                : _buildContent(),
        bottomNavigationBar: _cuenta == null ? null : _buildBottomBar(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No se pudo cargar la cuenta',
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final c = _cuenta!;
    return RefreshIndicator(
      onRefresh: _loadCuenta,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          _buildHeaderCard(),
          const SizedBox(height: 12),
          _buildAddProductButton(),
          const SizedBox(height: 12),
          if (c.items.isEmpty)
            _buildEmpty()
          else
            ...c.items.map(_buildItemCard).toList(),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final c = _cuenta!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cuenta #${c.id}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (c.mesaZona != null && c.mesaZona!.isNotEmpty)
                      Text(
                        c.mesaZona!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                    SizedBox(width: 6),
                    Text(
                      'ABIERTA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniMetric(
                  'Productos',
                  '${c.items.length}',
                  Icons.shopping_basket_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniMetric(
                  'Total',
                  '\$${PriceUtils.formatDiscountPrice(c.total)}',
                  Icons.payments_outlined,
                ),
              ),
              if (c.numeroComensales != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _miniMetric(
                    'Comensales',
                    '${c.numeroComensales}',
                    Icons.people_alt_outlined,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddProductButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : _agregarProductos,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text(
          'Agregar productos',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(28),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Icon(Icons.shopping_basket_outlined, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'La cuenta está vacía',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Toca "Agregar productos" para empezar',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(MesaCuentaItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.displayName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '\$${PriceUtils.formatDiscountPrice(item.subtotal)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4A90E2),
                ),
              ),
            ],
          ),
          if (item.presentacionNombre != null || item.ubicacionNombre != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                if (item.presentacionNombre != null)
                  _miniChip(item.presentacionNombre!, Icons.inventory_2_outlined),
                if (item.ubicacionNombre != null)
                  _miniChip(item.ubicacionNombre!, Icons.location_on_outlined),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '\$${PriceUtils.formatDiscountPrice(item.precioUnitario)} c/u',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const Spacer(),
              IconButton(
                onPressed: _busy
                    ? null
                    : () {
                        final step = item.cantidad % 1 != 0 ? 0.5 : 1.0;
                        _cambiarCantidad(item, item.cantidad - step);
                      },
                icon: const Icon(Icons.remove_circle_outline),
                color: Colors.red,
                iconSize: 22,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  PriceUtils.formatQuantity(item.cantidad),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy
                    ? null
                    : () {
                        final step = item.cantidad % 1 != 0 ? 0.5 : 1.0;
                        _cambiarCantidad(item, item.cantidad + step);
                      },
                icon: const Icon(Icons.add_circle_outline),
                color: const Color(0xFF4A90E2),
                iconSize: 22,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _busy ? null : () => _eliminarItem(item),
                icon: const Icon(Icons.delete_outline),
                color: Colors.red[400],
                iconSize: 22,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final c = _cuenta!;
    final empty = c.items.isEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Total cuenta:',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '\$${PriceUtils.formatDiscountPrice(c.total)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _cancelarCuenta,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancelar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_busy || empty) ? null : _cerrarNota,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text(
                      'Cerrar Nota',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90E2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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
  }
}
