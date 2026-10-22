import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/plan_dia.dart';
import '../../models/servicio.dart';
import '../../services/auth_service.dart';
import '../../services/catalogo_service.dart';
import '../../services/imagen_service.dart';
import '../../services/plan_config_service.dart';
import '../../tutorial/tutorial_anchor.dart';
import 'gestion_locales_screen.dart';
import 'gestion_servicios_screen.dart';
import 'local_servicio_admin_screen.dart';
import 'planificacion_sheets.dart';

/// Ancho máximo de las hojas modales en tablet y web: a pantalla completa un
/// formulario de 1400 px de ancho es incómodo de leer.
const BoxConstraints kHojaAdminConstraints = BoxConstraints(maxWidth: 640);

/// Nivel 2 de «Locales y servicios» en pantalla propia (teléfono).
///
/// Devuelve `true` al salir si cambió algo que la lista de locales pinta.
class LocalDetalleScreen extends StatefulWidget {
  final Local local;
  final int entidadId;

  const LocalDetalleScreen({
    super.key,
    required this.local,
    required this.entidadId,
  });

  @override
  State<LocalDetalleScreen> createState() => _LocalDetalleScreenState();
}

class _LocalDetalleScreenState extends State<LocalDetalleScreen> {
  bool _huboCambios = false;

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _huboCambios);
      },
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: SafeArea(
          child: LocalDetallePanel(
            local: widget.local,
            entidadId: widget.entidadId,
            mostrarAtras: true,
            onCambio: () => _huboCambios = true,
            onEliminado: () => Navigator.pop(context, true),
          ),
        ),
      ),
    );
  }
}

/// Detalle de un local: cabecera compacta y los servicios que ofrece.
///
/// No lleva `Scaffold`: lo usa [LocalDetalleScreen] en teléfono y la vista de
/// dos paneles de `LocalesServiciosScreen` en tablet y web.
class LocalDetallePanel extends StatefulWidget {
  final Local local;
  final int entidadId;

  /// Muestra la flecha de volver (pantalla propia) en la cabecera.
  final bool mostrarAtras;

  /// Algo del local o de sus servicios cambió: la lista debe recargarse.
  final VoidCallback onCambio;

  /// El local se eliminó.
  final VoidCallback onEliminado;

  const LocalDetallePanel({
    super.key,
    required this.local,
    required this.entidadId,
    required this.onCambio,
    required this.onEliminado,
    this.mostrarAtras = false,
  });

  @override
  State<LocalDetallePanel> createState() => _LocalDetallePanelState();
}

