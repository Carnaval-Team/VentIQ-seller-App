import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/entidad.dart';
import '../../models/servicio.dart';
import '../../services/catalogo_service.dart';
import '../../tutorial/tutorial_anchor.dart';
import 'gestion_locales_screen.dart';
import 'local_detalle_panel.dart';
import 'planificacion_sheets.dart';

/// Módulo «Locales y servicios»: sustituye a las antiguas pantallas de Locales
/// y Planificación.
///
/// Tres niveles, uno por pregunta:
///  1. ¿Qué locales tengo? → esta lista.
///  2. ¿Qué ofrece este local? → [LocalDetallePanel].
///  3. ¿Cómo funciona este servicio aquí? → `LocalServicioAdminScreen`.
///
/// En pantallas anchas (tablet apaisada, web) los niveles 1 y 2 conviven en
/// dos paneles; en teléfono el 2 se abre como pantalla propia.
class LocalesServiciosScreen extends StatefulWidget {
  final Entidad entidad;

  /// Local que se abre nada más cargar (lo usa el tutorial).
  final int? idLocalInicial;

  const LocalesServiciosScreen({
    super.key,
    required this.entidad,
    this.idLocalInicial,
  });

  @override
  State<LocalesServiciosScreen> createState() => _LocalesServiciosScreenState();
}

class _LocalesServiciosScreenState extends State<LocalesServiciosScreen> {
  /// A partir de este ancho la lista y el detalle se ven a la vez.
  static const double _anchoDosPaneles = 900;
  static const double _anchoLista = 380;

  List<Local> _locales = [];
  Map<int, List<LocalServicio>> _serviciosPorLocal = {};
  bool _cargando = true;
  String? _error;

  /// Local abierto en el panel derecho (solo en modo dos paneles).
  int? _seleccionado;

  /// Si el local inicial ya se abrió (para no reabrirlo en cada recarga).
  bool _inicialAbierto = false;

