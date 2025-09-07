import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import 'inventory_reception_screen.dart';
import 'inventory_operations_screen.dart';
import 'inventory_warehouse_screen.dart';
import 'inventory_stock_screen.dart';
import 'inventory_transfer_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {}); // Rebuild to update FAB
  }

  void _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Simular carga inicial si es necesaria
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar datos iniciales: $e';
      });
    }
  }

  void _showFabOptions() {
    final currentTab = _tabController.index;

    if (currentTab == 0) {
      // Stock tab - show reception option
      _navigateToReception();
    } else if (currentTab == 1) {
      // Warehouse tab - show transfer option
      _navigateToTransfer();
    }
  }

  void _navigateToReception() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const InventoryReceptionScreen()),
    );
  }

  void _navigateToTransfer() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const InventoryTransferScreen()),
    );
  }

  Widget? _buildFloatingActionButton() {
    final currentTab = _tabController.index;

    // Only show FAB for Stock (0) and Warehouse (1) tabs
    if (currentTab == 0 || currentTab == 1) {
      IconData icon;
      String tooltip;
      Color backgroundColor;

      if (currentTab == 0) {
        // Stock tab - Reception
        icon = Icons.input;
        tooltip = 'Registrar Recepción';
        backgroundColor = const Color(0xFF10B981); // Green
      } else {
        // Warehouse tab - Transfer
        icon = Icons.swap_horiz;
        tooltip = 'Registrar Transferencia';
        backgroundColor = const Color(0xFF4A90E2); // Blue
      }

      return FloatingActionButton(
        onPressed: _showFabOptions,
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        tooltip: tooltip,
        child: Icon(icon),
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Control de Inventario',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Stock', icon: Icon(Icons.inventory_2, size: 18)),
            Tab(text: 'Almacenes', icon: Icon(Icons.warehouse, size: 18)),
            Tab(text: 'Movimientos', icon: Icon(Icons.swap_horiz, size: 18)),
            Tab(text: 'ABC', icon: Icon(Icons.analytics, size: 18)),
          ],
        ),
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
              : _errorMessage.isNotEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadInitialData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
              : TabBarView(
                controller: _tabController,
                children: [
                  const InventoryStockScreen(),
                  const InventoryWarehouseScreen(),
                  const InventoryOperationsScreen(),
                  const Center(
                    child: Text(
                      'Clasificación ABC\n(Próximamente)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
      floatingActionButton: _buildFloatingActionButton(),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0: // Dashboard
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/dashboard',
                (route) => false,
              );
              break;
            case 1: // Productos
              Navigator.pushNamed(context, '/products');
              break;
            case 2: // Inventario (current)
              break;
            case 3: // Configuración
              Navigator.pushNamed(context, '/settings');
              break;
          }
        },
      ),
    );
  }
}