class _LocalDetallePanelState extends State<LocalDetallePanel> {
  late Local _local;
  List<LocalServicio> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _local = widget.local;
    _cargar();
  }

  void _avisar(String mensaje, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final locales = await CatalogoService.getLocalesByEntidad(
        widget.entidadId,
      );
      final items = await CatalogoService.getLocalServicios(
        idLocal: _local.id,
        incluirInactivos: true,
      );
      items.sort(
        (a, b) => (a.servicio?.nombre ?? '').compareTo(b.servicio?.nombre ?? ''),
      );
      if (!mounted) return;
      setState(() {
        _local = locales.firstWhere(
          (l) => l.id == _local.id,
          orElse: () => _local,
        );
        _items = items;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cambio() {
    widget.onCambio();
    _cargar();
  }

  // ── Acciones del local ───────────────────────────────────────────────

  Future<void> _editarLocal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      constraints: kHojaAdminConstraints,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          LocalFormSheet(idEntidad: widget.entidadId, local: _local),
    );
    _cambio();
  }

  Future<void> _alternarActivo() async {
    final nuevo = !_local.activo;
    try {
      await CatalogoService.setLocalActivo(id: _local.id, activo: nuevo);
      _avisar(
        nuevo
            ? 'Local activo: vuelve a verse con sus servicios publicados'
            : 'Local oculto: él y todos sus servicios dejan de verse',
        color: nuevo ? AppTheme.success : AppTheme.warning,
      );
      _cambio();
    } catch (e) {
      _avisar('Error: $e', color: AppTheme.error);
    }
  }

  Future<void> _eliminarLocal() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar local'),
        content: Text(
          '¿Eliminar «${_local.nombre}»? Se eliminarán sus servicios '
          'vinculados y sus colas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await CatalogoService.deleteLocal(_local.id);
      widget.onCambio();
      widget.onEliminado();
    } catch (e) {
      _avisar('Error: $e', color: AppTheme.error);
    }
  }

  // ── Servicios del local ──────────────────────────────────────────────

  Future<void> _abrirServicio(
    LocalServicio ls, {
    PestanaLocalServicio pestana = PestanaLocalServicio.calendario,
  }) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LocalServicioAdminScreen(
          localServicio: ls,
          entidadId: widget.entidadId,
          pestanaInicial: pestana,
        ),
      ),
    );
    if (cambio == true) _cambio();
  }

  Future<void> _anadirServicio() async {
    final ls = await showModalBottomSheet<LocalServicio>(
      context: context,
      isScrollControlled: true,
      constraints: kHojaAdminConstraints,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AnadirServicioSheet(
        local: _local,
        entidadId: widget.entidadId,
        yaVinculados: _items.map((e) => e.idServicio).toSet(),
      ),
    );
    if (ls == null || !mounted) return;
    _cambio();
    // Recién añadido no tiene recursos ni días: se abre directo en la
    // configuración, que es lo siguiente que hay que hacer.
    await _abrirServicio(ls, pestana: PestanaLocalServicio.configuracion);
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Cabecera(
            local: _local,
            mostrarAtras: widget.mostrarAtras,
            onEditar: _editarLocal,
            onAlternarActivo: _alternarActivo,
            onEliminar: _eliminarLocal,
          ),
          if (!_local.activo) ...[
            const SizedBox(height: 8),
            _AvisoLocalInactivo(onActivar: _alternarActivo),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SERVICIOS EN ESTE LOCAL',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              TutorialAnchor(
                id: 'admin_anadir_servicio',
                child: TextButton.icon(
                  onPressed: _anadirServicio,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Añadir servicio'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_cargando && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && _items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No se pudieron cargar los servicios: $_error',
                style: const TextStyle(color: AppTheme.error),
              ),
            )
          else if (_items.isEmpty)
            _SinServicios(onAnadir: _anadirServicio)
          else
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    _FilaServicio(
                      // La clave por id evita que la ocupación cargada de una
                      // fila se quede pegada a otra al recargar la lista.
                      key: ValueKey(_items[i].id),
                      ls: _items[i],
                      onTap: () => _abrirServicio(_items[i]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Cabecera del local ─────────────────────────────────────────────────

class _Cabecera extends StatelessWidget {
  final Local local;
  final bool mostrarAtras;
  final VoidCallback onEditar;
  final VoidCallback onAlternarActivo;
  final VoidCallback onEliminar;

  const _Cabecera({
    required this.local,
    required this.mostrarAtras,
    required this.onEditar,
    required this.onAlternarActivo,
    required this.onEliminar,
  });

  @override
  Widget build(BuildContext context) {
    final linea = [
      local.direccion,
      local.horarioAtencion,
    ].where((v) => v != null && v.trim().isNotEmpty).join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mostrarAtras)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const BackButtonIcon(),
              tooltip: 'Volver',
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: FotoLocal(local: local, radio: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        local.nombre,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ChipEstado(
                      texto: local.activo ? 'Activo' : 'Inactivo',
                      color: local.activo ? AppTheme.success : AppTheme.warning,
                    ),
                  ],
                ),
                if (linea.isNotEmpty)
                  Text(
                    linea,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (local.ubicacion.isNotEmpty)
                  Text(
                    local.ubicacion,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Editar local',
          onPressed: onEditar,
        ),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          onSelected: (v) {
            if (v == 'activo') onAlternarActivo();
            if (v == 'eliminar') onEliminar();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'activo',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  local.activo
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                title: Text(local.activo ? 'Ocultar local' : 'Activar local'),
              ),
            ),
            const PopupMenuItem(
              value: 'eliminar',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_outline, color: AppTheme.error),
                title: Text(
                  'Eliminar local',
                  style: TextStyle(color: AppTheme.error),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Foto redonda del local, con un icono si no tiene.
class FotoLocal extends StatelessWidget {
  final Local local;
  final double radio;

  const FotoLocal({super.key, required this.local, this.radio = 22});

  @override
  Widget build(BuildContext context) {
    final foto = local.foto;
    return CircleAvatar(
      radius: radio,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
      backgroundImage: foto == null
          ? null
          : (kIsWeb
                ? NetworkImage(ImagenService.conVersion(foto)) as ImageProvider
                : CachedNetworkImageProvider(ImagenService.conVersion(foto))),
      child: foto == null
          ? Icon(Icons.store_outlined, color: AppTheme.primary, size: radio)
          : null,
    );
  }
}

class _AvisoLocalInactivo extends StatelessWidget {
  final VoidCallback onActivar;
  const _AvisoLocalInactivo({required this.onActivar});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppTheme.warning),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Local oculto: ni él ni sus servicios se ven ni se pueden reservar.',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
            ),
          ),
          TextButton(onPressed: onActivar, child: const Text('Activar')),
        ],
      ),
    );
  }
}

class _SinServicios extends StatelessWidget {
  final VoidCallback onAnadir;
  const _SinServicios({required this.onAnadir});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.miscellaneous_services_outlined,
            size: 40,
            color: AppTheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 10),
          const Text(
            'Este local todavía no ofrece servicios',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Añade uno del catálogo o crea uno nuevo para empezar a recibir '
            'reservas aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onAnadir,
            icon: const Icon(Icons.add),
            label: const Text('Añadir servicio'),
          ),
        ],
      ),
    );
  }
}

// ── Fila de un servicio del local ──────────────────────────────────────

/// Una línea por servicio: estado y ocupación de los próximos 7 días. Lo que
/// se configura vive en el nivel 3; aquí solo se ve si algo requiere atención.
class _FilaServicio extends StatefulWidget {
  final LocalServicio ls;
  final VoidCallback onTap;

