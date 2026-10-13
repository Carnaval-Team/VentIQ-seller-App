import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/servicio.dart';
import '../services/resena_service.dart';
import 'net_image.dart';

/// Bloque de identidad del servicio sobre la foto del local.
///
/// La imagen de fondo es la del SERVICIO si la tiene (punto 9 del plan); si no,
/// la del local, y si tampoco hay, el degradado de marca.
///
/// Va como `flexibleSpace` de un `SliverAppBar` y lee el progreso de colapso del
/// propio app bar (`FlexibleSpaceBarSettings`), así que no hay que calcular nada
/// desde el scroll: con el hero abierto se ve el bloque grande (nombre grande,
/// fichas de valoración/precio/modalidad/local) y, al colapsar, el bloque se
/// desvanece y entra el título compacto de la barra.
///
/// El contraste no depende de la foto: tres velos (superior para los iconos de
/// la barra, inferior oscuro para el texto y un tinte de marca) más sombra en el
/// texto. Con una foto blanca, oscura o cargada el bloque se lee igual.
///
/// Se puede usar suelto (sin `SliverAppBar`): sin `FlexibleSpaceBarSettings`
/// asume el estado expandido.
class DetalleHeroHeader extends StatelessWidget {
  const DetalleHeroHeader({
    super.key,
    required this.nombreServicio,
    required this.resenas,
    required this.precioTexto,
    required this.permiteDirecta,
    this.local,
    this.servicio,
  });

  /// Local al que pertenece el servicio; de él salen la foto, el nombre y la
  /// provincia. Si es `null` se pinta el degradado de marca.
  final Local? local;

  /// Servicio mostrado; solo se usa su tipo de actividad como cebecera.
  final Servicio? servicio;

  /// Nombre a mostrar (normalmente `servicio.nombre`).
  final String nombreServicio;

  /// Resumen de reseñas del servicio, para la ficha de valoración.
  final ResumenResenas resenas;

  /// Precio base ya formateado (`"1500 CUP"`) o `null` si no hay precio base.
  final String? precioTexto;

  /// Si el servicio permite reservar sin pasar por la cola.
  final bool permiteDirecta;

  static const List<Shadow> _sombra = [
    Shadow(color: Color(0x99000000), blurRadius: 12, offset: Offset(0, 1)),
  ];

  static String _capitalizar(String palabra) => palabra.isEmpty
      ? palabra
      : '${palabra[0].toUpperCase()}${palabra.substring(1).toLowerCase()}';

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final settings = context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
        final maxE = settings?.maxExtent ?? constraints.maxHeight;
        final minE = settings?.minExtent ?? (kToolbarHeight + topPad);
        final cur = math.min(settings?.currentExtent ?? maxE, maxE);
        final delta = maxE - minE;
        final t = delta <= 0 ? 0.0 : ((maxE - cur) / delta).clamp(0.0, 1.0);

        // El bloque grande desaparece antes de que entre el título de la barra:
        // sin este reparto se verían los dos nombres a la vez a medio colapsar.
        final opacidadBloque = (1 - t / 0.55).clamp(0.0, 1.0);
        final opacidadTitulo = ((t - 0.55) / 0.35).clamp(0.0, 1.0);
        final desplazado = math.max(0.0, maxE - cur);

