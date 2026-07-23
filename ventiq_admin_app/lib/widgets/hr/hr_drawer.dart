import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../config/app_colors.dart';
import '../../services/user_preferences_service.dart';
import '../../services/auth_service.dart';

class HRDrawer extends StatefulWidget {
  final bool isFromGerente;

  const HRDrawer({Key? key, this.isFromGerente = false}) : super(key: key);

  @override
  State<HRDrawer> createState() => _HRDrawerState();
}

class _HRDrawerState extends State<HRDrawer> {
  String _userName = '';
  String _userEmail = '';
  bool _isLoading = true;
  String _appVersion = 'v1.0.0';
  List<Map<String, dynamic>> _userStores = [];
  int? _currentStoreId;
  String _currentStoreName = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAppVersion();
  }

  Future<void> _loadUserData() async {
    try {
      final userPrefs = UserPreferencesService();
      final adminProfile = await userPrefs.getAdminProfile();
      final name = adminProfile['name'] as String?;
      final email = adminProfile['email'] as String?;
      final stores = await userPrefs.getUserStores();
      final currentStoreId = await userPrefs.getIdTienda();

      setState(() {
        _userName = name ?? 'Recursos Humanos';
        _userEmail = email ?? 'rrhh@inventtia.com';
        _userStores = stores ?? [];
        _currentStoreId = currentStoreId;
        _currentStoreName = _userStores
            .firstWhere(
              (s) => s['id_tienda'] == currentStoreId,
              orElse: () => {'denominacion': 'Tienda $_currentStoreId'},
            )['denominacion'] as String? ?? 'Tienda $currentStoreId';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _userName = 'Recursos Humanos';
        _userEmail = 'rrhh@inventtia.com';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final String changelogString = await rootBundle.loadString(
        'assets/changelog.json',
      );
      final Map<String, dynamic> changelog = json.decode(changelogString);
      final String version = changelog['current_version'] ?? '1.0.0';

      if (mounted) {
        setState(() {
          _appVersion = 'v$version';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appVersion = 'v1.0.0';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header con gradiente
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
                        Icons.badge,
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
                            'Recursos Humanos',
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
          // Menu
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.dashboard,
                  title: 'Dashboard RR.HH.',
                  subtitle: 'Resumen de recursos humanos',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/hr-dashboard');
                  },
                ),
                const Divider(height: 1),
                _buildDrawerItem(
                  context,
                  icon: Icons.login,
                  title: 'Firmar Entrada',
                  subtitle: 'Registrar entrada de trabajadores',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/hr-checkin');
                  },
                ),
                const Divider(height: 1),
                _buildDrawerItem(
                  context,
                  icon: Icons.logout,
                  title: 'Firmar Salida',
                  subtitle: 'Registrar salida de trabajadores',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/hr-checkout');
                  },
                ),
                const Divider(height: 1),
                _buildDrawerItem(
                  context,
                  icon: Icons.receipt_long,
                  title: 'Reporte de Salarios',
                  subtitle: 'Consultar y exportar salarios',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/hr-salary-report');
                  },
                ),
                const Divider(height: 1),
                _buildDrawerItem(
                  context,
                  icon: Icons.settings,
                  title: 'Configurar Trabajador',
                  subtitle: 'Salarios y pago por resultado',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushReplacementNamed(context, '/hr-worker-config');
                  },
                ),
                const Divider(height: 1),

                // Cambiar tienda (solo si tiene acceso a múltiples tiendas)
                if (_userStores.length > 1) ...[
                  const Divider(height: 1),
                  _buildDrawerItem(
                    context,
                    icon: Icons.store_outlined,
                    title: 'Cambiar Tienda',
                    subtitle: _currentStoreName.isNotEmpty
                        ? 'Ahora: $_currentStoreName'
                        : 'Seleccionar tienda',
                    onTap: () {
                      Navigator.pop(context);
                      // StoreSelectionScreen expects stores in the format:
                      // {'id_tienda': int, 'app_dat_tienda': {'denominacion': string}}
                      final storesForScreen = _userStores.map((s) => {
                        'id_tienda': s['id_tienda'],
                        'app_dat_tienda': {'denominacion': s['denominacion'] ?? 'Tienda ${s['id_tienda']}'},
                      }).toList();
                      Navigator.pushReplacementNamed(
                        context,
                        '/store-selection',
                        arguments: {
                          'stores': storesForScreen,
                          'defaultStoreId': _currentStoreId ?? _userStores.first['id_tienda'],
                        },
                      );
                    },
                  ),
                ],

                // Opcion para gerente: ir a administracion
                if (widget.isFromGerente) ...[
                  _buildDrawerItem(
                    context,
                    icon: Icons.admin_panel_settings,
                    title: 'Ir a Administracion',
                    subtitle: 'Volver al panel de gestion',
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
                ],

                _buildDrawerItem(
                  context,
                  icon: Icons.power_settings_new,
                  title: 'Cerrar Sesion',
                  subtitle: 'Salir de la aplicacion',
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
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Inventtia Gestión $_appVersion',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext builderContext, StateSetter setState) {
            bool isLoading = false;
            return AlertDialog(
              title: const Text('Cerrar Sesion'),
              content: isLoading
                  ? const SizedBox(
                      height: 50,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const Text('Estas seguro de que deseas cerrar sesion?'),
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
                          await AuthService().signOut();
                          await Future.delayed(const Duration(milliseconds: 300));
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (context.mounted) {
                            Navigator.of(context, rootNavigator: true)
                                .pushNamedAndRemoveUntil('/', (route) => false);
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
                      : const Text('Cerrar Sesion'),
                ),
              ],
            );
          },
        );
      },
    );
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
          color: isLogout
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
}
