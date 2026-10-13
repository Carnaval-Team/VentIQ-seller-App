import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/config_precio.dart';

/// Filtros que se pueden aplicar a una lista de servicios.
///
/// Es una clase **de valor**: el Home y el catálogo guardan una instancia, y el
/// sheet edita una copia (`borrador`) que solo se aplica al confirmar. Así,
/// cerrar el sheet sin pulsar "Aplicar" no cambia nada.
///
/// La coincidencia se resuelve aquí y no en cada pantalla porque el Home
/// (`HomeCatalogItem`) y el catálogo (`LocalServicio`) tienen modelos distintos:
/// cada uno pasa los primitivos que ya tiene y la regla vive en un único sitio.
@immutable
class FiltrosServicios {
  const FiltrosServicios({
    this.moneda,
    this.precioMin,
    this.precioMax,
    this.provincia,
    this.idLocal,
    this.nombreLocal,
    this.idSubcategoria,
    this.nombreSubcategoria,
    this.ratingMinimo,
    this.soloAbiertos = false,
    this.soloFavoritos = false,
  });

  static const FiltrosServicios vacio = FiltrosServicios();

  /// `null` = todas las monedas.
  final String? moneda;

  /// Rango de precio en la moneda elegida. `null` en los dos = sin límite.
  final double? precioMin;
  final double? precioMax;

  /// `null` = todas las provincias.
  final String? provincia;

  /// Establecimiento (local) concreto. El nombre solo se guarda para poder
  /// pintar el chip sin volver a buscar el local.
  final int? idLocal;
  final String? nombreLocal;

  /// Subcategoría concreta (`nom_tipo_actividad_servicio.id_padre is not null`).
  /// `null` = todas las subcategorías de la categoría elegida.
  ///
  /// Vive aquí además de en el riel del Home porque el catálogo también filtra
  /// por ella: así la regla de coincidencia es una sola para las dos pantallas.
  final int? idSubcategoria;
  final String? nombreSubcategoria;

  /// Valoración mínima (1..5). `null` = cualquiera.
  final double? ratingMinimo;

  /// Solo locales que a esta hora están abiertos **según su horario**, no según
  /// una suposición: un horario ilegible no cuenta como abierto.
  final bool soloAbiertos;

  /// Solo los servicios guardados como favoritos.
  ///
  /// Vive aquí y no en la barra del catálogo para que **todos** los filtros se
  /// elijan en el mismo sitio: antes era un chip suelto encima de la lista, con
  /// lo que el usuario tenía que saber que existía para poder usarlo.
  final bool soloFavoritos;

  /// Sentinel para distinguir "no toques este campo" de "ponlo a `null`".
  static const Object _sinCambio = Object();

  FiltrosServicios copyWith({
    Object? moneda = _sinCambio,
    Object? precioMin = _sinCambio,
    Object? precioMax = _sinCambio,
    Object? provincia = _sinCambio,
    Object? idLocal = _sinCambio,
    Object? nombreLocal = _sinCambio,
    Object? idSubcategoria = _sinCambio,
    Object? nombreSubcategoria = _sinCambio,
    Object? ratingMinimo = _sinCambio,
    bool? soloAbiertos,
    bool? soloFavoritos,
  }) {
    return FiltrosServicios(
      moneda: identical(moneda, _sinCambio) ? this.moneda : moneda as String?,
      precioMin: identical(precioMin, _sinCambio)
          ? this.precioMin
          : precioMin as double?,
      precioMax: identical(precioMax, _sinCambio)
          ? this.precioMax
          : precioMax as double?,
      provincia: identical(provincia, _sinCambio)
          ? this.provincia
          : provincia as String?,
      idLocal: identical(idLocal, _sinCambio) ? this.idLocal : idLocal as int?,
      nombreLocal: identical(nombreLocal, _sinCambio)
          ? this.nombreLocal
          : nombreLocal as String?,
      idSubcategoria: identical(idSubcategoria, _sinCambio)
          ? this.idSubcategoria
          : idSubcategoria as int?,
      nombreSubcategoria: identical(nombreSubcategoria, _sinCambio)
          ? this.nombreSubcategoria
          : nombreSubcategoria as String?,
      ratingMinimo: identical(ratingMinimo, _sinCambio)
          ? this.ratingMinimo
          : ratingMinimo as double?,
      soloAbiertos: soloAbiertos ?? this.soloAbiertos,
      soloFavoritos: soloFavoritos ?? this.soloFavoritos,
    );
  }

