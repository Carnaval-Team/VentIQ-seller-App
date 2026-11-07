import 'package:flutter/material.dart';

import '../../theme/ventiq_home_theme.dart';

/// Placeholder con pulso, para sustituir a `shimmer` sin traer la dependencia.
///
/// Son ~30 líneas: un `AnimationController` que late entre 0.45 y 1.0 de opacidad
/// sobre un bloque del color de borde. Suficiente para que la espera se lea como
/// "esto está cargando" en vez de como "aquí no hay nada", que es lo único que
/// tiene que hacer un skeleton.
///
/// Respeta `MediaQuery.disableAnimationsOf`: con movimiento reducido se queda
/// fijo en el tono medio, sin latir.
class VentiqSkeleton extends StatefulWidget {
  const VentiqSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<VentiqSkeleton> createState() => _VentiqSkeletonState();
}

class _VentiqSkeletonState extends State<VentiqSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controlador = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _controlador.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget bloque = DecoratedBox(
      decoration: BoxDecoration(
        color: VentiqHomeTheme.border,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
      child: SizedBox(width: widget.width, height: widget.height),
    );

    if (VentiqHomeTheme.reduceMotion(context)) {
      return Opacity(opacity: 0.7, child: bloque);
    }

    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(
        CurvedAnimation(parent: _controlador, curve: Curves.easeInOut),
      ),
      child: bloque,
    );
  }
}

/// Skeleton con la forma exacta de una `TarjetaExploracion`.
///
/// No es decorativo: al tener el mismo alto y radio que la tarjeta real, la
/// rejilla no salta cuando llegan los datos.
class VentiqSkeletonTarjeta extends StatelessWidget {
  const VentiqSkeletonTarjeta({super.key, this.alto = VentiqHomeTheme.cardExtentBase});

  final double alto;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: alto,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusCard),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              VentiqSkeleton(width: 68, height: 18, radius: 8),
              Spacer(),
              VentiqSkeleton(width: 32, height: 32, radius: 10),
            ],
          ),
          Spacer(),
          VentiqSkeleton(width: 110, height: 16, radius: 6),
          SizedBox(height: 6),
          VentiqSkeleton(width: 70, height: 11, radius: 6),
        ],
      ),
    );
  }
}

/// Rejilla de skeletons con la forma de la grilla real de categorías.
class VentiqSkeletonRejilla extends StatelessWidget {
  const VentiqSkeletonRejilla({super.key, this.cantidad = 4, this.columnas = 2});

  final int cantidad;
  final int columnas;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: VentiqHomeTheme.sectionPadding,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cantidad,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnas,
        mainAxisSpacing: VentiqHomeTheme.gridSpacing,
        crossAxisSpacing: VentiqHomeTheme.gridSpacing,
        mainAxisExtent: VentiqHomeTheme.cardExtent(context),
      ),
      itemBuilder: (_, __) => const VentiqSkeletonTarjeta(),
    );
  }
}
