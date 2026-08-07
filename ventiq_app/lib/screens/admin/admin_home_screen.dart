import 'package:flutter/material.dart';

import '../../services/admin_access_service.dart';
import '../../services/subscription_guard_service.dart';
import '../../widgets/app_drawer.dart';

/// Hub Admin Lite: stock, recepción, ajuste, productos.
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
      if (!mounted) return;
      setState(() {
        _loading = false;
        _allowed = can;
        _inventoryOnly = only;
        _error = can
            ? null
            : 'No tienes permisos de gerente o supervisor en esta tienda.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !_inventoryOnly,
      ),
      endDrawer: const AppDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_allowed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ?? 'Acceso denegado',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700], fontSize: 16),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      _inventoryOnly
                          ? 'Gestión de inventario y productos (sin venta)'
                          : 'Gestión de inventario y productos',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey[700],
                          ),
                    ),
                    const SizedBox(height: 16),
                    _tile(
                      icon: Icons.inventory_2_outlined,
                      title: 'Stock',
                      subtitle: 'Consultar inventario local',
                      route: '/admin-stock',
                    ),
                    _tile(
                      icon: Icons.move_to_inbox,
                      title: 'Recepción',
                      subtitle: 'Registrar entrada de mercancía',
                      route: '/admin-reception',
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
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}
