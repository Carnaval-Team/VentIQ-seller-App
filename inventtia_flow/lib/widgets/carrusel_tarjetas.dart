import 'package:flutter/material.dart';

/// Carrusel de tarjetas anchas cuya **primera tarjeta arranca alineada con el
/// título de su sección**.
///
/// POR QUE EXISTE
///   Un `PageView` con `viewportFraction < 1` **centra** la página y añade por
///   su cuenta un margen a la izquierda de `(1 - viewportFraction) / 2 × ancho`.
///   Con `viewportFraction: 0.86` y un móvil de 360 eso son ~25 px: sumados al
///   padding de 16 de la primera tarjeta, la tarjeta arrancaba en ~41 px
///   —debajo de la "a" de "Espacio patrocinado"— mientras el resto de secciones
///   del Home arrancan en 16, debajo de la "E" del título.
///
///   `padEnds: false` quita ese margen implícito. Lo que queda es una regla
///   explícita y visible: [paddingExterior] en los extremos del carrusel y
///   [separacion] entre tarjetas.
///
/// Se extrajo del Home a propósito: así la alineación se puede medir en un test
/// (`test/carrusel_tarjetas_test.dart`) en vez de quedar como un detalle
/// invisible en una revisión de código.
class CarruselTarjetas extends StatelessWidget {
  const CarruselTarjetas({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.alto = 176,
    this.paddingExterior = 16,
    this.separacion = 5,
    this.onPageChanged,
    this.physics,
  });

  final PageController controller;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Alto de la fila de tarjetas. El `PageView` necesita un alto finito.
  final double alto;

  /// Margen izquierdo de la primera tarjeta y derecho de la última. Coincide con
  /// el padding horizontal con el que se pintan los títulos de sección.
  final double paddingExterior;

  /// Hueco entre tarjetas (el borde de asomo de la siguiente).
  final double separacion;

  final ValueChanged<int>? onPageChanged;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: alto,
      child: PageView.builder(
        controller: controller,
        physics: physics,
        padEnds: false,
        itemCount: itemCount,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(
            left: index == 0 ? paddingExterior : separacion,
            right: index == itemCount - 1 ? paddingExterior : separacion,
          ),
          child: itemBuilder(context, index),
        ),
      ),
    );
  }
}
