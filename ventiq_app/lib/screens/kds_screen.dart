import 'dart:async';

import 'package:flutter/material.dart';

import '../models/comanda.dart';
import '../services/comanda_service.dart';
import '../widgets/comanda_card.dart';

/// Pantalla KDS (Kitchen Display System) para el jefe de cocina y cocineros.
///
/// Diseño tomado de los KDS de la industria (Lightspeed, Toast): tarjetas en
/// cuadrícula, código de colores por estado, filtro por estación y refresco
/// automático. Prioridades del oficio, no de la app:
///
///   * FIFO visible: la comanda más vieja primero, con minutos de espera.
///   * Un toque por acción. Sin diálogos de confirmación en el flujo normal:
///     en cocina no hay tiempo, y un marcado equivocado se deshace con otro
///     toque (el backend permite retroceder un paso).
///   * Texto grande. Se lee a un metro de distancia, con las manos ocupadas.
///
/// El alcance lo decide el servidor: `fn_listar_comandas_cocina` devuelve solo
/// las cocinas del usuario autenticado.
class KdsScreen extends StatefulWidget {
  const KdsScreen({super.key});

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> with WidgetsBindingObserver {
  final ComandaService _service = ComandaService();

  List<CocinaAsignada> _cocinas = const [];
  List<Comanda> _comandas = const [];

  /// `null` = todas las cocinas del usuario.
  int? _cocinaFiltro;

  /// Mostrar el histórico (entregadas/canceladas) en lugar de lo vivo.
  bool _verHistorico = false;

  bool _loading = true;
  bool _refrescando = false;
  String? _error;
  DateTime? _ultimaCarga;

  Timer? _polling;

  /// Ids de items con una acción en vuelo, para no dispararla dos veces con un
  /// doble toque accidental.
  final Set<int> _enVuelo = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarTodo();
    _iniciarPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _polling?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // La tablet de cocina se apaga y enciende constantemente. Al volver hay que
    // recargar de inmediato: mostrar comandas de hace media hora es peor que no
    // mostrar nada.
    if (state == AppLifecycleState.resumed) {
      _cargar(silencioso: true);
      _iniciarPolling();
    } else if (state == AppLifecycleState.paused) {
      _polling?.cancel();
    }
  }

