import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/order_service.dart';
import '../services/user_preferences_service.dart';
import '../services/category_service.dart';
import '../services/product_service.dart';
import '../services/promotion_service.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final OrderService _orderService = OrderService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  bool _isPrintEnabled = true; // Valor por defecto
  bool _isLimitDataUsageEnabled = false; // Valor por defecto
  bool _isOfflineModeEnabled = false; // Valor por defecto

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final printEnabled = await _userPreferencesService.isPrintEnabled();
    final limitDataEnabled = await _userPreferencesService.isLimitDataUsageEnabled();
    final offlineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
    setState(() {
      _isPrintEnabled = printEnabled;
      _isLimitDataUsageEnabled = limitDataEnabled;
      _isOfflineModeEnabled = offlineModeEnabled;
    });
  }

  Future<void> _onPrintSettingChanged(bool value) async {
    setState(() {
      _isPrintEnabled = value;
    });

    await _userPreferencesService.setPrintEnabled(value);

    // Mostrar confirmación al usuario
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '✅ Impresión habilitada - Las órdenes se imprimirán automáticamente'
              : '❌ Impresión deshabilitada - Las órdenes no se imprimirán',
        ),
        backgroundColor: value ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onLimitDataUsageChanged(bool value) async {
    setState(() {
      _isLimitDataUsageEnabled = value;
    });

    await _userPreferencesService.setLimitDataUsage(value);

    // Mostrar confirmación al usuario
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '📱 Modo ahorro de datos activado - Las imágenes no se cargarán'
              : '📶 Modo ahorro de datos desactivado - Las imágenes se cargarán normalmente',
        ),
        backgroundColor: value ? Colors.blue : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onOfflineModeChanged(bool value) async {
    if (value) {
      // Si se activa, mostrar diálogo de sincronización
      await _showSyncDialog();
    } else {
      // Si se desactiva, simplemente actualizar el estado
      setState(() {
        _isOfflineModeEnabled = false;
      });
      await _userPreferencesService.setOfflineMode(false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌐 Modo offline desactivado'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Configuración',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sección de cuenta
          _buildSectionHeader('Cuenta'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.person_outline,
              title: 'Perfil de Usuario',
              subtitle: 'Editar información personal',
              onTap: () => _showComingSoon('Perfil de Usuario'),
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.lock_outline,
              title: 'Cambiar Contraseña',
              subtitle: 'Actualizar credenciales de acceso',
              onTap: () => _showComingSoon('Cambiar Contraseña'),
            ),
          ]),

          const SizedBox(height: 16),

          // Sección de aplicación
          _buildSectionHeader('Aplicación'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Notificaciones',
              subtitle: 'Configurar alertas y avisos',
              onTap: () => _showComingSoon('Notificaciones'),
            ),
            _buildDivider(),
            _buildPrintSettingsTile(),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.language_outlined,
              title: 'Idioma',
              subtitle: 'Español',
              onTap: () => _showComingSoon('Idioma'),
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.dark_mode_outlined,
              title: 'Tema',
              subtitle: 'Claro',
              onTap: () => _showComingSoon('Tema'),
            ),
          ]),

          const SizedBox(height: 16),

          // Sección de uso de datos
          _buildSectionHeader('Uso de datos'),
          _buildSettingsCard([
            _buildDataUsageSettingsTile(),
            _buildDivider(),
            _buildOfflineModeSettingsTile(),
          ]),

          const SizedBox(height: 16),

          // Sección de datos
          _buildSectionHeader('Datos'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.sync_outlined,
              title: 'Sincronización',
              subtitle: 'Última sync: Hace 2 horas',
              onTap: () => _showComingSoon('Sincronización'),
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.storage_outlined,
              title: 'Almacenamiento',
              subtitle: 'Gestionar datos locales',
              onTap: () => _showStorageOptions(),
            ),
          ]),

          const SizedBox(height: 16),

          // Sección de ayuda
          _buildSectionHeader('Ayuda y Soporte'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.help_outline,
              title: 'Centro de Ayuda',
              subtitle: 'Preguntas frecuentes y tutoriales',
              onTap: () => _showComingSoon('Centro de Ayuda'),
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.contact_support_outlined,
              title: 'Contactar Soporte',
              subtitle: 'Reportar problemas o sugerencias',
              onTap: () => _showComingSoon('Contactar Soporte'),
            ),
            _buildDivider(),
            _buildSettingsTile(
              icon: Icons.info_outline,
              title: 'Acerca de',
              subtitle: 'VentIQ v1.0.0',
              onTap: () => _showAboutDialog(),
            ),
          ]),

          const SizedBox(height: 24),

          // Botón de cerrar sesión
          _buildLogoutButton(),

          const SizedBox(height: 80), // Espacio para el bottom navigation
        ],
      ),
      endDrawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 3, // Configuración tab
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF4A90E2), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey[200],
      indent: 60,
    );
  }

  Widget _buildPrintSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.print_outlined,
          color: Color(0xFF4A90E2),
          size: 20,
        ),
      ),
      title: const Text(
        'Habilitar Impresión',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isPrintEnabled
            ? 'Las órdenes se imprimirán automáticamente'
            : 'Impresión deshabilitada',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isPrintEnabled,
        onChanged: _onPrintSettingChanged,
        activeColor: const Color(0xFF4A90E2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDataUsageSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.data_saver_on,
          color: Colors.orange,
          size: 20,
        ),
      ),
      title: const Text(
        'Limitar uso de datos',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isLimitDataUsageEnabled
            ? 'Modo ahorro activado - No se cargarán imágenes'
            : 'Carga completa de imágenes',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isLimitDataUsageEnabled,
        onChanged: _onLimitDataUsageChanged,
        activeColor: Colors.orange,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildOfflineModeSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.cloud_off,
          color: Colors.blue,
          size: 20,
        ),
      ),
      title: const Text(
        'Modo Offline',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isOfflineModeEnabled
            ? 'Datos sincronizados - Puede trabajar sin conexión'
            : 'Sincronizar datos para trabajar offline',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isOfflineModeEnabled,
        onChanged: _onOfflineModeChanged,
        activeColor: Colors.blue,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[300]!, width: 1),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.logout, color: Colors.red, size: 20),
        ),
        title: const Text(
          'Cerrar Sesión',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.red,
          ),
        ),
        subtitle: Text(
          'Salir de la aplicación',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        onTap: _showLogoutDialog,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  Future<void> _showSyncDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _SyncDialog(
          userPreferencesService: _userPreferencesService,
          onSyncComplete: (bool success) {
            Navigator.of(context).pop();
            if (success) {
              setState(() {
                _isOfflineModeEnabled = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Datos sincronizados correctamente - Modo offline activado'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            } else {
              setState(() {
                _isOfflineModeEnabled = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Error al sincronizar datos'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
        );
      },
    );
  }

  void _showComingSoon(String feature) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('$feature'),
            content: Text(
              'Esta funcionalidad estará disponible en una próxima actualización.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  void _showStorageOptions() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Gestión de Datos'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Opciones de almacenamiento:'),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Limpiar todas las órdenes'),
                  subtitle: Text(
                    '${_orderService.totalOrders} órdenes guardadas',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showClearOrdersDialog();
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
    );
  }

  void _showClearOrdersDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Limpiar Órdenes'),
            content: Text(
              '¿Estás seguro de que quieres eliminar todas las órdenes guardadas? Esta acción no se puede deshacer.\n\nSe eliminarán ${_orderService.totalOrders} órdenes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  _orderService.clearAllOrders();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Todas las órdenes han sido eliminadas'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Eliminar Todo'),
              ),
            ],
          ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'VentIQ',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.inventory_2, color: Colors.white, size: 32),
      ),
      children: [
        const Text('Aplicación de gestión de inventario y ventas.'),
        const SizedBox(height: 8),
        const Text(
          'Desarrollado para optimizar el proceso de pedidos y gestión de productos.',
        ),
      ],
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cerrar Sesión'),
            content: const Text('¿Estás seguro de que quieres cerrar sesión?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Aquí implementarías la lógica de logout real
                  Navigator.pop(context);
                  _performLogout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Cerrar Sesión'),
              ),
            ],
          ),
    );
  }

  void _performLogout() {
    // Limpiar datos de sesión si es necesario
    // _orderService.clearAllOrders(); // Opcional: limpiar órdenes al cerrar sesión

    // Mostrar mensaje de confirmación
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('👋 Sesión cerrada exitosamente'),
        backgroundColor: Colors.green,
      ),
    );

    // Navegar a la pantalla de login (por ahora volvemos a categorías)
    // En una implementación real, aquí navegarías a la pantalla de login
    Navigator.pushNamedAndRemoveUntil(context, '/categories', (route) => false);
  }
  
  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/categories',
          (route) => false,
        );
        break;
      case 1: // Preorden
        Navigator.pushNamed(context, '/preorder');
        break;
      case 2: // Órdenes
        Navigator.pushNamed(context, '/orders');
        break;
      case 3: // Configuración (current)
        break;
    }
  }
}

