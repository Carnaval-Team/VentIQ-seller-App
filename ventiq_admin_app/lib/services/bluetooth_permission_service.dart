import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Servicio para manejar permisos de Bluetooth
class BluetoothPermissionService {
  /// Verificar y solicitar permisos de Bluetooth
  Future<bool> checkAndRequestBluetoothPermissions(BuildContext context) async {
    try {
      // Lista de permisos requeridos
      List<Permission> requiredPermissions = [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location,
      ];

      // Verificar estado actual de permisos
      Map<Permission, PermissionStatus> statuses = {};
      for (Permission permission in requiredPermissions) {
        statuses[permission] = await permission.status;
      }

      // Filtrar permisos que necesitan ser solicitados
      List<Permission> permissionsToRequest = [];
      for (Permission permission in requiredPermissions) {
        if (statuses[permission] != PermissionStatus.granted) {
          permissionsToRequest.add(permission);
        }
      }

      // Si todos los permisos ya están concedidos
      if (permissionsToRequest.isEmpty) {
        return true;
      }

      // Mostrar diálogo de permisos y solicitar
      bool userAccepted = await _showPermissionDialog(context, permissionsToRequest);
      if (!userAccepted) {
        return false;
      }

      // Solicitar permisos
      Map<Permission, PermissionStatus> results = {};
      for (Permission permission in permissionsToRequest) {
        results[permission] = await permission.request();
      }

      // Verificar si todos los permisos fueron concedidos
      bool allGranted = results.values.every((status) => status == PermissionStatus.granted);

      if (!allGranted) {
        _showPermissionDeniedDialog(context);
        return false;
      }

      return true;
    } catch (e) {
      print('❌ Error verificando permisos: $e');
      return false;
    }
  }

  /// Mostrar diálogo de solicitud de permisos
  Future<bool> _showPermissionDialog(
    BuildContext context,
    List<Permission> permissions,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.bluetooth, color: Color(0xFF4A90E2)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Permisos Requeridos'),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Para usar la impresora Bluetooth necesitamos los siguientes permisos:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ...permissions.map((permission) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_getPermissionDescription(permission)),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 16),
                Text(
                  'Los permisos se solicitarán automáticamente.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Conceder Permisos'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Obtener descripción amigable del permiso
  String _getPermissionDescription(Permission permission) {
    switch (permission) {
      case Permission.bluetooth:
        return 'Acceso a Bluetooth';
      case Permission.bluetoothConnect:
        return 'Conectar dispositivos Bluetooth';
      case Permission.bluetoothScan:
        return 'Escanear dispositivos Bluetooth';
      case Permission.location:
        return 'Ubicación (requerida para Bluetooth)';
      default:
        return 'Permiso desconocido';
    }
  }

  /// Mostrar diálogo de permisos denegados
  void _showPermissionDeniedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permisos Denegados'),
        content: const Text(
          'No se pueden usar las funciones de impresora Bluetooth sin los permisos necesarios. '
          'Puedes habilitarlos manualmente en Configuración > Aplicaciones > Inventtia Admin > Permisos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
            ),
            child: const Text('Ir a Configuración'),
          ),
        ],
      ),
    );
  }
}
