import 'package:flutter/material.dart';

import '../../controllers/home_controller.dart';
import '../../models/home_catalogo.dart';
import '../../theme/ventiq_home_theme.dart';
import '../../utils/categoria_gradiente.dart';
import '../../utils/categoria_icono.dart';
import 'home_estado_vacio.dart';
import 'home_hero_header.dart';
import 'home_seccion_titulo.dart';
import 'tarjeta_exploracion.dart';
import 'tienda_card.dart';
import 'ventiq_skeleton.dart';
import '../../tutorial/tutorial_anchor.dart';

/// El contenido del Home, **sin `Scaffold` y sin servicios**.
///
/// Recibe datos y devuelve gestos. Esa separación no es ceremonia: el armazón
/// de la pantalla (`AppBottomNavigation`, `ConnectionStatusWidget`, el FAB)
/// construye servicios que leen `Supabase.instance` al crearse, así que
/// cualquier test que monte la pantalla entera arrastra media app. Este widget
/// se prueba solo, y el armazón se prueba cuando se pueda.
///
/// Nada de aquí hace red: todo entra por parámetros.
class HomeCatalogoView extends StatelessWidget {
  const HomeCatalogoView({
    super.key,
    required this.saludo,
    required this.estado,
    required this.catalogo,
    required this.onTapCategoria,
    required this.onTapTienda,
    required this.onAbrirListado,
    required this.onRefrescar,
    this.subtitulo,
    this.estadoConexion,
    this.acciones = const <Widget>[],
    this.buscador,
    this.chips,
    this.rieles = const <Widget>[],
    this.nombreTienda = 'Tienda',
    this.imagenTienda,
    this.contenidoAlternativo,
  });

  final String saludo;
  final String? subtitulo;

  /// Estado online/offline. Va en la esquina inferior derecha del hero, debajo
  /// de [acciones].
  final Widget? estadoConexion;

  /// Huecos derechos del hero (escáner, campana...).
  final List<Widget> acciones;

  /// El buscador. Es obligatorio en la práctica: el requisito es que esté
  /// siempre visible.
  final Widget? buscador;

  final Widget? chips;

  /// Rieles extra («Ofertas», «Más vendidos»). El armazón los pinta al final,
  /// después de las categorías: primero el catálogo, luego las recomendaciones.
  final List<Widget> rieles;

  /// Nombre de la tienda para la tarjeta de agrupación (D2). Por defecto,
  /// «Tienda»; el armazón lo resuelve de `app_dat_tienda`.
  final String nombreTienda;

  /// Foto del local para la tarjeta de agrupación (D2). Opcional y
  /// best-effort: `null` deja la tarjeta con su icono, como siempre.
  ///
  /// La resuelve el armazón y entra por parámetro: este widget no lee
  /// preferencias ni hace red (ver la nota de la clase).
  final String? imagenTienda;

  /// Lo que se pinta en vez del catálogo cuando hay una búsqueda activa.
  final Widget? contenidoAlternativo;

  final HomeEstado estado;
  final HomeCatalogo catalogo;

  /// Toca la tarjeta: abre el drawer.
  final void Function(HomeCategoria categoria) onTapCategoria;

  /// Toca el pie "Ver todos": va al listado de productos, **sin** drawer.
  final void Function(HomeCategoria categoria) onAbrirListado;

