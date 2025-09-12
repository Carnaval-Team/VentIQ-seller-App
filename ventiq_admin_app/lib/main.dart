import 'package:flutter/material.dart';
import 'config/app_colors.dart';
import 'models/product.dart';
import 'screens/splash_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/products_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/add_product_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/sales_screen.dart';
import 'screens/promotions_screen.dart';
import 'screens/marketing_dashboard_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/campaigns_screen.dart';
import 'screens/communications_screen.dart';
import 'screens/segments_screen.dart';
import 'screens/loyalty_screen.dart';
import 'screens/financial_screen.dart';
import 'screens/customers_screen.dart';
import 'screens/workers_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/warehouse_screen.dart';
import 'screens/add_warehouse_screen.dart';
import 'services/auth_service.dart';

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
      title: 'Vendedor admin',
      debugShowCheckedModeBanner: false,
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
          default:
            return null;
        }
      },
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/products': (context) => const ProductsScreen(),
        '/categories': (context) => const CategoriesScreen(),
        '/inventory': (context) => const InventoryScreen(),
        '/sales': (context) => const SalesScreen(),
        '/financial': (context) => const FinancialScreen(),
        '/customers': (context) => const CustomersScreen(),
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
      },
    );
  }
}
