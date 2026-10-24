import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/home_features.dart';
import '../tutorial/tutorial_anchor.dart';

/// Rejilla de acceso rápido del Home del cliente: cuatro tarjetas grandes con su
/// degradado, su chip de contexto y su icono.
///
/// Sustituye al riel de chips de «Categorías principales». El riel obligaba a
/// deslizar en horizontal para descubrir que existían más rubros y no decía
/// cuánto había dentro de cada uno; esta rejilla enseña de un vistazo los cuatro
/// caminos del catálogo (categorías, servicios, establecimientos y los más
/// populares) y el número real de rubros activos.
///
/// El widget es **tonto a propósito**: no pide datos ni navega, recibe los
/// callbacks y el contador ya resueltos. Así se puede probar sin Supabase y el
/// Home decide qué abre cada tarjeta (una sola fuente de verdad:
/// `ExploracionNavegacion`).
class ExploracionRapidaGrid extends StatelessWidget {
  const ExploracionRapidaGrid({
    super.key,
    required this.categoriasActivas,
    required this.onCategorias,
    required this.onServicios,
    required this.onEstablecimientos,
    required this.onMasPopulares,
    this.anchorId = 'home_exploracion',
    this.trailingAnchorId = 'home_ver_todo',
    this.categoriasAnchorId = 'home_card_categorias',
  });

  /// Cuántas categorías raíz activas tiene el nomenclador. Es el número del chip
  /// «N ACTIVAS»; con 0 (nomenclador aún sin cargar o migración 47 sin aplicar)
  /// el chip dice «TODOS LOS RUBROS» en vez de un «0 ACTIVAS» que parece un error.
  final int categoriasActivas;

  final VoidCallback onCategorias;
  final VoidCallback onServicios;
  final VoidCallback onEstablecimientos;
  final VoidCallback onMasPopulares;

  /// Anclas del tutorial. `null` = sin ancla.
  final String? anchorId;
  final String? trailingAnchorId;
  final String? categoriasAnchorId;

  @override
  Widget build(BuildContext context) {
    // El alto de cada tarjeta se fija con `mainAxisExtent` y no con un
    // `childAspectRatio`: con texto al 130 % un ratio fijo desborda en pantallas
    // de 320 pt, y aquí el contenido (chip + título + subtítulo) tiene una altura
    // mínima conocida. Se escala con el texto del sistema.
    final escala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final alto = 122 * escala;

    final tarjetas = <Widget>[
      TarjetaExploracion(
        chip: categoriasActivas > 0
            ? '$categoriasActivas ACTIVAS'
            : 'TODOS LOS RUBROS',
        titulo: 'Categorías',
        subtitulo: 'Todos los rubros',
        icono: Icons.grid_view_rounded,
        colores: const [AppTheme.exploracionIndigo, AppTheme.exploracionIndigoDark],
        onTap: onCategorias,
        anchorId: categoriasAnchorId,
      ),
      TarjetaExploracion(
        chip: 'CATÁLOGO',
        titulo: 'Servicios',
        subtitulo: 'Explorar catálogo',
        icono: Icons.storefront_rounded,
        colores: const [AppTheme.exploracionTeal, AppTheme.exploracionTealDark],
        onTap: onServicios,
      ),
      TarjetaExploracion(
        chip: 'LOCALES',
        titulo: 'Establecimientos',
        // «Cerca de ti» solo cuando de verdad hay distancias. Hoy
        // `HomeFeatures.distancia` está apagado (no hay coordenadas ni ubicación
        // del cliente), así que prometer cercanía sería inventar un dato.
        subtitulo: HomeFeatures.distancia ? 'Cerca de ti' : 'Todos los locales',
        icono: Icons.store_mall_directory_rounded,
        colores: const [AppTheme.exploracionNavy, AppTheme.exploracionNavyDark],
        onTap: onEstablecimientos,
      ),
      TarjetaExploracion(
        chip: 'TOP 10',
        titulo: 'Más populares',
        // El ranking agrega la semana en curso (`date_trunc('week')`): decir
        // «hoy» sería mentir sobre la ventana del dato.
        subtitulo: 'Tendencias de la semana',
        icono: Icons.star_rounded,
        colores: const [AppTheme.exploracionCoral, AppTheme.exploracionCoralDark],
        onTap: onMasPopulares,
      ),
    ];

    final rejilla = GridView(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: alto,
      ),
      children: tarjetas,
    );

