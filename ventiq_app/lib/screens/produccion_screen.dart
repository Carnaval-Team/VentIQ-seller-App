import 'dart:async';

import 'package:flutter/material.dart';

import '../models/comanda.dart';
import '../models/tanda.dart';
import '../services/comanda_service.dart';
import '../widgets/tanda_widgets.dart';

/// Pantalla de produccion por tandas, para el jefe de cocina.
///
/// Responde dos preguntas del oficio:
///
///   1. "¿De que me estoy quedando sin porciones?"  -> pestaña Platos
///   2. "¿Que lotes tengo abiertos y cuanto me costaron?" -> pestaña Lotes
///
/// Producir, cerrar y anular exigen ser JEFE (lo valida el backend). Un cocinero
/// entra y lee, pero los botones de accion no le aparecen.
class ProduccionScreen extends StatefulWidget {
  const ProduccionScreen({super.key});

  @override
  State<ProduccionScreen> createState() => _ProduccionScreenState();
}

class _ProduccionScreenState extends State<ProduccionScreen>
    with SingleTickerProviderStateMixin {
  final ComandaService _service = ComandaService();

  late final TabController _tabs;

  List<CocinaAsignada> _cocinas = const [];
  CocinaAsignada? _cocina;

  List<PlatoPorTanda> _platos = const [];
  List<Tanda> _tandas = const [];

  bool _verHistorico = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargarTodo();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Solo un jefe puede producir. Gerente y supervisor tambien llegan aqui con
  /// es_jefe = true desde fn_cocinas_del_usuario.
  bool get _puedeProducir => _cocina?.esJefe ?? false;

  Future<void> _cargarTodo() async {
    setState(() => _loading = true);
    try {
      final cocinas = await _service.listarMisCocinas();
      if (!mounted) return;
      setState(() {
        _cocinas = cocinas;
        // Se elige la primera cocina donde el usuario sea jefe: es la que va a
        // querer operar. Si solo es cocinero, la primera que tenga.
        _cocina = cocinas.isEmpty
            ? null
            : cocinas.firstWhere((c) => c.esJefe, orElse: () => cocinas.first);
      });
      await _cargar(silencioso: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargar({bool silencioso = false}) async {
    final c = _cocina;
    if (c == null) {
      setState(() => _loading = false);
      return;
    }
    if (!silencioso) setState(() => _loading = true);

    try {
      // Las dos listas en paralelo: son independientes y la pantalla las
      // necesita juntas para no parpadear al cambiar de pestaña.
      final resultados = await Future.wait([
        _service.listarPlatosPorTanda(c.idCocina),
        _service.listarTandas(
          idCocina: c.idCocina,
          estados: _verHistorico ? EstadoTanda.cerrados : EstadoTanda.vivos,
          dias: _verHistorico ? 7 : 2,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _platos = resultados[0] as List<PlatoPorTanda>;
        _tandas = resultados[1] as List<Tanda>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Acciones ───────────────────────────────────────────────────────────

  Future<void> _producir(PlatoPorTanda plato) async {
    final c = _cocina;
    if (c == null || _busy) return;

    final datos = await showDialog<({double porciones, String? notas})>(
      context: context,
      builder: (ctx) => ProducirTandaDialog(plato: plato),
    );
    if (datos == null) return;

    setState(() => _busy = true);
    try {
      final res = await _service.producirTanda(
        idCocina: c.idCocina,
        idProducto: plato.idProducto,
        porciones: datos.porciones,
        notas: datos.notas,
      );
      await _cargar(silencioso: true);
      if (!mounted) return;
      _aviso(res.mensaje);
    } on TandaException catch (e) {
      if (!mounted) return;
      // Falta de materia prima: se muestra el detalle, no un texto generico.
      // El jefe necesita saber QUE pedir al almacen.
      if (e.esFaltaDeStock && e.faltantes.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => FaltantesDialog(error: e),
        );
      } else {
        _aviso('${e.titulo}: ${e.mensaje}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cerrar(Tanda tanda) async {
    if (_busy) return;

    final datos = await showDialog<({double descartadas, String? motivo})>(
      context: context,
      builder: (ctx) => CerrarTandaDialog(tanda: tanda),
    );
    if (datos == null) return;

    setState(() => _busy = true);
    try {
      final res = await _service.cerrarTanda(
        idTanda: tanda.id,
        descartadas: datos.descartadas,
        motivo: datos.motivo,
      );
      await _cargar(silencioso: true);
      if (!mounted) return;

      // El costo por porcion SERVIDA es el dato que importa al cerrar: incluye
      // lo que se boto. Se muestra si el servidor lo calculo.
      final costo = res['costo_por_servida'];
      final msg = res['message'] as String? ?? 'Tanda cerrada';
      _aviso(costo == null ? msg : '$msg · Costo real por porcion: $costo');
    } on TandaException catch (e) {
      _aviso('${e.titulo}: ${e.mensaje}', error: true);
    } catch (e) {
      _aviso('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _anular(Tanda tanda) async {
    if (_busy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Anular esta produccion?'),
        content: Text(
          'Se retiran ${tanda.num2(tanda.producidas)} porciones de '
          '${tanda.producto} y se devuelve la materia prima al almacen.\n\n'
          'Solo funciona si no ha salido ninguna porcion. Si ya se sirvio algo, '
          'cierra la tanda declarando la merma.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Si, anular'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final res = await _service.anularTanda(idTanda: tanda.id);
      await _cargar(silencioso: true);
      if (!mounted) return;
      _aviso(res['message'] as String? ?? 'Tanda anulada');
    } on TandaException catch (e) {
      if (!mounted) return;
      // Ya se sirvio: el camino correcto es cerrar con merma. Se ofrece.
      if (e.yaConsumida) {
        final cerrar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(e.titulo),
            content: Text('${e.mensaje}\n\n¿Cerrar la tanda declarando merma?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cerrar con merma'),
              ),
            ],
          ),
        );
        if (cerrar == true && mounted) await _cerrar(tanda);
      } else {
        _aviso('${e.titulo}: ${e.mensaje}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _aviso(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        duration: Duration(seconds: error ? 5 : 3),
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
            const Text('Produccion',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(
              _subtitulo(),
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _verHistorico ? 'Ver lotes activos' : 'Ver historial',
            icon: Icon(_verHistorico ? Icons.inventory_2 : Icons.history),
            onPressed: () {
              setState(() => _verHistorico = !_verHistorico);
              _cargar();
            },
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : () => _cargar(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: 'Platos (${_platos.length})'),
            Tab(text: 'Lotes (${_tandas.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Selector de cocina. Solo si tiene mas de una: un jefe de una sola
          // estacion no necesita elegir.
          if (_cocinas.length > 1) _selectorCocina(),
          if (_cocina != null && !_puedeProducir) _avisoSoloLectura(),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  String _subtitulo() {
    if (_cocina == null) return 'Sin cocina';
    final rol = _puedeProducir ? 'Jefe' : 'Solo lectura';
    return '${_cocina!.denominacion} · $rol'
        '${_verHistorico ? ' · Historial' : ''}';
  }

  Widget _selectorCocina() {
    return Container(
      color: const Color(0xFF357ABD),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final c in _cocinas)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  selected: _cocina?.idCocina == c.idCocina,
                  onSelected: (_) {
                    setState(() => _cocina = c);
                    _cargar();
                  },
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Marcar donde es jefe: es donde puede producir.
                      if (c.esJefe) ...[
                        const Icon(Icons.star, size: 12),
                        const SizedBox(width: 3),
                      ],
                      Text(c.denominacion),
                    ],
                  ),
                  selectedColor: Colors.white,
                  backgroundColor: const Color(0xFF2E6DA8),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _cocina?.idCocina == c.idCocina
                        ? const Color(0xFF1F2937)
                        : Colors.white,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide.none,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Un cocinero puede consultar el estado pero no producir. Decirlo evita que
  /// crea que la app esta rota cuando no ve los botones.
  Widget _avisoSoloLectura() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined,
              size: 16, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Solo consulta: producir y cerrar lotes lo hace el jefe de cocina.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return _mensaje(
        icono: Icons.cloud_off,
        titulo: 'No se pudo cargar la produccion',
        detalle: _error!,
        accion: 'Reintentar',
        onAccion: _cargarTodo,
      );
    }

    if (_cocinas.isEmpty) {
      return _mensaje(
        icono: Icons.no_meals_outlined,
        titulo: 'No tienes cocinas asignadas',
        detalle: 'Pide al gerente que te asigne a una cocina desde '
            'Gestion de cocinas en la app de administracion.',
      );
    }

    return TabBarView(
      controller: _tabs,
      children: [_tabPlatos(), _tabLotes()],
    );
  }

  Widget _tabPlatos() {
    if (_platos.isEmpty) {
      return _mensaje(
        icono: Icons.ramen_dining_outlined,
        titulo: 'Sin platos por tanda',
        detalle: 'Esta cocina no tiene platos configurados como "por tanda". '
            'Se configuran en la gestion de platos del administrador.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _cargar(silencioso: true),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final p in _platos)
            PlatoTandaCard(
              plato: p,
              puedeProducir: _puedeProducir && !_busy,
              onProducir: () => _producir(p),
            ),
        ],
      ),
    );
  }

  Widget _tabLotes() {
    if (_tandas.isEmpty) {
      return _mensaje(
        icono: _verHistorico ? Icons.history_toggle_off : Icons.inventory_2_outlined,
        titulo: _verHistorico ? 'Sin lotes en el historial' : 'Sin lotes abiertos',
        detalle: _verHistorico
            ? 'Aqui aparecen los lotes cerrados y anulados de los ultimos 7 dias.'
            : 'Produce una tanda desde la pestaña Platos.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _cargar(silencioso: true),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final t in _tandas)
            TandaCard(
              tanda: t,
              puedeOperar: _puedeProducir && !_busy,
              onCerrar: () => _cerrar(t),
              onAnular: () => _anular(t),
            ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      children: [
        Icon(icono, size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 14),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
          ),
        ),
        if (detalle != null) ...[
          const SizedBox(height: 8),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
        if (accion != null && onAccion != null) ...[
          const SizedBox(height: 18),
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
