import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../models/config_precio.dart';
import '../models/servicio.dart';
import '../providers/favoritos_provider.dart';
import '../services/catalogo_service.dart';
import '../services/resena_service.dart';
import '../utils/horario_atencion.dart';
import '../utils/precio_reserva.dart';
import '../widgets/boton_favorito.dart';
import '../widgets/filtros_servicios_sheet.dart';
import '../widgets/net_image.dart';
import '../widgets/notificaciones_bell.dart';
import '../widgets/pista_busqueda_avanzada.dart';
import 'local_servicio_detail_screen.dart';

class CatalogoScreen extends StatefulWidget {
  const CatalogoScreen({super.key});

  @override
  State<CatalogoScreen> createState() => CatalogoScreenState();
}

class CatalogoScreenState extends State<CatalogoScreen> {
  Future<void> reload() => _load();
  List<LocalServicio> _localServicios = [];
  bool _isLoading = true;

  // Filtros
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  /// Todo lo que el cliente puede acotar desde el sheet de filtros: precio,
  /// moneda, provincia, valoración, establecimiento, "abierto ahora" y **solo
  /// favoritos** (que antes era un chip suelto encima de la lista).
  FiltrosServicios _filtros = FiltrosServicios.vacio;

  /// Ancla del mensaje que apunta al botón de filtros.
  final LayerLink _linkFiltros = LayerLink();

  /// Pista "¿no encuentras lo que buscas?": se enseña una vez, mientras el
  /// usuario no haya filtrado ni buscado nada, y se apunta en preferencias para
  /// no repetirla en cada visita.
  static const String _prefPistaFiltros = 'catalogo_pista_filtros_vista';
  bool _pistaFiltros = false;
  Timer? _pistaTimer;

  /// Valoraciones reales por `local_servicio.id` (`flow.resena`). Vacío si el
  /// RPC no está disponible: entonces no se ofrece filtrar por valoración.
  Map<int, ResumenResenas> _resenas = const {};

  // Rate limiting: máx 5 refrescos por minuto
  static const int _maxRefrescosPorMinuto = 5;
  final List<DateTime> _historialRefrescos = [];

  @override
  void initState() {
    super.initState();
    _load();
    _comprobarPistaFiltros();
  }

