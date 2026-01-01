import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../config/app_colors.dart';
import '../services/user_preferences_service.dart';
import '../services/permissions_service.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../utils/navigation_guard.dart';
import '../services/changelog_service.dart';
import '../services/update_service.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/update_dialog.dart';

class AdminDrawer extends StatefulWidget {
  const AdminDrawer({Key? key}) : super(key: key);

  @override
  State<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends State<AdminDrawer> {
  String _userName = '';
  String _userEmail = '';
  bool _isLoading = true;
  String _appVersion = 'v1.0.0';
  final ChangelogService _changelogService = ChangelogService();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAppVersion();
  }

  Future<void> _loadUserData() async {
    try {
      final userPrefs = UserPreferencesService();

      print('=== DEBUG ADMIN DRAWER USER DATA ===');

      // Obtener perfil del administrador
      final adminProfile = await userPrefs.getAdminProfile();
      print('Admin Profile: $adminProfile');

      final name = adminProfile['name'] as String?;
      final role = adminProfile['role'] as String?;
      final email = adminProfile['email'] as String?;

      print('Name: $name');
      print('Role: $role');
      print('Email: $email');

      String displayName = name ?? 'Administrador';
      String displayEmail = email ?? 'admin@inventtia.com';

      print('Display Name: $displayName');
      print('Display Email: $displayEmail');
      print('===================================');

      setState(() {
        _userName = displayName;
        _userEmail = displayEmail;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading admin user data: $e');
      setState(() {
        _userName = 'Administrador';
        _userEmail = 'admin@inventtia.com';
        _isLoading = false;
      });
    }
  }

  /// Cargar versión de la app desde changelog.json
  Future<void> _loadAppVersion() async {
    try {
      final String changelogString = await rootBundle.loadString('assets/changelog.json');
      final Map<String, dynamic> changelog = json.decode(changelogString);
      final String version = changelog['current_version'] ?? '1.0.0';
      final int build = changelog['build'] ?? 100;
      
      if (mounted) {
        setState(() {
          _appVersion = 'v$version';
        });
      }
      
      print('✅ Versión de la app cargada: $_appVersion');
    } catch (e) {
      print('❌ Error cargando versión desde changelog.json: $e');
      if (mounted) {
        setState(() {
          _appVersion = 'v1.0.0 (100)'; // Fallback
        });
      }
    }
  }

  /// Verificar si la tienda puede acceder a consignaciones
  /// Todas las tiendas pueden ver consignaciones (para confirmar contratos)
  /// Pero solo con plan Avanzado pueden crear contratos
  Future<bool> _hasConsignacionFeature() async {
    try {
      // Todas las tiendas pueden acceder a consignaciones
      // La restricción de crear contratos se valida en la pantalla
      return true;
    } catch (e) {
      print('❌ Error verificando función de consignación: $e');
      return false;
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
                            _isLoading ? 'Cargando...' : _userName,
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
                            _isLoading ? 'Cargando...' : _userEmail,
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
                    NavigationGuard.navigateAndRemoveUntil(
                      context,
                      '/dashboard',
                    );
                  },
                ),
                const Divider(height: 1),

                // Productos (solo Gerente y Supervisor)
                FutureBuilder<bool>(
                  future: NavigationGuard.canNavigate(
                    '/products',
                    context,
                    showDialog: false,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          _buildDrawerItem(
                            context,
                            icon: Icons.inventory_2,
                            title: 'Productos',
                            subtitle: 'Gestión del catálogo',
                            onTap: () {
                              Navigator.pop(context);
                              NavigationGuard.navigateWithPermission(
                                context,
                                '/products-dashboard',
                              );
                            },
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Inventario (solo Gerente y Supervisor)
                FutureBuilder<bool>(
                  future: NavigationGuard.canNavigate(
                    '/inventory',
                    context,
                    showDialog: false,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          _buildDrawerItem(
                            context,
                            icon: Icons.warehouse,
                            title: 'Inventario',
                            subtitle: 'Control de stock',
                            onTap: () {
                              Navigator.pop(context);
                              NavigationGuard.navigateWithPermission(context, '/inventory');
                            },
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                _buildDrawerItem(
                  context,
                  icon: Icons.store,
                  title: 'Almacenes',
                  subtitle: 'Gestión de almacenes',
                  onTap: () {
                    Navigator.pop(context);
                    NavigationGuard.navigateWithPermission(context, '/warehouse');
                  },
                ),
                const Divider(height: 1),

                // TPVs (Puntos de Venta)
                _buildDrawerItem(
                  context,
                  icon: Icons.point_of_sale,
                  title: 'TPVs',
                  subtitle: 'Gestión de puntos de venta',
                  onTap: () {
                    Navigator.pop(context);
                    NavigationGuard.navigateWithPermission(context, '/tpv-management');
                  },
                ),
                const Divider(height: 1),

                // Marketing (solo Gerente)
                FutureBuilder<bool>(
                  future: NavigationGuard.canNavigate(
                    '/marketing-dashboard',
                    context,
                    showDialog: false,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          _buildDrawerItem(
                            context,
                            icon: Icons.campaign,
                            title: 'Marketing',
                            subtitle: 'Campañas y promociones',
                            onTap: () {
                              Navigator.pop(context);
                              NavigationGuard.navigateWithPermission(
                                context,
                                '/marketing-dashboard',
                              );
                            },
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Ventas (solo Gerente y Supervisor)
                FutureBuilder<bool>(
                  future: NavigationGuard.canNavigate(
                    '/sales',
                    context,
                    showDialog: false,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          _buildDrawerItem(
                            context,
                            icon: Icons.point_of_sale,
                            title: 'Ventas',
                            subtitle: 'Monitoreo de ventas',
                            onTap: () {
                              Navigator.pop(context);
                              NavigationGuard.navigateWithPermission(context, '/sales');
                            },
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Finanzas (solo Gerente)
                FutureBuilder<bool>(
                  future: NavigationGuard.canNavigate(
                    '/financial',
                    context,
                    showDialog: false,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          _buildDrawerItem(
                            context,
                            icon: Icons.account_balance_wallet,
                            title: 'Finanzas',
                            subtitle: 'Gestión financiera',
                            onTap: () {
                              Navigator.pop(context);
                              NavigationGuard.navigateWithPermission(context, '/financial');
                            },
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // CRM (solo Gerente)
                FutureBuilder<bool>(
                  future: NavigationGuard.canNavigate(
                    '/crm-dashboard',
                    context,
                    showDialog: false,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          _buildDrawerItem(
                            context,
                            icon: Icons.business_center,
                            title: 'CRM Empresarial',
                            subtitle: 'Clientes y proveedores',
                            onTap: () {
                              Navigator.pop(context);
                              NavigationGuard.navigateWithPermission(context, '/crm-dashboard');
                            },
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Consignaciones (solo con plan Avanzado)
                FutureBuilder<bool>(
                  future: _hasConsignacionFeature(),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          _buildDrawerItem(
                            context,
                            icon: Icons.handshake,
                            title: 'Consignaciones',
                            subtitle: 'Gestión de consignaciones',
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/consignacion');
                            },
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Trabajadores (solo Gerente y Supervisor)
                FutureBuilder<bool>(
                  future: NavigationGuard.canNavigate(
                    '/workers',
                    context,
                    showDialog: false,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return Column(
                        children: [
                          _buildDrawerItem(
                            context,
                            icon: Icons.group,
                            title: 'Trabajadores',
                            subtitle: 'Gestión de personal',
                            onTap: () {
                              Navigator.pop(context);
                              NavigationGuard.navigateWithPermission(context, '/workers');
                            },
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Configuración (solo Gerente)
                FutureBuilder<bool>(
                  future: NavigationGuard.canNavigate(
                    '/settings',
                    context,
                    showDialog: false,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.data == true) {
                      return _buildDrawerItem(
                        context,
                        icon: Icons.settings,
                        title: 'Configuración',
                        subtitle: 'Ajustes del sistema',
                        onTap: () {
                          Navigator.pop(context);
                          NavigationGuard.navigateWithPermission(context, '/settings');
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const Divider(height: 1),

                _buildDrawerItem(
                  context,
                  icon: Icons.logout,
                  title: 'Cerrar Sesión',
                  subtitle: 'Salir del panel de administración',
                  onTap: () => _showLogoutDialog(context),
                  isLogout: true,
                ),
              ],
            ),
          ),

          // Footer
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Inventtia® Admin $_appVersion',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _checkForUpdates,
                      icon: Icon(Icons.system_update, size: 16, color: AppColors.primary),
                      label: Text(
                        'Ver Novedades',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Verificar actualizaciones disponibles
  Future<void> _checkForUpdates() async {
    // Mostrar diálogo de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Verificando actualizaciones...'),
          ],
        ),
      ),
    );

    try {
      final updateInfo = await UpdateService.checkForUpdates();
      
      // Cerrar diálogo de carga
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (updateInfo['hay_actualizacion'] == true) {
        // Hay actualización disponible
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: updateInfo['obligatoria'] != true,
            builder: (context) => UpdateDialog(updateInfo: updateInfo),
          );
        }
      } else {
        // No hay actualizaciones, mostrar changelog actual
        final changelog = await _changelogService.getLatestChangelog();
        if (changelog != null && mounted) {
          showDialog(
            context: context,
            barrierDismissible: true,
            builder: (context) => ChangelogDialog(changelog: changelog),
          );
        }
      }
    } catch (e) {
      // Cerrar diálogo de carga
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      print('Error checking for updates: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al verificar actualizaciones: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Mostrar diálogo de confirmación para cerrar sesión
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext builderContext, StateSetter setState) {
            bool isLoading = false;

            return AlertDialog(
              title: const Text('Cerrar Sesión'),
              content: isLoading
                  ? const SizedBox(
                      height: 50,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : const Text('¿Estás seguro de que deseas cerrar sesión?'),
              actions: [
                if (!isLoading)
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancelar'),
                  ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          // Hacer logout
                          await _performLogout();
                          // Cerrar diálogo
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          // Navegar a splash que detectará que no hay sesión
                          if (context.mounted) {
                            Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
                              '/',
                              (route) => false,
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Cerrar Sesión'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Realizar logout
  Future<void> _performLogout() async {
    try {
      print('🔐 Iniciando logout...');
      final authService = AuthService();

      // Usar AuthService.signOut() que limpia TODO correctamente
      await authService.signOut();

      // Pequeña espera para asegurar que la limpieza se complete
      await Future.delayed(const Duration(milliseconds: 300));

      print('✅ Logout completado');
    } catch (e) {
      print('❌ Error durante logout: $e');
    }
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLogout = false,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:
              isLogout
                  ? Colors.red.withOpacity(0.1)
                  : AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isLogout ? Colors.red : AppColors.primary,
          size: 24,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isLogout ? Colors.red : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isLogout ? Colors.red[400] : Colors.grey[600],
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildSubMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        margin: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: Colors.grey[600], size: 18),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.grey[700],
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      dense: true,
    );
  }
}