    final actual = anchorId;
    final contenido = actual == null
        ? rejilla
        : TutorialAnchor(id: actual, child: rejilla);

    // Título con el mismo peso visual que el resto de secciones del Home, pero
    // en mayúsculas y con más aire entre letras: es un rótulo de bloque, no un
    // titular de contenido.
    final accion = TextButton(
      onPressed: onServicios,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text(
        'Ver catálogo ›',
        style: TextStyle(
          color: AppTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final accionAnclada = trailingAnchorId == null
        ? accion
        : TutorialAnchor(id: trailingAnchorId!, child: accion);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'EXPLORACIÓN RÁPIDA',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
                accionAnclada,
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: contenido,
          ),
        ],
      ),
    );
  }
}

/// Una tarjeta de la rejilla: degradado, chip de contexto, icono, título,
/// subtítulo y —opcionalmente— una acción en el pie.
class TarjetaExploracion extends StatelessWidget {
  const TarjetaExploracion({
    super.key,
    required this.chip,
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.colores,
    required this.onTap,
    this.anchorId,
    this.accionEtiqueta,
    this.onAccion,
  });

  final String chip;
  final String titulo;
  final String subtitulo;
  final IconData icono;

  /// Dos colores: inicio (arriba-izquierda) y fin (abajo-derecha).
  final List<Color> colores;

  final VoidCallback onTap;
  final String? anchorId;

  /// Acción secundaria del pie de la tarjeta («Ver todos»).
  ///
  /// `null` = la tarjeta no lleva pie, que es como la usa la rejilla del Home.
  /// Las carpetas de categorías sí lo llevan: tocar la tarjeta abre la carpeta y
  /// «Ver todos» salta al listado filtrado —dos destinos distintos sin
  /// mezclarlos en un solo toque, como en el resto de la app—.
  final String? accionEtiqueta;

  /// Con `null` el pie se pinta apagado y no responde: mantiene el alto de la
  /// tarjeta sin ofrecer un toque que no lleva a ningún sitio.
  final VoidCallback? onAccion;

  @override
  Widget build(BuildContext context) {
    final tarjeta = ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colores,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // Marca de agua: da profundidad sin competir con el texto.
                Positioned(
                  right: -10,
                  bottom: -14,
                  child: Icon(
                    icono,
                    size: 76,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(child: _Chip(texto: chip)),
                          const SizedBox(width: 6),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Icon(icono, size: 17, color: Colors.white),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontSize: 12,
                          height: 1.15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (accionEtiqueta != null) ...[
                        const SizedBox(height: 7),
                        _AccionTarjeta(
                          etiqueta: accionEtiqueta!,
                          onTap: onAccion,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final actual = anchorId;
    return actual == null
        ? tarjeta
        : TutorialAnchor(id: actual, child: tarjeta);
  }
}

/// Etiqueta pequeña en mayúsculas del ángulo superior izquierdo.
class _Chip extends StatelessWidget {  const _Chip({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// Acción del pie de una tarjeta («Ver todos ›»).
///
/// Tiene su propio gesto para que no se confunda con el toque de la tarjeta: el
/// usuario pidió expresamente que abrir la carpeta y ver el listado sean dos
/// acciones distintas.
class _AccionTarjeta extends StatelessWidget {
  const _AccionTarjeta({required this.etiqueta, this.onTap});

  final String etiqueta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final activo = onTap != null;
    final pastilla = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: activo ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: activo ? 0.24 : 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: activo ? 0.95 : 0.50),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (activo) ...[
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right_rounded,
              size: 13,
              color: Colors.white,
            ),
          ],
        ],
      ),
    );

    if (!activo) return pastilla;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: pastilla,
    );
  }
}