  @override
  void initState() {
    super.initState();
    _seleccionado = widget.idLocalInicial;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final locales = await CatalogoService.getLocalesByEntidad(
        widget.entidad.id,
      );
      // Una sola llamada para todos los servicios de la entidad (antes era una
      // por local).
      final pares = await CatalogoService.getLocalServicios(
        idEntidad: widget.entidad.id,
        incluirInactivos: true,
      );
      final porLocal = <int, List<LocalServicio>>{};
      for (final ls in pares) {
        porLocal.putIfAbsent(ls.idLocal, () => []).add(ls);
      }
      for (final lista in porLocal.values) {
        lista.sort(
          (a, b) =>
              (a.servicio?.nombre ?? '').compareTo(b.servicio?.nombre ?? ''),
        );
      }
      locales.sort((a, b) => a.nombre.compareTo(b.nombre));
      if (!mounted) return;
      setState(() {
        _locales = locales;
        _serviciosPorLocal = porLocal;
        if (_seleccionado != null &&
            !locales.any((l) => l.id == _seleccionado)) {
          _seleccionado = null;
        }
      });
      _abrirInicialSiToca();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// En teléfono el local inicial se abre como pantalla; en dos paneles basta
  /// con dejarlo seleccionado.
  void _abrirInicialSiToca() {
    if (_inicialAbierto || widget.idLocalInicial == null) return;
    _inicialAbierto = true;
    final local = _locales
        .where((l) => l.id == widget.idLocalInicial)
        .firstOrNull;
    if (local == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.sizeOf(context).width < _anchoDosPaneles) {
        _abrirEnPantalla(local);
      }
    });
  }

  Future<void> _nuevoLocal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      constraints: kHojaAdminConstraints,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LocalFormSheet(idEntidad: widget.entidad.id),
    );
    await _cargar();
  }

  Future<void> _abrirEnPantalla(Local local) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            LocalDetalleScreen(local: local, entidadId: widget.entidad.id),
      ),
    );
    if (cambio == true) await _cargar();
  }

  void _alTocarLocal(Local local, bool dosPaneles) {
    if (dosPaneles) {
      setState(() => _seleccionado = local.id);
    } else {
      _abrirEnPantalla(local);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dosPaneles = constraints.maxWidth >= _anchoDosPaneles;
        final seleccionado = dosPaneles
            ? _locales.where((l) => l.id == _seleccionado).firstOrNull
            : null;

        return Scaffold(
          backgroundColor: AppTheme.surface,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Locales y servicios'),
                Text(
                  widget.entidad.denominacion,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: TutorialAnchor(
            id: 'admin_nuevo_local',
            child: FloatingActionButton.extended(
              onPressed: _nuevoLocal,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Nuevo local'),
            ),
          ),
          // En dos paneles el FAB queda bajo la lista, no sobre el detalle.
          floatingActionButtonLocation: dosPaneles
              ? _FabBajoLista(_anchoLista)
              : FloatingActionButtonLocation.endFloat,
          body: !dosPaneles
              ? _buildLista(dosPaneles: false)
              : Row(
                  children: [
                    SizedBox(
                      width: _anchoLista,
                      child: _buildLista(dosPaneles: true),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: seleccionado == null
                          ? const _NadaSeleccionado()
                          : LocalDetallePanel(
                              // Clave por id: al cambiar de local el panel se
                              // monta de nuevo y carga los datos del nuevo.
                              key: ValueKey(seleccionado.id),
                              local: seleccionado,
                              entidadId: widget.entidad.id,
                              onCambio: _cargar,
                              onEliminado: () =>
                                  setState(() => _seleccionado = null),
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildLista({required bool dosPaneles}) {
    if (_cargando && _locales.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _locales.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No se pudieron cargar los locales: $_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.error),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_locales.isEmpty) return _SinLocales(onNuevo: _nuevoLocal);

    return RefreshIndicator(
      onRefresh: _cargar,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // En teléfono apaisado o tablet vertical la lista no se estira.
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: _locales.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final local = _locales[i];
              return _TarjetaLocal(
                local: local,
                servicios: _serviciosPorLocal[local.id] ?? const [],
                seleccionada: dosPaneles && local.id == _seleccionado,
                onTap: () => _alTocarLocal(local, dosPaneles),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Coloca el FAB abajo a la derecha del panel de la lista.
class _FabBajoLista extends FloatingActionButtonLocation {
  final double anchoLista;
  const _FabBajoLista(this.anchoLista);

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) {
    const margen = 16.0;
    final x = anchoLista - g.floatingActionButtonSize.width - margen;
    final y =
        g.contentBottom - g.floatingActionButtonSize.height - margen;
    return Offset(x, y);
  }
}

class _TarjetaLocal extends StatelessWidget {
  final Local local;
  final List<LocalServicio> servicios;
  final bool seleccionada;
  final VoidCallback onTap;

  const _TarjetaLocal({
    required this.local,
    required this.servicios,
    required this.seleccionada,
    required this.onTap,
  });

  /// Lo único que se señala en la lista: lo que el admin probablemente no sabe
  /// y deja algo sin verse.
  String? get _aviso {
    if (servicios.isEmpty) return 'Sin servicios: los clientes no pueden reservar';
    final ocultos = servicios.where((s) => !s.activoEfectivo).length;
    if (local.activo && ocultos > 0) {
      return ocultos == 1
          ? '1 servicio oculto'
          : '$ocultos servicios ocultos';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const maxNombres = 3;
    final nombres = servicios.map((s) => s.servicio?.nombre ?? '—').toList();
    final resumen = nombres.take(maxNombres).join(' · ');
    final resto = nombres.length - maxNombres;
    final aviso = _aviso;

    return Material(
      color: seleccionada
          ? AppTheme.primary.withValues(alpha: 0.06)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: seleccionada ? AppTheme.primary : Colors.grey.shade200,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          // Un local oculto sigue en la lista (hay que poder reactivarlo), pero
          // atenuado para que se note de un vistazo.
          opacity: local.activo ? 1 : 0.65,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                FotoLocal(local: local),
                const SizedBox(width: 12),
                Expanded(
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
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!local.activo) ...[
                            const SizedBox(width: 6),
                            const ChipEstado(
                              texto: 'Inactivo',
                              color: AppTheme.warning,
                            ),
                          ],
                        ],
                      ),
                      if (servicios.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          resto > 0 ? '$resumen  +$resto' : resumen,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                      if (aviso != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 14,
                              color: AppTheme.warning,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                aviso,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SinLocales extends StatelessWidget {
  final VoidCallback onNuevo;
  const _SinLocales({required this.onNuevo});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.store_outlined,
              size: 64,
              color: AppTheme.primary.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            const Text(
              'Todavía no tienes locales',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'El local es el sitio donde atiendes. Créalo y después añádele '
              'los servicios que ofrece.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onNuevo,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Crear el primer local'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NadaSeleccionado extends StatelessWidget {
  const _NadaSeleccionado();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.touch_app_outlined,
            size: 48,
            color: AppTheme.primary.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 10),
          const Text(
            'Elige un local para ver sus servicios',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
