import 'dart:async';

import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/config_precio.dart';
import '../../models/precio_config.dart';
import '../../models/recurso.dart';
import '../../models/servicio.dart';
import '../../models/tasa_cambio.dart';
import '../../services/auth_service.dart';
import '../../services/precio_config_service.dart';
import '../../services/recurso_service.dart';
import '../../services/tasa_cambio_service.dart';
import '../../tutorial/tutorial_anchor.dart';
import '../../utils/conversion_precio.dart';
import '../../utils/parse_monto.dart';

/// Pantalla que envuelve el panel de configuración de recursos de un
/// local_servicio.
///
/// Mantiene el AppBar y Scaffold; toda la lógica y UI vive en
/// [ConfigRecursosPanel].
class ConfigRecursosScreen extends StatefulWidget {
  final LocalServicio localServicio;
  const ConfigRecursosScreen({super.key, required this.localServicio});

  @override
  State<ConfigRecursosScreen> createState() => _ConfigRecursosScreenState();
}

class _ConfigRecursosScreenState extends State<ConfigRecursosScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recursos y turnos')),
      // El hueco del tutorial cubre todo el panel (modo simple, alta de
      // recursos y turnos) para que el admin pueda interactuar con él.
      body: TutorialAnchor(
        id: 'admin_recursos_turnos',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConfigRecursosPanel(localServicio: widget.localServicio),
        ),
      ),
    );
  }
}

/// Configuración de RECURSOS, TRAMOS y TURNOS de un local_servicio.
///
/// Jerarquía editable (con ejemplos de varios oficios, no sólo transporte):
///   Recurso (Carro 1 / Mesa 3 / Habitación 4) → Tramos (Ida, Vuelta, Entrada)
///   → Turnos (la opción que el cliente elige)
/// Un turno consume 1 plaza de cada tramo marcado. La disponibilidad de un
/// turno = mínimo de los tramos que ocupa (capacidad compartida).
///
/// Es OPCIONAL, y desde el punto 6 del plan de mejoras hay dos atajos para quien
/// no necesita pensar en tramos:
///   · `sin_tramos`  → se ocultan los tramos; cada turno recibe un tramo oculto
///                     propio (cupo independiente por turno).
///   · `solo_turnos` → además se ocultan los recursos: el admin sólo ve una
///                     lista de turnos y el sistema crea el recurso oculto.
/// En ambos casos los objetos siguen existiendo en la base de datos: no se
/// cambia ni una regla de `_ls_tiene_recursos`, `plan_tramo` ni la reserva.
///
/// Es OPCIONAL: si un servicio no define recursos, sigue funcionando con el
/// cupo por día de siempre (plan_servicios).
class ConfigRecursosPanel extends StatefulWidget {
  final LocalServicio localServicio;
  final VoidCallback? onUpdated;
  final bool showHeader;

  const ConfigRecursosPanel({
    super.key,
    required this.localServicio,
    this.onUpdated,
    this.showHeader = true,
  });

  @override
  State<ConfigRecursosPanel> createState() => _ConfigRecursosPanelState();
}

class _ConfigRecursosPanelState extends State<ConfigRecursosPanel> {
  List<Recurso> _recursos = [];
  bool _loading = true;

  /// Modo simplificado: no se gestionan tramos (se crean solos, uno por turno).
  late bool _sinTramos;

  /// Modo simplificado extremo: tampoco se gestionan recursos.
  late bool _soloTurnos;

  bool _cambiandoModo = false;

  /// Configuración de precios de la entidad dueña del servicio (moneda de
  /// origen y redondeo). Se lee una vez; si no se puede, quedan los valores por
  /// defecto de la base y el formulario de turno sigue funcionando.
  PrecioConfig _precioConfig = const PrecioConfig();

  String get _uuid => AuthService.currentUserId ?? '';

  /// Moneda del servicio para el precio fijo de los turnos.
  String get _moneda =>
      widget.localServicio.servicio?.configPrecio.monedaDefault ?? 'USD';

  /// Monedas habilitadas del servicio: el turno guarda el precio en TODAS (el
  /// cliente lo verá en la que corresponda), no sólo en la moneda por defecto.
  List<String> get _monedasServicio {
    final monedas = widget.localServicio.servicio?.configPrecio.monedas;
    if (monedas == null || monedas.isEmpty) return ['USD'];
    return [...monedas];
  }

  bool get _esTransporte => widget.localServicio.esTransporteOmnibus;

  /// En modo simple los tramos y el recurso son invisibles: no tiene sentido
  /// asustar al admin con las reglas de mínimos de ida/vuelta del transporte.
  bool get _modoSimple => _soloTurnos || _sinTramos;

  /// Recursos que se pintan. En "solo turnos" la lista queda vacía porque todo
  /// se muestra en el bloque plano de turnos.
  List<Recurso> get _recursosVisibles => _soloTurnos ? const [] : _recursos;

  /// Todos los turnos del local_servicio con su recurso, para el modo simple.
  List<(Recurso, Turno)> get _turnosPlano => [
    for (final r in _recursos)
      for (final t in r.turnos) (r, t),
  ];

  /// Para transporte: cada recurso activo debe tener al menos un turno solo-ida
  /// y un turno solo-vuelta. El turno combinado (ida+vuelta) es opcional.
  String? get _avisoTurnosMinimos {
    if (!_esTransporte || _modoSimple) return null;
    final incompletos = <String>[];
    for (final r in _recursos.where((e) => e.activo)) {
      final falta = _faltantesTurnosMinimos(r);
      if (falta.isNotEmpty) {
        incompletos.add('${r.nombre}: faltan turnos de ${falta.join(' y ')}');
      }
    }
    if (incompletos.isEmpty) return null;
    return 'Configuración incompleta. Cada vehículo necesita mínimo un turno '
        'de Ida y uno de Vuelta.\n${incompletos.join('\n')}';
  }

  static List<String> _faltantesTurnosMinimos(Recurso r) {
    final tramosById = {for (final t in r.tramos) t.id: t};
    var tieneIda = false;
    var tieneVuelta = false;
    for (final turno in r.turnos.where((t) => t.activo)) {
      final tipos = turno.tramosIds
          .map((id) => tramosById[id]?.tipoTrayecto)
          .whereType<String>()
          .toSet();
      if (tipos.length == 1 && tipos.contains('ida')) tieneIda = true;
      if (tipos.length == 1 && tipos.contains('vuelta')) tieneVuelta = true;
    }
    return [if (!tieneIda) 'Ida', if (!tieneVuelta) 'Vuelta'];
  }

