import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';

class CarnavalFab extends StatelessWidget {
  const CarnavalFab({super.key});

  /// Muestra el diálogo informativo antes de redirigir
  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.paddingL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con logo o icono
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  size: 32,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 16),

              // Título
              const Text(
                'Compra en Carnaval App',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Contenido
              // Contenido
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(
                      text:
                          'Algunos de los productos que aparecen en el catálogo se pueden comprar en línea a través de Carnaval App con ',
                    ),
                    TextSpan(
                      text: 'envío a domicilio gratis',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const TextSpan(
                      text:
                          '.\n\nEl precio puede diferir por temas logísticos y de preparación hasta en un 5%.',
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Botones
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: const BorderSide(color: AppTheme.textSecondary),
                      ),
                      child: const Text(
                        'Cerrar',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Cerrar diálogo
                        _launchCarnavalApp(context); // Ejecutar lógica
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.errorColor, // Botón rojo
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Ir a comprar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchCarnavalApp(BuildContext context) async {
    bool isIOS;
    bool navegador = false;
    try {
      isIOS = Platform.isIOS;
    } catch (e) {
      isIOS = false;
      navegador = true;
    }

    // URIs para abrir la app
    final Uri appUri = Uri.parse(
      'carnavaltienda://carnavaltienda.com/productostore',
    );

    // URIs para las tiendas
    final Uri playStoreUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.carnaval24&pcampaignid=web_share',
    );
    final Uri appStoreUri = Uri.parse(
      'https://apps.apple.com/us/app/carnaval-tienda/id6742862060',
    );

    final Uri storeUri = isIOS ? appStoreUri : playStoreUri;

    try {
      // Intentar abrir la app
      bool appLaunched = false;
      try {
        if (await launchUrl(navegador ? playStoreUri: appUri , mode: LaunchMode.externalApplication)) {
          appLaunched = true;
        }
      } catch (e) {
        debugPrint('Could not launch app uri directly: $e');
      }

      if (!appLaunched) {
        // Si no se pudo abrir la app, abrir la tienda correspondiente
        if (await canLaunchUrl(storeUri)) {
          await launchUrl(storeUri, mode: LaunchMode.externalApplication);
        } else {
          // Fallback final
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
      onPressed: () => _showInfoDialog(context),
      backgroundColor: Colors.red,
      elevation: 6,
      shape: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(5.0),
        child: Image.asset('assets/logoapp25.png', fit: BoxFit.contain),
      ),
    );
  }
}
