import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/establecimiento_resumen.dart';
import '../services/exploracion_service.dart';
import '../services/home_catalog_service.dart';
import '../tutorial/tutorial_anchor.dart';
import '../utils/exploracion_navegacion.dart';
import '../utils/exploracion_resumen.dart';
import '../utils/horario_atencion.dart';
import '../widgets/barra_navegacion_cliente.dart';
import '../widgets/filtros_servicios_sheet.dart';
import '../widgets/net_image.dart';
import '../widgets/resenas.dart';

/// Listado de establecimientos de «Exploración rápida».
///
/// POR QUE EXISTE
///   El Home y el listado de categorías mandan aquí: el cliente ya eligió un
///   rubro (o una subcategoría, o una provincia) y lo que quiere ver son los
///   locales donde puede reservar, no una lista de servicios.
///
/// DE DONDE SALE CADA DATO
///   * Locales: `flow.cliente_locales_publicos(p_id_categoria, p_id_subcategoria,
///     p_provincia)` (migración 57). Los tres filtros son de **servidor** y se
///     aplican al pedir; volver a pedir solo ocurre cuando cambia uno de ellos
///     (chips de subcategoría).
///   * Orden, filtros del sheet y estado «abierto ahora»: en memoria, con los
///     helpers de `utils/exploracion_resumen.dart`. Cambiar el orden o marcar
///     «solo abiertos» no cuesta una petición.
///
/// NADA INVENTADO: un local sin reseñas no pinta estrellas ni un «0.0», y sin
/// precio configurado no hay «Desde». La tarjeta simplemente no muestra ese dato.
class EstablecimientosScreen extends StatefulWidget {
  const EstablecimientosScreen({
    super.key,
    this.categoria,
    this.subcategoria,
    this.provincia,
  });

  /// Categoría por la que se filtra (incluye sus subcategorías).
  final HomeCatalogCategory? categoria;

  /// Subcategoría elegida; manda sobre [categoria].
  final HomeCatalogCategory? subcategoria;

  /// Provincia exacta, o `null` = todas.
  final String? provincia;

  @override
  State<EstablecimientosScreen> createState() =>
      _EstablecimientosScreenState();
}

class _EstablecimientosScreenState extends State<EstablecimientosScreen> {
  /// Locales tal como los devolvió el servidor. Sobre esta lista se aplican el
  /// orden y los filtros del sheet.
  List<EstablecimientoResumen> _cargados = const <EstablecimientoResumen>[];

  bool _cargando = true;
  bool _error = false;
  bool _migracionPendiente = false;

  FiltrosServicios _filtros = FiltrosServicios.vacio;
  OrdenEstablecimientos _orden = OrdenEstablecimientos.mejorValorados;

  // Los filtros de servidor son copia local: los chips de subcategoría y el
  // botón del estado vacío pueden cambiarlos sin volver a montar la pantalla.
  HomeCatalogCategory? _categoriaActiva;
  HomeCatalogCategory? _subcategoriaActiva;
  String? _provinciaActiva;

  @override
  void initState() {
    super.initState();
    _categoriaActiva = widget.categoria;
    _subcategoriaActiva = widget.subcategoria;
    _provinciaActiva = widget.provincia;
    _cargar();
  }

