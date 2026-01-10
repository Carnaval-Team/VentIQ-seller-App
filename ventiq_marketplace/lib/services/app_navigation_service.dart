import 'package:flutter/material.dart';

class AppNavigationService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static NavigatorState? get _navigator => navigatorKey.currentState;

  static Future<T?> pushNamed<T extends Object?>(
    String routeName, {
    Object? arguments,
  }) {
    final navigator = _navigator;
    if (navigator == null) return Future.value(null);
    return navigator.pushNamed<T>(routeName, arguments: arguments);
  }

  static Future<T?> pushNamedAndRemoveUntil<T extends Object?>(
    String routeName, {
    Object? arguments,
  }) {
    final navigator = _navigator;
    if (navigator == null) return Future.value(null);

    return navigator.pushNamedAndRemoveUntil<T>(
      routeName,
      (route) => false,
      arguments: arguments,
    );
  }
}
