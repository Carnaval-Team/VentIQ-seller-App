import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../widgets/global_config_tab_view.dart';
import '../widgets/categories_tab_view.dart';
import '../widgets/variants_tab_view.dart';
import '../widgets/presentations_tab_view.dart';
import '../widgets/units_tab_view.dart';
import '../services/variant_service.dart';
import '../utils/screen_protection_mixin.dart';
import '../utils/navigation_guard.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin, ScreenProtectionMixin {
  @override
  String get protectedRoute => '/settings';
  late TabController _tabController;
  final GlobalKey<State<GlobalConfigTabView>> _globalConfigTabKey =
      GlobalKey<State<GlobalConfigTabView>>();
  final GlobalKey<State<CategoriesTabView>> _categoriesTabKey =
      GlobalKey<State<CategoriesTabView>>();
  final GlobalKey<State<VariantsTabView>> _variantsTabKey =
      GlobalKey<State<VariantsTabView>>();
  final GlobalKey<State<PresentationsTabView>> _presentationsTabKey =
      GlobalKey<State<PresentationsTabView>>();
  final GlobalKey<State<UnitsTabView>> _unitsTabKey =
      GlobalKey<State<UnitsTabView>>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Verificar permisos antes de mostrar contenido
    if (isCheckingPermissions) {
      return buildPermissionLoadingWidget();
    }

    if (!hasAccess) {
      return buildAccessDeniedWidget();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Configuración',
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
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Global', icon: Icon(Icons.settings_applications)),
            Tab(text: 'Categorías', icon: Icon(Icons.category)),
            Tab(text: 'Variantes', icon: Icon(Icons.format_shapes)),
            Tab(text: 'Presentaciones', icon: Icon(Icons.format_paint)),
            Tab(text: 'Unidades', icon: Icon(Icons.straighten)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          GlobalConfigTabView(key: _globalConfigTabKey),
          CategoriesTabView(key: _categoriesTabKey),
          VariantsTabView(key: _variantsTabKey),
          PresentationsTabView(key: _presentationsTabKey),
          UnitsTabView(key: _unitsTabKey),
        ],
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 3,
        onTap: _onBottomNavTap,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog() {
    final currentTab = _tabController.index;
    switch (currentTab) {
      case 0:
        // Tab Global - no tiene funcionalidad de agregar
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La configuración global no permite agregar elementos',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        break;
      case 1:
        _showAddCategoryDialog();
        break;
      case 2:
        (_variantsTabKey.currentState as dynamic)?.showAddVariantDialog();
        break;
      case 3:
        (_presentationsTabKey.currentState as dynamic)
            ?.showAddPresentationDialog();
        break;
      case 4:
        (_unitsTabKey.currentState as dynamic)?.showAddDialog();
        break;
    }
  }

  void _showAddCategoryDialog() {
    // Llamar directamente al método del CategoriesTabView usando la key
    (_categoriesTabKey.currentState as dynamic)?.showAddCategoryDialog();
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
        break;
      case 1:
        Navigator.pushNamed(context, '/products-dashboard');
        break;
      case 2:
        Navigator.pushNamed(context, '/inventory');
        break;
      case 3:
        break;
    }
  }
}