  bool get hayAlgo =>
      moneda != null ||
      precioMin != null ||
      precioMax != null ||
      provincia != null ||
      idLocal != null ||
      idSubcategoria != null ||
      ratingMinimo != null ||
      soloAbiertos ||
      soloFavoritos;

  /// Cuántas decisiones ha tomado el usuario. Alimenta el badge del botón.
  int get activos {
    var total = 0;
    if (moneda != null) total++;
    if (precioMin != null || precioMax != null) total++;
    if (provincia != null) total++;
    if (idLocal != null) total++;
    if (idSubcategoria != null) total++;
    if (ratingMinimo != null) total++;
    if (soloAbiertos) total++;
    if (soloFavoritos) total++;
    return total;
  }

  /// `true` si el servicio descrito por los primitivos pasa los filtros.
  ///
  /// Cada parámetro es opcional: `null` significa "no tengo ese dato", y en ese
  /// caso el servicio **queda fuera** solo si hay un filtro que lo exige. Nunca
  /// se le supone un valor que no existe (mismo criterio que las estrellas del
  /// feed: un servicio sin reseñas no vale 0 estrellas, simplemente no tiene).
  bool coincide({
    double? precioItem,
    String? monedaItem,
    String? provinciaItem,
    double? ratingItem,
    int? idLocalItem,
    int? idSubcategoriaItem,
    bool? abiertoItem,
    bool? esFavoritoItem,
  }) {
    if (moneda != null && monedaItem != moneda) return false;

    if (precioMin != null && (precioItem == null || precioItem < precioMin!)) {
      return false;
    }
    if (precioMax != null && (precioItem == null || precioItem > precioMax!)) {
      return false;
    }

    if (provincia != null && provinciaItem != provincia) return false;

    if (idLocal != null && idLocalItem != idLocal) return false;

    // Un servicio en la categoría sin subcategoría no pasa un filtro de
    // subcategoría: no se le supone una que no tiene.
    if (idSubcategoria != null && idSubcategoriaItem != idSubcategoria) {
      return false;
    }

    if (ratingMinimo != null &&
        (ratingItem == null || ratingItem < ratingMinimo!)) {
      return false;
    }

    // Un horario que no se pudo interpretar no es "abierto".
    if (soloAbiertos && abiertoItem != true) return false;

    // "Solo favoritos" se resuelve con el conjunto de ids que ya tiene la
    // pantalla: quien no tiene ese dato (el Home no filtra por guardados) no se
    // ve afectado porque el filtro solo se ofrece cuando hay favoritos.
    if (soloFavoritos && esFavoritoItem != true) return false;

    return true;
  }
}

/// Un precio con su moneda, tal como sale del catálogo cargado.
@immutable
class OfertaPrecio {
  const OfertaPrecio({required this.precio, required this.moneda});

  final double precio;
  final String moneda;
}

/// Un establecimiento elegible como filtro.
@immutable
class LocalOpcion {
  const LocalOpcion({required this.id, required this.nombre, this.provincia});

  final int id;
  final String nombre;
  final String? provincia;
}

/// Una subcategoría elegible como filtro, con el nombre de su categoría.
@immutable
class SubcategoriaOpcion {
  const SubcategoriaOpcion({
    required this.id,
    required this.nombre,
    this.categoria,
  });

  final int id;
  final String nombre;

  /// Nombre de la categoría a la que pertenece. Se usa para agrupar la lista.
  final String? categoria;

  /// `"Belleza › Uñas / Manicure"`, o solo el nombre si no hay categoría.
  String get etiqueta =>
      (categoria == null || categoria!.trim().isEmpty)
      ? nombre
      : '${categoria!.trim()} › $nombre';
}