// Widget del diálogo de sincronización
class _SyncDialog extends StatefulWidget {
  final UserPreferencesService userPreferencesService;
  final Function(bool) onSyncComplete;

  const _SyncDialog({
    required this.userPreferencesService,
    required this.onSyncComplete,
  });

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  double _progress = 0.0;
  String _currentTask = 'Iniciando sincronización...';
  bool _isCompleted = false;
  bool _hasError = false;

  final List<Map<String, String>> _tasks = [
    {'name': 'Guardando credenciales', 'key': 'credentials'},
    {'name': 'Sincronizando promociones globales', 'key': 'promotions'},
    {'name': 'Descargando categorías', 'key': 'categories'},
    {'name': 'Descargando productos', 'key': 'products'},
    {'name': 'Sincronizando órdenes', 'key': 'orders'},
  ];

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    try {
      final Map<String, dynamic> offlineData = {};
      
      for (int i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        setState(() {
          _currentTask = task['name']!;
          _progress = (i + 1) / _tasks.length;
        });

        // Simular delay para mostrar progreso
        await Future.delayed(const Duration(milliseconds: 800));

        // Aquí irían las llamadas reales a los servicios
        switch (task['key']) {
          case 'credentials':
            offlineData['credentials'] = await _syncCredentials();
            break;
          case 'promotions':
            offlineData['promotions'] = await _syncPromotions();
            break;
          case 'categories':
            offlineData['categories'] = await _syncCategories();
            break;
          case 'products':
            offlineData['products'] = await _syncProducts();
            break;
          case 'orders':
            offlineData['orders'] = await _syncOrders();
            break;
        }
      }

      // Guardar todos los datos offline
      await widget.userPreferencesService.saveOfflineData(offlineData);
      await widget.userPreferencesService.setOfflineMode(true);

      setState(() {
        _isCompleted = true;
        _currentTask = '¡Sincronización completada!';
      });

      // Esperar un momento antes de cerrar
      await Future.delayed(const Duration(seconds: 1));
      widget.onSyncComplete(true);
    } catch (e) {
      print('❌ Error durante sincronización: $e');
      setState(() {
        _hasError = true;
        _currentTask = 'Error: $e';
      });
      await Future.delayed(const Duration(seconds: 2));
      widget.onSyncComplete(false);
    }
  }

  Future<Map<String, dynamic>> _syncCredentials() async {
    final userData = await widget.userPreferencesService.getUserData();
    final credentials = await widget.userPreferencesService.getSavedCredentials();
    
    // Verificar que tenemos email y password
    final email = userData['email'] ?? credentials['email'];
    final password = credentials['password'];
    final userId = userData['userId'];
    
    if (email == null || password == null || userId == null) {
      throw Exception(
        'No se pueden sincronizar credenciales. '
        'Asegúrate de marcar "Recordarme" en el login para habilitar modo offline.'
      );
    }
    
    print('✅ Credenciales encontradas:');
    print('  - Email: $email');
    print('  - Password: ${password.isNotEmpty ? "***" : "vacío"}');
    print('  - UserId: $userId');
    
    // Guardar usuario en el array de usuarios offline
    await widget.userPreferencesService.saveOfflineUser(
      email: email,
      password: password,
      userId: userId,
    );
    
    return {
      'email': email,
      'password': password,
      'userId': userId,
    };
  }

  Future<Map<String, dynamic>> _syncPromotions() async {
    final promotionData = await widget.userPreferencesService.getPromotionData();
    return promotionData ?? {};
  }

  Future<List<Map<String, dynamic>>> _syncCategories() async {
    // Aquí llamarías al CategoryService para obtener todas las categorías
    final categoryService = CategoryService();
    try {
      final categories = await categoryService.getCategories();
      return categories.map((cat) => {
        'id': cat.id,
        'name': cat.name,
        'imageUrl': cat.imageUrl,
        'color': cat.color.value,
      }).toList();
    } catch (e) {
      print('Error sincronizando categorías: $e');
      return [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _syncProducts() async {
    final productService = ProductService();
    final categoryService = CategoryService();
    final Map<String, List<Map<String, dynamic>>> productsByCategory = {};
    
    try {
      final categories = await categoryService.getCategories();
      print('📦 Sincronizando productos de ${categories.length} categorías...');
      
      for (var category in categories) {
        final productsMap = await productService.getProductsByCategory(category.id);
        
        // Convertir el Map<String, List<Product>> a lista plana con detalles completos
        final List<Map<String, dynamic>> allProducts = [];
        
        for (var entry in productsMap.entries) {
          final subcategory = entry.key;
          final products = entry.value;
          
          for (var prod in products) {
            try {
              // Obtener detalles completos del producto usando el RPC get_detalle_producto
              print('  🔍 Obteniendo detalles de: ${prod.denominacion} (ID: ${prod.id})');
              
              final detailResponse = await Supabase.instance.client.rpc(
                'get_detalle_producto',
                params: {'id_producto_param': prod.id},
              );
              
              if (detailResponse != null) {
                // Guardar la respuesta completa del RPC con todos los detalles
                final productWithDetails = {
                  'id': prod.id,
                  'denominacion': prod.denominacion,
                  'precio': prod.precio,
                  'foto': prod.foto,
                  'categoria': prod.categoria,
                  'descripcion': prod.descripcion,
                  'cantidad': prod.cantidad,
                  'subcategoria': subcategory,
                  // Agregar detalles completos del RPC
                  'detalles_completos': detailResponse,
                };
                
                allProducts.add(productWithDetails);
                print('    ✅ Detalles obtenidos para: ${prod.denominacion}');
              } else {
                // Si no hay detalles, guardar solo datos básicos
                allProducts.add({
                  'id': prod.id,
                  'denominacion': prod.denominacion,
                  'precio': prod.precio,
                  'foto': prod.foto,
                  'categoria': prod.categoria,
                  'descripcion': prod.descripcion,
                  'cantidad': prod.cantidad,
                  'subcategoria': subcategory,
                });
                print('    ⚠️ Sin detalles para: ${prod.denominacion}');
              }
            } catch (e) {
              print('    ❌ Error obteniendo detalles de ${prod.denominacion}: $e');
              // En caso de error, guardar solo datos básicos
              allProducts.add({
                'id': prod.id,
                'denominacion': prod.denominacion,
                'precio': prod.precio,
                'foto': prod.foto,
                'categoria': prod.categoria,
                'descripcion': prod.descripcion,
                'cantidad': prod.cantidad,
                'subcategoria': subcategory,
              });
            }
          }
        }
        
        productsByCategory[category.id.toString()] = allProducts;
        print('✅ Categoría "${category.name}": ${allProducts.length} productos sincronizados');
      }
      
      print('🎉 Total de productos sincronizados: ${productsByCategory.values.fold(0, (sum, list) => sum + list.length)}');
      return productsByCategory;
    } catch (e) {
      print('❌ Error sincronizando productos: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> _syncOrders() async {
    try {
      // Obtener datos del usuario
      final userData = await widget.userPreferencesService.getUserData();
      final idTienda = await widget.userPreferencesService.getIdTienda();
      final idTpv = await widget.userPreferencesService.getIdTpv();
      final userId = userData['userId'];

      if (idTienda == null || idTpv == null || userId == null) {
        print('⚠️ Faltan datos para sincronizar órdenes');
        return [];
      }

      // Llamar al RPC listar_ordenes para obtener órdenes desde Supabase
      final response = await Supabase.instance.client.rpc(
        'listar_ordenes',
        params: {
          'con_inventario_param': false,
          'fecha_desde_param': null,
          'fecha_hasta_param': null,
          'id_estado_param': null,
          'id_tienda_param': idTienda,
          'id_tipo_operacion_param': null,
          'id_tpv_param': idTpv,
          'id_usuario_param': userId,
          'limite_param': null,
          'pagina_param': null,
          'solo_pendientes_param': false,
        },
      );

      if (response is List && response.isNotEmpty) {
        print('✅ Órdenes sincronizadas: ${response.length}');
        // Retornar la respuesta completa del RPC
        return response.cast<Map<String, dynamic>>();
      }

      return [];
    } catch (e) {
      print('Error sincronizando órdenes: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícono
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _hasError
                    ? Colors.red.withOpacity(0.1)
                    : _isCompleted
                        ? Colors.green.withOpacity(0.1)
                        : Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _hasError
                    ? Icons.error_outline
                    : _isCompleted
                        ? Icons.check_circle_outline
                        : Icons.cloud_download,
                size: 48,
                color: _hasError
                    ? Colors.red
                    : _isCompleted
                        ? Colors.green
                        : Colors.blue,
              ),
            ),
            const SizedBox(height: 24),
            
            // Título
            Text(
              _hasError
                  ? 'Error de Sincronización'
                  : _isCompleted
                      ? '¡Completado!'
                      : 'Sincronizando Datos',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Tarea actual
            Text(
              _currentTask,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            
            // Barra de progreso
            if (!_isCompleted && !_hasError) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            
            // Lista de tareas
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _tasks.asMap().entries.map((entry) {
                  final index = entry.key;
                  final task = entry.value;
                  final isCompleted = _progress > (index / _tasks.length);
                  final isCurrent = _progress > (index / _tasks.length) && 
                                   _progress <= ((index + 1) / _tasks.length);
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          isCompleted
                              ? Icons.check_circle
                              : isCurrent
                                  ? Icons.sync
                                  : Icons.circle_outlined,
                          size: 16,
                          color: isCompleted
                              ? Colors.green
                              : isCurrent
                                  ? Colors.blue
                                  : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task['name']!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isCompleted || isCurrent
                                  ? Colors.black87
                                  : Colors.grey,
                              fontWeight: isCurrent
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
