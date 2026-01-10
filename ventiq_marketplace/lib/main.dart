import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_theme.dart';
import 'config/supabase_config.dart';
import 'services/app_navigation_service.dart';
import 'services/notification_service.dart';
import 'screens/splash_screen.dart';
import 'screens/main_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/store_management_screen.dart';
import 'screens/notification_hub_screen.dart';
import 'screens/notification_settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  await NotificationService().initialize();

  runApp(const InventtiaMarketplaceApp());
}

class InventtiaMarketplaceApp extends StatelessWidget {
  const InventtiaMarketplaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventtia Marketplace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: AppNavigationService.navigatorKey,
      builder: (context, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NotificationService().drainPendingNavigation();
        });
        return child ?? const SizedBox.shrink();
      },
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/home': (context) => const MainScreen(),
        '/auth': (context) => const AuthScreen(),
        '/store-management': (context) => const StoreManagementScreen(),
        '/notification-hub': (context) => const NotificationHubScreen(),
        '/notification-settings': (context) =>
            const NotificationSettingsScreen(),
      },
    );
  }
}
