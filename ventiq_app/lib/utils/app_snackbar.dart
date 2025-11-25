import 'package:flutter/material.dart';

/// Utilidad centralizada para mostrar SnackBars persistentes
/// que solo se cierran cuando el usuario toca el botón.
class AppSnackBar {
  /// Muestra un SnackBar que permanece visible hasta que el usuario
  /// presiona el botón de "Cerrar" (o hasta que otra parte del código
  /// lo oculte explícitamente).
  static void showPersistent(
    BuildContext context, {
    required String message,
    Color? backgroundColor,
    String closeLabel = 'Cerrar',
  }) {
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? Colors.black87,
        // Duración muy larga para que, en la práctica, solo se cierre
        // cuando el usuario pulse el botón.
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: closeLabel,
          textColor: Colors.white,
          onPressed: () {
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}
