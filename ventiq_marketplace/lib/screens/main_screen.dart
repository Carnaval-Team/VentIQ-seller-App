import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'stores_screen.dart';
import 'products_screen.dart';
import 'cart_screen.dart';
import '../widgets/carnaval_fab.dart';

/// Pantalla principal con navegación inferior
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _didApplyInitialTab = false;

  final GlobalKey<CartScreenState> _cartScreenKey =
      GlobalKey<CartScreenState>();

  void _maybeRefreshCart(int index) {
    if (index != 3) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cartScreenKey.currentState?.refreshCart();
    });
  }

  void _setTab(int index) {
    setState(() {
      _currentIndex = index;
    });
    _maybeRefreshCart(index);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didApplyInitialTab) return;

    final args = ModalRoute.of(context)?.settings.arguments;

    int? initialTabIndex;
    if (args is int) {
      initialTabIndex = args;
    } else if (args is Map) {
      final raw = args['initialTabIndex'];
      if (raw is int) {
        initialTabIndex = raw;
      } else if (raw != null) {
        initialTabIndex = int.tryParse(raw.toString());
      }
    }

    if (initialTabIndex != null &&
        initialTabIndex >= 0 &&
        initialTabIndex <= 3) {
      _didApplyInitialTab = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setTab(initialTabIndex!);
      });
    } else {
      _didApplyInitialTab = true;
    }
  }

  void _changeTab(int index) {
    _setTab(index);
  }

  List<Widget> get _screens => [
    HomeScreen(onNavigateToTab: _changeTab),
    const StoresScreen(),
    const ProductsScreen(),
    CartScreen(key: _cartScreenKey),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: const CarnavalFab(),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          _setTab(index);
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.store_outlined),
            activeIcon: Icon(Icons.store),
            label: 'Tiendas',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_outlined),
            activeIcon: Icon(Icons.grid_view),
            label: 'Productos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_outlined),
            activeIcon: Icon(Icons.shopping_cart),
            label: 'Plan',
          ),
        ],
      ),
    );
  }
}
