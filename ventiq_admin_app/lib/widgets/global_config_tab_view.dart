import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/store_config_service.dart';
import '../services/user_preferences_service.dart';

class GlobalConfigTabView extends StatefulWidget {
  const GlobalConfigTabView({super.key});

  @override
  State<GlobalConfigTabView> createState() => _GlobalConfigTabViewState();
}

class _GlobalConfigTabViewState extends State<GlobalConfigTabView> {
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  
  bool _isLoading = true;
  bool _needMasterPasswordToCancel = false;
  bool _needAllOrdersCompletedToContinue = false;
  int? _storeId;

  @override
  void initState() {
    super.initState();
    _loadStoreConfig();
  }

  Future<void> _loadStoreConfig() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Obtener ID de tienda desde UserPreferencesService
      _storeId = await _userPreferencesService.getIdTienda();
      
      if (_storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      print('🏪 Cargando configuración para tienda ID: $_storeId');

      // Obtener configuración de la tienda
      final config = await StoreConfigService.getStoreConfig(_storeId!);
      
      setState(() {
        _needMasterPasswordToCancel = config['need_master_password_to_cancel'] ?? false;
        _needAllOrdersCompletedToContinue = config['need_all_orders_completed_to_continue'] ?? false;
        _isLoading = false;
      });

      print('✅ Configuración cargada:');
      print('  - Contraseña maestra para cancelar: $_needMasterPasswordToCancel');
      print('  - Completar todas las órdenes: $_needAllOrdersCompletedToContinue');

    } catch (e) {
      print('❌ Error al cargar configuración de tienda: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar configuración: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateMasterPasswordSetting(bool value) async {
    if (_storeId == null) return;

    try {
      print('🔧 Actualizando configuración de contraseña maestra: $value');
      
      await StoreConfigService.updateNeedMasterPasswordToCancel(_storeId!, value);
      
      setState(() {
        _needMasterPasswordToCancel = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value 
                ? 'Contraseña maestra activada para cancelar órdenes'
                : 'Contraseña maestra desactivada para cancelar órdenes'
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ Configuración de contraseña maestra actualizada');
    } catch (e) {
      print('❌ Error al actualizar configuración de contraseña maestra: $e');
      
      // Revertir el cambio en caso de error
      setState(() {
        _needMasterPasswordToCancel = !value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar configuración: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateOrdersCompletionSetting(bool value) async {
    if (_storeId == null) return;

    try {
      print('🔧 Actualizando configuración de órdenes completadas: $value');
      
      await StoreConfigService.updateNeedAllOrdersCompletedToContinue(_storeId!, value);
      
      setState(() {
        _needAllOrdersCompletedToContinue = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value 
                ? 'Ahora se requiere completar todas las órdenes antes de continuar'
                : 'Ya no se requiere completar todas las órdenes antes de continuar'
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ Configuración de órdenes completadas actualizada');
    } catch (e) {
      print('❌ Error al actualizar configuración de órdenes completadas: $e');
      
      // Revertir el cambio en caso de error
      setState(() {
        _needAllOrdersCompletedToContinue = !value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar configuración: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Cargando configuración global...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          

          const SizedBox(height: 24),

          // Configuración de Contraseña Maestra
          _buildConfigCard(
            icon: Icons.lock_outline,
            iconColor: Colors.orange,
            title: 'Contraseña Maestra para Cancelar',
            subtitle: _needMasterPasswordToCancel
                ? 'Los vendedores necesitan contraseña maestra para cancelar órdenes'
                : 'Los vendedores pueden cancelar órdenes sin contraseña maestra',
            value: _needMasterPasswordToCancel,
            onChanged: _updateMasterPasswordSetting,
          ),

          const SizedBox(height: 16),

          // Configuración de Órdenes Completadas
          _buildConfigCard(
            icon: Icons.check_circle_outline,
            iconColor: Colors.green,
            title: 'Completar Todas las Órdenes',
            subtitle: _needAllOrdersCompletedToContinue
                ? 'Los vendedores deben completar todas las órdenes antes de crear una nueva'
                : 'Los vendedores pueden crear nuevas órdenes sin completar las pendientes',
            value: _needAllOrdersCompletedToContinue,
            onChanged: _updateOrdersCompletionSetting,
          ),

          const SizedBox(height: 24),

          // Información adicional
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Información',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Estas configuraciones afectan el comportamiento de la aplicación de vendedores (VentIQ Seller App). Los cambios se aplicarán inmediatamente para todos los usuarios.',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icono
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Contenido
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Switch
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.3),
          ),
        ],
      ),
    );
  }
}
