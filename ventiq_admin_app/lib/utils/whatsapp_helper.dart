import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Utilidades para contactar clientes por WhatsApp desde la app.
///
/// Los teléfonos en `carnavalapp.Usuarios` vienen en formatos mixtos: la gran
/// mayoría son móviles cubanos de 8 dígitos sin prefijo (`54905391`), y una
/// minoría trae ya el formato internacional (`+13052978955`, `+5350005083`).
/// También hay bastante dato basura (`5555555`, `0`, `13123`) que no debe
/// producir un botón de contacto.
class WhatsAppHelper {
  /// Prefijo asumido cuando el número no trae código de país. Los datos de
  /// Carnaval son cubanos (móviles de 8 dígitos que empiezan por 5).
  static const String defaultCountryCode = '53';

  /// Color de marca de WhatsApp.
  static const Color brandColor = Color(0xFF25D366);

  /// Normaliza un teléfono a la forma que espera `wa.me` (solo dígitos, con
  /// código de país y sin `+`). Devuelve `null` cuando el valor no puede ser
  /// un número real — el llamador debe ocultar el botón en ese caso.
  static String? normalizePhone(dynamic raw) {
    if (raw == null) return null;

    var text = raw.toString().trim();
    if (text.isEmpty) return null;

    // Un teléfono guardado como número pierde el `+` y puede llegar como
    // double ("5350005083.0"); recortamos la parte decimal antes de limpiar.
    final asNum = num.tryParse(text);
    if (asNum != null && asNum == asNum.truncate()) {
      text = asNum.toInt().toString();
    }

    final hadPlus = text.startsWith('+');
    var digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    // Prefijo internacional marcado con 00 en vez de +.
    var hasCountryCode = hadPlus;
    if (!hadPlus && digits.startsWith('00')) {
      digits = digits.substring(2);
      hasCountryCode = true;
    }

    // Un número de un solo dígito repetido es dato de prueba, no un contacto.
    // Va antes de anteponer el prefijo: `55555555` dejaría de parecer relleno
    // una vez convertido en `5355555555`.
    if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return null;

    if (!hasCountryCode && digits.length == 8) {
      // Caso dominante: móvil cubano sin código de país. Ojo, un `53` inicial
      // aquí es parte del número (los móviles empiezan por 5), no el prefijo.
      digits = '$defaultCountryCode$digits';
    }

    // E.164: entre 8 y 15 dígitos. Exigimos 10 porque por debajo de eso, ya
    // normalizado, solo quedan los números de relleno tipo 5555555.
    if (digits.length < 10 || digits.length > 15) return null;

    return digits;
  }

  /// `true` si el valor da un número contactable por WhatsApp.
  static bool isContactable(dynamic raw) => normalizePhone(raw) != null;

  /// Abre el chat de WhatsApp con [rawPhone]. Devuelve `false` si el número no
  /// es válido o si no se pudo abrir la app/enlace.
  static Future<bool> openChat(dynamic rawPhone, {String? message}) async {
    final phone = normalizePhone(rawPhone);
    if (phone == null) return false;

    final query =
        (message != null && message.isNotEmpty)
            ? '?text=${Uri.encodeComponent(message)}'
            : '';
    final uri = Uri.parse('https://wa.me/$phone$query');

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// Botón circular verde que abre WhatsApp con el teléfono dado.
///
/// Se auto-oculta (devuelve un widget vacío) cuando el teléfono no es
/// contactable, así el llamador no tiene que validar antes de insertarlo.
class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton({
    Key? key,
    required this.phone,
    this.message,
    this.size = 32,
    this.tooltip,
  }) : super(key: key);

  /// Teléfono crudo tal como viene de la BD.
  final dynamic phone;

  /// Texto pre-cargado en el chat (p. ej. la orden por la que se contacta).
  final String? message;

  /// Diámetro del círculo.
  final double size;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final normalized = WhatsAppHelper.normalizePhone(phone);
    if (normalized == null) return const SizedBox.shrink();

    return Tooltip(
      message: tooltip ?? 'Contactar por WhatsApp',
      child: Material(
        color: WhatsAppHelper.brandColor,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final ok = await WhatsAppHelper.openChat(phone, message: message);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No se pudo abrir WhatsApp'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.chat,
              size: size * 0.55,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
