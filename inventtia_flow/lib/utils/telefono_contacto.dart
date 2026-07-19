import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';

/// Diálogo para contactar por llamada o WhatsApp (web y APK).
class TelefonoContacto {
  TelefonoContacto._();

  /// Solo dígitos; útil para WhatsApp (`wa.me`).
  static String soloDigitos(String telefono) =>
      telefono.replaceAll(RegExp(r'\D'), '');

  static Future<void> mostrarOpciones(
    BuildContext context,
    String telefono,
  ) async {
    final numero = telefono.trim();
    if (numero.isEmpty || numero == '-') return;

    final opcion = await showModalBottomSheet<_ContactoOpcion>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Contactar cliente',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  numero,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1A0D47A1),
                    child: Icon(Icons.phone, color: AppTheme.primary),
                  ),
                  title: const Text('Llamar'),
                  subtitle: Text(
                    kIsWeb
                        ? 'Abrir el marcador o la app de llamadas'
                        : 'Iniciar una llamada telefónica',
                  ),
                  onTap: () =>
                      Navigator.pop(ctx, _ContactoOpcion.llamar),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0x1A25D366),
                    child: Icon(Icons.chat, color: Color(0xFF25D366)),
                  ),
                  title: const Text('WhatsApp'),
                  subtitle: const Text('Abrir chat con este número'),
                  onTap: () =>
                      Navigator.pop(ctx, _ContactoOpcion.whatsapp),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (opcion == null || !context.mounted) return;

    switch (opcion) {
      case _ContactoOpcion.llamar:
        await _abrirUri(Uri(scheme: 'tel', path: numero));
      case _ContactoOpcion.whatsapp:
        final digitos = soloDigitos(numero);
        if (digitos.isEmpty) return;
        await _abrirUri(Uri.parse('https://wa.me/$digitos'));
    }
  }

  static Future<void> _abrirUri(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri);
      } catch (_) {}
    }
  }
}

enum _ContactoOpcion { llamar, whatsapp }
