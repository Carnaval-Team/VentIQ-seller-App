import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/ficha_local.dart';
import '../models/servicio.dart';
import '../services/campana_service.dart';
import '../services/catalogo_service.dart';
import '../services/tipo_actividad_service.dart';
import '../tutorial/tutorial_anchor.dart';
import '../utils/horario_atencion.dart';
import '../utils/precio_reserva.dart';
import '../widgets/barra_navegacion_cliente.dart';
import '../widgets/net_image.dart';
import '../widgets/resenas.dart';
import 'local_servicio_detail_screen.dart';

/// Ficha comercial de un establecimiento: la vista que comparten el espacio
/// patrocinado y el listado de establecimientos.
///
/// POR QUE EXISTE
///   Antes, tocar una tarjeta patrocinada abría el detalle de UN servicio, que no
///   es lo que promete el espacio patrocinado: la campaña presenta un
///   **establecimiento**. Esa vista (imagen grande, descripción, datos de
///   contacto, horario y **todos** sus servicios reservables) es exactamente la
///   que quiere ver quien toca un establecimiento en el listado, así que se pinta
///   en un solo sitio. `EspacioPatrocinadoScreen` se queda como envoltorio que
///   pasa la campaña; el listado le pasa la ficha normal.
///
/// DOS MODOS, UNA PANTALLA
///   * Con campaña (`campana != null`): sello «ESPACIO PATROCINADO», degradado de
///     la campaña y bloque «DESTACADO DEL MOMENTO». Es el comportamiento de
///     siempre, intacto.
///   * Sin campaña: sello «ESTABLECIMIENTO», degradado de marca y, en vez del
///     bloque de campaña, la valoración real del local y su número de servicios.
///     Sin campaña no se anuncia NADA de campaña.
///   El modo lo decide `campana` y no `ficha.destacado` a propósito: el envoltorio
///   patrocinado pasa las dos cosas y así el modo queda explícito en el punto de
///   uso, sin depender de que un campo se rellene bien en el modelo.
///
/// DE DONDE SALE CADA DATO
///   * Todo lo del local llega ya normalizado en [FichaLocal]
///     (`desdeCampana` / `desdeEstablecimiento`), para que aquí no haya dos ramas
///     de pintado con campos distintos: es como se acaba mostrando «null».
///   * Servicios del local: `flow.cliente_obtener_servicios(p_id_local)` — la
///     misma regla de visibilidad que el resto del cliente (`_ls_disponible`).
///   * Categoría y subcategoría de cada servicio: `flow.nom_tipo_actividad_servicio`
///     leído una vez y resuelto en memoria (migración 47).
///
/// NADA DE ESTA PANTALLA CAMBIA EL PRECIO. La campaña solo destaca: el importe lo
/// fija el servidor al reservar, igual que desde el catálogo.
class FichaLocalScreen extends StatefulWidget {
  const FichaLocalScreen({
    super.key,
    required this.ficha,
    this.campana,
    this.serviciosIniciales,
  });

  final FichaLocal ficha;

  /// La campaña cuando la ficha viene del espacio patrocinado. `null` = ficha
  /// normal del listado de establecimientos.
  final CampanaPatrocinada? campana;

  /// Servicios ya resueltos, **solo para tests de widget**.
  ///
  /// La lista de servicios se pide al RPC y en un test eso no puede responder:
  /// inyectándola se ejercita el cuerpo entero (cabecera, chips, contacto y
  /// estado vacío) sin tocar Supabase. En la app siempre es `null`.
  @visibleForTesting
  final List<LocalServicio>? serviciosIniciales;

  @override
  State<FichaLocalScreen> createState() => _FichaLocalScreenState();
}

class _FichaLocalScreenState extends State<FichaLocalScreen> {
  List<LocalServicio> _servicios = const [];
  Taxonomia _taxonomia = Taxonomia.vacia;
  bool _cargando = true;
  bool _error = false;

  FichaLocal get _ficha => widget.ficha;

  /// `true` cuando la ficha se pinta como espacio patrocinado.
  bool get _patrocinada => widget.campana != null;

