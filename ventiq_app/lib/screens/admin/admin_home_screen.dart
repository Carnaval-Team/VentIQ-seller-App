import 'package:flutter/material.dart';

import '../../services/admin_access_service.dart';
import '../../services/admin_inventory_service.dart';
import '../../services/offline_database_service.dart';
import '../../services/subscription_guard_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/app_drawer.dart';

/// Hub Admin Lite: inventario + resumen mínimo offline.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  bool _loading = true;
  bool _allowed = false;
  bool _inventoryOnly = false;
  String? _error;

  int _pendingOps = 0;
  int _pendingOrders = 0;
  int _pendingTurnos = 0;
  int _lowStock = 0;
  int _productCount = 0;

  @override
  void initState() {
    super.initState();
    _gate();
  }

  Future<void> _gate() async {
    try {
      final hasSub = await SubscriptionGuardService().hasActiveSubscription();
      if (!hasSub) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _allowed = false;
          _error = 'Licencia/suscripción no válida. Revalida para continuar.';
        });
        return;
      }

      final admin = AdminAccessService();
      final can = await admin.canManageInventory();
      final only = await admin.isInventoryOnlySession();
      if (!can) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _allowed = false;
          _inventoryOnly = only;
          _error =
              'No tienes permisos de gerente o supervisor en esta tienda.';
        });
        return;
      }

      await _loadDashboard();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _allowed = true;
        _inventoryOnly = only;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _allowed = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadDashboard() async {
    final db = OfflineDatabaseService();
    final prefs = UserPreferencesService();
    final products = await AdminInventoryService().listCachedProducts();
    final low = products.where((p) {
      final qty = (p['cantidad'] as num?)?.toDouble() ?? 0;
      return qty > 0 && qty <= 5;
    }).length;

    final pendingOps = await db.countPendingAdminOps();
    final pendingOrders = await prefs.getPendingOrdersCount();
    final turnos = await prefs.getOfflineTurnosPendingSync();

    if (!mounted) return;
    setState(() {
      _pendingOps = pendingOps;
      _pendingOrders = pendingOrders;
      _pendingTurnos = turnos.length;
      _lowStock = low;
      _productCount = products.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !_inventoryOnly,
        actions: [
          IconButton(
            tooltip: 'Cambiar usuario / Salir',
            onPressed: () => AppDrawer.promptLogoutOrSwitchUser(context),
            icon: const Icon(Icons.swap_horiz),
          ),
          IconButton(
            tooltip: 'Actualizar resumen',
            onPressed: _allowed
                ? () async {
                    await _loadDashboard();
                  }
                : null,
            icon: const Icon(Icons.refresh),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Menú',
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              icon: const Icon(Icons.menu),
            ),
          ),
        ],
      ),
      endDrawer: const AppDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error ?? 'Acceso denegado',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () =>
                              AppDrawer.promptLogoutOrSwitchUser(context),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Cambiar usuario / Salir'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDashboard,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _inventoryOnly
                            ? 'Gestión de inventario y productos (sin venta POS)'
                            : 'Gestión de inventario y productos',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.grey[700],
                                ),
                      ),
                      if (_inventoryOnly) ...[
                        const SizedBox(height: 12),
                        Card(
                          color: Colors.orange.shade50,
                          child: ListTile(
                            leading: Icon(
                              Icons.person_search,
                              color: Colors.orange.shade800,
                            ),
                            title: const Text('Cambiar a vendedor'),
                            subtitle: const Text(
                              'Salir de esta sesión e iniciar otro usuario '
                              'en el dispositivo',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                AppDrawer.promptLogoutOrSwitchUser(context),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _dashboardRow(context),
                      const SizedBox(height: 16),
                      _tile(
                        icon: Icons.inventory_2_outlined,
                        title: 'Stock',
                        subtitle: 'Consultar inventario local',
                        route: '/admin-stock',
                      ),
                      _tile(
                        icon: Icons.warehouse_outlined,
                        title: 'Stock por ubicación',
                        subtitle: 'Agrupar productos por layout/almacén',
                        route: '/admin-warehouses',
                      ),
                      _tile(
                        icon: Icons.move_to_inbox,
                        title: 'Recepción',
                        subtitle: 'Registrar entrada de mercancía',
                        route: '/admin-reception',
                      ),
                      _tile(
                        icon: Icons.outbox,
                        title: 'Extracción',
                        subtitle: 'Salida de mercancía (merma, uso, etc.)',
                        route: '/admin-extraction',
                      ),
                      _tile(
                        icon: Icons.handshake_outlined,
                        title: 'Venta por acuerdo',
                        subtitle: 'Venta directa con pago (offline-first)',
                        route: '/admin-sale-agreement',
                      ),
                      _tile(
                        icon: Icons.swap_horiz,
                        title: 'Transferencia',
                        subtitle: 'Mover stock entre ubicaciones',
                        route: '/admin-transfer',
                      ),
                      _tile(
                        icon: Icons.tune,
                        title: 'Ajuste',
                        subtitle: 'Corregir cantidades de inventario',
                        route: '/admin-adjustment',
                      ),
                      _tile(
                        icon: Icons.sell_outlined,
                        title: 'Productos',
                        subtitle: 'Precios, costo y alta rápida',
                        route: '/admin-products',
                      ),
                      _tile(
                        icon: Icons.point_of_sale,
                        title: 'Precios por TPV',
                        subtitle: 'Precios diferenciados por punto de venta',
                        route: '/admin-tpv-prices',
                      ),
                      _tile(
                        icon: Icons.storefront_outlined,
                        title: 'TPVs y vendedores',
                        subtitle: 'Crear/editar TPVs y asignar vendedores',
                        route: '/admin-tpv-vendors',
                      ),
                      _tile(
                        icon: Icons.fact_check_outlined,
                        title: 'IPV / Inventario',
                        subtitle: 'Conteo físico desde cache local',
                        route: '/admin-ipv',
                      ),
                      _tile(
                        icon: Icons.local_shipping_outlined,
                        title: 'Proveedores',
                        subtitle: 'Consulta cache offline',
                        route: '/admin-suppliers',
                      ),
                      _tile(
                        icon: Icons.people_outline,
                        title: 'Clientes',
                        subtitle: 'Consulta cache offline',
                        route: '/admin-customers',
                      ),
                      _tile(
                        icon: Icons.pending_actions,
                        title: 'Ops / movimientos',
                        subtitle: 'Cola e historial local de operaciones',
                        route: '/admin-pending-ops',
                      ),
                      _tile(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Cuadres offline',
                        subtitle:
                            'Turnos locales pendientes de sincronizar',
                        route: '/admin-turnos-offline',
                      ),
                      if (_inventoryOnly)
                        _tile(
                          icon: Icons.phonelink_setup,
                          title: 'Preparar dispositivo offline',
                          subtitle:
                              'Sync + registrar vendedores para cambio local',
                          route: '/admin-prepare-offline',
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _dashboardRow(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                label: 'Ops admin',
                value: '$_pendingOps',
                color: _pendingOps > 0 ? Colors.orange : Colors.green,
                onTap: () => Navigator.pushNamed(context, '/admin-pending-ops')
                    .then((_) => _loadDashboard()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                label: 'Ventas pend.',
                value: '$_pendingOrders',
                color: _pendingOrders > 0 ? Colors.orange : Colors.blue,
                onTap: null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _statCard(
                label: 'Turnos',
                value: '$_pendingTurnos',
                color: _pendingTurnos > 0 ? Colors.deepOrange : Colors.teal,
                onTap: () =>
                    Navigator.pushNamed(context, '/admin-turnos-offline')
                        .then((_) => _loadDashboard()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statCard(
                label: 'Stock bajo',
                value: '$_lowStock / $_productCount',
                color: _lowStock > 0 ? Colors.red : Colors.green,
                onTap: () => Navigator.pushNamed(context, '/admin-stock')
                    .then((_) => _loadDashboard()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue[50],
          child: Icon(icon, color: Colors.blue[700]),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, route).then((_) {
          _loadDashboard();
        }),
      ),
    );
  }
}
