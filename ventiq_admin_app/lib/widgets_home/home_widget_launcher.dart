import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../utils/app_route_observer.dart';
import 'home_widget_service.dart';
import 'screens/widget_config_screen.dart';
import 'widget_keys.dart';

/// Enruta las aperturas de la app provocadas por un widget.
///
/// Dos flujos distintos:
///
/// 1. CONFIGURACIÓN. Android lanza MainActivity con
///    `ACTION_APPWIDGET_CONFIGURE` al soltar el widget en el escritorio.
///    `initiallyLaunchedFromHomeWidgetConfigure()` devuelve el appWidgetId; hay
///    que abrir la pantalla de ajustes y terminar con
///    `finishHomeWidgetConfigure()`, o el lanzador descarta el widget.
///
/// 2. TAP NORMAL. El widget abre la app con un deep link
///    `ventiqwidget://<host>?type=...&id=...`; se navega a la pantalla
///    correspondiente.
class HomeWidgetLauncher {
  HomeWidgetLauncher._();

  static StreamSubscription<Uri?>? _subscription;
  static _LifecycleHook? _lifecycleHook;

  /// Evita reentrar en el flujo de configuración mientras la pantalla está
  /// abierta (el hook de ciclo de vida puede disparar varias veces).
  static bool _configureInFlight = false;

  /// `attach` es idempotente: el Dashboard la llama en cada `initState`, y sin
  /// este guard cada reconstrucción volvería a leer el intent de lanzamiento.
  static bool _attached = false;

  /// El intent de lanzamiento (acción `...action.LAUNCH`) permanece pegado a la
  /// Activity durante toda su vida, así que
  /// `initiallyLaunchedFromHomeWidget()` devuelve el MISMO Uri en cada llamada.
  /// Se consume una única vez por proceso; los taps posteriores llegan por el
  /// stream `widgetClicked`.
  static bool _initialLaunchConsumed = false;

  /// Ruta en la que ya estamos cuando arranca el enrutado. Sirve para no
  /// re-navegar al destino actual (el caso del widget de Resumen, que apunta al
  /// propio Dashboard) y provocar un ciclo push → initState → push.
  static const String _dashboardRoute = '/dashboard';

  /// Se llama desde el Dashboard; solo la primera invocación tiene efecto.
  static Future<void> attach(GlobalKey<NavigatorState> navigatorKey) async {
    if (_attached) return;
    _attached = true;

    await _handleConfigureLaunch(navigatorKey);
    await _handleInitialLaunch(navigatorKey);

    _subscription ??= HomeWidget.widgetClicked.listen((uri) {
      _route(navigatorKey, uri);
    });

    // Con la app ya abierta, el intent de configuración llega por onNewIntent
    // (MainActivity es singleTop). Al volver a primer plano se vuelve a
    // comprobar para atender el widget que el usuario acaba de colocar.
    if (_lifecycleHook == null) {
      _lifecycleHook = _LifecycleHook(navigatorKey);
      WidgetsBinding.instance.addObserver(_lifecycleHook!);
    }
  }