  @override
  void initState() {
    super.initState();
    _soloTurnos = widget.localServicio.soloTurnos;
    _sinTramos = widget.localServicio.sinTramos;
    _cargarPrecioConfig();
    _cargar();
  }

  /// Configuración de precios automáticos de la entidad dueña del servicio.
  ///
  /// Se resuelve a partir del servicio (el panel no conoce la entidad) y no
  /// bloquea la pantalla: mientras llega se usan los valores por defecto.
  Future<void> _cargarPrecioConfig() async {
    final config = await PrecioConfigService.paraServicio(
      widget.localServicio.idServicio,
    );
    if (!mounted) return;
    setState(() => _precioConfig = config);
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final recursos = await RecursoService.listar(
        uuidUsuario: _uuid,
        idLocalServicio: widget.localServicio.id,
      );
      if (mounted) {
        setState(() => _recursos = recursos);
        widget.onUpdated?.call();
      }
    } catch (e) {
      _snack('Error al cargar: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── Modo de gestión (punto 6) ──────────────────────────────────────────

  /// Activa/desactiva los modos simplificados.
  ///
  /// Todo el trabajo lo hace la RPC en una transacción: guarda las banderas,
  /// garantiza el recurso oculto si hace falta y crea un tramo oculto por cada
  /// turno que aún no tenga. Aquí sólo se refleja el resultado y se recarga.
  Future<void> _cambiarModo({bool? soloTurnos, bool? sinTramos}) async {
    final nuevoSolo = soloTurnos ?? _soloTurnos;
    final nuevoSin = sinTramos ?? _sinTramos;
    setState(() => _cambiandoModo = true);
    try {
      final res = await RecursoService.configurarModo(
        uuidUsuario: _uuid,
        idLocalServicio: widget.localServicio.id,
        soloTurnos: nuevoSolo,
        sinTramos: nuevoSin,
      );
      if (!mounted) return;
      setState(() {
        _soloTurnos = res.soloTurnos;
        _sinTramos = res.sinTramos;
      });
      widget.onUpdated?.call();
      await _cargar();
      if (!mounted) return;
      final detalles = <String>[
        if (res.recursoCreado) 'se creó el cupo interno',
        if (res.tramosCreados > 0)
          'se creó ${res.tramosCreados} tramo(s) interno(s)',
      ];
      _snack(
        detalles.isEmpty
            ? 'Modo actualizado'
            : 'Modo actualizado: ${detalles.join(' y ')}.',
        AppTheme.success,
      );
    } catch (e) {
      // La RPC rechaza "solo turnos" cuando hay varios recursos: el mensaje ya
      // explica qué hacer, así que se muestra tal cual.
      _snack('$e'.replaceFirst('Exception: ', ''), AppTheme.warning);
    } finally {
      if (mounted) setState(() => _cambiandoModo = false);
    }
  }

  // ── Recurso ────────────────────────────────────────────────────────────

  Future<void> _editarRecurso({Recurso? recurso}) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RecursoFormSheet(
        uuid: _uuid,
        idLocalServicio: widget.localServicio.id,
        recurso: recurso,
      ),
    );
    if (res == true) _cargar();
  }

  Future<void> _eliminarRecurso(Recurso r) async {
    final ok = await _confirmar(
      '¿Eliminar el recurso "${r.nombre}"?\n\nSe borrarán sus tramos, turnos y los cupos por día asociados.',
    );
    if (ok != true) return;
    try {
      await RecursoService.eliminarRecurso(uuidUsuario: _uuid, id: r.id);
      _cargar();
    } catch (e) {
      _snack('Error: $e', AppTheme.error);
    }
  }

  // ── Tramo ──────────────────────────────────────────────────────────────

