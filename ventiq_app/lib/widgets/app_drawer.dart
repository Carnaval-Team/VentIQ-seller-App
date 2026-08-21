import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/admin_access_service.dart';
import '../services/auth_service.dart';
import '../services/auto_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/user_preferences_service.dart';
import '../services/store_config_service.dart';
import '../utils/global_navigator.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({Key? key}) : super(key: key);

  /// Cerrar sesión o abrir selector local (full offline).
  /// Usable desde AppBar / tiles fuera del drawer.
  static Future<void> promptLogoutOrSwitchUser(BuildContext context) =>
      _promptLogoutOrSwitchUser(context);

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

void _goAfterLogout(String routeName) {
  final nav = globalNavigatorKey.currentState;
  if (nav != null) {
    nav.pushNamedAndRemoveUntil(routeName, (route) => false);
    return;
  }
  // Fallback si el key aún no está montado
  final ctx = globalNavigatorKey.currentContext;
  if (ctx != null) {
    Navigator.of(ctx).pushNamedAndRemoveUntil(routeName, (route) => false);
  }
}

Future<void> _promptLogoutOrSwitchUser(BuildContext context) async {
  try {
    final prefs = UserPreferencesService();
    final fullOfflineReady = await prefs.isDeviceFullOfflineReady();
    final stayFullyOffline = await prefs.shouldStayFullyOffline();
    final online = ConnectivityService().isConnected;

    // Si hay conexión real, reconciliar la cola local de turnos contra el
    // servidor antes de decidir si hay "pendientes de sincronizar": una
    // entrada local puede haber quedado huérfana (turno ya cerrado o
    // resuelto en el servidor por otra vía) y sin esto el aviso aparecería
    // siempre aunque en el servidor ya no quede nada pendiente.
    if (online) {
      try {
        await AutoSyncService().reconcileStaleOfflineTurnos();
      } catch (e) {
        print('⚠️ No se pudo reconciliar turnos offline antes del logout: $e');
      }
    }

    final hasUnsynced = await prefs.hasUnsyncedOfflineData();
    final storeId = await prefs.getOfflineInventoryStoreId();

    // Selector local solo si el dispositivo está preparado Y
    // (sin red O modo offline completo activo). Con red + modo online
    // hay que cerrar la sesión real en Supabase.
    final useLocalSwitch =
        fullOfflineReady && (!online || stayFullyOffline);

    // Usar el navigator raíz: el context del drawer se desmonta al cerrarlo.
    final dialogContext =
        globalNavigatorKey.currentContext ?? context;

    if (useLocalSwitch) {
      final bool? confirm = await showDialog<bool>(
        context: dialogContext,
        builder: (BuildContext ctx) {
          return AlertDialog(
            title: const Text('Cambiar de usuario'),
            content: Text(
              hasUnsynced
                  ? 'Hay operaciones sin sincronizar (se conservan). '
                      'Se abrirá el selector local sin salir al servidor.'
                  : 'Se abrirá el selector local (admin/vendedor) sin '
                      'conexión al servidor. Inventario de la tienda'
                      '${storeId != null ? ' #$storeId' : ''} conservado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Cambiar usuario'),
              ),
            ],
          );
        },
      );

      if (confirm == true) {
        // Si hay red, cerrar JWT de Supabase para no dejar sesión del
        // trabajador abierta en el servidor.
        if (online) {
          try {
            await AuthService().signOut();
          } catch (e) {
            print('⚠️ signOut en cambio local (continuando): $e');
            AdminAccessService().clearMemoryCache();
          }
        } else {
          AdminAccessService().clearMemoryCache();
        }
        await prefs.clearSessionKeepingStoreOffline();
        _goAfterLogout('/offline-user-switch');
      }
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: dialogContext,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Cerrar Sesión'),
          content: Text(
            hasUnsynced
                ? 'Hay ventas u operaciones sin sincronizar. '
                    'El inventario de la tienda${storeId != null ? ' #$storeId' : ''} '
                    'se conserva. ¿Cerrar sesión?'
                : '¿Cerrar sesión? El inventario local se conserva.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cerrar Sesión'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    // Cierre real online: siempre signOut de Supabase.
    try {
      await AuthService().signOut();
    } catch (e) {
      print('⚠️ signOut falló, limpiando sesión local igual: $e');
      AdminAccessService().clearMemoryCache();
    }

    if (fullOfflineReady) {
      await prefs.clearSessionKeepingStoreOffline();
      print('🔓 Sesión cerrada → selector local de usuarios');
      _goAfterLogout('/offline-user-switch');
    } else {
      await prefs.clearUserData();
      print('🔓 Sesión cerrada → login');
      _goAfterLogout('/login');
    }
  } catch (e) {
    print('❌ Error al cerrar sesión: $e');
    final messenger = globalScaffoldMessengerKey.currentState;
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Error al cerrar sesión: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

class _AppDrawerState extends State<AppDrawer> {
  String _userName = '';
  String _userEmail = '';
  bool _isLoading = true;
  String _appVersion = 'Cargando...';
  bool _modoRestaurante = false;
  bool _isSuperAdmin = false;
  bool _canManageInventory = false;
  bool _inventoryOnly = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAppVersion();
    _loadModoRestaurante();
    _loadSuperAdminFlag();
    _loadAdminAccess();
  }

  /// Carga el flag de superadmin (cacheado en login). Controla la visibilidad
  /// de la entrada oculta "Datos Offline". Funciona también offline.
  Future<void> _loadSuperAdminFlag() async {
    try {
      final value = await UserPreferencesService().isSuperAdmin();
      if (mounted && value != _isSuperAdmin) {
        setState(() => _isSuperAdmin = value);
      }
    } catch (e) {
      print('❌ Error cargando flag superadmin en drawer: $e');
    }
  }

  /// Solo gerente/supervisor → menú Administración.
  /// Si es sesión solo-gestión, se ocultan opciones de venta/caja.
  Future<void> _loadAdminAccess() async {
    try {
      final admin = AdminAccessService();
      final can = await admin.canManageInventory();
      final only = await admin.isInventoryOnlySession();
      if (!mounted) return;
      setState(() {
        _canManageInventory = can;
        _inventoryOnly = only;
      });
    } catch (e) {
      print('❌ Error cargando acceso admin en drawer: $e');
    }
  }

  /// Carga el flag modo_restaurante desde el cache de StoreConfig.
  /// Se ejecuta en paralelo con los demás loads — el primer render del drawer
  /// es con modo=false, pero el rebuild llega muy rápido y la entrada aparece.
  Future<void> _loadModoRestaurante() async {
    try {
      final config = await StoreConfigService.getStoreConfigFromCache();
      final value = config?['modo_restaurante'] ?? false;
      if (mounted && value != _modoRestaurante) {
        setState(() => _modoRestaurante = value);
      }
    } catch (e) {
      print('❌ Error cargando modo_restaurante en drawer: $e');
    }
  }

  /// Cargar versión de la app desde changelog.json
  Future<void> _loadAppVersion() async {
    try {
      final String changelogString = await rootBundle.loadString('assets/changelog.json');
      final Map<String, dynamic> changelog = json.decode(changelogString);
      final String version = changelog['current_version'] ?? '1.0.0';
      
      if (mounted) {
        setState(() {
          _appVersion = 'v$version';
        });
      }
      
      print('✅ Versión de la app cargada en drawer: $_appVersion');
    } catch (e) {
      print('❌ Error cargando versión desde changelog.json en drawer: $e');
      if (mounted) {
        setState(() {
          _appVersion = 'v1.0.0'; // Fallback
        });
      }
    }
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
                          const Text(
                            'Inventtia® Caja',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
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
                // Gerente/supervisor: solo gestión de inventario/productos
                if (_inventoryOnly) ...[
                  _buildDrawerItem(
                    context,
                    icon: Icons.admin_panel_settings,
                    title: 'Administración',
                    subtitle: 'Inventario y productos',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/admin-home',
                        (route) => false,
                      );
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
                    icon: Icons.settings,
                    title: 'Configuración',
                    subtitle: 'Sync, offline y preferencias',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                  const Divider(height: 1),
                ] else ...[
                  // Modo restaurante: el item de mesas va primero como entrada
                  // principal de la operación. La "Venta de Productos" se
                  // mantiene debajo (útil para venta de mostrador puntual).
                  if (_modoRestaurante) ...[
                    _buildDrawerItem(
                      context,
                      icon: Icons.table_restaurant,
                      title: 'Mesas y Comensales',
                      subtitle: 'Gestionar mesas y cuentas abiertas',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/mesas',
                          (route) => false,
                        );
                      },
                    ),
                    const Divider(height: 1),
                  ],

                  _buildDrawerItem(
                    context,
                    icon: Icons.shopping_cart,
                    title: _modoRestaurante
                        ? 'Venta de Mostrador'
                        : 'Venta de Productos',
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

                  if (_canManageInventory) ...[
                    _buildDrawerItem(
                      context,
                      icon: Icons.admin_panel_settings,
                      title: 'Administración',
                      subtitle: 'Inventario y productos',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/admin-home');
                      },
                    ),
                    const Divider(height: 1),
                  ],
                  _buildDrawerItem(
                    context,
                    icon: Icons.settings,
                    title: 'Configuración',
                    subtitle: 'Sync, offline y preferencias',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                  const Divider(height: 1),
                ],

                // Entrada oculta: solo visible para superadmins. Diagnóstico de
                // los datos guardados para trabajar offline.
                if (_isSuperAdmin) ...[
                  _buildDrawerItem(
                    context,
                    icon: Icons.storage,
                    title: 'Datos Offline',
                    subtitle: 'Ver datos guardados sin conexión',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/offline-data-viewer');
                    },
                  ),
                  const Divider(height: 1),
                ],

                _buildDrawerItem(
                  context,
                  icon: Icons.logout,
                  title: _inventoryOnly || _canManageInventory
                      ? 'Cambiar usuario / Salir'
                      : 'Cerrar Sesión',
                  subtitle: 'Salir o cambiar de cuenta en este dispositivo',
                  onTap: () {
                    // Cerrar drawer; la navegación post-logout usa globalNavigatorKey.
                    Navigator.pop(context);
                    AppDrawer.promptLogoutOrSwitchUser(
                      globalNavigatorKey.currentContext ?? context,
                    );
                  },
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
                  'Inventtia® Caja $_appVersion',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
