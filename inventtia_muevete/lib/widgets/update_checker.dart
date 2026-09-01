import 'package:flutter/material.dart';

import '../services/update_service.dart';
import 'update_dialog_helper.dart';

/// Verifica automáticamente si hay una actualización disponible al iniciar
/// la aplicación. Funciona tanto para APK como para web.
class UpdateChecker extends StatefulWidget {
  final Widget child;
  const UpdateChecker({super.key, required this.child});

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
  }

  Future<void> _checkForUpdates() async {
    if (_checked) return;
    _checked = true;

    // Esperar a que la navegación inicial termine y la UI esté estable.
    await Future.delayed(const Duration(seconds: 4));

    if (!mounted) return;

    try {
      final updateInfo = await UpdateService.checkForUpdates();

      if (!mounted) return;

      if (updateInfo['hay_actualizacion'] == true) {
        print('🆕 Actualización disponible detectada desde UpdateChecker');
        UpdateDialogHelper.showUpdateAvailableDialog(context, updateInfo);
      } else {
        print('✅ No hay actualizaciones disponibles desde UpdateChecker');
      }
    } catch (e) {
      print('❌ Error verificando actualizaciones automáticamente: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