        // Punto 9: la foto del SERVICIO manda. Sólo si no tiene se cae a la del
        // local, que es lo que se usaba siempre (y hacía que la foto del
        // servicio no se viera nunca en el detalle).
        final fotoServicio = servicio?.foto;
        final fotoLocal = local?.foto;
        final urlFoto = (fotoServicio != null && fotoServicio.isNotEmpty)
            ? fotoServicio
            : (fotoLocal != null && fotoLocal.isNotEmpty ? fotoLocal : null);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Foto con parallax suave: anclada arriba, sube al colapsar.
            Positioned(
              top: -desplazado * 0.25,
              left: 0,
              right: 0,
              height: math.max(maxE, constraints.maxHeight),
              child: urlFoto != null
                  ? NetImage(
                      url: urlFoto,
                      fit: BoxFit.cover,
                      placeholder: () => const _FallbackFoto(),
                      errorWidget: () => const _FallbackFoto(),
                    )
                  : const _FallbackFoto(),
            ),
            // Velo superior: deja legibles los iconos de la barra (volver y
            // favorito) sobre cualquier foto.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xA6000000), Color(0x00000000)],
                    stops: [0.0, 0.38],
                  ),
                ),
              ),
            ),
            // Velo inferior: el que garantiza la lectura del bloque aunque la
            // foto sea blanca. Blanco sobre #07111F da ~18:1 de contraste; con
            // la capa al 88% sobre una foto blanca sigue por encima de 12:1.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x0007111F),
                      Color(0x6607111F),
                      Color(0xE007111F),
                    ],
                    stops: [0.34, 0.66, 1.0],
                  ),
                ),
              ),
            ),
            // Tinte de marca: que cualquier foto case con la paleta.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.primaryDark.withValues(alpha: 0.40),
                      AppTheme.primary.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            if (opacidadBloque > 0)
              Positioned(
                left: 18,
                right: 18,
                bottom: 20,
                child: Opacity(
                  opacity: opacidadBloque,
                  child: _bloqueIdentidad(),
                ),
              ),
            Positioned(
              top: topPad,
              left: 56,
              right: 64,
              height: kToolbarHeight,
              child: Opacity(
                opacity: opacidadTitulo,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    nombreServicio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      shadows: _sombra,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Cebecera + nombre + fichas (valoración, precio, modalidad, local).
  Widget _bloqueIdentidad() {
    final tipo = (servicio?.tipoActividad ?? '').trim();
    final eyebrow = tipo.isEmpty
        ? 'SERVICIO'
        : tipo
              .split(RegExp(r'[_\s]+'))
              .where((w) => w.isNotEmpty)
              .map(_capitalizar)
              .join(' ')
              .toUpperCase();

    final provincia = (local?.provincia ?? '').trim();
    final ubicacion = [
      local?.nombre ?? '',
      provincia,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' · ');

    final fichas = <Widget>[];
    if (resenas.hayDatos) {
      fichas.add(
        _ChipHero(
          icon: Icons.star_rounded,
          colorIcono: const Color(0xFFFFC107),
          texto: '${resenas.promedio.toStringAsFixed(1)} (${resenas.total})',
        ),
      );
    }
    if (precioTexto != null) {
      // Mismo formato que catálogo y favoritos: la etiqueta ya decide si hay
      // precio base (`{}` o 0 no muestran ficha).
      fichas.add(_ChipHero(icon: Icons.sell_outlined, texto: precioTexto!));
    }
    fichas.add(
      _ChipHero(
        icon: permiteDirecta ? Icons.event_available : Icons.playlist_add,
        texto: permiteDirecta ? 'Reserva directa' : 'Lista de espera',
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          nombreServicio,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            // 21 en vez de 25: en un movil de 360px el nombre partia en dos
            // lineas casi siempre y el bloque se comia el hero entero.
            fontSize: 21,
            height: 1.12,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            shadows: _sombra,
          ),
        ),
        // 14 y no 12: con las fichas pegadas al nombre el bloque se veia apiñado
        // (el nombre es de dos lineas mas veces de las que parece).
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...fichas,
            if (ubicacion.isNotEmpty)
              _ChipHero(
                icon: Icons.place_outlined,
                texto: ubicacion,
                maxAncho: 250,
              ),
          ],
        ),
      ],
    );
  }
}

/// Ficha translúcida sobre la foto del hero (valoración, precio, local...).
class _ChipHero extends StatelessWidget {
  const _ChipHero({
    required this.icon,
    required this.texto,
    this.colorIcono = Colors.white,
    this.maxAncho = 220,
  });

  final IconData icon;
  final String texto;
  final Color colorIcono;
  final double maxAncho;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorIcono),
          const SizedBox(width: 5),
          // Flexible: en un móvil estrecho la ficha se encoge con elipsis en vez
          // de desbordar la fila; `maxAncho` solo la limita cuando sobra sitio.
          // (Con `ConstrainedBox` a secas, un nombre de local largo desbordaba
          // 11px a 320px de ancho.)
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxAncho),
              child: Text(
                texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  shadows: DetalleHeroHeader._sombra,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Degradado de marca cuando el local no tiene foto (o falla la carga).
class _FallbackFoto extends StatelessWidget {
  const _FallbackFoto();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
      ),
      child: Center(
        child: Icon(Icons.storefront_outlined, size: 64, color: Colors.white24),
      ),
    );
  }
}