  final VoidCallback onTapTienda;
  final VoidCallback onRefrescar;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: HomeHeroHeader(
            saludo: saludo,
            subtitulo: subtitulo,
            estadoConexion: estadoConexion,
            acciones: acciones,
            buscador: buscador,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (contenidoAlternativo != null)
          SliverToBoxAdapter(child: contenidoAlternativo)
        else ...<Widget>[
          if (chips != null) SliverToBoxAdapter(child: chips),
          // Las categorías van PRIMERO: son el punto de entrada del Home. Los
          // rieles de producto («Ofertas», «Más vendidos») son un extra y van
          // después del catálogo, no delante de él.
          ..._sliversCatalogo(context),
          if (rieles.isNotEmpty) ...<Widget>[
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverToBoxAdapter(child: Column(children: rieles)),
          ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  List<Widget> _sliversCatalogo(BuildContext context) {
    switch (estado) {
      case HomeEstado.inicial:
      case HomeEstado.cargando:
        return <Widget>[
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
          SliverToBoxAdapter(
            child: VentiqSkeletonRejilla(columnas: columnasDe(context)),
          ),
        ];

      case HomeEstado.error:
        return <Widget>[
          SliverToBoxAdapter(child: HomeEstadoError(onReintentar: onRefrescar)),
        ];

      case HomeEstado.listo:
        if (catalogo.vacio) {
          return <Widget>[
            SliverToBoxAdapter(
              child: HomeEstadoVacio(
                icono: Icons.category_outlined,
                titulo: 'Todavía no hay categorías',
                mensaje:
                    'Cuando el administrador asigne categorías con productos '
                    'a esta tienda, aparecerán aquí.',
                accionEtiqueta: 'Actualizar',
                onAccion: onRefrescar,
              ),
            ),
          ];
        }
        return _sliversConContenido(context);
    }
  }

  List<Widget> _sliversConContenido(BuildContext context) {
    final List<HomeCategoria> especiales = catalogo.especiales;
    final double alto = VentiqHomeTheme.cardExtent(context);

    // Sin especiales no hay nada que agrupar. Meter la tarjeta "Tienda" en ese
    // caso sería añadir un nivel de navegación de más: el vendedor tendría que
    // tocar "Tienda" para ver las únicas categorías que hay. Se pintan sueltas,
    // como el catálogo de siempre. La tarjeta "Tienda" solo tiene sentido
    // cuando convive con especiales y separa dos grupos.
    final bool categoriasSueltas = especiales.isEmpty;
    final List<HomeCategoria> tarjetas =
        categoriasSueltas ? catalogo.tienda : especiales;
    final bool hayTiendaAgrupada =
        !categoriasSueltas && catalogo.mostrarTarjetaTienda;

    // Dónde va la tarjeta «Tienda». Con un número impar de especiales la
    // última fila de la rejilla queda coja (un hueco a la derecha de la última
    // destacada en 2 columnas, tres en 4), y «Tienda» —que es la tarjeta que
    // cierra el catálogo— encaja justo ahí: entra como una celda más y la fila
    // se lee completa. Con un número par la rejilla ya está llena, así que la
    // tarjeta se queda abajo y a lo ancho, como siempre.
    final bool tiendaEnRejilla = tiendaEnLaRejilla(catalogo);
    final bool tiendaAnchaAbajo = hayTiendaAgrupada && !tiendaEnRejilla;

    return <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      SliverToBoxAdapter(
        child: TutorialAnchor(
          id: 'home_categorias',
          child: HomeSeccionTitulo(
            rotulo: categoriasSueltas ? 'CATEGORÍAS' : 'DESTACADAS',
            accionEtiqueta: hayTiendaAgrupada ? 'Ver tienda ›' : null,
            onAccion: hayTiendaAgrupada ? onTapTienda : null,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      if (tarjetas.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: VentiqHomeTheme.sectionPadding,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columnasDe(context),
              mainAxisSpacing: VentiqHomeTheme.gridSpacing,
              crossAxisSpacing: VentiqHomeTheme.gridSpacing,
              mainAxisExtent: alto,
            ),
            delegate: SliverChildBuilderDelegate((BuildContext context, int i) {
              // El hueco de la fila impar: la misma tarjeta «Tienda» en formato
              // celda. Hereda alto y espaciado de este delegado, así que mide
              // exactamente lo mismo que las especiales de al lado. Solo se
              // alcanza cuando `tiendaEnRejilla`, porque `childCount` es
              // justo uno más que `tarjetas`.
              if (tiendaEnRejilla && i == tarjetas.length) {
                return TiendaCard.celda(
                  nombre: nombreTienda,
                  imagenTienda: imagenTienda,
                  categorias: catalogo.tienda.length,
                  productos: productosEnTienda(catalogo),
                  onTap: onTapTienda,
                );
              }

              final HomeCategoria c = tarjetas[i];
              return TarjetaExploracion(
                chip: chipDeCategoria(c),
                titulo: c.nombre,
                subtitulo: subtituloDeCategoria(c),
                icono: iconoCategoria(c.nombre),
                colores: gradienteCategoria(c.id),
                // La foto de la categoría (`app_dat_categoria.image`) manda
                // cuando existe: la tarjeta la usa de fondo con velo. Si no
                // hay foto, queda el degradado. Vale para las dos ramas
                // (destacadas y categorías sueltas).
                imagenUrl: c.imagen,
                onTap: () => onTapCategoria(c),
                accionEtiqueta: 'Ver todos',
                onAccion: () => onAbrirListado(c),
              );
            }, childCount: tarjetas.length + (tiendaEnRejilla ? 1 : 0)),
          ),
        ),
      if (tiendaAnchaAbajo) ...<Widget>[
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: TiendaCard(
            nombre: nombreTienda,
            imagenTienda: imagenTienda,
            categorias: catalogo.tienda.length,
            productos: productosEnTienda(catalogo),
            onTap: onTapTienda,
          ),
        ),
      ],
    ];
  }

  // ── Reglas de presentación ─────────────────────────────────────────────
  // Públicas y estáticas para poder probarlas sin montar el árbol.

  /// ¿La tarjeta «Tienda» va como una celda más de la rejilla?
  ///
  /// Sí cuando hay especiales y su número es **impar**: la última fila queda
  /// coja y esa es la forma de rellenarla sin inventar una tarjeta ni dejar un
  /// hueco. Con un número **par** (o sin especiales, donde ni hay rejilla de
  /// destacadas ni tarjeta que colocar) va a ancho completo debajo, como
  /// siempre. El `mostrarTarjetaTienda` cierra el caso de una «Tienda» vacía,
  /// que es un toque muerto en cualquier posición.
  static bool tiendaEnLaRejilla(HomeCatalogo catalogo) =>
      catalogo.especiales.isNotEmpty &&
      catalogo.especiales.length.isOdd &&
      catalogo.mostrarTarjetaTienda;

  /// Productos que agrupa «Tienda», sumando los de sus categorías.
  ///
  /// Lo usan las dos disposiciones de la tarjeta (la ancha y la celda): el
  /// contador sale de un único sitio para que no se desincronicen.
  static int productosEnTienda(HomeCatalogo catalogo) {
    return catalogo.tienda.fold<int>(
      0,
      (int suma, HomeCategoria c) => suma + c.totalProductos,
    );
  }

  /// Columnas según el ancho: 2 en móvil, hasta 5 en monitores de TPV.
  static int columnasDe(BuildContext context) {
    final double ancho = MediaQuery.sizeOf(context).width;
    if (ancho >= 1200) return 5;
    if (ancho >= 900) return 4;
    if (ancho >= 600) return 3;
    return 2;
  }

  static String chipDeCategoria(HomeCategoria c) {
    if (c.totalProductos <= 0) return 'SIN PRODUCTOS';
    return '${c.totalProductos} PRODUCTO${c.totalProductos == 1 ? '' : 'S'}';
  }

  /// Subtítulo de la tarjeta de categoría.
  ///
  /// Con **cero o una** subcategoría el toque entra directo a los productos (no
  /// hay nivel intermedio que enseñar), así que anunciar «1 subcategoría» sería
  /// prometer una pantalla que no existe. La regla es la misma que usa el
  /// drawer para decidir si abre ese nivel: una sola definición, sin
  /// discrepancias entre el Home y el listado.
  static String subtituloDeCategoria(HomeCategoria c) {
    final int n = c.totalSubcategorias;
    if (n >= 2) return '$n subcategorías';
    return 'Ver productos';
  }
}
