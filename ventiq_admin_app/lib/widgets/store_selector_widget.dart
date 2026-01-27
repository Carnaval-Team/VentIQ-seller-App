import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/permissions_service.dart';
import '../services/store_selector_service.dart';
import '../services/user_preferences_service.dart';

class StoreSelectorWidget extends StatefulWidget {
  final bool showLabel;
  final bool isCompact;

  const StoreSelectorWidget({
    super.key,
    this.showLabel = true,
    this.isCompact = false,
  });

  @override
  State<StoreSelectorWidget> createState() => _StoreSelectorWidgetState();
}

class _StoreSelectorWidgetState extends State<StoreSelectorWidget> {
  late StoreSelectorService _storeService;

  @override
  void initState() {
    super.initState();
    _storeService = StoreSelectorService();
    _storeService.addListener(_onStoreServiceChanged);
    _storeService.initialize();
  }

  @override
  void dispose() {
    _storeService.removeListener(_onStoreServiceChanged);
    super.dispose();
  }

  void _onStoreServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // No mostrar si solo hay una tienda
    if (!_storeService.hasMultipleStores) {
      return const SizedBox.shrink();
    }

    if (_storeService.isLoading) {
      return _buildLoadingIndicator();
    }

    if (_storeService.userStores.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildSelector(context, _storeService);
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.isCompact ? Colors.white : AppColors.primary,
              ),
            ),
          ),
          if (widget.showLabel && !widget.isCompact) ...[
            const SizedBox(width: 8),
            Text(
              'Cargando...',
              style: TextStyle(
                fontSize: 12,
                color: widget.isCompact ? Colors.white70 : Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelector(
    BuildContext context,
    StoreSelectorService storeService,
  ) {
    final selectedStore = storeService.selectedStore;

    if (widget.isCompact) {
      return _buildCompactSelector(context, storeService, selectedStore);
    }

    return _buildFullSelector(context, storeService, selectedStore);
  }

  Widget _buildCompactSelector(
    BuildContext context,
    StoreSelectorService storeService,
    Store? selectedStore,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Store>(
          value: selectedStore,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white,
            size: 18,
          ),
          dropdownColor: Colors.white,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items:
              storeService.userStores.map((Store store) {
                return DropdownMenuItem<Store>(
                  value: store,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          store.denominacion,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
          onChanged: (Store? newStore) {
            if (newStore != null) {
              storeService.selectStore(newStore);
            }
          },
        ),
      ),
    );
  }

  Widget _buildFullSelector(
    BuildContext context,
    StoreSelectorService storeService,
    Store? selectedStore,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showLabel) ...[
            Row(
              children: [
                Icon(Icons.store, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Tienda Seleccionada',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          DropdownButtonFormField<Store>(
            value: selectedStore,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
            items:
                storeService.userStores.map((Store store) {
                  return DropdownMenuItem<Store>(
                    value: store,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.store,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                store.denominacion,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (store.direccion != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  store.direccion!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
            onChanged: (Store? newStore) {
              if (newStore != null) {
                storeService.selectStore(newStore);

                // Mostrar confirmación
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Cambiado a: ${newStore.denominacion}'),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Widget especializado para usar en AppBar
class AppBarStoreSelectorWidget extends StatefulWidget {
  const AppBarStoreSelectorWidget({super.key});

  @override
  State<AppBarStoreSelectorWidget> createState() =>
      _AppBarStoreSelectorWidgetState();
}

class _AppBarStoreSelectorWidgetState extends State<AppBarStoreSelectorWidget> {
  late StoreSelectorService _storeService;
  final PermissionsService _permissionsService = PermissionsService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  @override
  void initState() {
    super.initState();
    _storeService = StoreSelectorService();
    _storeService.addListener(_onStoreServiceChanged);
    _storeService.initialize();
  }

  @override
  void dispose() {
    _storeService.removeListener(_onStoreServiceChanged);
    super.dispose();
  }

  void _onStoreServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showStoreSelectionDialog() async {
    final storeService = _storeService;

    if (storeService.userStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay tiendas disponibles'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedStore = await showDialog<Store>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.store, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Seleccionar Tienda'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<Map<int, UserRole>>(
              future: _permissionsService.getUserRolesByStore(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rolesByStore = snapshot.data ?? {};
                final currentStoreId = storeService.selectedStore?.id;

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: storeService.userStores.length,
                  itemBuilder: (context, index) {
                    final store = storeService.userStores[index];
                    final isCurrentStore = store.id == currentStoreId;
                    final userRole = rolesByStore[store.id] ?? UserRole.none;
                    final roleName = _permissionsService.getRoleName(userRole);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            isCurrentStore
                                ? AppColors.primary
                                : AppColors.primary.withOpacity(0.1),
                        child: Icon(
                          Icons.store,
                          color:
                              isCurrentStore ? Colors.white : AppColors.primary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        store.denominacion,
                        style: TextStyle(
                          fontWeight:
                              isCurrentStore
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                          color: isCurrentStore ? AppColors.primary : null,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ID: ${store.id}'),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getRoleColor(userRole).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Rol: $roleName',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _getRoleColor(userRole),
                              ),
                            ),
                          ),
                        ],
                      ),
                      trailing:
                          isCurrentStore
                              ? const Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                              )
                              : null,
                      onTap: () {
                        Navigator.of(context).pop(store);
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (selectedStore != null &&
        selectedStore.id != storeService.selectedStore?.id) {
      await _switchStore(selectedStore);
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.gerente:
        return Colors.green;
      case UserRole.supervisor:
        return Colors.blue;
      case UserRole.auditor:
        return Colors.teal;
      case UserRole.almacenero:
        return Colors.orange;
      case UserRole.vendedor:
        return Colors.purple;
      case UserRole.none:
        return Colors.grey;
    }
  }

  Future<void> _switchStore(Store store) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Cambiando tienda...'),
                ],
              ),
            ),
      );

      _permissionsService.clearAllCache();
      print('🧹 TODO el caché de roles limpiado al cambiar de tienda');

      await _storeService.selectStore(store);

      final userRole = await _permissionsService.getUserRoleForStore(store.id);
      print(
        '🔄 Rol obtenido para tienda ${store.id}: ${_permissionsService.getRoleName(userRole)}',
      );

      final rolesByStore = await _userPreferencesService.getUserRolesByStore();
      rolesByStore[store.id] =
          _permissionsService.getRoleName(userRole).toLowerCase();
      await _userPreferencesService.saveUserRolesByStore(rolesByStore);
      print(
        '💾 Rol guardado para tienda ${store.id}: ${rolesByStore[store.id]}',
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cambiado a: ${store.denominacion}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error switching store: $e');

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cambiar tienda'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeService = _storeService;

    // No mostrar si solo hay una tienda
    if (!storeService.hasMultipleStores) {
      return const SizedBox.shrink();
    }

    if (storeService.isLoading) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    final selectedStore = storeService.selectedStore;
    if (selectedStore == null) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.store, color: Colors.white),
      onPressed: _showStoreSelectionDialog,
      tooltip: 'Seleccionar Tienda: ${selectedStore.denominacion}',
    );
  }
}