/// Lo que el sheet puede ofrecer, deducido de **los datos ya cargados**.
///
/// No se inventa ninguna opción: si el catálogo no trae precios, la sección de
/// precio no se pinta; si nadie tiene reseñas, la de valoración tampoco. Antes
/// que un control que filtra a cero, no hay control.
@immutable
class OpcionesFiltros {
  const OpcionesFiltros({
    this.precios = const <OfertaPrecio>[],
    this.provincias = const <String>[],
    this.locales = const <LocalOpcion>[],
    this.subcategorias = const <SubcategoriaOpcion>[],
    this.hayValoraciones = false,
    this.hayFavoritos = false,
    this.totalFavoritos = 0,
  });

  final List<OfertaPrecio> precios;
  final List<String> provincias;
  final List<LocalOpcion> locales;

  /// Subcategorías presentes en el catálogo cargado (solo las que tienen algún
  /// servicio). Si la migración 47 no está aplicada llega vacía y la sección no
  /// se pinta.
  final List<SubcategoriaOpcion> subcategorias;

  final bool hayValoraciones;

  /// Si el usuario tiene guardados y la tabla de favoritos está disponible. La
  /// pantalla que sí puede filtrar por guardados lo pone a `true`.
  final bool hayFavoritos;
  final int totalFavoritos;

  bool get hayPrecios => precios.isNotEmpty;
  bool get hayProvincias => provincias.isNotEmpty;
  bool get hayLocales => locales.isNotEmpty;
  bool get haySubcategorias => subcategorias.isNotEmpty;

  /// Monedas presentes, ordenadas según el catálogo de la app.
  List<String> get monedas {
    final presentes = <String>{for (final p in precios) p.moneda};
    final ordenadas = <String>[
      for (final m in MonedasApp.todas)
        if (presentes.contains(m)) m,
    ];
    ordenadas.addAll(
      presentes.where((m) => !ordenadas.contains(m)).toList()..sort(),
    );
    return ordenadas;
  }

  /// Extremos de precio para una moneda (`null` = todas juntas).
  ///
  /// Mezclar monedas en un mismo rango no significa nada (1 000 CUP no es más
  /// caro que 20 USD), así que al elegir una moneda el rango se recalcula.
  ({double min, double max})? rangoPrecio(String? moneda) {
    final valores = [
      for (final p in precios)
        if (moneda == null || p.moneda == moneda) p.precio,
    ];
    if (valores.isEmpty) return null;
    var min = valores.first;
    var max = valores.first;
    for (final v in valores) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    return (min: min, max: max);
  }

  /// ¿Hay algo que filtrar? Si no, el botón de filtros no debe ofrecerse.
  bool get hayAlgo =>
      hayPrecios ||
      hayProvincias ||
      hayLocales ||
      haySubcategorias ||
      hayValoraciones ||
      hayFavoritos;
}

/// Abre el sheet de filtros y devuelve los elegidos, o `null` si se cerró sin
/// aplicar.
///
/// [contador] permite enseñar en vivo cuántos servicios quedarían con el
/// borrador actual: quien abre el sheet ya tiene la lista cargada, así que el
/// número es gratis y el usuario no aplica a ciegas.
Future<FiltrosServicios?> mostrarFiltrosServicios(
  BuildContext context, {
  required FiltrosServicios actual,
  required OpcionesFiltros opciones,
  int Function(FiltrosServicios)? contador,
}) {
  return showModalBottomSheet<FiltrosServicios>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.84,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      expand: false,
      snap: true,
      snapSizes: const [0.45, 0.84, 0.96],
      builder: (_, scrollController) => _FiltrosSheet(
        actual: actual,
        opciones: opciones,
        contador: contador,
        scrollController: scrollController,
      ),
    ),
  );
}

class _FiltrosSheet extends StatefulWidget {
  const _FiltrosSheet({
    required this.actual,
    required this.opciones,
    required this.scrollController,
    this.contador,
  });

  final FiltrosServicios actual;
  final OpcionesFiltros opciones;
  final ScrollController scrollController;
  final int Function(FiltrosServicios)? contador;

  @override
  State<_FiltrosSheet> createState() => _FiltrosSheetState();
}

class _FiltrosSheetState extends State<_FiltrosSheet> {
  late FiltrosServicios _borrador = widget.actual;

  final TextEditingController _buscarLocal = TextEditingController();
  bool _todosLosLocales = false;

  @override
  void dispose() {
    _buscarLocal.dispose();
    super.dispose();
  }

