import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/permissions_service.dart';

class AdminBottomNavigation extends StatefulWidget {
  final String? currentRoute;
  final int? currentIndex;
  final Function(int)? onTap;

  const AdminBottomNavigation({
    Key? key,
    this.currentRoute,
    this.currentIndex,
    this.onTap,
  }) : super(key: key);

  @override
  State<AdminBottomNavigation> createState() => _AdminBottomNavigationState();
}

class _AdminBottomNavigationState extends State<AdminBottomNavigation> {
  final PermissionsService _permissionsService = PermissionsService();
  List<BottomNavigationBarItem> _items = [];
  List<String> _routes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNavigationItems();
  }

  Future<void> _loadNavigationItems() async {
    final userRole = await _permissionsService.getUserRole();
    final items = <BottomNavigationBarItem>[];
    final routes = <String>[];

    // Dashboard - Todos
    items.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.dashboard_outlined),
        activeIcon: Icon(Icons.dashboard),
        label: 'Dashboard',
      ),
    );
    routes.add('/dashboard');

    // Productos - Solo Gerente y Supervisor
    if (userRole == UserRole.gerente || userRole == UserRole.supervisor) {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.inventory_2_outlined),
          activeIcon: Icon(Icons.inventory_2),
          label: 'Productos',
        ),
      );
      routes.add('/products-dashboard');
    }

    // Inventario - Todos (Gerente, Supervisor, Almacenero)
    items.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.warehouse_outlined),
        activeIcon: Icon(Icons.warehouse),
        label: 'Inventario',
      ),
    );
    routes.add('/inventory');

    // Almacenes - Todos (pero almacenero solo ve el suyo)
    items.add(
      const BottomNavigationBarItem(
        icon: Icon(Icons.store_outlined),
        activeIcon: Icon(Icons.store),
        label: 'Almacenes',
      ),
    );
    routes.add('/warehouse');

    // Configuración - Solo Gerente
    if (userRole == UserRole.gerente) {
      items.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'Config',
        ),
      );
      routes.add('/settings');
    }

    setState(() {
      _items = items;
      _routes = routes;
      _isLoading = false;
    });
  }

  int _getCurrentIndex() {
    // Si se pasó currentRoute, buscar su índice
    if (widget.currentRoute != null) {
      final index = _routes.indexOf(widget.currentRoute!);
      return index >= 0 ? index : 0;
    }
    // Si se pasó currentIndex (legacy), usarlo
    if (widget.currentIndex != null) {
      return widget.currentIndex!.clamp(0, _items.length - 1);
    }
    return 0;
  }

  void _handleTap(int index) {
    // SIEMPRE usar navegación por ruta para evitar problemas con índices
    if (index >= 0 && index < _routes.length) {
      final route = _routes[index];

      // Si ya estamos en la ruta, no hacer nada
      if (widget.currentRoute == route) {
        return;
      }

      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 60,
        color: Colors.white,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _getCurrentIndex(),
        onTap: _handleTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey[600],
        selectedFontSize: 12,
        unselectedFontSize: 11,
        iconSize: 24,
        elevation: 0,
        items: _items,
      ),
    );
  }
}
