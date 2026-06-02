import 'package:flutter/material.dart';
import '../models/mesa.dart';
import '../models/mesa_cuenta.dart';
import '../models/order.dart';
import '../services/mesa_service.dart';
import '../services/mesa_cuenta_service.dart';
import '../services/order_service.dart';
import '../utils/price_utils.dart';
import '../widgets/mesa_form_dialog.dart';

/// Pantalla de detalle de una mesa específica.
///
/// Muestra:
///   - Cabecera con info de la mesa (número, zona, capacidad, estado).
///   - Botón principal "+ Nueva Cuenta" → setea mesa activa y va a /categories.
///   - Lista de órdenes asociadas a la mesa, separada en activas e históricas.
///   - Al tocar una orden navega a /orders con autoOpenOrderId para abrir
///     el detalle nativo (reutilización total del flujo existente).
class MesaDetailScreen extends StatefulWidget {
  final int idMesa;
  const MesaDetailScreen({Key? key, required this.idMesa}) : super(key: key);

  @override
  State<MesaDetailScreen> createState() => _MesaDetailScreenState();
}

class _MesaDetailScreenState extends State<MesaDetailScreen> {
  final MesaService _mesaService = MesaService();
  final MesaCuentaService _cuentaService = MesaCuentaService();
  final OrderService _orderService = OrderService();

  Mesa? _mesa;
  List<Order> _ordenes = [];
  List<MesaCuenta> _cuentasAbiertas = [];
  bool _loading = true;
  bool _busy = false;
  bool _showHistoricas = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      // Cargamos lista de mesas con stats y filtramos la nuestra; así reutilizamos
      // el conteo de órdenes abiertas/cerradas sin RPC adicional.
      final mesas = await _mesaService.listMesasWithStats(incluirInactivas: true);
      Mesa? mesa;
      try {
        mesa = mesas.firstWhere((m) => m.id == widget.idMesa);
      } catch (_) {
        mesa = null;
      }

      // En paralelo: órdenes históricas/registradas + cuentas abiertas
      // (estado intermedio).
      final results = await Future.wait([
        _mesaService.getOrdersForMesa(widget.idMesa),
        _cuentaService.listarCuentasMesa(widget.idMesa),
      ]);
      final ordenes = (results[0] as List<Order>)
        ..sort((a, b) => b.fechaCreacion.compareTo(a.fechaCreacion));
      final cuentas = results[1] as List<MesaCuenta>;

