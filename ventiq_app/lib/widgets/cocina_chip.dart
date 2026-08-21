import 'package:flutter/material.dart';

import '../models/product.dart';

/// Chip que identifica la estación de cocina de un plato y su disponibilidad.
///
/// Solo se pinta para productos que van a cocina (`product.vaACocina`); un
/// producto de barra devuelve `SizedBox.shrink()` y la tarjeta queda igual que
/// antes.
///
/// Sigue el patrón de código de colores que usan los KDS de la industria
/// (Lightspeed, Toast): un color por tipo de flujo, para que el vendedor
/// distinga de un vistazo sin leer.
///
///   por_tanda  ámbar  → porciones ya hechas, se sirven de inmediato
///   al_pedido  índigo → hay que cocinarlo, tarda
///   agotado    rojo   → no se puede pedir
class CocinaChip extends StatelessWidget {
  const CocinaChip({
    super.key,
    required this.product,
    this.compacto = false,
    this.mostrarNombreCocina = true,
  });

  final Product product;

  /// Versión reducida: solo icono y disponibilidad, sin nombre de estación.
  /// Para listas densas donde no cabe el texto completo.
  final bool compacto;

  final bool mostrarNombreCocina;

  @override
  Widget build(BuildContext context) {
    if (!product.vaACocina) return const SizedBox.shrink();

    final agotado = !product.ilimitado && product.cantidadReal <= 0;

    final Color color;
    final IconData icono;

    if (agotado) {
      color = Colors.red.shade600;
      icono = Icons.block;
    } else if (product.esPorTanda) {
      color = Colors.amber.shade800;
      icono = Icons.inventory_2_outlined;
    } else {
      color = Colors.indigo.shade500;
      icono = Icons.outdoor_grill_outlined;
    }

    final etiqueta = product.etiquetaDisponibilidad;
    final nombreCocina = product.cocina;
    final mostrarNombre =
        mostrarNombreCocina &&
        !compacto &&
        nombreCocina != null &&
        nombreCocina.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              mostrarNombre ? '$nombreCocina · $etiqueta' : etiqueta,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge mínimo con el modo de elaboración, para cabeceras y detalles.
///
/// Explica al vendedor *por qué* la disponibilidad es la que es: un plato por
/// tanda se agota aunque quede materia prima, y uno al pedido tarda.
class ModoElaboracionBadge extends StatelessWidget {
  const ModoElaboracionBadge({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    if (!product.vaACocina) return const SizedBox.shrink();

    final esPorTanda = product.esPorTanda;
    final color = esPorTanda ? Colors.amber.shade800 : Colors.indigo.shade500;

    return Tooltip(
      message: esPorTanda
          ? 'Se sirve de las porciones ya preparadas en la cocina'
          : 'Se prepara al momento de pedirlo',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          esPorTanda ? 'POR TANDA' : 'AL PEDIDO',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
