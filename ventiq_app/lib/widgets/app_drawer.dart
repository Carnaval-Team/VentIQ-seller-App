import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_preferences_service.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _userName = '';
  String _userEmail = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final userPrefs = UserPreferencesService();

      print('=== DEBUG DRAWER USER DATA ===');

      // Obtener perfil del trabajador
      final workerProfile = await userPrefs.getWorkerProfile();
      print('Worker Profile: $workerProfile');

      final nombres = workerProfile['nombres'] as String?;
      final apellidos = workerProfile['apellidos'] as String?;

      print('Nombres: $nombres');
      print('Apellidos: $apellidos');

      // Obtener email del usuario
      final email = await userPrefs.getUserEmail();
      print('Email: $email');

      String displayName = '';
      if (nombres != null && apellidos != null) {
        displayName = '$nombres $apellidos';
      } else if (nombres != null) {
        displayName = nombres;
      } else {
        displayName = 'Usuario';
      }

      print('Display Name: $displayName');
      print('==============================');

      setState(() {
        _userName = displayName;
        _userEmail = email ?? 'Sin email';
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user data in drawer: $e');
      setState(() {
        _userName = 'Usuario';
        _userEmail = 'Sin email';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
              ),
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
                      child: Icon(Icons.person, size: 30, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // const Text(
                          //   'VentIQ',
                          //   style: TextStyle(
                          //     color: Colors.white,
                          //     fontSize: 18,
                          //     fontWeight: FontWeight.bold,
                          //     letterSpacing: 0.5,
                          //   ),
                          // ),
                          const SizedBox(height: 6),
                          if (_isLoading)
                            const Row(
                              children: [
                                SizedBox(
                                  height: 12,
                                  width: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white70,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Cargando...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            Text(
                              _userName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
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
                              'Gestión de Ventas',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
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
                const Divider(height: 1),

                _buildDrawerItem(
                  context,
                  icon: Icons.people,
                  title: 'Trabajadores de Turno',
                  subtitle: 'Gestionar trabajadores del turno',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/shift-workers');
                  },
                ),
                const Divider(height: 1),

                _buildDrawerItem(
                  context,
                  icon: Icons.logout,
                  title: 'Cerrar Sesión',
                  subtitle: 'Salir de la aplicación',
                  onTap: () => _handleLogout(context),
                ),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'VentIQ v1.0',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Manejar logout
  Future<void> _handleLogout(BuildContext context) async {
    try {
      // Mostrar diálogo de confirmación
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Cerrar Sesión'),
            content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Cerrar Sesión'),
              ),
            ],
          );
        },
      );

      if (confirm == true) {
        // Cerrar sesión en Supabase
        await AuthService().signOut();

        // Limpiar datos del usuario de las preferencias
        await UserPreferencesService().clearUserData();

        print('🔓 Sesión cerrada y datos limpiados');

        // Navegar al login y limpiar toda la pila de navegación
        if (context.mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      }
    } catch (e) {
      print('❌ Error al cerrar sesión: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cerrar sesión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        child: Icon(icon, color: const Color(0xFF4A90E2), size: 24),
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
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