  int? get _coincidencias => widget.contador?.call(_borrador);

  void _aplicar(FiltrosServicios filtros) =>
      setState(() => _borrador = filtros);

  void _limpiar() {
    _buscarLocal.clear();
    setState(() {
      _borrador = FiltrosServicios.vacio;
      _todosLosLocales = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final coincidencias = _coincidencias;
    final hayResultados = coincidencias == null || coincidencias > 0;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: Container(
        color: AppTheme.surface,
        child: Column(
          children: [
            _buildCabecera(),
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (widget.opciones.hayFavoritos) ...[
                    _buildSeccionFavoritos(),
                    const SizedBox(height: 14),
                  ],
                  if (widget.opciones.hayPrecios) ...[
                    _buildSeccionMoneda(),
                    const SizedBox(height: 14),
                  ],
                  _buildSeccionPrecio(),
                  if (widget.opciones.hayValoraciones) ...[
                    const SizedBox(height: 14),
                    _buildSeccionValoracion(),
                  ],
                  if (widget.opciones.hayProvincias) ...[
                    const SizedBox(height: 14),
                    _buildSeccionProvincia(),
                  ],
                  if (widget.opciones.hayLocales) ...[
                    const SizedBox(height: 14),
                    _buildSeccionEstablecimiento(),
                  ],
                  if (widget.opciones.haySubcategorias) ...[
                    const SizedBox(height: 14),
                    _buildSeccionSubcategoria(),
                  ],
                  const SizedBox(height: 14),
                  _buildSeccionExtras(),
                ],
              ),
            ),
            _buildPie(coincidencias, hayResultados),
          ],
        ),
      ),
    );
  }

  // ── Cabecera con degradado y contador en vivo ──────────────────────────
  Widget _buildCabecera() {
    final coincidencias = _coincidencias;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filtra los servicios',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      coincidencias == null
                          ? 'Ajusta lo que quieres ver'
                          : coincidencias == 1
                          ? '1 servicio coincide ahora mismo'
                          : '$coincidencias servicios coinciden ahora mismo',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_borrador.activos > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_borrador.activos} activo${_borrador.activos == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Secciones ──────────────────────────────────────────────────────────
  /// Solo los servicios guardados.
  ///
  /// Antes era un chip encima de la lista del catálogo; se trajo aquí para que
  /// todos los filtros se elijan en el mismo sitio (y para que el contador de
  /// "cuántos quedarían" lo tenga en cuenta igual que el resto).
  Widget _buildSeccionFavoritos() {
    final total = widget.opciones.totalFavoritos;
    return _Seccion(
      icono: Icons.favorite_rounded,
      color: AppTheme.error,
      titulo: 'Guardados',
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _borrador.soloFavoritos,
          onChanged: (v) => _aplicar(_borrador.copyWith(soloFavoritos: v)),
          title: const Text(
            'Solo favoritos',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          subtitle: Text(
            total == 1
                ? 'El servicio que guardaste con el corazón.'
                : 'Los $total servicios que guardaste con el corazón.',
            style: const TextStyle(fontSize: 11.5),
          ),
          secondary: const Icon(Icons.favorite_rounded),
        ),
      ),
    );
  }

  Widget _buildSeccionPrecio() {
    if (!widget.opciones.hayPrecios) {
      return _Seccion(
        icono: Icons.attach_money_rounded,
        color: AppTheme.success,
        titulo: 'Precio',
        subtitulo: 'Ningún servicio de la lista tiene precio configurado.',
        child: const SizedBox.shrink(),
      );
    }

    // Con una sola moneda el rango ya es comparable sin elegir nada. Con
    // varias, filtrar por 10–50 mezclaría dólares con pesos: no significa nada,
    // así que primero se pide la moneda en lugar de ofrecer un control falso.
    final monedas = widget.opciones.monedas;
    final monedaEfectiva =
        _borrador.moneda ?? (monedas.length == 1 ? monedas.first : null);

    if (monedaEfectiva == null) {
      return _Seccion(
        icono: Icons.attach_money_rounded,
        color: AppTheme.success,
        titulo: 'Precio',
        subtitulo: 'Este catálogo tiene servicios en varias monedas.',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppTheme.textSecondary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Elige una moneda arriba para poder comparar precios.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final rango = widget.opciones.rangoPrecio(monedaEfectiva)!;
    final min = rango.min;
    final max = rango.max;
    final sinRango = max - min < 0.01;

    final seleccionado = RangeValues(
      (_borrador.precioMin ?? min).clamp(min, max),
      (_borrador.precioMax ?? max).clamp(min, max),
    );

    return _Seccion(
      icono: Icons.attach_money_rounded,
      color: AppTheme.success,
      titulo: 'Precio',
      subtitulo: 'Rango en $monedaEfectiva.',
      child: sinRango
          ? Text(
              'Todos los servicios están en '
              '${_etiquetaPrecio(min, monedaEfectiva)}.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PrecioPill(
                      texto: _etiquetaPrecio(
                        seleccionado.start,
                        monedaEfectiva,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.horizontal_rule_rounded,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    _PrecioPill(
                      texto: _etiquetaPrecio(seleccionado.end, monedaEfectiva),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.primary,
                    inactiveTrackColor: AppTheme.primary.withValues(
                      alpha: 0.15,
                    ),
                    thumbColor: Colors.white,
                    overlayColor: AppTheme.primary.withValues(alpha: 0.12),
                    rangeThumbShape: const RoundRangeSliderThumbShape(
                      enabledThumbRadius: 11,
                      elevation: 3,
                    ),
                  ),
                  child: RangeSlider(
                    min: min,
                    max: max,
                    values: seleccionado,
                    onChanged: (v) => _aplicar(
                      _borrador.copyWith(precioMin: v.start, precioMax: v.end),
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PresetPrecio(
                      label: 'Todos',
                      activo:
                          _borrador.precioMin == null &&
                          _borrador.precioMax == null,
                      onTap: () => _aplicar(
                        _borrador.copyWith(precioMin: null, precioMax: null),
                      ),
                    ),
                    ..._presets(min, max).map(
                      (p) => _PresetPrecio(
                        label:
                            '${_etiquetaPrecio(p.$1, monedaEfectiva)} – '
                            '${_etiquetaPrecio(p.$2, monedaEfectiva)}',
                        activo:
                            _borrador.precioMin == p.$1 &&
                            _borrador.precioMax == p.$2,
                        onTap: () => _aplicar(
                          _borrador.copyWith(precioMin: p.$1, precioMax: p.$2),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Cuartiles redondeados: cuatro tramos reales de **este** catálogo, no
  /// cortes fijos que en un catálogo barato no separarían nada.
  List<(double, double)> _presets(double min, double max) {
    double r(double v) {
      if (v >= 100) return (v / 10).round() * 10;
      if (v >= 10) return (v / 5).round() * 5;
      return v.roundToDouble();
    }

    final a = r(min + (max - min) * 0.25);
    final b = r(min + (max - min) * 0.5);
    final c = r(min + (max - min) * 0.75);
    final tramos = <(double, double)>[(min, a), (a, b), (b, c), (c, max)];
    // Un tramo vacío o repetido solo confunde.
    return tramos.where((t) => t.$2 - t.$1 > 0.01).toList();
  }

  String _etiquetaPrecio(double valor, String? moneda) {
    final monto = valor == valor.roundToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(2);
    if (moneda == null) return monto;
    return '$monto ${MonedasApp.simbolo(moneda)}';
  }

  Widget _buildSeccionMoneda() {
    final monedas = widget.opciones.monedas;
    return _Seccion(
      icono: Icons.payments_outlined,
      color: AppTheme.primary,
      titulo: 'Moneda',
      subtitulo: 'Comparar precios entre monedas distintas no dice nada.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ChipOpcion(
            label: 'Todas',
            seleccionado: _borrador.moneda == null,
            onTap: () => _aplicar(
              _borrador.copyWith(
                moneda: null,
                precioMin: null,
                precioMax: null,
              ),
            ),
          ),
          ...monedas.map(
            (m) => _ChipOpcion(
              label: '${MonedasApp.simbolo(m)} $m',
              seleccionado: _borrador.moneda == m,
              onTap: () => _aplicar(
                _borrador.copyWith(
                  moneda: m,
                  // El rango anterior era de otra moneda: se descarta.
                  precioMin: null,
                  precioMax: null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionValoracion() {
    const opciones = <(double, String)>[
      (3, '3★ o más'),
      (3.5, '3.5★ o más'),
      (4, '4★ o más'),
      (4.5, '4.5★ o más'),
    ];
    return _Seccion(
      icono: Icons.star_rounded,
      color: AppTheme.warning,
      titulo: 'Valoración',
      subtitulo:
          'Sale de reseñas reales. Un servicio sin reseñas no aparece al filtrar.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ChipOpcion(
            label: 'Cualquiera',
            seleccionado: _borrador.ratingMinimo == null,
            onTap: () => _aplicar(_borrador.copyWith(ratingMinimo: null)),
          ),
          ...opciones.map(
            (o) => _ChipOpcion(
              label: o.$2,
              icono: Icons.star_rounded,
              seleccionado: _borrador.ratingMinimo == o.$1,
              onTap: () => _aplicar(_borrador.copyWith(ratingMinimo: o.$1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionProvincia() {
    return _Seccion(
      icono: Icons.map_outlined,
      color: AppTheme.accent,
      titulo: 'Provincia',
      subtitulo: 'Solo los locales con provincia registrada.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ChipOpcion(
            label: 'Todas',
            seleccionado: _borrador.provincia == null,
            onTap: () => _aplicar(_borrador.copyWith(provincia: null)),
          ),
          ...widget.opciones.provincias.map(
            (p) => _ChipOpcion(
              label: p,
              icono: Icons.place_outlined,
              seleccionado: _borrador.provincia == p,
              onTap: () => _aplicar(_borrador.copyWith(provincia: p)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionEstablecimiento() {
    final consulta = _buscarLocal.text.trim().toLowerCase();
    final todos = widget.opciones.locales;
    var visibles = consulta.isEmpty
        ? todos
        : todos
              .where(
                (l) =>
                    l.nombre.toLowerCase().contains(consulta) ||
                    (l.provincia ?? '').toLowerCase().contains(consulta),
              )
              .toList();
    final recortados = consulta.isEmpty && !_todosLosLocales;
    if (recortados && visibles.length > 5) {
      visibles = visibles.take(5).toList();
    }

    return _Seccion(
      icono: Icons.storefront_outlined,
      color: AppTheme.primaryLight,
      titulo: 'Establecimiento',
      subtitulo: 'Ver solo lo que publica un local concreto.',
      child: Column(
        children: [
          TextField(
            controller: _buscarLocal,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar local...',
              hintStyle: const TextStyle(
                fontSize: 13.5,
                color: AppTheme.textSecondary,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 19,
                color: AppTheme.textSecondary,
              ),
              suffixIcon: consulta.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _buscarLocal.clear();
                        setState(() {});
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppTheme.primary,
                  width: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (visibles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Ningún local coincide con esa búsqueda.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            )
          else
            ...visibles.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LocalTile(
                  local: l,
                  seleccionado: _borrador.idLocal == l.id,
                  onTap: () {
                    final yaEstaba = _borrador.idLocal == l.id;
                    _aplicar(
                      yaEstaba
                          ? _borrador.copyWith(idLocal: null, nombreLocal: null)
                          : _borrador.copyWith(
                              idLocal: l.id,
                              nombreLocal: l.nombre,
                            ),
                    );
                  },
                ),
              ),
            ),
          if (recortados && todos.length > 5)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _todosLosLocales = true),
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: Text('Ver los ${todos.length} establecimientos'),
              ),
            ),
        ],
      ),
    );
  }

  /// Subcategoría: es un segundo nivel dentro de la categoría.
  ///
  /// Solo se ofrecen las que **tienen algún servicio en el catálogo cargado**:
  /// elegir una subcategoría vacía llevaría a "0 resultados" sin explicación.
  Widget _buildSeccionSubcategoria() {
    final opciones = widget.opciones.subcategorias;
    return _Seccion(
      icono: Icons.account_tree_outlined,
      color: AppTheme.accent,
      titulo: 'Subcategoría',
      subtitulo: 'Un nivel más fino dentro de la categoría del servicio.',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ChipOpcion(
            label: 'Todas',
            seleccionado: _borrador.idSubcategoria == null,
            onTap: () => _aplicar(
              _borrador.copyWith(
                idSubcategoria: null,
                nombreSubcategoria: null,
              ),
            ),
          ),
          ...opciones.map(
            (s) => _ChipOpcion(
              label: s.etiqueta,
              icono: Icons.label_outline_rounded,
              seleccionado: _borrador.idSubcategoria == s.id,
              onTap: () {
                final yaEstaba = _borrador.idSubcategoria == s.id;
                _aplicar(
                  yaEstaba
                      ? _borrador.copyWith(
                          idSubcategoria: null,
                          nombreSubcategoria: null,
                        )
                      : _borrador.copyWith(
                          idSubcategoria: s.id,
                          nombreSubcategoria: s.nombre,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionExtras() {
    return _Seccion(
      icono: Icons.bolt_rounded,
      color: AppTheme.warning,
      titulo: 'Ahora mismo',
      // El ListTile necesita un Material propio: si no, pinta su tinta sobre el
      // `DecoratedBox` de la sección y el framework avisa de que no se vería.
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _borrador.soloAbiertos,
          onChanged: (v) => _aplicar(_borrador.copyWith(soloAbiertos: v)),
          title: const Text(
            'Abierto ahora',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
          subtitle: const Text(
            'Según el horario que cada local tiene registrado. Si el horario no '
            'se puede leer, no se cuenta como abierto.',
            style: TextStyle(fontSize: 11.5),
          ),
          secondary: const Icon(Icons.schedule_rounded),
        ),
      ),
    );
  }

  Widget _buildPie(int? coincidencias, bool hayResultados) {
    final activos = _borrador.activos;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          if (activos > 0)
            TextButton.icon(
              onPressed: _limpiar,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Limpiar'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
              ),
            ),
          if (activos > 0) const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: hayResultados
                    ? () => Navigator.pop(context, _borrador)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: Icon(
                  hayResultados
                      ? Icons.check_rounded
                      : Icons.search_off_rounded,
                  size: 19,
                ),
                label: Text(
                  coincidencias == null
                      ? 'Aplicar filtros'
                      : coincidencias == 0
                      ? 'Sin resultados'
                      : coincidencias == 1
                      ? 'Ver 1 servicio'
                      : 'Ver $coincidencias servicios',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Piezas de UI ─────────────────────────────────────────────────────────

class _Seccion extends StatelessWidget {
  const _Seccion({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.child,
    this.subtitulo,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String? subtitulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icono, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitulo!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ChipOpcion extends StatelessWidget {
  const _ChipOpcion({
    required this.label,
    required this.seleccionado,
    required this.onTap,
    this.icono,
  });

  final String label;
  final bool seleccionado;
  final VoidCallback onTap;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: seleccionado ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: seleccionado ? AppTheme.primary : AppTheme.border,
          ),
          boxShadow: seleccionado
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(
                icono,
                size: 15,
                color: seleccionado ? Colors.white : AppTheme.warning,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: seleccionado ? FontWeight.w800 : FontWeight.w600,
                color: seleccionado ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetPrecio extends StatelessWidget {
  const _PresetPrecio({
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: activo
              ? AppTheme.success.withValues(alpha: 0.12)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: activo ? AppTheme.success : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: activo ? FontWeight.w800 : FontWeight.w600,
            color: activo ? AppTheme.success : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PrecioPill extends StatelessWidget {
  const _PrecioPill({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w800,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}

class _LocalTile extends StatelessWidget {
  const _LocalTile({
    required this.local,
    required this.seleccionado,
    required this.onTap,
  });

  final LocalOpcion local;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inicial = local.nombre.trim().isEmpty
        ? '?'
        : local.nombre.trim()[0].toUpperCase();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: seleccionado
              ? AppTheme.primary.withValues(alpha: 0.07)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: seleccionado ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.16),
                    AppTheme.accent.withValues(alpha: 0.16),
                  ],
                ),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                inicial,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    local.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: seleccionado
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if ((local.provincia ?? '').trim().isNotEmpty)
                    Text(
                      local.provincia!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: seleccionado ? AppTheme.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: seleccionado ? AppTheme.primary : AppTheme.border,
                  width: 1.6,
                ),
              ),
              child: seleccionado
                  ? const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
