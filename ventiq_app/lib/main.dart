import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/login_web_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/categories_web_screen.dart';
import 'screens/products_screen.dart';
import 'screens/products_web_screen.dart';
import 'screens/product_details_screen.dart';
import 'screens/product_details_web_screen.dart';
import 'screens/preorder_screen.dart';
import 'screens/preorder_web_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/apertura_screen.dart';
import 'screens/apertura_web_screen.dart';
import 'screens/egreso_screen.dart';
import 'screens/venta_total_screen.dart';
import 'screens/venta_total_web_screen.dart';
import 'screens/cierre_screen.dart';
import 'screens/cierre_web_screen.dart';
import 'screens/shift_workers_screen.dart';
import 'screens/offline_data_viewer_screen.dart';
import 'screens/subscription_detail_screen.dart';
import 'screens/wifi_printers_screen.dart';
import 'models/product.dart';
import 'screens/default_order_items_screen.dart';
import 'screens/mesas_screen.dart';
import 'screens/mesa_detail_screen.dart';
import 'screens/cuenta_mesa_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/admin_stock_screen.dart';
import 'screens/admin/admin_reception_screen.dart';
import 'screens/admin/admin_adjustment_screen.dart';
import 'screens/admin/admin_products_screen.dart';
import 'screens/admin/admin_prepare_offline_screen.dart';
import 'screens/admin/admin_turnos_offline_screen.dart';
import 'screens/offline_user_switch_screen.dart';
import 'services/auth_service.dart';
import 'services/user_preferences_service.dart';
import 'services/store_config_service.dart';
import 'services/offline_database_service.dart';
import 'utils/platform_utils.dart';
import 'utils/global_navigator.dart';
import 'widgets/sync_blocking_overlay.dart';
import 'widgets/offline_dialog_overlay.dart';
import 'widgets/license_reconnect_banner.dart';

const double _webLayoutBreakpoint = 1200;

bool _shouldUseWebLayout(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  return PlatformUtils.isWeb && width >= _webLayoutBreakpoint;
}

Route<dynamic> _buildErrorRoute(String message) {
  return MaterialPageRoute(
    builder:
        (context) => Scaffold(
          appBar: AppBar(title: const Text('Ruta no disponible')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
  );
}

Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/products':
      final args = settings.arguments;
      if (args is! Map<String, dynamic>) {
        return _buildErrorRoute('Faltan datos para abrir productos.');
      }

      final categoryId = args['categoryId'] as int?;
      final categoryName = args['categoryName'] as String?;
      final categoryColor = args['categoryColor'] as Color?;

      if (categoryId == null || categoryName == null || categoryColor == null) {
        return _buildErrorRoute('Faltan datos para abrir productos.');
      }

      return MaterialPageRoute(
        builder: (context) {
          final useWebLayout = _shouldUseWebLayout(context);
          return useWebLayout
              ? ProductsWebScreen(
                categoryId: categoryId,
                categoryName: categoryName,
                categoryColor: categoryColor,
              )
              : ProductsScreen(
                categoryId: categoryId,
                categoryName: categoryName,
                categoryColor: categoryColor,
              );
        },
      );
    case '/product-details':
      final args = settings.arguments;
      if (args is! Map<String, dynamic>) {
        return _buildErrorRoute('Faltan datos para abrir el producto.');
      }

      final product = args['product'] as Product?;
      final categoryColor = args['categoryColor'] as Color?;

      if (product == null || categoryColor == null) {
        return _buildErrorRoute('Faltan datos para abrir el producto.');
      }

      return MaterialPageRoute(
        builder: (context) {
          final useWebLayout = _shouldUseWebLayout(context);
          return useWebLayout
              ? ProductDetailsWebScreen(
                product: product,
                categoryColor: categoryColor,
              )
              : ProductDetailsScreen(
                product: product,
                categoryColor: categoryColor,
              );
        },
      );
  }

  return null;
}