  static Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
    if (_lifecycleHook != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleHook!);
      _lifecycleHook = null;
    }
    _attached = false;
  }

  /// Flujo de configuración nativo de Android.
  static Future<void> _handleConfigureLaunch(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    if (_configureInFlight) return;

    String? rawId;
    try {
      rawId = await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure();
    } catch (error) {
      debugPrint('⚠️ Widgets: configure launch no disponible: $error');
      return;
    }

    final appWidgetId = int.tryParse(rawId ?? '');
    if (appWidgetId == null) return;

    _configureInFlight = true;
    try {
      final type = await _resolveTypeForAppWidgetId(appWidgetId);
      if (type == null) {
        debugPrint('⚠️ Widgets: no se pudo resolver el tipo de $appWidgetId');
        // Se cierra el flujo igualmente para no dejar el widget en limbo.
        await HomeWidget.finishHomeWidgetConfigure();
        return;
      }

      final navigator = navigatorKey.currentState;
      if (navigator == null) return;

      await navigator.push(
        MaterialPageRoute(
          builder: (_) => WidgetConfigScreen(
            type: type,
            appWidgetId: appWidgetId,
            finishOnSave: true,
            onFinish: HomeWidget.finishHomeWidgetConfigure,
          ),
        ),
      );
    } finally {
      _configureInFlight = false;
    }
  }

  /// Deep link con el que se abrió la app (app cerrada previamente).
  ///
  /// Solo se atiende una vez por proceso: el intent de lanzamiento no se
  /// "consume" en el lado nativo, así que volver a preguntar devolvería el mismo
  /// Uri y re-navegaría en bucle.
  static Future<void> _handleInitialLaunch(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    if (_initialLaunchConsumed) return;
    _initialLaunchConsumed = true;

    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (uri != null) _route(navigatorKey, uri);
    } catch (error) {
      debugPrint('⚠️ Widgets: initial launch no disponible: $error');
    }
  }

  /// Resuelve el tipo de widget a partir del appWidgetId consultando los
  /// providers instalados (el canal de configuración solo entrega el id).
  static Future<HomeWidgetType?> _resolveTypeForAppWidgetId(
    int appWidgetId,
  ) async {
    try {
      final installed = await HomeWidget.getInstalledWidgets();
      for (final info in installed) {
        if (info.androidWidgetId != appWidgetId) continue;
        final className = info.androidClassName;
        if (className == null) continue;
        return HomeWidgetType.fromProviderClassName(className);
      }
    } catch (error) {
      debugPrint('⚠️ Widgets: getInstalledWidgets falló: $error');
    }
    return null;
  }

  static void _route(GlobalKey<NavigatorState> navigatorKey, Uri? uri) {
    if (uri == null) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final type = HomeWidgetType.fromPrefix(uri.queryParameters['type'] ?? '');
    final appWidgetId = int.tryParse(uri.queryParameters['id'] ?? '');

    switch (uri.host) {
      case 'dashboard':
        // El widget de Resumen apunta al propio Dashboard, que es justo la
        // pantalla desde la que se llama a `attach`. Navegar aquí crearía el
        // ciclo push → initState del Dashboard → attach → push. Si ya estamos
        // en '/dashboard' basta con no hacer nada: la pantalla correcta ya está
        // en primer plano.
        if (!_isCurrentRoute(_dashboardRoute)) {
          navigator.pushNamedAndRemoveUntil(_dashboardRoute, (route) => false);
        }
        break;

      case 'sales':
        _pushOnce(navigator, '/sales');
        break;

      case 'product':
        // Sin el objeto Product completo, la ruta '/product-detail' no puede
        // construirse; se abre el listado, que ya permite buscar el producto.
        _pushOnce(navigator, '/products');
        break;

      case 'configure':
        if (type != null && appWidgetId != null) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => WidgetConfigScreen(
                type: type,
                appWidgetId: appWidgetId,
              ),
            ),
          );
        }
        break;

      case WidgetKeys.hostRefresh:
        if (type != null && appWidgetId != null) {
          HomeWidgetService.refreshAll(onlyType: type);
        }
        break;
    }
  }

  /// Empuja la ruta solo si no es ya la visible, para no apilar duplicados
  /// cuando el usuario toca el widget varias veces.
  static void _pushOnce(NavigatorState navigator, String routeName) {
    if (_isCurrentRoute(routeName)) return;
    navigator.pushNamed(routeName);
  }

  /// ¿La ruta visible es [routeName]?
  ///
  /// Lo resuelve [AppRouteObserver], registrado en `MaterialApp`.
  static bool _isCurrentRoute(String routeName) =>
      AppRouteObserver.instance.isCurrent(routeName);
}

/// Reintenta el flujo de configuración cuando la app vuelve a primer plano.
///
/// Necesario porque, con la app ya abierta, Android entrega el intent
/// `ACTION_APPWIDGET_CONFIGURE` por `onNewIntent` (MainActivity es singleTop) y
/// no hay ningún evento de plugin que lo notifique a Dart.
class _LifecycleHook extends WidgetsBindingObserver {
  _LifecycleHook(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    HomeWidgetLauncher._handleConfigureLaunch(navigatorKey);
  }
}