  Future<void> _editarTramo(Recurso recurso, {Tramo? tramo}) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TramoFormSheet(
        uuid: _uuid,
        recurso: recurso,
        tramo: tramo,
        esTransporte: widget.localServicio.esTransporteOmnibus,
      ),
    );
    if (res == true) _cargar();
  }

  Future<void> _eliminarTramo(Tramo t) async {
    final ok = await _confirmar(
      '¿Eliminar el tramo "${t.nombre}"?\n\nLos turnos que lo usaban dejarán de ocuparlo.',
    );
    if (ok != true) return;
    try {
      await RecursoService.eliminarTramo(uuidUsuario: _uuid, id: t.id);
      _cargar();
    } catch (e) {
      _snack('Error: $e', AppTheme.error);
    }
  }

  // ── Turno ──────────────────────────────────────────────────────────────

  Future<void> _editarTurno(Recurso recurso, {Turno? turno}) async {
    // En modo simple los tramos son un detalle interno: no se piden. Fuera de
    // él, un turno sin tramos no tendría cupo que descontar.
    if (!_sinTramos && recurso.tramos.where((t) => t.activo).isEmpty) {
      _snack(
        'Primero agrega al menos un tramo a este recurso.',
        AppTheme.warning,
      );
      return;
    }
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TurnoFormSheet(
        uuid: _uuid,
        recurso: recurso,
        idLocalServicio: widget.localServicio.id,
        turno: turno,
        sinTramos: _sinTramos,
        moneda: _moneda,
        monedas: _monedasServicio,
        precioConfig: _precioConfig,
        exigirTurnosMinimos: _esTransporte && !_modoSimple,
      ),
    );
    if (res == true) _cargar();
  }

  /// Alta de turno en "Solo configurar turnos" cuando todavía no existe ningún
  /// recurso: la RPC crea el cupo interno y el tramo la primera vez.
  Future<void> _nuevoTurnoModoSimple() async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TurnoFormSheet(
        uuid: _uuid,
        recurso: null,
        idLocalServicio: widget.localServicio.id,
        sinTramos: true,
        moneda: _moneda,
        monedas: _monedasServicio,
        precioConfig: _precioConfig,
      ),
    );
    if (res == true) _cargar();
  }

  Future<void> _eliminarTurno(Recurso recurso, Turno t) async {
    if (_esTransporte) {
      final simulados = recurso.turnos
          .where((x) => x.id != t.id && x.activo)
          .toList();
      final prueba = Recurso(
        id: recurso.id,
        idLocalServicio: recurso.idLocalServicio,
        nombre: recurso.nombre,
        capacidad: recurso.capacidad,
        orden: recurso.orden,
        activo: recurso.activo,
        tramos: recurso.tramos,
        turnos: simulados,
      );
      final falta = _faltantesTurnosMinimos(prueba);
      if (falta.isNotEmpty) {
        _snack(
          'No se puede eliminar: el vehículo quedaría sin turno(s) de '
          '${falta.join(' y ')}. Debe haber mínimo Ida y Vuelta.',
          AppTheme.warning,
        );
        return;
      }
    }
    final ok = await _confirmar('¿Eliminar el turno "${t.nombre}"?');
    if (ok != true) return;
    try {
      await RecursoService.eliminarTurno(uuidUsuario: _uuid, id: t.id);
      _cargar();
    } catch (e) {
      _snack('Error: $e', AppTheme.error);
    }
  }

  Future<bool?> _confirmar(String mensaje) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirmar'),
      content: Text(mensaje),
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

  @override
  Widget build(BuildContext context) {
    final servicio = widget.localServicio.servicio?.nombre ?? 'Servicio';
    final local = widget.localServicio.local?.nombre ?? '';
    final moneda =
        widget.localServicio.servicio?.configPrecio.monedaDefault ?? 'USD';
    final content = ListView(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (widget.showHeader) _Header(servicio: servicio, local: local),
        if (_avisoTurnosMinimos != null) ...[
          const SizedBox(height: 12),
          Material(
            color: AppTheme.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _avisoTurnosMinimos!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _ModoGestionCard(
          soloTurnos: _soloTurnos,
          sinTramos: _sinTramos,
          cambiando: _cambiandoModo,
          cantidadRecursos: _recursos.length,
          onSoloTurnos: (v) => _cambiarModo(
            soloTurnos: v,
            // Activar "solo turnos" implica "sin tramos" (lo exige el CHECK).
            sinTramos: v ? true : _sinTramos,
          ),
          onSinTramos: (v) => _cambiarModo(sinTramos: v),
        ),
        const SizedBox(height: 16),
        if (!_modoSimple) _AyudaTramos(esTransporte: _esTransporte),
        const SizedBox(height: 16),

        if (_soloTurnos) ...[
          // ── Modo "solo configurar turnos": lista plana, sin recursos ──
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Turnos reservables',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              TextButton.icon(
                onPressed: _nuevoTurnoModoSimple,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Turno'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (_turnosPlano.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Aún no hay turnos. Crea el primero: el sistema se encarga del '
                'cupo interno.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  for (final (recurso, turno) in _turnosPlano)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        turno.activo
                            ? Icons.confirmation_number_outlined
                            : Icons.confirmation_number_outlined,
                        color: turno.activo
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                      title: Text(
                        turno.nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: turno.activo ? null : AppTheme.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        _subtituloTurno(turno, moneda: moneda),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () =>
                                _editarTurno(recurso, turno: turno),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppTheme.error,
                            ),
                            onPressed: () => _eliminarTurno(recurso, turno),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ] else ...[
          // ── Modo normal: recursos (con o sin tramos visibles) ──
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: () => _editarRecurso(),
              icon: const Icon(Icons.add),
              label: const Text('Recurso'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_recursos.isEmpty)
            _EmptyState(onCrear: () => _editarRecurso())
          else
            ..._recursosVisibles.map(
              (r) => _RecursoCard(
                recurso: r,
                ocultarTramos: _sinTramos,
                onEditRecurso: () => _editarRecurso(recurso: r),
                onDeleteRecurso: () => _eliminarRecurso(r),
                onAddTramo: () => _editarTramo(r),
                onEditTramo: (t) => _editarTramo(r, tramo: t),
                onDeleteTramo: _eliminarTramo,
                onAddTurno: () => _editarTurno(r),
                onEditTurno: (t) => _editarTurno(r, turno: t),
                onDeleteTurno: (t) => _eliminarTurno(r, t),
              ),
            ),
        ],
      ],
    );

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(onRefresh: _cargar, child: content);
  }
}

/// Subtítulo de un turno: horas (si las tiene), tramos y precios.
String _subtituloTurno(Turno turno, {required String moneda}) {
  final partes = <String>[
    if (turno.etiquetaHora != null) turno.etiquetaHora!,
    if (turno.precios.isNotEmpty)
      turno.precios.entries
          .map(
            (e) =>
                '${e.value.toStringAsFixed(e.value == e.value.roundToDouble() ? 0 : 2)} ${e.key}',
          )
          .join(' · '),
  ];
  return partes.isEmpty ? 'Sin precio fijo' : partes.join('  ·  ');
}

