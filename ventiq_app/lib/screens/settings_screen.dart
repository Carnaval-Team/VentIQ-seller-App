import 'package:flutter/material.dart';
import '../services/order_service.dart';
import '../services/user_preferences_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final printEnabled = await _userPreferencesService.isPrintEnabled();
    final limitDataEnabled = await _userPreferencesService.isLimitDataUsageEnabled();
    setState(() {
      _isPrintEnabled = printEnabled;
      _isLimitDataUsageEnabled = limitDataEnabled;
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