  const _FilaServicio({super.key, required this.ls, required this.onTap});

  @override
  State<_FilaServicio> createState() => _FilaServicioState();
}

class _FilaServicioState extends State<_FilaServicio> {
  /// `null` mientras carga o si falló (la fila se pinta igual, sin ocupación).
  List<PlanDia>? _semana;

  @override
  void initState() {
    super.initState();
    _cargarSemana();
  }

  Future<void> _cargarSemana() async {
    final hoy = DateUtils.dateOnly(DateTime.now());
    try {
      final planes = await PlanConfigService.getPlanDias(
        uuidUsuario: AuthService.currentUserId ?? '',
        idLocalServicio: widget.ls.id,
        desde: hoy,
        hasta: hoy.add(const Duration(days: 6)),
      );
      if (mounted) setState(() => _semana = planes);
    } catch (_) {
      // Sin ocupación: no es motivo para romper la fila.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ls = widget.ls;
    final semana = _semana;
    final capacidad = semana?.fold<int>(0, (s, p) => s + p.cantidad) ?? 0;
    final reservados = semana?.fold<int>(0, (s, p) => s + p.agendados) ?? 0;

    Widget? ocupacion;
    if (semana != null) {
      ocupacion = capacidad == 0
          ? const Text(
              'Sin días planificados esta semana',
              style: TextStyle(fontSize: 12, color: AppTheme.warning),
            )
          : Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (reservados / capacidad).clamp(0, 1).toDouble(),
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade200,
                      color: reservados >= capacidad
                          ? AppTheme.error
                          : AppTheme.success,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$reservados/$capacidad · 7 días',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            );
    }

    return ListTile(
      onTap: widget.onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            ls.servicio?.nombre ?? '—',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (!ls.activoEfectivo)
            const ChipEstado(texto: 'Oculto', color: AppTheme.warning)
          else
            const ChipEstado(texto: 'Publicado', color: AppTheme.success),
          if (ls.permiteReservaDirecta)
            const ChipEstado(texto: 'Directa', color: AppTheme.accent),
        ],
      ),
      subtitle: ocupacion == null
          ? null
          : Padding(padding: const EdgeInsets.only(top: 6), child: ocupacion),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ── Hoja: añadir un servicio al local ──────────────────────────────────

/// Sustituye al antiguo «Vincular servicio a local»: el local ya está elegido,
/// así que basta con elegir el servicio del catálogo o crearlo en el momento.
/// Devuelve el [LocalServicio] creado.
class _AnadirServicioSheet extends StatefulWidget {
  final Local local;
  final int entidadId;
  final Set<int> yaVinculados;

  const _AnadirServicioSheet({
    required this.local,
    required this.entidadId,
    required this.yaVinculados,
  });

  @override
  State<_AnadirServicioSheet> createState() => _AnadirServicioSheetState();
}

class _AnadirServicioSheetState extends State<_AnadirServicioSheet> {
  List<Servicio> _disponibles = [];
  bool _cargando = true;
  int? _vinculando;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final servicios = await CatalogoService.getServiciosByEntidad(
        widget.entidadId,
      );
      if (!mounted) return;
      setState(() {
        _disponibles = servicios
            .where((s) => !widget.yaVinculados.contains(s.id))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _cargando = false;
        });
      }
    }
  }

  Future<void> _vincular(Servicio s) async {
    setState(() {
      _vinculando = s.id;
      _error = null;
    });
    try {
      final creado = await CatalogoService.createLocalServicio(
        idLocal: widget.local.id,
        idServicio: s.id,
      );
      // Se relee con el tipo de actividad: el nivel 3 lo necesita para saber
      // si es transporte.
      final completo = await CatalogoService.getLocalServicio(creado.id);
      if (mounted) Navigator.pop(context, completo);
    } catch (e) {
      if (mounted) {
        setState(() {
          _vinculando = null;
          _error = '$e'.contains('unique')
              ? '«${s.nombre}» ya está en este local'
              : 'Error: $e';
        });
      }
    }
  }

  Future<void> _crearNuevo() async {
    final nuevo = await showModalBottomSheet<Servicio>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      constraints: kHojaAdminConstraints,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ServicioFormSheet(idEntidad: widget.entidadId),
    );
    if (nuevo != null && mounted) await _vincular(nuevo);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Añadir servicio',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'a ${widget.local.nombre}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _vinculando == null ? _crearNuevo : null,
              icon: const Icon(Icons.add),
              label: const Text('Crear un servicio nuevo'),
            ),
            const SizedBox(height: 16),
            const Text(
              'O elige uno del catálogo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 13),
                ),
              ),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_disponibles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Todos los servicios del catálogo ya están en este local.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _disponibles.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = _disponibles[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: _vinculando == null,
                      leading: const Icon(
                        Icons.miscellaneous_services_outlined,
                        color: AppTheme.accent,
                      ),
                      title: Text(s.nombre),
                      subtitle: s.activo
                          ? null
                          : const Text(
                              'Inactivo en el catálogo',
                              style: TextStyle(color: AppTheme.warning),
                            ),
                      trailing: _vinculando == s.id
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      onTap: () => _vincular(s),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