Route<dynamic> _onUnknownRoute(RouteSettings settings) {
  final routeName = settings.name ?? 'desconocida';
  return _buildErrorRoute('Ruta no disponible: $routeName');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Supabase
  await AuthService.initialize();

  // Inicializar almacenamiento offline. En web no usa SQLite (ver
  // OfflineDatabaseService); un fallo aquí no debe bloquear flutter-first-frame.
  try {
    await OfflineDatabaseService().initialize();
  } catch (e) {
    print('⚠️ OfflineDatabase init falló (continuando arranque): $e');
  }

  // Pre-cargar preferencias de usuario en caché para acceso sincrónico
  await UserPreferencesService().isShowSkuEnabled();

  // Pre-cargar el flag modo_restaurante en cache sincrónico para que el
  // NavigationHelper pueda decidir el destino del botón Home sin Future.
  await StoreConfigService.primeModoRestauranteCache();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inventtia Caja',
      debugShowCheckedModeBanner: false,
      navigatorKey: globalNavigatorKey,
      scaffoldMessengerKey: globalScaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF194B8C)),
      ),
      builder: (context, child) {
        return OfflineDialogOverlay(
          child: SyncBlockingOverlay(
            child: Column(
              children: [
                const LicenseReconnectBanner(),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
          ),
        );
      },
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
      onUnknownRoute: _onUnknownRoute,
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const PlatformAwareLoginScreen(),
        '/login-mobile': (context) => const LoginScreen(),
        '/login-web': (context) => const LoginWebScreen(),
        '/categories': (context) => const PlatformAwareCategoriesScreen(),
        '/categories-mobile': (context) => const CategoriesScreen(),
        '/categories-web': (context) => const CategoriesWebScreen(),
        '/preorder':
            (context) =>
                _shouldUseWebLayout(context)
                    ? const PreorderWebScreen()
                    : const PreorderScreen(),
        '/orders': (context) {
          // Soporta opcional autoOpenOrderId vía Navigator.pushNamed(arguments: ...)
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is String) {
            return OrdersScreen(autoOpenOrderId: args);
          }
          return const OrdersScreen();
        },
        '/settings': (context) => const SettingsScreen(),
        '/apertura':
            (context) =>
                _shouldUseWebLayout(context)
                    ? const AperturaWebScreen()
                    : const AperturaScreen(),
        '/egreso': (context) => const EgresoScreen(),
        '/venta-total':
            (context) =>
                _shouldUseWebLayout(context)
                    ? const VentaTotalWebScreen()
                    : const VentaTotalScreen(),
        '/cierre':
            (context) =>
                _shouldUseWebLayout(context)
                    ? const CierreWebScreen()
                    : const CierreScreen(),
        '/shift-workers': (context) => const ShiftWorkersScreen(),
        '/offline-data-viewer': (context) => const OfflineDataViewerScreen(),
        '/subscription-detail': (context) => const SubscriptionDetailScreen(),
        '/wifi-printers': (context) => const WiFiPrintersScreen(),
        '/default-order-items': (context) =>
            const DefaultOrderItemsScreen(),
        '/mesas': (context) => const MesasScreen(),
        '/mesa-detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is int) {
            return MesaDetailScreen(idMesa: args);
          }
          // Sin id → volver atrás
          return const _MesasFallback();
        },
        '/cuenta-mesa': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is int) {
            return CuentaMesaScreen(idCuenta: args);
          }
          return const _MesasFallback();
        },
        '/admin-home': (context) => const AdminHomeScreen(),
        '/admin-stock': (context) => const AdminStockScreen(),
        '/admin-reception': (context) => const AdminReceptionScreen(),
        '/admin-adjustment': (context) => const AdminAdjustmentScreen(),
        '/admin-products': (context) => const AdminProductsScreen(),
        '/admin-prepare-offline': (context) =>
            const AdminPrepareOfflineScreen(),
        '/admin-turnos-offline': (context) =>
            const AdminTurnosOfflineScreen(),
        '/offline-user-switch': (context) => const OfflineUserSwitchScreen(),
      },
    );
  }
}

/// Widget que detecta la plataforma y redirige al login apropiado
class PlatformAwareLoginScreen extends StatelessWidget {
  const PlatformAwareLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Detectar si estamos en web y redirigir al login apropiado
    if (PlatformUtils.isWeb) {
      return const LoginWebScreen();
    } else {
      return const LoginScreen();
    }
  }
}

/// Fallback cuando se navega a /mesa-detail sin id (no debería pasar).
class _MesasFallback extends StatelessWidget {
  const _MesasFallback();
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushReplacementNamed(context, '/mesas');
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Widget que detecta la plataforma y redirige a las categorías apropiadas
class PlatformAwareCategoriesScreen extends StatelessWidget {
  const PlatformAwareCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Detectar si estamos en web y redirigir a las categorías apropiadas
    if (PlatformUtils.isWeb) {
      return const CategoriesWebScreen();
    } else {
      return const CategoriesScreen();
    }
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
