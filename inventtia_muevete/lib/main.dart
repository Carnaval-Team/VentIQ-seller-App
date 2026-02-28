import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'config/app_theme.dart';
import 'services/background_service.dart';
import 'services/local_notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/location_provider.dart';
import 'providers/transport_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/address_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/client/home_map_screen.dart';
import 'screens/client/route_preview_screen.dart';
import 'screens/client/driver_offers_screen.dart';
import 'screens/client/ride_confirmed_screen.dart';
import 'screens/client/wallet_screen.dart';
import 'screens/client/profile_screen.dart';
import 'screens/client/saved_addresses_screen.dart';
import 'screens/client/request_history_screen.dart';
import 'screens/driver/driver_home_screen.dart';
import 'screens/driver/incoming_requests_screen.dart';
import 'screens/driver/active_ride_screen.dart';
import 'screens/driver/driver_wallet_screen.dart';
import 'widgets/notification_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  // Initialize background service & local notifications
  await BackgroundService.init();
  await LocalNotificationService().init();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MueveteApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MueveteApp extends StatelessWidget {
  const MueveteApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Wire up the navigator key for notification tap navigation.
    LocalNotificationService.navigatorKey = navigatorKey;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => TransportProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => AddressProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Muevete',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            initialRoute: '/',
            builder: (context, child) {
              return NotificationOverlay(
                child: child ?? const SizedBox.shrink(),
              );
            },
            routes: {
              '/': (context) => const SplashScreen(),
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/client/home': (context) => const HomeMapScreen(),
              '/client/route-preview': (context) => const RoutePreviewScreen(),
              '/client/driver-offers': (context) => const DriverOffersScreen(),
              '/client/ride-confirmed': (context) =>
                  const RideConfirmedScreen(),
              '/client/wallet': (context) => const WalletScreen(),
              '/client/profile': (context) => const ProfileScreen(),
              '/client/saved-addresses': (context) =>
                  const SavedAddressesScreen(),
              '/client/request-history': (context) =>
                  const RequestHistoryScreen(),
              '/driver/home': (context) => const DriverHomeScreen(),
              '/driver/requests': (context) =>
                  const IncomingRequestsScreen(),
              '/driver/active-ride': (context) => const ActiveRideScreen(),
              '/driver/wallet': (context) => const DriverWalletScreen(),
            },
          );
        },
      ),
    );
  }
}
