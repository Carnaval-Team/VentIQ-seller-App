import 'package:flutter/material.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'stores_screen.dart';
import 'products_screen.dart';
import 'cart_screen.dart';
import '../widgets/carnaval_fab.dart';
import '../services/store_service.dart';
import 'store_detail_screen.dart';

/// Pantalla principal con navegación inferior
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _didApplyInitialTab = false;
  bool _didHandleDeepLinkStore = false;

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _deepLinkSub;

  int? _parseStoreIdFromUri(Uri? uri) {
    if (uri == null) return null;
    final raw = (uri.queryParameters['storeId'] ?? '').toString();
    final id = int.tryParse(raw);
    if (id != null && id > 0) return id;
    return null;
  }

  @override
  void initState() {
    super.initState();

    _deepLinkSub = _appLinks.uriLinkStream.listen((uri) {
      if (!mounted) return;
      if (_didHandleDeepLinkStore) return;

      final storeId = _parseStoreIdFromUri(uri);
      if (storeId == null || storeId <= 0) return;

      _didHandleDeepLinkStore = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openStoreFromDeepLink(storeId);
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  int? _parseStoreIdFromUrl() {
    final base = Uri.base;

    final direct = (base.queryParameters['storeId'] ?? '').toString();
    final directId = int.tryParse(direct);
    if (directId != null && directId > 0) return directId;

    final fragment = base.fragment;
    if (fragment.isEmpty) return null;

    final fragPath = fragment.startsWith('/') ? fragment : '/$fragment';
    final fragUri = Uri.tryParse('http://localhost$fragPath');
    final fragRaw = (fragUri?.queryParameters['storeId'] ?? '').toString();
    final fragId = int.tryParse(fragRaw);
    if (fragId != null && fragId > 0) return fragId;

    return null;
  }

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

    final args = ModalRoute.of(context)?.settings.arguments;

    if (!_didApplyInitialTab) {
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

    if (_didHandleDeepLinkStore) return;
    int? storeId;
    if (args is Map) {
      final raw = args['storeId'];
      if (raw is int) {
        storeId = raw;
      } else if (raw != null) {
        storeId = int.tryParse(raw.toString());
      }
    }

    storeId ??= _parseStoreIdFromUrl();

    if (storeId != null && storeId > 0) {
      _didHandleDeepLinkStore = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openStoreFromDeepLink(storeId!);
      });
    }
  }

  Future<void> _openStoreFromDeepLink(int storeId) async {
    try {
      final store = await StoreService().getStoreDetails(storeId);
      if (!mounted) return;

      if (store == null) {
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Tienda no disponible'),
              content: const Text('No se pudo cargar la tienda del QR'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
        return;
      }

      final isValidated = store['validada'] == true;
      final isVisibleInCatalog = store['mostrar_en_catalogo'] == true;
      final effectiveVisible = isValidated && isVisibleInCatalog;

      if (!effectiveVisible) {
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Tienda no disponible'),
              content: const Text('La tienda que buscas no está validada'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
        return;
      }

      _setTab(1);

      int productCount = 0;
      try {
        final response = await Supabase.instance.client
            .from('app_dat_producto')
            .select('id')
            .eq('id_tienda', storeId)
            .isFilter('deleted_at', null)
            .eq('es_vendible', true)
            .count(CountOption.exact);
        productCount = response.count;
      } catch (_) {
        productCount = 0;
      }

      final normalizedStore = <String, dynamic>{
        ...store,
        'nombre': store['nombre'] ?? store['denominacion'] ?? 'Tienda',
        'logoUrl': store['logoUrl'] ?? store['imagen_url'],
        'productCount': store['productCount'] ?? productCount,
      };

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StoreDetailScreen(store: normalizedStore),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Tienda no disponible'),
            content: const Text('Error abriendo la tienda del QR'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      );
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