  /// Segunda línea de la cabecera: el titular de la campaña o quién publica el
  /// local. Con campaña, `FichaLocal.desdeCampana` ya la resolvió (el titular si
  /// el nombre grande es el local, o su subtítulo si no).
  String get _lineaSecundaria => _ficha.titular?.trim() ?? '';

  /// Nombre del local, nunca vacío: con un nombre en blanco los textos que lo
  /// intercalan («Sobre X», «Lo que puedes reservar en X») quedarían cojos.
  String get _nombreLocal {
    final nombre = _ficha.nombre.trim();
    return nombre.isEmpty ? 'este establecimiento' : nombre;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final inyectados = widget.serviciosIniciales;
    if (inyectados != null) {
      setState(() {
        _servicios = inyectados;
        _taxonomia = Taxonomia.vacia;
        _cargando = false;
        _error = false;
      });
      return;
    }
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      // La taxonomía es una lectura pública y pequeña: se pide en paralelo con
      // los servicios para no encadenar dos esperas.
      final resultados = await Future.wait<Object>([
        _ficha.idLocal == null
            ? Future<List<LocalServicio>>.value(const <LocalServicio>[])
            : CatalogoService.getLocalServicios(idLocal: _ficha.idLocal!),
        TipoActividadService.taxonomia(soloActivos: true),
      ]);
      if (!mounted) return;
      setState(() {
        _servicios = resultados[0] as List<LocalServicio>;
        _taxonomia = resultados[1] as Taxonomia;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
      });
      debugPrint('[flow] FichaLocalScreen._cargar ERROR: $e');
    }
  }

  void _abrirServicio(LocalServicio localServicio) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalServicioDetailScreen(localServicio: localServicio),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      // Misma barra del cliente que el shell: la ficha es una ruta apilada y, sin
      // esto, cambiaba la navegación de sitio (el espacio patrocinado tampoco la
      // tenía). Se marca «Inicio» porque la ficha se abre desde el Home y desde
      // el listado de establecimientos, que también cuelga de él.
      bottomNavigationBar: BarraNavegacionCliente.dePantalla(),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _cargar,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            _buildHero(context),
            SliverToBoxAdapter(child: _buildCuerpo(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }

  // ── Cabecera: imagen del local con degradado y nombre completo ────────────
  Widget _buildHero(BuildContext context) {
    final imagen = _ficha.foto;
    final ancho = MediaQuery.sizeOf(context).width;
    final alto = (ancho * 0.72).clamp(210.0, 330.0);
    final colores = _coloresCabecera();

    return SliverAppBar(
      expandedHeight: alto,
      pinned: true,
      stretch: true,
      backgroundColor: AppTheme.primaryDark,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.maybePop(context),
        tooltip: 'Volver',
      ),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imagen != null && imagen.trim().isNotEmpty)
              NetImage(
                url: imagen,
                fit: BoxFit.cover,
                errorWidget: () => _sinImagen(colores),
              )
            else
              _sinImagen(colores),
            // Degradado de arriba a abajo: oscurece la parte baja (donde va el
            // texto) y deja la imagen limpia en el centro. Nunca tapa el nombre:
            // el texto va debajo del degradado, no encima de un velo plano.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.72),
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
            // Contenido anclado abajo.
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // El sello dice de dónde viene la ficha, no lo que se anuncia:
                  // sin campaña no se anuncia nada.
                  _EtiquetaModo(
                    texto: _patrocinada
                        ? 'ESPACIO PATROCINADO'
                        : 'ESTABLECIMIENTO',
                  ),
                  const SizedBox(height: 10),
                  // El nombre grande es el del ESTABLECIMIENTO: el espacio
                  // patrocinado presenta un local, no un eslogan. El titular de
                  // la campaña (o quién publica el local) va justo debajo.
                  Text(
                    _ficha.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      shadows: [
                        Shadow(
                          color: Color(0x66000000),
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  if (_lineaSecundaria.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _lineaSecundaria,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sinImagen(List<Color> colores) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colores,
      ),
    ),
    child: Center(
      child: Icon(
        // El icono de campaña solo tiene sentido con campaña; una ficha normal
        // enseña el icono de establecimiento de siempre.
        _patrocinada ? _iconoCampana(_ficha.icono) : Icons.storefront_outlined,
        size: 84,
        color: Colors.white.withValues(alpha: 0.22),
      ),
    ),
  );

  // ── Cuerpo ───────────────────────────────────────────────────────────────
  Widget _buildCuerpo(BuildContext context) {
    final destacado = _ficha.descripcionDestacada?.trim() ?? '';
    final sobre = _ficha.descripcion?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFichaLocal(),
          // El bloque de campaña solo existe con campaña Y con texto: una
          // campaña sin descripción no destaca nada.
          if (_patrocinada && destacado.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildDescripcionCampana(destacado),
          ],
          if (sobre.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildSobreLocal(sobre),
          ],
          const SizedBox(height: 14),
          _buildContacto(),
          const SizedBox(height: 22),
          _buildServiciosHeader(),
          const SizedBox(height: 10),
          _buildServicios(),
        ],
      ),
    );
  }

  /// Chips de datos reales del establecimiento: ubicación, horario, valoración y
  /// servicios.
  Widget _buildFichaLocal() {
    final totalServicios = _totalServicios();
    final chips = <Widget>[
      if (_ficha.ubicacion != null)
        _DatoChip(icono: Icons.place_outlined, texto: _ficha.ubicacion!),
      ..._chipsHorario(),
      // Estrellas solo con reseñas reales: sin valoración no se le supone nada a
      // nadie (misma regla que el Home y el listado).
      if (_ficha.tieneValoracion)
        _ChipValoracion(
          promedio: _ficha.rating!,
          totalResenas: _ficha.totalResenas,
        ),
      if (totalServicios != null && totalServicios > 0)
        _DatoChip(
          icono: Icons.miscellaneous_services_outlined,
          texto: totalServicios == 1
              ? '1 servicio disponible'
              : '$totalServicios servicios disponibles',
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: _tarjeta(),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  /// Cuántos servicios tiene el local, o `null` si todavía no se sabe.
  ///
  /// El listado ya lo sabe (lo agrega el servidor), así que se usa tal cual y el
  /// chip aparece sin esperar a que termine la carga. En modo campaña la campaña
  /// no lo trae y se cuentan los servicios cargados, como se hacía antes.
  int? _totalServicios() {
    final declarado = _ficha.totalServicios;
    if (declarado != null) return declarado;
    if (_cargando) return null;
    return _servicios.length;
  }

  List<Widget> _chipsHorario() {
    final horario = HorarioAtencion.parseConDetalle(
      _ficha.horarioTexto,
      _ficha.horarioDetalle,
    );
    final estado = horario.evaluar(DateTime.now());
    final texto = _ficha.horarioTexto?.trim() ?? '';
    return [
      if (estado != EstadoHorario.desconocido)
        _DatoChip(
          icono: estado == EstadoHorario.abierto
              ? Icons.schedule_rounded
              : Icons.schedule_outlined,
          texto: estado == EstadoHorario.abierto ? 'Abierto ahora' : 'Cerrado',
          color: estado == EstadoHorario.abierto
              ? AppTheme.success
              : AppTheme.textSecondary,
        ),
      if (texto.isNotEmpty)
        _DatoChip(icono: Icons.access_time_rounded, texto: texto),
    ];
  }

  /// Bloque de campaña: solo se llama con campaña y con texto que destacar.
  Widget _buildDescripcionCampana(String destacado) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _coloresCabecera(),
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A2B3A67),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconoCampana(_ficha.icono),
                color: Colors.white.withValues(alpha: 0.85),
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'DESTACADO DEL MOMENTO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            destacado,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          if (_ficha.hasta != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Vigente hasta ${_fechaCorta(_ficha.hasta!)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSobreLocal(String sobre) {
    return _Bloque(
      titulo: 'Sobre $_nombreLocal',
      icono: Icons.storefront_outlined,
      child: Text(
        sobre,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13.5,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildContacto() {
    final direccion = _ficha.direccion?.trim() ?? '';
    final telefono = _ficha.entidadTelefono?.trim() ?? '';
    final publica = _ficha.entidad?.trim() ?? '';
    final filas = <Widget>[
      if (direccion.isNotEmpty)
        _FilaDato(
          icono: Icons.map_outlined,
          etiqueta: 'Dirección',
          valor: direccion,
        ),
      if (_ficha.ubicacion != null)
        _FilaDato(
          icono: Icons.public_rounded,
          etiqueta: 'Ubicación',
          valor: _ficha.ubicacion!,
        ),
      if (telefono.isNotEmpty)
        _FilaDato(
          icono: Icons.call_outlined,
          etiqueta: 'Teléfono',
          valor: telefono,
        ),
      if (publica.isNotEmpty)
        _FilaDato(
          icono: Icons.business_outlined,
          etiqueta: 'Publica',
          valor: publica,
        ),
    ];
    if (filas.isEmpty) return const SizedBox.shrink();

    return _Bloque(
      titulo: 'Cómo llegar y contactar',
      icono: Icons.contact_page_outlined,
      child: Column(
        children: [
          for (var i = 0; i < filas.length; i++) ...[
            if (i > 0) const Divider(height: 18),
            filas[i],
          ],
        ],
      ),
    );
  }

  Widget _buildServiciosHeader() {
    // Ancla del tutorial: el paso que explica la lista de servicios se resalta
    // sobre este encabezado, que está montado siempre (aunque la lista esté
    // cargando, vacía o con error).
    return TutorialAnchor(
      id: 'ficha_local_servicios',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Servicios disponibles',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lo que puedes reservar en $_nombreLocal.',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_error)
            IconButton(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Reintentar',
            ),
        ],
      ),
    );
  }

  Widget _buildServicios() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error) {
      return _Aviso(
        icono: Icons.cloud_off_rounded,
        titulo: 'No pudimos cargar los servicios',
        detalle: 'Revisa tu conexión y vuelve a intentarlo.',
        accion: TextButton.icon(
          onPressed: _cargar,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Reintentar'),
        ),
      );
    }
    if (_servicios.isEmpty) {
      return const _Aviso(
        icono: Icons.hourglass_empty_rounded,
        titulo: 'Todavía no hay servicios publicados',
        detalle:
            'Este establecimiento aún no tiene servicios reservables en la app.',
      );
    }

    return Column(
      children: [
        for (final servicio in _servicios) ...[
          _TarjetaServicioLocal(
            localServicio: servicio,
            taxonomia: _taxonomia,
            onTap: () => _abrirServicio(servicio),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── Utilidades de pintado ────────────────────────────────────────────────

  /// Degradado de la cabecera: el de la campaña si la hay, si no el de marca.
  ///
  /// `FichaLocal.desdeEstablecimiento` no rellena colores, así que sin campaña
  /// esto da siempre `primaryDark → primary`.
  List<Color> _coloresCabecera() {
    if (!_patrocinada) return const [AppTheme.primaryDark, AppTheme.primary];
    final inicio = _colorHex(_ficha.colorInicio) ?? AppTheme.primaryDark;
    final fin = _colorHex(_ficha.colorFin) ?? AppTheme.primary;
    return [inicio, fin];
  }

  static Color? _colorHex(String? hex) {
    if (hex == null || hex.trim().isEmpty) return null;
    var v = hex.trim().replaceFirst('#', '');
    if (v.length == 6) v = 'FF$v';
    if (v.length != 8) return null;
    final n = int.tryParse(v, radix: 16);
    return n == null ? null : Color(n);
  }

  BoxDecoration _tarjeta() => BoxDecoration(
    color: AppTheme.cardBg,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: AppTheme.border),
    boxShadow: const [
      BoxShadow(color: Color(0x0D2B3A67), blurRadius: 14, offset: Offset(0, 6)),
    ],
  );
}

/// Icono de una campaña: la clave corta que guarda el superadmin.
IconData _iconoCampana(String? nombre) => switch (nombre) {
  'spa' => Icons.spa_outlined,
  'storefront' => Icons.storefront_outlined,
  'star' => Icons.star_rounded,
  'local_offer' => Icons.local_offer_outlined,
  'directions_bus' => Icons.directions_bus_filled_outlined,
  'restaurant' => Icons.restaurant_outlined,
  'pets' => Icons.pets_outlined,
  'health' => Icons.medical_services_outlined,
  _ => Icons.campaign_outlined,
};

String _fechaCorta(DateTime d) {
  final dia = d.day.toString().padLeft(2, '0');
  final mes = d.month.toString().padLeft(2, '0');
  return '$dia/$mes/${d.year}';
}

// ── Widgets de apoyo ───────────────────────────────────────────────────────

/// Sello de la cabecera: dice cómo llegó el usuario a esta ficha.
class _EtiquetaModo extends StatelessWidget {
  const _EtiquetaModo({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _DatoChip extends StatelessWidget {
  const _DatoChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip de valoración real del local: estrellas + promedio + número de reseñas.
///
/// Usa [Estrellas], que redondea a media estrella y **no** inventa una nota
/// cuando no hay ninguna. Solo se construye si el local tiene reseñas
/// (`FichaLocal.tieneValoracion`), así que aquí el promedio nunca es nulo.
class _ChipValoracion extends StatelessWidget {
  const _ChipValoracion({required this.promedio, required this.totalResenas});

  final double promedio;
  final int totalResenas;

  @override
  Widget build(BuildContext context) {
    final resenas = totalResenas == 1 ? '1 reseña' : '$totalResenas reseñas';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Estrellas(promedio: promedio, size: 13),
          const SizedBox(width: 6),
          Text(
            '${promedio.toStringAsFixed(1)} ($resenas)',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bloque extends StatelessWidget {
  const _Bloque({
    required this.titulo,
    required this.icono,
    required this.child,
  });

  final String titulo;
  final IconData icono;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D2B3A67),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 17, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  const _FilaDato({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 17, color: AppTheme.textSecondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 78,
          child: Text(
            etiqueta,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

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
      width: double.infinity,
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
            ),
          ),
          if (accion != null) ...[const SizedBox(height: 8), accion!],
        ],
      ),
    );
  }
}

/// Tarjeta de un servicio del local: imagen, categoría › subcategoría, precio y
/// valoración real. Toda la tarjeta abre el detalle, donde se reserva.
class _TarjetaServicioLocal extends StatelessWidget {
  const _TarjetaServicioLocal({
    required this.localServicio,
    required this.taxonomia,
    required this.onTap,
  });

  final LocalServicio localServicio;
  final Taxonomia taxonomia;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final servicio = localServicio.servicio;
    final precio = precioBaseDe(servicio?.configPrecio);
    final foto = servicio?.foto?.trim();
    final categoria = taxonomia.categoriaNombre(servicio?.idTipoActividad);
    final subcategoria = taxonomia.subcategoriaNombre(
      servicio?.idTipoActividad,
    );
    final etiqueta = <String>[
      if (categoria != null) categoria,
      if (subcategoria != null) subcategoria,
    ].join(' › ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D2B3A67),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: foto != null && foto.isNotEmpty
                      ? NetImage(
                          url: foto,
                          fit: BoxFit.cover,
                          errorWidget: () => _placeholderServicio(),
                        )
                      : _placeholderServicio(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (etiqueta.isNotEmpty)
                      Row(
                        children: [
                          const Icon(
                            Icons.account_tree_outlined,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              etiqueta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 3),
                    Text(
                      servicio?.nombre ?? 'Servicio sin nombre',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    if (servicio?.descripcion != null &&
                        servicio!.descripcion!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        servicio.descripcion!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (precio != null) ...[
                          Text(
                            _precioLabel(precio.precio, precio.moneda),
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        const Spacer(),
                        if (localServicio.permiteReservaDirecta)
                          const _MiniTag(texto: 'Reserva directa'),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderServicio() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppTheme.primary.withValues(alpha: 0.18),
          AppTheme.accent.withValues(alpha: 0.22),
        ],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.miscellaneous_services_outlined,
        color: AppTheme.primary.withValues(alpha: 0.5),
        size: 26,
      ),
    ),
  );

  static String _precioLabel(double valor, String? moneda) {
    final monto = valor == valor.roundToDouble()
        ? valor.toStringAsFixed(0)
        : valor.toStringAsFixed(2);
    return '$monto ${moneda ?? 'USD'}';
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: AppTheme.success,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
