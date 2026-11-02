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
          ..._sliversCatalogo(context),
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
          SliverToBoxAdapter(
            child: HomeEstadoError(onReintentar: onRefrescar),
          ),
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

    return <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      SliverToBoxAdapter(
        child: HomeSeccionTitulo(
          rotulo: categoriasSueltas ? 'CATEGORÍAS' : 'DESTACADAS',
          accionEtiqueta: hayTiendaAgrupada ? 'Ver tienda ›' : null,
          onAccion: hayTiendaAgrupada ? onTapTienda : null,
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
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int i) {
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
              },
              childCount: tarjetas.length,
            ),
          ),
        ),
      if (hayTiendaAgrupada) ...<Widget>[
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: TiendaCard(
            categorias: catalogo.tienda.length,
            productos: catalogo.tienda.fold<int>(
              0,
              (int suma, HomeCategoria c) => suma + c.totalProductos,
            ),
            onTap: onTapTienda,
          ),
        ),
      ],
    ];
  }

  // ── Reglas de presentación ─────────────────────────────────────────────
  // Públicas y estáticas para poder probarlas sin montar el árbol.

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

  static String subtituloDeCategoria(HomeCategoria c) {
    if (c.tieneSubcategorias) {
      final int n = c.totalSubcategorias;
      return '$n subcategoría${n == 1 ? '' : 's'}';
    }
    return 'Ver productos';
  }
}
