import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/tutorial_service.dart';
import 'tutorial_controller.dart';
import 'tutorial_destino.dart';
import 'tutorial_navegacion.dart';
import 'tutorial_paso.dart';

/// Guiones del tutorial guiado de venta.
///
/// Cada paso apunta a un `TutorialAnchor` colocado en la vista real. El
/// controlador navega al destino del paso cuando el ancla aún no está montada y
/// la burbuja se ancla al hueco del elemento (overlay con foco).
class TutorialFlujos {
  TutorialFlujos._();

  // ── Venta normal (mostrador / tienda) ──────────────────────────────────
  static const List<TutorialPaso> pasosNormal = <TutorialPaso>[
    TutorialPaso(
      id: 'home_buscar',
      titulo: 'Busca el producto',
      mensaje:
          'Escribe el nombre o toca una categoría. El buscador está siempre '
          'visible para no perder tiempo.',
      destino: TutorialDestino.home,
    ),
    TutorialPaso(
      id: 'home_chips',
      titulo: 'Filtros rápidos',
      mensaje:
          '«Solo con stock» te deja ver únicamente lo que puedes vender ahora '
          'mismo. El chip «Tutorial» vuelve a abrir este recorrido.',
    ),
    TutorialPaso(
      id: 'home_categorias',
      titulo: 'Toca una categoría',
      mensaje:
          'Las categorías muestran cuántos productos tienen. Las destacadas van '
          'primero y el resto está en «Tienda».',
    ),
    TutorialPaso(
      id: 'preorder_footer',
      titulo: 'Revisa y envía la orden',
      mensaje:
          'Aquí ves el total, eliges la forma de pago y creas la orden. El stock '
          'se descuenta al confirmar.',
      destino: TutorialDestino.preorder,
      posicion: TutorialPosicion.arriba,
    ),
  ];

  // ── Restaurante / cocina ───────────────────────────────────────────────
  static const List<TutorialPaso> pasosRestaurante = <TutorialPaso>[
    TutorialPaso(
      id: 'mesas_resumen',
      titulo: 'Tu salón de un vistazo',
      mensaje:
          'El anillo y los contadores muestran ocupación, mesas libres y cuentas '
          'activas. Los colores te dicen el estado de cada mesa.',
      destino: TutorialDestino.mesas,
    ),
    TutorialPaso(
      id: 'mesas_primera',
      titulo: 'Toca una mesa',
      mensaje:
          'Abre la cuenta del comensal. Si la mesa solo tiene una cuenta, entra '
          'directo para atenderla sin pasos de más.',
    ),
    TutorialPaso(
      id: 'mesa_agregar',
      titulo: 'Añade los productos',
      mensaje:
          'Desde la mesa abres la cuenta y añades platos y bebidas. Los '
          'elaborados descuentan sus ingredientes y la cocina recibe la comanda.',
      destino: TutorialDestino.mesaDetalle,
    ),
    TutorialPaso(
      id: 'cuenta_cobrar',
      titulo: 'Cobra y libera la mesa',
      mensaje:
          'Cobra la cuenta completa o dividida. Al cerrarla, la mesa vuelve a '
          'quedar libre para el siguiente cliente.',
      destino: TutorialDestino.cuentaMesa,
      posicion: TutorialPosicion.arriba,
    ),
  ];

  static void iniciarVenta(
    BuildContext context, {
    required bool restaurante,
    required String uuidUsuario,
  }) {
    final NavigatorState nav = Navigator.of(context);
    final List<TutorialPaso> pasos =
        restaurante ? pasosRestaurante : pasosNormal;

    TutorialController.instance.iniciar(
      pasos,
      flujoId: restaurante ? 'venta_restaurante' : 'venta_normal',
      navegador:
          (TutorialDestino destino) => TutorialNavegacion.ir(nav, destino),
      alCompletar: () => TutorialService.marcarVisto(uuidUsuario, restaurante),
      alOmitir: () => TutorialService.marcarOmitido(uuidUsuario, restaurante),
    );
  }
}

/// Arranque automático del tutorial: una vez por usuario y modo.
///
/// Se llama al terminar de pintar el Home y también desde Mesas (un usuario de
/// restaurante puede caer directo ahí sin pasar por el Home).
class TutorialAutoStart {
  TutorialAutoStart._();

  static bool _intentado = false;

  /// Devuelve `true` si el tutorial quedó visible (para no encadenar otro
  /// diálogo encima, como el changelog).
  static Future<bool> intentar(
    BuildContext context, {
    required bool restaurante,
  }) async {
    if (_intentado) return false;
    _intentado = true;

    if (TutorialController.instance.activo) return true;

    final String uuid = Supabase.instance.client.auth.currentUser?.id ?? '';
    if (uuid.isEmpty) return false;
    if (!await TutorialService.debeMostrar(uuid, restaurante)) return false;
    if (!context.mounted) return false;

    // Un respiro para que la pantalla esté pintada y las anclas registradas.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!context.mounted) return false;

    TutorialFlujos.iniciarVenta(
      context,
      restaurante: restaurante,
      uuidUsuario: uuid,
    );
    return true;
  }

  /// Para tests o para relanzar el tutorial desde ajustes.
  static void reiniciarIntento() {
    _intentado = false;
  }
}
