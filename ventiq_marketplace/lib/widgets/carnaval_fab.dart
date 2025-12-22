import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CarnavalFab extends StatelessWidget {
  const CarnavalFab({super.key});

  Future<void> _handlePress(BuildContext context) async {
    final Uri appUri = Uri.parse(
      'carnavaltienda://carnavaltienda.com/productostore',
    );
    final Uri storeUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.carnaval24&pcampaignid=web_share',
    );

    try {
      // Intentar abrir la app
      // Nota: Para que canLaunchUrl funcione con esquemas personalizados en Android 11+,
      // se debe haber agregado el esquema a <queries> en AndroidManifest.xml
      bool appLaunched = false;
      try {
        if (await launchUrl(appUri, mode: LaunchMode.externalApplication)) {
          appLaunched = true;
        }
      } catch (e) {
        debugPrint('Could not launch app uri directly: $e');
      }

      if (!appLaunched) {
        // Si no se pudo abrir la app, abrir Play Store
        if (await canLaunchUrl(storeUri)) {
          await launchUrl(storeUri, mode: LaunchMode.externalApplication);
        } else {
          try {
            await launchUrl(storeUri, mode: LaunchMode.externalApplication);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No se pudo abrir la tienda de aplicaciones'),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al intentar abrir Carnaval App: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _handlePress(context),
      backgroundColor: Colors.red,
      elevation: 6,
      shape: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(5.0),
        child: Image.asset(
          'assets/logoapp25.png', // Asegúrate de que este asset exista y esté en pubspec.yaml
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