// ══════════════════════════════════════════════════════════════════════════
//  Header + estado vacío
// ══════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final String servicio;
  final String local;
  const _Header({required this.servicio, required this.local});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune_outlined, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  servicio,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (local.isNotEmpty)
                  Text(
                    local,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 6),
                const Text(
                  'Aquí se define QUÉ puede reservarse y CUÁNTO cabe por día. '
                  'Si sólo necesitas horarios (ej: turnos de 9:00, 10:00...), '
                  'activa el modo simple más abajo y olvídate de recursos y '
                  'tramos.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Explicación de qué es un "recurso" y qué es un "tramo", pensada para que la
/// entienda quien corta uñas o alquila habitaciones, no sólo un transportista.
class _AyudaTramos extends StatelessWidget {
  final bool esTransporte;
  const _AyudaTramos({required this.esTransporte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 18,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '¿Qué es un recurso y qué es un tramo?',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _AyudaParrafo(
            titulo: 'Recurso',
            texto:
                'Es "la cosa" que atiende a un cliente a la vez: Carro 1, Mesa '
                '3, Habitación 4, Sillón de uñas, Sillón 2. Cada recurso lleva '
                'su propia capacidad por día.',
          ),
          const SizedBox(height: 6),
          const _AyudaParrafo(
            titulo: 'Tramo',
            texto:
                'Es un contador dentro del recurso. Sólo hace falta cuando una '
                'misma reserva consume varias plazas a la vez. Ejemplo de '
                'transporte: un recurso "Carro 1" con los tramos Ida y Vuelta, '
                'porque un pasaje de ida y vuelta gasta una plaza en cada uno.',
          ),
          const SizedBox(height: 6),
          _AyudaParrafo(
            titulo: 'Turno',
            texto: esTransporte
                ? 'Es la opción que el cliente elige: "Solo ida", "Solo '
                      'vuelta", "Ida y vuelta". Puede llevar horas y precio '
                      'propios.'
                : 'Es la opción que el cliente elige: "9:00 – 10:00", "Turno '
                      'mañana", "Sesión completa". Puede llevar horas y precio '
                      'propios.',
          ),
          const SizedBox(height: 10),
          const Text(
            'Regla práctica: si cada reserva gasta una sola plaza, NO uses '
            'tramos. Marca "No uso tramos" abajo y listo.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AyudaParrafo extends StatelessWidget {
  const _AyudaParrafo({required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.textSecondary,
          height: 1.35,
        ),
        children: [
          TextSpan(
            text: '$titulo: ',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          TextSpan(text: texto),
        ],
      ),
    );
  }
}

/// Tarjeta con los dos atajos del punto 6 del plan.
class _ModoGestionCard extends StatelessWidget {
  const _ModoGestionCard({
    required this.soloTurnos,
    required this.sinTramos,
    required this.cambiando,
    required this.cantidadRecursos,
    required this.onSoloTurnos,
    required this.onSinTramos,
  });

  final bool soloTurnos;
  final bool sinTramos;
  final bool cambiando;
  final int cantidadRecursos;
  final ValueChanged<bool> onSoloTurnos;
  final ValueChanged<bool> onSinTramos;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Modo de configuración',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                if (cambiando) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            activeColor: AppTheme.primary,
            value: sinTramos || soloTurnos,
            onChanged: cambiando ? null : (v) => onSinTramos(v == true),
            title: const Text(
              'No uso tramos',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Oculta los tramos. Cada turno recibe un cupo propio e '
              'independiente, así que el cupo del día se reparte por turno.',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            activeColor: AppTheme.primary,
            value: soloTurnos,
            onChanged: cambiando ? null : (v) => onSoloTurnos(v == true),
            title: const Text(
              'Solo configurar turnos',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Verás únicamente la lista de turnos. '
              '${cantidadRecursos > 1 ? 'Requiere tener un solo recurso: ahora hay $cantidadRecursos.' : 'El sistema crea el cupo interno que necesite.'}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              'Recursos y tramos se siguen guardando por dentro, sólo se '
              'ocultan. Las reservas y los cupos por día funcionan igual.',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCrear;
  const _EmptyState({required this.onCrear});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            size: 56,
            color: AppTheme.textSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sin recursos configurados',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Este servicio usa el cupo por día normal: sirve para agendar sin '
              'distinguir entre varias personas, mesas o habitaciones. Crea un '
              'recurso por cada una si quieres controlar su cupo por separado.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onCrear,
            icon: const Icon(Icons.add),
            label: const Text('Crear primer recurso'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Tarjeta de recurso (con sus tramos y turnos)
// ══════════════════════════════════════════════════════════════════════════

class _RecursoCard extends StatelessWidget {
  final Recurso recurso;

  /// Modo "no uso tramos": se oculta la sección de tramos (siguen existiendo en
  /// la base de datos, uno por turno, pero son un detalle interno).
  final bool ocultarTramos;
  final VoidCallback onEditRecurso;
  final VoidCallback onDeleteRecurso;
  final VoidCallback onAddTramo;
  final void Function(Tramo) onEditTramo;
  final void Function(Tramo) onDeleteTramo;
  final VoidCallback onAddTurno;
  final void Function(Turno) onEditTurno;
  final void Function(Turno) onDeleteTurno;

  const _RecursoCard({
    required this.recurso,
    required this.onEditRecurso,
    required this.onDeleteRecurso,
    required this.onAddTramo,
    required this.onEditTramo,
    required this.onDeleteTramo,
    required this.onAddTurno,
    required this.onEditTurno,
    required this.onDeleteTurno,
    this.ocultarTramos = false,
  });

  String _nombresTramos(Turno t) {
    final nombres = recurso.tramos
        .where((tr) => t.tramosIds.contains(tr.id))
        .map((tr) => tr.nombre)
        .toList();
    return nombres.isEmpty ? 'sin tramos' : nombres.join(' + ');
  }

  /// Línea secundaria de un turno: horas (punto 7), tramos y precios.
  String _detalleTurno(Turno t) {
    final partes = <String>[
      if (t.etiquetaHora != null) t.etiquetaHora!,
      if (!ocultarTramos) _nombresTramos(t),
      if (t.precios.isNotEmpty)
        t.precios.entries
            .map(
              (e) =>
                  '${e.value.toStringAsFixed(e.value == e.value.roundToDouble() ? 0 : 2)} ${e.key}',
            )
            .join(' · '),
    ];
    return partes.isEmpty ? 'Sin precio fijo' : partes.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera recurso
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.widgets_outlined,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recurso.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        ocultarTramos
                            ? '${recurso.turnos.length} turno(s)'
                            : '${recurso.tramos.length} tramo(s) · '
                                  '${recurso.turnos.length} turno(s)',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!recurso.activo)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Chip(
                      label: Text('inactivo'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEditRecurso,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppTheme.error,
                  ),
                  onPressed: onDeleteRecurso,
                ),
              ],
            ),
            const Divider(height: 20),

            // Tramos (ocultos en modo "no uso tramos": el sistema crea uno
            // interno por turno, así que no hay nada que el admin deba tocar).
            if (!ocultarTramos) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tramos',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  TextButton.icon(
                    onPressed: onAddTramo,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Añadir'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              if (recurso.tramos.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Aún no hay tramos.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: recurso.tramos.map((t) {
                    return InputChip(
                      label: Text(t.nombre),
                      onPressed: () => onEditTramo(t),
                      onDeleted: () => onDeleteTramo(t),
                      backgroundColor: AppTheme.accent.withValues(alpha: 0.10),
                      deleteIconColor: AppTheme.error,
                    );
                  }).toList(),
                ),
              const SizedBox(height: 14),
            ],

            // Turnos
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Turnos reservables',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                TextButton.icon(
                  onPressed: onAddTurno,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Añadir'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            if (recurso.turnos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Aún no hay turnos.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              )
            else
              ...recurso.turnos.map(
                (t) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(
                    Icons.confirmation_number_outlined,
                    color: AppTheme.primary,
                  ),
                  title: Text(
                    t.nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    _detalleTurno(t),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => onEditTurno(t),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppTheme.error,
                        ),
                        onPressed: () => onDeleteTurno(t),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Formularios (bottom sheets)
// ══════════════════════════════════════════════════════════════════════════

class _RecursoFormSheet extends StatefulWidget {
  final String uuid;
  final int idLocalServicio;
  final Recurso? recurso;
  const _RecursoFormSheet({
    required this.uuid,
    required this.idLocalServicio,
    this.recurso,
  });

  @override
  State<_RecursoFormSheet> createState() => _RecursoFormSheetState();
}

class _RecursoFormSheetState extends State<_RecursoFormSheet> {
  late final TextEditingController _nombre = TextEditingController(
    text: widget.recurso?.nombre ?? '',
  );
  late bool _activo = widget.recurso?.activo ?? true;
  bool _saving = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _err('El nombre es obligatorio');
      return;
    }
    setState(() => _saving = true);
    try {
      await RecursoService.guardarRecurso(
        uuidUsuario: widget.uuid,
        idLocalServicio: widget.idLocalServicio,
        nombre: nombre,
        // La capacidad ya no se define aquí: se fija al planificar (por día).
        // Se conserva el valor previo (o 1) solo porque la RPC lo exige.
        capacidad: widget.recurso?.capacidad ?? 1,
        activo: _activo,
        id: widget.recurso?.id,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _err('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(m), backgroundColor: AppTheme.error));

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      titulo: widget.recurso == null ? 'Nuevo recurso' : 'Editar recurso',
      saving: _saving,
      onGuardar: _guardar,
      children: [
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre *',
            hintText: 'Ej: Carro 1',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La capacidad se define al planificar (por día), no aquí. '
                  'Este recurso solo agrupa tramos y turnos.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activo'),
          value: _activo,
          activeThumbColor: AppTheme.primary,
          onChanged: (v) => setState(() => _activo = v),
        ),
      ],
    );
  }
}

class _TramoFormSheet extends StatefulWidget {
  final String uuid;
  final Recurso recurso;
  final Tramo? tramo;
  final bool esTransporte;
  const _TramoFormSheet({
    required this.uuid,
    required this.recurso,
    this.tramo,
    this.esTransporte = false,
  });

  @override
  State<_TramoFormSheet> createState() => _TramoFormSheetState();
}

class _TramoFormSheetState extends State<_TramoFormSheet> {
  late final TextEditingController _nombre = TextEditingController(
    text: widget.tramo?.nombre ?? '',
  );
  late bool _activo = widget.tramo?.activo ?? true;
  late String _tipoTrayecto = widget.tramo?.tipoTrayecto ?? 'ida';
  bool _saving = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _err('El nombre es obligatorio');
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.esTransporte) {
        await RecursoService.guardarTramoTransporte(
          uuidUsuario: widget.uuid,
          idRecurso: widget.recurso.id,
          nombre: nombre,
          tipoTrayecto: _tipoTrayecto,
          activo: _activo,
          id: widget.tramo?.id,
        );
      } else {
        await RecursoService.guardarTramo(
          uuidUsuario: widget.uuid,
          idRecurso: widget.recurso.id,
          nombre: nombre,
          capacidad: widget.tramo?.capacidad,
          activo: _activo,
          id: widget.tramo?.id,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _err('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String m) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(m), backgroundColor: AppTheme.error));

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      titulo: widget.tramo == null ? 'Nuevo tramo' : 'Editar tramo',
      saving: _saving,
      onGuardar: _guardar,
      children: [
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nombre *',
            hintText: 'Ej: Ida, Vuelta',
            border: OutlineInputBorder(),
          ),
        ),
        if (widget.esTransporte) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _tipoTrayecto,
            decoration: const InputDecoration(
              labelText: 'Trayecto *',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'ida', child: Text('Ida')),
              DropdownMenuItem(value: 'vuelta', child: Text('Vuelta')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _tipoTrayecto = value);
            },
          ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activo'),
          value: _activo,
          activeThumbColor: AppTheme.primary,
          onChanged: (v) => setState(() => _activo = v),
        ),
      ],
    );
  }
}