  void _iniciarPolling() {
    _polling?.cancel();
    // 15 s: la mitad que en mesas_screen. La cocina necesita ver el pedido
    // nuevo cuanto antes; medio minuto de retraso se nota en el servicio.
    _polling = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_verHistorico) _cargar(silencioso: true);
    });
  }

  Future<void> _cargarTodo() async {
    setState(() => _loading = true);
    try {
      _cocinas = await _service.listarMisCocinas();
      await _cargar(silencioso: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _loading = true);
    if (silencioso) setState(() => _refrescando = true);

    try {
      final lista = await _service.listarComandas(
        idCocina: _cocinaFiltro,
        estados: _verHistorico ? EstadoComanda.cerrados : EstadoComanda.vivos,
        limite: _verHistorico ? 50 : 100,
      );
      if (!mounted) return;
      setState(() {
        _comandas = lista;
        _error = null;
        _ultimaCarga = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refrescando = false;
        });
      }
    }
  }

  // ── Acciones ───────────────────────────────────────────────────────────

  Future<void> _avanzarItem(ComandaItem item) async {
    final siguiente = item.siguienteEstado;
    if (siguiente == null || _enVuelo.contains(item.id)) return;

    setState(() => _enVuelo.add(item.id));
    try {
      final msg = await _service.cambiarEstadoItem(
        idItem: item.id,
        nuevoEstado: siguiente,
      );
      await _cargar(silencioso: true);
      _aviso(msg);
    } on ComandaException catch (e) {
      if (e.requiereRecarga) await _cargar(silencioso: true);
      _aviso(e.mensaje, error: true);
    } catch (e) {
      _aviso('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _enVuelo.remove(item.id));
    }
  }

  Future<void> _cambiarComanda(Comanda comanda, int estado) async {
    try {
      final msg = await _service.cambiarEstadoComanda(
        idComanda: comanda.id,
        nuevoEstado: estado,
      );
      await _cargar(silencioso: true);
      _aviso(msg);
    } on ComandaException catch (e) {
      if (e.requiereRecarga) await _cargar(silencioso: true);
      _aviso(e.mensaje, error: true);
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
  }

  /// Cancelar sí pide confirmación: es la única acción que no se puede deshacer
  /// (el estado 5 es terminal) y además deja el pedido sin preparar.
  Future<void> _cancelarItem(ComandaItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar este plato?'),
        content: Text(
          '${item.cantidadTexto}× ${item.denominacion}\n\n'
          'No se va a preparar. El ajuste de inventario lo decide quien maneja '
          'la nota, desde la cuenta de la mesa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final msg = await _service.cambiarEstadoItem(
        idItem: item.id,
        nuevoEstado: EstadoComanda.cancelado,
      );
      await _cargar(silencioso: true);
      _aviso(msg);
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
  }

  void _aviso(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        duration: Duration(seconds: error ? 4 : 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Cocina',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(
              _subtitulo(),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // Alternar vivo / histórico. En el histórico se apaga el polling:
          // no tiene sentido refrescar algo que ya no cambia.
          IconButton(
            tooltip: _verHistorico ? 'Ver activas' : 'Ver historial',
            icon: Icon(_verHistorico ? Icons.pending_actions : Icons.history),
            onPressed: () {
              setState(() => _verHistorico = !_verHistorico);
              _cargar();
              if (!_verHistorico) _iniciarPolling();
            },
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: _refrescando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: _refrescando ? null : () => _cargar(),
          ),
        ],
        bottom: _cocinas.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: _filtroCocinas(),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () => _cargar(silencioso: true),
        child: _cuerpo(),
      ),
    );
  }

  String _subtitulo() {
    if (_verHistorico) return 'Historial';
    final n = _comandas.length;
    final base = n == 0
        ? 'Sin comandas activas'
        : n == 1
            ? '1 comanda activa'
            : '$n comandas activas';
    if (_ultimaCarga == null) return base;
    final h = _ultimaCarga!;
    final hh = h.hour.toString().padLeft(2, '0');
    final mm = h.minute.toString().padLeft(2, '0');
    final ss = h.second.toString().padLeft(2, '0');
    return '$base · $hh:$mm:$ss';
  }

  /// Filtro por estación. Solo aparece si el usuario tiene más de una cocina
  /// (un jefe de una sola estación no necesita elegir).
  Widget _filtroCocinas() {
    return Container(
      height: 48,
      color: const Color(0xFF357ABD),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          _chipCocina('Todas', null),
          for (final c in _cocinas)
            _chipCocina(c.denominacion, c.idCocina, activa: c.activa),
        ],
      ),
    );
  }

  Widget _chipCocina(String texto, int? id, {bool activa = true}) {
    final sel = _cocinaFiltro == id;
    // Cuenta de comandas por estación, para saber dónde está la carga sin
    // tener que filtrar.
    final n = id == null
        ? _comandas.length
        : _comandas.where((c) => c.idCocina == id).length;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: sel,
        onSelected: (_) {
          setState(() => _cocinaFiltro = id);
          _cargar();
        },
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!activa) ...[
              const Icon(Icons.pause_circle_outline, size: 13),
              const SizedBox(width: 3),
            ],
            Text(texto),
            if (n > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF4A90E2) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$n',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: sel ? Colors.white : const Color(0xFF4A90E2),
                  ),
                ),
              ),
            ],
          ],
        ),
        selectedColor: Colors.white,
        backgroundColor: const Color(0xFF2E6DA8),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: sel ? const Color(0xFF1F2937) : Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide.none,
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _mensaje(
        icono: Icons.cloud_off,
        titulo: 'No se pudieron cargar las comandas',
        detalle: _error!,
        accion: 'Reintentar',
        onAccion: _cargarTodo,
      );
    }

    // Sin cocinas asignadas no es un error: es que falta configurarlo. El
    // mensaje tiene que decir QUIÉN lo resuelve, porque el cocinero no puede.
    if (_cocinas.isEmpty) {
      return _mensaje(
        icono: Icons.no_meals_outlined,
        titulo: 'No tienes cocinas asignadas',
        detalle: 'Pide al gerente que te asigne a una cocina desde '
            'Gestión de cocinas en la app de administración.',
      );
    }

    if (_comandas.isEmpty) {
      return _mensaje(
        icono: _verHistorico
            ? Icons.history_toggle_off
            : Icons.check_circle_outline,
        titulo: _verHistorico
            ? 'Sin comandas en el historial'
            : 'Todo al día',
        detalle: _verHistorico
            ? 'Aquí aparecen las comandas entregadas y canceladas.'
            : 'No hay platos pendientes de preparar.',
      );
    }

    // Cuadrícula responsive: en una tablet de cocina en horizontal entran 3–4
    // tarjetas; en un móvil, una sola columna.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = switch (constraints.maxWidth) {
          >= 1400 => 4,
          >= 1000 => 3,
          >= 640 => 2,
          _ => 1,
        };

        return GridView.builder(
          padding: const EdgeInsets.all(10),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnas,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            // Alto generoso: las tarjetas llevan varios platos y sus notas.
            mainAxisExtent: 320,
          ),
          itemCount: _comandas.length,
          itemBuilder: (context, i) {
            final c = _comandas[i];
            return ComandaCard(
              comanda: c,
              itemsEnVuelo: _enVuelo,
              onAvanzarItem: _avanzarItem,
              onCancelarItem: _cancelarItem,
              onCambiarComanda: _cambiarComanda,
            );
          },
        );
      },
    );
  }

  Widget _mensaje({
    required IconData icono,
    required String titulo,
    String? detalle,
    String? accion,
    VoidCallback? onAccion,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Icon(icono, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
          ),
        ),
        if (detalle != null) ...[
          const SizedBox(height: 8),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
        if (accion != null && onAccion != null) ...[
          const SizedBox(height: 20),
          Center(
            child: FilledButton.icon(
              onPressed: onAccion,
              icon: const Icon(Icons.refresh),
              label: Text(accion),
            ),
          ),
        ],
      ],
    );
  }
}
