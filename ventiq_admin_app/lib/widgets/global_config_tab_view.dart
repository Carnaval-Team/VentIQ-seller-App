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
  final TextEditingController _masterPasswordController = TextEditingController();
  
  bool _isLoading = true;
  bool _needMasterPasswordToCancel = false;
  bool _needAllOrdersCompletedToContinue = false;
  bool _manejaInventario = false;
  bool _hasMasterPassword = false;
  bool _showMasterPasswordField = false;
  bool _obscureMasterPassword = true;
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
      
      // Verificar si existe master password
      final hasMasterPassword = await StoreConfigService.hasMasterPassword(_storeId!);
      
      setState(() {
        _needMasterPasswordToCancel = config['need_master_password_to_cancel'] ?? false;
        _needAllOrdersCompletedToContinue = config['need_all_orders_completed_to_continue'] ?? false;
        _manejaInventario = config['maneja_inventario'] ?? false;
        _hasMasterPassword = hasMasterPassword;
        _showMasterPasswordField = _needMasterPasswordToCancel;
        _isLoading = false;
      });

      print('✅ Configuración cargada:');
      print('  - Contraseña maestra para cancelar: $_needMasterPasswordToCancel');
      print('  - Completar todas las órdenes: $_needAllOrdersCompletedToContinue');
      print('  - Maneja inventario: $_manejaInventario');
      print('  - Tiene contraseña maestra: $_hasMasterPassword');

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
        _showMasterPasswordField = value;
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

  Future<void> _updateInventoryManagementSetting(bool value) async {
    if (_storeId == null) return;

    try {
      print('🔧 Actualizando configuración de manejo de inventario: $value');
      
      await StoreConfigService.updateManejaInventario(_storeId!, value);
      
      setState(() {
        _manejaInventario = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value 
                ? 'Control de inventario activado - Los vendedores deberán hacer control al abrir/cerrar turno'
                : 'Control de inventario desactivado - Los vendedores no harán control al abrir/cerrar turno'
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ Configuración de manejo de inventario actualizada');
    } catch (e) {
      print('❌ Error al actualizar configuración de manejo de inventario: $e');
      
      // Revertir el cambio en caso de error
      setState(() {
        _manejaInventario = !value;
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

  Future<void> _updateMasterPassword() async {
    if (_storeId == null) return;

    final password = _masterPasswordController.text.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa una contraseña'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      print('🔧 Actualizando contraseña maestra...');
      
      await StoreConfigService.updateMasterPassword(_storeId!, password);
      
      setState(() {
        _hasMasterPassword = true;
      });

      // Limpiar el campo
      _masterPasswordController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contraseña maestra actualizada exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ Contraseña maestra actualizada');
    } catch (e) {
      print('❌ Error al actualizar contraseña maestra: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar contraseña: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _masterPasswordController.dispose();
    super.dispose();
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

          // Campo de Contraseña Maestra (solo visible si está activado)
          if (_showMasterPasswordField) ...[
            const SizedBox(height: 16),
            _buildMasterPasswordField(),
          ],

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

          const SizedBox(height: 16),

          // Configuración de Control de Inventario
          _buildConfigCard(
            icon: Icons.inventory_2_outlined,
            iconColor: Colors.blue,
            title: 'Control de Inventario en Turnos',
            subtitle: _manejaInventario
                ? 'Los vendedores deben hacer control de inventario al abrir y cerrar turno'
                : 'Los vendedores no hacen control de inventario al abrir y cerrar turno',
            value: _manejaInventario,
            onChanged: _updateInventoryManagementSetting,
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

  Widget _buildMasterPasswordField() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del campo
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.vpn_key,
                  color: Colors.purple,
                  size: 24,
                ),
              ),
              
              const SizedBox(width: 16),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contraseña Maestra',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hasMasterPassword 
                          ? 'Contraseña configurada - Ingresa una nueva para cambiarla'
                          : 'Establece la contraseña maestra para cancelar órdenes',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Campo de texto para la contraseña
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _masterPasswordController,
                  obscureText: _obscureMasterPassword,
                  decoration: InputDecoration(
                    hintText: _hasMasterPassword 
                        ? 'Nueva contraseña maestra'
                        : 'Contraseña maestra',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureMasterPassword 
                            ? Icons.visibility 
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureMasterPassword = !_obscureMasterPassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Botón para guardar
              ElevatedButton(
                onPressed: _updateMasterPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _hasMasterPassword ? 'Cambiar' : 'Establecer',
                ),
              ),
            ],
          ),
          
          // Información adicional
          if (_hasMasterPassword) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Contraseña maestra configurada correctamente',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
