import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            height: 100,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    Icons.store,
                    size: 28,
                    color: Colors.white,
                  ),
                  SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VentIQ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Gestión de Ventas',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
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
                  icon: Icons.shopping_cart,
                  title: 'Venta de Productos',
                  subtitle: 'Ir al catálogo de productos',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamedAndRemoveUntil(
                      context, 
                      '/categories', 
                      (route) => false,
                    );
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.lock_open,
                  title: 'Crear Apertura',
                  subtitle: 'Abrir caja para el día',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/apertura');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.money_off,
                  title: 'Crear Egreso',
                  subtitle: 'Registrar salida de dinero',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/egreso');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.receipt_long,
                  title: 'Venta Total',
                  subtitle: 'Ver productos vendidos',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/venta-total');
                  },
                ),
                const Divider(height: 1),
                
                _buildDrawerItem(
                  context,
                  icon: Icons.lock,
                  title: 'Crear Cierre',
                  subtitle: 'Cerrar caja del día',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/cierre');
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
                  'VentIQ v1.0',
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
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: const Color(0xFF4A90E2),
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
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
