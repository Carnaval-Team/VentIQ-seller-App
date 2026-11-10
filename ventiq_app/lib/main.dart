import 'dart:async';

import 'package:flutter/material.dart';
import 'tutorial/tutorial_overlay.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/login_web_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/categories_web_screen.dart';
import 'screens/home_shell_screen.dart';
import 'screens/preorder_screen.dart';
import 'screens/preorder_screen_styled.dart';
import 'screens/orders_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/apertura_screen.dart';
import 'screens/egreso_screen.dart';
import 'screens/venta_total_screen.dart';
import 'screens/cierre_screen.dart';
import 'screens/cierre_pendiente_detalle_screen.dart';
import 'screens/shift_workers_screen.dart';
import 'screens/offline_data_viewer_screen.dart';
import 'screens/subscription_detail_screen.dart';
import 'screens/wifi_printers_screen.dart';
import 'screens/default_order_items_screen.dart';
import 'screens/mesas_screen.dart';
import 'screens/servicentro_screen.dart';
import 'screens/mesa_detail_screen.dart';
import 'screens/cuenta_mesa_screen.dart';
import 'screens/kds_screen.dart';
import 'screens/produccion_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/admin/admin_stock_screen.dart';
import 'screens/admin/admin_reception_screen.dart';
import 'screens/admin/admin_adjustment_screen.dart';
import 'screens/admin/admin_products_screen.dart';
import 'screens/admin/admin_prepare_offline_screen.dart';
import 'screens/admin/admin_turnos_offline_screen.dart';
import 'screens/admin/admin_pending_ops_screen.dart';
import 'screens/admin/admin_extraction_screen.dart';
import 'screens/admin/admin_transfer_screen.dart';
import 'screens/admin/admin_warehouses_screen.dart';
import 'screens/admin/admin_sale_agreement_screen.dart';
import 'screens/admin/admin_suppliers_screen.dart';
import 'screens/admin/admin_customers_screen.dart';
import 'screens/admin/admin_ipv_screen.dart';
import 'screens/admin/admin_tpv_prices_screen.dart';
import 'screens/admin/admin_tpv_vendors_screen.dart';
import 'screens/offline_user_switch_screen.dart';
import 'services/auth_service.dart';
import 'services/user_preferences_service.dart';
import 'services/store_config_service.dart';
import 'services/servicentro_service.dart';
import 'services/offline_database_service.dart';
import 'services/server_time_service.dart';
import 'utils/platform_utils.dart';
import 'utils/global_navigator.dart';
import 'widgets/sync_blocking_overlay.dart';
import 'widgets/offline_dialog_overlay.dart';
import 'widgets/license_reconnect_banner.dart';

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
  await ServicentroService.primeCache();

  // Cargar el último desfasaje de reloj conocido contra el servidor (se
  // corrige de nuevo cada vez que hay una petición de red exitosa) para que
  // las fechas guardadas offline (apertura/cierre/órdenes) sean lo más fieles
  // posible a la hora real, aunque el reloj del dispositivo esté mal.
  await ServerTimeService().loadPersistedOffset();
  // Intento de refresco inmediato (no bloqueante si no hay red).
  unawaited(ServerTimeService().refreshFromNetwork());

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
      navigatorObservers: [routeObserver],
      scaffoldMessengerKey: globalScaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF194B8C)),
        // Lenguaje visual compartido con el Home nuevo y el listado:
        // superficies, radios, bordes y botones salen de VentiqHomeTheme para
        // que todas las pantallas se sientan de la misma familia.
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF194B8C),
          foregroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.white),
          actionsIconTheme: IconThemeData(color: Colors.white),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE0E6ED)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF194B8C),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF194B8C),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF194B8C),
            side: const BorderSide(color: Color(0xFFE0E6ED)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF194B8C),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE0E6ED)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE0E6ED)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF194B8C), width: 1.6),
          ),
          labelStyle: const TextStyle(color: Color(0xFF5A6B85), fontSize: 13),
          hintStyle: const TextStyle(color: Color(0xFF8A97AC), fontSize: 13),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE0E6ED),
          thickness: 1,
          space: 1,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE0E6ED)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          labelStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5A6B85),
          ),
          secondaryLabelStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF194B8C),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF14224A),
          ),
          contentTextStyle: const TextStyle(
            fontSize: 14,
            height: 1.35,
            color: Color(0xFF5A6B85),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF14224A),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF194B8C),
          textColor: Color(0xFF14224A),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF194B8C),
        ),
      ),
      builder: (context, child) {
        return TutorialOverlayHost(
          child: OfflineDialogOverlay(
            child: SyncBlockingOverlay(
              child: Column(
                children: [
                  const LicenseReconnectBanner(),
                  Expanded(child: child ?? const SizedBox.shrink()),
                ],
              ),
            ),
          ),
        );
      },
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const PlatformAwareLoginScreen(),
        '/login-mobile': (context) => const LoginScreen(),
        '/login-web': (context) => const LoginWebScreen(),
        '/categories': (context) => const PlatformAwareCategoriesScreen(),
        '/categories-mobile': (context) => const CategoriesScreen(),
        '/categories-web': (context) => const CategoriesWebScreen(),
        // Variante visual de la pre-orden. El interruptor `kPreorderStyled`
        // (en preorder_screen_styled.dart) decide cuál se sirve; ponerlo en
        // `false` devuelve la pantalla de siempre sin tocar nada más.
        // Ver docs/design/preorder-styled.md.
        '/preorder':
            (context) =>
                kPreorderStyled
                    ? const PreorderScreenStyled()
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
        '/apertura': (context) => const AperturaScreen(),
        '/egreso': (context) => const EgresoScreen(),
        '/venta-total': (context) => const VentaTotalScreen(),
        '/cierre': (context) => const CierreScreen(),
        '/cierre-pendiente': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          return CierrePendienteDetalleScreen(
            localTurnoId: args is String ? args : null,
          );
        },
        '/shift-workers': (context) => const ShiftWorkersScreen(),
        '/offline-data-viewer': (context) => const OfflineDataViewerScreen(),
        '/subscription-detail': (context) => const SubscriptionDetailScreen(),
        '/wifi-printers': (context) => const WiFiPrintersScreen(),
        '/default-order-items': (context) => const DefaultOrderItemsScreen(),
        '/mesas': (context) => const MesasScreen(),
        '/servicentro': (context) => const ServicentroScreen(),
        '/kds': (context) => const KdsScreen(),
        '/produccion': (context) => const ProduccionScreen(),
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
        '/admin-warehouses': (context) => const AdminWarehousesScreen(),
        '/admin-reception': (context) => const AdminReceptionScreen(),
        '/admin-extraction': (context) => const AdminExtractionScreen(),
        '/admin-transfer': (context) => const AdminTransferScreen(),
        '/admin-sale-agreement': (context) => const AdminSaleAgreementScreen(),
        '/admin-suppliers': (context) => const AdminSuppliersScreen(),
        '/admin-customers': (context) => const AdminCustomersScreen(),
        '/admin-ipv': (context) => const AdminIpvScreen(),
        '/admin-tpv-prices': (context) => const AdminTpvPricesScreen(),
        '/admin-tpv-vendors': (context) => const AdminTpvVendorsScreen(),
        '/admin-adjustment': (context) => const AdminAdjustmentScreen(),
        '/admin-products': (context) => const AdminProductsScreen(),
        '/admin-pending-ops': (context) => const AdminPendingOpsScreen(),
        '/admin-prepare-offline':
            (context) => const AdminPrepareOfflineScreen(),
        '/admin-turnos-offline': (context) => const AdminTurnosOfflineScreen(),
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
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// Punto de entrada del Home.
///
/// Desde la Fase 3 devuelve el **Home nuevo** (`HomeShellScreen`), que es una
/// sola pantalla para web y móvil. Las pantallas viejas siguen registradas en
/// `/categories-mobile` y `/categories-web` a propósito: son la vuelta atrás
/// durante un release, y su lógica no visual (modo fluido, ajustes, diálogo de
/// actualización) todavía se está portando pieza a pieza.
class PlatformAwareCategoriesScreen extends StatelessWidget {
  const PlatformAwareCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // `PlatformUtils` ya no decide nada aquí: el shell es responsive.
    return const HomeShellScreen();
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