  @override
  void didUpdateWidget(EstablecimientosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // La ruta puede reutilizar el `State` si le llegan otros filtros: se
    // recargan los datos en vez de mentir con los del filtro anterior.
    final cambioCategoria = oldWidget.categoria?.id != widget.categoria?.id;
    final cambioSubcategoria =
        oldWidget.subcategoria?.id != widget.subcategoria?.id;
    final cambioProvincia = oldWidget.provincia != widget.provincia;
    if (cambioCategoria || cambioSubcategoria || cambioProvincia) {
      _categoriaActiva = widget.categoria;
      _subcategoriaActiva = widget.subcategoria;
      _provinciaActiva = widget.provincia;
      _cargados = const <EstablecimientoResumen>[];
      _cargar();
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
      _migracionPendiente = false;
    });
    try {
      final lista = await ExploracionService.establecimientos(
        idCategoria: _categoriaActiva?.id,
        idSubcategoria: _subcategoriaActiva?.id,
        provincia: _provinciaActiva,
      );
      if (!mounted) return;
      setState(() {
        _cargados = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      // «Falta la migración» no es un fallo de red: el usuario no arregla nada
      // revisando su conexión, así que se le dice lo que de verdad pasa.
      setState(() {
        _cargando = false;
        if (ExploracionService.esMigracionPendiente(e)) {
          _migracionPendiente = true;
        } else {
          _error = true;
        }
      });
    }
  }

  /// Opciones del sheet, deducidas de lo ya cargado: nunca una que filtre a cero.
  OpcionesFiltros get _opciones => opcionesFiltrosEstablecimientos(_cargados);

  /// Cambiar de subcategoría es un filtro de servidor: se vuelve a pedir.
  void _elegirSubcategoria(HomeCatalogCategory? subcategoria) {
    if (subcategoria?.id == _subcategoriaActiva?.id) return;
    setState(() {
      _subcategoriaActiva = subcategoria;
      // Se vacía para no enseñar un listado que ya no corresponde al chip
      // marcado mientras llega el del servidor.
      _cargados = const <EstablecimientoResumen>[];
    });
    _cargar();
  }

  Future<void> _abrirFiltros() async {
    final elegidos = await mostrarFiltrosServicios(
      context,
      actual: _filtros,
      opciones: _opciones,
      // El contador es gratis: la lista ya está cargada. Así nadie aplica a
      // ciegas un filtro que deje la pantalla vacía.
      contador: (borrador) => _visiblesDe(
        _cargados,
        borrador,
        _orden,
        idSubcategoriaActiva: _subcategoriaActiva?.id,
      ).length,
    );
    if (!mounted || elegidos == null) return;
    setState(() => _filtros = elegidos);
  }

  /// Vacía el filtro que dejó la lista sin resultados.
  ///
  /// Primero los del sheet (no cuestan petición); solo si no hay ninguno se
  /// sueltan los de servidor, que obligan a recargar.
  void _quitarFiltroDelVacio() {
    if (_filtros.activos > 0 && _cargados.isNotEmpty) {
      setState(() => _filtros = FiltrosServicios.vacio);
      return;
    }
    final hayServidor =
        _subcategoriaActiva != null ||
        _categoriaActiva != null ||
        (_provinciaActiva?.trim().isNotEmpty ?? false);
    if (!hayServidor) return;
    setState(() {
      _filtros = FiltrosServicios.vacio;
      _subcategoriaActiva = null;
      _categoriaActiva = null;
      _provinciaActiva = null;
      _cargados = const <EstablecimientoResumen>[];
    });
    _cargar();
  }

  /// De qué filtro de servidor se trata, para poder decirlo en la cabecera.
  String get _descriptorFiltro {
    final partes = <String>[];
    final subcategoria = _subcategoriaActiva;
    if (subcategoria != null) {
      partes.add('En ${subcategoria.nombre}');
    } else if (_categoriaActiva != null) {
      partes.add('En ${_categoriaActiva!.nombre}');
    }
    final provincia = _provinciaActiva?.trim();
    if (provincia != null && provincia.isNotEmpty) {
      partes.add('En $provincia');
    }
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // Un solo reloj por build: el contador y las tarjetas dicen lo mismo sobre
    // «abierto ahora» aunque el pintado tarde.
    final ahora = DateTime.now();
    final visibles = _visiblesDe(
      _cargados,
      _filtros,
      _orden,
      ahora: ahora,
      idSubcategoriaActiva: _subcategoriaActiva?.id,
    );

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Establecimientos')),
      // Barra del cliente: esta vista está apilada sobre el shell y tapaba la
      // suya. Se marca «Inicio» porque de ahí cuelga (la rejilla del Home).
      bottomNavigationBar: BarraNavegacionCliente.dePantalla(),
      body: Column(
        children: [
          _buildCabecera(visibles.length),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: _cargar,
              child: _buildContenido(ahora),
            ),
          ),
        ],
      ),
    );
  }

  // ── Cabecera: título, filtro activo, contador, chips y barra de acciones ──
  Widget _buildCabecera(int visibles) {
    final descriptor = _descriptorFiltro;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        boxShadow: AppTheme.sombraTarjeta,
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El ancla va sobre la cabecera (siempre montada), nunca sobre una
          // tarjeta: la lista puede estar vacía o cargando y el paso del
          // tutorial tiene que poder resaltar algo.
          TutorialAnchor(
            id: 'establecimientos_lista',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  descriptor.isEmpty
                      ? 'Locales con servicios publicados'
                      : 'Locales con servicios publicados · $descriptor',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _etiquetaContador(visibles),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (_categoriaActiva != null &&
              _categoriaActiva!.tieneSubcategorias) ...[
            const SizedBox(height: 10),
            _buildChipsSubcategorias(),
          ],
          const SizedBox(height: 10),
          _buildBarraAcciones(),
        ],
      ),
    );
  }

  String _etiquetaContador(int visibles) {
    if (_cargando && _cargados.isEmpty) return 'Buscando establecimientos…';
    if (_error || _migracionPendiente) return 'Sin datos por ahora';
    return visibles == 1 ? '1 establecimiento' : '$visibles establecimientos';
  }

  Widget _buildChipsSubcategorias() {
    final categoria = _categoriaActiva!;
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _ChipSubcategoria(
            label: 'Todas',
            activo: _subcategoriaActiva == null,
            onTap: () => _elegirSubcategoria(null),
          ),
          for (final subcategoria in categoria.subcategorias) ...[
            const SizedBox(width: 8),
            _ChipSubcategoria(
              label: subcategoria.nombre,
              activo: _subcategoriaActiva?.id == subcategoria.id,
              onTap: () => _elegirSubcategoria(subcategoria),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBarraAcciones() {
    return Row(
      children: [
        Expanded(
          child: _SelectorOrden(
            orden: _orden,
            onCambio: (orden) => setState(() => _orden = orden),
          ),
        ),
        const SizedBox(width: 8),
        TutorialAnchor(
          id: 'establecimientos_filtros',
          child: _BotonFiltros(
            activos: _filtros.activos,
            // Sin opciones reales (nada cargado todavía) el sheet no tendría
            // nada que ofrecer: el botón se enseña, pero apagado.
            onTap: _opciones.hayAlgo ? _abrirFiltros : null,
          ),
        ),
      ],
    );
  }

  // ── Contenido: carga, avisos y listado ───────────────────────────────────
  Widget _buildContenido(DateTime ahora) {
    if (_cargando && _cargados.isEmpty) {
      return _scrollable(
        const Padding(
          padding: EdgeInsets.only(top: 72),
          child: Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          ),
        ),
      );
    }
    if (_migracionPendiente) {
      return _scrollable(
        _Aviso(
          icono: Icons.storage_rounded,
          titulo: 'Falta aplicar un cambio en la base de datos',
          detalle: ExploracionService.mensajeMigracionPendiente,
          accion: _botonReintentar(),
        ),
      );
    }
    if (_error) {
      return _scrollable(
        _Aviso(
          icono: Icons.cloud_off_rounded,
          titulo: 'No pudimos leer los establecimientos',
          detalle: 'Revisa tu conexión.',
          accion: _botonReintentar(),
        ),
      );
    }
    return CuerpoEstablecimientos(
      establecimientos: _cargados,
      filtros: _filtros,
      orden: _orden,
      categoria: _categoriaActiva,
      subcategoria: _subcategoriaActiva,
      provincia: _provinciaActiva,
      ahora: ahora,
      onQuitarFiltros: _quitarFiltroDelVacio,
    );
  }

  Widget _botonReintentar() => TextButton.icon(
    onPressed: _cargar,
    icon: const Icon(Icons.refresh_rounded, size: 18),
    label: const Text('Reintentar'),
  );

  /// Los estados de carga y aviso también tienen que poder arrastrarse para
  /// refrescar: si no, `RefreshIndicator` no tendría un scrollable al que
  /// agarrarse justo cuando más falta hace reintentar.
  Widget _scrollable(Widget child) => ListView(
    physics: const AlwaysScrollableScrollPhysics(
      parent: BouncingScrollPhysics(),
    ),
    padding: EdgeInsets.zero,
    children: [child],
  );
}

/// Filtra (en memoria) y ordena los locales ya cargados.
///
/// Vive fuera del `State` porque la usan dos sitios con la misma regla: el
/// contador de la cabecera y el propio cuerpo del listado. Así el número que
/// enseña la cabecera no puede discrepar de lo que se ve debajo.
List<EstablecimientoResumen> _visiblesDe(
  List<EstablecimientoResumen> establecimientos,
  FiltrosServicios filtros,
  OrdenEstablecimientos orden, {
  DateTime? ahora,
  int? idSubcategoriaActiva,
}) {
  final momento = ahora ?? DateTime.now();
  final pasan = establecimientos
      .where(
        (e) => pasaFiltrosEstablecimiento(
          e,
          filtros,
          ahora: momento,
          idSubcategoriaActiva: idSubcategoriaActiva,
        ),
      )
      .toList(growable: false);
  return ordenarEstablecimientos(pasan, orden);
}

/// Cuerpo del listado: recibe los datos ya cargados y los pinta.
///
/// Es **público y `@visibleForTesting`** a propósito: la carga (Supabase) vive
/// en el `State` de [EstablecimientosScreen] y este widget solo hace lo que se
/// puede probar sin red — aplicar los filtros en memoria, ordenar, pintar las
/// tarjetas y los estados. La pantalla lo monta por dentro; nadie más lo usa.
@visibleForTesting
class CuerpoEstablecimientos extends StatelessWidget {
  const CuerpoEstablecimientos({
    super.key,
    required this.establecimientos,
    required this.filtros,
    required this.orden,
    this.categoria,
    this.subcategoria,
    this.provincia,
    this.ahora,
    this.onQuitarFiltros,
  });

  /// Locales tal como llegaron del servidor: sin filtrar ni ordenar.
  final List<EstablecimientoResumen> establecimientos;

  final FiltrosServicios filtros;
  final OrdenEstablecimientos orden;

  /// Filtros de servidor, solo para poder nombrarlos en el estado vacío.
  final HomeCatalogCategory? categoria;
  final HomeCatalogCategory? subcategoria;
  final String? provincia;

  /// Reloj con el que se evalúa el horario. En la app es `DateTime.now()`; en
  /// los tests, una hora fija (un «abierto ahora» depende de la hora).
  final DateTime? ahora;

  /// Quita el filtro que dejó la lista vacía. `null` = no hay nada que quitar.
  final VoidCallback? onQuitarFiltros;

  @override
  Widget build(BuildContext context) {
    final momento = ahora ?? DateTime.now();
    final visibles = _visiblesDe(
      establecimientos,
      filtros,
      orden,
      ahora: momento,
      idSubcategoriaActiva: subcategoria?.id,
    );

    if (visibles.isEmpty) {
      return _VacioEstablecimientos(
        mensaje: _mensajeVacio,
        accionEtiqueta: _accionVacio,
        onQuitarFiltros: onQuitarFiltros,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: visibles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, indice) {
        final establecimiento = visibles[indice];
        return _TarjetaEstablecimiento(
          establecimiento: establecimiento,
          ahora: momento,
          // Misma ficha que abre el espacio patrocinado (F5): un solo destino.
          onTap: () => ExploracionNavegacion.abrirFicha(
            context,
            establecimiento: establecimiento,
          ),
        );
      },
    );
  }

  /// El vacío siempre dice **qué** lo dejó vacío: no es lo mismo que no haya
  /// nada publicado que haber filtrado de más.
  String get _mensajeVacio {
    if (filtros.activos > 0 && establecimientos.isNotEmpty) {
      return 'Ningún establecimiento pasa los filtros que elegiste. '
          'Quita alguno para ver más.';
    }
    final subcategoriaActiva = subcategoria;
    if (subcategoriaActiva != null) {
      return 'Todavía no hay establecimientos en ${subcategoriaActiva.nombre}.';
    }
    final categoriaActiva = categoria;
    if (categoriaActiva != null) {
      return 'Todavía no hay establecimientos en ${categoriaActiva.nombre}.';
    }
    final provinciaActiva = provincia?.trim();
    if (provinciaActiva != null && provinciaActiva.isNotEmpty) {
      return 'Todavía no hay establecimientos publicados en $provinciaActiva.';
    }
    return 'Todavía no hay establecimientos publicados. Cuando un local '
        'publique un servicio reservable, aparecerá aquí.';
  }

  String? get _accionVacio {
    if (onQuitarFiltros == null) return null;
    if (filtros.activos > 0 && establecimientos.isNotEmpty) {
      return 'Quitar filtros';
    }
    if (subcategoria != null) return 'Ver toda la categoría';
    if (categoria != null) return 'Ver todos los establecimientos';
    if (provincia?.trim().isNotEmpty ?? false) {
      return 'Ver todos los establecimientos';
    }
    return null;
  }
}

// ── Tarjeta ────────────────────────────────────────────────────────────────

class _TarjetaEstablecimiento extends StatelessWidget {
  const _TarjetaEstablecimiento({
    required this.establecimiento,
    required this.ahora,
    required this.onTap,
  });

  final EstablecimientoResumen establecimiento;
  final DateTime ahora;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = establecimiento;
    final estado = e.estadoHorario(ahora);
    final ubicacion = e.ubicacion;
    final foto = e.foto?.trim() ?? '';
    // El importe va aparte de la palabra «Desde»: se pintan en dos líneas para
    // que quepan en la columna de la derecha sin salir cortados con puntos
    // suspensivos (que es como se veía «Desde 3500 CUP»).
    final importe = e.precioDesdeMontoLabel;

    // Todos los chips en UNA fila, con scroll horizontal si no caben: apilados en
    // varias filas hacían que unas tarjetas crecieran y otras no. El alto se fija
    // aquí (escalado con el texto del sistema) para que la lista quede pareja.
    final chips = <Widget>[
      // Un horario ilegible no se cuenta como abierto **ni** como cerrado: sin
      // dato, no hay chip.
      if (estado != EstadoHorario.desconocido)
        _ChipDato(
          icono: estado == EstadoHorario.abierto
              ? Icons.schedule_rounded
              : Icons.schedule_outlined,
          texto: estado == EstadoHorario.abierto ? 'Abierto ahora' : 'Cerrado',
          color: estado == EstadoHorario.abierto
              ? AppTheme.success
              : AppTheme.textSecondary,
        ),
      if (e.totalServicios > 0)
        _ChipDato(
          icono: Icons.miscellaneous_services_outlined,
          texto: e.etiquetaServicios,
        ),
      if (e.tieneReservaDirecta)
        _ChipDato(
          icono: Icons.bolt_rounded,
          texto: 'Reserva directa',
          color: AppTheme.success,
        ),
    ];

    final escala = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          // Alto fijo: con el nombre a 1 o 2 líneas las tarjetas medían distinto.
          height: 124 * escala,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.sombraTarjeta,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                // La foto ocupa el alto disponible: así las cuatro esquinas de
                // todas las tarjetas coinciden.
                child: SizedBox(
                  width: 72,
                  height: double.infinity,
                  child: foto.isNotEmpty
                      ? NetImage(
                          url: foto,
                          fit: BoxFit.cover,
                          errorWidget: _respaldoFoto,
                        )
                      : _respaldoFoto(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    if (ubicacion != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              ubicacion,
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
                    // Los chips van al pie de la tarjeta, en una sola fila. Si no
                    // caben se deslizan en horizontal (dentro de la tarjeta) en
                    // vez de saltar a una segunda línea.
                    const Spacer(),
                    if (chips.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (var i = 0; i < chips.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              chips[i],
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Columna derecha acotada: a 320 pt la tarjeta no puede crecer sin
              // límite por un texto largo.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 92),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (e.tieneValoracion) ...[
                      Estrellas(promedio: e.rating, size: 11),
                      const SizedBox(height: 2),
                      Text(
                        '${e.rating!.toStringAsFixed(1)} (${e.etiquetaResenas})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                    if (importe != null) ...[
                      if (e.tieneValoracion) const SizedBox(height: 6),
                      const Text(
                        'Desde',
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      // `FittedBox` y no `ellipsis`: un importe largo («3500 CUP»,
                      // o el texto del sistema al 130 %) se reduce lo justo para
                      // caber en vez de salir cortado con puntos suspensivos, que
                      // era lo que se veía feo. Mismo patrón que el nombre del
                      // Home.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          importe,
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Respaldo cuando el local no tiene foto o la que tiene no carga: el mismo
  /// degradado de marca que usan el resto de tarjetas de la app.
  Widget _respaldoFoto() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppTheme.primary.withValues(alpha: 0.20),
          AppTheme.accent.withValues(alpha: 0.24),
        ],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.storefront_outlined,
        size: 26,
        color: AppTheme.primary.withValues(alpha: 0.55),
      ),
    ),
  );
}

class _ChipDato extends StatelessWidget {
  const _ChipDato({
    required this.icono,
    required this.texto,
    this.color = AppTheme.primary,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: 4),
          // `Flexible`: a 320 pt la columna de datos es estrecha y un chip más
          // ancho que ella tiene que recortar su texto, no desbordar la fila.
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Barra de acciones ──────────────────────────────────────────────────────

/// Selector de orden. Es de la pantalla, no del servidor: reordenar no cuesta
/// una petición.
class _SelectorOrden extends StatelessWidget {
  const _SelectorOrden({required this.orden, required this.onCambio});

  final OrdenEstablecimientos orden;
  final ValueChanged<OrdenEstablecimientos> onCambio;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<OrdenEstablecimientos>(
      tooltip: 'Cambiar el orden',
      initialValue: orden,
      onSelected: onCambio,
      itemBuilder: (_) => [
        for (final opcion in OrdenEstablecimientos.values)
          PopupMenuItem<OrdenEstablecimientos>(
            value: opcion,
            child: Text(opcion.etiqueta),
          ),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              size: 18,
              color: AppTheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                orden.etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón «Filtros». Con filtros puestos cambia a degradado de marca y dice
/// cuántos hay, para que no se puedan «perder» dentro del sheet.
class _BotonFiltros extends StatelessWidget {
  const _BotonFiltros({required this.activos, required this.onTap});

  final int activos;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hay = activos > 0;
    final contenido = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.tune_rounded,
          size: 19,
          color: hay ? Colors.white : AppTheme.primary,
        ),
        const SizedBox(width: 6),
        Text(
          'Filtros',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: hay ? Colors.white : AppTheme.primary,
          ),
        ),
      ],
    );

    return Opacity(
      // Apagado cuando no hay ninguna opción real que ofrecer: mejor que un
      // botón que abre una hoja vacía.
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: hay
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.primary, AppTheme.accent],
                    )
                  : null,
              color: hay ? null : Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: hay ? null : Border.all(color: AppTheme.border),
              boxShadow: hay
                  ? [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: hay
                ? Badge.count(
                    count: activos,
                    backgroundColor: Colors.white,
                    textColor: AppTheme.primaryDark,
                    child: contenido,
                  )
                : contenido,
          ),
        ),
      ),
    );
  }
}

