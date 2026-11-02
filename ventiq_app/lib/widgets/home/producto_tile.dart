import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/home_catalogo.dart';
import '../../theme/ventiq_home_theme.dart';

/// Fila de producto dentro del drawer.
///
/// Dos acciones separadas, con gestos separados —igual que en las tarjetas de
/// categoría—:
///
///  * **tocar la fila** abre el detalle del producto;
///  * **tocar «+»** suma una unidad a la venta sin salir del drawer.
///
/// Esa segunda acción es la que hace que el drawer sirva para vender de verdad
/// y no solo para mirar: en un servicentro, «Combustibles → Especial 95 → +» son
/// dos toques y ya está en la cuenta.
class ProductoTile extends StatelessWidget {
  const ProductoTile({
    super.key,
    required this.producto,
    required this.onTap,
    this.onAgregar,
    this.mostrarSku = false,
    this.atenuarImagenes = false,
    this.subtitulo,
    this.heroTag,
  });

  final HomeProducto producto;

  /// Abre el detalle.
  final VoidCallback onTap;

  /// Suma una unidad a la venta. `null` = sin botón (p. ej. sin stock).
  final VoidCallback? onAgregar;

  final bool mostrarSku;

  /// Modo ahorro de datos: no se descarga la foto.
  final bool atenuarImagenes;

  /// Línea extra bajo el nombre (p. ej. la categoría, en los resultados de la
  /// búsqueda global, donde no hay contexto de categoría alrededor).
  final String? subtitulo;

  /// Tag de `Hero` para la miniatura (el detalle usa el mismo para la
  /// transición de imagen). `null` = sin animación.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final bool disponible = producto.disponible;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VentiqHomeTheme.sectionPadding,
        0,
        VentiqHomeTheme.sectionPadding,
        8,
      ),
      child: Material(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: VentiqHomeTheme.border),
            ),
            child: Row(
              children: <Widget>[
                if (heroTag != null)
                  Hero(
                    tag: heroTag!,
                    child: _Miniatura(
                      url: producto.imagen,
                      atenuar: atenuarImagenes,
                    ),
                  )
                else
                  _Miniatura(url: producto.imagen, atenuar: atenuarImagenes),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        producto.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          // Un agotado se sigue viendo, pero se nota que no se
                          // puede vender: en un TPV es peor esconderlo que
                          // mostrarlo apagado.
                          color:
                              disponible
                                  ? VentiqHomeTheme.textPrimary
                                  : VentiqHomeTheme.textSecondary,
                        ),
                      ),
                      if (subtitulo != null &&
                          subtitulo!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 1),
                        Text(
                          subtitulo!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: VentiqHomeTheme.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 3),
                      // `Wrap` y no `Row`: con SKU + ELAB + «Elaborable: N» los
                      // chips no caben en una fila de móvil y desbordaban.
                      Wrap(
                        spacing: 0,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          if (producto.esElaborado || producto.esServicio)
                            _Etiqueta(
                              texto: producto.esServicio ? 'SERVICIO' : 'ELAB',
                              color: VentiqHomeTheme.primary,
                            ),
                          if (mostrarSku && (producto.sku ?? '').isNotEmpty)
                            _Etiqueta(
                              texto: producto.sku!,
                              color: VentiqHomeTheme.textSecondary,
                            ),
                          _EtiquetaStock(
                            disponible: disponible,
                            cantidad: producto.stock,
                            esServicio: producto.esServicio,
                            esElaborado: producto.esElaborado,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      producto.precio.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: VentiqHomeTheme.primary,
                      ),
                    ),
                    if (onAgregar != null) ...<Widget>[
                      const SizedBox(height: 4),
                      _BotonAgregar(onTap: onAgregar!),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Miniatura extends StatelessWidget {
  const _Miniatura({this.url, this.atenuar = false});

  final String? url;
  final bool atenuar;

  @override
  Widget build(BuildContext context) {
    final bool hayFoto = !atenuar && url != null && url!.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 48,
        height: 48,
        child:
            hayFoto
                ? Image.network(
                  url!,
                  fit: BoxFit.cover,
                  cacheWidth: 96,
                  loadingBuilder:
                      (_, Widget child, ImageChunkEvent? p) =>
                          p == null ? child : const _SinFoto(),
                  errorBuilder: (_, __, ___) => const _SinFoto(),
                )
                : const _SinFoto(),
      ),
    );
  }
}

class _SinFoto extends StatelessWidget {
  const _SinFoto();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: VentiqHomeTheme.surface,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 18,
        color: VentiqHomeTheme.textSecondary,
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _EtiquetaStock extends StatelessWidget {
  const _EtiquetaStock({
    required this.disponible,
    required this.cantidad,
    required this.esServicio,
    this.esElaborado = false,
  });

  final bool disponible;
  final double cantidad;
  final bool esServicio;

  /// Un elaborado no tiene «stock» propio: se vende lo que se puede preparar
  /// con su materia prima, así que la etiqueta lo dice con esas palabras.
  final bool esElaborado;

  @override
  Widget build(BuildContext context) {
    if (esServicio) return const SizedBox.shrink();

    final bool hay = esElaborado ? cantidad > 0 : disponible;
    final String texto =
        esElaborado
            ? (cantidad > 0
                ? 'Elaborable: ${_corta(cantidad)}'
                : 'Sin materia prima')
            : (disponible ? 'Stock: ${_corta(cantidad)}' : 'Agotado');
    final Color color = hay ? VentiqHomeTheme.success : VentiqHomeTheme.danger;

    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }

  /// Sin decimales cuando no aportan: "Stock: 12", no "Stock: 12.0".
  static String _corta(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _BotonAgregar extends StatelessWidget {
  const _BotonAgregar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Agregar a la venta',
      child: Material(
        color: VentiqHomeTheme.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          child: const SizedBox(
            width: 32,
            height: 32,
            child: Icon(Icons.add_rounded, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
