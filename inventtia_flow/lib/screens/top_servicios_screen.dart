import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/exploracion_service.dart';
import '../services/home_catalog_service.dart';
import '../tutorial/tutorial_anchor.dart';
import '../utils/categoria_icono.dart';
import '../utils/shell_navegacion.dart';
import '../widgets/barra_navegacion_cliente.dart';
import '../widgets/net_image.dart';
import '../widgets/resenas.dart';
import 'local_servicio_detail_screen.dart';

/// Top de servicios por lugares reservados en la **semana en curso**.
///
/// DE DÓNDE SALE EL ORDEN
///   `ExploracionService.topServicios()` delega en
///   `flow.cliente_ranking_semanal` (migración 36), que agrega `flow.agenda`
///   desde el lunes hasta hoy y devuelve `lugares_semana`. No es «lo más visto»
///   ni «lo mejor valorado»: es lo que la gente **reservó**. Por eso el copy
///   habla siempre de la semana y nunca de «hoy»: a las 9 de la mañana la
///   ventana ya incluye el lunes.
///
///   «Lugares» son **plazas** reservadas, no reservas: una reserva para 4
///   personas suma 4. Es el número que ordena el ranking, así que se pinta: sin
///   él, las posiciones 1-2-3 serían decorativas.
///
/// HONESTIDAD DE LOS DATOS
///   Si el RPC devuelve vacío se muestra el estado vacío; **nunca** se rellena
///   con el orden del catálogo, porque eso afirmaría unas reservas que no hubo.
///   Un servicio sin reseñas no pinta estrellas ni un «0.0».
class TopServiciosScreen extends StatefulWidget {
  const TopServiciosScreen({super.key, this.limite = 10});

  /// Cuántos puestos se muestran. 10 por defecto (el nombre de la tarjeta).
  final int limite;

  @override
  State<TopServiciosScreen> createState() => _TopServiciosScreenState();
}

class _TopServiciosScreenState extends State<TopServiciosScreen> {
  List<HomeCatalogItem> _items = const <HomeCatalogItem>[];
  bool _cargando = true;

  /// Fallo real (red, permisos): se puede reintentar.
  bool _error = false;

