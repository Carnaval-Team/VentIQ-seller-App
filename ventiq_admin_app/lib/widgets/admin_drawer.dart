import 'package:flutter/material.dart';
import '../config/app_colors.dart';

class AdminDrawer extends StatefulWidget {
  const AdminDrawer({Key? key}) : super(key: key);

  @override
  State<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends State<AdminDrawer> {
  String _userName = 'Administrador';
  String _userEmail = 'admin@ventiq.com';

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.white24,
                      child: Icon(
                        Icons.admin_panel_settings,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _userEmail,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Panel de Administración',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Opciones del menú
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.dashboard,
                  title: 'Dashboard',
                  subtitle: 'Vista general del negocio',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamedAndRemoveUntil(
                      context, 
                      '/dashboard', 
                      (route) => false,
                    );
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.inventory_2,
                  title: 'Productos',
                  subtitle: 'Gestión del catálogo',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/products');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.category,
                  title: 'Categorías',
                  subtitle: 'Organización de productos',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/categories');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.warehouse,
                  title: 'Inventario',
                  subtitle: 'Control de stock',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/inventory');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.store,
                  title: 'Almacenes',
                  subtitle: 'Gestión de almacenes',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/warehouse');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.point_of_sale,
                  title: 'Ventas',
                  subtitle: 'Monitoreo de ventas',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/sales');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.account_balance_wallet,
                  title: 'Finanzas',
                  subtitle: 'Gestión financiera',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/financial');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.people,
                  title: 'Clientes',
                  subtitle: 'CRM y fidelización',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/customers');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.group,
                  title: 'Trabajadores',
                  subtitle: 'Gestión de personal',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/workers');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.settings,
                  title: 'Configuración',
                  subtitle: 'Ajustes del sistema',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/settings');
                  },
                ),
              ],
            ),
          ),
          
          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  'VentIQ Admin v1.0',
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
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: AppColors.primary,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
