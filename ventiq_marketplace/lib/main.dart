import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_theme.dart';
import 'config/supabase_config.dart';
import 'providers/theme_provider.dart';
import 'services/app_navigation_service.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'screens/splash_screen.dart';
import 'screens/main_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/store_management_screen.dart';
import 'screens/notification_hub_screen.dart';
import 'screens/notification_settings_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  await NotificationService().initialize();

  // Registrar el servicio de segundo plano
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await BackgroundServiceManager.initializeService();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const InventtiaMarketplaceApp(),
    ),
  );
}

class InventtiaMarketplaceApp extends StatelessWidget {
  const InventtiaMarketplaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Inventtia Marketplace',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
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
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