  /// La función del RPC todavía no existe en la base. Se separa del error real
  /// porque el consejo es otro: no es la conexión, es una migración pendiente.
  bool _migracionPendiente = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
      _migracionPendiente = false;
    });
    try {
      final ranking = await ExploracionService.topServicios(
        limite: widget.limite,
      );
      if (!mounted) return;
      setState(() {
        _items = ranking;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        // El texto técnico no llega al usuario: se traduce a un estado
        // accionable, distinguiendo «falta la migración» de «falló la red».
        _migracionPendiente = ExploracionService.esMigracionPendiente(e);
        _error = !_migracionPendiente;
      });
    }
  }

  /// Abre el detalle del servicio tocado.
  ///
  /// `localServicio` es la entidad que acompaña al ítem del feed. Si faltara
  /// (por ejemplo, un ranking cacheado viejo), se avisa con un SnackBar en vez
  /// de reventar con un `!`.
  void _abrir(HomeCatalogItem item) {
    final entidad = item.localServicio;
    if (entidad == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No pudimos abrir este servicio.')),
        );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LocalServicioDetailScreen(localServicio: entidad),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      // Barra del cliente: el top 10 también es una ruta apilada. Y así el botón
      // «Ver el catálogo» del estado vacío puede cambiar a la pestaña Servicios
      // en vez de limitarse a volver atrás.
      bottomNavigationBar: BarraNavegacionCliente.dePantalla(),
      body: RefreshIndicator(
        color: AppTheme.exploracionCoral,
        onRefresh: _cargar,
        child: ListView(
          // El ranking casi siempre cabe, pero con «siempre desplazable» el
          // gesto de refrescar funciona también en carga, error y vacío.
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.zero,
          children: [
            // El ancla va sobre el encabezado y el encabezado se monta en todos
            // los estados: el tutorial no puede depender de que el ranking haya
            // llegado para encontrar su objetivo.
            TutorialAnchor(
              id: 'top_servicios',
              child: _CabeceraTop(limite: widget.limite),
            ),
            if (_cargando)
              const _CargandoTop()
            else if (_error)
              _AvisoEstado(
                icono: Icons.cloud_off_rounded,
                titulo: 'No pudimos leer el ranking.',
                detalle: 'Revisa tu conexión.',
                onReintentar: _cargar,
              )
            else if (_migracionPendiente)
              _AvisoEstado(
                icono: Icons.build_circle_outlined,
                titulo: 'Todavía falta un paso en la base de datos.',
                // Mensaje propio del ranking: su RPC es la migración 36, no la
                // 57 de las otras dos pantallas nuevas (decirle al usuario que
                // aplique la 57 lo mandaría a arreglar otra cosa).
                detalle: ExploracionService.mensajeRankingPendiente,
                onReintentar: _cargar,
              )
            else
              TopServiciosCuerpo(
                items: _items,
                limite: widget.limite,
                onAbrir: _abrir,
                // «Ver el catálogo» lleva a la pestaña Servicios (antes solo
                // volvía atrás, que con el top 10 abierto desde el Home era
                // quedarse en el mismo sitio). Fuera del shell —una vista previa
                // o un test— se mantiene el volver atrás.
                onVerCatalogo: () {
                  if (ShellNavegacion.disponible) {
                    ShellNavegacion.irAPestana(context, ShellNavegacion.servicios);
                    return;
                  }
                  Navigator.maybePop(context);
                },
              ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

/// Cuerpo pintado del ranking: podio (1-3) y filas compactas (4 al tope).
///
/// Es **público a propósito**, con el mismo criterio que
/// `HomeCatalogService.itemsDesdeFeed`: aquí vive lo que se puede probar con
/// datos inyectados (orden, tope, estado vacío) sin Supabase ni red. La lectura
/// y los estados de carga/error se quedan en el `State` de la pantalla.
class TopServiciosCuerpo extends StatelessWidget {
  const TopServiciosCuerpo({
    super.key,
    required this.items,
    required this.onAbrir,
    this.limite = 10,
    this.onVerCatalogo,
  });

  /// Ranking ya ordenado por el servidor, de más a menos lugares reservados.
  final List<HomeCatalogItem> items;

  /// Qué hacer al tocar un puesto; la pantalla abre el detalle.
  final ValueChanged<HomeCatalogItem> onAbrir;

  /// Tope de puestos pintados, por si el servidor mandara de más.
  final int limite;

  /// Acción de «Ver el catálogo» en el estado vacío. Por defecto, volver atrás.
  final VoidCallback? onVerCatalogo;

  @override
  Widget build(BuildContext context) {
    // El tope se vuelve a aplicar aquí (además de pedirlo al RPC): es la
    // garantía de que la pantalla nunca pinta un puesto 11.
    final tope = limite < 1 ? 1 : limite;
    final visibles = items.take(tope).toList(growable: false);

    if (visibles.isEmpty) {
      // Vacío de verdad. No se rellena con el orden del catálogo: sin reservas
      // esta semana, el primer puesto no existe.
      return _AvisoEstado(
        icono: Icons.event_busy_rounded,
        titulo: 'Todavía no hay reservas esta semana',
        detalle:
            'Cuando alguien reserve, aquí verás los servicios más pedidos.',
        accion: FilledButton.icon(
          onPressed: onVerCatalogo ?? () => Navigator.maybePop(context),
          icon: const Icon(Icons.storefront_rounded, size: 18),
          label: const Text('Ver el catálogo'),
        ),
      );
    }

    final podio = visibles.take(3).toList(growable: false);
    final resto = visibles.length > 3
        ? visibles.sublist(3)
        : const <HomeCatalogItem>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < podio.length; i++)
            _TarjetaPodio(
              puesto: i + 1,
              item: podio[i],
              onTap: () => onAbrir(podio[i]),
            ),
          if (resto.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 9),
              child: Text(
                'Más puestos',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < resto.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppTheme.border,
                      ),
                    _FilaCompacta(
                      puesto: i + 4,
                      item: resto[i],
                      onTap: () => onAbrir(resto[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Encabezado coral: etiqueta, título honesto y la frase que explica el dato.
class _CabeceraTop extends StatelessWidget {
  const _CabeceraTop({required this.limite});

  final int limite;

  @override
  Widget build(BuildContext context) {
    // La etiqueta nombra la tarjeta («Top 10»). Con otro tope se ajusta para no
    // mentir sobre cuántos puestos hay.
    final etiqueta = limite == 10 ? 'TOP 10' : 'TOP $limite';

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.exploracionCoral, AppTheme.exploracionCoralDark],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 10,
        16,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                color: Colors.white,
                tooltip: 'Volver',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  etiqueta,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Tendencias de la semana',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              height: 1.12,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Los servicios con más lugares reservados esta semana',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.94),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _CargandoTop extends StatelessWidget {
  const _CargandoTop();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 46),
      child: Column(
        children: [
          CircularProgressIndicator(color: AppTheme.exploracionCoral),
          SizedBox(height: 12),
          Text(
            'Leyendo el ranking de la semana…',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Aviso de pantalla completa para carga fallida y vacío.
///
/// Réplica del patrón de `espacio_patrocinado_screen.dart` (la clase de allí es
/// privada, así que no se puede importar).
class _AvisoEstado extends StatelessWidget {
  const _AvisoEstado({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
    this.onReintentar,
  });

  final IconData icono;
  final String titulo;
  final String detalle;

  /// Botón propio (lo usa el estado vacío).
  final Widget? accion;

  /// Si viene, se pinta un «Reintentar» (lo usan error y migración pendiente).
  final Future<void> Function()? onReintentar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 40, 26, 30),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0x1AFF4E5F),
              shape: BoxShape.circle,
            ),
            child: Icon(icono, size: 30, color: AppTheme.exploracionCoral),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: AppTheme.textSecondary,
            ),
          ),
          if (accion != null || onReintentar != null) ...[
            const SizedBox(height: 16),
            accion ??
                OutlinedButton.icon(
                  onPressed: onReintentar,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reintentar'),
                ),
          ],
        ],
      ),
    );
  }
}

/// Puesto 1-3: tarjeta grande con foto, medalla y el dato que explica el orden.
class _TarjetaPodio extends StatelessWidget {
  const _TarjetaPodio({
    required this.puesto,
    required this.item,
    required this.onTap,
  });

  final int puesto;
  final HomeCatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: AppTheme.textPrimary.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 148,
                      child: _FotoServicio(
                        item: item,
                        radius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        icono: 40,
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: _MedallaPuesto(puesto: puesto, grande: true),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.venue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      // Las estrellas solo existen si alguien reseñó: sin
                      // reseñas no se pinta ni un «0.0».
                      if (item.tieneValoracion) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Estrellas(promedio: item.rating, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              item.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                item.totalResenas == 1
                                    ? '(1 reseña)'
                                    : '(${item.totalResenas} reseñas)',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 9),
                      _PrecioConPromocion(item: item, fontSize: 15),
                      const SizedBox(height: 7),
                      _EtiquetaLugares(item: item),
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
}

/// Puesto 4 al tope: fila compacta, mismo lenguaje que `_WeeklyServiceRow`.
class _FilaCompacta extends StatelessWidget {
  const _FilaCompacta({
    required this.puesto,
    required this.item,
    required this.onTap,
  });

  final int puesto;
  final HomeCatalogItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            _MedallaPuesto(puesto: puesto),
            const SizedBox(width: 10),
            SizedBox(
              width: 56,
              height: 46,
              child: _FotoServicio(
                item: item,
                radius: BorderRadius.circular(9),
                icono: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.venue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (item.tieneValoracion) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Estrellas(promedio: item.rating, size: 12),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            item.rating!.toStringAsFixed(1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Los lugares van debajo, no al final de la fila: así el
                  // número nunca se recorta en un teléfono de 320 pt.
                  if (item.lugaresSemana != null) ...[
                    const SizedBox(height: 4),
                    _EtiquetaLugares(item: item, corto: true),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Círculo del puesto: los tres primeros llevan color de medalla.
class _MedallaPuesto extends StatelessWidget {
  const _MedallaPuesto({required this.puesto, this.grande = false});

  final int puesto;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final fondo = switch (puesto) {
      1 => const Color(0xFFFFC24B), // oro
      2 => const Color(0xFFCBD5E1), // plata
      3 => const Color(0xFFE0A176), // bronce
      _ => AppTheme.surface,
    };
    final lado = grande ? 34.0 : 28.0;

    return Semantics(
      label: 'Puesto $puesto',
      child: Container(
        width: lado,
        height: lado,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fondo,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 2,
          ),
        ),
        child: FittedBox(
          // Con el texto al 130 % un «10» no cabe en el círculo: se encoge en
          // vez de desbordar.
          fit: BoxFit.scaleDown,
          child: Text(
            '$puesto',
            style: TextStyle(
              // Sobre oro/plata/bronce el texto oscuro es el único legible.
              color: puesto <= 3 ? const Color(0xFF3A2E1E) : AppTheme.primary,
              fontSize: grande ? 15 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

/// Foto del servicio con respaldo degradado por categoría.
///
/// Réplica del patrón de `_MediaPreview` del Home (clase privada): usa
/// `NetImage` y, si no hay foto o falla, un degradado + icono de categoría.
class _FotoServicio extends StatelessWidget {
  const _FotoServicio({
    required this.item,
    required this.radius,
    this.icono = 28,
  });

  final HomeCatalogItem item;
  final BorderRadius radius;
  final double icono;

  @override
  Widget build(BuildContext context) {
    final respaldo = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _degradadoCategoria(item.category),
        ),
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Icon(
        iconoCategoria(item.category),
        size: icono,
        color: Colors.white.withValues(alpha: 0.92),
      ),
    );

    final url = item.imageUrl;
    if (url == null || url.trim().isEmpty) return respaldo;
    return ClipRRect(
      borderRadius: radius,
      child: NetImage(
        url: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: () => respaldo,
      ),
    );
  }
}

/// Precio de lista, o el de promoción con el original tachado.
///
/// Misma regla que `_PrecioConPromocion` del Home: el descuento es de
/// referencia y el importe final lo fija el servidor al reservar.
class _PrecioConPromocion extends StatelessWidget {
  const _PrecioConPromocion({required this.item, this.fontSize = 12});

  final HomeCatalogItem item;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final precioPromo = item.precioConPromocion;
    final precioLista = item.priceLabel;
    if (!item.tieneDescuento || precioPromo == null || precioLista == null) {
      return Text(
        precioLista ?? 'Consultar',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppTheme.primary,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            '${precioPromo.toStringAsFixed(0)} ${item.currency ?? ''}'.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.error,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            precioLista,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: fontSize * 0.8,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ),
      ],
    );
  }
}

/// El dato que explica la posición.
class _EtiquetaLugares extends StatelessWidget {
  const _EtiquetaLugares({required this.item, this.corto = false});

  final HomeCatalogItem item;

  /// En el podio se deletrea la ventana («… esta semana»); en las filas
  /// compactas basta «N lugares».
  final bool corto;

  @override
  Widget build(BuildContext context) {
    final texto = corto ? _lugaresCortos(item) : _lugaresSemana(item);
    // Un ítem del ranking siempre trae el número; si no viniera, no se inventa.
    if (texto == null) return const SizedBox.shrink();

    return Row(
      children: [
        const Icon(
          Icons.local_fire_department_rounded,
          size: 15,
          color: AppTheme.exploracionCoral,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.exploracionCoral,
            ),
          ),
        ),
      ],
    );
  }
}

/// «11 lugares reservados esta semana».
///
/// Se apoya en `lugaresSemanaLabel` (derivado de `lugaresSemana`, que solo
/// manda `cliente_ranking_semanal`) y le añade la ventana temporal. «Lugares»
/// son plazas reservadas, no reservas.
String? _lugaresSemana(HomeCatalogItem item) {
  final etiqueta = item.lugaresSemanaLabel;
  return etiqueta == null ? null : '$etiqueta esta semana';
}

/// «11 lugares», para la fila compacta, donde no cabe la frase entera.
String? _lugaresCortos(HomeCatalogItem item) {
  final n = item.lugaresSemana;
  if (n == null) return null;
  return n == 1 ? '1 lugar' : '$n lugares';
}

/// Degradado estable derivado del código de la categoría.
///
/// El mismo tipo de actividad pinta siempre igual, sin tabla que mantener. Es
/// el criterio de `_MediaPreview` (privado) replicado aquí.
List<Color> _degradadoCategoria(HomeCatalogCategory categoria) {
  if (categoria.codigo == 'transporte_omnibus') {
    return const [Color(0xFF385582), Color(0xFF7BA6D3)];
  }
  final semilla = categoria.codigo.isEmpty
      ? categoria.nombre.length
      : categoria.codigo.codeUnits.fold<int>(0, (a, b) => a + b);
  const paletas = <List<Color>>[
    [Color(0xFF70537C), Color(0xFFC69CC4)],
    [Color(0xFF2D7573), Color(0xFF71BCB4)],
    [Color(0xFF8A7355), Color(0xFFCBB58B)],
    [Color(0xFF395B91), Color(0xFF6D9DD1)],
    [Color(0xFF8C5B72), Color(0xFFC98CA4)],
  ];
  return paletas[semilla % paletas.length];
}
