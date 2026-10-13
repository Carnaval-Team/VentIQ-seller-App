import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../models/servicio.dart';
import '../services/campana_service.dart';
import '../services/catalogo_service.dart';
import '../services/tipo_actividad_service.dart';
import '../utils/horario_atencion.dart';
import '../utils/precio_reserva.dart';
import '../widgets/net_image.dart';
import 'local_servicio_detail_screen.dart';

/// Vista de marketing del local destacado en "Espacio patrocinado".
///
/// POR QUE EXISTE
///   Antes, tocar una tarjeta patrocinada abría el detalle de UN servicio, que no
///   es lo que promete el espacio patrocinado: la campaña presenta un
///   **establecimiento**. Esta pantalla enseña el local como una ficha comercial
///   (imagen grande, descripción, datos de contacto, horario) y debajo **todos**
///   sus servicios reservables.
///
/// DE DONDE SALE CADA DATO
///   * Local y campaña: `flow.campanas_activas()` (migración 49), que ya resuelve
///     imagen, descripción, dirección y horario del local.
///   * Servicios del local: `flow.cliente_obtener_servicios(p_id_local)` — la
///     misma regla de visibilidad que el resto del cliente (`_ls_disponible`).
///   * Categoría y subcategoría de cada servicio: `flow.nom_tipo_actividad_servicio`
///     leído una vez y resuelto en memoria (migración 47).
///
/// NADA DE ESTA PANTALLA CAMBIA EL PRECIO. La campaña solo destaca: el importe lo
/// fija el servidor al reservar, igual que desde el catálogo.
class EspacioPatrocinadoScreen extends StatefulWidget {
  const EspacioPatrocinadoScreen({super.key, required this.campana});

  final CampanaPatrocinada campana;

  @override
  State<EspacioPatrocinadoScreen> createState() =>
      _EspacioPatrocinadoScreenState();
}

class _EspacioPatrocinadoScreenState extends State<EspacioPatrocinadoScreen> {
  List<LocalServicio> _servicios = const [];
  Taxonomia _taxonomia = Taxonomia.vacia;
  bool _cargando = true;
  bool _error = false;

  CampanaPatrocinada get _campana => widget.campana;

  /// Nombre grande de la cabecera: el local si la campaña apunta a uno.
  String get _nombrePrincipal {
    final local = _campana.local?.trim() ?? '';
    return local.isNotEmpty ? local : _campana.titulo.trim();
  }

  /// Segunda línea: el titular de la campaña (o su subtítulo si ya se usó el
  /// titular como nombre principal).
  String get _lineaSecundaria {
    final local = _campana.local?.trim() ?? '';
    if (local.isNotEmpty) return _campana.titulo.trim();
    return _campana.subtitulo?.trim() ?? '';
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      // La taxonomía es una lectura pública y pequeña: se pide en paralelo con
      // los servicios para no encadenar dos esperas.
      final resultados = await Future.wait<Object>([
        _campana.idLocal == null
            ? Future<List<LocalServicio>>.value(const <LocalServicio>[])
            : CatalogoService.getLocalServicios(idLocal: _campana.idLocal!),
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
      debugPrint('[flow] EspacioPatrocinadoScreen._cargar ERROR: $e');
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
    final imagen = _campana.imagenPrincipal;
    final ancho = MediaQuery.sizeOf(context).width;
    final alto = (ancho * 0.72).clamp(210.0, 330.0);
    final colores = _degradadoCampana();

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
                  const _EtiquetaPatrocinado(),
                  const SizedBox(height: 10),
                  // El nombre grande es el del ESTABLECIMIENTO: el espacio
                  // patrocinado presenta un local, no un eslogan. El titular de
                  // la campaña va justo debajo.
                  Text(
                    _nombrePrincipal,
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
                  if (_lineaSecundaria.trim().isNotEmpty) ...[
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
        _iconoCampana(_campana.icono),
        size: 84,
        color: Colors.white.withValues(alpha: 0.22),
      ),
    ),
  );

  // ── Cuerpo ───────────────────────────────────────────────────────────────
  Widget _buildCuerpo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFichaLocal(),
          if (_campana.descripcion != null &&
              _campana.descripcion!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildDescripcionCampana(),
          ],
          if (_campana.localDescripcion != null &&
              _campana.localDescripcion!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildSobreLocal(),
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

  /// Chips de datos reales del establecimiento: ubicación, horario, servicios.
  Widget _buildFichaLocal() {
    final chips = <Widget>[
      if (_campana.ubicacionLocal != null)
        _DatoChip(
          icono: Icons.place_outlined,
          texto: _campana.ubicacionLocal!,
        ),
      ..._chipsHorario(),
      if (!_cargando && _servicios.isNotEmpty)
        _DatoChip(
          icono: Icons.miscellaneous_services_outlined,
          texto: _servicios.length == 1
              ? '1 servicio disponible'
              : '${_servicios.length} servicios disponibles',
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

  List<Widget> _chipsHorario() {
    final horario = HorarioAtencion.parseConDetalle(
      _campana.localHorarioAtencion,
      _campana.localHorarioDetalle,
    );
    final estado = horario.evaluar(DateTime.now());
    final texto = _campana.localHorarioAtencion?.trim() ?? '';
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

  Widget _buildDescripcionCampana() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _degradadoCampana(),
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
                _iconoCampana(_campana.icono),
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
            _campana.descripcion!.trim(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          if (_campana.hasta != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Vigente hasta ${_fechaCorta(_campana.hasta!)}',
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

  Widget _buildSobreLocal() {
    return _Bloque(
      titulo: 'Sobre ${_campana.local ?? 'el establecimiento'}',
      icono: Icons.storefront_outlined,
      child: Text(
        _campana.localDescripcion!.trim(),
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13.5,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildContacto() {
    final filas = <Widget>[
      if (_campana.localDireccion != null &&
          _campana.localDireccion!.trim().isNotEmpty)
        _FilaDato(
          icono: Icons.map_outlined,
          etiqueta: 'Dirección',
          valor: _campana.localDireccion!.trim(),
        ),
      if (_campana.ubicacionLocal != null)
        _FilaDato(
          icono: Icons.public_rounded,
          etiqueta: 'Ubicación',
          valor: _campana.ubicacionLocal!,
        ),
      if (_campana.entidadTelefono != null &&
          _campana.entidadTelefono!.trim().isNotEmpty)
        _FilaDato(
          icono: Icons.call_outlined,
          etiqueta: 'Teléfono',
          valor: _campana.entidadTelefono!.trim(),
        ),
      if (_campana.entidad != null && _campana.entidad!.trim().isNotEmpty)
        _FilaDato(
          icono: Icons.business_outlined,
          etiqueta: 'Publica',
          valor: _campana.entidad!.trim(),
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
    final nombre = _campana.local ?? 'este establecimiento';
    return Row(
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
                'Lo que puedes reservar en $nombre.',
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
  List<Color> _degradadoCampana() {
    final inicio = _colorHex(_campana.colorInicio) ?? AppTheme.primaryDark;
    final fin = _colorHex(_campana.colorFin) ?? AppTheme.primary;
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

class _EtiquetaPatrocinado extends StatelessWidget {
  const _EtiquetaPatrocinado();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: const Text(
        'ESPACIO PATROCINADO',
        style: TextStyle(
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
