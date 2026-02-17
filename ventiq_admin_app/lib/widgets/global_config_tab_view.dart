import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/store_config_service.dart';
import '../services/user_preferences_service.dart';
import '../services/subscription_service.dart';
import '../models/subscription.dart';
import '../screens/subscription_detail_screen.dart';
import '../utils/navigation_guard.dart';

class GlobalConfigTabView extends StatefulWidget {
  const GlobalConfigTabView({super.key});

  @override
  State<GlobalConfigTabView> createState() => _GlobalConfigTabViewState();
}

class _GlobalConfigTabViewState extends State<GlobalConfigTabView> {
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  final TextEditingController _masterPasswordController =
      TextEditingController();

  bool _isLoading = true;
  bool _needMasterPasswordToCancel = false;
  bool _needAllOrdersCompletedToContinue = false;
  bool _manejaInventario = false;
  bool _permiteVenderAunSinDisponibilidad = false;
  bool _noSolicitarCliente = false;
  bool _allowDiscountOnVendedor = false;
  bool _allowPrintPending = false;
  String _metodoRedondeoPrecioVenta = 'NO_REDONDEAR';
  bool _hasMasterPassword = false;
  bool _showMasterPasswordField = false;
  bool _obscureMasterPassword = true;
  bool _showDescriptionInSelectors = false;
  int? _storeId;
  String? _storeName;

  // Variables para suscripción
  Subscription? _activeSubscription;