      if (!mounted) return;
      setState(() {
        _mesa = mesa;
        _ordenes = ordenes;
        _cuentasAbiertas = cuentas;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error cargando detalle de mesa: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _esActiva(Order o) =>
      o.status == OrderStatus.enviada ||
      o.status == OrderStatus.procesando ||
      o.status == OrderStatus.borrador ||
      o.status == OrderStatus.pendienteDeSincronizacion;

  List<Order> get _activas => _ordenes.where(_esActiva).toList();
  List<Order> get _historicas => _ordenes.where((o) => !_esActiva(o)).toList();

  /// Abre una cuenta nueva en la mesa (persiste en BD vía RPC
  /// `fn_abrir_cuenta_mesa`, reutilizando una abierta si ya existe) y
  /// navega a CuentaMesaScreen — la "preorden persistente" por mesa.
  ///
  /// Desde ahí el vendedor toca "Agregar productos" que abre /categories
  /// con la cuenta marcada como activa; cada `addItemToCurrentOrder` se
  /// redirige a la BD en vez de al carrito local.
  Future<void> _nuevaCuenta({bool forzarNueva = false}) async {
    if (_mesa == null || _busy) return;
    if (!_mesa!.activa) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta mesa está inactiva. Actívala para abrir cuentas.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // Limpiar carrito local previo y mesa activa por seguridad.
      _orderService.cancelCurrentOrder();
      _orderService.setActiveMesa(idMesa: _mesa!.id, numero: _mesa!.numero);

      final idCuenta = await _cuentaService.abrirCuenta(
        idMesa: _mesa!.id,
        forzarNueva: forzarNueva,
      );

      _cuentaService.setActive(
        idCuenta: idCuenta,
        idMesa: _mesa!.id,
        mesaNumero: _mesa!.numero,
      );

      if (!mounted) return;
      await Navigator.pushNamed(
        context,
        '/cuenta-mesa',
        arguments: idCuenta,
      );

      // Al volver de CuentaMesaScreen refrescamos por si la cuenta cambió.
      if (mounted) _loadAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reabre una cuenta existente (la cuenta ya estaba abierta en BD; sólo
  /// navegamos a su pantalla y marcamos active).
  Future<void> _abrirCuentaExistente(MesaCuenta cuenta) async {
    if (_mesa == null) return;
    _orderService.setActiveMesa(idMesa: _mesa!.id, numero: _mesa!.numero);
    _cuentaService.setActive(
      idCuenta: cuenta.id,
      idMesa: _mesa!.id,
      mesaNumero: _mesa!.numero,
    );
    await Navigator.pushNamed(
      context,
      '/cuenta-mesa',
      arguments: cuenta.id,
    );
    if (mounted) _loadAll();
  }

  void _abrirDetalleOrden(Order o) {
    Navigator.pushNamed(
      context,
      '/orders',
      arguments: o.id, // OrdersScreen ya soporta autoOpenOrderId vía widget,
                      // pero como las rutas son estáticas usamos el flag global.
    ).then((_) => _loadAll());
  }

  Future<void> _editarMesa() async {
    if (_mesa == null) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => MesaFormDialog(mesa: _mesa),
    );
    if (result == true) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _mesa != null ? 'Mesa ${_mesa!.numero}' : 'Mesa',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            tooltip: 'Editar mesa',
            onPressed: _mesa == null ? null : _editarMesa,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refrescar',
            onPressed: _loading ? null : _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mesa == null
              ? _buildNotFound()
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      _buildMesaHeader(),
                      const SizedBox(height: 16),
                      _buildNuevaCuentaButton(),
                      const SizedBox(height: 20),
                      // Cuentas abiertas (estado intermedio, no son ventas todavía)
                      if (_cuentasAbiertas.isNotEmpty) ...[
                        _buildSectionTitle(
                          '🟢 Cuentas Abiertas',
                          _cuentasAbiertas.length,
                          const Color(0xFF10B981),
                        ),
                        const SizedBox(height: 8),
                        ..._cuentasAbiertas.map(_buildCuentaAbiertaCard),
                        const SizedBox(height: 20),
                      ],
                      // Órdenes ya registradas pero pendientes de cobro
                      _buildSectionTitle(
                        '🔴 Ventas Pendientes',
                        _activas.length,
                        Colors.red.shade700,
                      ),
                      const SizedBox(height: 8),
                      if (_activas.isEmpty)
                        _buildEmptyHint(
                          'No hay ventas pendientes en esta mesa',
                          Icons.event_seat_outlined,
                        )
                      else
                        ..._activas.map(_buildOrdenCard),
                      const SizedBox(height: 20),
                      _buildHistoricasHeader(),
                      if (_showHistoricas) ...[
                        const SizedBox(height: 8),
                        if (_historicas.isEmpty)
                          _buildEmptyHint(
                            'Esta mesa no tiene órdenes históricas',
                            Icons.history,
                          )
                        else
                          ..._historicas.map(_buildOrdenCard),
                      ],
                    ],
                  ),
                ),
    );
  }

  /// Tarjeta para una cuenta abierta (estado intermedio antes del checkout).
  Widget _buildCuentaAbiertaCard(MesaCuenta cuenta) {
    final fecha = cuenta.createdAt.toLocal();
    final fechaStr =
        '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _abrirCuentaExistente(cuenta),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Cuenta #${cuenta.id}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ABIERTA',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cuenta.items.isNotEmpty ? cuenta.items.length : cuenta.cantidadItems} producto(s) · $fechaStr',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${PriceUtils.formatDiscountPrice(cuenta.total)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----- subwidgets -----

  Widget _buildMesaHeader() {
    final m = _mesa!;
    Color stateColor;
    String stateLabel;
    IconData stateIcon;
    if (!m.activa) {
      stateColor = Colors.grey;
      stateLabel = 'Inactiva';
      stateIcon = Icons.visibility_off;
    } else if (m.ordenesAbiertas == 0) {
      stateColor = Colors.green.shade700;
      stateLabel = 'Libre';
      stateIcon = Icons.check_circle;
    } else {
      stateColor = Colors.orange.shade800;
      stateLabel = '${m.ordenesAbiertas} cuenta(s) activa(s)';
      stateIcon = Icons.event_seat;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.table_restaurant,
                  color: Color(0xFF4A90E2),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.numero,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    if (m.zona != null && m.zona!.isNotEmpty)
                      Text(
                        m.zona!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: stateColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: stateColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(stateIcon, size: 14, color: stateColor),
                    const SizedBox(width: 4),
                    Text(
                      stateLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: stateColor,
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
              _buildInfoChip(
                Icons.people_alt_outlined,
                'Capacidad',
                '${m.capacidad}',
              ),
              const SizedBox(width: 8),
              _buildInfoChip(
                Icons.receipt_long,
                'Histórico',
                '${m.ordenesCompletadasHistoricas}',
              ),
              const SizedBox(width: 8),
              _buildInfoChip(
                Icons.event_seat_outlined,
                'Abiertas',
                '${m.ordenesAbiertas}',
              ),
            ],
          ),
          if (m.notas != null && m.notas!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.note_outlined,
                      size: 16, color: Colors.amber.shade900),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      m.notas!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[700]),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
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

  Widget _buildNuevaCuentaButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : () => _nuevaCuenta(),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.add_shopping_cart, size: 24),
        label: Text(
          _busy ? 'Abriendo...' : 'Nueva Cuenta',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4A90E2),
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, int count, Color color) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoricasHeader() {
    return InkWell(
      onTap: () => setState(() => _showHistoricas = !_showHistoricas),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              _showHistoricas ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey[700],
            ),
            const SizedBox(width: 4),
            Text(
              '✅ Histórico',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_historicas.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdenCard(Order o) {
    final color = Color(
      int.parse('FF${o.status.displayColor.replaceAll('#', '')}', radix: 16),
    );
    final fecha = o.fechaCreacion;
    final fechaStr =
        '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _abrirDetalleOrden(o),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            o.id,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              o.status.displayName,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${o.items.length} producto(s) · $fechaStr',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (o.sellerName != null && o.sellerName!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '👤 ${o.sellerName}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${PriceUtils.formatDiscountPrice(o.total)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A90E2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyHint(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[500], size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Mesa no encontrada',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }
}