  @override
  void dispose() {
    _pistaTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Enseña la pista que apunta al botón de filtros solo la primera vez.
  ///
  /// Se guarda en preferencias al ocultarla (a mano o sola), así que no aparece
  /// en cada visita; si el usuario nunca llegó a verla por cerrar la app antes,
  /// volverá a salir, que es lo deseado.
  Future<void> _comprobarPistaFiltros() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefPistaFiltros) == true) return;

    // Se espera a que haya lista: la pista apunta al botón de filtros, así que
    // mientras carga (o si el catálogo vino vacío) no tiene a quién señalar.
    // Se reintenta un rato en vez de darla por perdida en la primera carga.
    for (var intento = 0; intento < 12; intento++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      if (!_isLoading && _localServicios.isNotEmpty) break;
    }
    if (!mounted || _isLoading || _localServicios.isEmpty) return;

    setState(() => _pistaFiltros = true);
    _pistaTimer = Timer(const Duration(seconds: 9), _ocultarPistaFiltros);
  }

  Future<void> _ocultarPistaFiltros() async {
    _pistaTimer?.cancel();
    if (mounted && _pistaFiltros) setState(() => _pistaFiltros = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPistaFiltros, true);
  }

  Future<void> _refresh() async {
    final ahora = DateTime.now();
    final hace1Min = ahora.subtract(const Duration(minutes: 1));
    _historialRefrescos.removeWhere((t) => t.isBefore(hace1Min));

    if (_historialRefrescos.length >= _maxRefrescosPorMinuto) {
      final proxDisponible = _historialRefrescos.first.add(
        const Duration(minutes: 1),
      );
      final espera = proxDisponible.difference(ahora).inSeconds + 1;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Límite alcanzado. Intenta en $espera s.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _historialRefrescos.add(ahora);
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      // Las valoraciones salen de otro RPC: si falla, el catálogo se pinta
      // igual y simplemente no se ofrece el filtro por valoración.
      final resultados = await Future.wait([
        CatalogoService.getLocalServicios(),
        ResenaService.porServicio().catchError(
          (_) => const <int, ResumenResenas>{},
        ),
      ]);

      final localServicios = resultados[0] as List<LocalServicio>;
      final resenas = resultados[1] as Map<int, ResumenResenas>;

      setState(() {
        // Red de seguridad: el RPC ya filtra por `flow._ls_disponible`, pero una
        // respuesta cacheada puede traer pares ya desactivados. Se descartan
        // aquí para no ofrecer algo no reservable (puntos 3/4/8).
        _localServicios = localServicios
            .where((ls) => ls.activoEfectivo)
            .toList(growable: false);
        _resenas = resenas;
        _isLoading = false;
      });
    } catch (e) {
      print('[flow] CatalogoScreen _load ERROR: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Filtra y ordena. Los favoritos van **primero**, preservando el orden
  /// original del catálogo dentro de cada grupo (ordenación estable).
  ///
  /// El criterio agrupa, no ordena alfabéticamente: si estás buscando algo que
  /// guardaste, lo encuentras arriba sin perder de vista el resto del catálogo.
  List<LocalServicio> _filtered(Set<int> idsFavoritos) => _filtrar(
    _localServicios,
    idsFavoritos: idsFavoritos,
    filtros: _filtros,
    query: _searchQuery,
  );

  /// Núcleo del filtrado, con todo por parámetro.
  ///
  /// El sheet de filtros lo reutiliza con su borrador para enseñar en vivo
  /// cuántos servicios quedarían: así el usuario no aplica a ciegas.
  List<LocalServicio> _filtrar(
    List<LocalServicio> base, {
    required Set<int> idsFavoritos,
    required FiltrosServicios filtros,
    required String query,
  }) {
    var lista = base;

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      lista = lista
          .where(
            (ls) =>
                (ls.local?.nombre ?? '').toLowerCase().contains(q) ||
                (ls.servicio?.nombre ?? '').toLowerCase().contains(q),
          )
          .toList();
    }

    if (filtros.hayAlgo) {
      lista = lista.where((ls) {
        final precio = precioBaseDe(ls.servicio?.configPrecio);
        final resumen = _resenas[ls.id];
        return filtros.coincide(
          precioItem: precio?.precio,
          monedaItem: precio?.moneda,
          provinciaItem: ls.local?.provincia,
          ratingItem: (resumen?.total ?? 0) > 0 ? resumen!.promedio : null,
          idLocalItem: ls.idLocal,
          // Solo se evalúa el horario cuando el filtro lo pide: interpretar el
          // texto libre de cada local no es gratis.
          abiertoItem: filtros.soloAbiertos ? _estaAbierto(ls) : null,
          esFavoritoItem: idsFavoritos.contains(ls.id),
        );
      }).toList();
    }

    if (idsFavoritos.isEmpty) return lista;

    // `List.sort` de Dart NO es estable, así que no se puede ordenar por el
    // booleano directamente: se particiona en dos listas conservando el orden.
    final favoritos = <LocalServicio>[];
    final resto = <LocalServicio>[];
    for (final ls in lista) {
      if (idsFavoritos.contains(ls.id)) {
        favoritos.add(ls);
      } else {
        resto.add(ls);
      }
    }
    return <LocalServicio>[...favoritos, ...resto];
  }

  /// `true` solo si el horario se pudo interpretar y estamos dentro de la franja.
  /// Un texto ilegible es "no lo sé", nunca "abierto".
  ///
  /// Prefiere `horario_detalle` (punto 10): con el constructor de días, un local
  /// que abre "Lun, Mié, Vie" no se lee como lunes-viernes.
  bool _estaAbierto(LocalServicio ls) =>
      HorarioAtencion.parseConDetalle(
        ls.local?.horarioAtencion,
        ls.local?.horarioDetalle,
      ).evaluar(DateTime.now()) ==
      EstadoHorario.abierto;

  /// Opciones reales del sheet de filtros, deducidas de lo ya cargado.
  OpcionesFiltros _opciones(Set<int> idsFavoritos) {
    final precios = <OfertaPrecio>[];
    final provincias = <String>{};
    final locales = <int, LocalOpcion>{};
    var hayValoraciones = false;

    for (final ls in _localServicios) {
      final precio = precioBaseDe(ls.servicio?.configPrecio);
      if (precio != null) {
        precios.add(OfertaPrecio(precio: precio.precio, moneda: precio.moneda));
      }

      final provincia = ls.local?.provincia?.trim();
      final provinciaValida = (provincia ?? '').isEmpty ? null : provincia;
      if (provinciaValida != null) provincias.add(provinciaValida);

      final local = ls.local;
      if (local != null && local.nombre.trim().isNotEmpty) {
        locales.putIfAbsent(
          local.id,
          () => LocalOpcion(
            id: local.id,
            nombre: local.nombre.trim(),
            provincia: provinciaValida,
          ),
        );
      }

      if ((_resenas[ls.id]?.total ?? 0) > 0) hayValoraciones = true;
    }

    final listaProvincias = provincias.toList()..sort();
    final listaLocales = locales.values.toList()
      ..sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

    return OpcionesFiltros(
      precios: precios,
      provincias: listaProvincias,
      locales: listaLocales,
      hayValoraciones: hayValoraciones,
    );
  }

  /// Abre el sheet de filtros y aplica Lo elegido.
  Future<void> _abrirFiltros() async {
    // Abrir el sheet es la respuesta a la pista flotante: se retira y no vuelve.
    _ocultarPistaFiltros();
    final idsFavoritos = context.read<FavoritosProvider>().ids;
    final query = _searchQuery;

    final elegidos = await mostrarFiltrosServicios(
      context,
      actual: _filtros,
      opciones: _opciones(idsFavoritos),
      contador: _localServicios.isEmpty
          ? null
          : (borrador) => _filtrar(
              _localServicios,
              idsFavoritos: idsFavoritos,
              filtros: borrador,
              query: query,
            ).length,
    );

    if (elegidos == null || !mounted) return;
    setState(() => _filtros = elegidos);

    if (elegidos.hayAlgo && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Filtros aplicados · ${_filtered(idsFavoritos).length} servicios',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Muestra solo los servicios de un establecimiento concreto.
  ///
  /// La llama `HomeShell` al tocar una tarjeta de "Establecimientos" en el Home:
  /// en lugar de abrir el primer servicio del local, se abre esta lista ya
  /// filtrada por él.
  void filtrarPorLocal(int idLocal, String nombreLocal) {
    _searchCtrl.clear();
    setState(() {
      _searchQuery = '';
      // Se parte de cero para que ningún filtro previo (ni "solo favoritos")
      // deje fuera al local que el usuario acaba de tocar.
      _filtros = FiltrosServicios(idLocal: idLocal, nombreLocal: nombreLocal);
    });
  }

  void _clearFiltros() {
    _searchCtrl.clear();
    setState(() {
      _searchQuery = '';
      _filtros = FiltrosServicios.vacio;
    });
  }

  bool get _hayFiltros => _searchQuery.isNotEmpty || _filtros.hayAlgo;

  /// Resumen de los filtros del sheet, para poder quitarlos de uno en uno.
  List<({String etiqueta, VoidCallback quitar})> _resumenFiltros() {
    final filtros = _filtros;
    final resumen = <({String etiqueta, VoidCallback quitar})>[];

    if (filtros.soloFavoritos) {
      resumen.add((
        etiqueta: 'Solo favoritos',
        quitar: () =>
            setState(() => _filtros = _filtros.copyWith(soloFavoritos: false)),
      ));
    }

    if (filtros.precioMin != null || filtros.precioMax != null) {
      final moneda = filtros.moneda;
      String valor(double? v) {
        if (v == null) return '…';
        final texto = v == v.roundToDouble()
            ? v.toStringAsFixed(0)
            : v.toStringAsFixed(2);
        return moneda == null ? texto : '$texto ${MonedasApp.simbolo(moneda)}';
      }

      resumen.add((
        etiqueta:
            'Precio ${valor(filtros.precioMin)} – ${valor(filtros.precioMax)}',
        quitar: () => setState(
          () => _filtros = _filtros.copyWith(precioMin: null, precioMax: null),
        ),
      ));
    }

    if (filtros.moneda != null) {
      resumen.add((
        etiqueta: 'Moneda ${filtros.moneda}',
        quitar: () => setState(
          () => _filtros = _filtros.copyWith(
            moneda: null,
            precioMin: null,
            precioMax: null,
          ),
        ),
      ));
    }

    if (filtros.ratingMinimo != null) {
      final r = filtros.ratingMinimo!;
      resumen.add((
        etiqueta: '${r == r.roundToDouble() ? r.toStringAsFixed(0) : r}★ o más',
        quitar: () =>
            setState(() => _filtros = _filtros.copyWith(ratingMinimo: null)),
      ));
    }

    if (filtros.idLocal != null) {
      resumen.add((
        etiqueta: filtros.nombreLocal ?? 'Establecimiento',
        quitar: () => setState(
          () => _filtros = _filtros.copyWith(idLocal: null, nombreLocal: null),
        ),
      ));
    }

    // La provincia ya no tiene su propia fila de chips en la lista, así que si
    // no se resumiera aquí, se podría activar en el sheet y no verla en
    // ninguna parte (solo el número del botón).
    if (filtros.provincia != null) {
      resumen.add((
        etiqueta: 'Provincia: ${filtros.provincia}',
        quitar: () =>
            setState(() => _filtros = _filtros.copyWith(provincia: null)),
      ));
    }

    if (filtros.soloAbiertos) {
      resumen.add((
        etiqueta: 'Abierto ahora',
        quitar: () =>
            setState(() => _filtros = _filtros.copyWith(soloAbiertos: false)),
      ));
    }

    return resumen;
  }

  @override
  Widget build(BuildContext context) {
    final favoritos = context.watch<FavoritosProvider>();
    final ids = favoritos.ids;
    final lista = _filtered(ids);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SizedBox.expand(
        // `expand` fija las restricciones al tamaño de la pantalla: así el
        // `Stack` no puede encogerse al tamaño de la pista flotante (que es un
        // hijo no posicionado y, sin esto, mandaría en el tamaño).
        child: Stack(
          children: [
            // `Positioned.fill` para que la columna reciba las mismas
            // restricciones que tenía antes de meter el Stack.
            Positioned.fill(
              child: Column(
                children: [
                  // ── Hero con degradado de marca + buscador flotante ──
                  _buildHero(),

                  // ── Chips de filtros activos + contador (en la superficie) ──
                  if (!_isLoading) _buildFiltersBar(lista.length),

                  // ── Lista ─────────────────────────────────────
                  Expanded(
                    child: _isLoading
                        ? _buildLoading()
                        : lista.isEmpty
                        ? _buildEmptyState(ids)
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: AppTheme.primary,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: lista.length,
                              itemBuilder: (_, i) => _LocalServicioCard(
                                localServicio: lista[i],
                                esFavorito: ids.contains(lista[i].id),
                                resenas: _resenas[lista[i].id],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // ── Pista flotante apuntando al botón de filtros ──
            // `CompositedTransformFollower` la ancla al botón real, así que
            // sigue apuntándolo aunque cambie el alto de la cabecera (safe area,
            // fuente del sistema, textos a dos líneas...).
            if (_pistaFiltros && !_isLoading && lista.isNotEmpty)
              CompositedTransformFollower(
                link: _linkFiltros,
                showWhenUnlinked: false,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 10),
                child: PistaBusquedaAvanzada(
                  onTap: _abrirFiltros,
                  onCerrar: _ocultarPistaFiltros,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Cabecera tipo "hero": gradiente de marca con esquinas inferiores
  // redondeadas. Contiene el saludo, el título grande y el buscador como
  // pastilla blanca flotando sobre el degradado.
  Widget _buildHero() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33405F90),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXPLORA',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // const Text(
                        //   'Servicios cerca de ti',
                        //   style: TextStyle(
                        //     color: Colors.white,
                        //     fontSize: 26,
                        //     fontWeight: FontWeight.w800,
                        //     letterSpacing: -0.5,
                        //     height: 1.1,
                        //   ),
                        // ),
                        const SizedBox(height: 4),
                        Text(
                          'Reserva tu turno y evita las filas',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Campana de notificaciones con badge de no leídas.
                  const NotificacionesBell(color: Colors.white),
                ],
              ),
              const SizedBox(height: 20),
              _buildSearchField(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) {
          // La pista apunta a los filtros: en cuanto se busca algo, sobra.
          if (_pistaFiltros && v.isNotEmpty) _ocultarPistaFiltros();
          setState(() => _searchQuery = v);
        },
        style: const TextStyle(fontSize: 14.5, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Buscar servicio o local...',
          hintStyle: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14.5,
          ),
          prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              // Botón de filtros a la derecha del buscador: abre el sheet.
              // Es el ancla de la pista flotante (ver `build`).
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CompositedTransformTarget(
                  link: _linkFiltros,
                  child: _BotonFiltros(
                    activos: _filtros.activos,
                    onTap: _abrirFiltros,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra sobre la lista: solo los filtros **activos** (quitables de uno en
  /// uno) y el contador. Los filtros de provincia y favoritos que antes tenían
  /// su propia fila de chips viven ahora dentro del sheet, que es donde el
  /// usuario los busca; aquí solo queda el resultado de lo ya elegido.
  Widget _buildFiltersBar(int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filtros del sheet, quitables de uno en uno sin volver a abrirlo.
        if (_resumenFiltros().isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final filtro in _resumenFiltros()) ...[
                  _ChipFiltroActivo(
                    label: filtro.etiqueta,
                    onRemove: filtro.quitar,
                  ),
                  const SizedBox(width: 8),
                ],
                GestureDetector(
                  onTap: _clearFiltros,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'Quitar todo',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.error.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
          child: Row(
            children: [
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                total == 1 ? 'servicio disponible' : 'servicios disponibles',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_hayFiltros)
                GestureDetector(
                  onTap: _clearFiltros,
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh,
                        size: 15,
                        color: AppTheme.primary.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Limpiar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          SizedBox(height: 16),
          Text(
            'Cargando servicios...',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Set<int> idsFavoritos) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primary.withValues(alpha: 0.10),
                  AppTheme.accent.withValues(alpha: 0.10),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.travel_explore,
              size: 46,
              color: AppTheme.primary.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _filtros.idLocal != null
                ? 'Sin servicios del establecimiento'
                : 'Nada por aquí todavía',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _filtros.idLocal != null
                ? '${_filtros.nombreLocal ?? 'Ese local'} no tiene servicios '
                      'publicados todavía.'
                : 'Prueba con otra búsqueda o quita algún filtro',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          if (_hayFiltros) ...[
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _clearFiltros,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Limpiar filtros'),
            ),
          ] else if (_opciones(idsFavoritos).hayAlgo) ...[
            // Sin filtros puestos y sin resultados: el camino es la búsqueda
            // avanzada, no seguir cambiando palabras en el buscador.
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _abrirFiltros,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('Búsqueda avanzada'),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}

class _LocalServicioCard extends StatelessWidget {
  final LocalServicio localServicio;

  /// Ya resuelto por el catálogo, para poder repintar la lista al alternar.
  final bool esFavorito;

  /// Reseñas reales del servicio. `null` si no tiene ninguna: entonces no se
  /// pinta ninguna valoración (no se inventa un 0).
  final ResumenResenas? resenas;

  const _LocalServicioCard({
    required this.localServicio,
    this.esFavorito = false,
    this.resenas,
  });

  @override
  Widget build(BuildContext context) {
    final local = localServicio.local;
    final servicio = localServicio.servicio;
    // La foto del servicio manda (punto 9); si no tiene, se cae a la del local,
    // igual que en el Home y en el detalle.
    final foto = servicio?.foto ?? local?.foto;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  LocalServicioDetailScreen(localServicio: localServicio),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Franja de acento vertical: identidad de marca en cada card.
                Container(
                  width: 5,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppTheme.primary, AppTheme.accent],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // ── Avatar / foto del servicio ──
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppTheme.primary.withValues(alpha: 0.14),
                                AppTheme.accent.withValues(alpha: 0.14),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: foto != null
                              ? NetImage(
                                  url: foto,
                                  fit: BoxFit.cover,
                                  errorWidget: () => const Icon(
                                    Icons.design_services_outlined,
                                    color: AppTheme.primary,
                                    size: 30,
                                  ),
                                )
                              : const Icon(
                                  Icons.design_services_outlined,
                                  color: AppTheme.primary,
                                  size: 30,
                                ),
                        ),
                        const SizedBox(width: 14),

                        // ── Datos ──
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Principal: nombre del servicio (+ valoración real)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      servicio?.nombre ?? 'Servicio',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: AppTheme.textPrimary,
                                        letterSpacing: -0.3,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (resenas != null && resenas!.hayDatos) ...[
                                    const SizedBox(width: 6),
                                    _RatingChip(resenas: resenas!),
                                  ],
                                ],
                              ),
                              // Secundario: nombre del local
                              if (local != null) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.storefront_outlined,
                                      size: 12,
                                      color: AppTheme.accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        local.nombre,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppTheme.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                // Terciario: ubicación
                                if (local.ubicacion.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  _InfoLinea(
                                    icon: Icons.location_city_outlined,
                                    texto: local.ubicacion,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // ── Favorito + indicador de navegación ──
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            BotonFavorito(
                              idLocalServicio: localServicio.id,
                              titulo: servicio?.nombre ?? 'Servicio',
                              saved: esFavorito,
                              size: 34,
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.arrow_forward_ios,
                                color: AppTheme.primary,
                                size: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

/// Botón de filtros que vive a la derecha del buscador.
///
/// Cuando hay filtros activos cambia a degradado de marca y muestra cuántos
/// son, para que no se puedan "perder" dentro del sheet.
class _BotonFiltros extends StatelessWidget {
  final int activos;
  final VoidCallback onTap;

  const _BotonFiltros({required this.activos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hay = activos > 0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: hay
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primary, AppTheme.accent],
                )
              : null,
          color: hay ? null : AppTheme.surface,
          borderRadius: BorderRadius.circular(13),
          boxShadow: hay
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.30),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.tune_rounded,
              size: 21,
              color: hay ? Colors.white : AppTheme.primary,
            ),
            if (hay)
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(minWidth: 15),
                  child: Text(
                    '$activos',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pill de un filtro activo: se quita con la X sin volver a abrir el sheet.
class _ChipFiltroActivo extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ChipFiltroActivo({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: const Icon(Icons.close_rounded, color: AppTheme.primary),
            tooltip: 'Quitar filtro',
          ),
        ],
      ),
    );
  }
}

/// Valoración real del servicio dentro de la tarjeta del catálogo.
class _RatingChip extends StatelessWidget {
  final ResumenResenas resenas;

  const _RatingChip({required this.resenas});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 13, color: AppTheme.warning),
          const SizedBox(width: 2),
          Text(
            resenas.promedio.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '(${resenas.total})',
            style: const TextStyle(
              fontSize: 10.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// Línea de info con ícono + texto truncable (ubicación, dirección).
class _InfoLinea extends StatelessWidget {
  final IconData icon;
  final String texto;
  final bool bold;

  const _InfoLinea({
    required this.icon,
    required this.texto,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.textSecondary,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