  static const List<_RoundingMethodOption> _roundingOptions = [
    _RoundingMethodOption(
      value: 'NO_REDONDEAR',
      title: 'No redondear',
      description:
          'Mantiene el precio exacto sin cambios (ej. 12.45 -> 12.45).',
    ),
    _RoundingMethodOption(
      value: 'REDONDEAR_POR_DEFECTO',
      title: 'Redondeo normal',
      description: 'Redondea al entero mas cercano (12.40 -> 12, 12.50 -> 13).',
    ),
    _RoundingMethodOption(
      value: 'REDONDEAR_POR_EXCESO',
      title: 'Redondeo por exceso',
      description:
          'Siempre redondea hacia arriba al entero siguiente (12.01 -> 13).',
    ),
    _RoundingMethodOption(
      value: 'REDONDEAR_A_MULT_5_POR_DEFECTO',
      title: 'Multiplo de 5 (normal)',
      description:
          'Redondea al multiplo de 5 mas cercano (12.4 -> 10, 12.6 -> 15).',
    ),
    _RoundingMethodOption(
      value: 'REDONDEAR_A_MULT_5_POR_EXCESO',
      title: 'Multiplo de 5 (por exceso)',
      description:
          'Redondea hacia arriba al siguiente multiplo de 5 (12 -> 15).',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadStoreConfig();
  }

  _RoundingMethodOption _getRoundingOption(String value) {
    return _roundingOptions.firstWhere(
      (option) => option.value == value,
      orElse: () => _roundingOptions.first,
    );
  }

  Future<void> _updateRoundingMethodSetting(String value) async {
    if (_storeId == null || _metodoRedondeoPrecioVenta == value) return;

    final previousValue = _metodoRedondeoPrecioVenta;
    final selectedOption = _getRoundingOption(value);

    try {
      print('🔧 Actualizando metodo de redondeo: $value');

      await StoreConfigService.updateMetodoRedondeoPrecioVenta(
        _storeId!,
        value,
      );

      setState(() {
        _metodoRedondeoPrecioVenta = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Metodo de redondeo actualizado: ${selectedOption.title}',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ Metodo de redondeo actualizado');
    } catch (e) {
      print('❌ Error al actualizar metodo de redondeo: $e');

      setState(() {
        _metodoRedondeoPrecioVenta = previousValue;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar configuracion: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateAllowPrintPendingSetting(bool value) async {
    if (_storeId == null) return;

    try {
      print(
        '🔧 Actualizando configuración permitir_imprimir_pendientes: $value',
      );

      await StoreConfigService.updateAllowPrintPending(_storeId!, value);

      setState(() {
        _allowPrintPending = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Ahora puedes imprimir órdenes pendientes'
                  : 'La impresión de órdenes pendientes se ha desactivado',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ permitir_imprimir_pendientes actualizado');
    } catch (e) {
      print('❌ Error al actualizar permitir_imprimir_pendientes: $e');

      setState(() {
        _allowPrintPending = !value;
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

      // Obtener información de la tienda actual
      final storeInfo = await _userPreferencesService.getCurrentStoreInfo();
      _storeName = storeInfo?['denominacion'] ?? 'Tienda Desconocida';

      print(
        '🏪 Cargando configuración para tienda ID: $_storeId - Nombre: $_storeName',
      );

      // Obtener configuración de la tienda
      final config = await StoreConfigService.getStoreConfig(_storeId!);

      // Verificar si existe master password
      final hasMasterPassword = await StoreConfigService.hasMasterPassword(
        _storeId!,
      );

      // Cargar configuración de UI desde preferencias locales
      final showDescriptionInSelectors =
          await _userPreferencesService.getShowDescriptionInSelectors();

      setState(() {
        _needMasterPasswordToCancel =
            config['need_master_password_to_cancel'] ?? false;
        _needAllOrdersCompletedToContinue =
            config['need_all_orders_completed_to_continue'] ?? false;
        _manejaInventario = config['maneja_inventario'] ?? false;
        _permiteVenderAunSinDisponibilidad =
            config['permite_vender_aun_sin_disponibilidad'] ?? false;
        _noSolicitarCliente = config['no_solicitar_cliente'] ?? false;
        _allowDiscountOnVendedor =
            config['allow_discount_on_vendedor'] ?? false;
        _allowPrintPending = config['permitir_imprimir_pendientes'] ?? false;
        _metodoRedondeoPrecioVenta =
            config['metodo_redondeo_precio_venta'] ?? 'NO_REDONDEAR';
        _hasMasterPassword = hasMasterPassword;
        _showMasterPasswordField = _needMasterPasswordToCancel;
        _showDescriptionInSelectors = showDescriptionInSelectors;
        _isLoading = false;
      });

      // Cargar suscripción actual (activa o vencida)
      _activeSubscription = await _subscriptionService.getCurrentSubscription(
        _storeId!,
      );

      if (_activeSubscription != null) {
        print('🔍 Suscripción encontrada:');
        print('  - ID: ${_activeSubscription!.id}');
        print('  - Plan: ${_activeSubscription!.planDenominacion}');
        print('  - Estado: ${_activeSubscription!.estadoText}');
        print('  - Activa: ${_activeSubscription!.isActive}');
        print('  - Vencida: ${_activeSubscription!.isExpired}');
        if (_activeSubscription!.fechaFin != null) {
          print('  - Fecha fin: ${_activeSubscription!.fechaFin}');
        }
      } else {
        print('⚠️ No se encontró suscripción para la tienda $_storeId');
      }

      print('✅ Configuración cargada:');
      print(
        '  - Contraseña maestra para cancelar: $_needMasterPasswordToCancel',
      );
      print(
        '  - Completar todas las órdenes: $_needAllOrdersCompletedToContinue',
      );
      print('  - Maneja inventario: $_manejaInventario');
      print(
        '  - Permite vender sin disponibilidad: $_permiteVenderAunSinDisponibilidad',
      );
      print('  - No solicitar cliente en venta: $_noSolicitarCliente');
      print(
        '  - Permitir descuentos manuales (vendedor): $_allowDiscountOnVendedor',
      );
      print('  - Metodo redondeo precio venta: $_metodoRedondeoPrecioVenta');
      print('  - Tiene contraseña maestra: $_hasMasterPassword');
      print(
        '  - Mostrar descripción en selectores: $_showDescriptionInSelectors',
      );
      print(
        '  - Suscripción actual: ${_activeSubscription?.planDenominacion ?? 'No encontrada'} (${_activeSubscription?.estadoText ?? 'N/A'})',
      );

      // Actualizar UI después de cargar la suscripción
      if (mounted) {
        setState(() {});
      }
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

  Future<void> _updateAllowDiscountOnVendedorSetting(bool value) async {
    if (_storeId == null) return;

    try {
      print(
        '🔧 Actualizando configuración de permitir descuentos manuales: $value',
      );

      await StoreConfigService.updateAllowDiscountOnVendedor(_storeId!, value);

      setState(() {
        _allowDiscountOnVendedor = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Los vendedores ahora pueden aplicar descuentos manuales'
                  : 'Los vendedores ya no pueden aplicar descuentos manuales',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ Configuración de permitir descuentos manuales actualizada');
    } catch (e) {
      print(
        '❌ Error al actualizar configuración de permitir descuentos manuales: $e',
      );

      setState(() {
        _allowDiscountOnVendedor = !value;
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

  Future<void> _updateMasterPasswordSetting(bool value) async {
    if (_storeId == null) return;

    try {
      print('🔧 Actualizando configuración de contraseña maestra: $value');

      await StoreConfigService.updateNeedMasterPasswordToCancel(
        _storeId!,
        value,
      );

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
                  : 'Contraseña maestra desactivada para cancelar órdenes',
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

      await StoreConfigService.updateNeedAllOrdersCompletedToContinue(
        _storeId!,
        value,
      );

      setState(() {
        _needAllOrdersCompletedToContinue = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Ahora se requiere completar todas las órdenes antes de continuar'
                  : 'Ya no se requiere completar todas las órdenes antes de continuar',
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
                  : 'Control de inventario desactivado - Los vendedores no harán control al abrir/cerrar turno',
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

  Future<void> _updateElaboratedProductsSetting(bool value) async {
    if (_storeId == null) return;

    // Mostrar diálogo de advertencia si se está activando
    if (value) {
      final confirmed = await _showElaboratedProductsWarning();
      if (!confirmed) return;
    }

    try {
      print(
        '🔧 Actualizando configuración de productos elaborados sin disponibilidad: $value',
      );

      await StoreConfigService.updatePermiteVenderAunSinDisponibilidad(
        _storeId!,
        value,
      );

      setState(() {
        _permiteVenderAunSinDisponibilidad = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? '⚠️ Los vendedores ahora pueden vender productos elaborados sin verificar ingredientes'
                  : '✅ Los vendedores deben verificar ingredientes antes de vender productos elaborados',
            ),
            backgroundColor: value ? Colors.orange : AppColors.success,
          ),
        );
      }

      print('✅ Configuración de productos elaborados actualizada');
    } catch (e) {
      print('❌ Error al actualizar configuración de productos elaborados: $e');

      // Revertir el cambio en caso de error
      setState(() {
        _permiteVenderAunSinDisponibilidad = !value;
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

  Future<void> _updateNoSolicitarClienteSetting(bool value) async {
    if (_storeId == null) return;

    try {
      print('🔧 Actualizando configuración de no solicitar cliente: $value');

      await StoreConfigService.updateNoSolicitarCliente(_storeId!, value);

      setState(() {
        _noSolicitarCliente = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'No se solicitarán datos del comprador en ventas - Se usará "Cliente" automáticamente'
                  : 'Se solicitarán datos del comprador en ventas',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ Configuración de no solicitar cliente actualizada');
    } catch (e) {
      print('❌ Error al actualizar configuración de no solicitar cliente: $e');

      // Revertir el cambio en caso de error
      setState(() {
        _noSolicitarCliente = !value;
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

  Future<bool> _showElaboratedProductsWarning() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Advertencia Importante',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
              content: Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🍽️ Productos sin Verificación de Disponibilidad',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Al activar esta opción:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildWarningPoint(
                            'Los vendedores podrán vender productos sin verificar si hay ingredientes o cantidad suficientes',
                          ),
                          const SizedBox(height: 8),
                          _buildWarningPoint(
                            'Esto puede resultar en ventas de productos que no se pueden preparar',
                          ),
                          const SizedBox(height: 8),
                          _buildWarningPoint(
                            'Podrías tener problemas de inventario y clientes insatisfechos',
                          ),
                          const SizedBox(height: 8),
                          _buildWarningPoint(
                            'Solo activa esta opción si confías completamente en el control manual de tus vendedores',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Recomendación: Mantén esta opción desactivada para un mejor control de inventario',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Activar de todos modos'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Widget _buildWarningPoint(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }

  Future<void> _updateShowDescriptionSetting(bool value) async {
    try {
      print(
        '🔧 Actualizando configuración de mostrar descripción en selectores: $value',
      );

      await _userPreferencesService.setShowDescriptionInSelectors(value);

      setState(() {
        _showDescriptionInSelectors = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Ahora se mostrarán las descripciones en los selectores de productos'
                  : 'Las descripciones en los selectores de productos están ocultas',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }

      print('✅ Configuración de mostrar descripción actualizada');
    } catch (e) {
      print('❌ Error al actualizar configuración de mostrar descripción: $e');

      // Revertir el cambio en caso de error
      setState(() {
        _showDescriptionInSelectors = !value;
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
              style: TextStyle(fontSize: 16, color: Colors.grey),
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
          // Detalles de la Tienda Activa
          _buildStoreDetailsCard(),
          const SizedBox(height: 24),

          // Sección de Suscripción
          if (_activeSubscription != null) ...[
            _buildSubscriptionCard(),
            const SizedBox(height: 24),
          ],

          const SizedBox(height: 24),

          // Configuración de Contraseña Maestra
          _buildConfigCard(
            icon: Icons.lock_outline,
            iconColor: Colors.orange,
            title: 'Contraseña Maestra para Cancelar',
            subtitle:
                _needMasterPasswordToCancel
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
            subtitle:
                _needAllOrdersCompletedToContinue
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
            subtitle:
                _manejaInventario
                    ? 'Los vendedores deben hacer control de inventario al abrir y cerrar turno'
                    : 'Los vendedores no hacen control de inventario al abrir y cerrar turno',
            value: _manejaInventario,
            onChanged: _updateInventoryManagementSetting,
          ),

          const SizedBox(height: 16),

          // Configuración de Productos Elaborados sin Disponibilidad
          _buildConfigCard(
            icon: Icons.restaurant_menu,
            iconColor: Colors.deepOrange,
            title: 'Venta de Productos Sin Disponibilidad',
            subtitle:
                _permiteVenderAunSinDisponibilidad
                    ? '⚠️ Los vendedores pueden vender productos sin verificar ingredientes disponibles'
                    : '✅ Los vendedores deben verificar ingredientes antes de vender productos',
            value: _permiteVenderAunSinDisponibilidad,
            onChanged: _updateElaboratedProductsSetting,
          ),

          const SizedBox(height: 16),

          // Configuración de Mostrar Descripción en Selectores
          _buildConfigCard(
            icon: Icons.description_outlined,
            iconColor: Colors.purple,
            title: 'Mostrar Descripción en Selectores',
            subtitle:
                _showDescriptionInSelectors
                    ? 'Las descripciones de productos se muestran en los selectores para facilitar la identificación'
                    : 'Solo se muestra el nombre del producto en los selectores (vista compacta)',
            value: _showDescriptionInSelectors,
            onChanged: _updateShowDescriptionSetting,
          ),

          const SizedBox(height: 16),

          // Configuración de No Pedir Datos en Venta
          _buildConfigCard(
            icon: Icons.person_off_outlined,
            iconColor: Colors.teal,
            title: 'No Pedir Datos en Venta',
            subtitle:
                _noSolicitarCliente
                    ? '✅ No se solicitan datos del comprador - Se usa "Cliente" automáticamente'
                    : '📋 Se solicitan datos del comprador (nombre, teléfono, contactos adicionales)',
            value: _noSolicitarCliente,
            onChanged: _updateNoSolicitarClienteSetting,
          ),

          const SizedBox(height: 16),

          _buildConfigCard(
            icon: Icons.percent,
            iconColor: Colors.indigo,
            title: 'Permitir Descuentos Manuales',
            subtitle:
                _allowDiscountOnVendedor
                    ? '✅ Los vendedores pueden aplicar descuentos manuales a una orden'
                    : '🔒 Los vendedores no pueden aplicar descuentos manuales (solo precios configurados)',
            value: _allowDiscountOnVendedor,
            onChanged: _updateAllowDiscountOnVendedorSetting,
          ),

          const SizedBox(height: 16),

          _buildRoundingMethodCard(),

          const SizedBox(height: 16),

          // Configuración de imprimir órdenes pendientes
          _buildConfigCard(
            icon: Icons.print_outlined,
            iconColor: Colors.orange,
            title: 'Imprimir Órdenes Pendientes',
            subtitle:
                _allowPrintPending
                    ? '✅ Si la tienda lo permite, se pueden imprimir órdenes pendientes'
                    : '🔒 Solo se imprimen órdenes pagadas o completadas',
            value: _allowPrintPending,
            onChanged: _updateAllowPrintPendingSetting,
          ),

          const SizedBox(height: 24),

          // Sección de Impresoras WiFi
          _buildWiFiPrintersSection(),

          const SizedBox(height: 24),

          // Información adicional
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
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
                  'Estas configuraciones afectan el comportamiento de la aplicación de vendedores (Inventtia App). Los cambios se aplicarán inmediatamente para todos los usuarios. La configuración de "Mostrar Descripción en Selectores" es una preferencia local que se guarda en este dispositivo.',
                  style: TextStyle(color: Colors.blue, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundingMethodCard() {
    final selectedOption = _getRoundingOption(_metodoRedondeoPrecioVenta);

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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.rounded_corner,
                  color: Colors.green,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Metodo de redondeo de precios',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Define como se ajusta el precio de venta al guardar.',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _metodoRedondeoPrecioVenta,
            items:
                _roundingOptions
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option.value,
                        child: Text(option.title),
                      ),
                    )
                    .toList(),
            onChanged: (value) {
              if (value != null) {
                _updateRoundingMethodSetting(value);
              }
            },
            decoration: InputDecoration(
              labelText: 'Metodo seleccionado',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child: Text(
              'Actual: ${selectedOption.title}. ${selectedOption.description}',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 12),
          ..._roundingOptions.map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${option.title}: ${option.description}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _buildStoreDetailsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90E2).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.store,
                  color: Color(0xFF4A90E2),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tienda Activa',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _storeName ?? 'Cargando...',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Color(0xFF4A90E2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ID: $_storeId',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF4A90E2),
                      fontWeight: FontWeight.w500,
                    ),
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
            child: Icon(icon, color: iconColor, size: 24),
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
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
                    hintText:
                        _hasMasterPassword
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
                child: Text(_hasMasterPassword ? 'Cambiar' : 'Establecer'),
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
                      style: TextStyle(color: Colors.green, fontSize: 12),
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

  Widget _buildWiFiPrintersSection() {
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.wifi,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Impresoras WiFi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Gestionar impresoras de red',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, '/wifi-printers');
                },
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Configurar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configura y gestiona las impresoras WiFi para imprimir documentos de inventario',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final subscription = _activeSubscription!;
    final isExpiringSoon =
        subscription.diasRestantes > 0 && subscription.diasRestantes <= 7;
    final isExpired = subscription.isExpired;

    Color statusColor = AppColors.success;
    if (isExpired) {
      statusColor = AppColors.error;
    } else if (isExpiringSoon) {
      statusColor = AppColors.warning;
    }

    return GestureDetector(
      onTap: () async {
        final canNavigate = await NavigationGuard.canNavigate(
          '/subscription-detail',
          context,
        );
        if (canNavigate) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SubscriptionDetailScreen(),
            ),
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.1),
              AppColors.primary.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con icono y título
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.workspace_premium,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan de Suscripción',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        subscription.planDenominacion ?? 'Plan desconocido',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    subscription.estadoText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Información del plan
            Row(
              children: [
                Expanded(
                  child: _buildSubscriptionInfo(
                    'Precio',
                    subscription.planPrecioMensual != null
                        ? '\$${subscription.planPrecioMensual!.toStringAsFixed(2)}/mes'
                        : 'N/A',
                    Icons.attach_money,
                  ),
                ),
                Expanded(
                  child: _buildSubscriptionInfo(
                    'Inicio',
                    DateFormat('dd/MM/yyyy').format(subscription.fechaInicio),
                    Icons.calendar_today,
                  ),
                ),
              ],
            ),

            if (subscription.fechaFin != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildSubscriptionInfo(
                      'Vencimiento',
                      DateFormat('dd/MM/yyyy').format(subscription.fechaFin!),
                      Icons.event,
                      isExpiringSoon || isExpired ? statusColor : null,
                    ),
                  ),
                  if (subscription.diasRestantes > 0)
                    Expanded(
                      child: _buildSubscriptionInfo(
                        'Días restantes',
                        '${subscription.diasRestantes} días',
                        Icons.hourglass_empty,
                        isExpiringSoon ? statusColor : AppColors.success,
                      ),
                    ),
                ],
              ),
            ],

            // Advertencia si está por vencer o vencida
            if (isExpiringSoon || isExpired) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isExpired ? Icons.error : Icons.warning,
                      color: statusColor,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isExpired
                            ? 'Tu suscripción ha vencido. Contacta al administrador para renovar.'
                            : 'Tu suscripción vence pronto. Contacta al administrador para renovar.',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Botón para ver detalles
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SubscriptionDetailScreen(),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.arrow_forward,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  label: Text(
                    'Ver detalles',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionInfo(
    String label,
    String value,
    IconData icon, [
    Color? color,
  ]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color ?? AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _RoundingMethodOption {
  const _RoundingMethodOption({
    required this.value,
    required this.title,
    required this.description,
  });

  final String value;
  final String title;
  final String description;
}
