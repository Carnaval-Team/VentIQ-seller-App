import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/auth_service.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuSection(
                  context,
                  title: 'Principal',
                  items: [
                    _DrawerItem(
                      icon: Icons.dashboard,
                      title: 'Dashboard',
                      route: '/dashboard',
                    ),
                  ],
                ),
                _buildMenuSection(
                  context,
                  title: 'Tiendas',
                  items: [
                    _DrawerItem(
                      icon: Icons.store,
                      title: 'Gestión de Tiendas',
                      route: '/tiendas',
                    ),
                    _DrawerItem(
                      icon: Icons.storefront,
                      title: 'Tiendas en Catálogo',
                      route: '/tiendas-catalogo',
                    ),
                    _DrawerItem(
                      icon: Icons.admin_panel_settings,
                      title: 'Administradores',
                      route: '/administradores',
                    ),
                    _DrawerItem(
                      icon: Icons.people,
                      title: 'Trabajadores',
                      route: '/trabajadores',
                    ),
                    _DrawerItem(
                      icon: Icons.sync,
                      title: 'Carnaval App Tiendas',
                      route: '/carnaval-tiendas',
                    ),
                    _DrawerItem(
                      icon: Icons.compare_arrows,
                      title: 'Productos Carnaval - Inventtia',
                      route: '/productos-carnaval-inventtia',
                    ),
                    _DrawerItem(
                      icon: Icons.payment,
                      title: 'Pago a Proveedores',
                      route: '/pago-proveedores',
                    ),
                  ],
                ),
                _buildMenuSection(
                  context,
                  title: 'Licencias',
                  items: [
                    _DrawerItem(
                      icon: Icons.card_membership,
                      title: 'Gestión de Licencias',
                      route: '/licencias',
                    ),
                    _DrawerItem(
                      icon: Icons.schedule,
                      title: 'Renovaciones',
                      route: '/renovaciones',
                    ),
                    _DrawerItem(
                      icon: Icons.layers,
                      title: 'Planes',
                      route: '/configuracion',
                    ),
                  ],
                ),

                _buildMenuSection(
                  context,
                  title: 'Usuarios',
                  items: [
                    _DrawerItem(
                      icon: Icons.person_add,
                      title: 'Registro de Usuarios',
                      route: '/usuarios/registro',
                    ),
                    _DrawerItem(
                      icon: Icons.people_outline,
                      title: 'Gestión de Usuarios',
                      route: '/usuarios',
                    ),
                    _DrawerItem(
                      icon: Icons.lock_reset,
                      title: 'Cambio de Contraseñas',
                      route: '/usuarios/passwords',
                    ),
                  ],
                ),
                _buildMenuSection(
                  context,
                  title: 'Sistema',
                  items: [
                    _DrawerItem(
                      icon: Icons.analytics,
                      title: 'Reportes',
                      route: '/reportes',
                    ),
                    _DrawerItem(
                      icon: Icons.settings,
                      title: 'Configuración',
                      route: '/configuracion',
                    ),
                    _DrawerItem(
                      icon: Icons.help_outline,
                      title: 'Soporte',
                      route: '/soporte',
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  'assets/images/ic_superadmin.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Inventtia Super Admin',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Sistema de Administración Global',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Super Administrador',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuSection(
    BuildContext context, {
    required String title,
    required List<_DrawerItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...items.map((item) => _buildDrawerItem(context, item)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDrawerItem(BuildContext context, _DrawerItem item) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final isSelected = currentRoute == item.route;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
          size: 22,
        ),
        title: Text(
          item.title,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        selected: isSelected,
        selectedTileColor: AppColors.primary.withOpacity(0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          Navigator.of(context).pop(); // Cerrar drawer
          if (currentRoute != item.route) {
            // Rutas implementadas
            if (item.route == '/dashboard' ||
                item.route == '/tiendas' ||
                item.route == '/tiendas-catalogo' ||
                item.route == '/usuarios' ||
                item.route == '/administradores' ||
                item.route == '/trabajadores' ||
                item.route == '/licencias' ||
                item.route == '/renovaciones' ||
                item.route == '/configuracion' ||
                item.route == '/carnaval-tiendas' ||
                item.route == '/productos-carnaval-inventtia' ||
                item.route == '/pago-proveedores') {
              Navigator.of(context).pushReplacementNamed(item.route);
            } else {
              // Para rutas que aún no están implementadas
              _showComingSoonDialog(context, item.title);
            }
          }
        },
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text(
              'Cerrar Sesión',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () => _showLogoutDialog(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Inventtia Super Admin v1.0.0',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cerrar Sesión'),
          content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop(); // Cerrar diálogo
                Navigator.of(context).pop(); // Cerrar drawer

                final authService = AuthService();
                await authService.logout();

                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Cerrar Sesión'),
            ),
          ],
        );
      },
    );
  }

  void _showComingSoonDialog(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Próximamente'),
          content: Text(
            'La funcionalidad "$feature" estará disponible pronto.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }
}

class _DrawerItem {
  final IconData icon;
  final String title;
  final String route;

  _DrawerItem({required this.icon, required this.title, required this.route});
}