class _TurnoFormSheet extends StatefulWidget {
  final String uuid;

  /// `null` en modo "solo configurar turnos" cuando el recurso oculto todavía no
  /// existe: la RPC `admin_guardar_turno_auto` lo crea.
  final Recurso? recurso;
  final int idLocalServicio;
  final Turno? turno;
  final String moneda;

  /// Monedas habilitadas del servicio: el turno guarda el precio en todas.
  final List<String> monedas;

  /// Configuración de precios de la entidad (origen + decimales).
  final PrecioConfig precioConfig;

  final bool exigirTurnosMinimos;

  /// Modo "no uso tramos": no se piden tramos; la RPC asigna el tramo propio del
  /// turno (y lo crea si falta).
  final bool sinTramos;

  const _TurnoFormSheet({
    required this.uuid,
    required this.idLocalServicio,
    required this.moneda,
    this.recurso,
    this.turno,
    this.monedas = const ['USD'],
    this.precioConfig = const PrecioConfig(),
    this.exigirTurnosMinimos = false,
    this.sinTramos = false,
  });

  @override
  State<_TurnoFormSheet> createState() => _TurnoFormSheetState();
}

class _TurnoFormSheetState extends State<_TurnoFormSheet> {
  late final TextEditingController _nombre = TextEditingController(
    text: widget.turno?.nombre ?? '',
  );
  late final Set<int> _tramosSel = {...(widget.turno?.tramosIds ?? const [])};
  late bool _activo = widget.turno?.activo ?? true;

  /// Un controlador de precio por moneda habilitada del servicio.
  late final Map<String, TextEditingController> _preciosCtrls = {
    for (final m in widget.monedas)
      m: TextEditingController(text: _textoPrecio(widget.turno?.precios[m])),
  };

  // ── Punto 4: precios automáticos con la tasa del día ──
  bool _calculandoPrecios = false;

  /// Contexto del cartel de extracción, para cerrarlo sin tocar la pila.
  BuildContext? _cartelCtx;

  /// Tasa con la que se calcularon los precios que hay ahora en la hoja.
  TasasDia? _tasasUsadas;

  /// Se está extrayendo la tasa: banner discreto (el diálogo modal es del botón).
  bool _extrayendoTasa = false;

  /// Último valor YA calculado por moneda de origen («CUP» -> 17000).
  ///
  /// Es un mapa y no una única firma global: con una sola firma, el cálculo de
  /// una moneda bloqueaba el de otra y editar CUP después de USD no recalculaba
  /// nada.
  final Map<String, double> _ultimoCalculado = {};

