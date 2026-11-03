import 'package:flutter/material.dart';

import '../../models/home_catalogo.dart';
import '../../services/home_extras_service.dart';
import '../../theme/ventiq_home_theme.dart';
import '../../utils/price_utils.dart';

/// Riel horizontal de productos del Home: «Más vendidos» u «Ofertas».
///
/// Es el mismo lenguaje que las tarjetas del resto del Home (radio 16, borde
/// `border`, sombra suave, foto con degradado de respaldo) pero compacto: el
/// riel no compite con la rejilla de categorías, la complementa.
class RielProductos extends StatelessWidget {
  const RielProductos({
    super.key,
    required this.titulo,
    required this.icono,
    required this.productos,
    required this.onTap,
    this.esOferta = false,
  });

  final String titulo;
  final IconData icono;
  final List<HomeRielProducto> productos;
  final void Function(HomeRielProducto producto) onTap;
  final bool esOferta;

  @override
  Widget build(BuildContext context) {
    if (productos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            VentiqHomeTheme.sectionPadding,
            0,
            VentiqHomeTheme.sectionPadding,
            8,
          ),
          child: Row(
            children: <Widget>[
              Icon(icono, size: 16, color: VentiqHomeTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(titulo, style: VentiqHomeTheme.tituloSeccion),
              ),
              Text(
                '${productos.length}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: VentiqHomeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: VentiqHomeTheme.sectionPadding,
            ),
            itemCount: productos.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int i) {
              return _TarjetaRiel(
                producto: productos[i],
                esOferta: esOferta,
                onTap: () => onTap(productos[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TarjetaRiel extends StatelessWidget {
  const _TarjetaRiel({
    required this.producto,
    required this.esOferta,
    required this.onTap,
  });

  final HomeRielProducto producto;
  final bool esOferta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double? precio =
        esOferta ? (producto.precioOferta ?? producto.precio) : producto.precio;
    final bool oferta = esOferta && producto.tieneOferta;

    return SizedBox(
      width: 138,
      child: Material(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: VentiqHomeTheme.border),
              boxShadow: VentiqHomeTheme.shadowRiel,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  height: 88,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _foto(),
                      if (oferta)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: _badge(
                            '-${producto.porcentajeDescuento?.round() ?? 0}%',
                            VentiqHomeTheme.danger,
                          ),
                        )
                      else if (!esOferta &&
                          (producto.unidadesVendidas ?? 0) > 0)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: _badge(
                            '${PriceUtils.formatQuantity(producto.unidadesVendidas!)} vendidos',
                            VentiqHomeTheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        producto.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: VentiqHomeTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (oferta)
                        Row(
                          children: <Widget>[
                            Text(
                              '\$${PriceUtils.formatAmount(producto.precio!)}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: VentiqHomeTheme.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '\$${PriceUtils.formatAmount(precio!)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: VentiqHomeTheme.danger,
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          precio == null
                              ? '—'
                              : '\$${PriceUtils.formatAmount(precio)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: VentiqHomeTheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _foto() {
    final String? url = producto.imagen;
    if (url == null || url.trim().isEmpty) return _respaldo();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _respaldo(),
      loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? p) {
        return p == null ? child : _respaldo();
      },
    );
  }

  Widget _respaldo() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFEEF2F7), Color(0xFFE0E6ED)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.inventory_2_rounded,
          size: 30,
          color: VentiqHomeTheme.textSecondary.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _badge(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