/// Chip de subcategoría de la cabecera. Tocar uno vuelve a pedir la lista al
/// servidor con ese `idSubcategoria`; «Todas» la pide sin subcategoría.
class _ChipSubcategoria extends StatelessWidget {
  const _ChipSubcategoria({
    required this.label,
    required this.activo,
    required this.onTap,
  });

  final String label;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activo ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: activo ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
            color: activo ? Colors.white : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Estados ────────────────────────────────────────────────────────────────

/// Aviso de error o de migración pendiente: mensaje claro y una salida.
class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(icono, size: 36, color: AppTheme.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (accion != null) ...[const SizedBox(height: 8), accion!],
        ],
      ),
    );
  }
}

class _VacioEstablecimientos extends StatelessWidget {
  const _VacioEstablecimientos({
    required this.mensaje,
    required this.accionEtiqueta,
    required this.onQuitarFiltros,
  });

  final String mensaje;
  final String? accionEtiqueta;
  final VoidCallback? onQuitarFiltros;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(
          Icons.storefront_outlined,
          size: 44,
          color: AppTheme.primary.withValues(alpha: 0.4),
        ),
        const SizedBox(height: 10),
        Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        if (accionEtiqueta != null && onQuitarFiltros != null) ...[
          const SizedBox(height: 14),
          Center(
            child: FilledButton.icon(
              onPressed: onQuitarFiltros,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: Text(accionEtiqueta!),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}