  /// Monedas cuyo precio lo puso el cálculo automático: salen en verde con su
  /// icono dentro del cuadro. Al editar a mano deja de estar marcada.
  final Set<String> _calculadas = {};

  /// El aviso de «no hay tasa» se da una sola vez por hoja.
  bool _avisoTasaMostrado = false;

  Timer? _debounceAuto;

  // ── Punto 7: la hora del turno es opcional ──
  TimeOfDay? _horaInicio;
  TimeOfDay? _horaFin;
  bool _saving = false;

  /// Moneda **base** del turno: la del servicio (`widget.moneda`, que es su
  /// «Moneda por defecto») si está habilitada. La preferencia de la entidad no
  /// manda: se usa solo como respaldo, igual que en el formulario del servicio.
  String get _origenEfectivo {
    if (widget.monedas.contains(widget.moneda)) return widget.moneda;
    if (widget.monedas.contains(widget.precioConfig.monedaOrigen)) {
      return widget.precioConfig.monedaOrigen;
    }
    return widget.monedas.isNotEmpty ? widget.monedas.first : widget.moneda;
  }

  /// Monedas del turno con la **base primero**.
  List<String> get _monedasOrdenadas => [
    _origenEfectivo,
    ...widget.monedas.where((m) => m != _origenEfectivo),
  ];

