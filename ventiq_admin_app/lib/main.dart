import 'package:flutter/material.dart';
import 'package:ventiq_admin_app/screens/excel_import_screen.dart';
import 'package:ventiq_admin_app/screens/suppliers/supplier_reports_screen.dart';
import 'package:ventiq_admin_app/widgets/supplier/supplier_alerts_widget.dart';
import 'config/app_colors.dart';
import 'models/product.dart';
import 'models/supplier.dart';
import 'screens/splash_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/dashboard_web_screen.dart';
import 'screens/login_screen.dart';
import 'utils/platform_utils.dart';
import 'screens/store_registration_screen.dart';
import 'screens/products_screen.dart';
import 'screens/products_dashboard_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/add_product_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/tpv_prices_screen.dart';
import 'screens/tpv_management_screen.dart';
import 'screens/promotions_screen.dart';
import 'screens/marketing_dashboard_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/campaigns_screen.dart';
import 'screens/communications_screen.dart';
import 'screens/segments_screen.dart';
import 'screens/loyalty_screen.dart';
import 'screens/financial_screen.dart';
import 'screens/financial_setup_screen.dart';
import 'screens/financial_dashboard_screen.dart';
import 'screens/financial_reports_screen.dart';
import 'screens/financial_expenses_screen.dart';
import 'screens/production_costs_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/workers_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/warehouse_screen.dart';
import 'screens/add_warehouse_screen.dart';
import 'services/auth_service.dart';
import 'screens/crm_dashboard_screen.dart';
import 'screens/crm_analytics_screen.dart';
import 'screens/crm_relationships_screen.dart';
import 'screens/suppliers/suppliers_list_screen.dart';
import 'screens/suppliers/supplier_detail_screen.dart';
import 'screens/suppliers/add_edit_supplier_screen.dart';
import 'screens/inventory_extractionbysale_screen.dart';
import 'screens/subscription_detail_screen.dart';
import 'screens/store_selection_screen.dart';
import 'screens/wifi_printers_screen.dart';
import 'screens/consignacion_screen.dart';
import 'screens/interacciones_clientes_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await AuthService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventtia Admin',
      debugShowCheckedModeBanner: false,
      // Configuración específica para web deployment
      // useInheritedMediaQuery: true,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          color: Colors.white,
        ),
      ),
      initialRoute: '/', // Inicia con splash screen
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/product-detail':
            final product = settings.arguments as Product?;
            if (product != null) {
              return MaterialPageRoute(
                builder: (context) => ProductDetailScreen(product: product),
              );
            }
            return MaterialPageRoute(
              builder: (context) => const ProductsScreen(),
            );
          case '/supplier-detail':
            final supplier = settings.arguments as Supplier?;
            if (supplier != null) {
              return MaterialPageRoute(
                builder: (context) => SupplierDetailScreen(supplier: supplier),
              );
            }
            return MaterialPageRoute(
              builder: (context) => const SuppliersListScreen(),
            );
          case '/edit-supplier':
            final supplier = settings.arguments as Supplier?;
            if (supplier != null) {
              return MaterialPageRoute(
                builder: (context) => AddEditSupplierScreen(supplier: supplier),
              );
            }
            return MaterialPageRoute(
              builder: (context) => const AddEditSupplierScreen(),
            );
          case '/store-selection':
            final args = settings.arguments as Map<String, dynamic>?;
            if (args != null) {
              return MaterialPageRoute(
                builder:
                    (context) => StoreSelectionScreen(
                      stores: args['stores'] as List<Map<String, dynamic>>,
                      defaultStoreId: args['defaultStoreId'] as int,
                    ),
              );
            }
            return MaterialPageRoute(
              builder: (context) => const SplashScreen(),
            );
          default:
            // Manejo de rutas no encontradas - redirigir al splash
            print('⚠️ Ruta no encontrada: ${settings.name}');
            return MaterialPageRoute(
              builder: (context) => const SplashScreen(),
            );
        }
      },
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const PlatformAwareDashboardScreen(),
        '/dashboard-mobile': (context) => const DashboardScreen(),
        '/dashboard-web': (context) => const DashboardWebScreen(),
        '/products': (context) => const ProductsScreen(),
        '/products-dashboard': (context) => const ProductsDashboardScreen(),
        '/categories': (context) => const CategoriesScreen(),
        '/inventory': (context) => const InventoryScreen(),
        '/sales': (context) => const SalesScreen(),
        '/tpv-prices': (context) => const TpvPricesScreen(),
        '/tpv-management': (context) => const TpvManagementScreen(),
        '/financial': (context) => const FinancialScreen(),
        '/financial-setup': (context) => const FinancialSetupScreen(),
        '/financial-dashboard': (context) => const FinancialDashboardScreen(),
        '/financial-reports': (context) => const FinancialReportsScreen(),
        '/financial-expenses': (context) => const FinancialExpensesScreen(),
        '/restaurant-costs': (context) => const ProductionCostsScreen(),
        '/customers': (context) => const CustomersScreen(),
        '/crm-dashboard': (context) => const CRMDashboardScreen(),
        '/crm-analytics': (context) => const CRMAnalyticsScreen(),
        '/relationships': (context) => const CRMRelationshipsScreen(),
        '/suppliers': (context) => const SuppliersListScreen(),
        '/supplier-alerts':
            (context) =>
                const SupplierAlertsWidget(alerts: [], isLoading: false),
        '/supplier-reports': (context) => const SupplierReportsScreen(),
        '/excel-import': (context) => const ExcelImportScreen(),
        '/add-supplier': (context) => const AddEditSupplierScreen(),
        '/edit-supplier': (context) => const AddEditSupplierScreen(),
        '/workers': (context) => const WorkersScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/warehouse': (context) => const WarehouseScreen(),
        '/add-warehouse': (context) => const AddWarehouseScreen(),
        '/promotions': (context) => const PromotionsScreen(),
        '/marketing-dashboard': (context) => const MarketingDashboardScreen(),
        '/analytics': (context) => const AnalyticsScreen(),
        '/campaigns': (context) => const CampaignsScreen(),
        '/communications': (context) => const CommunicationsScreen(),
        '/segments': (context) => const SegmentsScreen(),
        '/loyalty': (context) => const LoyaltyScreen(),
        '/add-product': (context) => const AddProductScreen(),
        '/store-registration': (context) => const StoreRegistrationScreen(),
        '/sale-by-agreement':
            (context) => const InventoryExtractionBySaleScreen(),
        '/subscription-detail': (context) => const SubscriptionDetailScreen(),
        '/consignacion': (context) => const ConsignacionScreen(),
        '/wifi-printers': (context) => const WiFiPrintersScreen(),
        '/interacciones-clientes': (context) => const InteraccionesClientesScreen(),
      },
    );
  }
}

/// Widget que detecta la plataforma y redirige al dashboard apropiado
class PlatformAwareDashboardScreen extends StatelessWidget {
  const PlatformAwareDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Detectar si estamos en web y redirigir al dashboard apropiado
    if (PlatformUtils.isWeb) {
      return const DashboardWebScreen();
    } else {
      return const DashboardScreen();
    }
  }
}
