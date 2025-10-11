import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import 'inventory_reception_screen.dart';
import 'inventory_operations_screen.dart';
import 'inventory_warehouse_screen.dart';
import 'inventory_stock_screen.dart';
import 'inventory_transfer_screen.dart';
import 'inventory_extraction_screen.dart';
import 'inventory_adjustment_screen.dart'; // Importar la pantalla de ajuste de inventario
import 'elaborated_products_extraction_screen.dart'; // Nueva pantalla
import 'inventory_extractionbysale_screen.dart'; // Venta por Acuerdo
import 'inventory_dashboard.dart';

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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Title
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text(
                    'Opciones de Inventario',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),

                // Scrollable menu options
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildMenuOption(
                          icon: Icons.input,
                          title: 'Recepción de Productos',
                          subtitle: 'Registrar entrada de mercancía',
                          color: const Color(0xFF10B981),
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToReception();
                          },
                        ),

                        _buildMenuOption(
                          icon: Icons.swap_horiz,
                          title: 'Transferencia entre Almacenes',
                          subtitle: 'Mover productos entre ubicaciones',
                          color: const Color(0xFF4A90E2),
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToTransfer();
                          },
                        ),

                        _buildMenuOption(
                          icon: Icons.trending_up,
                          title: 'Ajuste por Exceso',
                          subtitle: 'Reducir inventario por sobrante',
                          color: const Color(0xFFFF6B35),
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToExcessAdjustment();
                          },
                        ),

                        _buildMenuOption(
                          icon: Icons.trending_down,
                          title: 'Ajuste por Faltante',
                          subtitle: 'Aumentar inventario por faltante',
                          color: const Color(0xFFFF8C42),
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToShortageAdjustment();
                          },
                        ),

                        _buildMenuOption(
                          icon: Icons.output,
                          title: 'Extracción de Productos',
                          subtitle: 'Registrar salida de mercancía',
                          color: const Color(0xFFEF4444),
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToExtraction();
                          },
                        ),

                        _buildMenuOption(
                          icon: Icons.output,
                          title: 'Extracción de Productos Elaborados',
                          subtitle: 'Registrar salida de productos elaborados',
                          color: const Color(0xFFEF4444),
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToElaboratedProductsExtraction();
                          },
                        ),

                        _buildMenuOption(
                          icon: Icons.point_of_sale,
                          title: 'Venta por Acuerdo',
                          subtitle: 'Registrar venta directa con precio personalizado',
                          color: const Color(0xFF10B981),
                          onTap: () {
                            Navigator.pop(context);
                            _navigateToSaleByAgreement();
                          },
                        ),

                        _buildMenuOption(
                          icon: Icons.filter_list,
                          title: 'Filtro de Búsqueda',
                          subtitle: 'Filtrar y buscar productos',
                          color: const Color(0xFF8B5CF6),
                          onTap: () {
                            Navigator.pop(context);
                            _showSearchFilter();
                          },
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
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

  void _navigateToExtraction() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const InventoryExtractionScreen(),
      ),
    );
  }

  void _navigateToElaboratedProductsExtraction() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ElaboratedProductsExtractionScreen(),
      ),
    );
  }

  void _navigateToSaleByAgreement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const InventoryExtractionBySaleScreen(),
      ),
    );
  }

  void _navigateToExcessAdjustment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => const InventoryAdjustmentScreen(
              operationType: 4, // Tipo de operación para exceso (restar)
              adjustmentType: 'excess',
            ),
      ),
    );
  }

  void _navigateToShortageAdjustment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => const InventoryAdjustmentScreen(
              operationType: 3, // Tipo de operación para faltante (sumar)
              adjustmentType: 'shortage',
            ),
      ),
    );
  }

  void _showSearchFilter() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Filtro de Búsqueda'),
            content: const Text(
              'La funcionalidad de filtro avanzado estará disponible próximamente.',
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

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 14),
      ),
      onTap: onTap,
    );
  }

  Widget? _buildFloatingActionButton() {
    // Show FAB on all tabs now
    return FloatingActionButton(
      onPressed: _showFabOptions,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      tooltip: 'Opciones de Inventario',
      child: const Icon(Icons.add),
    );
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
            Tab(text: 'Dashboard', icon: Icon(Icons.dashboard, size: 18)),
            Tab(text: 'Stock', icon: Icon(Icons.inventory_2, size: 18)),            
            Tab(text: 'Movimientos', icon: Icon(Icons.swap_horiz, size: 18)),
            Tab(text: 'Almacenes', icon: Icon(Icons.warehouse, size: 18)),
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
                  const InventoryDashboard(),
                  const InventoryStockScreen(),                  
                  const InventoryOperationsScreen(),
                  const InventoryWarehouseScreen(),
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
              Navigator.pushNamed(context, '/products-dashboard');
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