  /// La base se distingue con el sello «BASE» y el color de marca; un precio
  /// calculado sale en **verde** con su icono dentro del cuadro (y deja de
  /// estarlo en cuanto se escribe a mano).
  InputDecoration _decoracionPrecio(String m) {
    final esBase = m == _origenEfectivo;
    final calculada = _calculadas.contains(m);
    final color = calculada
        ? AppTheme.success
        : (esBase ? AppTheme.primary : null);

    return InputDecoration(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Precio fijo (${MonedasApp.simbolo(m)})'),
          if (esBase) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'BASE',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      fillColor: color?.withValues(alpha: 0.07),
      border: const OutlineInputBorder(),
      enabledBorder: color == null
          ? null
          : OutlineInputBorder(
              borderSide: BorderSide(color: color, width: 1.5),
            ),
      focusedBorder: color == null
          ? null
          : OutlineInputBorder(
              borderSide: BorderSide(color: color, width: 1.8),
            ),
      suffixIcon: calculada
          ? const Tooltip(
              message: 'Calculado con la tasa del día',
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppTheme.success,
              ),
            )
          : null,
    );
  }

  /// `18.375` guardado se releería como 18375 (`parseMonto` lee tres decimales
  /// como millares), así que se limita a los decimales de precio.
  static String _textoPrecio(double? valor) {
    if (valor == null || valor == 0) return '';
    return Redondeo.texto(valor, Redondeo.maxDecimales);
  }

  @override
  void initState() {
    super.initState();
    _horaInicio = _parseHora(widget.turno?.horaInicio);
    _horaFin = _parseHora(widget.turno?.horaFin);
  }

  static TimeOfDay? _parseHora(String? texto) {
    if (texto == null) return null;
    final partes = texto.split(':');
    if (partes.length < 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  static String _textoHora(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:'
      '${h.minute.toString().padLeft(2, '0')}';

  String? get _horaInicioTexto =>
      _horaInicio == null ? null : _textoHora(_horaInicio!);
  String? get _horaFinTexto => _horaFin == null ? null : _textoHora(_horaFin!);

  @override
  void dispose() {
    _debounceAuto?.cancel();
    _nombre.dispose();
    for (final c in _preciosCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Precios automáticos con la tasa del día (punto 4) ────────────────────

  /// Lee un precio escrito a mano. `null` si no hay número o no es positivo:
  /// en esta app `0` significa «sin precio».
  double? _precioEscrito(TextEditingController? ctrl) {
    final valor = parseMonto(ctrl?.text ?? '');
    if (valor == null || valor <= 0) return null;
    return valor;
  }

  /// De dónde sale el precio que se convierte: el de la moneda de origen o, si
  /// está vacío, el de la primera moneda con precio.
  ({String moneda, double valor})? _baseParaCalcular([String? origenPedido]) {
    final origen = origenPedido ?? _origenEfectivo;
    final propio = _precioEscrito(_preciosCtrls[origen]);
    if (propio != null) return (moneda: origen, valor: propio);
    for (final m in widget.monedas) {
      final valor = _precioEscrito(_preciosCtrls[m]);
      if (valor != null) return (moneda: m, valor: valor);
    }
    return null;
  }

  void _snack(String mensaje, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: color ?? AppTheme.warning,
        ),
      );
  }

  /// Cartel no descartable mientras se extrae la tasa (mismo texto que en el
  /// formulario de servicio). Se espera un frame para que su contexto exista
  /// antes de cerrarlo.
  Future<void> _mostrarCartelExtraccion() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        _cartelCtx = ctx;
        return const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text('Extrayendo los precios automáticamente...'),
                ),
              ],
            ),
          ),
        );
      },
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  void _cerrarCartelExtraccion() {
    final ctx = _cartelCtx;
    _cartelCtx = null;
    if (ctx == null || !ctx.mounted) return;
    Navigator.of(ctx).pop();
  }

  /// Calcula el resto de monedas del turno con la tasa del día. Sin tasa no se
  /// toca ningún precio: se avisa y se deja todo como estaba.
  Future<void> _calcularRestoDesdeOrigen({
    String? origen,
    bool avisar = true,
  }) async {
    if (_calculandoPrecios) return;
    if (widget.monedas.length < 2) {
      if (avisar) {
        _snack(
          'Este servicio sólo tiene una moneda habilitada. Añade otra en la '
          'configuración del servicio para calcular el resto.',
        );
      }
      return;
    }

    setState(() => _calculandoPrecios = true);
    await _mostrarCartelExtraccion();

    TasasDia? tasas;
    try {
      tasas = await TasaCambioService.obtener();
    } finally {
      _cerrarCartelExtraccion();
      if (mounted) setState(() => _calculandoPrecios = false);
    }
    if (!mounted) return;

    if (tasas == null) {
      _snack(
        'No se pudo obtener la tasa de cambio. Los precios no se han '
        'modificado.',
        color: AppTheme.error,
      );
      return;
    }

    final base = _baseParaCalcular(origen);
    if (base == null) {
      _snack(
        'Escribe primero un precio en $_origenEfectivo (o en cualquier '
        'moneda) para calcular el resto.',
      );
      return;
    }

    final convertidos = convertirVarios(
      precios: {base.moneda: base.valor},
      origen: base.moneda,
      monedas: widget.monedas,
      tasas: tasas,
      decimalesDe: widget.precioConfig.decimalesDe,
    );
    setState(() {
      _calculadas.clear();
      for (final entrada in convertidos.entries) {
        if (entrada.key == base.moneda) continue;
        final valor = entrada.value;
        if (valor == null) continue; // sin tasa: NO se toca ese precio
        _preciosCtrls[entrada.key]?.text = Redondeo.texto(
          valor,
          widget.precioConfig.decimalesDe(entrada.key),
        );
        _calculadas.add(entrada.key);
      }
      _tasasUsadas = tasas;
    });
    // Al teclear no se avisa con SnackBar en cada pausa: el aviso es del botón.
    if (avisar) {
      _snack(
        'Precios calculados con la tasa del ${tasas.fechaTexto}.',
        color: AppTheme.success,
      );
    }
  }

  /// Cálculo automático al teclear (debounce de 700 ms).
  ///
  /// Ya **no** es «sólo la primera vez»: cada cambio de precio recalcula las
  /// demás monedas del turno, que es lo que se espera sin pulsar nada.
  void _programarCalculoAutomatico(String moneda) {
    _debounceAuto?.cancel();
    _debounceAuto = Timer(const Duration(milliseconds: 700), () {
      _debounceAuto = null;
      if (!mounted) return;
      _calcularAutomatico(moneda);
    });
  }

  Future<void> _calcularAutomatico(String moneda) async {
    if (!mounted || _calculandoPrecios) return;
    if (!widget.precioConfig.autoActivo) return;
    if (widget.monedas.length < 2) return;

    final origen = widget.monedas.contains(moneda) ? moneda : _origenEfectivo;
    final valor = _precioEscrito(_preciosCtrls[origen]);
    if (valor == null || valor <= 0) return;
    final firma = origen;
    if (_ultimoCalculado[firma] == valor) return;
    _ultimoCalculado[firma] = valor;

    var tasas = _tasasUsadas;
    if (tasas == null || !tasas.vigente) {
      setState(() => _extrayendoTasa = true);
      try {
        tasas = await TasaCambioService.obtener();
      } finally {
        if (mounted) setState(() => _extrayendoTasa = false);
      }
      if (!mounted) return;
    }

    if (tasas == null) {
      if (!_avisoTasaMostrado) {
        _avisoTasaMostrado = true;
        _snack(
          'No se pudo obtener la tasa de cambio. Los precios no se han '
          'modificado.',
          color: AppTheme.error,
        );
      }
      return;
    }

    final convertidos = convertirVarios(
      precios: {origen: valor},
      origen: origen,
      monedas: widget.monedas,
      tasas: tasas,
      decimalesDe: widget.precioConfig.decimalesDe,
    );
    setState(() {
      _calculadas.clear();
      for (final entrada in convertidos.entries) {
        if (entrada.key == origen) continue;
        final convertido = entrada.value;
        if (convertido == null) continue; // sin tasa: NO se toca ese precio
        _preciosCtrls[entrada.key]?.text = Redondeo.texto(
          convertido,
          widget.precioConfig.decimalesDe(entrada.key),
        );
        _calculadas.add(entrada.key);
      }
      _tasasUsadas = tasas;
    });
  }

  Future<void> _elegirHora({required bool inicio}) async {
    final elegida = await showTimePicker(
      context: context,
      initialTime:
          (inicio ? _horaInicio : _horaFin) ??
          const TimeOfDay(hour: 9, minute: 0),
      helpText: inicio ? 'Hora de inicio' : 'Hora de fin',
    );
    if (elegida == null || !mounted) return;
    setState(() {
      if (inicio) {
        _horaInicio = elegida;
      } else {
        _horaFin = elegida;
      }
    });
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      _err('El nombre es obligatorio');
      return;
    }
    if (!widget.sinTramos && _tramosSel.isEmpty) {
      _err('Selecciona al menos un tramo que el turno ocupa');
      return;
    }
    // Precio del turno en TODAS las monedas habilitadas del servicio. Se lee
    // con `parseMonto` (admite "1.500" como 1500 y "18.5" como 18,5); un campo
    // vacío simplemente no se guarda para esa moneda.
    final precios = <String, double>{};
    for (final m in widget.monedas) {
      final texto = _preciosCtrls[m]?.text.trim() ?? '';
      if (texto.isEmpty) continue;
      final valor = parseMonto(texto);
      if (valor == null || valor < 0) {
        _err('Ingresa un precio válido en $m');
        return;
      }
      if (valor > 0) precios[m] = valor;
    }
    // Hora fin después de inicio: misma regla que el CHECK de la base de datos,
    // validada aquí para dar un mensaje claro antes de ir a la red.
    if (_horaInicio != null && _horaFin != null) {
      final ini = _horaInicio!.hour * 60 + _horaInicio!.minute;
      final fin = _horaFin!.hour * 60 + _horaFin!.minute;
      if (fin <= ini) {
        _err('La hora de fin debe ser posterior a la de inicio');
        return;
      }
    }

    if (widget.exigirTurnosMinimos && widget.recurso != null) {
      // `widget.recurso` no se promueve a no-nulo (es un campo público detrás de
      // un getter), así que se copia a una local ya garantizada.
      final recurso = widget.recurso!;
      final editado = Turno(
        id: widget.turno?.id ?? -1,
        nombre: nombre,
        orden: widget.turno?.orden ?? 0,
        activo: _activo,
        precios: precios,
        tramosIds: _tramosSel.toList(),
      );
      final restantes = <Turno>[
        for (final t in recurso.turnos)
          if (widget.turno == null || t.id != widget.turno!.id) t,
        if (_activo) editado,
      ];
      final prueba = Recurso(
        id: recurso.id,
        idLocalServicio: recurso.idLocalServicio,
        nombre: recurso.nombre,
        capacidad: recurso.capacidad,
        orden: recurso.orden,
        activo: recurso.activo,
        tramos: recurso.tramos,
        turnos: restantes,
      );
      final falta = _ConfigRecursosPanelState._faltantesTurnosMinimos(prueba);
      // Solo bloquear si ya había configuración completa y esta edición la rompe,
      // o si desactiva/cambia el último turno mínimo. Al crear turnos uno a uno
      // se permite quedar incompleto (el aviso de la pantalla lo indica).
      final antes = _ConfigRecursosPanelState._faltantesTurnosMinimos(recurso);
      if (antes.isEmpty && falta.isNotEmpty) {
        _err(
          'Quedaría sin turno(s) de ${falta.join(' y ')}. '
          'Mantén al menos un turno Solo Ida y uno Solo Vuelta.',
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      TurnoAutoResultado? guardado;
      if (widget.sinTramos) {
        // Camino simple: la RPC resuelve el tramo propio del turno y (si es
        // nuevo) el turno + su vínculo, todo en una transacción.
        // El recurso destino es el que el admin tiene delante: sin `idRecurso`
        // la RPC elegía siempre el primero del local_servicio, así que con
        // varios recursos el turno aparecía siempre en el mismo.
        guardado = await RecursoService.guardarTurnoAuto(
          uuidUsuario: widget.uuid,
          idLocalServicio: widget.idLocalServicio,
          nombre: nombre,
          orden: widget.turno?.orden ?? 0,
          activo: _activo,
          precios: precios,
          horaInicio: _horaInicioTexto,
          horaFin: _horaFinTexto,
          id: widget.turno?.id,
          idRecurso: widget.recurso?.id,
        );
      } else {
        await RecursoService.guardarTurno(
          uuidUsuario: widget.uuid,
          idRecurso: widget.recurso!.id,
          nombre: nombre,
          tramosIds: _tramosSel.toList(),
          activo: _activo,
          precios: precios,
          horaInicio: _horaInicioTexto,
          horaFin: _horaFinTexto,
          id: widget.turno?.id,
        );
      }
      if (!mounted) return;
      if (guardado?.ignoroRecursoElegido == true) _avisoRecursoIgnorado();
      Navigator.pop(context, true);
    } catch (e) {
      _err('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// La base todavía no acepta el recurso elegido (migración 52 sin aplicar).
  /// El turno se guardó, pero en el primer recurso del servicio: se dice claro
  /// en vez de dejar al admin creyendo que quedó donde pidió.
  void _avisoRecursoIgnorado() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        backgroundColor: AppTheme.warning,
        content: Text(
          'El turno se guardó, pero en el primer recurso del servicio: falta '
          'aplicar la migración 52 en Supabase'
          '${widget.recurso == null ? '' : ' para que respete «${widget.recurso!.nombre}»'}.',
        ),
      ),
    );
  }

  void _err(String m) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(m), backgroundColor: AppTheme.error));

  @override
  Widget build(BuildContext context) {
    final tramos =
        widget.recurso?.tramos.where((t) => t.activo).toList() ?? const [];
    final ocultarTramos = widget.sinTramos;
    return _SheetScaffold(
      titulo: widget.turno == null ? 'Nuevo turno' : 'Editar turno',
      saving: _saving,
      onGuardar: _guardar,
      children: [
        TextField(
          controller: _nombre,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Nombre *',
            hintText: ocultarTramos
                ? 'Ej: 9:00 - 10:00, Turno mañana'
                : 'Ej: Ida y vuelta, Solo ida',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // ── Punto 7: hora inicio / hora fin (opcional) ──
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Horario del turno',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Opcional. Sirve para que el cliente vea a qué hora empieza y '
            'termina, no sólo el nombre.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _elegirHora(inicio: true),
                icon: const Icon(Icons.schedule, size: 16),
                label: Text(
                  _horaInicio == null
                      ? 'Hora inicio'
                      : _textoHora(_horaInicio!),
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _elegirHora(inicio: false),
                icon: const Icon(Icons.schedule_outlined, size: 16),
                label: Text(
                  _horaFin == null ? 'Hora fin' : _textoHora(_horaFin!),
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        if (_horaInicio != null || _horaFin != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _horaInicio = null;
                _horaFin = null;
              }),
              icon: const Icon(Icons.clear, size: 14),
              label: const Text('Quitar horas', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
        const SizedBox(height: 8),
        // ── Precio del turno (punto 4) ─────────────────
        Row(
          children: [
            const Expanded(
              child: Text(
                'Precio del turno',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: _calculandoPrecios
                  ? null
                  : _calcularRestoDesdeOrigen,
              icon: const Icon(Icons.calculate_outlined, size: 16),
              label: Text(
                'Calcular desde $_origenEfectivo',
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ],
        ),
        // Banner discreto del cálculo automático (el diálogo es del botón).
        if (_extrayendoTasa)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Extrayendo los precios automáticamente...',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        for (final m in _monedasOrdenadas)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _preciosCtrls[m],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _decoracionPrecio(m),
              // Cálculo automático: se dispara escribiendo en CUALQUIER moneda
              // (la que el admin esté tocando, incluida la base) y rellena las
              // demás.
              onChanged: (_) {
                // Escrito a mano ⇒ este campo deja de ser «calculado».
                if (_calculadas.remove(m)) setState(() {});
                if (widget.precioConfig.autoActivo) {
                  _programarCalculoAutomatico(m);
                }
              },
            ),
          ),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Opcional. Un campo vacío usa el precio base del servicio.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        if (_tasasUsadas != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Precios calculados con la tasa del '
                    '${_tasasUsadas!.fechaTexto}. Revísalos antes de guardar.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (ocultarTramos) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: AppTheme.accent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Este turno tendrá su propio cupo, independiente del resto '
                    'de turnos. No hace falta configurar tramos.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tramos que ocupa este turno *',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Reservar este turno descuenta 1 plaza de cada tramo marcado.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          ...tramos.map((t) {
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _tramosSel.contains(t.id),
              activeColor: AppTheme.primary,
              title: Text(t.nombre),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _tramosSel.add(t.id);
                } else {
                  _tramosSel.remove(t.id);
                }
              }),
            );
          }),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activo'),
          value: _activo,
          activeThumbColor: AppTheme.primary,
          onChanged: (v) => setState(() => _activo = v),
        ),
      ],
    );
  }
}

/// Andamiaje común de los bottom sheets: título, contenido y botón guardar.
class _SheetScaffold extends StatelessWidget {
  final String titulo;
  final bool saving;
  final VoidCallback onGuardar;
  final List<Widget> children;
  const _SheetScaffold({
    required this.titulo,
    required this.saving,
    required this.onGuardar,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saving ? null : onGuardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Guardar', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
